# Concepts — containerization with Docker

## Why Docker after bare-metal?

Moving from systemd services to containers teaches:

1. **Image vs. process** — a Docker image is a packaged filesystem with
   dependencies baked in.  No `pip install` on the VM.  The `Dockerfile`
   is the build recipe.
2. **Isolation** — containers have their own filesystem, network namespace,
   and process tree.  Two API instances can't interfere with each other.
3. **Declarative infrastructure** — `docker-compose.yml` describes the
   desired state: 3 services, 2 exposed ports, 1 named volume.  Ansible
   (or `docker compose up`) reconciles it.
4. **Portability** — the same `compose.yml` runs on a developer laptop,
   a CI runner, or a production server.

## Dockerfile

```dockerfile
FROM python:3.12-slim       # base image — minimal Python 3.12
WORKDIR /app                 # set working directory
COPY requirements.txt .      # copy dependencies first (layer caching)
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .               # copy app code
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Layer caching: Docker rebuilds only from the first changed instruction.  If
`requirements.txt` hasn't changed, the `pip install` step is cached and
skipped on rebuild.  If `main.py` changed, only the last `COPY` + `CMD`
are re-executed.

## docker-compose.yml

### Services

```yaml
services:
  postgres:
    image: postgres:16          # pull official image from Docker Hub
    environment:                 # inject env vars (creates DB + user on first start)
      POSTGRES_DB: labdb
      POSTGRES_USER: labuser
      POSTGRES_PASSWORD: labpass
    volumes:
      - pgdata:/var/lib/postgresql/data   # named volume — data survives container restart
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql  # auto-run on first start
    ports:
      - "5432:5432"              # host:container
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U labuser -d labdb"]
      interval: 5s
      retries: 10

  api_1:
    build: .                     # build from Dockerfile in current directory
    environment:
      DB_HOST: postgres          # service name = DNS hostname inside compose network
      DB_NAME: labdb
      DB_USER: labuser
      DB_PASSWORD: labpass
    ports:
      - "8000:8000"
    depends_on:
      postgres:
        condition: service_healthy  # wait for PG healthcheck to pass

  api_2:
    build: .                     # same image, different container
    ...
    ports:
      - "8001:8000"
```

### Docker Compose networking

Containers in the same compose file are on a **default bridge network**
named `<project>_default`.  Services can reach each other by **service name**
as a DNS hostname.  `DB_HOST: postgres` resolves to the PostgreSQL container's
IP — no need for separate VMs or static IPs.

### Named volumes

```yaml
volumes:
  pgdata:
```

Named volumes persist across `docker compose down`.  To reset:
```bash
docker compose down -v    # deletes named volumes
```

### Health checks

`depends_on: postgres: condition: service_healthy` means the API containers
wait for PostgreSQL to pass its `pg_isready` check (10 retries × 5s = 50s max)
before starting.  This replaces the old Ansible task ordering (first run
postgresql.yml, then fastapi.yml).

### `--wait` flag

`docker compose up -d --wait` blocks until all containers with health checks
report healthy.  Useful in Ansible: the task won't return until the stack is
ready, avoiding race conditions between compose and subsequent playbooks.

## init.sql — auto-seeding

The `postgres:16` image has a built-in mechanism: any `.sql` file placed in
`/docker-entrypoint-initdb.d/` is executed alphabetically on **first start**
only (when the data directory is empty).  Our `init.sql` creates the `items`
table and inserts seed data.

If you need to re-seed after the volume exists:
```bash
docker compose exec postgres psql -U labuser -d labdb -c "INSERT INTO items ..."
```

## HAProxy reconfiguration

The backend servers changed from separate VMs to different ports on one VM:

```
Before:  server api-01 10.10.10.11:8000 check
         server api-02 10.10.10.13:8000 check

After:   server api-1 10.10.10.11:8000 check
         server api-2 10.10.10.11:8001 check
```

The Jinja2 template (`haproxy.cfg.j2`) doesn't change — only the playbook
vars list is updated.  This is exactly the modularity that templating buys.

## Docker vs systemd — what changed

| | Before (systemd) | After (Docker) |
|---|---|---|
| App install | `pip install` via Ansible, virtualenv | `pip install` in Dockerfile, baked into image |
| Process management | `fastapi.service` with `Restart=always` | Docker restart policy (`restart: unless-stopped` by default in compose) |
| Port assignment | API processes on separate VMs | Containers on same VM, different host ports (8000, 8001) |
| Database config | `lineinfile` in pg_hba.conf, `GRANT` SQL | `environment:` vars + `init.sql` |
| Logging | `journalctl -u fastapi` | `docker compose logs api_1` |
| Updates | Re-run Ansible playbook | `docker compose build && docker compose up -d` |
| Rollback | Redeploy previous app version | `docker compose up -d` with previous image tag |

## Why three services on one VM?

In production, you'd typically run one container per VM (or per pod in k8s)
for resource isolation and security.  In this lab, consolidation demonstrates
that:
- Docker's network isolation replaces the need for separate VMs for the
  same logical service tier
- Multiple instances of the same service can share a VM via different ports
- The HAProxy load balancer works regardless of whether backends are on
  separate VMs or different ports on the same VM
