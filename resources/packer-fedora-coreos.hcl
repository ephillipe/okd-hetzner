source "hcloud" "fedora-coreos" {
  image           = "debian-11"
  location        = "nbg1"
  server_type     = "cx21"
  snapshot_name   = "fedora-coreos-{{user `LATEST_FEDORA_COREOS_VERSION`}}"
  ssh_keys        = ["default"]
  ssh_username    = "root"
  rescue          = "linux64"
  token           = var.hcloud_token
  snapshot_labels = { os = "fedora-coreos", release = "{{user `LATEST_FEDORA_COREOS_VERSION`}}" }
}

build {
  sources = ["source.fedora-coreos"]

  provisioner "shell" {
    inline = [
      "set -x",
      "curl -sL https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/{{user `LATEST_FEDORA_COREOS_VERSION`}}/x86_64/fedora-coreos-{{user `LATEST_FEDORA_COREOS_VERSION`}}-metal.x86_64.raw.xz | xz -d | dd of=/dev/sda",
      "mount /dev/sda3 /mnt",
      "mkdir /mnt/ignition",
      "set -x",
      "cd",
      "unmount /mnt"
    ]
  }
}
