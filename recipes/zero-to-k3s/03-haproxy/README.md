# 03 HAProxy

Goal: HAProxy on web-01 balances two FastAPI backends.

## Run

```bash
make pool    # once per host
make render STAGE=03-haproxy
cd infra/terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook playbooks/site.yml
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running.

VMs: web-01 10.10.10.10, api-01 10.10.10.11, api-02 10.10.10.13,
db-01 10.10.10.12.

## Verify

```bash
curl -s http://10.10.10.10/items
```

HAProxy stats: http://10.10.10.10:8404

Failover test:

```bash
ssh ubuntu@10.10.10.11 'sudo systemctl stop fastapi'
sleep 10
for i in $(seq 1 6); do curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.10/items; done
ssh ubuntu@10.10.10.11 'sudo systemctl start fastapi'
```

The requests should stay at 200 through api-02.
