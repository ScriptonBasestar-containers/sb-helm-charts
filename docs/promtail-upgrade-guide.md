# Promtail Upgrade Guide

## Table of Contents

1. [Overview](#overview)
2. [Version Compatibility](#version-compatibility)
3. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
4. [Upgrade Strategies](#upgrade-strategies)
5. [Version-Specific Notes](#version-specific-notes)
6. [Post-Upgrade Validation](#post-upgrade-validation)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

Promtail is a **stateless log shipping agent** that tails logs from Kubernetes pods and sends them to Loki. Upgrading Promtail is generally straightforward because:

- **No persistent state** (except optional positions file)
- **Rolling updates** supported via DaemonSet
- **Backward compatible** with Loki (within version ranges)
- **Configuration-driven** (no database migrations)

**Key Considerations:**
- Promtail version should be compatible with Loki version
- Pipeline stage changes may require configuration updates
- Label changes can affect Loki queries
- DaemonSet rolling updates minimize log loss

**Upgrade Impact:**
- **Downtime**: None (rolling update) or < 5 minutes per node
- **Log Loss**: Minimal (seconds during pod restart)
- **Configuration Changes**: May be required (see version-specific notes)

---

## Version Compatibility

### Promtail and Loki Version Matrix

Promtail versions should match or be within 1-2 minor versions of Loki:

| Promtail Version | Compatible Loki Versions | Release Date | Notable Changes |
|------------------|--------------------------|--------------|-----------------|
| **3.3.x** | 3.1.x - 3.3.x | 2025-11 | OTel logs support, improved memory usage |
| **3.2.x** | 3.0.x - 3.2.x | 2025-09 | Structured metadata support |
| **3.1.x** | 2.9.x - 3.1.x | 2025-07 | Log line parsing improvements |
| **3.0.x** | 2.8.x - 3.0.x | 2025-04 | Major release, configuration schema changes |
| **2.9.x** | 2.7.x - 2.9.x | 2024-09 | Kubernetes discovery improvements |
| **2.8.x** | 2.6.x - 2.8.x | 2024-05 | CRI parser enhancements |

**General Rule:** Keep Promtail within 2 minor versions of Loki

**Example:**
- Loki 3.2.0 → Use Promtail 3.0.x - 3.3.x ✅
- Loki 2.9.0 → Use Promtail 2.7.x - 3.1.x ✅
- Loki 3.0.0 → Use Promtail 2.5.x ❌ (too old, may have compatibility issues)

### Helm Chart Version Compatibility

| Chart Version | Promtail Version | Kubernetes Version | Notes |
|---------------|------------------|--------------------|-------|
| **0.4.x** | 3.3.x | 1.24+ | Enhanced RBAC, comprehensive docs |
| **0.3.x** | 3.2.x | 1.23+ | Production-ready |
| **0.2.x** | 3.1.x | 1.22+ | Beta release |
| **0.1.x** | 3.0.x | 1.21+ | Initial release |

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**Check for breaking changes:**

```bash
# View Promtail release notes
open https://github.com/grafana/loki/releases

# Check chart CHANGELOG
cat charts/promtail/CHANGELOG.md
```

**Key areas to review:**
- Configuration schema changes
- Pipeline stage syntax changes
- Deprecated features
- New required permissions

---

### 2. Backup Current Configuration

**Backup Helm values and ConfigMap:**

```bash
# Backup current Helm values
helm get values my-promtail -n default > promtail-values-backup-$(date +%Y%m%d).yaml

# Backup ConfigMap
kubectl get configmap -n default promtail-config -o yaml > promtail-config-backup-$(date +%Y%m%d).yaml

# Backup entire Helm manifest
helm get manifest my-promtail -n default > promtail-manifest-backup-$(date +%Y%m%d).yaml
```

**Store backups in secure location:**
```bash
cp promtail-*-backup-*.yaml backups/promtail/
```

---

### 3. Verify Current State

**Check current deployment:**

```bash
# Check Helm release
helm list -n default | grep promtail

# Check DaemonSet status
kubectl get daemonset -n default my-promtail

# Check all pods are running
kubectl get pods -n default -l app.kubernetes.io/name=promtail

# Check Promtail version
kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected output:**
```
NAME          CHART            STATUS    NAMESPACE
my-promtail   promtail-0.3.0   deployed  default

NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
my-promtail   3         3         3       3            3

NAME              READY   STATUS    RESTARTS   AGE
my-promtail-abc   1/1     Running   0          10d
my-promtail-def   1/1     Running   0          10d
my-promtail-ghi   1/1     Running   0          10d

grafana/promtail:3.2.1
```

---

### 4. Check Loki Compatibility

**Verify Loki version:**

```bash
# Get Loki version
kubectl get pods -n default -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].spec.containers[0].image}'

# Or via Loki API
kubectl port-forward -n default svc/loki 3100:3100 &
curl http://localhost:3100/loki/api/v1/status/buildinfo | jq '.version'
```

**Verify compatibility:** Check [Version Compatibility Matrix](#promtail-and-loki-version-matrix)

---

### 5. Test in Dev/Staging

**Deploy upgrade in test environment:**

```bash
# Test upgrade in staging namespace
helm upgrade promtail-staging scripton-charts/promtail \
  --version 0.4.0 \
  --set image.tag=3.3.0 \
  -n staging
```

**Verify:**
- Pods start successfully
- Logs are being sent to Loki
- No errors in Promtail logs
- Loki queries work as expected

---

### 6. Plan Maintenance Window (Optional)

For production upgrades, consider:
- **Low-traffic period** (e.g., off-peak hours)
- **Communication** with stakeholders
- **Rollback plan** ready

**Note:** Promtail supports rolling updates with minimal disruption, so maintenance window is optional.

---

## Upgrade Strategies

Promtail supports three upgrade strategies:

### Strategy 1: Rolling Update (Recommended)

**Best for:** Production environments, minimal disruption

**Downtime:** None (rolling update per node)

**Log Loss:** Minimal (seconds during pod restart)

**Procedure:**

1. **Update Helm chart:**
```bash
# Upgrade with new chart version
helm upgrade my-promtail scripton-charts/promtail \
  --version 0.4.0 \
  --set image.tag=3.3.0 \
  -n default \
  --wait
```

2. **Monitor rollout:**
```bash
# Watch DaemonSet rollout status
kubectl rollout status daemonset/my-promtail -n default

# Watch pod updates in real-time
watch kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

3. **Verify each node:**
```bash
# Check updated pods
kubectl get pods -n default -l app.kubernetes.io/name=promtail -o wide

# Verify new image version
kubectl get pods -n default -l app.kubernetes.io/name=promtail \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

**Expected output:**
```
Waiting for daemon set "my-promtail" rollout to finish: 1 out of 3 new pods have been updated...
Waiting for daemon set "my-promtail" rollout to finish: 2 out of 3 new pods have been updated...
Waiting for daemon set "my-promtail" rollout to finish: 3 out of 3 new pods have been updated...
daemon set "my-promtail" successfully rolled out
```

**Rolling Update Timeline:**
```
Node 1: Old pod → Stop → New pod → Running (30s - 1min)
  ↓
Node 2: Old pod → Stop → New pod → Running (30s - 1min)
  ↓
Node 3: Old pod → Stop → New pod → Running (30s - 1min)
```

**Total Time:** 2-5 minutes (depends on number of nodes and update strategy)

---

### Strategy 2: Configuration-Only Update

**Best for:** Updating Promtail configuration without version change

**Downtime:** None (rolling update)

**Procedure:**

1. **Update values.yaml:**
```yaml
# Example: Update Loki endpoint
promtail:
  client:
    url: "http://new-loki:3100/loki/api/v1/push"
```

2. **Apply configuration update:**
```bash
helm upgrade my-promtail scripton-charts/promtail \
  -f values.yaml \
  -n default
```

3. **Verify ConfigMap updated:**
```bash
kubectl get configmap -n default promtail-config -o yaml | grep -A5 client
```

4. **Restart pods to pick up new config:**
```bash
kubectl rollout restart daemonset/my-promtail -n default
kubectl rollout status daemonset/my-promtail -n default
```

---

### Strategy 3: Blue-Green Deployment (Advanced)

**Best for:** Major version upgrades with high risk, testing in parallel

**Downtime:** < 1 minute (switch traffic)

**Procedure:**

1. **Deploy green environment (new version):**
```bash
# Deploy new Promtail with different name
helm install my-promtail-green scripton-charts/promtail \
  --version 0.4.0 \
  --set image.tag=3.3.0 \
  --set fullnameOverride=promtail-green \
  -n default
```

2. **Monitor both environments:**
```bash
# Watch both old and new
watch kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

3. **Verify green environment:**
```bash
# Check green pods are sending logs
kubectl logs -n default -l app.kubernetes.io/instance=promtail-green --tail=100

# Verify in Loki (check for new labels)
# LogQL: {job="promtail-green"}
```

4. **Switch by deleting blue:**
```bash
# Once confident, delete old deployment
helm uninstall my-promtail -n default

# Rename green to primary
helm upgrade my-promtail scripton-charts/promtail \
  --reuse-values \
  --set fullnameOverride=promtail \
  -n default
```

**Note:** This strategy is rarely needed for Promtail due to its stateless nature. Use only for major version jumps (e.g., 2.x → 3.x).

---

## Version-Specific Notes

### Promtail 3.3.x

**Release Date:** November 2025

**Key Changes:**
- **OTel Logs Support**: Native OpenTelemetry logs ingestion
- **Memory Optimization**: Reduced memory footprint (20-30% improvement)
- **Improved Error Handling**: Better retry logic for Loki connection failures

**Configuration Changes:**

1. **OTel Logs Receiver (Optional):**
```yaml
promtail:
  config:
    server:
      http_listen_port: 3101
      grpc_listen_port: 9095
    receivers:
      otlp:
        protocols:
          http:
            endpoint: "0.0.0.0:4318"
          grpc:
            endpoint: "0.0.0.0:4317"
```

2. **Memory Limits Adjustment:**
```yaml
resources:
  limits:
    memory: 128Mi  # Reduced from 256Mi (due to optimization)
  requests:
    memory: 64Mi   # Reduced from 128Mi
```

**Upgrade Notes:**
- No breaking changes
- Memory limits can be reduced (test first)
- OTel receiver is opt-in

---

### Promtail 3.2.x

**Release Date:** September 2025

**Key Changes:**
- **Structured Metadata**: Support for structured metadata fields
- **Pipeline Performance**: 15-20% improvement in log processing speed
- **Kubernetes Discovery**: Improved pod discovery with caching

**Configuration Changes:**

1. **Structured Metadata (New Feature):**
```yaml
promtail:
  pipelineStages:
    custom:
      - json:
          expressions:
            level: level
            message: message
      - labels:
          level:
      - structured_metadata:  # NEW in 3.2.x
          trace_id:
          span_id:
```

2. **Kubernetes Discovery Cache:**
```yaml
promtail:
  kubernetesSD:
    # Enable discovery cache (default: true in 3.2.x)
    enableCache: true
    cacheTTL: "5m"
```

**Upgrade Notes:**
- Structured metadata is opt-in
- No configuration changes required for existing setups
- Performance improvements automatic

---

### Promtail 3.1.x

**Release Date:** July 2025

**Key Changes:**
- **Log Line Parsing**: Improved CRI parser with better error handling
- **Label Extraction**: New regex features for label extraction
- **Health Checks**: Enhanced readiness/liveness probes

**Configuration Changes:**

1. **CRI Parser Improvements (Automatic):**
```yaml
promtail:
  pipelineStages:
    cri:
      enabled: true
      # No changes needed - improvements are automatic
```

2. **Enhanced Label Extraction:**
```yaml
promtail:
  pipelineStages:
    custom:
      - regex:
          expression: '(?P<level>\w+)\s+(?P<message>.*)'
          # NEW: Named groups support
      - labels:
          level:
```

**Upgrade Notes:**
- No breaking changes
- CRI parser improvements automatic
- Enhanced regex features are backward compatible

---

### Promtail 3.0.x (Major Release)

**Release Date:** April 2025

**Key Changes:**
- **Configuration Schema**: Simplified configuration structure
- **Pipeline Stages**: New pipeline stage syntax
- **Deprecations**: Removed deprecated `docker` scrape config

**BREAKING CHANGES:**

1. **Docker Scrape Config Removed:**

**Old (2.9.x):**
```yaml
scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
```

**New (3.0.x):**
```yaml
# Use Kubernetes service discovery instead
scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
```

2. **Pipeline Stage Syntax:**

**Old (2.9.x):**
```yaml
pipeline_stages:
  - match:
      selector: '{app="nginx"}'
      stages:
        - regex:
            expression: '(?P<level>\w+)'
```

**New (3.0.x):**
```yaml
pipeline_stages:
  - match:
      selector: '{app="nginx"}'
      pipeline:  # Changed from 'stages' to 'pipeline'
        - regex:
            expression: '(?P<level>\w+)'
```

**Migration Steps:**

1. **Update configuration syntax:**
```bash
# Backup current config
helm get values my-promtail -n default > values-2.9.yaml

# Update to 3.0.x syntax
# Replace 'stages:' with 'pipeline:' in match blocks
sed -i 's/stages:/pipeline:/g' values-2.9.yaml

# Save as new version
cp values-2.9.yaml values-3.0.yaml
```

2. **Test new configuration:**
```bash
# Deploy to test namespace
helm install promtail-test scripton-charts/promtail \
  --version 0.4.0 \
  -f values-3.0.yaml \
  -n test
```

3. **Verify logs are being sent:**
```bash
kubectl logs -n test -l app.kubernetes.io/name=promtail --tail=100
```

**Upgrade Notes:**
- Review [Promtail 3.0 Migration Guide](https://grafana.com/docs/loki/latest/send-data/promtail/migration-3.0/)
- Test thoroughly in staging before production
- Plan for configuration syntax updates

---

### Promtail 2.9.x

**Release Date:** September 2024

**Key Changes:**
- **Kubernetes Discovery**: Improved pod discovery performance
- **Label Limits**: Configurable label limits to prevent cardinality explosion
- **Retry Logic**: Better handling of Loki connection failures

**Configuration Changes:**

1. **Label Limits (New):**
```yaml
promtail:
  config:
    limits_config:
      max_label_name_length: 1024
      max_label_value_length: 2048
      max_label_names_per_series: 30
```

2. **Retry Configuration:**
```yaml
promtail:
  client:
    backoff_config:
      min_period: 500ms
      max_period: 5m
      max_retries: 10
```

**Upgrade Notes:**
- No breaking changes
- Label limits are optional but recommended
- Retry improvements automatic

---

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# Script: promtail-post-upgrade-check.sh
# Description: Validate Promtail after upgrade

set -e

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-promtail}"

echo "=== Promtail Post-Upgrade Validation ==="

# 1. Check Helm release status
echo "1/6 Checking Helm release..."
HELM_STATUS=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '.info.status')
if [ "$HELM_STATUS" != "deployed" ]; then
  echo "❌ FAIL: Helm release status is $HELM_STATUS (expected: deployed)"
  exit 1
fi
echo "✅ PASS: Helm release is deployed"

# 2. Check DaemonSet rollout
echo "2/6 Checking DaemonSet rollout..."
kubectl rollout status daemonset/"$RELEASE_NAME" -n "$NAMESPACE" --timeout=5m
echo "✅ PASS: DaemonSet rollout complete"

# 3. Check all pods are running
echo "3/6 Checking pod status..."
DESIRED=$(kubectl get daemonset -n "$NAMESPACE" "$RELEASE_NAME" -o jsonpath='{.status.desiredNumberScheduled}')
READY=$(kubectl get daemonset -n "$NAMESPACE" "$RELEASE_NAME" -o jsonpath='{.status.numberReady}')
if [ "$DESIRED" != "$READY" ]; then
  echo "❌ FAIL: Only $READY/$DESIRED pods are ready"
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail
  exit 1
fi
echo "✅ PASS: All $READY pods are running"

# 4. Check Promtail version
echo "4/6 Checking Promtail version..."
IMAGE=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].spec.containers[0].image}')
echo "Current image: $IMAGE"

# 5. Check for errors in logs
echo "5/6 Checking Promtail logs for errors..."
ERRORS=$(kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=promtail --tail=100 --since=5m | grep -i "error" | wc -l)
if [ "$ERRORS" -gt 0 ]; then
  echo "⚠️  WARNING: Found $ERRORS errors in logs (check manually)"
  kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=promtail --tail=100 --since=5m | grep -i "error"
else
  echo "✅ PASS: No errors in recent logs"
fi

# 6. Check Promtail is sending logs
echo "6/6 Checking Promtail metrics..."
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n "$NAMESPACE" "$POD" 3101:3101 >/dev/null 2>&1 &
PF_PID=$!
sleep 2

SENT_ENTRIES=$(curl -s http://localhost:3101/metrics | grep "^promtail_sent_entries_total" | awk '{print $2}' | head -1)
kill $PF_PID

if [ -z "$SENT_ENTRIES" ] || [ "$SENT_ENTRIES" = "0" ]; then
  echo "⚠️  WARNING: No logs sent to Loki yet (check Loki connectivity)"
else
  echo "✅ PASS: Promtail is sending logs (sent_entries: $SENT_ENTRIES)"
fi

echo ""
echo "=== Post-Upgrade Validation Complete ==="
echo "Status: ✅ Upgrade successful"
```

**Run validation:**
```bash
chmod +x promtail-post-upgrade-check.sh
./promtail-post-upgrade-check.sh
```

**Expected output:**
```
=== Promtail Post-Upgrade Validation ===
1/6 Checking Helm release...
✅ PASS: Helm release is deployed
2/6 Checking DaemonSet rollout...
✅ PASS: DaemonSet rollout complete
3/6 Checking pod status...
✅ PASS: All 3 pods are running
4/6 Checking Promtail version...
Current image: grafana/promtail:3.3.0
5/6 Checking Promtail logs for errors...
✅ PASS: No errors in recent logs
6/6 Checking Promtail metrics...
✅ PASS: Promtail is sending logs (sent_entries: 12345)

=== Post-Upgrade Validation Complete ===
Status: ✅ Upgrade successful
```

---

### Manual Verification Checklist

**1. Check DaemonSet Status:**
```bash
kubectl get daemonset -n default my-promtail
```
Expected: `DESIRED = CURRENT = READY = UP-TO-DATE`

**2. Check Pod Health:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=promtail
```
Expected: All pods `STATUS=Running`, `READY=1/1`

**3. Check Promtail Logs:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=100
```
Expected: No errors, logs show "Successfully sent batch"

**4. Verify Loki Connectivity:**
```bash
# Port-forward to Promtail metrics
kubectl port-forward -n default svc/my-promtail 3101:3101

# Check metrics
curl http://localhost:3101/metrics | grep promtail_sent_entries_total
```
Expected: `promtail_sent_entries_total > 0`

**5. Test Log Ingestion in Loki:**
```bash
# Port-forward to Loki
kubectl port-forward -n default svc/loki 3100:3100

# Query recent logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="promtail"}' \
  --data-urlencode "start=$(date -u -d '5 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" | jq '.data.result[0].values | length'
```
Expected: Non-zero number of log entries

---

## Rollback Procedures

### Scenario 1: Rollback via Helm History

**Use Case:** Recent upgrade failed or caused issues

**Procedure:**

1. **Check Helm history:**
```bash
helm history my-promtail -n default
```

**Example output:**
```
REVISION  UPDATED                   STATUS      CHART            DESCRIPTION
1         Mon Jun  9 10:00:00 2025  superseded  promtail-0.3.0   Install complete
2         Mon Jun  9 14:30:00 2025  deployed    promtail-0.4.0   Upgrade complete
```

2. **Rollback to previous revision:**
```bash
helm rollback my-promtail 1 -n default
```

3. **Wait for rollback to complete:**
```bash
kubectl rollout status daemonset/my-promtail -n default
```

4. **Verify rollback:**
```bash
# Check chart version
helm list -n default | grep promtail

# Check image version
kubectl get pods -n default -l app.kubernetes.io/name=promtail \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected RTO:** < 5 minutes

---

### Scenario 2: Rollback via Backup Restore

**Use Case:** Helm history unavailable or multiple revisions failed

**Procedure:**

1. **Uninstall current release:**
```bash
helm uninstall my-promtail -n default
```

2. **Restore from backup:**
```bash
# Use backed-up values
helm install my-promtail scripton-charts/promtail \
  --version 0.3.0 \
  -f promtail-values-backup-20250609.yaml \
  -n default
```

3. **Verify restoration:**
```bash
kubectl get daemonset -n default my-promtail
kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

**Expected RTO:** < 10 minutes

---

### Scenario 3: Emergency Rollback (Configuration Only)

**Use Case:** Configuration change caused issues, version is OK

**Procedure:**

1. **Restore previous ConfigMap:**
```bash
kubectl apply -f promtail-config-backup-20250609.yaml
```

2. **Restart Promtail pods:**
```bash
kubectl rollout restart daemonset/my-promtail -n default
kubectl rollout status daemonset/my-promtail -n default
```

3. **Verify logs are flowing:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=50
```

**Expected RTO:** < 5 minutes

---

## Troubleshooting

### Issue 1: Pods CrashLoopBackOff After Upgrade

**Symptom:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=promtail
NAME              READY   STATUS             RESTARTS
my-promtail-abc   0/1     CrashLoopBackOff   5
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n default my-promtail-abc

# Check events
kubectl describe pod -n default my-promtail-abc | grep -A10 Events
```

**Common Causes:**

1. **Configuration syntax error:**
```
Error: yaml: line 15: mapping values are not allowed in this context
```
**Solution:** Validate YAML syntax
```bash
# Export current ConfigMap
kubectl get configmap -n default promtail-config -o yaml > config.yaml

# Validate YAML
yamllint config.yaml

# Fix syntax errors and reapply
kubectl apply -f config.yaml
kubectl rollout restart daemonset/my-promtail -n default
```

2. **Loki endpoint unreachable:**
```
Error: Post "http://loki:3100/loki/api/v1/push": dial tcp: lookup loki: no such host
```
**Solution:** Verify Loki service
```bash
# Check Loki service exists
kubectl get svc -n default loki

# Update Loki URL in values.yaml
promtail:
  client:
    url: "http://loki.default.svc.cluster.local:3100/loki/api/v1/push"

# Upgrade with corrected config
helm upgrade my-promtail scripton-charts/promtail -f values.yaml -n default
```

---

### Issue 2: No Logs Being Sent to Loki

**Symptom:** Promtail pods running but no logs in Loki

**Diagnosis:**
```bash
# Check Promtail metrics
kubectl port-forward -n default svc/my-promtail 3101:3101
curl http://localhost:3101/metrics | grep promtail_sent_entries_total
```

**Output:**
```
promtail_sent_entries_total 0
```

**Common Causes:**

1. **Pipeline stage error:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=promtail | grep -i error
```

**Output:**
```
level=error msg="pipeline stage error" err="regex expression does not match"
```

**Solution:** Fix pipeline stages
```yaml
# Simplify pipeline to test
promtail:
  pipelineStages:
    cri:
      enabled: true
    custom: []  # Remove custom stages temporarily
```

2. **Label extraction issue:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=promtail | grep -i "label"
```

**Solution:** Check label configuration
```yaml
promtail:
  client:
    externalLabels:
      cluster: "kubernetes"  # Ensure labels are valid
```

---

### Issue 3: High Memory Usage After Upgrade

**Symptom:**
```bash
kubectl top pods -n default -l app.kubernetes.io/name=promtail
```

**Output:**
```
NAME              CPU(cores)   MEMORY(bytes)
my-promtail-abc   150m         256Mi
```

**Diagnosis:**
```bash
# Check resource limits
kubectl get pods -n default my-promtail-abc -o yaml | grep -A5 resources
```

**Common Causes:**

1. **Positions file growth:**
```bash
# Check positions file size
kubectl exec -n default my-promtail-abc -- du -h /run/promtail/positions.yaml
```

**Solution:** Reset positions file
```bash
kubectl exec -n default my-promtail-abc -- rm /run/promtail/positions.yaml
kubectl delete pod -n default my-promtail-abc
```

2. **Too many targets:**
```bash
# Check active targets
kubectl port-forward -n default svc/my-promtail 3101:3101
curl http://localhost:3101/metrics | grep promtail_targets_active
```

**Solution:** Filter targets with relabel_configs

---

### Issue 4: Upgrade Stuck "Waiting for rollout to finish"

**Symptom:**
```bash
kubectl rollout status daemonset/my-promtail -n default
```

**Output:**
```
Waiting for daemon set "my-promtail" rollout to finish: 1 out of 3 new pods have been updated...
```

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n default -l app.kubernetes.io/name=promtail -o wide

# Check events
kubectl get events -n default --sort-by='.lastTimestamp' | grep promtail
```

**Common Causes:**

1. **Node resource constraints:**
```bash
kubectl describe node <node-name> | grep -A5 "Allocated resources"
```

**Solution:** Reduce resource requests or add node capacity

2. **Update strategy blocking:**
```bash
kubectl get daemonset -n default my-promtail -o yaml | grep -A5 updateStrategy
```

**Solution:** Adjust maxUnavailable
```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 2  # Increase from 1
```

---

## Best Practices

### 1. Version Management

**DO:**
- ✅ Keep Promtail within 2 minor versions of Loki
- ✅ Test upgrades in dev/staging first
- ✅ Review release notes before upgrading
- ✅ Use explicit version tags (e.g., `3.3.0`, not `latest`)
- ✅ Pin Helm chart version in production

**DON'T:**
- ❌ Use `latest` tag in production
- ❌ Skip minor versions (e.g., 3.0.x → 3.3.x without testing)
- ❌ Upgrade Promtail without checking Loki compatibility
- ❌ Deploy untested versions to production

---

### 2. Configuration Management

**DO:**
- ✅ Store values.yaml in Git
- ✅ Use GitOps for deployments (ArgoCD, FluxCD)
- ✅ Backup ConfigMap before every upgrade
- ✅ Validate configuration syntax before applying
- ✅ Test pipeline stages in dev first

**DON'T:**
- ❌ Manually edit ConfigMap in production
- ❌ Skip configuration validation
- ❌ Deploy untested pipeline stages
- ❌ Store sensitive data unencrypted

---

### 3. Rollout Strategy

**DO:**
- ✅ Use rolling updates (DaemonSet default)
- ✅ Monitor rollout progress (`kubectl rollout status`)
- ✅ Set appropriate `maxUnavailable` (1-2 pods)
- ✅ Verify each node after update
- ✅ Have rollback plan ready

**DON'T:**
- ❌ Set `maxUnavailable` too high (>2)
- ❌ Proceed if rollout is stuck
- ❌ Ignore pod errors during rollout
- ❌ Delete old pods manually during rollout

---

### 4. Monitoring and Validation

**DO:**
- ✅ Monitor Promtail metrics (sent_entries, dropped_entries)
- ✅ Set up alerts for pod failures
- ✅ Validate log ingestion in Loki after upgrade
- ✅ Check for errors in Promtail logs
- ✅ Run post-upgrade validation script

**DON'T:**
- ❌ Assume upgrade succeeded without validation
- ❌ Ignore warnings in logs
- ❌ Skip Loki connectivity checks
- ❌ Deploy and forget

---

## Summary

Promtail upgrades are straightforward due to its stateless nature:

**Key Points:**
- **Rolling updates** supported with minimal disruption
- **No data loss** (Promtail is stateless)
- **Configuration-driven** (test pipeline changes first)
- **Version compatibility** with Loki is critical

**Recommended Upgrade Flow:**
1. **Pre-upgrade**: Backup config, verify Loki compatibility, test in staging
2. **Upgrade**: Rolling update via Helm
3. **Post-upgrade**: Validate pods, check metrics, verify log ingestion
4. **Rollback**: Ready if issues arise (< 5 minutes)

**Upgrade Timeline:**
- **Preparation**: 15-30 minutes (backup, review, test)
- **Execution**: 2-5 minutes (rolling update)
- **Validation**: 5-10 minutes (post-upgrade checks)
- **Total**: 30-45 minutes

---

**Related Documentation:**
- [Promtail Backup Guide](promtail-backup-guide.md)
- [Promtail Chart README](../charts/promtail/README.md)
- [Loki Upgrade Guide](loki-upgrade-guide.md)
- [Grafana Promtail Documentation](https://grafana.com/docs/loki/latest/send-data/promtail/)

**Last Updated:** 2025-12-09
