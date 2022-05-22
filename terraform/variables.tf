# Cluster name and domain
variable "cluster_name" {
  type = string
}

variable "okd_domain" {
  type = string
}

# Hetzner SSH keys
variable "hetzner_ssh_keys" {
  type    = list(string)
  default = ["default"]
}

# Number of workers and control planes
variable "num_okd_workers" {
  type = number

  validation {
    condition     = var.num_okd_workers >= 2
    error_message = "Number of worker servers must be 2 or higher."
  }
}

variable "num_okd_control_plane" {
  type = number

  validation {
    condition     = var.num_okd_control_plane == 3 || var.num_okd_control_plane == 5
    error_message = "Number of control plane servers must be 3 or 5."
  }
}

# Server image
variable "fedora_coreos_image_id" {
  type = string
}

# Server types
variable "loadbalancer_server_type" {
  type    = string
  default = "cpx11"
}

variable "bootstrap_server_type" {
  type    = string
  default = "cx41"
}

variable "control_plane_server_type" {
  type    = string
  default = "cx41"
}

variable "worker_server_type" {
  type    = string
  default = "cpx41"
}

# Server locations
variable "loadbalancer_server_location" {
  type    = string
  default = "nbg1"
}

variable "bootstrap_server_location" {
  type    = string
  default = "nbg1"
}

variable "control_plane_server_location" {
  type    = list(string)
  default = ["nbg1", "hel1", "fsn1", "nbg1", "hel1"]
}

variable "worker_server_location" {
  type    = string
  default = "nbg1"
}

# DNS
variable "cloudflare_dns_zone_id" {
  type = string
}
