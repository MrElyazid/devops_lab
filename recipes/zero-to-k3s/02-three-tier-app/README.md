# 02 Three-tier app

Goal: Nginx, FastAPI and PostgreSQL on three VMs.

## Run

```bash
make pool    # once per host
make render STAGE=02-three-tier-app
cd infra/terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook playbooks/site.yml
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running.

VMs: web-01 10.10.10.10, api-01 10.10.10.11, db-01 10.10.10.12.

## Verify

```bash
curl -s http://10.10.10.10/items
ssh ubuntu@10.10.10.12 'sudo -u postgres psql -d labdb -c "select * from items;"'
```

Expected: three items from the API. Nginx proxies port 80 to FastAPI on
10.10.10.11:8000.
