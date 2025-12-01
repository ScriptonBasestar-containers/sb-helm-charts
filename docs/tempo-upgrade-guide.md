# Tempo Upgrade Guide

This guide provides comprehensive procedures for upgrading Tempo deployed via the Helm chart.

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
| 2.7.x | 2.8.x | Low | None | WAL format changes |
| 2.8.x | 2.9.x | Low | None | Query frontend improvements |
| 2.7.x | 2.9.x | Medium | Recommended | Jump upgrade - review all notes |

### Upgrade Complexity Factors

- **Storage format**: v2 block format changes between major versions
- **WAL changes**: Write-ahead log format updates require compaction
- **Storage backend**: S3/MinIO vs local filesystem (S3 is simpler for HA)
- **Replication factor**: Higher factor = easier rolling upgrade
- **Trace volume**: Larger data = longer compaction time

### Key Components Affected During Upgrade

| Component | Impact | Recovery Time |
|-----------|--------|---------------|
| Distributor | Trace ingestion paused | Seconds |
| Ingester | WAL replay required | Minutes |
| Compactor | Block compaction delayed | Hours |
| Query Frontend | Queries unavailable | Seconds |
| Metrics Generator | Metrics delayed | Minutes |

### RTO Targets

| Upgrade Strategy | Downtime | Complexity | Recommended For |
|-----------------|----------|-----------|----------------|
| Rolling Upgrade | None (with HA) | Low | Production |
| Blue-Green | 10-30 minutes | Medium | Large deployments |
| Maintenance Window | 15-45 minutes | Low | Dev/test |

---

## Pre-Upgrade Checklist

### Automated Pre-Upgrade Check

```bash
# Run automated pre-upgrade validation
make -f make/ops/tempo.mk tempo-pre-upgrade-check
```

### Manual Pre-Upgrade Checklist

#### 1. Review Release Notes

```bash
# Check Tempo release notes
CURRENT_VERSION=$(kubectl exec -n tracing tempo-0 -c tempo -- /tempo --version | head -1 | awk '{print $2}')
TARGET_VERSION=2.9.0

echo "Current: $CURRENT_VERSION"
echo "Target: $TARGET_VERSION"
echo ""
echo "Release notes: https://github.com/grafana/tempo/releases/tag/v$TARGET_VERSION"
echo "Changelog: https://github.com/grafana/tempo/blob/main/CHANGELOG.md"
```

#### 2. Check Current Health

```bash
# Verify Tempo is healthy
make -f make/ops/tempo.mk tempo-ready
make -f make/ops/tempo.mk tempo-health

# Check ring status (distributor ring)
make -f make/ops/tempo.mk tempo-ring-status

# Check memberlist status
make -f make/ops/tempo.mk tempo-memberlist-status

# Test trace query
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- "http://localhost:3200/api/search?limit=1"
```

#### 3. Create Full Backup

```bash
# Create pre-upgrade backup
make -f make/ops/tempo.mk tempo-backup-all

# Backup configuration
kubectl get configmap -n tracing tempo-config -o yaml > tempo-config-pre-upgrade.yaml

# Verify backup
ls -lh /backup/tempo-pre-upgrade-*.tar.gz
```

#### 4. Check Storage Space

```bash
# Check PVC usage (local storage)
kubectl exec -n tracing tempo-0 -c tempo -- df -h /var/tempo

# Check S3 bucket size (if using S3)
aws s3 ls --summarize --human-readable --recursive s3://tempo-traces/

# Check WAL directory size
kubectl exec -n tracing tempo-0 -c tempo -- du -sh /var/tempo/wal
```

#### 5. Check Active Traces and Flush WAL

```bash
# Check ingester status
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ingester/ring

# Flush all in-memory traces to storage
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush

# Wait for flush to complete (check WAL is empty)
sleep 30
kubectl exec -n tracing tempo-0 -c tempo -- \
  ls -la /var/tempo/wal/
```

#### 6. Review Configuration

```bash
# Export current config
kubectl get configmap -n tracing tempo-config -o yaml > tempo-config-pre-upgrade.yaml

# Validate config syntax
kubectl exec -n tracing tempo-0 -c tempo -- \
  /tempo -config.file=/etc/tempo/tempo.yaml -config.verify

# Check for deprecated configuration options
kubectl exec -n tracing tempo-0 -c tempo -- \
  /tempo -config.file=/etc/tempo/tempo.yaml -check-config 2>&1 | grep -i deprecated
```

#### 7. Document Current State

```bash
# Get current deployment state
kubectl get statefulset tempo -n tracing -o yaml > tempo-statefulset-pre-upgrade.yaml
kubectl get pvc -n tracing -l app.kubernetes.io/name=tempo -o yaml > tempo-pvc-pre-upgrade.yaml

# Get current version
kubectl exec -n tracing tempo-0 -c tempo -- /tempo --version > tempo-version-pre-upgrade.txt

# Get current metrics snapshot
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/metrics > tempo-metrics-pre-upgrade.txt
```

#### 8. Check Compactor Status

```bash
# Check compactor status
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/compactor/ring

# Verify no active compaction jobs
kubectl logs -n tracing tempo-0 -c tempo --tail=50 | grep -i compact
```

#### 9. Verify OTLP Receiver Health

```bash
# Check OTLP gRPC receiver
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ready

# Check receiver metrics
kubectl exec -n tracing tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/metrics | grep tempo_distributor_spans_received
```

#### 10. Plan Rollback Procedure

```bash
# Document current Helm revision
helm history tempo -n tracing

# Save current Helm values
helm get values tempo -n tracing > tempo-values-pre-upgrade.yaml

# Note current image tag
kubectl get statefulset tempo -n tracing -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Pre-Upgrade Checklist Script

```bash
#!/bin/bash
# pre-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-tracing}"
POD_NAME="${POD_NAME:-tempo-0}"
CONTAINER_NAME="${CONTAINER_NAME:-tempo}"

echo "=== Tempo Pre-Upgrade Checklist ==="
echo ""

# 1. Check current version
echo "[1/12] Checking current version..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /tempo --version 2>&1 | head -1 | awk '{print $2}')
echo "  Current version: $CURRENT_VERSION"

# 2. Check pod health
echo "[2/12] Checking pod health..."
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
  echo "  [X] Pod not running: $POD_STATUS"
  exit 1
fi
echo "  [OK] Pod is running"

# 3. Check Tempo readiness
echo "[3/12] Checking Tempo readiness..."
if kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/ready | grep -q "ready"; then
  echo "  [OK] Tempo is ready"
else
  echo "  [X] Tempo is not ready"
  exit 1
fi

# 4. Check distributor ring status
echo "[4/12] Checking distributor ring status..."
RING_MEMBERS=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/distributor/ring 2>/dev/null | grep -o '"state":"ACTIVE"' | wc -l)
echo "  Active ring members: $RING_MEMBERS"

# 5. Check storage space
echo "[5/12] Checking storage space..."
STORAGE_USAGE=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  df -h /var/tempo | tail -1 | awk '{print $5}')
echo "  Storage usage: $STORAGE_USAGE"
if [ "${STORAGE_USAGE%?}" -gt 80 ]; then
  echo "  [WARN] Storage usage above 80%"
fi

# 6. Check WAL size
echo "[6/12] Checking WAL size..."
WAL_SIZE=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  du -sh /var/tempo/wal 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "  WAL size: $WAL_SIZE"

# 7. Check active trace ingestion
echo "[7/12] Checking trace ingestion..."
SPANS_RECEIVED=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/metrics 2>/dev/null | \
  grep tempo_distributor_spans_received_total | head -1 || echo "N/A")
echo "  Spans received: $SPANS_RECEIVED"

# 8. Verify configuration
echo "[8/12] Validating configuration..."
if kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /tempo -config.file=/etc/tempo/tempo.yaml -config.verify 2>&1 | grep -q "valid"; then
  echo "  [OK] Config is valid"
else
  echo "  [WARN] Config validation returned warnings"
fi

# 9. Check PVC status
echo "[9/12] Checking PVC status..."
PVC_STATUS=$(kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=tempo -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "N/A")
echo "  PVC status: $PVC_STATUS"

# 10. Check recent errors
echo "[10/12] Checking recent errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME --tail=100 | grep -i error | wc -l)
echo "  Recent errors: $ERROR_COUNT"
if [ "$ERROR_COUNT" -gt 10 ]; then
  echo "  [WARN] High error count detected"
fi

# 11. Check compactor status
echo "[11/12] Checking compactor status..."
COMPACTOR_STATUS=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/compactor/ring 2>/dev/null | grep -o '"state":"[^"]*"' | head -1 || echo "N/A")
echo "  Compactor status: $COMPACTOR_STATUS"

# 12. Check Helm release
echo "[12/12] Checking Helm release..."
HELM_STATUS=$(helm status tempo -n $NAMESPACE -o json 2>/dev/null | jq -r '.info.status' || echo "N/A")
echo "  Helm status: $HELM_STATUS"

echo ""
echo "=== Pre-Upgrade Check Complete ==="
echo ""
echo "Next steps:"
echo "1. Review release notes for target version"
echo "2. Flush WAL: kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- wget -qO- -X POST http://localhost:3200/flush"
echo "3. Create full backup: make -f make/ops/tempo.mk tempo-backup-all"
echo "4. Proceed with upgrade strategy"
```

---

## Upgrade Strategies

### 1. Rolling Upgrade (Recommended)

Zero-downtime upgrade for HA deployments (replicaCount >= 2).

#### Prerequisites

- Replication factor >= 2
- S3/MinIO storage (required for multi-replica)
- PodDisruptionBudget configured
- WAL flushed before upgrade

#### Procedure

```bash
# 1. Flush WAL before upgrade
kubectl exec -n tracing tempo-0 -c tempo -- wget -qO- -X POST http://localhost:3200/flush
sleep 30

# 2. Create pre-upgrade backup
make -f make/ops/tempo.mk tempo-backup-all

# 3. Update Helm chart
helm repo update

# 4. Review changes
helm diff upgrade tempo scripton-charts/tempo \
  --set image.tag=2.9.0 \
  --reuse-values

# 5. Perform rolling upgrade
helm upgrade tempo scripton-charts/tempo \
  --set image.tag=2.9.0 \
  --reuse-values \
  --wait \
  --timeout=15m

# 6. Monitor rollout
kubectl rollout status statefulset tempo -n tracing

# 7. Verify all pods updated
kubectl get pods -n tracing -l app.kubernetes.io/name=tempo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

#### Rolling Upgrade with Detailed Monitoring

```bash
#!/bin/bash
# rolling-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-tracing}"
CHART_NAME="tempo"
TARGET_VERSION="${TARGET_VERSION:-2.9.0}"

echo "=== Tempo Rolling Upgrade to $TARGET_VERSION ==="

# 1. Flush WAL
echo "[1/7] Flushing WAL..."
kubectl exec -n $NAMESPACE ${CHART_NAME}-0 -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush
sleep 30

# 2. Pre-upgrade backup
echo "[2/7] Creating pre-upgrade backup..."
make -f make/ops/tempo.mk tempo-backup-all

# 3. Update Helm repo
echo "[3/7] Updating Helm repository..."
helm repo update scripton-charts

# 4. Perform upgrade
echo "[4/7] Upgrading Tempo..."
helm upgrade $CHART_NAME scripton-charts/$CHART_NAME \
  --namespace $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout=15m

# 5. Monitor rollout
echo "[5/7] Monitoring rollout..."
kubectl rollout status statefulset $CHART_NAME -n $NAMESPACE

# 6. Verify pods
echo "[6/7] Verifying pods..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME

# 7. Verify Tempo health
echo "[7/7] Verifying Tempo health..."
POD_NAME="${CHART_NAME}-0"
kubectl wait --for=condition=ready pod/$POD_NAME -n $NAMESPACE --timeout=300s
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  wget -qO- http://localhost:3200/ready

# Verify version
echo ""
echo "New version:"
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- /tempo --version

# Verify trace query works
echo ""
echo "Testing trace query..."
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  wget -qO- "http://localhost:3200/api/search?limit=1"

echo ""
echo "=== Rolling Upgrade Complete ==="
```

---

### 2. Blue-Green Deployment

Parallel deployment with traffic cutover.

#### Prerequisites

- 2x compute resources
- Separate namespace for green deployment
- Shared S3 storage (required for data access)
- Load balancer or service mesh for traffic switching

#### Procedure

```bash
# 1. Create full backup
make -f make/ops/tempo.mk tempo-backup-all

# 2. Deploy green environment
kubectl create namespace tracing-green

# Copy S3 credentials to green namespace
kubectl get secret tempo-secret -n tracing -o yaml | \
  sed 's/namespace: tracing/namespace: tracing-green/' | \
  kubectl apply -f -

helm install tempo-green scripton-charts/tempo \
  --namespace tracing-green \
  --set image.tag=2.9.0 \
  --values tempo-values.yaml

# 3. Wait for green to be ready
kubectl wait --for=condition=ready pod -n tracing-green \
  -l app.kubernetes.io/name=tempo --timeout=300s

# 4. Verify green environment
kubectl exec -n tracing-green tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ready

# 5. Test trace query on green (should access shared S3 storage)
kubectl exec -n tracing-green tempo-0 -c tempo -- \
  wget -qO- "http://localhost:3200/api/search?limit=10"

# 6. Update ingress/service to point to green
kubectl patch service tempo-receiver -n tracing -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"tempo-green"}}}'

# 7. Monitor for 15-30 minutes
# Check logs, metrics, trace ingestion

# 8. Decommission blue
helm uninstall tempo -n tracing
kubectl delete namespace tracing
```

#### Blue-Green Deployment Script

```bash
#!/bin/bash
# blue-green-upgrade.sh

set -e

BLUE_NAMESPACE="${BLUE_NAMESPACE:-tracing}"
GREEN_NAMESPACE="${GREEN_NAMESPACE:-tracing-green}"
TARGET_VERSION="${TARGET_VERSION:-2.9.0}"

echo "=== Tempo Blue-Green Upgrade ==="

# 1. Backup blue
echo "[1/8] Backing up blue environment..."
make -f make/ops/tempo.mk tempo-backup-all NAMESPACE=$BLUE_NAMESPACE

# 2. Create green namespace
echo "[2/8] Creating green namespace..."
kubectl create namespace $GREEN_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Copy secrets to green namespace
kubectl get secret tempo-secret -n $BLUE_NAMESPACE -o yaml | \
  sed "s/namespace: $BLUE_NAMESPACE/namespace: $GREEN_NAMESPACE/" | \
  kubectl apply -f -

# 3. Deploy green
echo "[3/8] Deploying green environment..."
helm get values tempo -n $BLUE_NAMESPACE > /tmp/tempo-values.yaml

helm install tempo-green scripton-charts/tempo \
  --namespace $GREEN_NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --values /tmp/tempo-values.yaml \
  --wait \
  --timeout=15m

# 4. Verify green
echo "[4/8] Verifying green environment..."
kubectl wait --for=condition=ready pod -n $GREEN_NAMESPACE \
  -l app.kubernetes.io/name=tempo --timeout=300s

kubectl exec -n $GREEN_NAMESPACE tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ready

# 5. Test green
echo "[5/8] Testing green environment..."
kubectl exec -n $GREEN_NAMESPACE tempo-0 -c tempo -- \
  wget -qO- "http://localhost:3200/api/search?limit=5"

# 6. Switch traffic
echo "[6/8] Switching traffic to green..."
echo "  Update your ingress/load balancer to point to $GREEN_NAMESPACE"
echo "  Example for service: kubectl patch service tempo -n $BLUE_NAMESPACE -p '{\"spec\":{\"selector\":{\"app.kubernetes.io/instance\":\"tempo-green\"}}}'"
echo ""
echo "  Press ENTER when traffic is switched..."
read

# 7. Monitor (manual step)
echo "[7/8] Monitoring green environment..."
echo "  Monitor logs, metrics, and traces for 15-30 minutes"
echo "  Check: kubectl logs -n $GREEN_NAMESPACE -l app.kubernetes.io/name=tempo -f"
echo "  Press ENTER to continue with decommissioning blue..."
read

# 8. Decommission blue
echo "[8/8] Decommissioning blue environment..."
helm uninstall tempo -n $BLUE_NAMESPACE

echo ""
echo "=== Blue-Green Upgrade Complete ==="
echo "Green environment is now serving traffic in namespace: $GREEN_NAMESPACE"
```

---

### 3. Maintenance Window Upgrade

Controlled upgrade with planned downtime.

#### Prerequisites

- Maintenance window scheduled
- Backup created
- Users notified (trace ingestion will be paused)
- Downstream systems handle trace loss gracefully

#### Procedure

```bash
# 1. Notify downstream systems (pause trace generation if possible)
echo "Maintenance window started - trace ingestion paused"

# 2. Flush WAL and create full backup
kubectl exec -n tracing tempo-0 -c tempo -- wget -qO- -X POST http://localhost:3200/flush
sleep 60
make -f make/ops/tempo.mk tempo-backup-all

# 3. Scale down to 0
kubectl scale statefulset tempo -n tracing --replicas=0
kubectl wait --for=delete pod -n tracing -l app.kubernetes.io/name=tempo --timeout=120s

# 4. Update Helm chart
helm upgrade tempo scripton-charts/tempo \
  --set image.tag=2.9.0 \
  --reuse-values \
  --wait

# 5. Scale up to 1 for verification
kubectl scale statefulset tempo -n tracing --replicas=1
kubectl wait --for=condition=ready pod -n tracing tempo-0 --timeout=300s

# 6. Verify health
make -f make/ops/tempo.mk tempo-ready

# 7. Test trace ingestion
make -f make/ops/tempo.mk tempo-test-trace

# 8. Scale to original replica count
kubectl scale statefulset tempo -n tracing --replicas=3
kubectl rollout status statefulset tempo -n tracing

# 9. Resume normal operations
echo "Maintenance window complete - trace ingestion resumed"
```

#### Maintenance Window Script

```bash
#!/bin/bash
# maintenance-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-tracing}"
TARGET_VERSION="${TARGET_VERSION:-2.9.0}"
ORIGINAL_REPLICAS=$(kubectl get statefulset tempo -n $NAMESPACE -o jsonpath='{.spec.replicas}')

echo "=== Tempo Maintenance Window Upgrade ==="
echo "Target version: $TARGET_VERSION"
echo "Current replicas: $ORIGINAL_REPLICAS"

# 1. Flush WAL
echo "[1/8] Flushing WAL..."
kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush
sleep 60

# 2. Create backup
echo "[2/8] Creating pre-upgrade backup..."
make -f make/ops/tempo.mk tempo-backup-all

# 3. Scale down
echo "[3/8] Scaling down to 0..."
kubectl scale statefulset tempo -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=tempo --timeout=120s

# 4. Upgrade Helm release
echo "[4/8] Upgrading Helm release..."
helm upgrade tempo scripton-charts/tempo \
  --namespace $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout=15m

# 5. Scale up to 1 for verification
echo "[5/8] Scaling up to 1 replica..."
kubectl scale statefulset tempo -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE tempo-0 --timeout=300s

# 6. Verify health
echo "[6/8] Verifying Tempo health..."
kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ready

NEW_VERSION=$(kubectl exec -n $NAMESPACE tempo-0 -c tempo -- /tempo --version | head -1)
echo "New version: $NEW_VERSION"

# 7. Test trace query
echo "[7/8] Testing trace query..."
kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  wget -qO- "http://localhost:3200/api/search?limit=1"

# 8. Scale to original replica count
echo "[8/8] Scaling to original replica count ($ORIGINAL_REPLICAS)..."
kubectl scale statefulset tempo -n $NAMESPACE --replicas=$ORIGINAL_REPLICAS
kubectl rollout status statefulset tempo -n $NAMESPACE

echo ""
echo "=== Maintenance Upgrade Complete ==="
```

---

## Version-Specific Notes

### Tempo 2.7.x to 2.8.x

**Breaking Changes:**
- WAL format changes (v2)
- Query frontend request splitting improvements
- OTLP receiver protocol updates
- Metrics endpoint changes

**Migration Steps:**

1. **Flush WAL before upgrade:**
   ```bash
   # Critical: Flush all in-memory data before upgrade
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- -X POST http://localhost:3200/flush

   # Wait for WAL to be fully flushed
   sleep 60

   # Verify WAL is empty
   kubectl exec -n tracing tempo-0 -c tempo -- \
     ls -la /var/tempo/wal/
   ```

2. **Update distributor configuration (if customized):**
   ```yaml
   # Old (2.7.x)
   distributor:
     receivers:
       otlp:
         protocols:
           grpc:
             endpoint: 0.0.0.0:4317

   # New (2.8.x) - protocol format simplified
   distributor:
     receivers:
       otlp:
         protocols:
           grpc:
             endpoint: "0.0.0.0:4317"
           http:
             endpoint: "0.0.0.0:4318"
   ```

3. **Update compactor configuration:**
   ```yaml
   # New options in 2.8.x
   compactor:
     compaction:
       # New: Improved block selection
       max_block_bytes: 107374182400  # 100GB
       # New: Better compaction scheduling
       compaction_cycle: 30s
   ```

4. **Verify metrics endpoint compatibility:**
   ```bash
   # Check metrics are exposed correctly
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- http://localhost:3200/metrics | head -20
   ```

### Tempo 2.8.x to 2.9.x

**Changes:**
- Query frontend improvements (TraceQL enhancements)
- Improved vParquet4 block format support
- Better memory management
- Enhanced metrics for observability
- OTLP HTTP endpoint improvements

**Migration Steps:**

1. **No config changes required** - rolling upgrade supported

2. **Optional: Enable new TraceQL features:**
   ```yaml
   query_frontend:
     search:
       # Enhanced in 2.9.x
       max_duration: "0"  # No limit
       default_result_limit: 20
       max_result_limit: 5000
   ```

3. **Optional: Enable improved block format:**
   ```yaml
   storage:
     trace:
       # vParquet4 improvements in 2.9.x
       block:
         version: vParquet4
   ```

4. **Update resource limits (recommended):**
   ```yaml
   # 2.9.x has improved memory efficiency
   resources:
     requests:
       memory: 256Mi  # Can reduce from previous versions
     limits:
       memory: 2Gi
   ```

5. **Enable new metrics (optional):**
   ```yaml
   metrics_generator:
     # Enhanced in 2.9.x
     processor:
       service_graphs:
         dimensions:
           - service.namespace
           - service.version
   ```

### Jump Upgrade: Tempo 2.7.x to 2.9.x

**Considerations:**

- Higher risk than sequential upgrades
- WAL format changes require flush before upgrade
- Review all changes between versions
- Testing recommended in non-production environment

**Migration Steps:**

1. **Pre-upgrade preparation:**
   ```bash
   # Flush all WAL data
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- -X POST http://localhost:3200/flush
   sleep 120

   # Create comprehensive backup
   make -f make/ops/tempo.mk tempo-backup-all

   # Document current configuration
   kubectl get configmap tempo-config -n tracing -o yaml > tempo-config-2.7.yaml
   ```

2. **Review configuration changes:**
   ```bash
   # Compare configurations between versions
   # Check for deprecated options
   helm template tempo scripton-charts/tempo \
     --set image.tag=2.9.0 \
     --values tempo-values.yaml \
     --show-only templates/configmap.yaml > tempo-config-2.9-preview.yaml

   diff tempo-config-2.7.yaml tempo-config-2.9-preview.yaml
   ```

3. **Apply configuration updates:**
   ```yaml
   # Update values.yaml with 2.9.x compatible options
   tempo:
     storage:
       trace:
         backend: s3
         block:
           version: vParquet4

     ingester:
       # Updated for 2.9.x
       trace_idle_period: 10s
       max_block_duration: 30m

     compactor:
       compaction:
         # 2.9.x recommended settings
         compaction_window: 1h
         max_compaction_objects: 6000000
   ```

4. **Perform upgrade with extended timeout:**
   ```bash
   helm upgrade tempo scripton-charts/tempo \
     --set image.tag=2.9.0 \
     --reuse-values \
     --wait \
     --timeout=20m
   ```

5. **Post-upgrade verification:**
   ```bash
   # Verify version
   kubectl exec -n tracing tempo-0 -c tempo -- /tempo --version

   # Verify trace ingestion
   make -f make/ops/tempo.mk tempo-test-trace

   # Verify trace query
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- "http://localhost:3200/api/search?limit=10"

   # Check for any errors
   kubectl logs -n tracing tempo-0 -c tempo --tail=100 | grep -i error
   ```

---

## Post-Upgrade Validation

### Automated Post-Upgrade Check

```bash
# Run automated validation
make -f make/ops/tempo.mk tempo-post-upgrade-check
```

### Manual Post-Upgrade Validation

```bash
#!/bin/bash
# post-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-tracing}"
POD_NAME="${POD_NAME:-tempo-0}"
CONTAINER_NAME="${CONTAINER_NAME:-tempo}"

echo "=== Tempo Post-Upgrade Validation ==="
echo ""

# 1. Check version
echo "[1/10] Verifying new version..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /tempo --version 2>&1 | head -1 | awk '{print $2}')
echo "  New version: $NEW_VERSION"

# 2. Check pod status
echo "[2/10] Checking pod status..."
READY_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=tempo \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=tempo --no-headers | wc -l)
echo "  Ready pods: $READY_PODS/$TOTAL_PODS"

# 3. Check Tempo readiness
echo "[3/10] Checking Tempo readiness..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/ready
echo "  [OK] Tempo is ready"

# 4. Check distributor ring status
echo "[4/10] Checking distributor ring status..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/distributor/ring | grep -o '"state":"[^"]*"' | head -3
echo "  [OK] Distributor ring is healthy"

# 5. Check ingester status
echo "[5/10] Checking ingester status..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/ingester/ring | grep -o '"state":"[^"]*"' | head -3
echo "  [OK] Ingester ring is healthy"

# 6. Test trace query (TraceQL)
echo "[6/10] Testing TraceQL query..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- "http://localhost:3200/api/search?q={status=ok}&limit=5" | head -20
echo "  [OK] TraceQL query successful"

# 7. Test tag search
echo "[7/10] Testing tag search..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- "http://localhost:3200/api/v2/search/tags" | head -10
echo "  [OK] Tag search successful"

# 8. Check OTLP receiver
echo "[8/10] Checking OTLP receiver status..."
SPANS_TOTAL=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/metrics 2>/dev/null | \
  grep "tempo_distributor_spans_received_total" | head -1 || echo "N/A")
echo "  $SPANS_TOTAL"

# 9. Check metrics
echo "[9/10] Checking key metrics..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/metrics 2>/dev/null | \
  grep -E "(tempo_build_info|tempo_ingester_blocks_flushed_total)" | head -2

# 10. Check for errors
echo "[10/10] Checking for errors..."
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
helm history tempo -n tracing

# Rollback to previous revision
helm rollback tempo -n tracing

# Or rollback to specific revision
helm rollback tempo 5 -n tracing

# Verify rollback
kubectl rollout status statefulset tempo -n tracing
```

### Method 2: Restore from Backup

```bash
# Scale down current deployment
kubectl scale statefulset tempo -n tracing --replicas=0

# Restore from backup
make -f make/ops/tempo.mk tempo-restore-all BACKUP_FILE=/path/to/backup.tar.gz

# Restore configuration
kubectl apply -f tempo-config-pre-upgrade.yaml

# Scale up
kubectl scale statefulset tempo -n tracing --replicas=3
```

### Method 3: Revert Image Tag

```bash
# Revert to previous image tag
helm upgrade tempo scripton-charts/tempo \
  --set image.tag=2.8.3 \
  --reuse-values

# Verify rollback
kubectl rollout status statefulset tempo -n tracing

# Verify version
kubectl exec -n tracing tempo-0 -c tempo -- /tempo --version
```

### Rollback Script

```bash
#!/bin/bash
# rollback.sh

set -e

NAMESPACE="${NAMESPACE:-tracing}"
PREVIOUS_VERSION="${PREVIOUS_VERSION:-2.8.3}"

echo "=== Tempo Rollback to $PREVIOUS_VERSION ==="

# 1. Check current state
echo "[1/5] Checking current state..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  /tempo --version 2>&1 | head -1 | awk '{print $2}')
echo "  Current version: $CURRENT_VERSION"

# 2. Confirm rollback
echo ""
echo "[WARN] This will rollback Tempo from $CURRENT_VERSION to $PREVIOUS_VERSION"
echo "Press ENTER to continue or Ctrl+C to cancel..."
read

# 3. Flush WAL before rollback
echo "[2/5] Flushing WAL..."
kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush || true
sleep 30

# 4. Perform rollback
echo "[3/5] Performing Helm rollback..."
helm rollback tempo -n $NAMESPACE

# 5. Wait for rollback
echo "[4/5] Waiting for rollback to complete..."
kubectl rollout status statefulset tempo -n $NAMESPACE

# 6. Verify rollback
echo "[5/5] Verifying rollback..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  /tempo --version 2>&1 | head -1 | awk '{print $2}')
echo "  Rolled back to: $NEW_VERSION"

kubectl exec -n $NAMESPACE tempo-0 -c tempo -- \
  wget -qO- http://localhost:3200/ready

echo ""
echo "=== Rollback Complete ==="
```

---

## Troubleshooting

### Issue 1: Pods Stuck in CrashLoopBackOff

**Symptoms:**
- Pods crash after upgrade
- Tempo won't start
- Config validation errors

**Solutions:**

1. **Check logs:**
   ```bash
   kubectl logs -n tracing tempo-0 -c tempo --tail=100
   kubectl logs -n tracing tempo-0 -c tempo --previous
   ```

2. **Validate configuration:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     /tempo -config.file=/etc/tempo/tempo.yaml -config.verify
   ```

3. **Check for deprecated options:**
   ```bash
   kubectl logs -n tracing tempo-0 -c tempo | grep -i deprecated
   ```

4. **Rollback to previous version:**
   ```bash
   helm rollback tempo -n tracing
   ```

### Issue 2: WAL Corruption After Upgrade

**Symptoms:**
- Tempo fails to start with WAL errors
- "failed to recover from WAL" messages
- Data loss on restart

**Solutions:**

1. **Check WAL status:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- ls -la /var/tempo/wal/
   ```

2. **Clear corrupted WAL (data loss):**
   ```bash
   # WARNING: This will lose in-flight traces
   kubectl exec -n tracing tempo-0 -c tempo -- rm -rf /var/tempo/wal/*

   # Restart pod
   kubectl delete pod tempo-0 -n tracing
   ```

3. **Restore from backup:**
   ```bash
   make -f make/ops/tempo.mk tempo-restore-wal BACKUP_FILE=/path/to/backup.tar.gz
   ```

### Issue 3: S3 Connection Failures

**Symptoms:**
- "NoSuchBucket" errors
- S3 timeout errors
- Blocks not uploaded

**Solutions:**

1. **Verify S3 credentials:**
   ```bash
   kubectl get secret tempo-secret -n tracing -o jsonpath='{.data.access-key-id}' | base64 -d
   ```

2. **Test S3 connectivity:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -O- http://minio:9000/tempo-traces/
   ```

3. **Check bucket exists:**
   ```bash
   # Using MinIO client
   mc ls myminio/tempo-traces/
   ```

4. **Update S3 configuration:**
   ```yaml
   tempo:
     storage:
       type: s3
       s3:
         endpoint: "minio.default.svc.cluster.local:9000"
         bucket: "tempo-traces"
         insecure: true  # For HTTP endpoints
   ```

### Issue 4: Traces Not Appearing After Upgrade

**Symptoms:**
- No new traces visible
- OTLP receiver not accepting traces
- Grafana shows empty results

**Solutions:**

1. **Check OTLP receiver status:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- http://localhost:3200/ready

   # Check receiver metrics
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- http://localhost:3200/metrics | grep tempo_distributor_spans
   ```

2. **Verify service endpoints:**
   ```bash
   kubectl get svc tempo -n tracing -o yaml
   kubectl get endpoints tempo -n tracing
   ```

3. **Test trace ingestion:**
   ```bash
   make -f make/ops/tempo.mk tempo-test-trace
   ```

4. **Check for protocol changes:**
   ```yaml
   # Ensure receivers are properly configured
   tempo:
     receivers:
       otlp:
         grpc:
           enabled: true
           port: 4317
         http:
           enabled: true
           port: 4318
   ```

### Issue 5: High Memory Usage

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
       memory: 1Gi
   ```

2. **Adjust ingester settings:**
   ```yaml
   tempo:
     ingester:
       trace_idle_period: 5s  # Flush traces faster
       max_block_duration: 15m  # Smaller blocks
   ```

3. **Limit concurrent queries:**
   ```yaml
   tempo:
     query_frontend:
       max_outstanding_per_tenant: 100
   ```

### Issue 6: Ring Membership Issues

**Symptoms:**
- Pods not joining ring
- Memberlist errors
- Replication failures

**Solutions:**

1. **Check ring status:**
   ```bash
   make -f make/ops/tempo.mk tempo-ring-status
   ```

2. **Check memberlist:**
   ```bash
   make -f make/ops/tempo.mk tempo-memberlist-status
   ```

3. **Restart affected pods:**
   ```bash
   kubectl delete pod tempo-1 -n tracing
   kubectl wait --for=condition=ready pod tempo-1 -n tracing --timeout=300s
   ```

4. **Verify network connectivity:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     nc -zv tempo-1.tempo.tracing.svc.cluster.local 7946
   ```

### Issue 7: Compactor Not Running

**Symptoms:**
- Blocks not being compacted
- Storage growing unexpectedly
- Old blocks not deleted

**Solutions:**

1. **Check compactor status:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- http://localhost:3200/compactor/ring
   ```

2. **Check compactor logs:**
   ```bash
   kubectl logs -n tracing tempo-0 -c tempo | grep -i compact
   ```

3. **Verify compactor configuration:**
   ```yaml
   tempo:
     compactor:
       compaction:
         compaction_window: 1h
         max_block_bytes: 107374182400  # 100GB
   ```

### Issue 8: Query Frontend Errors

**Symptoms:**
- TraceQL queries failing
- Slow query performance
- "query failed" errors

**Solutions:**

1. **Check query frontend status:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- http://localhost:3200/status/query-frontend
   ```

2. **Increase query timeout:**
   ```yaml
   tempo:
     query_frontend:
       search:
         max_duration: 0  # No limit
   ```

3. **Check backend storage access:**
   ```bash
   kubectl exec -n tracing tempo-0 -c tempo -- \
     wget -qO- "http://localhost:3200/api/search?limit=1"
   ```

---

## Best Practices

### Before Upgrade

1. **Always flush WAL** before upgrading
2. **Create full backup** before upgrading
3. **Test upgrade in non-production** environment first
4. **Review release notes** for breaking changes
5. **Document current configuration** for rollback
6. **Plan rollback procedure** before starting
7. **Schedule maintenance window** if needed
8. **Notify downstream systems** about potential trace loss

### During Upgrade

1. **Monitor logs** during upgrade process
2. **Check pod health** after each pod updates
3. **Verify trace ingestion** works after upgrade
4. **Monitor metrics** for anomalies
5. **Be ready to rollback** if issues occur
6. **Watch ring membership** for consistency

### After Upgrade

1. **Run post-upgrade validation** script
2. **Monitor for 24 hours** after upgrade
3. **Test trace queries** in Grafana
4. **Verify OTLP receivers** accept traces
5. **Check compactor status** and verify blocks are compacting
6. **Update documentation** with new version
7. **Clean up old backups** after successful upgrade

### General Recommendations

1. **Use S3 storage** for easier upgrades and HA
2. **Set replication factor >= 2** for zero-downtime upgrades
3. **Keep Tempo up to date** (within 2 minor versions)
4. **Automate upgrade testing** in CI/CD
5. **Document custom configurations** for future reference
6. **Configure PodDisruptionBudget** for HA deployments
7. **Enable ServiceMonitor** for upgrade monitoring
8. **Set appropriate resource limits** based on trace volume

### Trace Preservation

1. **Flush WAL before any maintenance**
2. **Configure adequate retention** for your use case
3. **Use shared S3 storage** for multi-replica deployments
4. **Monitor block storage usage**
5. **Verify compaction is running** regularly

---

## Related Documentation

- [Tempo Backup Guide](tempo-backup-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/tempo/README.md)
- [Tempo Makefile](../make/ops/tempo.mk)
- [Observability Stack Guide](observability-stack-guide.md)

---

**Last Updated:** 2025-12-01
**Chart Version:** 0.3.0
**Tempo Version:** 2.9.0
