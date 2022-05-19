packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "latest_fedora_coreos_version" {
  default = env("LATEST_FEDORA_COREOS_VERSION")
}

variable "hcloud_token" {
  default = env("HCLOUD_TOKEN")
}

source "hcloud" "fedora-coreos" {
  image           = "debian-11"
  location        = "nbg1"
  server_type     = "cx21"
  snapshot_name   = "fedora-coreos-${var.latest_fedora_coreos_version}"
  ssh_keys        = ["default"]
  ssh_username    = "root"
  rescue          = "linux64"
  token           = var.hcloud_token
  snapshot_labels = { os = "fedora-coreos", release = "${var.latest_fedora_coreos_version}" }
}

build {
  sources = ["source.hcloud.fedora-coreos"]

  provisioner "shell" {
    inline = [
      "set -x",
      "curl -sL https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${var.latest_fedora_coreos_version}/x86_64/fedora-coreos-${var.latest_fedora_coreos_version}-metal.x86_64.raw.xz | xz -d | dd of=/dev/sda"
    ]
  }
}
