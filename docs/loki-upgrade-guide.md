# Loki Upgrade Guide

This guide provides comprehensive procedures for upgrading Loki deployed via the Helm chart.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [1. Rolling Upgrade (Recommended)](#1-rolling-upgrade-recommended)
  - [2. Blue-Green Deployment](#2-blue-green-deployment)
  - [3. Maintenance Window Upgrade](#3-maintenance-window-upgrade)
- [Version-Specific Notes](#version-specific-notes)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

### Supported Upgrade Paths

| Current Version | Target Version | Complexity | Downtime | Notes |
|----------------|---------------|-----------|----------|-------|
| 2.9.x | 3.0.x | High | Recommended | Breaking changes in config |
| 3.0.x | 3.6.x | Low | None | Rolling upgrade |
| 3.6.x | 3.7.x | Low | None | Minor version bump |

### Upgrade Complexity Factors

- **Schema changes**: Index schema migrations required
- **Storage backend**: S3 vs filesystem (S3 is simpler)
- **Replication factor**: Higher factor = easier rolling upgrade
- **Data volume**: Larger data = longer migration time

### RTO Targets

| Upgrade Strategy | Downtime | Complexity | Recommended For |
|-----------------|----------|-----------|----------------|
| Rolling Upgrade | None (with HA) | Low | Production |
| Blue-Green | 10-30 minutes | Medium | Large deployments |
| Maintenance Window | 15-30 minutes | Low | Dev/test |

---

## Pre-Upgrade Checklist

### Automated Pre-Upgrade Check

```bash
# Run automated pre-upgrade validation
make -f make/ops/loki.mk loki-pre-upgrade-check
```

### Manual Pre-Upgrade Checklist

#### 1. Review Release Notes

```bash
# Check Loki release notes
CURRENT_VERSION=$(kubectl exec -n monitoring loki-0 -c loki -- /usr/bin/loki --version | head -1 | awk '{print $3}')
TARGET_VERSION=3.7.0

echo "Current: $CURRENT_VERSION"
echo "Target: $TARGET_VERSION"
echo ""
echo "Release notes: https://github.com/grafana/loki/releases/tag/v$TARGET_VERSION"
```

#### 2. Check Current Health

```bash
# Verify Loki is healthy
make -f make/ops/loki.mk loki-ready
make -f make/ops/loki.mk loki-health

# Check ring status
make -f make/ops/loki.mk loki-ring-status

# Check active queries
kubectl exec -n monitoring loki-0 -c loki -- \
  wget -qO- http://localhost:3100/loki/api/v1/query_range?query={job=\"loki\"}\&limit=1
```

#### 3. Create Full Backup

```bash
# Create pre-upgrade backup
make -f make/ops/loki.mk loki-backup-all

# Verify backup
make -f make/ops/loki.mk loki-backup-verify BACKUP_FILE=/path/to/backup.tar.gz
```

#### 4. Check Storage Space

```bash
# Check PVC usage
kubectl exec -n monitoring loki-0 -c loki -- df -h /loki

# Check S3 bucket size (if using S3)
aws s3 ls --summarize --human-readable --recursive s3://loki-chunks/
```

#### 5. Review Configuration

```bash
# Export current config
kubectl get configmap -n monitoring loki -o yaml > loki-config-pre-upgrade.yaml

# Validate config
kubectl exec -n monitoring loki-0 -c loki -- \
  /usr/bin/loki -config.file=/etc/loki/loki.yaml -verify-config
```

#### 6. Document Current State

```bash
# Get current deployment state
kubectl get statefulset loki -n monitoring -o yaml > loki-statefulset-pre-upgrade.yaml
kubectl get pvc -n monitoring -l app.kubernetes.io/name=loki -o yaml > loki-pvc-pre-upgrade.yaml

# Get current version
kubectl exec -n monitoring loki-0 -c loki -- /usr/bin/loki --version > loki-version-pre-upgrade.txt
```

#### 7. Plan Rollback Procedure

```bash
# Document current Helm revision
helm history loki -n monitoring

# Save current Helm values
helm get values loki -n monitoring > loki-values-pre-upgrade.yaml
```

#### Pre-Upgrade Checklist Script

```bash
#!/bin/bash
# pre-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
POD_NAME="${POD_NAME:-loki-0}"
CONTAINER_NAME="${CONTAINER_NAME:-loki}"

echo "=== Loki Pre-Upgrade Checklist ==="
echo ""

# 1. Check current version
echo "[1/10] Checking current version..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /usr/bin/loki --version 2>&1 | head -1 | awk '{print $3}')
echo "  Current version: $CURRENT_VERSION"

# 2. Check pod health
echo "[2/10] Checking pod health..."
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
  echo "  ✗ Pod not running: $POD_STATUS"
  exit 1
fi
echo "  ✓ Pod is running"

# 3. Check Loki readiness
echo "[3/10] Checking Loki readiness..."
if kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/ready | grep -q "ready"; then
  echo "  ✓ Loki is ready"
else
  echo "  ✗ Loki is not ready"
  exit 1
fi

# 4. Check ring status
echo "[4/10] Checking ring status..."
RING_STATUS=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/ring 2>/dev/null | grep -o '"state":"[^"]*"' | head -1)
echo "  Ring status: $RING_STATUS"

# 5. Check storage space
echo "[5/10] Checking storage space..."
STORAGE_USAGE=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  df -h /loki | tail -1 | awk '{print $5}')
echo "  Storage usage: $STORAGE_USAGE"
if [ "${STORAGE_USAGE%?}" -gt 80 ]; then
  echo "  ⚠ Storage usage above 80%"
fi

# 6. Check active queries
echo "[6/10] Checking active queries..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/metrics 2>/dev/null | grep loki_query_frontend_workers_enqueued_requests_total || true

# 7. Verify configuration
echo "[7/10] Validating configuration..."
if kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /usr/bin/loki -config.file=/etc/loki/loki.yaml -verify-config 2>&1 | grep -q "failed"; then
  echo "  ✗ Config validation failed"
  exit 1
fi
echo "  ✓ Config is valid"

# 8. Check PVC status
echo "[8/10] Checking PVC status..."
PVC_STATUS=$(kubectl get pvc loki-loki-0 -n $NAMESPACE -o jsonpath='{.status.phase}')
echo "  PVC status: $PVC_STATUS"

# 9. Check recent errors
echo "[9/10] Checking recent errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME --tail=100 | grep -i error | wc -l)
echo "  Recent errors: $ERROR_COUNT"
if [ "$ERROR_COUNT" -gt 10 ]; then
  echo "  ⚠ High error count detected"
fi

# 10. Check Helm release
echo "[10/10] Checking Helm release..."
HELM_STATUS=$(helm status loki -n $NAMESPACE -o json | jq -r '.info.status')
echo "  Helm status: $HELM_STATUS"

echo ""
echo "=== Pre-Upgrade Check Complete ==="
echo ""
echo "Next steps:"
echo "1. Review release notes for target version"
echo "2. Create full backup: make -f make/ops/loki.mk loki-backup-all"
echo "3. Proceed with upgrade strategy"
```

---

## Upgrade Strategies

### 1. Rolling Upgrade (Recommended)

Zero-downtime upgrade for HA deployments (replicaCount ≥ 2).

#### Prerequisites

- Replication factor ≥ 2
- S3 storage (recommended)
- PodDisruptionBudget configured

#### Procedure

```bash
# 1. Create pre-upgrade backup
make -f make/ops/loki.mk loki-backup-all

# 2. Update Helm chart
helm repo update

# 3. Review changes
helm diff upgrade loki scripton-charts/loki \
  --set image.tag=3.7.0 \
  --reuse-values

# 4. Perform rolling upgrade
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.7.0 \
  --reuse-values \
  --wait \
  --timeout=10m

# 5. Monitor rollout
kubectl rollout status statefulset loki -n monitoring

# 6. Verify all pods updated
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

#### Rolling Upgrade with Detailed Monitoring

```bash
#!/bin/bash
# rolling-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
CHART_NAME="loki"
TARGET_VERSION="${TARGET_VERSION:-3.7.0}"

echo "=== Loki Rolling Upgrade to $TARGET_VERSION ==="

# 1. Pre-upgrade backup
echo "[1/6] Creating pre-upgrade backup..."
make -f make/ops/loki.mk loki-backup-all

# 2. Update Helm repo
echo "[2/6] Updating Helm repository..."
helm repo update scripton-charts

# 3. Perform upgrade
echo "[3/6] Upgrading Loki..."
helm upgrade $CHART_NAME scripton-charts/$CHART_NAME \
  --namespace $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout=10m

# 4. Monitor rollout
echo "[4/6] Monitoring rollout..."
kubectl rollout status statefulset $CHART_NAME -n $NAMESPACE

# 5. Verify pods
echo "[5/6] Verifying pods..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME

# 6. Verify Loki health
echo "[6/6] Verifying Loki health..."
POD_NAME="${CHART_NAME}-0"
kubectl wait --for=condition=ready pod/$POD_NAME -n $NAMESPACE --timeout=300s
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- \
  wget -qO- http://localhost:3100/ready

# Verify version
echo ""
echo "New version:"
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- /usr/bin/loki --version

echo ""
echo "=== Rolling Upgrade Complete ==="
```

---

### 2. Blue-Green Deployment

Parallel deployment with traffic cutover.

#### Prerequisites

- 2x compute resources
- Separate namespace for green deployment
- Shared S3 storage (or data migration plan)

#### Procedure

```bash
# 1. Create full backup
make -f make/ops/loki.mk loki-backup-all

# 2. Deploy green environment
kubectl create namespace monitoring-green

helm install loki-green scripton-charts/loki \
  --namespace monitoring-green \
  --set image.tag=3.7.0 \
  --values loki-values.yaml

# 3. Wait for green to be ready
kubectl wait --for=condition=ready pod -n monitoring-green -l app.kubernetes.io/name=loki --timeout=300s

# 4. Verify green environment
kubectl exec -n monitoring-green loki-0 -c loki -- \
  wget -qO- http://localhost:3100/ready

# 5. Test queries on green
kubectl exec -n monitoring-green loki-0 -c loki -- \
  wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={job=\"loki\"}&limit=10"

# 6. Update service to point to green
kubectl patch service loki -n monitoring -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"loki-green"}}}'

# 7. Monitor for 15 minutes
# Check logs, metrics, queries

# 8. Decommission blue
helm uninstall loki -n monitoring
kubectl delete namespace monitoring
```

#### Blue-Green Deployment Script

```bash
#!/bin/bash
# blue-green-upgrade.sh

set -e

BLUE_NAMESPACE="${BLUE_NAMESPACE:-monitoring}"
GREEN_NAMESPACE="${GREEN_NAMESPACE:-monitoring-green}"
TARGET_VERSION="${TARGET_VERSION:-3.7.0}"

echo "=== Loki Blue-Green Upgrade ==="

# 1. Backup blue
echo "[1/8] Backing up blue environment..."
make -f make/ops/loki.mk loki-backup-all NAMESPACE=$BLUE_NAMESPACE

# 2. Create green namespace
echo "[2/8] Creating green namespace..."
kubectl create namespace $GREEN_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 3. Deploy green
echo "[3/8] Deploying green environment..."
helm get values loki -n $BLUE_NAMESPACE > /tmp/loki-values.yaml

helm install loki-green scripton-charts/loki \
  --namespace $GREEN_NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --values /tmp/loki-values.yaml \
  --wait \
  --timeout=10m

# 4. Verify green
echo "[4/8] Verifying green environment..."
kubectl wait --for=condition=ready pod -n $GREEN_NAMESPACE -l app.kubernetes.io/name=loki --timeout=300s

kubectl exec -n $GREEN_NAMESPACE loki-0 -c loki -- \
  wget -qO- http://localhost:3100/ready

# 5. Test green
echo "[5/8] Testing green environment..."
kubectl exec -n $GREEN_NAMESPACE loki-0 -c loki -- \
  wget -qO- "http://localhost:3100/loki/api/v1/labels"

# 6. Switch traffic
echo "[6/8] Switching traffic to green..."
kubectl label namespace $GREEN_NAMESPACE name=$BLUE_NAMESPACE --overwrite
kubectl patch service loki -n $BLUE_NAMESPACE -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"loki-green"}}}'

# 7. Monitor (manual step)
echo "[7/8] Monitoring green environment..."
echo "  Monitor logs, metrics, and queries for 15 minutes"
echo "  Press ENTER to continue with decommissioning blue..."
read

# 8. Decommission blue
echo "[8/8] Decommissioning blue environment..."
helm uninstall loki -n $BLUE_NAMESPACE

echo ""
echo "=== Blue-Green Upgrade Complete ==="
echo "Green environment is now serving traffic"
```

---

### 3. Maintenance Window Upgrade

Controlled upgrade with planned downtime.

#### Prerequisites

- Maintenance window scheduled
- Backup created
- Users notified

#### Procedure

```bash
# 1. Create full backup
make -f make/ops/loki.mk loki-backup-all

# 2. Scale down to 0
kubectl scale statefulset loki -n monitoring --replicas=0
kubectl wait --for=delete pod -n monitoring -l app.kubernetes.io/name=loki --timeout=120s

# 3. Update Helm chart
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.7.0 \
  --reuse-values \
  --wait

# 4. Scale up to 1
kubectl scale statefulset loki -n monitoring --replicas=1
kubectl wait --for=condition=ready pod -n monitoring loki-0 --timeout=300s

# 5. Verify health
make -f make/ops/loki.mk loki-ready

# 6. Scale to original replica count
kubectl scale statefulset loki -n monitoring --replicas=3
```

#### Maintenance Window Script

```bash
#!/bin/bash
# maintenance-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
TARGET_VERSION="${TARGET_VERSION:-3.7.0}"
ORIGINAL_REPLICAS=$(kubectl get statefulset loki -n $NAMESPACE -o jsonpath='{.spec.replicas}')

echo "=== Loki Maintenance Window Upgrade ==="
echo "Target version: $TARGET_VERSION"
echo "Current replicas: $ORIGINAL_REPLICAS"

# 1. Create backup
echo "[1/6] Creating pre-upgrade backup..."
make -f make/ops/loki.mk loki-backup-all

# 2. Scale down
echo "[2/6] Scaling down to 0..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=loki --timeout=120s

# 3. Upgrade Helm release
echo "[3/6] Upgrading Helm release..."
helm upgrade loki scripton-charts/loki \
  --namespace $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout=10m

# 4. Scale up to 1 for verification
echo "[4/6] Scaling up to 1 replica..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE loki-0 --timeout=300s

# 5. Verify health
echo "[5/6] Verifying Loki health..."
kubectl exec -n $NAMESPACE loki-0 -c loki -- \
  wget -qO- http://localhost:3100/ready

NEW_VERSION=$(kubectl exec -n $NAMESPACE loki-0 -c loki -- /usr/bin/loki --version | head -1)
echo "New version: $NEW_VERSION"

# 6. Scale to original replica count
echo "[6/6] Scaling to original replica count ($ORIGINAL_REPLICAS)..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=$ORIGINAL_REPLICAS
kubectl rollout status statefulset loki -n $NAMESPACE

echo ""
echo "=== Maintenance Upgrade Complete ==="
```

---

## Version-Specific Notes

### Loki 2.x to 3.0

**Breaking Changes:**
- Index schema changes (v11 → v12)
- Configuration structure changes
- Deprecated flags removed
- Query frontend changes

**Migration Steps:**

1. **Update schema config:**
   ```yaml
   # Old (v2.x)
   schema_config:
     configs:
       - from: 2020-10-24
         store: boltdb-shipper
         object_store: filesystem
         schema: v11
         index:
           prefix: index_
           period: 24h

   # New (v3.0)
   schema_config:
     configs:
       - from: 2020-10-24
         store: tsdb
         object_store: filesystem
         schema: v12
         index:
           prefix: index_
           period: 24h
   ```

2. **Update storage config:**
   ```yaml
   # Old (v2.x)
   storage_config:
     boltdb_shipper:
       active_index_directory: /loki/index
       cache_location: /loki/boltdb-cache
       shared_store: filesystem

   # New (v3.0)
   storage_config:
     tsdb_shipper:
       active_index_directory: /loki/index
       cache_location: /loki/tsdb-cache
       shared_store: filesystem
   ```

3. **Update query frontend:**
   ```yaml
   # Old (v2.x)
   query_range:
     align_queries_with_step: true

   # New (v3.0)
   limits_config:
     query_timeout: 5m
     split_queries_by_interval: 15m
   ```

4. **Verify deprecated flags:**
   ```bash
   # Check for deprecated flags
   kubectl exec -n monitoring loki-0 -c loki -- \
     /usr/bin/loki -config.file=/etc/loki/loki.yaml -verify-config
   ```

### Loki 3.0 to 3.6

**Changes:**
- Improved query performance
- New LogQL functions
- Enhanced TSDB support
- Better S3 integration

**Migration Steps:**

1. **No config changes required** - rolling upgrade supported

2. **Optional performance tuning:**
   ```yaml
   query_scheduler:
     max_outstanding_requests_per_tenant: 2048

   querier:
     max_concurrent: 20
   ```

3. **Enable new features:**
   ```yaml
   limits_config:
     allow_structured_metadata: true  # New in 3.6
     max_label_names_per_series: 30
   ```

### Loki 3.6 to 3.7

**Changes:**
- Enhanced native histograms
- Improved pattern matching
- Better resource utilization
- Bug fixes and stability improvements

**Migration Steps:**

1. **No breaking changes** - straightforward rolling upgrade

2. **Optional new features:**
   ```yaml
   limits_config:
     volume_enabled: true  # New in 3.7 (log volume endpoint)
   ```

---

## Post-Upgrade Validation

### Automated Post-Upgrade Check

```bash
# Run automated validation
make -f make/ops/loki.mk loki-post-upgrade-check
```

### Manual Post-Upgrade Validation

```bash
#!/bin/bash
# post-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
POD_NAME="${POD_NAME:-loki-0}"
CONTAINER_NAME="${CONTAINER_NAME:-loki}"

echo "=== Loki Post-Upgrade Validation ==="
echo ""

# 1. Check version
echo "[1/8] Verifying new version..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /usr/bin/loki --version 2>&1 | head -1 | awk '{print $3}')
echo "  New version: $NEW_VERSION"

# 2. Check pod status
echo "[2/8] Checking pod status..."
READY_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=loki --no-headers | wc -l)
echo "  Ready pods: $READY_PODS/$TOTAL_PODS"

# 3. Check Loki readiness
echo "[3/8] Checking Loki readiness..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/ready
echo "  ✓ Loki is ready"

# 4. Check ring status
echo "[4/8] Checking ring status..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/ring | grep -o '"state":"[^"]*"' | head -1
echo "  ✓ Ring is healthy"

# 5. Test label query
echo "[5/8] Testing label query..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- "http://localhost:3100/loki/api/v1/labels" | head -20
echo "  ✓ Label query successful"

# 6. Test log query
echo "[6/8] Testing log query..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={job=\"loki\"}&limit=10&start=$(date -u -d '5 minutes ago' +%s)000000000&end=$(date -u +%s)000000000" | jq '.status'
echo "  ✓ Log query successful"

# 7. Check metrics
echo "[7/8] Checking metrics..."
METRICS=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/metrics | grep -E "(loki_build_info|loki_ingester_chunks_stored_total)" | head -2)
echo "$METRICS"

# 8. Check for errors
echo "[8/8] Checking for errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME --tail=100 | grep -i error | wc -l)
echo "  Recent errors: $ERROR_COUNT"

echo ""
echo "=== Post-Upgrade Validation Complete ==="
```

---

## Rollback Procedures

### Method 1: Helm Rollback

```bash
# List Helm history
helm history loki -n monitoring

# Rollback to previous revision
helm rollback loki -n monitoring

# Or rollback to specific revision
helm rollback loki 5 -n monitoring
```

### Method 2: Restore from Backup

```bash
# Scale down current deployment
kubectl scale statefulset loki -n monitoring --replicas=0

# Restore from backup
make -f make/ops/loki.mk loki-restore-all BACKUP_FILE=/path/to/backup.tar.gz

# Scale up
kubectl scale statefulset loki -n monitoring --replicas=3
```

### Method 3: Revert Image Tag

```bash
# Revert to previous image tag
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.6.1 \
  --reuse-values

# Verify rollback
kubectl rollout status statefulset loki -n monitoring
```

### Rollback Script

```bash
#!/bin/bash
# rollback.sh

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
PREVIOUS_VERSION="${PREVIOUS_VERSION:-3.6.1}"

echo "=== Loki Rollback to $PREVIOUS_VERSION ==="

# 1. Check current state
echo "[1/4] Checking current state..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE loki-0 -c loki -- \
  /usr/bin/loki --version 2>&1 | head -1 | awk '{print $3}')
echo "  Current version: $CURRENT_VERSION"

# 2. Confirm rollback
echo ""
echo "⚠️  This will rollback Loki from $CURRENT_VERSION to $PREVIOUS_VERSION"
echo "Press ENTER to continue or Ctrl+C to cancel..."
read

# 3. Perform rollback
echo "[2/4] Performing Helm rollback..."
helm rollback loki -n $NAMESPACE

# 4. Wait for rollback
echo "[3/4] Waiting for rollback to complete..."
kubectl rollout status statefulset loki -n $NAMESPACE

# 5. Verify rollback
echo "[4/4] Verifying rollback..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE loki-0 -c loki -- \
  /usr/bin/loki --version 2>&1 | head -1 | awk '{print $3}')
echo "  Rolled back to: $NEW_VERSION"

kubectl exec -n $NAMESPACE loki-0 -c loki -- \
  wget -qO- http://localhost:3100/ready

echo ""
echo "=== Rollback Complete ==="
```

---

## Troubleshooting

### Issue 1: Pods Stuck in CrashLoopBackOff

**Symptoms:**
- Pods crash after upgrade
- Loki won't start
- Config validation errors

**Solutions:**

1. **Check logs:**
   ```bash
   kubectl logs -n monitoring loki-0 -c loki --tail=100
   ```

2. **Validate configuration:**
   ```bash
   kubectl exec -n monitoring loki-0 -c loki -- \
     /usr/bin/loki -config.file=/etc/loki/loki.yaml -verify-config
   ```

3. **Rollback to previous version:**
   ```bash
   helm rollback loki -n monitoring
   ```

### Issue 2: Index Schema Mismatch

**Symptoms:**
- Queries fail after upgrade
- "schema version mismatch" errors
- Index corruption

**Solutions:**

1. **Check schema config:**
   ```bash
   kubectl get configmap loki -n monitoring -o yaml | grep -A 10 schema_config
   ```

2. **Update schema version:**
   ```yaml
   schema_config:
     configs:
       - from: 2020-10-24
         store: tsdb
         schema: v12  # Update from v11
   ```

3. **Rebuild index:**
   ```bash
   # Delete corrupted index
   kubectl exec -n monitoring loki-0 -c loki -- rm -rf /loki/index/*

   # Restart Loki (will rebuild)
   kubectl rollout restart statefulset loki -n monitoring
   ```

### Issue 3: Data Loss After Upgrade

**Symptoms:**
- Missing log data
- Queries return no results
- Chunks not found

**Solutions:**

1. **Check storage backend:**
   ```bash
   # Filesystem mode
   kubectl exec -n monitoring loki-0 -c loki -- ls -lh /loki/chunks/

   # S3 mode
   aws s3 ls s3://loki-chunks/
   ```

2. **Restore from backup:**
   ```bash
   make -f make/ops/loki.mk loki-restore-data BACKUP_FILE=/path/to/backup.tar.gz
   ```

3. **Verify S3 credentials:**
   ```bash
   kubectl get secret loki-s3-credentials -n monitoring -o yaml
   ```

### Issue 4: High Memory Usage

**Symptoms:**
- OOMKilled pods
- Memory usage spikes
- Query timeouts

**Solutions:**

1. **Increase memory limits:**
   ```yaml
   resources:
     limits:
       memory: 4Gi  # Increased from 2Gi
     requests:
       memory: 2Gi  # Increased from 1Gi
   ```

2. **Adjust query limits:**
   ```yaml
   limits_config:
     max_query_parallelism: 32
     max_query_series: 500
     max_concurrent_tail_requests: 10
   ```

3. **Enable query result caching:**
   ```yaml
   query_range:
     results_cache:
       cache:
         enable_fifocache: true
         fifocache:
           max_size_bytes: 1GB
   ```

### Issue 5: Ring Membership Issues

**Symptoms:**
- Pods not joining ring
- Memberlist errors
- Replication failures

**Solutions:**

1. **Check ring status:**
   ```bash
   make -f make/ops/loki.mk loki-ring-status
   ```

2. **Check memberlist:**
   ```bash
   make -f make/ops/loki.mk loki-memberlist-status
   ```

3. **Restart affected pods:**
   ```bash
   kubectl delete pod loki-1 -n monitoring
   kubectl wait --for=condition=ready pod loki-1 -n monitoring --timeout=300s
   ```

4. **Verify network connectivity:**
   ```bash
   kubectl exec -n monitoring loki-0 -c loki -- nc -zv loki-1.loki.monitoring.svc.cluster.local 7946
   ```

### Issue 6: S3 Connection Failures

**Symptoms:**
- "NoSuchBucket" errors
- S3 timeout errors
- Chunks not uploaded

**Solutions:**

1. **Verify S3 credentials:**
   ```bash
   kubectl get secret loki-s3-credentials -n monitoring -o jsonpath='{.data.accessKeyId}' | base64 -d
   ```

2. **Test S3 connectivity:**
   ```bash
   kubectl exec -n monitoring loki-0 -c loki -- \
     aws s3 ls s3://loki-chunks/ --endpoint-url=https://s3.amazonaws.com
   ```

3. **Update S3 configuration:**
   ```yaml
   loki:
     storage:
       type: s3
       s3:
         endpoint: s3.amazonaws.com
         bucketNames: loki-chunks
         region: us-east-1
         s3ForcePathStyle: false
   ```

---

## Best Practices

### Before Upgrade

1. **Always create backup** before upgrading
2. **Test upgrade in non-production** environment first
3. **Review release notes** for breaking changes
4. **Plan rollback procedure** before starting
5. **Schedule maintenance window** if needed

### During Upgrade

1. **Monitor logs** during upgrade process
2. **Check pod health** after each pod updates
3. **Verify queries** work after upgrade
4. **Monitor metrics** for anomalies
5. **Be ready to rollback** if issues occur

### After Upgrade

1. **Run post-upgrade validation** script
2. **Monitor for 24 hours** after upgrade
3. **Test critical queries** and dashboards
4. **Update documentation** with new version
5. **Clean up old backups** after successful upgrade

### General Recommendations

1. **Use S3 storage** for easier upgrades
2. **Set replication factor ≥ 2** for zero-downtime upgrades
3. **Keep Loki up to date** (within 2 minor versions)
4. **Automate upgrade testing** in CI/CD
5. **Document custom configurations** for future reference

---

## Related Documentation

- [Loki Backup Guide](loki-backup-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/loki/README.md)
- [Loki Makefile](../make/ops/loki.mk)

---

**Last Updated:** 2025-11-27
**Chart Version:** 0.3.0
**Loki Version:** 3.6.1
