Based on the great projects: [slauger/hcloud-okd4](https://github.com/slauger/hcloud-okd4) and [dustymabe/digitalocean-okd-install](https://github.com/dustymabe/digitalocean-okd-install).

## Architecture

The deployment defaults to a 5 node cluster with 2 load balancers:

- 3x Master servers (CPX41)
- 2x Worker servers (CPX41)
- 2x Load balancer (LB11)
  - 1 for control plane
  - 1 for workers
- 1x Bootstrap server (CPX41)
  - Deleted after cluster is bootstrapped

## Usage

### Host requirements:
- Linux 64-bit
- Applications:
  - hcloud
  - jq
  - podman
  - packer
  - terraform

### Set environment variables:
```
# Hetzner Cloud API token
export HCLOUD_TOKEN=""

# Base domain. eg. example.com
export BASE_DOMAIN=""

# Cloudflare zone ID
export CLOUDFLARE_ZONE_ID=""

# Cloudlfare email. eg. user@example.com
export CLOUDFLARE_EMAIL=""

# Cloudflare global API key
export CLOUDFLARE_API_KEY=""

# Cloudflare API token
export CLOUDFLARE_API_TOKEN=""
```

#### How to get Cloudflare API token
1. Access [API tokens page](https://dash.cloudflare.com/profile/api-tokens)
2. Click 'Create token' -> 'Get started (Create Custom Token)'
3. Create token:
   - Name: 'OKD Terraform'
   - Permissions:
     - Zone - DNS - Edit
     - Zone - Page Rules - Edit
   - Zone Resources:
     - Include - Specific zone - ${BASE_DOMAIN}
4. Copy token, as it will not be shown again

### Run the install script:
`okd-install.sh`