# Concepts — boot a VM from scratch

## Terraform essentials

**Provider**: A plugin that talks to an API. `dmacvicar/libvirt` communicates
with the local `libvirtd`. Terraform downloads it on first `terraform init`.

**Resource**: Something that should exist (`libvirt_network`, `libvirt_pool`,
`libvirt_domain`). Declared as `resource "type" "name" { ... }`. After apply,
it exists both in reality and in the state file (`terraform.tfstate`).

**State**: Maps HCL resources to real-world IDs. Stored locally in
`terraform.tfstate` (git-ignored).

**Data source**: Reads information that already exists (not managed by us).
Referenced as `data.<type>.<name>`.

**Output**: Prints values after apply. Stores in state so
`terraform output <name>` works without running plan.

**The cycle**: `init` (download providers) → `plan` (diff state vs .tf, read-only)
→ `apply` (execute, update state) → `destroy` (delete everything in state).

Provider docs: https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/docs/resources/

## v0.9.x schema — XML direct mapping

The libvirt provider was rewritten from scratch at v0.9. The schema now
mirrors libvirt's XML structure directly — no abstractions. This means:

- Old flat attributes (`mode = "nat"`) → nested objects (`forward = { mode = "nat" }`)
- Old `dhcp { enabled = true }` blocks → nested lists (`ips[0].dhcp.ranges`)
- Old `addresses = ["..."]` → `ips[0].address` + `ips[0].netmask`

The Terraform Registry docs are JS-walled; fetch raw `.md` from GitHub's
`docs/resources/` directory instead.

## How libvirt networking works

When we define `libvirt_network "lab"`, libvirt:

1. Creates a **bridge** (`virbr1`) with IP `10.10.10.1/24` — the host is the
   gateway for all VMs on this network.
2. Starts **dnsmasq** on the bridge: DHCP (`10.10.10.1:67`) and DNS (`10.10.10.1:53`).
3. Inserts **iptables NAT rules** so VM traffic is masqueraded through the
   host's default route (e.g. `eth0`).
4. When a VM attaches to the network, a **tap interface** (`vnetN`) is created
   and plugged into the bridge.

```
internet
  ↑ masquerade via host's eth0
virbr1 (10.10.10.1/24)
  ├── vnet0 → web-01 (10.10.10.10)
  ├── vnet1 → web-02 (10.10.10.11)  [future]
  └── vnet2 → lb-01   (10.10.10.20)  [future]
```

**Addressing scheme** with DHCP range `.50–.200`:
- `.1` — gateway (host)
- `.2–.49` — free for static IPs (our VMs)
- `.50–.200` — DHCP pool
- `.201–.254` — free
- `.255` — broadcast

**Forward modes**: `nat` (VMs reach outside via host's IP, default), `route`
(no NAT, host acts as router), `bridge` (VMs bridged directly to physical NIC),
`none` (isolated, VMs can only talk to each other).

**DNS**: dnsmasq resolves `<vm-hostname>.lab.local` from DHCP lease data.

**Critical gotcha**: `ips[0].address` is the **host's own address** on the
bridge. Setting it to `10.10.10.0` (the network ID) makes the host unreachable
from VMs. Must be `10.10.10.1`.

## How cloud-init works

cloud-init is the industry-standard mechanism for first-boot provisioning.
It runs once, on first boot, then never again (unless `instance-id` changes).

**Delivery mechanism**: `libvirt_cloudinit_disk` generates an ISO 9660
filesystem with volume label `cidata`, containing:

| File | Purpose |
|------|---------|
| `user-data` | YAML: create users, install packages, run commands |
| `meta-data` | YAML: instance-id, hostname (VM identity) |
| `network-config` | Netplan v2 YAML: interface IP, gateway, DNS |

The ISO is uploaded to the storage pool and attached as a CD-ROM to the VM.
cloud-init (pre-installed in the Ubuntu cloud image) scans block devices for the
`cidata` label on first boot.

**Boot sequence**:
1. BIOS boots from vda (qcow2 disk)
2. Kernel loads, initramfs runs
3. `cloud-init-local.service`: scans for cidata, applies network-config via netplan
4. `cloud-init.service`: applies user-data (users, packages)
5. `cloud-config.service`: late config, `final_message`
6. VM is ready

**user-data directives used**:
- `users` — creates the `ubuntu` user with sudo, injects SSH authorized_keys,
  locks password
- `packages` — apt-get installs on first boot
- `hostname` — sets system hostname
- `ssh_pwauth: false` — no password-based SSH

**network-config (netplan v2)**:

```yaml
version: 2
ethernets:
  id0:
    match:
      driver: virtio_net     # matches any virtio NIC — immune to PCI renumbering
    dhcp4: false
    addresses:
      - 10.10.10.10/24
    gateway4: 10.10.10.1
    nameservers:
      addresses: [10.10.10.1]
```

Using `match: driver: virtio_net` is essential: libvirt assigns unpredictable
PCI addresses across destroy/recreate cycles, so hardcoded interface names
(`enp1s0`, `ens3`, etc.) break.  Matching by driver makes the config portable.

**Debugging cloud-init from inside the VM**:
```bash
cloud-init status
cat /var/log/cloud-init.log
cat /etc/netplan/50-cloud-init.yaml
ip link show
```

## Storage: pools, volumes, and qcow2 backing chains

### Storage pool

A directory on the host filesystem where libvirt stores disk images.
`type = "dir"` with `target.path = "/hdd/coding/devops_lab/pool"`.
The directory must not exist before creation.

### Base volume

The Ubuntu 24.04 cloud image (`ubuntu-24.04-base.qcow2`), downloaded once via
`create.content.url`. This is a qcow2 file (~550 MB). It serves as a read-only
backing store for all VMs in the lab.

### Overlay volume

A qcow2 file that references the base image via `backing_store`. Only writes
(diffs) are stored in the overlay. The base is shared and never modified.

```
ubuntu-24.04-base.qcow2  (read-only, 550 MB on disk)
    ↑ backing_store
web-01.qcow2             (writable, starts ~200 KB, grows with writes)
    ↑ attached as vda
VM sees a 10 GB disk
```

**Read**: QEMU checks the overlay first; if the block wasn't written there,
falls through to the base.

**Write**: QEMU always writes to the overlay (copy-on-write). Base never changes.

**Verification**:
```bash
qemu-img info --backing-chain /hdd/coding/devops_lab/pool/web-01.qcow2
```

### Machine type: pc vs q35

Ubuntu 24.04 cloud images use **virtio** for the root disk. With
`type_machine = "q35"` (PCIe-native chipset), the kernel needs `virtio-blk`
built into the initramfs to find the root disk. The cloud image doesn't
include it → hangs at `(initramfs)`.

With the default `type_machine = "pc"` (i440FX chipset), the kernel can fall
back to a compatibility path and finds the disk. **Always omit `type_machine`
unless you need q35-specific features.**
