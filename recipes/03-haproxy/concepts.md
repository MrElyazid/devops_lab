# Concepts — HAProxy load balancing

## What HAProxy is

HAProxy (High Availability Proxy) is a TCP/HTTP load balancer and reverse
proxy.  Its job: accept incoming connections and distribute them across
multiple backend servers.  It's been the industry standard for over 20 years.

## Why not Nginx for load balancing?

Nginx can load balance too (`upstream` blocks).  The differences:

| | HAProxy | Nginx |
|---|---|---|
| Primary strength | Layer 4/7 load balancing | Web serving + reverse proxy |
| Health checks | Built-in, rich (`option httpchk`, `tcp-check`) | Passive only (`max_fails`) |
| Stats page | Built-in live dashboard (`stats enable`) | Requires nginx-mod or 3rd-party |
| SSL termination | Yes, but historically weaker | Native, performant |
| Backend granularity | Per-server weights, maxconn, slow-start | Basic weight |
| Protocol support | TCP + HTTP | HTTP/HTTPS only (TCP requires stream module) |

In our lab: we want a dedicated load balancer with live health-check stats.
HAProxy's stats page alone makes it the right tool here — you can watch
backends go UP/DOWN in real time.

## How our config works

The full config is in `haproxy.cfg.j2` — an Ansible Jinja2 template that
gets rendered with the list of backend servers.

### Global section

```
global
    daemon              # Run as a background service
    maxconn 256         # Max concurrent connections
```

### Defaults section

```
defaults
    mode http           # Layer 7 (HTTP-aware) mode
    timeout connect 5s  # Max time to establish a TCP connection to a backend
    timeout client 30s  # Max time to wait for a client to send data
    timeout server 30s  # Max time to wait for a backend to respond
```

- `mode http` — HAProxy inspects HTTP headers (needed for cookie-based
  persistence, URL-based routing, HTTP health checks).
- `mode tcp` would pass raw TCP without parsing — used for databases,
  SSH, any non-HTTP traffic.

### Frontend

```
frontend http-in
    bind *:80                  # Listen on all interfaces, port 80
    default_backend api_servers # Send unmatched traffic to this backend
```

A frontend is the entry point.  You can have multiple frontends listening on
different ports or IPs.  ACLs (Access Control Lists) can route traffic to
different backends based on URL path, Host header, method, etc.

### Backend

```
backend api_servers
    balance roundrobin
    option httpchk GET /items
    server api-01 10.10.10.11:8000 check
    server api-02 10.10.10.13:8000 check
```

- `balance roundrobin` — each new connection goes to the next server in
  sequence: api-01 → api-02 → api-01 → ...
- `option httpchk GET /items` — every 2 seconds (default `inter`), HAProxy
  sends `GET /items HTTP/1.0` to each backend.  A 2xx/3xx response means
  healthy; anything else (or timeout) marks the server DOWN.
- `check` — enables health checking for this server.  Without it, the server
  is always considered UP.

**Load balancing algorithms**:

| Algorithm | Behavior |
|-----------|----------|
| `roundrobin` | Rotation, respects per-server `weight` |
| `leastconn` | Send to server with fewest active connections |
| `source` | Hash client IP → always same backend (session stickiness) |
| `uri` | Hash URL path → cache-friendly |
| `first` | Always use first available server (failover, not load balance) |

### Stats page

```
listen stats
    bind *:8404
    stats enable
    stats uri /
    stats refresh 10s
```

A `listen` block is a combined frontend+backend — it both accepts connections
and serves them itself.  The stats page shows:

- Server status: UP (green) / DOWN (red)
- Sessions: current, max, total per server
- Queued requests, errors, warnings
- Bytes in/out
- Health check status: last check result, transition count

Access it at: `http://10.10.10.10:8404`

## Jinja2 template injection

Ansible renders the template before uploading it.  The playbook defines:

```yaml
vars:
  api_servers:
    - { name: api-01, host: 10.10.10.11, port: 8000 }
    - { name: api-02, host: 10.10.10.13, port: 8000 }
```

The template iterates:

```jinja2
{% for srv in api_servers %}
    server {{ srv.name }} {{ srv.host }}:{{ srv.port }} check
{% endfor %}
```

Which produces:

```
    server api-01 10.10.10.11:8000 check
    server api-02 10.10.10.13:8000 check
```

Adding a third backend is a one-line change to `api_servers` in the playbook.
No template changes needed.

## Failover behavior

When a backend fails a health check (3 consecutive failures by default),
HAProxy marks it DOWN and stops sending traffic to it.  Existing connections
complete; new connections go to healthy servers.

When the backend recovers (2 consecutive successful checks), it's marked UP
and rejoins the rotation.  This is transparent to clients — no dropped
requests during the transition (except for in-flight requests to the failing
backend, which may return 5xx).

You can test this:

```bash
# Kill a backend
ssh ubuntu@10.10.10.11 sudo systemctl stop fastapi

# Watch the stats page — api-01 goes RED
# All curl calls now only hit api-02

# Bring it back
ssh ubuntu@10.10.10.11 sudo systemctl start fastapi

# Watch it go GREEN again
```

## HAProxy vs cloud load balancers

In cloud environments, you'd typically use AWS ALB/NLB, GCP Cloud LB, or
Azure Load Balancer.  HAProxy is the on-premises/open-source equivalent that
those cloud services are built on.  Understanding HAProxy means understanding
how any L4/L7 load balancer works at the protocol level.
