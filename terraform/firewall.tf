# resource "hcloud_firewall" "all" {
#   name = "${var.cluster_name}-all"

#   apply_to {
#     label_selector = "cluster=${var.cluster_name}"
#   }

#   rule {
#     direction = "in"
#     protocol  = "icmp"
#     source_ips = [
#       "${hcloud_network.okd.ip_range}"
#     ]
#   }

#   rule {
#     direction = "in"
#     protocol  = "tcp"
#     port      = "any"
#     source_ips = [
#       "${hcloud_network.okd.ip_range}"
#     ]
#   }

#   rule {
#     direction = "in"
#     protocol  = "udp"
#     port      = "any"
#     source_ips = [
#       "${hcloud_network.okd.ip_range}"
#     ]
#   }

#   rule {
#     direction = "in"
#     protocol  = "tcp"
#     port      = "22"
#     source_ips = [
#       "0.0.0.0/0",
#       "::/0"
#     ]
#   }
# }

# resource "hcloud_firewall" "control_plane" {
#   name = "${var.cluster_name}-control-plane"

#   apply_to {
#     label_selector = "type=control_plane"
#   }

#   rule {
#     direction  = "in"
#     protocol   = "tcp"
#     port       = "6443"
#     source_ips = concat([for ip in hcloud_server.okd_control_plane[*].ipv4_address : "${ip}/32"], [for ip in hcloud_server.okd_worker[*].ipv4_address : "${ip}/32"], ["${hcloud_server.okd_bootstrap.ipv4_address}/32"], ["${hcloud_load_balancer.control_plane.ipv4}/32"])
#   }

#   rule {
#     direction  = "in"
#     protocol   = "tcp"
#     port       = "22623"
#     source_ips = concat([for ip in hcloud_server.okd_control_plane[*].ipv4_address : "${ip}/32"], [for ip in hcloud_server.okd_worker[*].ipv4_address : "${ip}/32"], ["${hcloud_server.okd_bootstrap.ipv4_address}/32"], ["${hcloud_load_balancer.control_plane.ipv4}/32"])
#   }

#   rule {
#     direction  = "in"
#     protocol   = "tcp"
#     port       = "2379-2380"
#     source_ips = concat([for ip in hcloud_server.okd_control_plane[*].ipv4_address : "${ip}/32"], [for ip in hcloud_server.okd_worker[*].ipv4_address : "${ip}/32"], ["${hcloud_server.okd_bootstrap.ipv4_address}/32"], ["${hcloud_load_balancer.control_plane.ipv4}/32"])
#   }
# }

# resource "hcloud_firewall" "workers" {
#   name = "${var.cluster_name}-workers"

#   apply_to {
#     label_selector = "type=worker"
#   }

#   rule {
#     direction  = "in"
#     protocol   = "tcp"
#     port       = "80"
#     source_ips = ["${hcloud_load_balancer.workers.ipv4}/32", "${hcloud_server.okd_bootstrap.ipv4_address}/32"]
#   }

#   rule {
#     direction  = "in"
#     protocol   = "tcp"
#     port       = "443"
#     source_ips = ["${hcloud_load_balancer.workers.ipv4}/32", "${hcloud_server.okd_bootstrap.ipv4_address}/32"]
#   }
# }
