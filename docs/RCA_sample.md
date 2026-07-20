# Incident Post-Mortem / Root Cause Analysis (RCA)
## Incident: CrashLoopBackOff After Traffic Spike Caused OOM

> **What is an RCA?**
> After an incident is resolved, engineers write an RCA to understand what
> happened, why it happened, and how to prevent it in the future.
> Good RCAs are blameless — the goal is to fix the SYSTEM, not punish people.

---

## Incident Summary

| Field | Value |
|---|---|
| **Date** | 2024-03-15 |
| **Duration** | 23 minutes (14:07 UTC → 14:30 UTC) |
| **Severity** | P1 — Critical |
| **Services Affected** | `demo-app` in namespace `app` |
| **Impact** | 40% of requests returned 503 errors during peak period |
| **Root Cause** | Memory limit set too low; OOM kills during traffic spike caused CrashLoopBackOff |
| **Detection** | Automated — Prometheus alert fired at T+0 |
| **Resolution** | Automated (partial) + manual memory limit increase |

---

## Timeline

> All times in UTC. T+0 = when the incident started.

| Time | Event |
|---|---|
| **T-30 min** | Marketing team sends email campaign → traffic doubles |
| **T+0 (14:07)** | `PodOOMKilled` alert fires. Pod `demo-app-7d9b4f-xk2pq` terminated with OOMKilled |
| **T+1 min** | Remediation bot receives webhook from Alertmanager |
| **T+1 min** | Bot scales deployment from 2 → 3 replicas (scale_up action) |
| **T+2 min** | Bot patches memory limit from `128Mi` → `160Mi` (increase_memory action) |
| **T+2 min** | `KubePodCrashLooping` fires — the pod is restarting repeatedly (CrashLoopBackOff backoff timer is long) |
| **T+3 min** | Remediation bot deletes the crash-looping pod (restart_pod action) — resets backoff timer |
| **T+4 min** | New pod starts with 160Mi memory limit. But traffic is STILL high — new pod also OOMKills. |
| **T+5 min** | On-call engineer acknowledges alert |
| **T+10 min** | Engineer identifies root cause: 128Mi is insufficient for current traffic load |
| **T+15 min** | Engineer manually patches memory limit to `256Mi` and sets replicas to 5 |
| **T+20 min** | All 5 pods running stably. Error rate drops to 0. |
| **T+23 min** | Incident resolved. Alerts resolve. |
| **T+24 hours** | This RCA written. |

---

## Root Cause

**The memory limit of `128Mi` was set too low** when the Deployment was first created.
This was fine for normal traffic (average memory usage: 80Mi). However:

1. The marketing team sent an email campaign that tripled traffic
2. Each request required more memory to process (database queries, response serialization)
3. Average memory usage jumped to 145Mi — over the 128Mi limit
4. Kubernetes killed (`OOMKilled`) the pod to protect other workloads on the node
5. Kubernetes tried to restart the pod, but under the same load, it OOMKilled again
6. This created a CrashLoopBackOff loop

**Contributing factors:**
- Memory limit was set without load testing at realistic traffic levels
- No memory-based HPA policy existed (only CPU-based)
- Marketing team didn't notify engineering about the campaign

---

## What the Self-Healing System Did

✅ **Detected** — Prometheus fired `PodOOMKilled` within 1 minute  
✅ **Responded** — Remediation bot scaled up and increased memory limit automatically  
✅ **Partially resolved** — Bot's 25% memory increase (128Mi → 160Mi) wasn't enough for the traffic level  
⚠️ **Human needed** — Engineer had to manually set 256Mi and replicas=5  

**Assessment**: The self-healing system reduced MTTR (Mean Time To Recover) significantly.
Without it, the engineer would have needed to manually diagnose OOMKill cause, find the
limit, and patch it — estimated +15 minutes.

---

## What Did NOT Cause the Incident

- No code bugs or application errors
- No infrastructure failure
- No database issues
- No network problems

---

## Action Items

| Priority | Action | Owner | Due Date |
|---|---|---|---|
| P1 | Add load testing to CI/CD pipeline (k6 or locust) | Platform team | 2024-03-22 |
| P1 | Increase default memory limit to 256Mi across all deployments | Platform team | 2024-03-16 |
| P2 | Add memory-based HPA policy | Platform team | 2024-03-29 |
| P2 | Create runbook: "What to do when bot's memory increase is insufficient" | Platform team | 2024-03-22 |
| P3 | Establish process: Marketing notifies Engineering before campaigns | Marketing + Eng | 2024-03-31 |
| P3 | Set remediation bot's memory increase to 50% (instead of 25%) for OOM events | Platform team | 2024-03-29 |

---

## Lessons Learned

1. **Always load test at realistic traffic levels** before setting resource limits
2. **Self-healing automation reduces MTTR**, but has limits — humans are still needed for novel scenarios
3. **Cross-team communication matters** — a 15-minute Slack message from marketing would have prevented this
4. **The 25% memory increase heuristic was too conservative** for OOM incidents; 50% is safer

---

## Metrics

| Metric | Value |
|---|---|
| MTTD (Mean Time To Detect) | 1 minute (automated) |
| MTTA (Mean Time To Acknowledge) | 5 minutes |
| MTTR (Mean Time To Recover) | 23 minutes |
| Estimated MTTR without automation | ~38 minutes |
| Time saved by self-healing bot | ~15 minutes |
| Requests that returned 503 | ~12,400 (estimated) |
