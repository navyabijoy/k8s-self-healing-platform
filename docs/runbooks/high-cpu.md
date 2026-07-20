# Runbook: High CPU Utilization
## Alert: `HighCPUUtilization` or `NodeHighCPU`

---

## What's Happening?

One or more pods are using more than 80% of their CPU limit for over 5 minutes.
This causes slow response times and, if it continues, the HPA will keep scaling
until it hits the max replica limit.

---

## Step 1: Find which pods are using high CPU

```bash
# Show CPU usage for all pods in the app namespace
kubectl top pods -n app --sort-by=cpu

# Example output:
# NAME                        CPU(cores)   MEMORY(bytes)
# demo-app-7d9b4f-xk2pq       480m         120Mi     ← Near the 500m limit!
# demo-app-7d9b4f-mn8vz        95m          105Mi
```

---

## Step 2: Check if HPA is already scaling

```bash
# View HPA status — check REPLICAS and TARGETS
kubectl get hpa demo-app-hpa -n app

# Example output:
# NAME            REFERENCE          TARGETS         MINPODS   MAXPODS   REPLICAS
# demo-app-hpa    Deployment/demo-app 82%/60%, 60%/75%  2         10        4

# If REPLICAS < MAXPODS, the HPA is handling it. Wait 2-3 minutes.
# If REPLICAS = MAXPODS (10), manual intervention is needed.
```

---

## Step 3: If HPA has maxed out — manually investigate

```bash
# Is a CPU load simulation running? (someone hit the /load endpoint)
kubectl logs demo-app-7d9b4f-xk2pq -n app | grep "load simulation"

# Is there a traffic spike? Check request rate in Grafana:
# Dashboard: App Metrics → "Request Rate" panel
```

---

## Step 4: Manual scale if needed

```bash
# Scale beyond what HPA allows for emergency relief
# WARNING: HPA will fight you — it may scale back down
# Disable HPA first if you need to manually control replicas
kubectl annotate hpa demo-app-hpa -n app \
  "kubectl.kubernetes.io/last-applied-configuration-"

# Manually scale
kubectl scale deployment demo-app --replicas=8 -n app
```

---

## Step 5: If high CPU is from a specific endpoint

```bash
# Check Grafana: App Metrics → "Request Rate by Endpoint"
# If /load is being hammered:

# Kill any running load simulation by restarting the pod
kubectl rollout restart deployment/demo-app -n app
```

---

## Step 6: Increase CPU limits if this is recurring

```bash
# Check how often this alert has fired in the last 7 days in Grafana/Prometheus
# If it's recurring, increase the CPU limit:

kubectl set resources deployment demo-app \
  --limits=cpu=1000m \
  --requests=cpu=200m \
  -n app
```

---

## Step 7: Verify and close

```bash
# CPU should drop within 1-2 minutes as more replicas join
kubectl top pods -n app --sort-by=cpu

# Alert will auto-resolve once CPU drops below 80% for 5+ min
```
