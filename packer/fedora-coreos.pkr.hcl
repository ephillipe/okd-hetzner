packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.3"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "hcloud_token" {
  type    = string
  default = env("HCLOUD_TOKEN")
}

variable "fedora_coreos_version" {
  type = string
}

source "hcloud" "fedora-coreos" {
  image           = "debian-11"
  location        = "nbg1"
  server_type     = "cx21"
  snapshot_name   = "fedora-coreos-${var.fedora_coreos_version}"
  ssh_keys        = ["default"]
  ssh_username    = "root"
  rescue          = "linux64"
  token           = var.hcloud_token
  snapshot_labels = { os = "fedora-coreos", release = "${var.fedora_coreos_version}" }
  user_data       = "#cloud-config\nvendor_data: {'enabled': false}\n"
}

build {
  sources = ["source.hcloud.fedora-coreos"]

  provisioner "shell" {
    inline = [
      "set -x",
      "curl -sL https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${var.fedora_coreos_version}/x86_64/fedora-coreos-${var.fedora_coreos_version}-qemu.x86_64.qcow2.xz | unxz > fedora-coreos-${var.fedora_coreos_version}-qemu.x86_64.qcow2",
      "qemu-img convert -f qcow2 -O raw fedora-coreos-${var.fedora_coreos_version}-qemu.x86_64.qcow2 /dev/sda",
      "mount /dev/sda3 /mnt",
      "mkdir /mnt/ignition"
    ]
  }

  provisioner "file" {
    source      = "packer/config.ign"
    destination = "/mnt/ignition/config.ign"
  }

  provisioner "shell" {
    inline = [
      "set -x",
      "umount /mnt"
    ]
  }
}