# 01 Boot a VM

Goal: one Ubuntu VM reachable at 10.10.10.10.

## Run

From the repo root:

```bash
make pool    # once per host
make render STAGE=01-boot-vm
cd infra/terraform
terraform init
terraform apply
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running. The first apply downloads the Ubuntu image and creates the network,
volumes and VM.

## Verify

```bash
virsh -c qemu:///system list --all
ssh ubuntu@10.10.10.10 'hostname; ip -4 addr show'
```

## Next

```bash
cd infra/terraform
terraform destroy
```
