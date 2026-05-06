resource "libvirt_volume" "web_01_disk" {
  name = "web-01.qcow2"
  pool = libvirt_pool.lab.name

  target = {
    format = {
      type = "qcow2"
    }
  }

  capacity = 10737418240 # 10 GB

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "web_01_init" {
  name = "web-01-init"

  meta_data = yamlencode({
    instance-id    = "web-01"
    local-hostname = "web-01"
  })


  user_data = <<-EOF
    #cloud-config
    hostname: web-01
    timezone: UTC

    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ${trimspace(file("~/.ssh/lab_key.pub"))}

    ssh_pwauth: false
    packages:
      - qemu-guest-agent

    final_message: cloud-init done — web-01 is ready
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      id0:
        match:
          driver: virtio_net
        dhcp4: false
        addresses:
          - 10.10.10.10/24
        gateway4: 10.10.10.1
        nameservers:
          addresses: [10.10.10.1]
  EOF
}


# ── Upload the cloud-init ISO to the pool ────────────────────────────────
resource "libvirt_volume" "web_01_cloudinit" {
  name  = "web-01-cloudinit.iso"
  pool  = libvirt_pool.lab.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.web_01_init.path
    }
  }
}

# ── Domain ───────────────────────────────────────────────────────────────
resource "libvirt_domain" "web_01" {
  name        = "web-01"
  type        = "kvm"
  memory      = 1024
  memory_unit = "MiB"
  vcpu        = 1

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
  }

  devices = {
    disks = [
      # Main root disk
      {
        source = {
          volume = {
            pool   = libvirt_volume.web_01_disk.pool
            volume = libvirt_volume.web_01_disk.name
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
      # Cloud-init ISO
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.web_01_cloudinit.pool
            volume = libvirt_volume.web_01_cloudinit.name
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

    # VNC for graphical console (optional — connect with virt-viewer)
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]

    # Serial console so `virsh console web-01` works
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

# IP is static (10.10.10.10) — no wait_for_ip needed
