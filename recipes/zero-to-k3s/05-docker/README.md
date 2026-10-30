# 05 Docker

Goal: run the app stack with Docker Compose on app-01.

## Run

```bash
make pool    # once per host
make render STAGE=05-docker
cd infra/terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook playbooks/site.yml
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running.

VMs: web-01 10.10.10.10, app-01 10.10.10.11, mon-01 10.10.10.30.
This stage removes api-01, api-02 and db-01.

## Verify

```bash
curl -s http://10.10.10.10/items
ssh ubuntu@10.10.10.11 'sudo docker compose -f /opt/app/docker-compose.yml ps'
```

Expected: three containers running (postgres and two API containers).
HAProxy targets app-01:8000 and app-01:8001.
Stats: http://10.10.10.10:8404

The first run pulls images from Docker Hub.

Reset the database volume:

```bash
ssh ubuntu@10.10.10.11 'cd /opt/app && sudo docker compose down -v && sudo docker compose up -d --wait'
```
