# Architecture & How It Works

A walkthrough of every file in this project.

---

## The Big Picture

```
Your App (FastAPI)
    ↓  exposes /metrics
Prometheus  (scrapes every 15s, evaluates alert rules)
    ↓  alert fires
Alertmanager  (routes alert → webhook)
    ↓  HTTP POST
Remediation Bot  (Python + Kubernetes SDK)
    ↓  Kubernetes API
Cluster  (deletes pods, scales deployments, cordons nodes)
```

---

## `app/`

### `main.py`

FastAPI application. Seven endpoints:

| Endpoint | What it does |
|---|---|
| `GET /` | Returns pod name, node, timestamp — proves each replica is identifiable in logs |
| `GET /health` | Kubernetes calls this every 5–10 s to decide if the pod is alive and ready for traffic |
| `GET /metrics` | Prometheus scrapes this; returns all counters/histograms in Prometheus text format |
| `GET /version` | Shows which Docker image tag and git commit is running — essential for canary verification |
| `GET /db` | Opens a PostgreSQL connection and runs `SELECT version()` — smoke test after deploys |
| `POST /load?seconds=N` | Pegs one CPU core for N seconds in a background thread — triggers HighCPUUtilization |
| `GET /crash` | Calls `os._exit(1)` — kills the process instantly — triggers KubePodCrashLooping |

**Design decisions:**

- **`os._exit(1)` not `raise Exception`** — raising an exception lets FastAPI's error handler catch it and return HTTP 500; the process stays alive. `os._exit()` terminates immediately with no cleanup, which is what a real OOM kill or segfault looks like to Kubernetes.
- **`lifespan` not `@app.on_event("startup")`** — `on_event` was deprecated in FastAPI 0.93. `lifespan` is a standard async context manager — code before `yield` runs on startup, code after `yield` on graceful shutdown.
- **`time.perf_counter()` not `time.time()`** — `time.time()` can go backwards (NTP corrections). `perf_counter()` is monotonic — always increasing — making it safe for measuring elapsed durations.
- **Middleware for metrics** — wrapping at the middleware layer means every route is instrumented automatically. No risk of adding a new endpoint and forgetting to add metric tracking.

### `Dockerfile`

Multi-stage build:

- **Stage 1 (builder):** Installs `gcc` and `libpq-dev` (needed to compile the psycopg2 C extension) and builds a virtualenv.
- **Stage 2 (runtime):** Copies only the venv. The build tools are left behind — smaller image, smaller attack surface.
- **`PYTHONUNBUFFERED=1`** — without this, Python buffers stdout. In containers, buffered output doesn't reach your log aggregator until the buffer flushes. You lose logs on crashes.
- **Non-root user** — if an attacker exploits the app, they get a restricted system user, not root on the host node.
- **`UVICORN_WORKERS` env var** — worker count is configurable at runtime. Default is 2; in production you'd set it to `(2 × CPU cores) + 1`.

### `.dockerignore`

Prevents `__pycache__`, `.git`, test files, and local env files from being sent to Docker's build context. Smaller context = faster builds and no accidental credential leaks.

---

## `k8s/`

### `namespace.yaml`
Creates the `app` namespace. Namespaces are like folders — they scope resources and allow separate RBAC and network policies per team.

### `deployment.yaml`

| Field | Why it's set this way |
|---|---|
| `replicas: 2` | Always two copies for redundancy — one can crash while the other serves traffic |
| `maxUnavailable: 0` | Never take a pod down before its replacement is ready — zero-downtime deploys |
| `maxSurge: 1` | Temporarily run 3 pods during a rollout to avoid dropping below 2 |
| `topologySpreadConstraints: ScheduleAnyway` | Prefer spreading across nodes, but don't block scheduling if only one node exists (minikube) |
| `securityContext (pod)` | Sets Linux user/group for all containers in the pod |
| `readOnlyRootFilesystem: true` | Container can't write to disk — a compromised process can't drop malware. `/tmp` is mounted as an emptyDir volume |
| `startupProbe` | Gives the app up to 30 s to start before the liveness probe begins. Prevents killing a slow-starting container |
| `lifecycle.preStop: sleep 5` | Waits 5 s before sending SIGTERM — gives the load balancer time to stop routing traffic to the pod |

### `hpa.yaml`

Horizontal Pod Autoscaler — watches CPU and memory, adds/removes pods automatically.

- **Target: 60% CPU, 75% memory** — leaving headroom means a sudden spike doesn't immediately breach the limit.
- **Scale up fast (30 s stabilisation)** — adding capacity is cheap; latency impact is not.
- **Scale down slow (5 min stabilisation)** — prevents "flapping" where the cluster constantly adds then removes pods under bursty traffic.

### `pdb.yaml`

PodDisruptionBudget. Tells Kubernetes: "always keep at least 1 pod available." Prevents a voluntary disruption (e.g., `kubectl drain` during node maintenance) from taking all replicas down simultaneously.

### `servicemonitor.yaml`

Tells the Prometheus Operator which pods to scrape. Instead of hardcoding changing pod IPs, you describe pods by labels — Prometheus discovers them automatically. It's a label selector, not an IP address.

### `remediation-bot.yaml`

Deploys the bot with a ClusterRole that grants only the specific Kubernetes API verbs needed:
- `delete` pods
- `patch/update` deployments
- `patch` nodes

This is the principle of least privilege — if the bot is compromised, the blast radius is limited.

---

## `monitoring/alert-rules.yaml`

PrometheusRule resource. Prometheus Operator watches for these CRDs and loads them automatically — no Prometheus restart required.

Every alert has four parts:

| Field | Purpose |
|---|---|
| `expr` | PromQL query — if it returns non-zero, the alert is "pending" |
| `for` | How long it must stay non-zero before firing. Filters out transient spikes |
| `labels` | Metadata: severity, team, which remediation to apply |
| `annotations` | Human-readable text shown in Grafana and alert notifications |

**Key PromQL patterns:**

- `rate(metric[10m])` — per-second rate averaged over 10 minutes. Always use `rate()` on counters, never raw values.
- `histogram_quantile(0.99, ...)` — computes p99 from histogram buckets. Requires the `_bucket` suffix metric.
- `changes(...) == 0` — true if a value hasn't changed in the window. Used in `DeploymentReplicasMismatch` to exclude alerts during active rollouts.

---

## `remediation/`

### `remediation_bot.py`

The fix logic. Key design decisions:

- **K8s client is a singleton** — initialised once at import time and reused. Per-alert init wastes ~50 ms on a TLS handshake every invocation.
- **Dispatch table (`_ALERT_HANDLERS` dict) not `if/elif`** — adding a new alert handler means adding one line to the dict. An if/elif chain gets unwieldy at 10+ cases and is harder to test in isolation.
- **Delete pod, don't restart it** — there is no "restart" verb in the Kubernetes API. Deleting the pod forces the Deployment controller to create a fresh one, which also resets the exponential backoff timer that causes CrashLoopBackOff delays.

### `webhook_server.py`

Flask HTTP server with three routes:

| Route | Purpose |
|---|---|
| `POST /webhook` | Alertmanager sends here when an alert fires or resolves |
| `POST /trigger` | Manual trigger for testing without a live Alertmanager |
| `GET /log` | Returns the last 100 remediation actions — for debugging |

- **gunicorn** (production entrypoint) — Flask's dev server is single-threaded. Alertmanager can send concurrent webhook POSTs; gunicorn handles them in parallel workers.
- **`deque(maxlen=100)` + `Lock`** — the action log is a ring buffer (O(1) append, auto-evicts old entries) protected by a threading lock for concurrent access safety.

---

## `terraform/`

Not applied locally (EKS control plane costs ~$73/month). Documents what production infrastructure looks like:

| Module | What it creates |
|---|---|
| `vpc` | VPC, public/private subnets in 3 AZs, IGW, NAT Gateways, route tables |
| `eks` | EKS control plane, managed node groups (on-demand + spot), OIDC provider for IRSA |
| `rds` | PostgreSQL on RDS Multi-AZ, Secrets Manager integration, security groups |
| `iam` | Cluster and node IAM roles, IRSA roles so pods assume AWS roles without hardcoded keys |

**Why IRSA (IAM Roles for Service Accounts)?**
Instead of putting AWS credentials in environment variables (a common security mistake), IRSA lets a pod assume an IAM role via its Kubernetes service account token. Credentials are short-lived, rotated automatically, and never written to disk.

---

## `docs/`

- **`SOP.md`** — the first document an on-call engineer reads when their phone rings. Answers: where do I look, what severity is this, who do I escalate to?
- **`RCA_sample.md`** — Root Cause Analysis for a simulated OOM incident. Demonstrates the full incident lifecycle: detection → response → resolution → prevention.
- **`runbooks/`** — per-alert diagnosis guides. The difference from the SOP: the SOP is general process, runbooks are specific step-by-step commands for one type of alert.

---

## `.github/workflows/`

- **`terraform-validate.yml`** — on every PR touching `terraform/`: runs `fmt` (format check) and `validate` (syntax + type check) without creating any real AWS resources. Posts a pass/fail table as a PR comment.
- **`app-build.yml`** — on every push to `main` touching `app/`: builds the Docker image, scans for CVEs with Docker Scout, pushes tagged image to Docker Hub.

---

## End-to-End Self-Healing Flow

```
1.  make simulate-crash  →  hits /crash 6 times
2.  os._exit(1) kills the Python process each time
3.  Kubernetes restarts the container, waiting longer each time
    (0 s → 10 s → 20 s → 40 s → ... — this is CrashLoopBackOff)
4.  Prometheus evaluates: restart rate > 0.5/min for 2 minutes → FIRING
5.  Alertmanager receives the firing alert
6.  Alertmanager POSTs JSON to http://remediation-bot-service:9000/webhook
7.  webhook_server.py parses the alert name and labels from the payload
8.  dispatch table matches "KubePodCrashLooping" → restart_crashing_pod()
9.  Bot calls core_v1.delete_namespaced_pod() with grace_period_seconds=0
10. Deployment controller sees replica count < 2 → creates a new pod immediately
11. New pod starts healthy, backoff timer is reset
12. Prometheus sees restart rate drop to 0 → alert resolves
13. Alertmanager POSTs resolved notification → bot logs it, takes no action
```
