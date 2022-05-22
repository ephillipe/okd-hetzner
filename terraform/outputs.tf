output "loadbalancer_server_ip" {
  value = hcloud_server.okd_loadbalancer.ipv4_address
}