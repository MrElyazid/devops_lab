resource "libvirt_volume" "k3s_master_disk" {
  name = "k3s-master.qcow2"
  pool = libvirt_pool.lab.name

  target = { format = { type = "qcow2" } }
  capacity = 10737418240

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "k3s_master_init" {
  name = "k3s-master-init"

  meta_data = yamlencode({
    instance-id    = "k3s-master"
    local-hostname = "k3s-master"
  })

  user_data = <<-EOF
    #cloud-config
    hostname: k3s-master
    timezone: UTC
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ${trimspace(file("~/.ssh/lab_key.pub"))}
    ssh_pwauth: false
    final_message: cloud-init done — k3s-master is ready
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      id0:
        match:
          driver: virtio_net
        dhcp4: false
        addresses:
          - 10.10.10.40/24
        gateway4: 10.10.10.1
        nameservers:
          addresses: [10.10.10.1]
  EOF
}

resource "libvirt_volume" "k3s_master_cloudinit" {
  name  = "k3s-master-cloudinit.iso"
  pool  = libvirt_pool.lab.name
  create = {
    content = {
      url = libvirt_cloudinit_disk.k3s_master_init.path
    }
  }
}

resource "libvirt_domain" "k3s_master" {
  name        = "k3s-master"
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
            pool   = libvirt_volume.k3s_master_disk.pool
            volume = libvirt_volume.k3s_master_disk.name
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
            pool   = libvirt_volume.k3s_master_cloudinit.pool
            volume = libvirt_volume.k3s_master_cloudinit.name
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
