# 06 — k3s Kubernetes cluster

## Goal
Replace the Docker Compose stack on `app-01` with a multi-node k3s Kubernetes
cluster.  Deploy PostgreSQL and FastAPI via Kubernetes manifests (StatefulSet,
Deployment, Service, ConfigMap).  HAProxy load-balances to the NodePort service
exposed on both k3s nodes.

## Prerequisites
- Recipe 05 completed (4 VMs, Docker + HAProxy + monitoring working)

## Architecture

```
BEFORE (4 VMs)                          AFTER (5 VMs)

app-01 ✕  (docker compose removed)
          → replaced by →               k3s-master (10.10.10.40)  control plane + workloads
                                         k3s-worker (10.10.10.41)  workloads only

web-01 ✓  (HAProxy :80, :8404)          web-01 ✓  (backends → NodePort :30000)
mon-01 ✓  (Prometheus :9090, :3000)     mon-01 ✓  (4 scrape targets)
```

### Traffic flow

```
HAProxy (web-01 :80)
    │
    ├──→ k3s-master:30000 (NodePort) ── iptables ──→ fastapi pod (any node)
    │
    └──→ k3s-worker:30000 (NodePort) ── iptables ──→ fastapi pod (any node)
```

## Steps

### 1. Remove app-01, add k3s VMs

```bash
cd infra/terraform
rm vm-app-01.tf
cp recipes/06-k3s/terraform/vm-{k3s-master,k3s-worker}.tf .
# Update outputs.tf from recipe
terraform apply
# Destroys app-01, creates 2 new VMs
```

### 2. Update inventory

Replace `app` group with `k3s_master` and `k3s_worker` groups (see recipe).

### 3. Update playbooks

- Copy `k3s.yml` from recipe — replaces `docker.yml`
- Update `haproxy.yml` vars: `api_servers` → `k3s-master:30000` + `k3s-worker:30000`
- Update `monitoring.yml` targets: 4 nodes
- Update `site.yml` to import `k3s.yml`

### 4. Copy k8s manifests

Copy the `k8s/` and `app/` directories alongside `ansible/`.

### 5. Apply

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

The `k3s.yml` playbook:
1. Installs k3s server on master
2. Installs Docker on master, builds the FastAPI image, imports into containerd
3. Copies k8s manifests to master
4. Fetches the join token
5. Installs k3s agent on worker (joins cluster)
6. Waits for both nodes to be Ready
7. `kubectl apply -f k8s/` — deploys namespace, PostgreSQL StatefulSet, FastAPI Deployment
8. Waits for pods to be Ready

### 6. Verify

```bash
# Nodes are Ready
ssh ubuntu@10.10.10.40 k3s kubectl get nodes

# Pods running in the lab namespace
ssh ubuntu@10.10.10.40 k3s kubectl get pods,svc -n lab

# API through HAProxy (load-balanced across NodePorts)
for i in $(seq 1 6); do curl -s http://10.10.10.10/items | head -1; done

# Scale the deployment
ssh ubuntu@10.10.10.40 k3s kubectl scale deployment fastapi -n lab --replicas=4
ssh ubuntu@10.10.10.40 k3s kubectl get pods -n lab -l app=fastapi
```

## Verify
```bash
ssh ubuntu@10.10.10.40 "k3s kubectl get pods,svc -n lab -o wide"
# Expected: postgres-0 Running, 2x fastapi-* Running, postgres ClusterIP, fastapi NodePort
```

## Gotchas
- **k3s uses containerd, not Docker** — images must be imported into
  containerd (`k3s ctr images import`).  Docker is installed only for
  building the image on the master node.
- **`imagePullPolicy: IfNotPresent`** — the FastAPI manifest uses this because
  the image is imported manually, not pulled from a registry.  Without it,
  k3s would try to pull `fastapi:latest` from Docker Hub and fail.
- **Service DNS** — within the cluster, `postgres.lab.svc.cluster.local`
  resolves to the PostgreSQL Service ClusterIP.  The ConfigMap injects this
  into the FastAPI pods via `envFrom`.
- **NodePort 30000** — the default NodePort range in k3s is 30000-32767.
  `nodePort: 30000` is explicitly specified so HAProxy targets a known port.
- **k3s token expires** — the node token fetched from
  `/var/lib/rancher/k3s/server/node-token` persists until the master is
  rebuilt.  Ansible caches it via `slurp` + `hostvars`.
