#!/bin/bash
set -eu -o pipefail

# Returns a string representing the image ID for a given label.
# Returns empty string if none exists
get_fedora_coreos_image_id() {
    hcloud image list -o json | jq -r ".[] | select(.labels.os == \"fedora-coreos\").id"
}

create_image_if_not_exists() {
    echo -e "\nCreating custom Fedora CoreOS image.\n"

    # if image exists, return
    if [ "$(get_fedora_coreos_image_id)" != "" ]; then
        echo "Image with name already exists. Skipping image creation."
        return 0
    fi

    # Create the image with packer
    fedora_coreos_version=$(curl -s https://builds.coreos.fedoraproject.org/streams/stable.json | jq -r '.architectures.x86_64.artifacts.metal.release')

    packer init ./packer/fedora-coreos.pkr.hcl >/dev/null

    packer build ./packer/fedora-coreos.pkr.hcl \
        -var 'fedora_coreos_version=${fedora_coreos_version}' >/dev/null

    # Wait for the image to finish being created
    for x in {0..100}; do
        if [ "$(get_fedora_coreos_image_id)" != "" ]; then
            return 0 # We're done
        fi
        echo "Waiting for image to finish creation..."
        sleep 10
    done

    echo "Image never finished being created." >&2
    return 1
}

download_okd_tools_if_not_exists() {
    # Download OKD tools if they do not exist
    okd_tools_version=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/openshift/okd/tags | jq -j -r .[0].name)

    ls ./containers | grep openshift-install-linux-${okd_tools_version} || \
    wget -O ./containers/openshift-install-linux-${okd_tools_version}.tar.gz https://github.com/openshift/okd/releases/download/${okd_tools_version}/openshift-install-linux-${okd_tools_version}.tar.gz >/dev/null

    ls ./containers | grep openshift-client-linux-${okd_tools_version} || \
	wget -O ./containers/openshift-client-linux-${okd_tools_version}.tar.gz https://github.com/openshift/okd/releases/download/${okd_tools_version}/openshift-client-linux-${okd_tools_version}.tar.gz >/dev/null
}

build_okd_tools_container_if_not_exists(){
    # Build OKD tools container if it does not exist
    podman image list --format json | grep ${okd_tools_version} || \
    podman build --file ./containers/Containerfile --build-arg okd_tools_version=${okd_tools_version} -t okd-tools:${okd_tools_version} .
}

generate_manifests() {
    echo -e "\nGenerating manifests/configs for install.\n"

    # Clear out old generated files
    rm -rf ./terraform/generated-files/ && mkdir ./terraform/generated-files

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
    podman run -it --hostname okd-tools -v ./:/workspace:Z okd-tools:${okd_tools_version} /bin/bash \
        -c "cd /workspace; openshift-install create manifests --dir=terraform/generated-files; openshift-install create ignition-configs --dir=terraform/generated-files"

    # Create a pod and serve the ignition files via Cloudflare tunnels 
    # so we can pull from it on startup. They're too large to fit in user-data.
    bootstrap_sha256sum=$(sha512sum ./terraform/generated-files/bootstrap.ign | cut -d ' ' -f 1)
    control_plane_sha256sum=$(sha512sum ./terraform/generated-files/master.ign | cut -d ' ' -f 1)
    worker_sha256sum=$(sha512sum ./terraform/generated-files/worker.ign | cut -d ' ' -f 1)

    podman pod create -n ignition-server
    
    podman run -it -d --pod ignition-server --name ignition-server-nginx \
        -v ./terraform/generated-files/bootstrap.ign:/usr/share/nginx/html/bootstrap.ign:Z \
        -v ./terraform/generated-files/master.ign:/usr/share/nginx/html/master.ign:Z \
        -v ./terraform/generated-files/worker.ign:/usr/share/nginx/html/worker.ign:Z \
        docker.io/library/nginx:1.21.6-alpine
    
    podman run -it -d --pod ignition-server --name ignition-server-cloudflared \
        docker.io/cloudflare/cloudflared:2022.5.1 \
        tunnel --no-autoupdate --url http://localhost:80

    # Allow nginx to read ignition file
    chmod 0644 terraform/generated-files/bootstrap.ign
    chmod 0644 terraform/generated-files/master.ign
    chmod 0644 terraform/generated-files/worker.ign

    # Get the ignition URLs from cloudflared container logs
    bootstrap_url=$(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")/bootstrap.ign
    master_url=$(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")/master.ign
    worker_url=$(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")/worker.ign

    # Add tweaks to the bootstrap ignition and a pointer to the remote bootstrap
    cat templates/butane-bootstrap.yaml | \
        sed "s|BOOTSTRAP_SHA512|sha512-${sum}|" | \
        sed "s|BOOTSTRAP_SOURCE_URL|${bootstrap_url}|" | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        > ./terraform/generated-files/bootstrap-processed.ign

    # Add tweaks to the control plane config
    cat templates/butane-control-plane.yaml | \
        sed "s|CONTROL_PLANE_SHA512|sha512-${sum}|" | \
        sed "s|CONTROL_PLANE_SOURCE_URL|${master_url}|" | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        > ./terraform/generated-files/control-plane-processed.ign

    # Add tweaks to the worker config
    cat templates/butane-worker.yaml | \
        sed "s|WORKER_SHA512|sha512-${sum}|" | \
        sed "s|WORKER_SOURCE_URL|${worker_url}|" | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        > ./terraform/generated-files/worker-processed.ign
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
    # Check for required credentials
    for v in SSH_KEY      \
             HCLOUD_TOKEN  \
             CLUSTER_NAME \
             BASE_DOMAIN \
             NUM_OKD_WORKERS \
             NUM_OKD_CONTROL_PLANE; do
        if [[ -z "${!v-}" ]]; then
            echo "You must set environment variable $v" >&2
            return 1
        fi
    done

    # Check for required software
    reqs=(
        jq
        hcloud
        podman
        packer
        terraform
    )
    for req in ${reqs[@]}; do
        check_requirement $req
    done

    # Create Fedora CoreOS image
    create_image_if_not_exists

    # Download OKD tools if they do not exist
    download_okd_tools_if_not_exists

    # Build OKD tools container if it does not exist
    build_okd_tools_container_if_not_exists

    # Generate and serve the ignition configs
    generate_manifests

    # Create the servers, load balancer, private network, firewall and
    # create DNS/RDNS records
    terraform -chdir=./terraform apply \
    -var fedora_coreos_image_id=$(get_fedora_coreos_image_id) \
    -var cloudflare_dns_zone_id=
}