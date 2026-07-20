# Runbook: High Latency / Latency Spike
## Alert: `HighLatency`

---

## What's Happening?

The 99th percentile response time has exceeded 2 seconds for 3+ minutes.
This means 1 in 100 users is waiting more than 2 seconds for a response.

Possible causes (in order of likelihood):
1. **App is overloaded** — too many requests, not enough replicas
2. **Database is slow** — queries taking too long, connection pool exhausted
3. **Memory pressure** — pod near memory limit causing frequent garbage collection
4. **Network issue** — slow connection between pod and DB or external service

---

## Step 1: Confirm the latency spike in Grafana

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Open: http://localhost:3000
# Go to: Self-Healing EKS / App Metrics
# Check: "Request Latency p99" panel
```

Note: which endpoints are slow? All of them, or just `/db`?

---

## Step 2: Check pod CPU and memory

```bash
kubectl top pods -n app

# If CPU is near the limit → HPA should help. Check HPA status:
kubectl get hpa demo-app-hpa -n app
```

---

## Step 3: Check if the database is the bottleneck

```bash
# Hit the /db endpoint and time it
kubectl port-forward svc/demo-app-service 8080:80 -n app
time curl http://localhost:8080/db

# If this is slow (>500ms), the DB is the problem:
kubectl top pods -n app | grep postgres

# Check postgres pod logs for slow queries
kubectl logs deploy/postgres -n app | grep -i "slow\|duration\|error"
```

---

## Step 4: Scale up replicas for immediate relief

```bash
# Add more replicas to distribute load
kubectl scale deployment demo-app --replicas=5 -n app

# Watch error/latency improve in Grafana over the next 2-3 minutes
```

---

## Step 5: Check if it's a traffic spike

```bash
# In Grafana: App Metrics → "Request Rate" panel
# Is request rate much higher than normal?

# If yes: this is a traffic event — scaling is the right fix
# Consider: did a batch job, marketing campaign, or cron job just fire?
```

---

## Step 6: Verify recovery

```bash
# Latency alert auto-resolves when p99 drops below 2s for 3+ min
# Verify in Grafana or:
kubectl port-forward svc/demo-app-service 8080:80 -n app
for i in {1..10}; do time curl -s http://localhost:8080/ > /dev/null; done
```
