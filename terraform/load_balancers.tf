# Control plane
resource "hcloud_load_balancer" "control_plane" {
  name               = "${var.cluster_name}-control"
  load_balancer_type = var.load_balancer_type
  network_zone       = var.load_balancer_location
  algorithm {
    type = "round_robin"
  }
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "control_plane"
  }
}

resource "hcloud_rdns" "kubernetes_api" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  ip_address       = hcloud_load_balancer.control_plane.ipv4
  dns_ptr          = "api.${var.okd_domain}"
}

resource "hcloud_rdns" "kubernetes_api_int" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  ip_address       = hcloud_load_balancer.control_plane.ipv4
  dns_ptr          = "api-int.${var.okd_domain}"
}

resource "hcloud_load_balancer_service" "kubernetes_api" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "machine_config_server" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  protocol         = "tcp"
  listen_port      = 22623
  destination_port = 22623

  health_check {
    protocol = "tcp"
    port     = 22623
    interval = 10
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_target" "control_plane" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.control_plane.id
  label_selector   = "type=control_plane"
}

# Workers
resource "hcloud_load_balancer" "workers" {
  name               = "${var.cluster_name}-workers"
  load_balancer_type = var.load_balancer_type
  network_zone       = var.load_balancer_location
  algorithm {
    type = "round_robin"
  }
  labels = {
    "cluster" = "${var.cluster_name}",
    "type"    = "worker"
  }
}

resource "hcloud_load_balancer_service" "ingress_http" {
  load_balancer_id = hcloud_load_balancer.workers.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 10
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "ingress_https" {
  load_balancer_id = hcloud_load_balancer.workers.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 10
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_target" "workers" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.workers.id
  label_selector   = "type=worker"
}