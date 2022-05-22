#!/bin/bash
set -eu -o pipefail

# Set variables
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
CLUSTER_NAME="okd"
OKD_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
NUM_OKD_WORKERS=2
NUM_OKD_CONTROL_PLANE=3
REGISTRY_VOLUME_SIZE='50'

# Set tools and OS versions
OKD_VERSION=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/openshift/okd/tags | jq -j -r .[0].name)
FEDORA_COREOS_VERSION=$(curl -s https://builds.coreos.fedoraproject.org/streams/stable.json | jq -r '.architectures.x86_64.artifacts.qemu.release')
HCLOUD_CSI_VERSION=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/hetznercloud/csi-driver/tags | jq -j -r .[0].name)

# Returns a string representing the image ID for a given label.
# Returns empty string if none exists
get_fedora_coreos_image_id() {
    hcloud image list -o json | jq -r ".[] | select((.labels.os == \"fedora-coreos\") and (.labels.release == \"${FEDORA_COREOS_VERSION}\")).id"
}

get_loadbalancer_server_ip() {
    terraform -chdir=./terraform output -raw loadbalancer_server_ip
}

create_image_if_not_exists() {
    echo -e "\nCreating custom Fedora CoreOS image.\n"

    # if image exists, return
    if [ "$(get_fedora_coreos_image_id)" != "" ]; then
        echo "Image with name already exists. Skipping image creation."
        return 0
    fi

    # Create ignition file
    cat packer/butane-config.yaml | \
        sed "s|OKD_DOMAIN|${OKD_DOMAIN}|" | \
        podman run --interactive --rm quay.io/coreos/butane:release \
        > packer/config.ign

    # Create the image with packer
    packer init packer/fedora-coreos.pkr.hcl &> /dev/null

    packer build \
        -var fedora_coreos_version=${FEDORA_COREOS_VERSION} \
        packer/fedora-coreos.pkr.hcl &> /dev/null
}

download_okd_tools_if_not_exists() {
    echo -e "\nDownloading and installing OKD tools.\n"

    if which oc &> /dev/null; then
        if oc version | grep ${OKD_VERSION} &> /dev/null; then
            echo "Correct OKD tools version already exists. Skipping OKD tools download and installation."
            return 0
        fi
    fi

    # Remove older OKD tools version
    rm -f ~/.local/bin/{openshift-install,oc,kubectl}

    # Download OKD tools
    curl -sSL https://github.com/openshift/okd/releases/download/${OKD_VERSION}/openshift-install-linux-${OKD_VERSION}.tar.gz -o openshift-install-linux-${OKD_VERSION}.tar.gz >/dev/null
    curl -sSL https://github.com/openshift/okd/releases/download/${OKD_VERSION}/openshift-client-linux-${OKD_VERSION}.tar.gz -o openshift-client-linux-${OKD_VERSION}.tar.gz >/dev/null

    # Install OKD tools
    tar -zxf openshift-install-linux-${OKD_VERSION}.tar.gz -C ~/.local/bin/ openshift-install
    tar -zxf openshift-client-linux-${OKD_VERSION}.tar.gz -C ~/.local/bin/ {oc,kubectl}

    # Cleanup tars
    rm -f openshift-install-linux-${OKD_VERSION}.tar.gz
    rm -f openshift-client-linux-${OKD_VERSION}.tar.gz
}

create_loadbalancer_server() {
    echo -e "\nCreating load balancer server.\n"

    cat templates/butane-loadbalancer.yaml | \
        sed "s|SSH_KEY|${SSH_KEY}|" | \
        sed "s|WIREGUARD_CLUSTER_KEY|${WIREGUARD_CLUSTER_KEY}|" | \
        sed "s|OKD_DOMAIN|${OKD_DOMAIN}|" | \
        sed "s|CLUSTER_NAME|${CLUSTER_NAME}|" | \
        sed "s|HAPROXY_STATS_PASSWORD|${HAPROXY_STATS_PASSWORD}|" | \
        podman run --interactive --rm quay.io/coreos/butane:release \
        > terraform/generated-files/loadbalancer-processed.ign

    terraform -chdir=./terraform apply \
        -auto-approve \
        -var cluster_name=${CLUSTER_NAME} \
        -var okd_domain=${OKD_DOMAIN} \
        -var cloudflare_dns_zone_id=${CLOUDFLARE_ZONE_ID} \
        -var num_okd_workers=${NUM_OKD_WORKERS} \
        -var num_okd_control_plane=${NUM_OKD_CONTROL_PLANE} \
        -var fedora_coreos_image_id=$(get_fedora_coreos_image_id) \
        -target hcloud_server.okd_loadbalancer
}

generate_manifests() {
    echo -e "\nGenerating manifests/configs for install.\n"

    # Copy install-config in place (remove comments) and replace tokens
    # in the template with the actual values we want to use.
    grep -v '^#' templates/install-config.yaml > terraform/generated-files/install-config.yaml
    for token in BASE_DOMAIN      \
                 CLUSTER_NAME     \
                 NUM_OKD_WORKERS \
                 NUM_OKD_CONTROL_PLANE \
                 SSH_KEY;
    do
        sed -i "s#$token#${!token}#" terraform/generated-files/install-config.yaml
    done

    # Generate manifests and create the ignition configs from that
    openshift-install create manifests --dir=terraform/generated-files
    openshift-install create ignition-configs --dir=terraform/generated-files

    # Create a pod and serve the ignition files via Cloudflare tunnels 
    # so we can pull from it on startup. They're too large to fit in user-data.
    bootstrap_sha512sum=$(sha512sum terraform/generated-files/bootstrap.ign | cut -d ' ' -f 1)
    control_plane_sha512sum=$(sha512sum terraform/generated-files/master.ign | cut -d ' ' -f 1)
    worker_sha512sum=$(sha512sum terraform/generated-files/worker.ign | cut -d ' ' -f 1)

    echo -e "\nServing ignition files via Cludflare tunnel.\n"
    # Remove ignition-server pod if it's already running
    podman pod rm --force --ignore ignition-server &> /dev/null

    # Create pod
    podman pod create -n ignition-server &> /dev/null
    
    # Pull and run nginx
    podman pull docker.io/library/nginx:stable-alpine &> /dev/null
    podman run -it -d --pod ignition-server --name ignition-server-nginx \
        -v ./terraform/generated-files/bootstrap.ign:/usr/share/nginx/html/bootstrap.ign:Z \
        -v ./terraform/generated-files/master.ign:/usr/share/nginx/html/master.ign:Z \
        -v ./terraform/generated-files/worker.ign:/usr/share/nginx/html/worker.ign:Z \
        docker.io/library/nginx:stable-alpine &> /dev/null
    
    # Pull and run cloudflared
    podman pull docker.io/cloudflare/cloudflared:latest &> /dev/null
    podman run -it -d --pod ignition-server --name ignition-server-cloudflared \
        docker.io/cloudflare/cloudflared:latest \
        tunnel --no-autoupdate --url http://localhost:80 &> /dev/null

    # Allow nginx to read ignition files
    chmod 0644 terraform/generated-files/{bootstrap,master,worker}.ign

    # Wait for Cloudflare tunnel to be available
    for x in {0..100}; do
        if curl -s -o /dev/null -I -w "%{http_code}" $(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")/bootstrap.ign | grep 200 &> /dev/null; then
            break # Tunnel is available
        fi
        echo "Waiting for Cloudflare tunnel to become available..."
        sleep 10
    done

    # Get the ignition domain from cloudflared container logs
    ignition_url=$(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")

    # Add tweaks to the bootstrap ignition and a pointer to the remote bootstrap
    cat templates/butane-bootstrap.yaml | \
        sed "s|BOOTSTRAP_SHA512|${bootstrap_sha512sum}|" | \
        sed "s|BOOTSTRAP_SOURCE_URL|${ignition_url}/bootstrap.ign|" | \
        sed "s|WIREGUARD_CLUSTER_KEY|${WIREGUARD_CLUSTER_KEY}|" | \
        sed "s|LOADBALANCER_SERVER_IP|$(get_loadbalancer_server_ip)|" | \
        podman run --interactive --rm quay.io/coreos/butane:release \
        > terraform/generated-files/bootstrap-processed.ign

    # Add tweaks to the control plane config
    cat templates/butane-control-plane.yaml | \
        sed "s|CONTROL_PLANE_SHA512|${control_plane_sha512sum}|" | \
        sed "s|CONTROL_PLANE_SOURCE_URL|${ignition_url}/master.ign|" | \
        sed "s|WIREGUARD_CLUSTER_KEY|${WIREGUARD_CLUSTER_KEY}|" | \
        sed "s|LOADBALANCER_SERVER_IP|$(get_loadbalancer_server_ip)|" | \
        podman run --interactive --rm quay.io/coreos/butane:release \
        > terraform/generated-files/control-plane-processed.ign

    # Add tweaks to the worker config
    cat templates/butane-worker.yaml | \
        sed "s|WORKER_SHA512|${worker_sha512sum}|" | \
        sed "s|WORKER_SOURCE_URL|${ignition_url}/worker.ign|" | \
        sed "s|WIREGUARD_CLUSTER_KEY|${WIREGUARD_CLUSTER_KEY}|" | \
        sed "s|LOADBALANCER_SERVER_IP|$(get_loadbalancer_server_ip)|" | \
        podman run --interactive --rm quay.io/coreos/butane:release \
        > terraform/generated-files/worker-processed.ign
}

# prints a sequence of numbers to iterate over from 0 to N-1
# for the number of control plane nodes
control_plane_num_sequence() {
    seq 0 $((NUM_OKD_CONTROL_PLANE-1))
}

# prints a sequence of numbers to iterate over from 0 to N-1
# for the number of worker nodes
worker_num_sequence() {
    seq 0 $((NUM_OKD_WORKERS-1))
}

# https://github.com/hetznercloud/csi-driver
configure_hetzner_cloud_volumes_driver() {
    echo -e "\nCreating Hetzner cloud volumes driver.\n"
    # Create the secret that contains the Hetzner token for volume creation
    oc create -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: hcloud
  namespace: kube-system
stringData:
  token: "${HCLOUD_TOKEN}"
EOF

    # Deploy Hetzner's CSI storage provisioner
    oc apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/${HCLOUD_CSI_VERSION}/deploy/kubernetes/hcloud-csi.yml >/dev/null
}

fixup_registry_storage() {
    echo -e "\nFixing the registry storage to use Hetzner volume.\n"
    # Set the registry to be managed.
    # Will cause it to try and create a PVC.
    PATCH='
    spec:
      managementState: Managed
      storage:
        pvc:
          claim:'
    oc patch configs.imageregistry.operator.openshift.io cluster --type merge -p "$PATCH" >/dev/null

    # Update the image-registry deployment to not have a rolling update strategy
    # because it won't work with a RWO backing device.
    # https://docs.openshift.com/container-platform/latest/applications/deployments/deployment-strategies.html
    PATCH='
    spec:
      strategy:
        $retainKeys:
          - type
        type: Recreate'
    sleep 10 # wait a bit for image-registry deployment
    oc patch deployment image-registry -n openshift-image-registry -p "$PATCH" >/dev/null

    # scale the deployment down to 1 desired pod since the volume for
    # the registry can only be attached to one node at a time
    oc scale --replicas=1 deployment/image-registry -n openshift-image-registry >/dev/null

    # Replace the PVC with a RWO one (hcloud volumes only support RWO)
    oc delete pvc/image-registry-storage -n openshift-image-registry >/dev/null
    oc create -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: image-registry-storage
  namespace: openshift-image-registry
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${REGISTRY_VOLUME_SIZE}Gi
  storageClassName: hcloud-volumes
EOF
}

# https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-approve-csrs_installing-bare-metal
wait_and_approve_CSRs() {
    echo -e "\nApprove CSRs if needed.\n"

    # Some handy commands to run manually if needed
    # oc get csr -o json | jq -r '.items[] | select(.spec.username == "system:node:okd-worker-0")'
    # oc get csr -o json | jq -r '.items[] | select(.spec.username == "system:node:okd-worker-0").status'

    # Wait for all requests for worker nodes to come in and approve them
    while true; do
        csrinfo=$(oc get csr -o json)
        echo "Approving all pending CSRs and waiting for remaining requests.."
        echo $csrinfo |                                              \
            jq -r '.items[] | select(.status == {}).metadata.name' | \
            xargs --no-run-if-empty oc adm certificate approve
        sleep 10
        csrinfo=$(oc get csr -o json) # refresh info
        for num in $(worker_num_sequence); do
            # If no CSR for this worker then continue
            exists=$(echo $csrinfo | jq -r ".items[] | select(.spec.username == \"system:node:okd-worker-${num}\").metadata.name")
            if [ ! $exists ]; then
                echo "CSR not yet requested for okd-worker-${num}. Continuing."
                continue 2 # continue the outer loop
            fi
            # If the CSR is not yet approved for this worker then continue
            statusfield=$(echo $csrinfo | jq -r ".items[] | select(.spec.username == \"system:node:okd-worker-${num}\").status")
            if [[ $statusfield == '{}' ]]; then
                echo "CSR not yet approved for okd-worker-${num}. Continuing."
                continue 2 # continue the outer loop
            fi
        done
        break # all expected CSRs have been approved
    done
}

which() {
    (alias; declare -f) | /usr/bin/which --read-alias --read-functions --show-tilde --show-dot $@
}

check_requirement() {
    req=$1
    if ! which $req &>/dev/null; then
        echo "No $req. Can't continue" 1>&2
        return 1
    fi
}

main() {
    # Check for required environment variables
    for v in HCLOUD_TOKEN  \
             BASE_DOMAIN \
             CLOUDFLARE_ZONE_ID \
             CLOUDFLARE_EMAIL \
             CLOUDFLARE_API_KEY \
             CLOUDFLARE_API_TOKEN \
             WIREGUARD_CLUSTER_KEY \
             HAPROXY_STATS_PASSWORD; do
        if [[ -z "${!v-}" ]]; then
            echo "You must set environment variable $v" >&2
            return 1
        fi
    done

    # Check for required software
    reqs=(
        jq
        podman
        packer
        terraform
    )
    for req in ${reqs[@]}; do
        check_requirement $req
    done

    # Clear out old generated files
    rm -rf terraform/generated-files/ && mkdir terraform/generated-files

    # Init Terraform
    echo -e "\nInitializing Terraform.\n"
    terraform -chdir=./terraform init &> /dev/null

    # Create Fedora CoreOS image
    create_image_if_not_exists

    # Download OKD tools if they do not exist
    download_okd_tools_if_not_exists

    # Create load balancer server
    create_loadbalancer_server

    # Generate and serve the ignition configs
    generate_manifests

    # Create the servers, load balancer, firewall and DNS/RDNS records
    echo -e "\nCreating servers, load balancer, firewall and DNS records.\n"

    terraform -chdir=./terraform apply \
        -auto-approve \
        -var cluster_name=${CLUSTER_NAME} \
        -var okd_domain=${OKD_DOMAIN} \
        -var cloudflare_dns_zone_id=${CLOUDFLARE_ZONE_ID} \
        -var num_okd_workers=${NUM_OKD_WORKERS} \
        -var num_okd_control_plane=${NUM_OKD_CONTROL_PLANE} \
        -var fedora_coreos_image_id=$(get_fedora_coreos_image_id)

    # Wait for the bootstrap to complete
    echo -e "\nWaiting for bootstrap to complete.\n"

    openshift-install --dir=terraform/generated-files wait-for bootstrap-complete

    # Remove bootstrap node and nginx/cloudflared containers as bootstrap is complete
    echo -e "\nRemoving bootstrap resources.\n"
    terraform -chdir=./terraform destroy \
        -auto-approve \
        -var cluster_name=${CLUSTER_NAME} \
        -var okd_domain=${OKD_DOMAIN} \
        -var cloudflare_dns_zone_id=${CLOUDFLARE_ZONE_ID} \
        -var num_okd_workers=${NUM_OKD_WORKERS} \
        -var num_okd_control_plane=${NUM_OKD_CONTROL_PLANE} \
        -var fedora_coreos_image_id=$(get_fedora_coreos_image_id) \
        -target hcloud_server.okd_bootstrap \
        -target hcloud_rdns.bootstrap \
        -target cloudflare_record.dns_a_bootstrap

    podman pod rm --force --ignore ignition-server

    # Set the KUBECONFIG so subsequent oc or kubectl commands can run
    export KUBECONFIG=${PWD}/terraform/generated-files/auth/kubeconfig

    # Wait for CSRs to come in and approve them before moving on
    wait_and_approve_CSRs

    # Wait for the install to complete
    echo -e "\nWaiting for install to complete.\n"
    openshift-install --dir=terraform/generated-files wait-for install-complete

    # Configure Hetzner cloud volume driver
    # NOTE: this will store your API token in your cluster
    configure_hetzner_cloud_volumes_driver

    # Configure the registry to use a separate volume created
    # by the Hetzner cloud volume driver
    fixup_registry_storage
}

main $@
if [ $? -ne 0 ]; then
    exit 1
else
    exit 0
fi