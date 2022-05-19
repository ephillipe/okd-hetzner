terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "3.15.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.33.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }
  }
}
