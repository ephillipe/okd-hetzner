Based on the great projects: [slauger/hcloud-okd4](https://github.com/slauger/hcloud-okd4) and [dustymabe/digitalocean-okd-install](https://github.com/dustymabe/digitalocean-okd-install).

## Architecture

The deployment defaults to a 5 node cluster with 1 load balancer:

- 3x Master servers (CX41)
- 2x Worker servers (CPX41)
- 1x Load balancer server (CPX11)
  - Runs HAProxy
  - Also acts as 'lighthouse' for Wireguard cluster
- 1x Bootstrap server (CX41)
  - Deleted after cluster is bootstrapped

Highlights:
- Fedora CoreOS image created with Packer.
- Wireguard cluster with overlay mesh network CIDR of 10.0.0.0/16 created with wesher.
  - Does not use Hetzner's private network.
- Serves ignition files through Cloudflare tunnels.
  - Does not create a server with the sole purpose of serving these files.
- DNS records through Cloudflare.
- Configures Hetzner's cloud volumes driver.

## Usage

### Host requirements:
- Linux 64-bit
- Applications:
  - [Podman](https://podman.io)
  - [Packer](https://www.packer.io/downloads)
  - [Terraform](https://www.terraform.io/downloads)
  - [hcloud cli](https://github.com/hetznercloud/cli)
  - [jq](https://stedolan.github.io/jq/)

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

# Wireguard's pre-shared key
# Can be generated with `openssl rand -base64 32`
export WIREGUARD_CLUSTER_KEY=""

# HAProxy stats password
export HAPROXY_STATS_PASSWORD=""
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