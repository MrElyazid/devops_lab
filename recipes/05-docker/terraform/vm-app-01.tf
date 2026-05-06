resource "libvirt_volume" "app_01_disk" {
  name = "app-01.qcow2"
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

resource "libvirt_cloudinit_disk" "app_01_init" {
  name = "app-01-init"

  meta_data = yamlencode({
    instance-id    = "app-01"
    local-hostname = "app-01"
  })

  user_data = <<-EOF
    #cloud-config
    hostname: app-01
    timezone: UTC
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ${trimspace(file("~/.ssh/lab_key.pub"))}
    ssh_pwauth: false
    final_message: cloud-init done — app-01 is ready
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      id0:
        match:
          driver: virtio_net
        dhcp4: false
        addresses:
          - 10.10.10.11/24
        gateway4: 10.10.10.1
        nameservers:
          addresses: [10.10.10.1]
  EOF
}

resource "libvirt_volume" "app_01_cloudinit" {
  name  = "app-01-cloudinit.iso"
  pool  = libvirt_pool.lab.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.app_01_init.path
    }
  }
}

resource "libvirt_domain" "app_01" {
  name        = "app-01"
  type        = "kvm"
  memory      = 2048
  memory_unit = "MiB"
  vcpu        = 2

  os = {
    type      = "hvm"
    type_arch = "x86_64"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.app_01_disk.pool
            volume = libvirt_volume.app_01_disk.name
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
            pool   = libvirt_volume.app_01_cloudinit.pool
            volume = libvirt_volume.app_01_cloudinit.name
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
