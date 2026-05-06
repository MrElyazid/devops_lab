# AGENTS.md

## Project structure
```
exercises/      # Self-contained .md practice problems (01-, 02-, ...)
concepts/       # Deep-dive explanations of topics used in exercises
infra/terraform/  # Working Terraform root module you build through exercises
```

Each exercise builds on the previous. `infra/terraform/` is the live workspace; exercises tell you what to add to it.

## Critical provider knowledge

**libvirt provider v0.9.x is a full rewrite** — schema mirrors libvirt XML directly. Flat attributes from old 0.7/0.8 examples (`mode`, `addresses`, `dhcp {}` blocks) don't exist. The authoritative schema docs:
- GitHub: `https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/docs/resources/`
- Terraform Registry: `https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs` (JS-walled — fetch raw .md from GitHub instead)

Install: the `dmacvicar/libvirt` provider from your distribution or upstream releases.

## Hard-earned gotchas

1. **`virsh` vs Terraform URI mismatch** — Terraform uses `qemu:///system`; `virsh` defaults to `qemu:///session`. Always:
   ```bash
   virsh -c qemu:///system ...
   # or: export LIBVIRT_DEFAULT_URI=qemu:///system
   ```

2. **`ips[0].address` is the HOST address** on the bridge, NOT the network ID. Set it to `10.10.10.1`, not `10.10.10.0`. This bit us for an hour.

3. **Ubuntu cloud images hang at initramfs with `type_machine = "q35"`** — the initramfs lacks virtio-blk modules needed for q35 PCIe. Omit `type_machine` (defaults to `pc`, which works).

4. **`wait_for_ip` with static IP + cloud-init will always timeout** — static IP VMs never appear in DHCP lease table (`source = "lease"`), and guest agent channel schema in v0.9.x is tricky (`source = "agent"`). Omit `wait_for_ip` when using static IPs.

5. **cloud-init `network_config` interface names** — libvirt assigns unpredictable PCI addresses across destroy/recreate cycles. Hardcoded names (`enp1s0`, `ens3`) break. Use `match: driver: virtio_net` in netplan config.

6. **`backing_store.path`** must reference `libvirt_volume.<name>.path`, not `.id` or `.name`.

7. **Storage pool `target.path`** must NOT exist before creation — libvirt will fail to define the pool.

8. **`mkisofs`/`genisoimage` required** for `libvirt_cloudinit_disk` — install via your distribution's package manager.

9. **cloud-init runs once** — changing user_data after first boot has no effect. Must destroy/recreate the VM (or change instance-id in meta_data).

## Provider install & version
Install `dmacvicar/libvirt` v0.9.x from your distribution's package manager or the upstream release.

Terraform version constraint: `version = "~> 0.9.0"`

Provider URI: `qemu:///system` in `provider "libvirt" {}` block.
