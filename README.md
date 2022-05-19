Set environment variables:
```
export HCLOUD_TOKEN="abc"
```

Requirements:
jq
hcloud
podman




terraform plan \
    -var fedora_coreos_image_id=$(get_fedora_coreos_image_id) \
    -var cloudflare_dns_zone_id=