# Required DNS records
# https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal

# Kubernetes API
resource "cloudflare_record" "dns_a_api" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "api.${var.okd_domain}"
  value   = hcloud_load_balancer.control_plane.ipv4
  type    = "A"
  ttl     = 120
}

resource "cloudflare_record" "dns_a_api_int" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "api-int.${var.okd_domain}"
  value   = hcloud_load_balancer.control_plane.ipv4
  type    = "A"
  ttl     = 120
}

# Routes / Apps
resource "cloudflare_record" "dns_a_apps" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "*.apps.${var.okd_domain}"
  value   = hcloud_load_balancer.workers.ipv4
  type    = "A"
  ttl     = 120
}

# Bootstrap machine
resource "cloudflare_record" "dns_a_bootstrap" {
  zone_id = var.cloudflare_dns_zone_id
  name    = "bootstrap.${var.okd_domain}"
  value   = hcloud_server.okd_bootstrap.ipv4_address
  type    = "A"
  ttl     = 120
}

# Control plane machines
resource "cloudflare_record" "dns_a_control_plane" {
  count = var.num_okd_control_plane

  zone_id = var.cloudflare_dns_zone_id
  name    = "${var.cluster_name}-control-${count.index}.${var.okd_domain}"
  value   = hcloud_server.okd_control_plane[count.index].ipv4_address
  type    = "A"
  ttl     = 120
}

# Worker machines
resource "cloudflare_record" "dns_a_workers" {
  count = var.num_okd_workers

  zone_id = var.cloudflare_dns_zone_id
  name    = "${var.cluster_name}-worker-${count.index}.${var.okd_domain}"
  value   = hcloud_server.okd_worker[count.index].ipv4_address
  type    = "A"
  ttl     = 120
}

# etcd
resource "cloudflare_record" "dns_a_etcd" {
  count = var.num_okd_control_plane

  zone_id = var.cloudflare_dns_zone_id
  name    = "etcd-${count.index}.${var.okd_domain}"
  value   = hcloud_server.okd_control_plane[count.index].ipv4_address
  type    = "A"
  ttl     = 120
}

resource "cloudflare_record" "dns_srv_etcd" {
  count = var.num_okd_control_plane

  zone_id = var.cloudflare_dns_zone_id
  name    = "_etcd-server-ssl._tcp.${var.okd_domain}"
  type    = "SRV"

  data {
    service  = "_etcd-server-ssl"
    proto    = "_tcp"
    name     = "_etcd-server-ssl._tcp.${var.okd_domain}"
    priority = 0
    weight   = 0
    port     = 2380
    target   = "etcd-${count.index}.${var.okd_domain}"
  }
}