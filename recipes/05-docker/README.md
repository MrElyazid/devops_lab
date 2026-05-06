# 05 — Containerize the stack with Docker

## Goal
Consolidate the three VMs running the API and database layer (`api-01`, `api-02`,
`db-01`) into a single Docker host (`app-01`).  The app stack runs in Docker
containers managed by `docker compose`.  HAProxy (web-01) and monitoring
(mon-01) remain bare-metal.

## Prerequisites
- Recipe 04 completed (6 VMs, monitoring working)

## Architecture

```
BEFORE (6 VMs)                          AFTER (4 VMs)

api-01 ✕                                          
api-02 ✕  →  consolidated to →  app-01 (10.10.10.11)
db-01  ✕                         ├─ postgres  :5432
                                  ├─ api_1     :8000
                                  └─ api_2     :8001

web-01 ✓  (HAProxy :80, :8404)      web-01 ✓  (unchanged)
mon-01 ✓  (Prometheus :9090)        mon-01 ✓  (3 scrape targets)
          (Grafana   :3000)                     
```

## Steps

### 1. Remove old VMs, add app-01

```bash
# In infra/terraform/
rm vm-api-01.tf vm-api-02.tf vm-db-01.tf
cp recipes/05-docker/terraform/vm-app-01.tf .
# Update outputs.tf from the recipe
terraform apply
# Destroys 3 VMs, creates app-01
```

### 2. Update inventory

Replace `api` and `db` groups with a single `app` group (see recipe's
`inventory/hosts.yml`).

### 3. Update playbooks

- Copy `docker.yml` from recipe — replaces `fastapi.yml` + `postgresql.yml`
- Update `haproxy.yml` vars: `api_servers` now points to `app-01:8000` + `app-01:8001`
- Update `monitoring.yml` targets: 3 nodes instead of 5
- Update `site.yml` to import `docker.yml` instead of the old playbooks

### 4. Copy the app files

Create `app/` with `Dockerfile`, `docker-compose.yml`, `init.sql`, `main.py`,
and `requirements.txt` (copy from recipe).  Place it alongside `ansible/` so
the playbook's `copy` paths resolve.

### 5. Apply

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 6. Verify

```bash
# Containers running on app-01
ssh ubuntu@10.10.10.11 docker compose -f /opt/app/docker-compose.yml ps

# API through HAProxy (both backends on same VM)
for i in $(seq 1 6); do curl -s http://10.10.10.10/items | head -1; done

# HAProxy stats page shows both backends UP
http://10.10.10.10:8404

# Prometheus sees 3 targets
curl -s http://10.10.10.30:9090/api/v1/targets | python3 -m json.tool | grep instance
```

## Verify
```bash
ssh ubuntu@10.10.10.11 "docker compose -f /opt/app/docker-compose.yml ps --format json" | python3 -m json.tool
# Expected: 3 services (postgres, api_1, api_2) all "running"
```

## Gotchas
- **Existing state needs a destroy first** — Terraform manages the old VMs.
  Removing the `.tf` files tells Terraform to destroy them.  Run `terraform plan`
  first to confirm.
- **Docker needs internet** — `docker compose up` pulls images from Docker Hub.
  App-01 must have internet access (the lab network is NAT'd, so this works).
- **`--wait` flag** in `docker compose up -d --wait` blocks until all containers
  report healthy.  The PostgreSQL healthcheck uses `pg_isready`; API containers
  wait for `depends_on: postgres: condition: service_healthy`.
- **init.sql auto-seeds** — the PostgreSQL image runs `.sql` files from
  `/docker-entrypoint-initdb.d/` on first start.  If the `pgdata` volume
  already exists (from a previous run), init scripts don't re-run.  To reset:
  `docker compose down -v` (destroys the volume).
- **node_exporter on app-01** — Prometheus scrape target changes from
  5 hosts to 3.  The monitoring playbook vars are updated accordingly.
