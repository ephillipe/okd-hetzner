Set environment variables:
```
export HCLOUD_TOKEN="abc"
export BASE_DOMAIN="example.com"
```

Requirements:
- jq
- hcloud
- podman
- packer
- terraform

Tests:
```
    podman run \
        -v ./packer:/workspace:Z \
        -w /workspace \
        -e PACKER_PLUGIN_PATH=/workspace/.packer.d/plugins \
        docker.io/hashicorp/packer:light-1.8.0 \
        build . -var 'fedora_coreos_version=${fedora_coreos_version}'
```