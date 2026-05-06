# 04 — Monitoring with Prometheus + Grafana

## Goal
Add a monitoring VM (`mon-01`) running Prometheus and Grafana.  Install
node_exporter on every VM so Prometheus can scrape CPU, memory, disk, and
network metrics.  Provision a pre-built Grafana dashboard.

## Prerequisites
- Recipe 03 completed (5 VMs, HAProxy load balancing)

## Architecture

```
                         mon-01 (10.10.10.30)
                      ┌─────────────────────────┐
                      │  Grafana     :3000       │  dashboards
                      │    ↓                     │
                      │  Prometheus  :9090       │  scraper + time-series DB
                      └─────────┬───────────────┘
                                │ pull every 15s
            ┌───────┬───────────┼───────┬───────┐
            ▼       ▼           ▼       ▼       ▼
          web-01  api-01     api-02  db-01   mon-01
          :9100   :9100      :9100   :9100    :9100
```

Prometheus polls the `/metrics` endpoint of each node_exporter instance.
Grafana queries Prometheus and renders dashboards.

## Steps

### 1. Add mon-01 VM

Copy `recipes/04-monitoring/terraform/vm-mon-01.tf` into `infra/terraform/`,
update `outputs.tf`, then:

```bash
cd infra/terraform
terraform apply
```

Verify:

```bash
ssh ubuntu@10.10.10.30 hostname  # mon-01
```

### 2. Update inventory

Add the `mon` group with `mon-01` and `ansible_host: 10.10.10.30`.

### 3. Add new playbooks and templates

Copy into your ansible workspace:
- `playbooks/node_exporter.yml` — installs on all VMs
- `playbooks/monitoring.yml` — Prometheus + Grafana on mon-01
- `templates/prometheus.yml.j2` — scrape targets from playbook vars
- `templates/grafana-datasource.yml` — Prometheus as default data source
- `templates/grafana-dashboard-provider.yml` — file-based dashboard loading
- `templates/node-overview.json` — pre-built CPU/memory/disk/network dashboard

Update `site.yml` to import `node_exporter.yml` and `monitoring.yml`.

### 4. Apply

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 5. Verify

```bash
# All exporters are running
curl -s http://10.10.10.10:9100/metrics | grep node_cpu
curl -s http://10.10.10.12:9100/metrics | grep node_memory

# Prometheus sees all 5 targets
curl -s http://10.10.10.30:9090/api/v1/targets | python3 -m json.tool | grep instance

# Grafana is up
curl -s http://10.10.10.30:3000 | head -5

# HAProxy still works
curl http://10.10.10.10/items
```

Open `http://10.10.10.30:3000` in a browser.  The "Node Overview" dashboard
should be pre-loaded.

### 6. Explore Prometheus

```bash
# Query CPU usage across all nodes
curl "http://10.10.10.30:9090/api/v1/query?query=100-(avg+by(instance)(irate(node_cpu_seconds_total\{mode=\"idle\"\}[5m]))*100)"

# Query memory available
curl "http://10.10.10.30:9090/api/v1/query?query=node_memory_MemAvailable_bytes"
```

## Verify
```bash
curl -s http://10.10.10.30:9090/api/v1/targets | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(f\"{t['labels']['instance']} {t['health']}\")
"
# Expected: 5 targets, all health=up
```

## Gotchas
- **Prometheus needs enough disk space on mon-01** — time-series data grows
  over time.  The VM has a 10 GB disk; Prometheus retention is 15 days by
  default (`--storage.tsdb.retention.time=15d`).  For a local lab this is
  more than enough.
- **node_exporter listens on all interfaces** — no authentication.  In
  production you'd restrict with firewall rules or a reverse proxy.  For
  the lab, the isolated `lab-net` network is sufficient.
- **Grafana anonymous auth is off by default** — you may need to log in with
  `admin/admin` on first visit.  To enable anonymous access, add to
  `/etc/grafana/grafana.ini`:
  ```
  [auth.anonymous]
  enabled = true
  ```
- **Dashboard provisioning is file-based** — to update the dashboard, edit
  `node-overview.json` and re-run the playbook.  Grafana watches the
  provisioning directory automatically (polling, not inotify).
