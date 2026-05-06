# Concepts — monitoring with Prometheus + Grafana

## Why monitoring matters

Without monitoring, you find out your API is down when a user complains.
With monitoring, you get a dashboard showing CPU/memory/disk trends, alerting
before the server fills its disk or runs out of memory, and historical data
to correlate issues ("the outage started exactly when the deploy happened").

Prometheus + Grafana is the de-facto open-source monitoring stack.

## Prometheus — pull-based metrics

Prometheus is a **time-series database** with a built-in scraper.  It does NOT
receive pushed metrics — it **pulls** them from HTTP endpoints.

### The pull model

```
Prometheus (15s interval)
    │
    │ HTTP GET /metrics
    ▼
node_exporter (:9100)
    returns plaintext Prometheus format:
    node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
    node_memory_MemTotal_bytes 4194304000
    node_network_receive_bytes_total{device="enp1s0"} 987654
```

Advantages of pull over push:
- Dead targets are immediately visible (scrape fails → target DOWN)
- No agent needs to know where Prometheus lives
- Security: only Prometheus needs network access to all targets, not the reverse

### Scrape configuration

```yaml
global:
  scrape_interval: 15s       # poll every 15 seconds

scrape_configs:
  - job_name: nodes
    static_configs:
      - targets:
          - 10.10.10.10:9100
          - 10.10.10.11:9100
          - 10.10.10.12:9100
          - 10.10.10.13:9100
          - 10.10.10.30:9100
```

Each target is an HTTP endpoint.  Prometheus appends `/metrics` and fetches.
The `job_name` is a label added to all metrics from these targets, used for
grouping in queries.

### PromQL — query language

```
# CPU usage per instance (0-100%)
100 - (avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage percentage for root partition
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Network receive rate (bytes/sec)
rate(node_network_receive_bytes_total{device!="lo"}[5m])
```

Key concepts:
- `irate()` — instant per-second rate (good for volatile metrics like CPU)
- `rate()` — average per-second rate over a window (good for stable metrics)
- `by(instance)` — group results by the `instance` label (IP:port)
- `{}` — label filters (e.g., `mode="idle"`, `device!="lo"`)

### Check targets in Prometheus UI

```bash
# All targets and their health
http://10.10.10.30:9090/targets

# Or via API
curl http://10.10.10.30:9090/api/v1/targets
```

## node_exporter

A small Go binary that exposes Linux system metrics in Prometheus format on
port 9100.  Installed from Ubuntu's `prometheus-node-exporter` package.

Metrics it exposes:
- `node_cpu_seconds_total` — CPU time per mode (idle, system, user, iowait)
- `node_memory_MemTotal_bytes`, `node_memory_MemAvailable_bytes` — memory
- `node_filesystem_avail_bytes`, `node_filesystem_size_bytes` — disk
- `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` — network
- `node_disk_read_bytes_total`, `node_disk_write_bytes_total` — disk I/O
- `node_load1`, `node_load5`, `node_load15` — system load

No configuration needed — it just works out of the box.

## Grafana — visualization

Grafana is a dashboarding tool.  It connects to data sources (Prometheus being
the most common) and renders charts, gauges, tables, and heatmaps.

### Provisioning (what we automate)

Grafana supports file-based provisioning — drop YAML/JSON files into specific
directories and Grafana imports them on startup:

```
/etc/grafana/provisioning/
├── datasources/
│   └── prometheus.yml        # "Here's your Prometheus"
└── dashboards/
    ├── provider.yml           # "Look in this directory for dashboards"
    └── node-overview.json     # actual dashboard definition
```

**Datasource config:**
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy              # Grafana proxies requests to Prometheus
    url: http://localhost:9090
    isDefault: true
```

**Dashboard provider:**
```yaml
apiVersion: 1
providers:
  - name: default
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

This tells Grafana: "watch this directory for `.json` files and auto-import them."

### Our dashboard

The `node-overview.json` has 4 panels:

| Panel | Type | PromQL query |
|-------|------|-------------|
| CPU Usage | Gauge (per instance) | `100 - avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Memory Usage | Gauge (per instance) | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Disk Usage (/) | Gauge (per instance) | `100 - (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100` |
| Network Traffic | Time series | `rate(node_network_receive_bytes_total[5m])` + `rate(node_network_transmit_bytes_total[5m])` |

Thresholds: green < 80%, orange 80-90%, red > 90%.

### Anonymous access

By default, Grafana requires login (`admin/admin`).  For the lab, you can
enable anonymous access by editing `/etc/grafana/grafana.ini`:

```ini
[auth.anonymous]
enabled = true
org_role = Viewer
```

This is not automated in the playbook — do it manually if desired, or add it
as a `lineinfile` task.

## How Jinja2 generates the Prometheus config

The playbook defines:
```yaml
vars:
  node_targets:
    - 10.10.10.10:9100
    - 10.10.10.11:9100
    ...
```

The template iterates:
```jinja2
{% for target in node_targets %}
          - "{{ target }}"
{% endfor %}
```

Rendering:
```yaml
      - targets:
          - "10.10.10.10:9100"
          - "10.10.10.11:9100"
          ...
```

When adding a new VM, add its `host:9100` to the `node_targets` list — one
change, no template edits needed.

## Why not Alertmanager / Loki?

- **Alertmanager** — defines alert rules (e.g., "disk > 90%") and sends
  notifications (email, Slack, PagerDuty).  Valuable in production; skipped here
  to keep the exercise focused.
- **Loki** — log aggregation (Prometheus for logs).  Separately useful; adds
  another daemon and more complexity.

Both can be added later as standalone exercises if you want.
