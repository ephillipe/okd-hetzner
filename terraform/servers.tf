data "local_file" "bootstrap_ignition" {
  filename = "${path.root}/generated-files/bootstrap.ign"
}

data "local_file" "control_plane_ignition" {
  filename = "${path.root}/generated-files/control-plane.ign"
}

data "local_file" "worker_ignition" {
  filename = "${path.root}/generated-files/worker.ign"
}

resource "hcloud_server" "okd_bootstrap" {
  depends_on = [
    hcloud_network_subnet.okd
  ]

  name        = "${var.cluster_name}-bootstrap"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = var.bootstrap_server_location
  user_data   = data.local_file.bootstrap_ignition
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "control_plane"
  }
  network {
    network_id = hcloud_network.okd.id
  }
}

resource "hcloud_server" "okd_control_plane" {
  depends_on = [
    hcloud_network_subnet.okd
  ]

  count = var.num_okd_control_plane

  name        = "${var.cluster_name}-control-plane-${count.index}"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = [for location in var.control_plane_server_location : "${location}"]
  user_data   = data.local_file.control_plane_ignition
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "control_plane"
  }
  network {
    network_id = hcloud_network.okd.id
  }
}

resource "hcloud_server" "okd_worker" {
  depends_on = [
    hcloud_network_subnet.okd
  ]

  count = var.num_okd_workers

  name        = "${var.cluster_name}-worker-${count.index}"
  server_type = var.bootstrap_server_type
  image       = var.fedora_coreos_image_id
  location    = var.worker_server_location
  user_data   = data.local_file.control_plane_ignition
  ssh_keys    = var.hetzner_ssh_keys
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "worker"
  }
  network {
    network_id = hcloud_network.okd.id
  }
}