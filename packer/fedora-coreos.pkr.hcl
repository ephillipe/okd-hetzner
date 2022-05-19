packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "hcloud_token" {
  default = env("HCLOUD_TOKEN")
}

source "hcloud" "fedora-coreos" {
  image           = "debian-11"
  location        = "nbg1"
  server_type     = "cx21"
  snapshot_name   = "fedora-coreos-{{user `fedora_coreos_version`}}"
  ssh_keys        = ["default"]
  ssh_username    = "root"
  rescue          = "linux64"
  token           = var.hcloud_token
  snapshot_labels = { os = "fedora-coreos", release = "{{user `fedora_coreos_version`}}" }
}

build {
  sources = ["source.hcloud.fedora-coreos"]

  provisioner "shell" {
    inline = [
      "set -x",
      "curl -sL https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/{{user `fedora_coreos_version`}}/x86_64/fedora-coreos-{{user `fedora_coreos_version`}}-metal.x86_64.raw.xz | xz -d | dd of=/dev/sda"
    ]
  }
}
