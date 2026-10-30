# One VM template

Minimal Terraform module for one Ubuntu 24.04 VM. Use it as the starting point
for a new lab. It is not part of the six-stage course.

## What it creates

- `lab-net` NAT network, 10.10.10.0/24
- `lab-pool` storage pool under this repo
- Ubuntu base image and a 10 GB overlay disk
- `web-01` at 10.10.10.10, with the key from `~/.ssh/lab_key.pub`

## Use

Copy the folder, then change the network name, subnet, pool path, VM name and
IP before applying. The defaults collide with the course lab.

```bash
cp -r recipes/one-vm ~/my-lab
cd ~/my-lab/terraform
# edit the .tf files first
terraform init
terraform apply
ssh ubuntu@10.10.10.10
```

## Destroy

```bash
terraform destroy
```

To re-apply after a destroy, remove the pool directory first. libvirt will not
build it again if the directory already exists.
