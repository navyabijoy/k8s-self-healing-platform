# Self-Healing EKS Cluster with Full Observability

> A production-grade project demonstrating Infrastructure as Code,
> Kubernetes, automated monitoring, and self-healing automation — running for **$0** on minikube.

---

## What This Project Does

1. **Provisions infrastructure as code** — Terraform modules for VPC, EKS, RDS, and IAM (production-ready, deployable to AWS)
2. **Runs a sample microservice** — Python FastAPI app with health checks, Prometheus metrics, and intentional failure endpoints for demos
3. **Monitors everything** — Prometheus collects metrics, Grafana draws dashboards, Alertmanager routes alerts
4. **Heals itself** — A Python bot receives alert webhooks and automatically fixes common problems (crash loops, OOM kills, high CPU)
5. **Documents like a real company** — SOP, incident RCA, and per-alert runbooks

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    minikube Cluster (local)                         │
│                                                                     │
│  Namespace: app                  Namespace: monitoring              │
│  ┌─────────────────────┐         ┌──────────────────────────────┐   │
│  │  demo-app (x2 pods) │         │  Prometheus                  │   │
│  │  ┌───────────────┐  │ scrape  │  Grafana                     │   │
│  │  │ /health       │──┼────────▶│  Alertmanager                │   │
│  │  │ /metrics      │  │         │  kube-state-metrics          │   │
│  │  │ /crash  ←demo │  │  alert  │  node-exporter               │   │
│  │  │ /load   ←demo │  │◀────────│                              │   │
│  │  └───────────────┘  │ webhook │  remediation-bot ──────────▶ │   │
│  │                     │         │  (auto-fixes alerts)         │   │
│  │  postgres (1 pod)   │         └──────────────────────────────┘   │
│  └─────────────────────┘                                            │
│                                                                     │
│  Ingress (nginx) ─── routes app.local → demo-app                    │
│  HPA ────────────── auto-scales 2→10 replicas on CPU/memory         │
└─────────────────────────────────────────────────────────────────────┘

Terraform Code (production-ready, not applied locally):
  modules/vpc   → VPC, subnets, IGW, NAT Gateway
  modules/eks   → EKS cluster, node groups, OIDC, add-ons
  modules/rds   → PostgreSQL, Secrets Manager, security groups
  modules/iam   → Cluster role, node role, IRSA roles
```

---

## Skills Demonstrated

| Area | Technology / Concept |
|---|---|
| **Infrastructure as Code** | Terraform modules, remote state, workspaces |
| **Containerization** | Multi-stage Docker builds, non-root user, health checks |
| **Kubernetes** | Deployments, Services, HPA, PDB, Ingress, RBAC, ServiceMonitor |
| **Observability** | Prometheus, Grafana dashboards, AlertManager, PromQL |
| **Self-Healing** | Python Kubernetes SDK, webhook-driven automation |
| **Documentation** | SOP, incident RCA, per-alert runbooks |
| **CI/CD** | GitHub Actions — Terraform validate, Docker build + scan + push |
| **Security** | IRSA (no credentials in pods), non-root containers, Secrets |

---

## Prerequisites

Install these on your laptop before starting:

```bash
# Check what you have
brew install minikube kubectl helm terraform docker

# Verify versions
minikube version   # >= 1.32
kubectl version    # >= 1.28
helm version       # >= 3.14
terraform version  # >= 1.6
docker version     # >= 24
```

---

## Quick Start (5 commands)

```bash
# 1. Clone the repo
git clone https://github.com/navyabijoy/k8s-self-healing-platform.git
cd k8s-self-healing-platform

# 2. Build Docker images inside minikube (no Docker Hub needed)
make build-minikube

# 3. Full stack setup (minikube + ingress + monitoring + app + bot)
make install-all

# 4. Open Grafana
make port-grafana
# → http://localhost:3000  (admin / grafana-admin-pass)

# 5. Trigger the self-healing demo!
make simulate-crash
# Watch the terminal and Grafana simultaneously
```

---

## Demo Scenarios

### Demo 1: Self-Healing a Crash Loop

```bash
# Terminal 1: Watch pods
make watch-pods

# Terminal 2: Trigger crashes
make simulate-crash
```

**What you'll see:**
1. Pod starts crashing and entering `CrashLoopBackOff`
2. Restart count climbs: 1, 2, 3, 4, 5...
3. Alertmanager fires `KubePodCrashLooping` alert
4. Remediation bot receives webhook → deletes the pod
5. Fresh pod starts — no more crash loop

---

### Demo 2: Auto-Scaling on High CPU

```bash
# Terminal 1: Watch HPA
make watch-hpa

# Terminal 2: Simulate CPU spike
make simulate-load
```

**What you'll see:**
1. CPU climbs to ~100% on existing pods
2. HPA detects CPU > 60% target
3. HPA scales from 2 → 4 replicas
4. `HighCPUUtilization` alert fires
5. Remediation bot bumps HPA `minReplicas`
6. Load distributes across more pods → CPU drops

---

## Project Structure

```
self-healing-eks/
├── terraform/              # AWS infrastructure as code
│   ├── modules/
│   │   ├── vpc/            # Network (VPC, subnets, routing)
│   │   ├── eks/            # Kubernetes cluster + node groups
│   │   ├── rds/            # PostgreSQL database
│   │   └── iam/            # Roles and permissions
│   └── environments/dev/   # Dev environment (wires modules together)
├── app/                    # FastAPI demo application
│   ├── main.py             # Application code with all endpoints
│   └── Dockerfile          # Multi-stage production-ready build
├── k8s/                    # Kubernetes manifests
│   ├── deployment.yaml     # App deployment (2 replicas, probes, limits)
│   ├── hpa.yaml            # Auto-scaler (2-10 replicas)
│   ├── pdb.yaml            # Always keep 1 pod alive
│   └── remediation-bot.yaml # Self-healing bot + RBAC
├── helm/                   # Helm chart configuration
│   ├── prometheus-values.yaml  # Alertmanager webhook config
│   └── grafana-values.yaml     # Pre-built dashboards
├── monitoring/
│   └── alert-rules.yaml    # 10 Prometheus alert rules
├── remediation/            # Self-healing Python bot
│   ├── webhook_server.py   # Receives Alertmanager webhooks
│   └── remediation_bot.py  # Fix logic (scale, restart, cordon)
├── docs/
│   ├── SOP.md              # On-call standard operating procedure
│   ├── RCA_sample.md       # Sample incident post-mortem
│   └── runbooks/           # Per-alert diagnosis guides
├── .github/workflows/      # CI/CD pipelines
│   ├── terraform-validate.yml
│   └── app-build.yml
└── Makefile                # One-word shortcuts for everything
```

---

## Observability Stack

| Component | Purpose | Access |
|---|---|---|
| **Prometheus** | Stores all metrics | `make port-prometheus` → :9090 |
| **Grafana** | Dashboards & visualization | `make port-grafana` → :3000 |
| **Alertmanager** | Routes alerts to webhook | `make port-alertmanager` → :9093 |
| **Remediation Bot** | Receives alerts, auto-fixes | `make port-bot` → :9000 |
| **kube-state-metrics** | K8s object state (pods, HPAs) | in-cluster |
| **node-exporter** | Node CPU/memory/disk | in-cluster |

---

## Alert Rules

| Alert | Condition | Action Taken |
|---|---|---|
| `KubePodCrashLooping` | > 5 restarts in 10min | Delete pod (fresh restart) |
| `PodOOMKilled` | Pod killed for OOM | Scale up + increase memory 25% |
| `HighCPUUtilization` | CPU > 80% for 5min | Scale up replicas |
| `HighMemoryUtilization` | Memory > 85% for 5min | Increase memory limit |
| `HighLatency` | p99 > 2s for 3min | Scale up replicas |
| `HighErrorRate` | 5xx rate > 5% | Alert only (needs human) |
| `NodeNotReady` | Node unready 2min+ | Cordon node |
| `DeploymentReplicasMismatch` | Desired ≠ Available | Alert only |
| `PodStuckPending` | Pending > 5min | Alert only |
| `NodeHighCPU` | Node CPU > 85% | Alert only |

---

## Deploying to Real AWS

When ready to deploy to AWS:

```bash
# Configure AWS credentials
aws configure

# Set your DB password
export TF_VAR_db_password="password"

# Deploy everything
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# Configure kubectl to use the new cluster
aws eks update-kubeconfig --name self-healing-eks-dev --region us-east-1

# Deploy the app
make deploy-app
make install-monitoring
```

---

## Documentation

- [**SOP** — On-call procedures](docs/SOP.md)
- [**RCA** — Sample incident post-mortem](docs/RCA_sample.md)
- [**Runbook: Pod Crash Loop**](docs/runbooks/pod-crash-loop.md)
- [**Runbook: High CPU**](docs/runbooks/high-cpu.md)
- [**Runbook: Latency Spike**](docs/runbooks/latency-spike.md)

---

## License

MIT.
