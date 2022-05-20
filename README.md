Set environment variables:
```
export SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export HCLOUD_TOKEN="abc"
export CLUSTER_NAME="okd"
export BASE_DOMAIN="example.com"
export DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export NUM_OKD_WORKERS=2
export NUM_OKD_CONTROL_PLANE=3

# The size of the backing volume for the container registry
export REGISTRY_VOLUME_SIZE='50' # in GiB
```

Requirements:
- jq
- hcloud
- podman
- packer
- terraform