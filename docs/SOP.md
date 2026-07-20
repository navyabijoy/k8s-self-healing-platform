# Standard Operating Procedure (SOP)
## Self-Healing EKS Cluster

> **What is an SOP?**
> An SOP is a written guide that tells on-call engineers exactly what to do
> when something goes wrong — even at 3am when you're half-asleep.
> Good SOPs mean faster recovery and fewer mistakes under pressure.

---

## Table of Contents
1. [Who's On-Call?](#whos-on-call)
2. [How to Access Dashboards](#how-to-access-dashboards)
3. [Alert Severity Definitions](#alert-severity-definitions)
4. [Alert Triage Decision Tree](#alert-triage-decision-tree)
5. [Common Commands](#common-commands)
6. [Escalation Path](#escalation-path)
7. [How to Silence a False Alarm](#how-to-silence-a-false-alarm)

---

## Who's On-Call?

In a real company this would list actual people. For this portfolio project,
it demonstrates that you understand on-call rotations matter.

| Role | Responsibility |
|---|---|
| **Primary On-Call** | First to respond to alerts (target: acknowledge within 5 min) |
| **Secondary On-Call** | Backup if primary doesn't respond within 15 min |
| **Escalation** | Engineering lead — for P1 incidents only |

---

## How to Access Dashboards

### Grafana (Metrics & Graphs)
```bash
# Forward Grafana port to your laptop
kubectl port-forward svc/grafana 3000:80 -n monitoring

# Then open in browser:
open http://localhost:3000
# Login: admin / grafana-admin-pass
```

**Key dashboards:**
- `Self-Healing EKS / Kubernetes Cluster Overview` — node CPU, memory, pod counts
- `Self-Healing EKS / App Metrics` — request rate, latency, error rate
- `Self-Healing EKS / Node Exporter` — disk I/O, network

### Prometheus (Raw Metrics & Alert Status)
```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
open http://localhost:9090/alerts
```

### Alertmanager (Active Alerts & Silences)
```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
open http://localhost:9093
```

---

## Alert Severity Definitions

| Severity | What it means | Target Response Time |
|---|---|---|
| **P1 / Critical** | Service is down or data loss risk | 5 minutes |
| **P2 / Warning** | Degraded performance, risk of P1 soon | 30 minutes |
| **P3 / Info** | Something unusual, needs investigation | Business hours |

---

## Alert Triage Decision Tree

```
Alert fires
    │
    ├── Is it Critical? ──────────────────────────────────────────────┐
    │                                                                  │
    │   YES → Check if remediation bot already acted                  │
    │          kubectl logs deploy/remediation-bot -n monitoring      │
    │                │                                                 │
    │                ├── Bot handled it → Monitor for 10 min          │
    │                │   Still broken? → Follow runbook               │
    │                │                                                 │
    │                └── Bot did NOT handle → Go to runbook directly  │
    │                                                                  │
    └── Is it Warning? ────────────────────────────────────────────────┘
                │
                └── Check in next 30 min during business hours
                    Is it trending toward Critical? → Escalate


RUNBOOKS BY ALERT TYPE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
KubePodCrashLooping    → docs/runbooks/pod-crash-loop.md
PodOOMKilled           → docs/runbooks/pod-crash-loop.md
HighCPUUtilization     → docs/runbooks/high-cpu.md
HighLatency            → docs/runbooks/latency-spike.md
NodeNotReady           → Check node health, cordon if needed
HighErrorRate          → Check app logs for exceptions
```

---

## Common Commands

> Copy-paste these during an incident — no need to think.

```bash
# ── See all pods and their status ──────────────────────────────────
kubectl get pods -n app -o wide

# ── See recent events (why did something crash?) ───────────────────
kubectl get events -n app --sort-by='.lastTimestamp' | tail -20

# ── Read logs from a pod ───────────────────────────────────────────
kubectl logs <pod-name> -n app
kubectl logs <pod-name> -n app --previous   # Logs from BEFORE the last crash

# ── Describe a pod (see probe failures, OOM, scheduling issues) ────
kubectl describe pod <pod-name> -n app

# ── Check the HPA status (is it scaling?) ─────────────────────────
kubectl get hpa -n app

# ── Manually scale a deployment ───────────────────────────────────
kubectl scale deployment demo-app --replicas=4 -n app

# ── Read remediation bot logs ──────────────────────────────────────
kubectl logs deploy/remediation-bot -n monitoring -f

# ── See what the bot did via its API ──────────────────────────────
kubectl port-forward svc/remediation-bot-service 9000:9000 -n monitoring
curl http://localhost:9000/log

# ── Roll back a bad deployment ────────────────────────────────────
kubectl rollout undo deployment/demo-app -n app
kubectl rollout status deployment/demo-app -n app

# ── Restart all pods in a deployment (rolling restart) ────────────
kubectl rollout restart deployment/demo-app -n app
```

---

## Escalation Path

```
1. Alert fires
2. Remediation bot acts automatically
3. On-call engineer acknowledges within 5 min
4. If not resolved in 30 min → notify secondary on-call
5. If P1 and not resolved in 1 hour → notify engineering lead
6. Write RCA within 24 hours of resolution (see docs/RCA_sample.md for template)
```

---

## How to Silence a False Alarm

Sometimes alerts fire when there's no real problem (e.g., during a planned deploy).

```bash
# Via Alertmanager UI (easiest)
# 1. Open http://localhost:9093
# 2. Click "Silences" → "New Silence"
# 3. Add matchers: alertname="KubePodCrashLooping", namespace="app"
# 4. Set duration (e.g., 30 minutes)
# 5. Add comment: "Silencing during planned rolling deploy"

# Via amtool CLI
amtool silence add \
  alertname="KubePodCrashLooping" \
  namespace="app" \
  --duration=30m \
  --comment="Planned maintenance" \
  --alertmanager.url=http://localhost:9093
```

> ⚠️ **Rule**: Always add a comment explaining WHY you silenced an alert.
> Silences without comments will be removed at next review.
