# 04 Monitoring

Goal: Prometheus and Grafana on mon-01, node_exporter on every VM.

## Run

```bash
make pool    # once per host
make render STAGE=04-monitoring
cd infra/terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook playbooks/site.yml
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running.

VMs: web-01 10.10.10.10, api-01 10.10.10.11, api-02 10.10.10.13,
db-01 10.10.10.12, mon-01 10.10.10.30.

## Verify

```bash
curl -s http://10.10.10.30:9090/-/ready
curl -s http://10.10.10.30:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
```

Expected: `Prometheus Server is Ready.` and `5`.

Grafana: http://10.10.10.30:3000

First login: `admin` / `admin`. The Prometheus datasource and node dashboard
are provisioned automatically. First start can take a minute or two.
