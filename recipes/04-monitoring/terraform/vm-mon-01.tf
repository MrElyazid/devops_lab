resource "libvirt_volume" "mon_01_disk" {
  name = "mon-01.qcow2"
  pool = libvirt_pool.lab.name

  target = {
    format = {
      type = "qcow2"
    }
  }

  capacity = 10737418240

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "mon_01_init" {
  name = "mon-01-init"

  meta_data = yamlencode({
    instance-id    = "mon-01"
    local-hostname = "mon-01"
  })

  user_data = <<-EOF
    #cloud-config
    hostname: mon-01
    timezone: UTC
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ${trimspace(file("~/.ssh/lab_key.pub"))}
    ssh_pwauth: false
    final_message: cloud-init done — mon-01 is ready
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      id0:
        match:
          driver: virtio_net
        dhcp4: false
        addresses:
          - 10.10.10.30/24
        gateway4: 10.10.10.1
        nameservers:
          addresses: [10.10.10.1]
  EOF
}

resource "libvirt_volume" "mon_01_cloudinit" {
  name  = "mon-01-cloudinit.iso"
  pool  = libvirt_pool.lab.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.mon_01_init.path
    }
  }
}

resource "libvirt_domain" "mon_01" {
  name        = "mon-01"
  type        = "kvm"
  memory      = 1536
  memory_unit = "MiB"
  vcpu        = 1

  os = {
    type      = "hvm"
    type_arch = "x86_64"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.mon_01_disk.pool
            volume = libvirt_volume.mon_01_disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.mon_01_cloudinit.pool
            volume = libvirt_volume.mon_01_cloudinit.name
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
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.lab.name
          }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
  }

  running = true
}
