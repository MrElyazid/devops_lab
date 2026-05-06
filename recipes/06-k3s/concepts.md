# Concepts — k3s Kubernetes

## Why k3s?

k3s is a lightweight Kubernetes distribution by Rancher (SUSE).  It's a
single ~60 MB binary that bundles:
- Kubernetes API server, controller-manager, scheduler
- containerd (container runtime)
- CoreDNS (service discovery)
- Traefik (ingress controller, not used in this lab)
- local-path-provisioner (for PersistentVolumeClaims)
- Flannel (overlay networking via VXLAN)

It runs on systems with as little as 512 MB RAM, making it ideal for a local lab.

## Kubernetes vs Docker Compose

| Concept | Docker Compose | Kubernetes |
|---------|---------------|------------|
| Unit of deployment | `service` in compose file | Pod (one or more containers) |
| Declaring desired state | `docker-compose.yml` | YAML manifests (Deployment, StatefulSet, etc.) |
| Replicas | `deploy: replicas: 2` | `spec.replicas: 2` in Deployment |
| Service discovery | Compose DNS (`postgres:5432`) | Service DNS (`postgres.namespace.svc.cluster.local`) |
| Persistent storage | Named volumes (`pgdata:`) | PersistentVolumeClaim + StorageClass |
| Health checks | `healthcheck:` in compose | `readinessProbe`, `livenessProbe` |
| Rolling updates | `docker compose up -d` rebuilds | `kubectl rollout restart` or changing the image |
| Self-healing | `restart: unless-stopped` | Controller loop: pod dies → recreated automatically |
| Scheduling | Everything on one host | Scheduler places pods across nodes based on resources |

## Kubernetes resources we use

### Namespace (`00-namespace.yml`)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab
```

Logical boundary that groups related resources.  All our manifests use
`namespace: lab` so they're isolated from `kube-system`.

### PersistentVolumeClaim (`postgres/01-pvc.yml`)

```yaml
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
```

A request for storage.  k3s ships with `local-path` StorageClass which
creates directories on the node.  The StatefulSet references this via
`volumeClaimTemplates` (not directly — that approach is different).

### ConfigMap (`postgres/02-configmap.yml`, `fastapi/01-configmap.yml`)

```yaml
kind: ConfigMap
metadata:
  name: fastapi-config
data:
  DB_HOST: "postgres.lab.svc.cluster.local"
  DB_NAME: "labdb"
```

Non-secret configuration injected into pods via `envFrom` or volume mounts.
The `postgres.lab.svc.cluster.local` is the cluster-internal DNS name:

```
<service-name>.<namespace>.svc.cluster.local
```

### Service — ClusterIP (`postgres/03-service.yml`)

```yaml
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

Internal IP accessible only within the cluster.  kube-proxy manages iptables
rules so traffic to `postgres:5432` reaches any pod with `app: postgres`.

### StatefulSet (`postgres/04-statefulset.yml`)

```yaml
kind: StatefulSet
metadata:
  name: postgres
spec:
  replicas: 1
  serviceName: postgres
  selector:
    matchLabels:
      app: postgres
  template: ...
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 1Gi
```

A StatefulSet is like a Deployment but:
- Pods have stable, predictable names (`postgres-0`, not `postgres-abc123`)
- Each pod gets its own PVC (created from `volumeClaimTemplates`)
- Scaling is ordered (0, then 1, then 2...)
- The PVC survives pod deletion and rescheduling to another node

Why StatefulSet and not Deployment for PostgreSQL?  Databases need stable
identity and persistent storage that follows the pod.  A Deployment would
create a new volume on every restart.

### Deployment (`fastapi/02-deployment.yml`)

```yaml
kind: Deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi
  template:
    spec:
      containers:
        - name: fastapi
          image: fastapi:latest
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: fastapi-config
          readinessProbe:
            httpGet:
              path: /items
              port: 8000
```

- `replicas: 2` — k3s ensures exactly 2 pods are always running
- `imagePullPolicy: IfNotPresent` — critical: we imported the image manually
- `readinessProbe` — k3s won't send traffic until `/items` returns 200
- `livenessProbe` — if the pod hangs, k3s restarts it

### Service — NodePort (`fastapi/03-service.yml`)

```yaml
kind: Service
spec:
  type: NodePort
  selector:
    app: fastapi
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30000
```

Exposes the service on every node's IP at port 30000.  kube-proxy ensures
that hitting any node's `:30000` reaches a healthy pod, even if that pod is
on a different node.

HAProxy backend: `10.10.10.40:30000` and `10.10.10.41:30000` — redundant
paths to the same service.

## The k3s installation flow

1. **Master**: `curl -sfL https://get.k3s.io | sh -`
   - Installs k3s binary
   - Generates TLS certificates
   - Starts API server on :6443
   - Creates node token at `/var/lib/rancher/k3s/server/node-token`
   - Runs etcd (embedded) for cluster state

2. **Worker**: `curl -sfL https://get.k3s.io | K3S_URL=https://master:6443 K3S_TOKEN=<token> sh -`
   - Installs k3s binary
   - Connects to master's API server
   - Joins the cluster as a worker node
   - Starts kubelet + kube-proxy

3. **Ansible orchestrates**: fetches the token from master via `slurp`,
   passes it to worker via `hostvars`.

## Image workflow

```
Dockerfile + main.py + requirements.txt
        │
        ▼
    docker build -t fastapi:latest .
        │
        ▼
    docker save | k3s ctr images import
        │
        ▼
    kubectl apply -f fastapi/02-deployment.yml
        │
        │ imagePullPolicy: IfNotPresent
        ▼
    Pod starts using imported image
```

Why not use a registry?  For a local lab, importing directly avoids setting
up Docker Hub credentials or a local registry.  In production, you'd push to
a registry and use `imagePullSecrets`.

## kubectl commands to know

```bash
k3s kubectl get nodes                      # cluster nodes
k3s kubectl get pods -n lab               # pods in lab namespace
k3s kubectl describe pod fastapi-xxx -n lab  # pod details + events
k3s kubectl logs fastapi-xxx -n lab       # container logs
k3s kubectl exec -it postgres-0 -n lab -- psql -U labuser -d labdb  # shell into pod
k3s kubectl scale deployment fastapi -n lab --replicas=4  # scale up
k3s kubectl rollout restart deployment fastapi -n lab     # rolling restart
```

## k3s vs kubeadm vs microk8s

| | k3s | kubeadm | microk8s |
|---|---|---|---|
| Install | Single curl command | Multi-step manual | snap install |
| Binary size | ~60 MB | Multiple binaries | Snap package |
| Runtime | containerd | Your choice | containerd |
| Default CNI | Flannel | None (you pick) | Calico |
| Best for | Edge/IoT, dev labs | Production clusters | Ubuntu dev environments |

In this lab, k3s was chosen for its zero-config setup — one command to get a
working control plane, and one command to join a worker.  No etcd config,
no CNI plugin selection, no certificate management.
