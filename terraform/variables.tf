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
}

variable "num_okd_control_plane" {
  type = number
}

# Server image
variable "fedora_coreos_image_id" {
  type = string
}

# Server types
variable "bootstrap_server_type" {
  type    = string
  default = "cpx41"
}

variable "control_plane_server_type" {
  type    = string
  default = "cpx41"
}

variable "worker_server_type" {
  type    = string
  default = "cpx41"
}

# Server locations
variable "bootstrap_server_location" {
  type    = string
  default = "nbg1"
}

variable "control_plane_server_location" {
  type    = list(string)
  default = ["nbg1", "hel1", "fsn1"]
}

variable "worker_server_location" {
  type    = string
  default = "nbg1"
}

# Private network and subnetwork
variable "okd_private_network_ip_range" {
  type    = string
  default = "10.0.0.0/8"
}

variable "okd_private_subnetwork_zone" {
  type    = string
  default = "eu-central"
}

variable "okd_private_subnetwork_ip_range" {
  type    = string
  default = "10.0.0.0/16"
}

# Load balancer
variable "load_balancer_type" {
  type    = string
  default = "lb11"
}

variable "load_balancer_location" {
  type    = string
  default = "eu-central"
}

# DNS
variable "cloudflare_dns_zone_id" {
  type = string
}
