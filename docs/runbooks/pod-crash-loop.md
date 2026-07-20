# Runbook: Pod CrashLoopBackOff
## Alert: `KubePodCrashLooping` or `PodOOMKilled`

> **What is a runbook?**
> A runbook is a step-by-step guide for a specific type of incident.
> Follow these steps IN ORDER. Don't skip steps.

---

## What is CrashLoopBackOff?

When a pod crashes (exits with a non-zero code), Kubernetes restarts it.
If it keeps crashing, Kubernetes waits longer before each restart:
`0s → 10s → 20s → 40s → 80s → ... → 5 minutes max`

**CrashLoopBackOff = "I've given up restarting quickly. Something is very wrong."**

Common causes:
| Cause | How to identify |
|---|---|
| Out of Memory (OOM) | `kubectl describe pod` shows `OOMKilled` |
| Bad config / missing env var | Pod logs show config error on startup |
| App code bug | Pod logs show unhandled exception |
| DB connection failure | Pod logs show "connection refused" or timeout |
| Image pull failure | `kubectl describe pod` shows `ErrImagePull` |

---

## Step 1: Identify the crashing pod

```bash
# List all pods — look for STATUS=CrashLoopBackOff and high RESTARTS count
kubectl get pods -n app

# Example output:
# NAME                         READY   STATUS             RESTARTS   AGE
# demo-app-7d9b4f-xk2pq        0/1     CrashLoopBackOff   8          12m
# demo-app-7d9b4f-mn8vz        1/1     Running            0          12m
```

Note the pod name (e.g., `demo-app-7d9b4f-xk2pq`)

---

## Step 2: Check recent events for the pod

```bash
kubectl describe pod demo-app-7d9b4f-xk2pq -n app

# Scroll to the bottom and look at "Events" section:
# Events:
#   Type     Reason     Message
#   ----     ------     -------
#   Warning  OOMKilling  Memory limit reached: 128Mi
#   Normal   Pulled      Successfully pulled image
#   Warning  BackOff     Back-off restarting failed container
```

---

## Step 3: Read the crash logs

```bash
# Current logs (might be empty if pod just restarted)
kubectl logs demo-app-7d9b4f-xk2pq -n app

# Logs from BEFORE the last crash — usually has the error
kubectl logs demo-app-7d9b4f-xk2pq -n app --previous
```

---

## Step 4: Diagnose by cause

### If you see `OOMKilled`:
```bash
# Check current memory limit
kubectl get deployment demo-app -n app -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'

# Increase memory limit manually (example: set to 256Mi)
kubectl set resources deployment demo-app \
  --limits=memory=256Mi,cpu=500m \
  --requests=memory=192Mi,cpu=100m \
  -n app

# Watch the rolling restart
kubectl rollout status deployment/demo-app -n app
```

### If you see a config/env error in logs:
```bash
# Check all environment variables set on the pod
kubectl exec -it demo-app-7d9b4f-mn8vz -n app -- env | sort

# Check ConfigMaps and Secrets exist
kubectl get configmap postgres-config -n app
kubectl get secret postgres-secret -n app
```

### If you see a DB connection error:
```bash
# Test DB connectivity from a running pod
kubectl exec -it demo-app-7d9b4f-mn8vz -n app -- \
  python -c "import psycopg2; psycopg2.connect(host='postgres-service', dbname='appdb', user='appuser', password='changeme123')"

# Check if postgres pod is running
kubectl get pods -n app | grep postgres
```

### If you see `ErrImagePull` or `ImagePullBackOff`:
```bash
# Check the image name in the deployment
kubectl get deployment demo-app -n app -o jsonpath='{.spec.template.spec.containers[0].image}'

# Force re-pull with a rollout restart
kubectl rollout restart deployment/demo-app -n app
```

---

## Step 5: Verify recovery

```bash
# Watch pods come back healthy (wait for 1/1 Running)
kubectl get pods -n app -w

# Once all pods are Running, check the app is responding
kubectl port-forward svc/demo-app-service 8080:80 -n app
curl http://localhost:8080/health
# Expected: {"status": "ok"}
```

---

## Step 6: Close the incident

1. Silence the alert in Alertmanager if still firing (it'll auto-resolve in ~5 min)
2. Document what you did in the incident ticket
3. If this was OOM: file a ticket to run load tests before next release
4. Write or update an action item to prevent recurrence
