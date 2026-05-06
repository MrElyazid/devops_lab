# 02 — Three-tier app with Ansible

## Goal
Extend the lab from 1 VM to 3, then use Ansible to configure them as a
three-tier web application: Nginx → FastAPI → PostgreSQL.

## Prerequisites
- Recipe 01 completed (base pool, network, web-01 exists)
- `ansible` installed on the host

## Architecture

```
10.10.10.10 (web-01)     10.10.10.11 (api-01)     10.10.10.12 (db-01)
 ┌──────────┐              ┌─────────────┐          ┌──────────────┐
 │   Nginx  │              │   FastAPI   │          │ PostgreSQL   │
 │ proxy:80 │──────────────│  uvicorn   │──────────│ items table  │
 │          │  proxy_pass  │   :8000     │  5432    │              │
 └──────────┘              └─────────────┘          └──────────────┘
```

Requests flow: `curl http://10.10.10.10/items` → Nginx proxies to
`api-01:8000` → FastAPI queries `db-01:5432` → returns JSON.

## Steps

### 1. Add two VM definitions

Create `infra/terraform/vm-api-01.tf` and `infra/terraform/vm-db-01.tf`.
Follow the same pattern as `vm-web-01.tf` but with different IPs and hostnames:

- `api-01 / 10.10.10.11`
- `db-01 / 10.10.10.12`

Reference copies are in `recipes/02-three-tier-app/terraform/`.

### 2. Update outputs

Add the new IPs to `infra/terraform/outputs.tf`.

### 3. Apply

```bash
cd infra/terraform
terraform apply
```

Verify all 3 VMs are running:

```bash
virsh -c qemu:///system list --all
ssh ubuntu@10.10.10.10 hostname  # web-01
ssh ubuntu@10.10.10.11 hostname  # api-01
ssh ubuntu@10.10.10.12 hostname  # db-01
```

### 4. Create Ansible inventory

Copy `recipes/02-three-tier-app/ansible/` into the project root (or run from
within the recipe directory):

```yaml
# ansible/inventory/hosts.yml
all:
  children:
    web:
      hosts:
        web-01:
          ansible_host: 10.10.10.10
    api:
      hosts:
        api-01:
          ansible_host: 10.10.10.11
    db:
      hosts:
        db-01:
          ansible_host: 10.10.10.12
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/lab_key
```

### 5. Write the playbooks

Four playbooks that build on each other. Run them all with `site.yml` or
individually to test as you go.

```bash
# Full run
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Or step by step
ansible-playbook ... playbooks/postgresql.yml
ansible-playbook ... playbooks/fastapi.yml
ansible-playbook ... playbooks/nginx.yml
```

Reference copies of all playbooks and the app source are in
`recipes/02-three-tier-app/ansible/` and `recipes/02-three-tier-app/app/`.

### 6. Verify

```bash
# Direct to API
curl http://10.10.10.11:8000/items
# Expected: [{"id":1,"name":"Widget","price":9.99}, ...]

# Through Nginx
curl http://10.10.10.10/items
# Expected: same JSON — Nginx proxying works
```

## Verify
```bash
curl -s http://10.10.10.10/items | python3 -m json.tool
# Should show 3 seeded items with id, name, price
```

## Gotchas
- **Ansible must run from the project root** (or wherever you place `ansible/`
  and `app/`). The playbooks use `copy: src=../../app/main.py` relative paths.
- **PostgreSQL apt install requires `apt update` first** — the playbook does this.
- **systemd units need `daemon_reload: yes`** after writing the service file.
- **FastAPI environment variables** are set in the systemd unit file (`Environment=`).
- **The app is copied via Ansible** — no git clone needed, just `copy` the source.
- **You need Ansible on the host**.  The VMs don't need it.
