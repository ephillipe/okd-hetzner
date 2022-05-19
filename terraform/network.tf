resource "hcloud_network" "okd" {
  name     = var.cluster_name
  ip_range = var.okd_private_network_ip_range
}

resource "hcloud_network_subnet" "okd" {
  type         = "cloud"
  network_id   = hcloud_network.okd.id
  network_zone = var.okd_private_subnetwork_zone
  ip_range     = var.okd_private_subnetwork_ip_range
}