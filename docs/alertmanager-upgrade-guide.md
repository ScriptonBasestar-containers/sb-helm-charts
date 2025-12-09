# Alertmanager Upgrade Guide

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

Alertmanager handles alerts from Prometheus and routes them to receivers. Upgrading Alertmanager requires careful planning due to:

- **Configuration schema changes** (routing rules, receivers)
- **API changes** (v1 vs v2)
- **Clustering protocol updates** (gossip, mesh)
- **Runtime state** (active silences, notifications)

**Key Considerations:**
- Alertmanager version should be compatible with Prometheus version
- Configuration syntax may change between major versions
- Silences are runtime state (backup before upgrade)
- Clustering requires coordinated upgrade

**Upgrade Impact:**
- **Downtime**: < 1 minute (rolling update) or 5-15 minutes (full restart)
- **Silence Loss**: Possible (backup required)
- **Configuration Changes**: May be required (see version-specific notes)

---

## Version Compatibility

### Alertmanager and Prometheus Version Matrix

Alertmanager versions should be compatible with Prometheus:

| Alertmanager Version | Compatible Prometheus | Release Date | Notable Changes |
|----------------------|----------------------|--------------|-----------------|
| **0.27.x** | 2.45.x - 2.50.x | 2024-02 | UTF-8 support in templates, improved clustering |
| **0.26.x** | 2.40.x - 2.47.x | 2023-08 | API v2 stabilization, new receiver types |
| **0.25.x** | 2.37.x - 2.45.x | 2023-01 | Template improvements, webhook enhancements |
| **0.24.x** | 2.30.x - 2.40.x | 2022-01 | Configuration validation improvements |
| **0.23.x** | 2.28.x - 2.37.x | 2021-08 | Clustering improvements, API v2 beta |

**General Rule:** Keep Alertmanager within 2-3 minor versions of Prometheus

**Example:**
- Prometheus 2.47.0 → Use Alertmanager 0.26.x - 0.27.x ✅
- Prometheus 2.45.0 → Use Alertmanager 0.25.x - 0.27.x ✅
- Prometheus 2.30.0 → Use Alertmanager 0.27.x ❌ (version gap too large)

### Helm Chart Version Compatibility

| Chart Version | Alertmanager Version | Kubernetes Version | Notes |
|---------------|---------------------|--------------------|-------|
| **0.4.x** | 0.27.x | 1.24+ | Enhanced RBAC, comprehensive docs |
| **0.3.x** | 0.26.x | 1.23+ | Production-ready |
| **0.2.x** | 0.25.x | 1.22+ | Beta release |
| **0.1.x** | 0.24.x | 1.21+ | Initial release |

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**Check for breaking changes:**

```bash
# View Alertmanager release notes
open https://github.com/prometheus/alertmanager/releases

# Check chart CHANGELOG
cat charts/alertmanager/CHANGELOG.md
```

**Key areas to review:**
- Configuration schema changes
- API deprecations
- Receiver configuration changes
- Clustering protocol updates

---

### 2. Backup Current Configuration and Silences

**Backup Helm values, ConfigMap, and silences:**

```bash
# Backup current Helm values
helm get values my-alertmanager -n default > alertmanager-values-backup-$(date +%Y%m%d).yaml

# Backup ConfigMap
kubectl get configmap -n default my-alertmanager-config -o yaml > alertmanager-config-backup-$(date +%Y%m%d).yaml

# Backup silences
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > silences-backup-$(date +%Y%m%d).json

# Backup entire Helm manifest
helm get manifest my-alertmanager -n default > alertmanager-manifest-backup-$(date +%Y%m%d).yaml
```

**Store backups in secure location:**
```bash
cp alertmanager-*-backup-*.yaml backups/alertmanager/
cp silences-backup-*.json backups/alertmanager/
```

---

### 3. Verify Current State

**Check current deployment:**

```bash
# Check Helm release
helm list -n default | grep alertmanager

# Check StatefulSet status
kubectl get statefulset -n default my-alertmanager

# Check all pods are running
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager

# Check Alertmanager version
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected output:**
```
NAME              CHART               STATUS    NAMESPACE
my-alertmanager   alertmanager-0.3.0  deployed  default

NAME              READY   AGE
my-alertmanager   1/1     10d

NAME                READY   STATUS    RESTARTS   AGE
my-alertmanager-0   1/1     Running   0          10d

prom/alertmanager:v0.26.0
```

---

### 4. Check Prometheus Compatibility

**Verify Prometheus version:**

```bash
# Get Prometheus version
kubectl get pods -n default -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.containers[0].image}'

# Or via Prometheus API
kubectl port-forward -n default svc/prometheus 9090:9090 &
curl http://localhost:9090/api/v1/status/buildinfo | jq '.data.version'
kill %1
```

**Verify compatibility:** Check [Version Compatibility Matrix](#alertmanager-and-prometheus-version-matrix)

---

### 5. Test in Dev/Staging

**Deploy upgrade in test environment:**

```bash
# Test upgrade in staging namespace
helm upgrade alertmanager-staging scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  -n staging
```

**Verify:**
- Pods start successfully
- Alerts are being routed correctly
- No errors in Alertmanager logs
- Silences are preserved
- Receivers are working

---

### 6. Plan Maintenance Window (Optional)

For production upgrades, consider:
- **Low-traffic period** (e.g., off-peak hours)
- **Communication** with stakeholders about potential alert delays
- **Rollback plan** ready

**Note:** Alertmanager supports rolling updates with minimal disruption, so maintenance window is optional.

---

## Upgrade Strategies

Alertmanager supports three upgrade strategies:

### Strategy 1: Rolling Update (Recommended)

**Best for:** Production environments, HA setups (replicaCount > 1)

**Downtime:** < 1 minute (brief clustering re-mesh)

**Alert Loss:** None (clustered instances take over)

**Procedure:**

1. **Ensure HA is enabled:**
```bash
# Check replica count
helm get values my-alertmanager -n default | grep replicaCount
```

2. **Update Helm chart:**
```bash
# Upgrade with new chart version
helm upgrade my-alertmanager scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  -n default \
  --wait
```

3. **Monitor rollout:**
```bash
# Watch StatefulSet rollout status
kubectl rollout status statefulset/my-alertmanager -n default

# Watch pod updates in real-time
watch kubectl get pods -n default -l app.kubernetes.io/name=alertmanager
```

4. **Verify each pod:**
```bash
# Check updated pods
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o wide

# Verify new image version
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

**Expected output:**
```
Waiting for statefulset rolling update to complete 0 pods at revision my-alertmanager-xxx...
Waiting for 1 pods to be ready...
Waiting for statefulset rolling update to complete 1 pods at revision my-alertmanager-xxx...
statefulset rolling update complete 2 pods at revision my-alertmanager-xxx...
```

**Rolling Update Timeline (HA with 2 replicas):**
```
Pod 0: Old version → Stop → New version → Running (30s - 1min)
  ↓ (Pod 1 handles alerts during Pod 0 upgrade)
Pod 1: Old version → Stop → New version → Running (30s - 1min)
  ↓ (Pod 0 handles alerts during Pod 1 upgrade)
Both pods Running (Clustering re-establishes)
```

**Total Time:** 2-5 minutes (depends on replica count)

---

### Strategy 2: Blue-Green Deployment (Zero Downtime)

**Best for:** Major version upgrades with high risk

**Downtime:** None (brief during traffic switch)

**Alert Loss:** None

**Procedure:**

1. **Deploy green environment (new version):**
```bash
# Deploy new Alertmanager with different name
helm install my-alertmanager-green scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  --set fullnameOverride=alertmanager-green \
  -n default
```

2. **Restore silences to green:**
```bash
# Wait for green to be ready
kubectl wait --for=condition=ready pod -n default -l app.kubernetes.io/instance=alertmanager-green --timeout=300s

# Port-forward to green
kubectl port-forward -n default svc/alertmanager-green 9093:9093 &

# Import silences
cat silences-backup-20250609.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done

kill %1
```

3. **Test green deployment:**
```bash
# Send test alert to green
kubectl run -it --rm test-alert --image=curlimages/curl --restart=Never -- \
  curl -X POST http://alertmanager-green.default.svc.cluster.local:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"info"},"annotations":{"summary":"Test"}}]'

# Verify green is working
kubectl logs -n default -l app.kubernetes.io/instance=alertmanager-green --tail=100
```

4. **Update Prometheus to point to green:**
```bash
# Update Prometheus alertmanagers configuration
# Edit Prometheus ConfigMap to point to alertmanager-green service

kubectl edit configmap -n default prometheus-config

# Change:
#   alertmanagers:
#   - static_configs:
#     - targets: ['my-alertmanager:9093']
# To:
#   alertmanagers:
#   - static_configs:
#     - targets: ['alertmanager-green:9093']

# Reload Prometheus configuration
kubectl exec -n default prometheus-0 -- killall -HUP prometheus
```

5. **Monitor for 24 hours, then decommission blue:**
```bash
# After confidence is gained
helm uninstall my-alertmanager -n default

# Rename green to primary
helm upgrade alertmanager-green scripton-charts/alertmanager \
  --reuse-values \
  --set fullnameOverride=alertmanager \
  -n default
```

---

### Strategy 3: Maintenance Window Upgrade (Full Restart)

**Best for:** Single instance, major version jumps

**Downtime:** 5-15 minutes

**Alert Loss:** Possible (alerts during downtime)

**Procedure:**

1. **Announce maintenance window:**
```bash
# Create silence for all alerts
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": ".*", "isRegex": true}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "admin",
    "comment": "Alertmanager upgrade maintenance window"
  }'

kill %1
```

2. **Backup silences:**
```bash
# Already done in pre-upgrade checklist
```

3. **Upgrade:**
```bash
# Uninstall old version
helm uninstall my-alertmanager -n default

# Wait for cleanup
kubectl wait --for=delete pod -n default -l app.kubernetes.io/name=alertmanager --timeout=60s

# Install new version
helm install my-alertmanager scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  -f alertmanager-values-backup-20250609.yaml \
  -n default --wait
```

4. **Restore silences:**
```bash
# Wait for Alertmanager to be ready
kubectl wait --for=condition=ready pod -n default -l app.kubernetes.io/name=alertmanager --timeout=300s

# Port-forward
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

# Import silences
cat silences-backup-20250609.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done

kill %1
```

**Total Time:** 10-20 minutes

---

## Version-Specific Notes

### Alertmanager 0.27.x

**Release Date:** February 2024

**Key Changes:**
- **UTF-8 Support**: Full UTF-8 support in notification templates
- **Improved Clustering**: Better gossip protocol reliability
- **API Enhancements**: New endpoints for cluster status

**Configuration Changes:**

1. **Template UTF-8 (Automatic):**
```yaml
# No changes needed - UTF-8 is now fully supported in templates
templates:
  - '/etc/alertmanager/templates/*.tmpl'
```

2. **Clustering Improvements (Automatic):**
```yaml
# Clustering is more stable - no configuration changes required
# But consider increasing cluster-reconnect-timeout for large clusters
alertmanager:
  extraArgs:
    - --cluster.reconnect-timeout=5m  # Default is 5m
```

**Upgrade Notes:**
- No breaking changes
- Configuration is backward compatible
- Templates with UTF-8 characters will render correctly

---

### Alertmanager 0.26.x

**Release Date:** August 2023

**Key Changes:**
- **API v2 Stabilization**: API v2 is now stable and recommended
- **New Receiver Types**: Support for Discord, Telegram
- **Webhook Enhancements**: Better retry logic

**Configuration Changes:**

1. **New Receiver Types (Optional):**
```yaml
receivers:
  - name: discord-alerts
    discord_configs:
      - webhook_url: 'https://discord.com/api/webhooks/...'
        title: '{{ .Status | toUpper }}: {{ .GroupLabels.alertname }}'

  - name: telegram-alerts
    telegram_configs:
      - bot_token: 'your-bot-token'
        chat_id: 123456789
        message: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
```

2. **Webhook Retry Logic (Automatic):**
```yaml
# Webhook retry is now more reliable - no changes needed
receivers:
  - name: webhook
    webhook_configs:
      - url: 'http://example.com/webhook'
        # Retry logic is improved automatically
```

**Upgrade Notes:**
- No breaking changes
- API v1 still supported but deprecated
- Consider migrating to API v2

---

### Alertmanager 0.25.x

**Release Date:** January 2023

**Key Changes:**
- **Template Improvements**: Better error messages
- **Webhook Enhancements**: Custom headers support
- **Configuration Validation**: Stricter validation

**Configuration Changes:**

1. **Webhook Custom Headers (New Feature):**
```yaml
receivers:
  - name: webhook-with-auth
    webhook_configs:
      - url: 'http://example.com/webhook'
        http_config:
          headers:
            Authorization: 'Bearer token123'
            X-Custom-Header: 'value'
```

2. **Configuration Validation (Stricter):**
```yaml
# Ensure all required fields are present
route:
  receiver: default  # Required (was optional before)
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

receivers:
  - name: default  # Must match route.receiver
```

**Upgrade Notes:**
- Configuration validation is stricter
- Fix any warnings in pre-upgrade validation
- Custom headers are now supported in webhooks

---

### Alertmanager 0.24.x

**Release Date:** January 2022

**Key Changes:**
- **Configuration Validation**: Improved error messages
- **Clustering**: Better peer discovery

**Configuration Changes:**

No significant configuration changes. Version is stable.

**Upgrade Notes:**
- No breaking changes
- Safe to upgrade from 0.23.x

---

### API v1 to API v2 Migration

**If migrating from API v1 to v2:**

**API v1 (Deprecated):**
```bash
# Old silence creation
curl -X POST http://localhost:9093/api/v1/silences \
  -d '{"matchers":[{"name":"alertname","value":"HighCPU"}],"startsAt":"...","endsAt":"...","createdBy":"admin","comment":"Maintenance"}'
```

**API v2 (Recommended):**
```bash
# New silence creation
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "alertname",
        "value": "HighCPU",
        "isRegex": false,
        "isEqual": true
      }
    ],
    "startsAt": "...",
    "endsAt": "...",
    "createdBy": "admin",
    "comment": "Maintenance"
  }'
```

**Key Differences:**
- `isRegex` and `isEqual` fields added to matchers
- Content-Type header required for v2
- Response format changed

---

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# Script: alertmanager-post-upgrade-check.sh
# Description: Validate Alertmanager after upgrade

set -e

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-alertmanager}"

echo "=== Alertmanager Post-Upgrade Validation ==="

# 1. Check Helm release status
echo "1/6 Checking Helm release..."
HELM_STATUS=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '.info.status')
if [ "$HELM_STATUS" != "deployed" ]; then
  echo "❌ FAIL: Helm release status is $HELM_STATUS (expected: deployed)"
  exit 1
fi
echo "✅ PASS: Helm release is deployed"

# 2. Check StatefulSet rollout
echo "2/6 Checking StatefulSet rollout..."
kubectl rollout status statefulset/"$RELEASE_NAME" -n "$NAMESPACE" --timeout=5m
echo "✅ PASS: StatefulSet rollout complete"

# 3. Check all pods are running
echo "3/6 Checking pod status..."
DESIRED=$(kubectl get statefulset -n "$NAMESPACE" "$RELEASE_NAME" -o jsonpath='{.spec.replicas}')
READY=$(kubectl get statefulset -n "$NAMESPACE" "$RELEASE_NAME" -o jsonpath='{.status.readyReplicas}')
if [ "$DESIRED" != "$READY" ]; then
  echo "❌ FAIL: Only $READY/$DESIRED pods are ready"
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager
  exit 1
fi
echo "✅ PASS: All $READY pods are running"

# 4. Check for errors in logs
echo "4/6 Checking Alertmanager logs for errors..."
ERRORS=$(kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager --tail=100 --since=5m | grep -i "error\|fatal" | wc -l)
if [ "$ERRORS" -gt 0 ]; then
  echo "⚠️  WARNING: Found $ERRORS errors in logs (check manually)"
  kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager --tail=100 --since=5m | grep -i "error"
else
  echo "✅ PASS: No errors in recent logs"
fi

# 5. Check Alertmanager health
echo "5/6 Checking Alertmanager health..."
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n "$NAMESPACE" "$POD" -- wget -qO- http://localhost:9093/-/healthy >/dev/null 2>&1 && \
  echo "✅ PASS: Alertmanager is healthy" || \
  (echo "❌ FAIL: Alertmanager health check failed" && exit 1)

# 6. Check clustering status (if HA)
echo "6/6 Checking cluster status..."
REPLICAS=$(kubectl get statefulset -n "$NAMESPACE" "$RELEASE_NAME" -o jsonpath='{.spec.replicas}')
if [ "$REPLICAS" -gt 1 ]; then
  CLUSTER_STATUS=$(kubectl exec -n "$NAMESPACE" "$POD" -- wget -qO- http://localhost:9093/api/v2/status | jq -r '.cluster.status')
  if [ "$CLUSTER_STATUS" == "ready" ]; then
    echo "✅ PASS: Cluster is ready"
  else
    echo "⚠️  WARNING: Cluster status is $CLUSTER_STATUS (expected: ready)"
  fi
else
  echo "✅ PASS: Single instance (no clustering)"
fi

echo ""
echo "=== Post-Upgrade Validation Complete ==="
echo "Status: ✅ Upgrade successful"
```

**Run validation:**
```bash
chmod +x alertmanager-post-upgrade-check.sh
./alertmanager-post-upgrade-check.sh
```

**Expected output:**
```
=== Alertmanager Post-Upgrade Validation ===
1/6 Checking Helm release...
✅ PASS: Helm release is deployed
2/6 Checking StatefulSet rollout...
✅ PASS: StatefulSet rollout complete
3/6 Checking pod status...
✅ PASS: All 2 pods are running
4/6 Checking Alertmanager logs for errors...
✅ PASS: No errors in recent logs
5/6 Checking Alertmanager health...
✅ PASS: Alertmanager is healthy
6/6 Checking cluster status...
✅ PASS: Cluster is ready

=== Post-Upgrade Validation Complete ===
Status: ✅ Upgrade successful
```

---

### Manual Verification Checklist

**1. Check StatefulSet Status:**
```bash
kubectl get statefulset -n default my-alertmanager
```
Expected: `READY = X/X` (all replicas ready)

**2. Check Pod Health:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager
```
Expected: All pods `STATUS=Running`, `READY=1/1`

**3. Check Alertmanager Logs:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=alertmanager --tail=100
```
Expected: No errors, logs show successful startup

**4. Verify Silences:**
```bash
# Port-forward to Alertmanager
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

# List silences
curl http://localhost:9093/api/v2/silences | jq '.[] | {id, comment}'

kill %1
```
Expected: Silences are present (if restored)

**5. Test Alert Routing:**
```bash
# Send test alert
kubectl run -it --rm test-alert --image=curlimages/curl --restart=Never -- \
  curl -X POST http://my-alertmanager.default.svc.cluster.local:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"info"},"annotations":{"summary":"Upgrade test"}}]'

# Check alert was received
kubectl logs -n default -l app.kubernetes.io/name=alertmanager --tail=50 | grep TestAlert
```
Expected: Alert is received and routed

---

## Rollback Procedures

### Scenario 1: Rollback via Helm History

**Use Case:** Recent upgrade failed or caused issues

**Procedure:**

1. **Check Helm history:**
```bash
helm history my-alertmanager -n default
```

**Example output:**
```
REVISION  UPDATED                   STATUS      CHART                DESCRIPTION
1         Mon Jun  9 10:00:00 2025  superseded  alertmanager-0.3.0   Install complete
2         Mon Jun  9 14:30:00 2025  deployed    alertmanager-0.4.0   Upgrade complete
```

2. **Rollback to previous revision:**
```bash
helm rollback my-alertmanager 1 -n default
```

3. **Wait for rollback to complete:**
```bash
kubectl rollout status statefulset/my-alertmanager -n default
```

4. **Verify rollback:**
```bash
# Check chart version
helm list -n default | grep alertmanager

# Check image version
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected RTO:** < 5 minutes

---

### Scenario 2: Rollback via Backup Restore

**Use Case:** Helm history unavailable or multiple revisions failed

**Procedure:**

1. **Uninstall current release:**
```bash
helm uninstall my-alertmanager -n default
```

2. **Restore from backup:**
```bash
# Use backed-up values
helm install my-alertmanager scripton-charts/alertmanager \
  --version 0.3.0 \
  -f alertmanager-values-backup-20250609.yaml \
  -n default
```

3. **Restore silences:**
```bash
# Wait for Alertmanager to be ready
kubectl wait --for=condition=ready pod -n default -l app.kubernetes.io/name=alertmanager --timeout=300s

# Import silences
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &
cat silences-backup-20250609.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done
kill %1
```

4. **Verify restoration:**
```bash
kubectl get statefulset -n default my-alertmanager
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager
```

**Expected RTO:** < 10 minutes

---

### Scenario 3: Emergency Rollback (Configuration Only)

**Use Case:** Configuration change caused issues, version is OK

**Procedure:**

1. **Restore previous ConfigMap:**
```bash
kubectl apply -f alertmanager-config-backup-20250609.yaml
```

2. **Restart Alertmanager pods:**
```bash
kubectl rollout restart statefulset/my-alertmanager -n default
kubectl rollout status statefulset/my-alertmanager -n default
```

3. **Verify configuration:**
```bash
kubectl get configmap -n default my-alertmanager-config -o yaml
```

**Expected RTO:** < 5 minutes

---

## Troubleshooting

### Issue 1: Pods CrashLoopBackOff After Upgrade

**Symptom:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager
NAME                  READY   STATUS             RESTARTS
my-alertmanager-0     0/1     CrashLoopBackOff   5
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n default my-alertmanager-0

# Check events
kubectl describe pod -n default my-alertmanager-0 | grep -A10 Events
```

**Common Causes:**

1. **Configuration syntax error:**
```
level=error ts=2025-06-09T14:30:00Z caller=main.go:123 msg="failed to load config" err="yaml: unmarshal error"
```
**Solution:** Validate configuration syntax
```bash
# Export current ConfigMap
kubectl get configmap -n default my-alertmanager-config -o yaml > config.yaml

# Validate YAML
yamllint config.yaml

# Fix errors and reapply
kubectl apply -f config.yaml
kubectl rollout restart statefulset/my-alertmanager -n default
```

2. **Incompatible configuration schema:**
```
level=error ts=2025-06-09T14:30:00Z caller=main.go:123 msg="unknown field in config"
```
**Solution:** Review version-specific notes and update configuration

---

### Issue 2: Silences Lost After Upgrade

**Symptom:** All silences are gone after upgrade

**Cause:** Silences were not backed up before upgrade

**Solution:**

1. **Restore from backup (if available):**
```bash
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &
cat silences-backup-20250609.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done
kill %1
```

2. **If no backup, recreate manually:**
```bash
# Create new silences via UI or API
kubectl port-forward -n default svc/my-alertmanager 9093:9093

# Visit http://localhost:9093 and create silences via UI
```

**Prevention:** Always backup silences before upgrades

---

### Issue 3: Clustering Not Working

**Symptom:**
```bash
kubectl exec -n default my-alertmanager-0 -- wget -qO- http://localhost:9093/api/v2/status | jq '.cluster.status'
# Output: "disabled" or "not ready"
```

**Diagnosis:**
```bash
# Check cluster peers
kubectl logs -n default -l app.kubernetes.io/name=alertmanager | grep cluster
```

**Common Causes:**

1. **Headless service not found:**
```
level=error msg="failed to join cluster" err="no such host"
```
**Solution:** Verify headless service exists
```bash
kubectl get service -n default my-alertmanager-headless
```

2. **Network policy blocking gossip:**
```
level=error msg="failed to join cluster" err="connection refused"
```
**Solution:** Check NetworkPolicy allows port 9094

---

### Issue 4: Configuration Validation Fails

**Symptom:**
```
Error: UPGRADE FAILED: failed to create resource: admission webhook denied the request
```

**Cause:** Strict validation in newer versions

**Solution:**

1. **Export and validate configuration:**
```bash
helm get values my-alertmanager -n default > values.yaml

# Test upgrade with --dry-run
helm upgrade my-alertmanager scripton-charts/alertmanager \
  --version 0.4.0 \
  -f values.yaml \
  --dry-run
```

2. **Fix validation errors:**
```yaml
# Ensure all required fields are present
route:
  receiver: default  # Required
  group_by: ['alertname']

receivers:
  - name: default  # Must match route.receiver
```

---

## Best Practices

### 1. Version Management

**DO:**
- ✅ Keep Alertmanager within 2-3 versions of Prometheus
- ✅ Test upgrades in dev/staging first
- ✅ Review release notes before upgrading
- ✅ Use explicit version tags (e.g., `v0.27.0`, not `latest`)
- ✅ Pin Helm chart version in production

**DON'T:**
- ❌ Use `latest` tag in production
- ❌ Skip minor versions (e.g., 0.24.x → 0.27.x without testing)
- ❌ Upgrade without checking Prometheus compatibility
- ❌ Deploy untested versions to production

---

### 2. Configuration Management

**DO:**
- ✅ Store alertmanager.yml in Git
- ✅ Use GitOps for deployments (ArgoCD, FluxCD)
- ✅ Backup ConfigMap and silences before every upgrade
- ✅ Validate configuration syntax before applying
- ✅ Test routing rules in dev first

**DON'T:**
- ❌ Manually edit ConfigMap in production
- ❌ Skip configuration validation
- ❌ Deploy untested routing rules
- ❌ Store credentials unencrypted

---

### 3. Rollout Strategy

**DO:**
- ✅ Use rolling updates for HA deployments (replicaCount > 1)
- ✅ Monitor rollout progress (`kubectl rollout status`)
- ✅ Backup silences before upgrade
- ✅ Verify each pod after update
- ✅ Have rollback plan ready

**DON'T:**
- ❌ Upgrade single instance without maintenance window
- ❌ Proceed if rollout is stuck
- ❌ Ignore pod errors during rollout
- ❌ Delete pods manually during rollout

---

### 4. Monitoring and Validation

**DO:**
- ✅ Monitor Alertmanager metrics (alerts_received, notifications_sent)
- ✅ Set up alerts for Alertmanager pod failures
- ✅ Validate alert routing after upgrade
- ✅ Check for errors in logs
- ✅ Run post-upgrade validation script

**DON'T:**
- ❌ Assume upgrade succeeded without validation
- ❌ Ignore warnings in logs
- ❌ Skip clustering status checks (HA deployments)
- ❌ Deploy and forget

---

## Summary

Alertmanager upgrades require attention to configuration and runtime state:

**Key Points:**
- **Rolling updates** supported for HA deployments
- **Silences are runtime state** (backup required)
- **Configuration validation** is stricter in newer versions
- **Version compatibility** with Prometheus is critical

**Recommended Upgrade Flow:**
1. **Pre-upgrade**: Backup config and silences, verify Prometheus compatibility, test in staging
2. **Upgrade**: Rolling update via Helm (HA) or maintenance window (single instance)
3. **Post-upgrade**: Validate pods, restore silences, test alert routing
4. **Rollback**: Ready if issues arise (< 5 minutes)

**Upgrade Timeline:**
- **Preparation**: 15-30 minutes (backup, review, test)
- **Execution**: 2-5 minutes (rolling update) or 10-20 minutes (maintenance window)
- **Validation**: 5-10 minutes (post-upgrade checks)
- **Total**: 30-60 minutes

---

**Related Documentation:**
- [Alertmanager Backup Guide](alertmanager-backup-guide.md)
- [Alertmanager Chart README](../charts/alertmanager/README.md)
- [Prometheus Upgrade Guide](prometheus-upgrade-guide.md)
- [Grafana Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)

**Last Updated:** 2025-12-09
