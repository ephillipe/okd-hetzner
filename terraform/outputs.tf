output "lighthouse_server_ip" {
  value = hcloud_server.okd_lighthouse.ipv4_address
}