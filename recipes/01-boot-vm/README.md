# 01 — Boot a VM from scratch

## Goal
Provision a running Ubuntu 24.04 VM reachable via SSH at `10.10.10.10`, using
Terraform + libvirt.

## Prerequisites
- QEMU/KVM, libvirt, and `mkisofs`/`genisoimage` installed (needed by the cloud-init resource)
- User in the `libvirt` group: `groups | grep libvirt`
- `libvirtd.service` running: `systemctl status libvirtd`
- SSH key pair at `~/.ssh/lab_key` (generate: `ssh-keygen -t ed25519 -f ~/.ssh/lab_key -N ""`)
- `~/.ssh/config` entry so `ssh ubuntu@10.10.10.10` uses the right key:
  ```
  Host 10.10.10.*
    IdentityFile ~/.ssh/lab_key
  ```

## Steps

### 1. Install the Terraform libvirt provider

Install `dmacvicar/libvirt` v0.9.x from your distribution or upstream.
This provider was rewritten at v0.9 — it mirrors libvirt XML directly.
Old examples found online with `mode = "nat"` or `dhcp {}` blocks won't work.
Use the docs at:
https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/docs/resources/

### 2. Create `infra/terraform/main.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

### 3. Create `infra/terraform/network.tf`

```hcl
resource "libvirt_network" "lab" {
  name = "lab-net"

  forward = {
    mode = "nat"
  }

  domain = {
    name = "lab.local"
  }

  ips = [{
    address = "10.10.10.1"       # host's address on the bridge, NOT the network ID
    netmask = "255.255.255.0"
    dhcp = {
      ranges = [{
        start = "10.10.10.50"
        end   = "10.10.10.200"
      }]
    }
  }]

  dns = {
    enable = "yes"
  }
}
```

### 4. Create `infra/terraform/pool.tf`

```hcl
resource "libvirt_pool" "lab" {
  name = "lab-pool"
  type = "dir"

  target = {
    path = "/hdd/coding/devops_lab/pool"
  }
}
```

The directory must not already exist — libvirt creates it.

### 5. Create `infra/terraform/volumes.tf`

```hcl
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-24.04-base.qcow2"
  pool = libvirt_pool.lab.name

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    }
  }
}
```

### 6. Create `infra/terraform/vm-web-01.tf`

```hcl
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

resource "libvirt_volume" "web_01_cloudinit" {
  name  = "web-01-cloudinit.iso"
  pool  = libvirt_pool.lab.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.web_01_init.path
    }
  }
}

resource "libvirt_domain" "web_01" {
  name        = "web-01"
  type        = "kvm"
  memory      = 1024
  memory_unit = "MiB"
  vcpu        = 1

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    # type_machine omitted — defaults to "pc" (q35 hangs at initramfs)
  }

  devices = {
    disks = [
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
```

### 7. Create `infra/terraform/outputs.tf`

```hcl
output "ssh_command" {
  value = "ssh ubuntu@10.10.10.10"
}
```

### 8. Initialize and apply

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

Terraform will:
1. Create the libvirt NAT network + dnsmasq
2. Create the storage pool directory
3. Download the ~550 MB Ubuntu cloud image (~47s)
4. Create the overlay qcow2 (instant — just metadata)
5. Generate and upload the cloud-init ISO
6. Define and start the VM

### 9. Verify

```bash
# VM is running
virsh -c qemu:///system list --all

# Check boot progress (ctrl+] to exit)
virsh -c qemu:///system console web-01

# SSH in
ssh ubuntu@10.10.10.10
```

## Verify
```bash
ssh ubuntu@10.10.10.10 'hostname && uname -r && uptime'
# Expected: web-01, 6.x kernel, uptime in minutes
```

## Gotchas
- **`ips[0].address` is the host's IP on the bridge** — set to `10.10.10.1`,
  not `10.10.10.0`. Using the network ID breaks routing.
- **`type_machine` must be omitted** — Ubuntu cloud images hang at initramfs
  with `q35` (virtio-blk drivers missing from initramfs). Default `pc` works.
- **`backing_store.path` must be `libvirt_volume.ubuntu_base.path`** — not
  `.id` or `.name`.
- **`virsh` needs `-c qemu:///system`** — `virsh` defaults to `qemu:///session`,
  which has no Terraform-created resources. Set `LIBVIRT_DEFAULT_URI` or use
  the flag.
- **No `wait_for_ip`** — static IP VMs never appear in the DHCP lease table
  (`source = "lease"`), and the guest agent channel (`source = "agent"`) has a
  tricky schema in v0.9.x. The IP is deterministic (`10.10.10.10`).
- **Pool directory must not exist** — `rmdir /hdd/coding/devops_lab/pool` first
  if it does.
- **`mkisofs`/`genisoimage` required** — install via your package manager.
- **cloud-init runs once** — changing user_data after first boot has no effect.
  Destroy and recreate the VM (or change `instance-id` in meta_data).
- **SSH key path** — the config above uses `lab_key.pub`. Adjust to your key.
  If using a non-default name, add `IdentityFile` to `~/.ssh/config`.
