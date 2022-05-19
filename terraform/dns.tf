# Required DNS records
# https://docs.okd.io/4.10/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal

# Kubernetes API
resource "cloudflare_record" "dns_a_api" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "api.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_load_balancer.control_plane.ipv4}"
  type    = "A"
  ttl     = 120
}

resource "hcloud_rdns" "api" {
  load_balancer_id = "${hcloud_load_balancer.control_plane.id}"
  ip_address       = "${hcloud_load_balancer.control_plane.ipv4}"
  dns_ptr          = "api.${var.cluster_name}.${base_domain}"
}

resource "cloudflare_record" "dns_a_api_int" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "api-int.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_load_balancer.control_plane.ipv4}"
  type    = "A"
  ttl     = 120
}

resource "hcloud_rdns" "api_int" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  ip_address       = hcloud_load_balancer.control_plane.ipv4
  dns_ptr          = "api-int.${var.cluster_name}.${base_domain}"
}

# Routes
resource "cloudflare_record" "dns_a_apps_wc" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "*.apps.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_load_balancer.workers.ipv4}"
  type    = "A"
  ttl     = 120
}

# Bootstrap machine
resource "cloudflare_record" "dns_a_bootstrap" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "bootstrap.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_server.okd_bootstrap.ipv4_address}"
  type    = "A"
  ttl     = 120
}

resource "hcloud_rdns" "bootstrap" {
  load_balancer_id = hcloud_server.okd_bootstrap.id
  ip_address       = hcloud_server.okd_bootstrap.ipv4_address
  dns_ptr          = "bootstrap.${var.cluster_name}.${base_domain}"
}

# Control plane machines
resource "cloudflare_record" "dns_a_control_plane" {
  count = var.num_okd_control_plane

  zone_id = var.cloudflare_dns_zone_id
  name    = "okd-control-${count.index}.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_server.okd_control_plane[count.index].ipv4_address}"
  type    = "A"
  ttl     = 120
}

resource "hcloud_rdns" "control_plane" {
  count = var.num_okd_control_plane

  load_balancer_id = "${hcloud_server.okd_bootstrap[count.index].id}"
  ip_address       = "${hcloud_server.okd_bootstrap[count.index].ipv4_address}"
  dns_ptr          = "okd-control-${count.index}.${var.cluster_name}.${base_domain}"
}

# Worker machines
resource "cloudflare_record" "dns_a_workers" {
  count = var.num_okd_workers

  zone_id = var.cloudflare_dns_zone_id
  name    = "okd-worker-${count.index}.${var.cluster_name}.${base_domain}"
  value   = "${hcloud_server.okd_worker.count.index.ipv4_address}"
  type    = "A"
  ttl     = 120
}

resource "hcloud_rdns" "workers" {
  count = var.num_okd_workers

  load_balancer_id = "${hcloud_server.okd_worker[count.index].id}"
  ip_address       = "${hcloud_server.okd_worker[count.index].ipv4_address}"
  dns_ptr          = "okd-worker-${count.index}.${var.cluster_name}.${base_domain}"
}