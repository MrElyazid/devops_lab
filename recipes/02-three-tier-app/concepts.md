# Concepts — three-tier app with Ansible

## Ansible basics

**Inventory**: A YAML file listing hosts, grouped by role.  Our static
inventory defines three groups (`db`, `api`, `web`) with hardcoded IPs from
Terraform's output.

**Playbook**: A YAML file declaring a list of **plays**.  Each play targets a
host group and runs a list of **tasks**.  Tasks are executed in order and
should be idempotent (running twice produces the same result).

**Modules**: Built-in tools that Ansible runs on remote hosts — `apt` (install
packages), `copy` (upload files), `template` (render Jinja2 templates),
`systemd` (manage services), `lineinfile` (edit config files),
`postgresql_db` (create databases).

**Facts**: Ansible gathers system info (`ansible_facts`) at the start of each
play.  Playbooks can reference these (e.g., `ansible_distribution`).

### Inventory structure

```yaml
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

- `children` creates group hierarchies
- `ansible_host` overrides the hostname used for SSH
- Group-level `vars` are shared by all hosts
- `all.vars` apply to every host in the inventory

### Playbook structure

```yaml
- name: Configure PostgreSQL
  hosts: db
  become: yes
  vars:
    pg_version: 16
  tasks:
    - name: Install PostgreSQL
      apt:
        name: "postgresql-{{ pg_version }}"
        state: present
    ...
```

- `hosts: db` — runs only on hosts in the `db` group
- `become: yes` — escalates to root (needed for package installs)
- `vars:` — play-level variables (accessible as `{{ pg_version }}`)

### Running Ansible

```bash
# Check connectivity
ansible all -i inventory/hosts.yml -m ping

# Run a single playbook
ansible-playbook -i inventory/hosts.yml playbooks/postgresql.yml

# Run the master playbook
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## How the three-tier app works

### PostgreSQL (`db-01`)

Ansible installs PostgreSQL, creates a database `labdb` and user `labuser`,
then creates a table and seeds it with test data.

**Why PostgreSQL and not SQLite?** Real apps use network-accessible databases.
The PM -> API -> DB pattern over TCP/IP is what you'll see in production.

Key Ansible tasks:
1. `apt: name=postgresql-16` — install
2. `postgresql_db: name=labdb` — create database
3. `postgresql_user: name=labuser password=...` — create user with password
4. `postgresql_query: query=CREATE TABLE ...` — create schema
5. `postgresql_query: query=INSERT INTO ...` — seed data
6. `lineinfile`: set `listen_addresses = '*'` in `postgresql.conf`
7. `lineinfile`: add `host all all 10.10.10.0/24 md5` to `pg_hba.conf`
8. `systemd: name=postgresql state=restarted` — apply config changes

### FastAPI (`api-01`)

A Python web server using FastAPI + uvicorn, managed by systemd.

The app (`main.py`):
- Connects to PostgreSQL using `psycopg2`
- DB credentials come from environment variables set in the systemd unit
- Exposes `GET /items` (list all) and `GET /items/{id}` (single item)
- Returns JSON

Key Ansible tasks:
1. `apt: name=python3-venv,python3-pip` — Python tooling
2. `copy`: upload `main.py` and `requirements.txt` to `/opt/fastapi/`
3. `pip`: install dependencies in a virtualenv
4. `template`: render `fastapi.service` from Jinja2 (injecting DB host/port/creds)
5. `copy`: install the unit file to `/etc/systemd/system/`
6. `systemd`: daemon-reload, enable, start

The systemd unit:
```ini
[Unit]
Description=FastAPI app
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/fastapi
Environment="DB_HOST=10.10.10.12"
Environment="DB_NAME=labdb"
Environment="DB_USER=labuser"
Environment="DB_PASSWORD=labpass"
ExecStart=/opt/fastapi/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

### Nginx (`web-01`)

A reverse proxy that forwards HTTP requests to the FastAPI backend.

Key Ansible tasks:
1. `apt: name=nginx` — install
2. `template`: render nginx config from Jinja2 (injecting API server IP)
3. `copy`: install config to `/etc/nginx/sites-available/fastapi`
4. `file`: symlink to `sites-enabled`
5. `file`: remove default site symlink
6. `systemd`: restart nginx

The Nginx config:
```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://10.10.10.11:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Why IPs not DNS

We use hardcoded IPs in inventory vars and systemd environment files.
dnsmasq DNS only works for DHCP-assigned hosts — static-IP VMs don't register.
Using IPs is simpler for a local lab and teaches the same Ansible patterns.

## systemd in a DevOps lab

Using systemd units (not Docker, not screen/tmux) is the standard way to run
persistent services on Linux.  The `fastapi.service` unit:

- `Type=simple` — the process stays in the foreground
- `Restart=always` — auto-restarts on crash
- `Environment=` — injects config without config files
- `WantedBy=multi-user.target` — starts at boot

View logs: `journalctl -u fastapi -f`
Check status: `systemctl status fastapi`

## Terraform patterns for multiple VMs

The three VM configs are near-identical: different IPs and hostnames, same
machine spec.  In production you'd use `count`, `for_each`, or a module to
avoid copy-paste.  We keep them explicit here so every attribute is visible
and debuggable.
