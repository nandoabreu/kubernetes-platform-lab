locals {
  nodes = {
    k3s-1 = {
      ip  = "10.77.0.11"
      mac = "52:54:00:77:00:11"
    }
    k3s-2 = {
      ip  = "10.77.0.12"
      mac = "52:54:00:77:00:12"
    }
    k3s-3 = {
      ip  = "10.77.0.13"
      mac = "52:54:00:77:00:13"
    }
  }
}

resource "libvirt_network" "k3s_lab" {
  name      = "k3s-lab"
  autostart = false

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "10.77.0.1"
      prefix  = 24

      dhcp = {
        ranges = [
          {
            start = "10.77.0.100"
            end   = "10.77.0.199"
          }
        ]

        hosts = [
          for name, node in local.nodes : {
            name = name
            mac  = node.mac
            ip   = node.ip
          }
        ]
      }
    }
  ]
}

resource "libvirt_volume" "ubuntu_base" {
  name       = "k3s-lab-ubuntu-24.04-base.qcow2"
  pool       = var.storage_pool
  capacity   = var.base_image_capacity_gib * 1024 * 1024 * 1024
  allocation = 0

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = pathexpand(var.cloud_image_path)
    }
  }
}

resource "libvirt_volume" "node_disk" {
  for_each = local.nodes

  name       = "${each.key}.qcow2"
  pool       = var.storage_pool
  capacity   = var.disk_size_gib * 1024 * 1024 * 1024
  allocation = 0

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "node" {
  for_each = local.nodes

  name = "${each.key}-cloudinit.iso"
  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })
  meta_data = yamlencode({
    "instance-id"    = each.key
    "local-hostname" = each.key
  })
}

resource "libvirt_volume" "node_cloudinit" {
  for_each = local.nodes

  name = "${each.key}-cloudinit.iso"
  pool = var.storage_pool

  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.node[each.key].path
    }
  }
}

resource "libvirt_domain" "node" {
  for_each = local.nodes

  name        = each.key
  type        = "kvm"
  memory      = var.memory_mib
  memory_unit = "MiB"
  vcpu        = var.vcpu
  running     = false
  autostart   = false

  os = {
    type      = "hvm"
    type_arch = "x86_64"
    boot_devices = [
      { dev = "hd" },
      { dev = "cdrom" }
    ]
  }

  devices = {
    serials = [
      {
        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]

    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    disks = [
      {
        device = "disk"
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = var.storage_pool
            volume = libvirt_volume.node_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = var.storage_pool
            volume = libvirt_volume.node_cloudinit[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        mac = {
          address = each.value.mac
        }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.k3s_lab.name
          }
        }
      }
    ]
  }

  lifecycle {
    ignore_changes = [running]
  }
}
