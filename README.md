# devops_lab

A local DevOps practice environment using QEMU/KVM.
Provisions VMs with Terraform, configures them with Ansible, and
progressively introduces Docker and k3s — all on one machine.

## Stack

- **Terraform** — `dmacvicar/libvirt` provider (v0.9.x) for VM provisioning
- **Ansible** — configuration management and deployment
- **HAProxy** — TCP/HTTP load balancer
- **Prometheus + Grafana** — metrics collection and dashboards
- **Docker / docker compose** — containerized application stack
- **k3s** — lightweight Kubernetes distribution

## Recipes

Each recipe is a self-contained exercise that builds on the previous one.

| # | Recipe | What you build |
|---|--------|---------------|
| 01 | [Boot a VM](./recipes/01-boot-vm/) | Terraform + libvirt: network, storage pool, cloud image, cloud-init, single VM with SSH |
| 02 | [Three-tier app](./recipes/02-three-tier-app/) | Nginx reverse proxy, FastAPI + PostgreSQL, Ansible static inventory and playbooks |
| 03 | [HAProxy](./recipes/03-haproxy/) | Load balancing with health checks and stats page, multiple backends |
| 04 | [Monitoring](./recipes/04-monitoring/) | Prometheus + Grafana, node_exporter on all VMs, pre-provisioned dashboard |
| 05 | [Docker](./recipes/05-docker/) | Containerize the app stack with Docker and docker compose |
| 06 | [k3s](./recipes/06-k3s/) | Multi-node Kubernetes cluster: StatefulSet, Deployment, Services, NodePort |

Each recipe has a `README.md` (step-by-step instructions) and a `concepts.md` (deep-dive explanation of the technologies used).
The `infra/` directory is the live workspace. `terraform apply` and
   `ansible-playbook` commands are run from there. The `recipes/` directory
   contains reference copies of everything you should end up with.
