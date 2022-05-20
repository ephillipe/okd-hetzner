## Architecture

The deployment defaults to a 5 node cluster:

- 3x Master servers (CPX41)
- 2x Worker servers (CPX41)
- 2x Load balancer (LB11)
- 1x Bootstrap server (CPX41) - deleted after cluster is bootstrapped

## Usage

### Set environment variables:
```
export HCLOUD_TOKEN=""
export BASE_DOMAIN="example.com"
export CLOUDFLARE_ZONE_ID=""
export CLOUDFLARE_EMAIL="user@example.com"
export CLOUDFLARE_API_KEY="cloudflare_global_api_key"
export CLOUDFLARE_API_TOKEN="cloudflare_api_token"
```

#### How to get Cloudflare credentials
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

Requirements:
- jq
- podman
- packer
- terraform