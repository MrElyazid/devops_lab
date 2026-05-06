# 03 — HAProxy load balancing

## Goal
Add a second API server (`api-02`) and replace Nginx with HAProxy on `web-01`,
load balancing requests across both backends with health checks.

## Prerequisites
- Recipe 02 completed (3 VMs, PostgreSQL, FastAPI, Nginx all working)

## Architecture

```
                         HAProxy (web-01 :80, stats :8404)
                        /                                 \
                 roundrobin                           roundrobin
                      ▼                                       ▼
          api-01 (:8000)                              api-02 (:8000)
                      \                                      /
                       ▼                                    ▼
                              db-01 (:5432)
```

Both API servers query the same PostgreSQL database.  HAProxy distributes
incoming requests with round-robin and verifies each backend is healthy by
polling `GET /items` every 2 seconds.

## Steps

### 1. Add api-02 VM

Copy `recipes/03-haproxy/terraform/vm-api-02.tf` into `infra/terraform/`,
update `outputs.tf` from the recipe, then:

```bash
cd infra/terraform
terraform apply
```

Verify:

```bash
ssh ubuntu@10.10.10.13 hostname   # api-02
```

### 2. Update inventory

Add `api-02` to `api` group in `inventory/hosts.yml`.

### 3. Add HAProxy playbook

Copy `recipes/03-haproxy/ansible/playbooks/haproxy.yml` and the template
`ansible/templates/haproxy.cfg.j2` into your workspace.  Update `site.yml`
to import `haproxy.yml` instead of `nginx.yml`.

### 4. Apply

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 5. Verify load balancing

```bash
# Hit the same endpoint multiple times — responses should alternate
for i in $(seq 1 6); do curl -s http://10.10.10.10/items | head -1; done

# Check the HAProxy stats page
http://10.10.10.10:8404
```

### 6. Test failover

```bash
# Stop one API server
ssh ubuntu@10.10.10.11 sudo systemctl stop fastapi

# All requests now go to api-02
curl http://10.10.10.10/items

# Bring it back
ssh ubuntu@10.10.10.11 sudo systemctl start fastapi
```

## Verify
```bash
# Both backends are UP in the stats page
curl -s http://10.10.10.10:8404 | grep -o "UP"
# Expected: UP appears twice (once per backend)
```

## Gotchas
- **HAProxy and Nginx both want port 80** — the playbook stops and disables
  Nginx before installing HAProxy.  If you run the haproxy playbook alone
  without stopping Nginx first, it will fail to bind.
- **HAProxy health checks need a real endpoint** — `option httpchk GET /items`
  verifies the backend serves our API.  If the FastAPI service is down on a
  backend, HAProxy marks it DOWN and stops sending traffic to it.
- **The `fastapi.yml` playbook already handles both api-01 and api-02** because
  it targets the `api` group.  No changes needed.
- **Stats page at port 8404** — no authentication, accessible from any VM on
  the lab network.  In production you'd add basic auth and restrict access.
