# devops_lab

A local DevOps practice environment on one machine: QEMU/KVM + libvirt run the
virtual machines, Terraform provisions them, Ansible configures them.

Everything is done thanks to : https://github.com/dmacvicar/terraform-provider-libvirt


## Layout

| Path | Purpose |
|---|---|
| [`recipes/one-vm/`](./recipes/one-vm/) | Minimal Terraform template for a single Ubuntu VM |
| [`recipes/zero-to-k3s/NN-*/`](./recipes/zero-to-k3s/) | Complete, independently runnable snapshots of the six stages |
| `labs/` | Independent experiments; each has its own state, subnet and pool |
| `infra/` | Generated workspace (gitignored); never treat it as the source |

Each stage is a full snapshot, `make render STAGE=...` copies one
into `infra/`. The six stages share the persistent `lab-pool` (created once with
`make pool`); `recipes/one-vm` remains self-contained and defines its own pool.

## Prerequisites

- QEMU/KVM and libvirt, user in the `libvirt` group
- Terraform >= 1.5 with `dmacvicar/libvirt` 0.9.x
- Ansible
- `mkisofs` or `genisoimage` for cloud-init ISO generation
- SSH key at `~/.ssh/lab_key` (the public key is injected by cloud-init)
- The persistent storage pool `lab-pool` (create once with `make pool`)

## Usage

```bash
make pool          # once per host; idempotent
make list
make render STAGE=04-monitoring

cd infra/terraform
terraform init
terraform apply

cd ../ansible
ansible-playbook playbooks/site.yml
```

Switch stages:

```bash
cd infra/terraform
terraform destroy
cd ../..
make render STAGE=05-docker
cd infra/terraform && terraform init && terraform apply
```

The `lab-pool` storage pool is persistent and not managed by Terraform, so it
survives `terraform destroy`; only its volumes are removed. The next apply
re-downloads the Ubuntu base image.

`infra/` is disposable and gitignored. It also holds Terraform state; deleting
it without `terraform destroy` leaves the VMs defined but unmanaged.

## Labs

Independent experiments go under `labs/<name>/` as their own Terraform root
module, with unique network, pool and VM names and a subnet that does not
overlap `10.10.10.0/24`. They are not part of the six-stage course.
