# 06 k3s

Goal: two-node k3s cluster running PostgreSQL and FastAPI.

## Run

```bash
make pool    # once per host
make render STAGE=06-k3s
cd infra/terraform
terraform init
terraform apply
cd ../ansible
ansible-playbook playbooks/site.yml
```

`make render` deletes `infra/`. Destroy the current stage first if one is
running.

VMs: web-01 10.10.10.10, mon-01 10.10.10.30, k3s-master 10.10.10.40,
k3s-worker 10.10.10.41. This stage removes app-01.

## Verify

```bash
ssh ubuntu@10.10.10.40 'sudo k3s kubectl get nodes'
ssh ubuntu@10.10.10.40 'sudo k3s kubectl get pods,svc -n lab'
curl -s http://10.10.10.10/items
```

Expected: two nodes Ready, postgres-0 Running, two fastapi pods Running, and
the API returns the three items through HAProxy.

Scale the API:

```bash
ssh ubuntu@10.10.10.40 'sudo k3s kubectl scale deployment fastapi -n lab --replicas=4'
```

Notes: Docker on the k3s nodes only builds the FastAPI image. k3s runs it with
containerd. HAProxy targets NodePort `30000` on both nodes.
