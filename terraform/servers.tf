# Load balancer
data "local_file" "loadbalancer_ignition" {
  filename = "${path.module}/generated-files/loadbalancer-processed.ign"
}

resource "hcloud_server" "okd_loadbalancer" {
  name        = "${var.cluster_name}-loadbalancer"
  server_type = var.loadbalancer_server_type
  image       = var.fedora_coreos_image_id
  location    = var.loadbalancer_server_location
  user_data   = data.local_file.loadbalancer_ignition.content
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "loadbalancer"
  }
}

resource "hcloud_rdns" "loadbalancer" {
  for_each = toset(["api", "api-int"])

  server_id  = hcloud_server.okd_loadbalancer.id
  ip_address = hcloud_server.okd_loadbalancer.ipv4_address
  dns_ptr    = "${each.key}.${var.okd_domain}"
}

# Bootstrap
data "local_file" "bootstrap_ignition" {
  filename = "${path.module}/generated-files/bootstrap-processed.ign"
}

resource "hcloud_server" "okd_bootstrap" {
  name        = "${var.cluster_name}-bootstrap"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = var.bootstrap_server_location
  user_data   = data.local_file.bootstrap_ignition.content
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "control_plane"
  }
}

resource "hcloud_rdns" "bootstrap" {
  server_id  = hcloud_server.okd_bootstrap.id
  ip_address = hcloud_server.okd_bootstrap.ipv4_address
  dns_ptr    = "bootstrap.${var.okd_domain}"
}

# Control Plane
data "local_file" "control_plane_ignition" {
  filename = "${path.module}/generated-files/control-plane-processed.ign"
}

resource "hcloud_server" "okd_control_plane" {
  count = var.num_okd_control_plane

  name        = "${var.cluster_name}-control${count.index}"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = var.control_plane_server_location[count.index]
  user_data   = data.local_file.control_plane_ignition.content
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "control_plane"
  }
}

resource "hcloud_rdns" "control_plane" {
  count = var.num_okd_control_plane

  server_id  = hcloud_server.okd_control_plane[count.index].id
  ip_address = hcloud_server.okd_control_plane[count.index].ipv4_address
  dns_ptr    = "control${count.index}.${var.okd_domain}"
}

# Workers
data "local_file" "worker_ignition" {
  filename = "${path.module}/generated-files/worker-processed.ign"
}

resource "hcloud_server" "okd_worker" {
  count = var.num_okd_workers

  name        = "${var.cluster_name}-worker${count.index}"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = var.worker_server_location
  user_data   = data.local_file.worker_ignition.content
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "worker"
  }
}

resource "hcloud_rdns" "workers" {
  count = var.num_okd_workers

  server_id  = hcloud_server.okd_worker[count.index].id
  ip_address = hcloud_server.okd_worker[count.index].ipv4_address
  dns_ptr    = "worker${count.index}.${var.okd_domain}"
}
