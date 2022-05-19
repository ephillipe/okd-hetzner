#!/bin/bash
set -eu -o pipefail

# Load the environment variables that control the behavior of this
# script.
source ./config

# Returns a string representing the image ID for a given label.
# Returns empty string if none exists
get_fedora_coreos_image_id() {
    hcloud image list -o json | jq -r ".[] | select(.labels.os == \"fedora-coreos\").id"
}

create_image_if_not_exists() {
    echo -e "\nCreating custom Fedora CoreOS ${LATEST_FEDORA_COREOS_VERSION} image.\n"

    # if image exists, return
    if [ "$(get_fedora_coreos_image_id)" != "" ]; then
        echo "Image with name already exists. Skipping image creation."
        return 0
    fi

    # Create the image with packer
    packer build ./resources/packer-fedora-coreos.hcl \
        -var 'LATEST_FEDORA_COREOS_VERSION=${LATEST_FEDORA_COREOS_VERSION}' >/dev/null

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

generate_manifests() {
    echo -e "\nGenerating manifests/configs for install.\n"

    # Clear out old generated files
    rm -rf ./generated-files/ && mkdir ./generated-files

    # Copy install-config in place (remove comments) and replace tokens
    # in the template with the actual values we want to use.
    grep -v '^#' resources/install-config.yaml.in > generated-files/install-config.yaml
    for token in BASEDOMAIN      \
                 CLUSTERNAME     \
                 NUM_OKD_WORKERS \
                 NUM_OKD_CONTROL_PLANE \
                 SSH_KEY;
    do
        sed -i "s/$token/${!token}/" generated-files/install-config.yaml
    done

    # Generate manifests and create the ignition configs from that.
    openshift-install create manifests --dir=generated-files
    openshift-install create ignition-configs --dir=generated-files

    # Create a pod and serve the bootstrap ignition file via Cloudflare tunnels 
    # so we can pull from it on startup. It's too large to fit in user-data.
    sum=$(sha512sum ./generated-files/bootstrap.ign | cut -d ' ' -f 1)
    podman pod create -n ignition-server
    podman run -it -d --pod ignition-server --name ignition-server-nginx \
        -v ./generated-files/bootstrap.ign:/usr/share/nginx/html/bootstrap.ign:Z \
        docker.io/library/nginx:1.21.6-alpine
    podman run -it -d --pod ignition-server --name ignition-server-cloudflared \
        docker.io/cloudflare/cloudflared:2022.5.1 \
        tunnel --no-autoupdate --url http://localhost:80

    # Get the URL from cloudflared container logs
    url=$(podman logs ignition-server-cloudflared | grep -Eo "https://[a-zA-Z0-9./?=_%:-]*trycloudflare.com")/bootstrap.ign

    # backslash escape the '&' chars in the URL since '&' is interpreted by sed
    escapedurl=${url//&/\\&}

    # Add tweaks to the bootstrap ignition and a pointer to the remote bootstrap
    cat resources/butane-bootstrap.yaml | \
        sed "s|SHA512|sha512-${sum}|" | \
        sed "s|SOURCE_URL|${escapedurl}|" | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        -o ./generated-files/bootstrap-processed.ign

    # Add tweaks to the control plane config
    cat resources/butane-control-plane.yaml | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        -d ./ -o ./generated-files/control-plane-processed.ign

    # Add tweaks to the worker config
    cat resources/butane-worker.yaml | \
        podman run --interactive --rm quay.io/coreos/butane:v0.14.0 \
        -d ./ -o ./generated-files/worker-processed.ign
}

# returns if we have any worker nodes or not to create
have_workers() {
    if [ $NUM_OKD_WORKERS -gt 0 ]; then
        return 0
    else
        return 1
    fi
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

create_nodes() {
    echo -e "\nCreating node.\n"

    local common_options=''
    common_options+="--image $(get_fedora_coreos_image_id) "
    common_options+="--network $(get_private_network_id) "
    common_options+="--ssh-key $NODE_SSH_KEYPAIR "
    common_options+="--label $ALL_NODES_LABEL "

    # Create bootstrap node
    hcloud server create $common_options \
        --name "okd-bootstrap" \
        --label "${CONTROL_PLANE_NODE_LABEL}" \
        --location "$BOOTSTRAP_NODE_LOCATION" \
        --type "$BOOTSTRAP_NODE_TYPE" \
        --user-data-from-file generated-files/bootstrap-processed.ign >/dev/null

    # Create control plane nodes
    for num in $(control_plane_num_sequence); do
        hcloud server create $common_options \
            --name "okd-control-${num}" \
            --label "${CONTROL_PLANE_NODE_LABEL}" \
            --location "${CONTROL_PLANE_NODE_LOCATION[@]}" \
            --type "$CONTROL_PLANE_NODE_TYPE" \
            --user-data-from-file generated-files/control-plane-processed.ign >/dev/null
    done

    # Create worker nodes
    if have_workers; then
        for num in $(worker_num_sequence); do
            hcloud server create $common_options \
                --name "okd-worker-${num}" \
                --label "${WORKER_NODE_LABEL}" \
                --location "$WORKER_NODE_LOCATION" \
                --type "$WORKER_NODE_TYPE" \
                --user-data-from-file ./generated-files/worker-processed.ign >/dev/null
        done
    fi
}

create_load_balancer() {
    echo -e "\nCreating load-balancer.\n"

    # Create a load balancer that passes through port 80 443 6443 22623 traffic.
    # to all nodes tagged as control plane nodes.
    hcloud load-balancer create \
        --name $DOMAIN \
        --network-zone $LOAD_BALANCER_LOCATION \
        --type $LOAD_BALANCER_TYPE \
        --algorithm-type 'round_robin' \
        --label $CONTROL_PLANE_NODE_LABEL >/dev/null

    # Attach load balancer to network
    hcloud load-balancer attach-to-network $(get_load_balancer_id) \
        --network $(get_private_network_id)

    # Add services and health checks to load balancer
    for port in 80 443 6443 22623; do
        hcloud load-balancer add-service $(get_load_balancer_id) \
            --destination-port ${port} \
            --listen-port ${port} \
            --protocol 'tcp' >/dev/null

        hcloud load-balancer update-service $(get_load_balancer_id) \
            --health-check-protocol 'tcp' \
            --health-check-port ${port} \
            --health-check-interval 10s \
            --health-check-timeout 10s \
            --health-check-retries 3 \
            --listen-port ${port} >/dev/null
    done

    # Add targets to load balancer
    hcloud load-balancer add-target $(get_load_balancer_id) \
        --label-selector $CONTROL_PLANE_NODE_LABEL >/dev/null

    # wait for load balancer to come up
    ip='null'
    while [ "${ip}" == 'null' ]; do
        echo "Waiting for load balancer to come up..."
        sleep 5
        ip=$(get_load_balancer_ip)
    done
}

get_load_balancer_id() {
    hcloud load-balancer list -o json | \
        jq -r ".[] | select(.name == \"${DOMAIN}\").id"
}

get_load_balancer_ip() {
    hcloud load-balancer list -o json | \
        jq -r ".[] | select(.name == \"${DOMAIN}\").public_net.ipv4.ip"
}

create_firewall() {
    echo -e "\nCreating firewall.\n"

    # Create firewall
    hcloud firewall create \
        --name $DOMAIN \
        --label $ALL_NODES_LABEL >/dev/null

    # Allow anything from our private network and all node to node traffic
    # even if it comes from a public interface
    iprange=$(get_okd_private_network_ip_range)

    for protocol in 'udp' 'tcp' 'icmp'; do
        hcloud firewall add-rule $(get_firewall_id) \
            --description 'Internal inbound traffic - ${protocol}' \
            --protocol ${protocol} \
            --direction 'in' \
            --source-ips $iprange >/dev/null
    done

    # Allow all outbound traffic
    for protocol in 'udp' 'tcp'; do
        hcloud firewall add-rule $(get_firewall_id) \
            --description 'Internal outbound traffic - ${protocol}' \
            --protocol ${protocol} \
            --direction 'out' \
            --destination-ips '["0.0.0.0", "::/0"]' \
            --port '1-65535' >/dev/null
    done

    hcloud firewall add-rule $(get_firewall_id) \
        --description 'Internal outbound traffic - icmp' \
        --protocol 'icmp' \
        --direction 'out' \
        --destination-ips '["0.0.0.0/0", "::/0"]' >/dev/null

    # Allow tcp 22 80 443 6443 22623 from the public
    for port in 22 80 443 6443 22623; do
        hcloud firewall add-rule $(get_firewall_id) \
            --description 'External inbound traffic - ${port}' \
            --protocol 'tcp' \
            --direction 'in' \
            --source-ips '["0.0.0.0/0", "::/0"]' \
            --port ${port} >/dev/null
    done
}

get_firewall_id() {
    hcloud firewall list -o json | \
        jq -r ".[] | select(.name == \"${DOMAIN}\").id"
}

create_private_network() {
    echo -e "\nCreating private_network for private traffic.\n"
    hcloud network create \
        --name $DOMAIN \
        --ip-range $okd_private_network_ip_range \
        --label $ALL_NODES_LABEL >/dev/null
}

get_private_network_id() {
    hcloud network list -o json | \
        jq -r ".[] | select(.name == \"${DOMAIN}\").id"
}

get_okd_private_network_ip_range() {
    hcloud network list -o json | \
        jq -r ".[] | select(.name == \"${DOMAIN}\").ip_range"
}

