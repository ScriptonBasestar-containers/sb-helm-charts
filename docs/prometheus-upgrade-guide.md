# Prometheus Upgrade Guide

## Table of Contents

1. [Overview](#overview)
2. [Pre-Upgrade Preparation](#pre-upgrade-preparation)
3. [Upgrade Strategies](#upgrade-strategies)
4. [Version-Specific Notes](#version-specific-notes)
5. [Post-Upgrade Validation](#post-upgrade-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive procedures for upgrading Prometheus deployments managed by this Helm chart, ensuring zero-downtime upgrades and data integrity.

### Upgrade Complexity

| Component | Complexity | Downtime Required | Notes |
|-----------|------------|-------------------|-------|
| **Prometheus Server** | Medium | No (with HA) | StatefulSet rolling update |
| **Configuration** | Low | No | ConfigMap + reload |
| **Storage/TSDB** | Low | No | Backward compatible |
| **Recording Rules** | Low | No | ConfigMap + reload |
| **Alerting Rules** | Low | No | ConfigMap + reload |
| **Major Version** | High | Recommended | Breaking changes possible |

### Supported Upgrade Paths

| From Version | To Version | Strategy | Notes |
|--------------|------------|----------|-------|
| 2.x → 2.y | 2.z | Rolling | Patch upgrades (safe) |
| 2.x → 3.0 | 3.x | Rolling/Blue-Green | Major version (review breaking changes) |
| 3.x → 3.y | 3.z | Rolling | Minor/patch upgrades (safe) |

---

## Pre-Upgrade Preparation

### 1. Pre-Upgrade Checklist

```bash
#!/bin/bash
# pre-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
RELEASE_NAME="${RELEASE_NAME:-prometheus}"
POD_NAME="${POD_NAME:-prometheus-0}"

echo "=== Prometheus Pre-Upgrade Checklist ==="
echo ""

# 1. Check current version
echo "[1/10] Checking current Prometheus version..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  prometheus --version 2>&1 | head -1 | awk '{print $3}')
echo "  Current version: $CURRENT_VERSION"

# 2. Check pod health
echo "[2/10] Checking pod health..."
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
  echo "  ERROR: Pod is not running (status: $POD_STATUS)"
  exit 1
fi
echo "  Pod status: $POD_STATUS ✓"

# 3. Check Prometheus ready
echo "[3/10] Checking if Prometheus is ready..."
READY=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/-/ready 2>&1)
if [[ "$READY" != *"Prometheus Server is Ready"* ]]; then
  echo "  ERROR: Prometheus is not ready"
  exit 1
fi
echo "  Prometheus is ready ✓"

# 4. Check TSDB status
echo "[4/10] Checking TSDB status..."
TSDB_STATUS=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb 2>/dev/null | jq -r '.status')
if [ "$TSDB_STATUS" != "success" ]; then
  echo "  WARNING: TSDB status check failed"
else
  echo "  TSDB status: OK ✓"
fi

# 5. Check active targets
echo "[5/10] Checking active scrape targets..."
ACTIVE_TARGETS=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null | \
  jq '.data.activeTargets | length')
echo "  Active targets: $ACTIVE_TARGETS"

# 6. Check storage usage
echo "[6/10] Checking storage usage..."
STORAGE_USED=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  df -h /prometheus | tail -1 | awk '{print $5}')
echo "  Storage used: $STORAGE_USED"
if [[ "${STORAGE_USED%\%}" -gt 90 ]]; then
  echo "  WARNING: Storage usage above 90%"
fi

# 7. Check configuration validity
echo "[7/10] Validating configuration..."
CONFIG_CHECK=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  promtool check config /etc/prometheus/prometheus.yml 2>&1)
if [[ "$CONFIG_CHECK" == *"SUCCESS"* ]]; then
  echo "  Configuration is valid ✓"
else
  echo "  ERROR: Configuration validation failed"
  echo "$CONFIG_CHECK"
  exit 1
fi

# 8. Check PVC status
echo "[8/10] Checking PVC status..."
PVC_STATUS=$(kubectl get pvc -n $NAMESPACE prometheus-$RELEASE_NAME-0 \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "  PVC status: $PVC_STATUS"

# 9. Check for active alerts
echo "[9/10] Checking for active alerts..."
ACTIVE_ALERTS=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null | \
  jq '.data.alerts | map(select(.state == "firing")) | length')
echo "  Active firing alerts: $ACTIVE_ALERTS"
if [ "$ACTIVE_ALERTS" -gt 0 ]; then
  echo "  WARNING: There are active firing alerts"
fi

# 10. Check WAL (Write-Ahead Log) status
echo "[10/10] Checking WAL status..."
WAL_SIZE=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  du -sh /prometheus/wal 2>/dev/null | cut -f1)
echo "  WAL size: $WAL_SIZE"

echo ""
echo "=== Pre-Upgrade Check Completed ==="
echo ""
echo "Summary:"
echo "  Current Version: $CURRENT_VERSION"
echo "  Pod Health: OK"
echo "  Active Targets: $ACTIVE_TARGETS"
echo "  Storage Used: $STORAGE_USED"
echo "  Active Alerts: $ACTIVE_ALERTS"
echo ""
echo "Next Steps:"
echo "  1. Create backup: make -f make/ops/prometheus.mk prom-backup-all"
echo "  2. Review release notes for target version"
echo "  3. Proceed with upgrade strategy"
```

### 2. Backup Before Upgrade

**CRITICAL: Always backup before upgrading!**

```bash
# Full backup (TSDB + config + rules)
make -f make/ops/prometheus.mk prom-backup-all

# Verify backup
ls -lh backups/prometheus/full/
```

See [Prometheus Backup Guide](prometheus-backup-guide.md) for detailed backup procedures.

### 3. Review Release Notes

Check Prometheus release notes for breaking changes:

- [Prometheus Releases](https://github.com/prometheus/prometheus/releases)
- [Prometheus Changelog](https://github.com/prometheus/prometheus/blob/main/CHANGELOG.md)

**Key areas to review:**
- Configuration changes
- Deprecated flags
- Storage format changes
- API changes
- PromQL changes

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Recommended)

**Best for**: Minor/patch version upgrades, production with HA

**Downtime**: None (with HA setup, replicas ≥ 2)

**Complexity**: Low

#### Steps:

```bash
#!/bin/bash
# rolling-upgrade.sh

set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
NEW_VERSION="3.7.3"  # Target version

echo "=== Prometheus Rolling Upgrade ==="
echo "Target version: $NEW_VERSION"
echo ""

# 1. Pre-upgrade backup
echo "[1/6] Creating pre-upgrade backup..."
make -f make/ops/prometheus.mk prom-backup-all

# 2. Update Helm repository
echo "[2/6] Updating Helm repository..."
helm repo update

# 3. Check what will change
echo "[3/6] Checking upgrade diff..."
helm diff upgrade $RELEASE_NAME scripton-charts/prometheus \
  -n $NAMESPACE \
  --set image.tag=$NEW_VERSION \
  --reuse-values || echo "helm diff plugin not installed"

# 4. Perform upgrade
echo "[4/6] Performing Helm upgrade..."
helm upgrade $RELEASE_NAME scripton-charts/prometheus \
  -n $NAMESPACE \
  --set image.tag=$NEW_VERSION \
  --reuse-values \
  --wait \
  --timeout 10m

# 5. Monitor rollout
echo "[5/6] Monitoring rollout status..."
kubectl rollout status statefulset/$RELEASE_NAME -n $NAMESPACE --timeout=600s

# 6. Post-upgrade validation
echo "[6/6] Running post-upgrade validation..."
./post-upgrade-check.sh

echo ""
echo "=== Rolling Upgrade Completed ==="
```

**Advantages:**
- Zero downtime with HA (replicas ≥ 2)
- Kubernetes-native (StatefulSet rolling update)
- Automatic rollback on failure

**Disadvantages:**
- Slower for single replica
- Mixed versions temporarily during upgrade

### Strategy 2: Blue-Green Deployment

**Best for**: Major version upgrades, high-risk changes

**Downtime**: 10-30 minutes (during cutover)

**Complexity**: Medium

#### Steps:

```bash
#!/bin/bash
# blue-green-upgrade.sh

set -e

NAMESPACE="monitoring"
BLUE_RELEASE="prometheus"  # Current (old)
GREEN_RELEASE="prometheus-green"  # New
NEW_VERSION="3.7.3"

echo "=== Prometheus Blue-Green Upgrade ==="
echo "Blue (current): $BLUE_RELEASE"
echo "Green (new): $GREEN_RELEASE"
echo "Target version: $NEW_VERSION"
echo ""

# 1. Backup blue deployment
echo "[1/8] Backing up blue deployment..."
make -f make/ops/prometheus.mk prom-backup-all

# 2. Deploy green environment
echo "[2/8] Deploying green environment..."
helm install $GREEN_RELEASE scripton-charts/prometheus \
  -n $NAMESPACE \
  --set image.tag=$NEW_VERSION \
  --set nameOverride=prometheus-green \
  --set service.name=prometheus-green \
  --values values-green.yaml \
  --wait \
  --timeout 10m

# 3. Wait for green to be ready
echo "[3/8] Waiting for green environment to be ready..."
kubectl wait --for=condition=Ready pod/prometheus-green-0 \
  -n $NAMESPACE --timeout=600s

# 4. Validate green environment
echo "[4/8] Validating green environment..."
kubectl exec -n $NAMESPACE prometheus-green-0 -c prometheus -- \
  wget -qO- http://localhost:9090/-/ready

# 5. Run smoke tests on green
echo "[5/8] Running smoke tests on green..."
kubectl exec -n $NAMESPACE prometheus-green-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=up" | jq .

# 6. Switch traffic to green (update Service selector)
echo "[6/8] Switching traffic to green..."
kubectl patch service prometheus -n $NAMESPACE -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"'$GREEN_RELEASE'"}}}'

# 7. Monitor for 15 minutes
echo "[7/8] Monitoring green for 15 minutes..."
echo "  Check metrics, alerts, and dashboards"
echo "  Press Ctrl+C to abort and rollback"
sleep 900

# 8. Decommission blue
echo "[8/8] Decommissioning blue environment..."
helm uninstall $BLUE_RELEASE -n $NAMESPACE

echo ""
echo "=== Blue-Green Upgrade Completed ==="
echo "Old release decommissioned: $BLUE_RELEASE"
echo "New release active: $GREEN_RELEASE"
```

**Advantages:**
- Full testing before cutover
- Easy rollback (just switch back)
- No mixed versions

**Disadvantages:**
- Requires 2x resources temporarily
- Manual cutover required
- Potential data loss during cutover window

### Strategy 3: Maintenance Window

**Best for**: Major version upgrades with breaking changes, single replica

**Downtime**: 15-30 minutes

**Complexity**: Low

#### Steps:

```bash
#!/bin/bash
# maintenance-upgrade.sh

set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
NEW_VERSION="3.7.3"

echo "=== Prometheus Maintenance Window Upgrade ==="
echo "WARNING: This will cause downtime!"
echo "Target version: $NEW_VERSION"
echo ""

read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Upgrade cancelled"
  exit 0
fi

# 1. Create backup
echo "[1/6] Creating full backup..."
make -f make/ops/prometheus.mk prom-backup-all

# 2. Scale down to 0
echo "[2/6] Scaling down Prometheus..."
kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod/prometheus-0 -n $NAMESPACE --timeout=300s

# 3. Upgrade Helm release
echo "[3/6] Upgrading Helm release..."
helm upgrade $RELEASE_NAME scripton-charts/prometheus \
  -n $NAMESPACE \
  --set image.tag=$NEW_VERSION \
  --reuse-values \
  --wait \
  --timeout 10m

# 4. Scale up to 1
echo "[4/6] Scaling up Prometheus..."
kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=1
kubectl wait --for=condition=Ready pod/prometheus-0 -n $NAMESPACE --timeout=600s

# 5. Verify health
echo "[5/6] Verifying health..."
sleep 30
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/-/ready

# 6. Post-upgrade validation
echo "[6/6] Running post-upgrade validation..."
./post-upgrade-check.sh

echo ""
echo "=== Maintenance Window Upgrade Completed ==="
```

**Advantages:**
- Simplest approach
- Clean shutdown/startup
- No resource overhead

**Disadvantages:**
- Downtime required
- Metrics collection gap
- Not suitable for production HA

### Strategy 4: In-Place Helm Upgrade (Simple)

**Best for**: Configuration-only changes, minor chart updates

**Downtime**: None

**Complexity**: Very Low

```bash
#!/bin/bash
# helm-upgrade-simple.sh

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"

# Update values only (no version change)
helm upgrade $RELEASE_NAME scripton-charts/prometheus \
  -n $NAMESPACE \
  --values values-updated.yaml \
  --wait

# Reload configuration
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

---

## Version-Specific Notes

### Prometheus 2.x → 3.x

**Release Date**: December 2024
**Risk Level**: Medium-High

#### Breaking Changes

1. **Removed deprecated flags:**
   ```yaml
   # REMOVED in 3.x:
   extraArgs:
     - --storage.tsdb.allow-overlapping-blocks  # Removed
     - --query.lookback-delta=5m  # Renamed to --query.lookback-time

   # REPLACE WITH:
   extraArgs:
     - --query.lookback-time=5m
   ```

2. **Changed default values:**
   ```yaml
   # Prometheus 2.x defaults:
   --storage.tsdb.retention.time=15d
   --storage.tsdb.wal-compression=false

   # Prometheus 3.x defaults:
   --storage.tsdb.retention.time=15d  # Unchanged
   --storage.tsdb.wal-compression=true  # Now enabled by default
   ```

3. **PromQL changes:**
   - Stricter label matcher validation
   - Changed behavior for `rate()` with missing data points
   - New functions available: `sort_by_label()`, `sort_by_label_desc()`

4. **API changes:**
   - `/api/v1/admin/*` endpoints require explicit `--web.enable-admin-api` flag
   - New `/api/v1/metadata` endpoint for target metadata

#### Migration Checklist

```bash
# 1. Check for deprecated flags
grep -r "allow-overlapping-blocks\|lookback-delta" charts/prometheus/

# 2. Update configuration
sed -i 's/--query.lookback-delta/--query.lookback-time/g' values.yaml

# 3. Test PromQL queries
# Run critical queries against test instance before upgrade

# 4. Validate configuration
promtool check config prometheus.yml
```

### Prometheus 3.6.x → 3.7.x

**Release Date**: November 2024
**Risk Level**: Low

#### Changes

1. **Performance improvements:**
   - Faster query execution for high-cardinality metrics
   - Improved memory usage for rule evaluation

2. **New features:**
   - Enhanced native histograms support
   - Improved OTLP receiver

3. **Bug fixes:**
   - Fixed race condition in remote write
   - Fixed memory leak in service discovery

#### Migration Checklist

```bash
# Simple rolling upgrade, no config changes needed
helm upgrade prometheus scripton-charts/prometheus \
  --set image.tag=3.7.3 \
  --reuse-values
```

### Prometheus 3.5.x → 3.6.x

**Release Date**: October 2024
**Risk Level**: Low

#### Changes

1. **New features:**
   - UTF-8 support in label names and values
   - Improved Azure service discovery

2. **Deprecations:**
   - Deprecated `--storage.tsdb.retention` (use `--storage.tsdb.retention.time` instead)

#### Migration Checklist

```bash
# Check for deprecated flags
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  prometheus --help | grep deprecated

# Update if needed
helm upgrade prometheus scripton-charts/prometheus \
  --set image.tag=3.6.1 \
  --reuse-values
```

---

## Post-Upgrade Validation

### 1. Health Checks

```bash
#!/bin/bash
# post-upgrade-check.sh

set -e

NAMESPACE="monitoring"
POD_NAME="prometheus-0"

echo "=== Prometheus Post-Upgrade Validation ==="
echo ""

# 1. Check pod status
echo "[1/12] Checking pod status..."
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
  echo "  ERROR: Pod is not running (status: $POD_STATUS)"
  exit 1
fi
echo "  Pod status: $POD_STATUS ✓"

# 2. Check container ready
echo "[2/12] Checking container readiness..."
READY_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE \
  -o jsonpath='{.status.containerStatuses[0].ready}')
if [ "$READY_STATUS" != "true" ]; then
  echo "  ERROR: Container is not ready"
  exit 1
fi
echo "  Container ready: true ✓"

# 3. Verify new version
echo "[3/12] Verifying Prometheus version..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  prometheus --version 2>&1 | head -1 | awk '{print $3}')
echo "  New version: $NEW_VERSION ✓"

# 4. Check Prometheus ready endpoint
echo "[4/12] Checking ready endpoint..."
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/-/ready
echo "  Ready endpoint: OK ✓"

# 5. Check Prometheus healthy endpoint
echo "[5/12] Checking healthy endpoint..."
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/-/healthy
echo "  Healthy endpoint: OK ✓"

# 6. Verify configuration loaded
echo "[6/12] Verifying configuration..."
CONFIG_HASH_NEW=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/config 2>/dev/null | \
  jq -r '.data.yaml' | md5sum | cut -d' ' -f1)
echo "  Config hash: $CONFIG_HASH_NEW ✓"

# 7. Check TSDB status
echo "[7/12] Checking TSDB status..."
TSDB_STATUS=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb 2>/dev/null | jq -r '.status')
echo "  TSDB status: $TSDB_STATUS ✓"

# 8. Verify active targets
echo "[8/12] Checking active scrape targets..."
ACTIVE_TARGETS=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null | \
  jq '.data.activeTargets | length')
echo "  Active targets: $ACTIVE_TARGETS"

if [ "$ACTIVE_TARGETS" -eq 0 ]; then
  echo "  WARNING: No active targets found!"
fi

# 9. Test query execution
echo "[9/12] Testing query execution..."
QUERY_RESULT=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=up" 2>/dev/null | \
  jq -r '.status')
if [ "$QUERY_RESULT" != "success" ]; then
  echo "  ERROR: Query execution failed"
  exit 1
fi
echo "  Query execution: OK ✓"

# 10. Check rules loaded
echo "[10/12] Checking loaded rules..."
RULES_COUNT=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/rules 2>/dev/null | \
  jq '.data.groups | length')
echo "  Rules groups loaded: $RULES_COUNT"

# 11. Check alerts
echo "[11/12] Checking alerting rules..."
ALERTS_COUNT=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null | \
  jq '.data.alerts | length')
echo "  Total alerts: $ALERTS_COUNT"

# 12. Verify metrics retention
echo "[12/12] Checking metrics retention..."
OLDEST_SAMPLE=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=prometheus_tsdb_lowest_timestamp" 2>/dev/null | \
  jq -r '.data.result[0].value[1]')
if [ -n "$OLDEST_SAMPLE" ]; then
  OLDEST_DATE=$(date -d @$((${OLDEST_SAMPLE%.*}/1000)) '+%Y-%m-%d %H:%M:%S')
  echo "  Oldest sample: $OLDEST_DATE"
else
  echo "  WARNING: Could not determine oldest sample"
fi

echo ""
echo "=== Post-Upgrade Validation Completed ==="
echo ""
echo "Summary:"
echo "  Version: $NEW_VERSION"
echo "  Pod Status: Running"
echo "  Active Targets: $ACTIVE_TARGETS"
echo "  Rules Groups: $RULES_COUNT"
echo "  Total Alerts: $ALERTS_COUNT"
echo ""

# 13. Optional: Check for errors in logs
echo "Checking recent logs for errors..."
kubectl logs $POD_NAME -n $NAMESPACE -c prometheus --tail=100 | \
  grep -i "error\|warn\|fatal" || echo "  No errors found in recent logs ✓"
```

### 2. Functional Tests

```bash
# Test 1: Verify self-scraping
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"prometheus\"}" | \
  jq '.data.result[0].value[1]'
# Expected: "1"

# Test 2: Verify time series count
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=count(up)" | \
  jq '.data.result[0].value[1]'
# Expected: Non-zero number

# Test 3: Verify range queries
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query_range?query=up&start=$(date -d '1 hour ago' +%s)&end=$(date +%s)&step=60s" | \
  jq '.data.result | length'
# Expected: Non-zero number

# Test 4: Verify recording rules
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=job:up:sum" | \
  jq '.data.result | length'
# Expected: Number matching your recording rules

# Test 5: Verify alerting rules evaluation
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/rules | \
  jq '.data.groups[].rules[] | select(.type == "alerting") | .name'
# Expected: List of your alerting rule names
```

### 3. Performance Validation

```bash
# Check memory usage
kubectl top pod prometheus-0 -n monitoring

# Check storage usage
kubectl exec -n monitoring prometheus-0 -c prometheus -- df -h /prometheus

# Check scrape duration
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=scrape_duration_seconds" | \
  jq '.data.result[] | {job: .metric.job, duration: .value[1]}'

# Check query latency (p95)
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95, rate(prometheus_engine_query_duration_seconds_bucket[5m]))"
```

---

## Rollback Procedures

### Method 1: Helm Rollback (Recommended)

```bash
#!/bin/bash
# rollback-helm.sh

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"

# 1. List release history
echo "Available revisions:"
helm history $RELEASE_NAME -n $NAMESPACE

# 2. Identify previous revision
PREVIOUS_REVISION=$(helm history $RELEASE_NAME -n $NAMESPACE -o json | \
  jq -r '.[-2].revision')

echo "Rolling back to revision: $PREVIOUS_REVISION"

# 3. Perform rollback
helm rollback $RELEASE_NAME $PREVIOUS_REVISION -n $NAMESPACE --wait

# 4. Verify rollback
kubectl rollout status statefulset/$RELEASE_NAME -n $NAMESPACE

# 5. Check version
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  prometheus --version

echo "Rollback completed"
```

### Method 2: Restore from Backup

```bash
#!/bin/bash
# rollback-restore.sh

set -e

NAMESPACE="monitoring"
BACKUP_FILE="./backups/prometheus/full/20231127-120000.tar.gz"

echo "=== Prometheus Rollback via Restore ==="

# 1. Scale down current deployment
kubectl scale statefulset/prometheus -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod/prometheus-0 -n $NAMESPACE --timeout=120s

# 2. Restore data from backup
# (See prometheus-backup-guide.md for full restore procedure)
./restore-full-backup.sh $BACKUP_FILE

# 3. Helm rollback to previous chart version
PREVIOUS_REVISION=$(helm history prometheus -n $NAMESPACE -o json | \
  jq -r '.[-2].revision')
helm rollback prometheus $PREVIOUS_REVISION -n $NAMESPACE --wait

# 4. Scale up
kubectl scale statefulset/prometheus -n $NAMESPACE --replicas=1
kubectl wait --for=condition=Ready pod/prometheus-0 -n $NAMESPACE --timeout=600s

echo "Rollback completed"
```

### Method 3: Blue-Green Rollback

```bash
# Simply switch traffic back to blue deployment
kubectl patch service prometheus -n monitoring -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"prometheus-blue"}}}'

# Delete green deployment
helm uninstall prometheus-green -n monitoring
```

---

## Troubleshooting

### Issue 1: Pod Fails to Start After Upgrade

**Symptoms:**
- Pod stuck in `CrashLoopBackOff`
- Pod stuck in `Pending`

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod prometheus-0 -n monitoring

# Check logs
kubectl logs prometheus-0 -n monitoring -c prometheus --tail=100

# Check previous logs (if pod restarted)
kubectl logs prometheus-0 -n monitoring -c prometheus --previous
```

**Common Causes & Solutions:**

1. **Configuration Error:**
   ```bash
   # Validate configuration
   kubectl exec -n monitoring prometheus-0 -c prometheus -- \
     promtool check config /etc/prometheus/prometheus.yml

   # Fix: Rollback to previous config or fix configuration
   ```

2. **Incompatible Flags:**
   ```bash
   # Check for deprecated flags in logs
   kubectl logs prometheus-0 -n monitoring | grep "deprecated\|unknown flag"

   # Fix: Update values.yaml to remove deprecated flags
   ```

3. **Resource Limits:**
   ```bash
   # Check OOMKilled
   kubectl describe pod prometheus-0 -n monitoring | grep -A 5 "Last State"

   # Fix: Increase memory limits in values.yaml
   ```

### Issue 2: TSDB Corruption After Upgrade

**Symptoms:**
- Prometheus starts but shows errors in logs about TSDB
- Metrics queries return errors

**Diagnosis:**
```bash
# Check TSDB status
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb

# Check for corruption in logs
kubectl logs prometheus-0 -n monitoring | grep -i "corruption\|tsdb"
```

**Solution:**
```bash
# 1. Scale down
kubectl scale statefulset/prometheus -n monitoring --replicas=0

# 2. Backup current data
kubectl cp monitoring/prometheus-0:/prometheus /tmp/prometheus-corrupted

# 3. Restore from snapshot
./restore-tsdb.sh ./backups/prometheus/tsdb/latest.tar.gz

# 4. Scale up
kubectl scale statefulset/prometheus -n monitoring --replicas=1
```

### Issue 3: Missing Metrics After Upgrade

**Symptoms:**
- Prometheus running but no metrics showing up
- Gaps in time series data

**Diagnosis:**
```bash
# Check active targets
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/targets

# Check service discovery
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/service-discovery

# Check scrape status
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=up"
```

**Solution:**
```bash
# 1. Reload configuration
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload

# 2. Check RBAC permissions (for Kubernetes service discovery)
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:prometheus -n monitoring

# 3. Verify NetworkPolicy allows scraping
kubectl get networkpolicy -n monitoring
```

### Issue 4: High Memory Usage After Upgrade

**Symptoms:**
- Memory usage significantly higher than before
- Pod getting OOMKilled

**Diagnosis:**
```bash
# Check current memory usage
kubectl top pod prometheus-0 -n monitoring

# Check heap size
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=go_memstats_heap_inuse_bytes"

# Check cardinality
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb | \
  jq '.data.seriesCountByMetricName | to_entries | sort_by(.value) | reverse | .[0:10]'
```

**Solution:**
```bash
# Option 1: Increase memory limits
helm upgrade prometheus scripton-charts/prometheus \
  --set resources.limits.memory=4Gi \
  --reuse-values

# Option 2: Reduce retention
helm upgrade prometheus scripton-charts/prometheus \
  --set retention=7d \  # Previously 15d
  --reuse-values

# Option 3: Add target relabeling to reduce cardinality
# Update scrape configs to drop high-cardinality labels
```

### Issue 5: Slow Queries After Upgrade

**Symptoms:**
- Queries timing out
- Grafana dashboards loading slowly

**Diagnosis:**
```bash
# Check query execution time
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=prometheus_engine_query_duration_seconds{quantile=\"0.9\"}"

# Check slow queries in logs
kubectl logs prometheus-0 -n monitoring | grep "slow query"
```

**Solution:**
```bash
# Option 1: Increase query timeout
helm upgrade prometheus scripton-charts/prometheus \
  --set extraArgs[0]="--query.timeout=2m" \
  --reuse-values

# Option 2: Optimize queries
# Reduce time range or add more specific label matchers

# Option 3: Check for TSDB issues
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  promtool tsdb analyze /prometheus/data
```

### Issue 6: Configuration Reload Failed

**Symptoms:**
- Configuration changes not applied
- Reload endpoint returns error

**Diagnosis:**
```bash
# Check if lifecycle is enabled
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/flags | grep lifecycle

# Try manual reload
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

**Solution:**
```bash
# If lifecycle not enabled, restart pod
kubectl delete pod prometheus-0 -n monitoring

# Or enable lifecycle flag
helm upgrade prometheus scripton-charts/prometheus \
  --set extraArgs[0]="--web.enable-lifecycle" \
  --reuse-values
```

---

## Appendix

### A. Upgrade Checklist Template

```markdown
# Prometheus Upgrade Checklist

## Pre-Upgrade
- [ ] Review release notes for target version
- [ ] Check for breaking changes
- [ ] Run pre-upgrade check script
- [ ] Create full backup (TSDB + config + rules)
- [ ] Verify backup integrity
- [ ] Plan rollback procedure
- [ ] Schedule maintenance window (if needed)
- [ ] Notify team/stakeholders

## During Upgrade
- [ ] Execute chosen upgrade strategy
- [ ] Monitor pod status
- [ ] Watch for errors in logs
- [ ] Verify new version deployed

## Post-Upgrade
- [ ] Run post-upgrade validation script
- [ ] Check active targets
- [ ] Verify metrics collection
- [ ] Test critical queries
- [ ] Check alerting rules
- [ ] Verify Grafana dashboards
- [ ] Monitor for 24 hours

## Rollback (if needed)
- [ ] Execute rollback procedure
- [ ] Verify rollback successful
- [ ] Document issues encountered
- [ ] Plan remediation
```

### B. Version Compatibility Matrix

| Prometheus Version | Go Version | Kubernetes | Chart Version | Notes |
|--------------------|------------|------------|---------------|-------|
| 2.45.x | 1.20+ | 1.21+ | v0.2.0 | Legacy |
| 2.50.x | 1.21+ | 1.23+ | v0.2.0 | Legacy |
| 3.0.x | 1.21+ | 1.24+ | v0.3.0 | Major release |
| 3.5.x | 1.22+ | 1.25+ | v0.3.0 | Current |
| 3.6.x | 1.22+ | 1.25+ | v0.3.0 | Current |
| 3.7.x | 1.22+ | 1.26+ | v0.3.0 | Latest |

### C. Useful Commands

```bash
# Get current Helm release values
helm get values prometheus -n monitoring

# Compare two Prometheus configurations
diff <(kubectl exec -n monitoring prometheus-0 -c prometheus -- cat /etc/prometheus/prometheus.yml) \
     <(cat prometheus-backup.yml)

# Check Helm release history
helm history prometheus -n monitoring

# Dry-run upgrade
helm upgrade prometheus scripton-charts/prometheus \
  --dry-run --debug \
  --set image.tag=3.7.3 \
  --reuse-values

# Export current configuration
kubectl get configmap prometheus-server -n monitoring -o yaml > prometheus-config-backup.yaml

# Check StatefulSet update strategy
kubectl get statefulset prometheus -n monitoring -o jsonpath='{.spec.updateStrategy}'
```

---

**Document Version**: 1.0.0
**Last Updated**: 2025-11-27
**Prometheus Version**: 3.7.3
**Chart Version**: v0.3.0
