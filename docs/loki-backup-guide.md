# Loki Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for Loki deployed via the Helm chart.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Configuration Backup](#1-configuration-backup)
  - [2. Log Data Backup](#2-log-data-backup)
  - [3. Index Backup](#3-index-backup)
  - [4. PVC Snapshot Backup](#4-pvc-snapshot-backup)
- [Backup Procedures](#backup-procedures)
  - [Full Backup](#full-backup)
  - [Configuration-Only Backup](#configuration-only-backup)
  - [Data-Only Backup](#data-only-backup)
- [Recovery Procedures](#recovery-procedures)
  - [Full Recovery](#full-recovery)
  - [Configuration Recovery](#configuration-recovery)
  - [Data Recovery](#data-recovery)
- [Backup Automation](#backup-automation)
- [Backup Verification](#backup-verification)
- [RTO & RPO Targets](#rto--rpo-targets)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Strategy

Loki backup strategy depends on storage backend:

| Storage Type | Backup Strategy | Complexity | Data Loss Risk |
|-------------|----------------|-----------|---------------|
| **Filesystem** | ConfigMap + PVC snapshot | Medium | Low (1 hour RPO) |
| **S3** | ConfigMap + S3 bucket snapshot | Low | Very Low (continuous) |

### Key Backup Components

1. **Configuration** - Loki YAML config, ring configuration
2. **Log Data** - Chunks (compressed log data)
3. **Index** - BoltDB or TSDB index files
4. **PVC** - Persistent volume data (filesystem mode only)

### RTO/RPO Summary

| Component | RTO (Recovery Time) | RPO (Recovery Point) | Backup Frequency |
|-----------|-------------------|---------------------|-----------------|
| Configuration | < 5 minutes | 0 | Daily or before changes |
| Log Data (filesystem) | < 1 hour | 1 hour | Hourly |
| Log Data (S3) | < 10 minutes | 0 | Continuous (S3 versioning) |
| Index | < 30 minutes | 1 hour | Hourly |
| PVC Snapshot | < 2 hours | 1 week | Weekly |

---

## Backup Strategy

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Loki Backup Components                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ ConfigMap    │  │  Log Chunks  │  │  Index Files │         │
│  │ (Loki YAML)  │  │  (/loki/     │  │  (/loki/     │         │
│  │              │  │   chunks/)   │  │   index/)    │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                 │                  │                 │
│         ├─────────────────┴──────────────────┘                 │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────┐         │
│  │         Backup Storage (S3/MinIO)                │         │
│  │  - /backups/loki/config/                         │         │
│  │  - /backups/loki/data/                           │         │
│  │  - /backups/loki/index/                          │         │
│  │  - /backups/loki/pvc-snapshots/                  │         │
│  └──────────────────────────────────────────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Storage-Specific Strategies

#### Filesystem Storage

**Components to backup:**
1. Configuration (ConfigMap)
2. PVC data (/loki directory)
3. Index files (if using BoltDB)

**Backup method:**
- ConfigMap export
- PVC snapshot (VolumeSnapshot API)
- Data extraction via kubectl cp

**Recovery method:**
- ConfigMap restore
- PVC restore from snapshot
- Data restoration via kubectl cp

#### S3 Storage

**Components to backup:**
1. Configuration (ConfigMap)
2. S3 bucket lifecycle management
3. Index files (local PVC)

**Backup method:**
- ConfigMap export
- S3 bucket versioning/replication
- Index PVC snapshot

**Recovery method:**
- ConfigMap restore
- S3 data recovery (versioning)
- Index rebuild from S3 data

---

## Backup Components

### 1. Configuration Backup

Configuration includes Loki YAML, ring settings, and storage configuration.

#### Backup Configuration

```bash
# Backup ConfigMap
make -f make/ops/loki.mk loki-backup-config

# Or manually
kubectl get configmap -n monitoring loki -o yaml > loki-config-backup.yaml
```

#### What's Included

- `loki.yaml` - Main Loki configuration
- `auth_enabled` - Authentication settings
- `server` - HTTP/gRPC server config
- `common` - Storage, ring, replication config
- `schema_config` - Index schema definitions
- `storage_config` - Chunk storage settings
- `limits_config` - Rate limits, retention

#### Storage Requirements

- Size: ~50-200 KB
- Retention: 90 days recommended
- Backup frequency: Daily or before changes

---

### 2. Log Data Backup

Log data (chunks) contain compressed log entries.

#### Filesystem Storage Backup

**Method 1: PVC Snapshot (Recommended)**

```bash
# Create PVC snapshot
make -f make/ops/loki.mk loki-backup-pvc-snapshot

# Or manually with VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: loki-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: monitoring
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: loki-loki-0
EOF
```

**Method 2: Data Extraction**

```bash
# Extract chunks directory
make -f make/ops/loki.mk loki-backup-data

# Or manually
POD_NAME=loki-0
NAMESPACE=monitoring
BACKUP_DIR=./backups/loki/data/$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- tar czf - /loki/chunks | \
  tar xzf - -C $BACKUP_DIR
```

#### S3 Storage Backup

**Method: S3 Versioning & Lifecycle**

```bash
# Enable S3 versioning (AWS CLI)
aws s3api put-bucket-versioning \
  --bucket loki-chunks \
  --versioning-configuration Status=Enabled

# Configure lifecycle policy for backups
cat > lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "Id": "loki-chunks-lifecycle",
      "Status": "Enabled",
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 365
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket loki-chunks \
  --lifecycle-configuration file://lifecycle-policy.json
```

**S3 Bucket Snapshot**

```bash
# Sync S3 bucket to backup location
aws s3 sync s3://loki-chunks s3://loki-backups/chunks/$(date +%Y%m%d-%H%M%S) \
  --storage-class GLACIER_IR
```

#### Storage Requirements

| Storage Type | Data Size | Retention | Backup Frequency |
|-------------|-----------|----------|-----------------|
| Filesystem | 1-100 GB | 30 days | Hourly |
| S3 | Unlimited | 90-365 days | Continuous (versioning) |

---

### 3. Index Backup

Index files (BoltDB or TSDB) enable fast log queries.

#### Backup Index

```bash
# Flush in-memory index to disk first
make -f make/ops/loki.mk loki-flush-index

# Backup index files
make -f make/ops/loki.mk loki-backup-index

# Or manually
POD_NAME=loki-0
NAMESPACE=monitoring
BACKUP_DIR=./backups/loki/index/$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- tar czf - /loki/index | \
  tar xzf - -C $BACKUP_DIR
```

#### Index Rebuild (Alternative Recovery)

If index backups are lost, rebuild from chunk data:

```bash
# For BoltDB Shipper (filesystem)
# Loki will automatically rebuild index from chunks on startup

# For TSDB (S3)
# Use Loki compactor to rebuild index
kubectl exec -n monitoring loki-0 -c loki -- \
  /usr/bin/loki -target=compactor -config.file=/etc/loki/loki.yaml
```

#### Storage Requirements

- Size: 100 MB - 10 GB (depending on log volume)
- Retention: 30 days
- Backup frequency: Hourly

---

### 4. PVC Snapshot Backup

Complete persistent volume backup (filesystem mode only).

#### Create PVC Snapshot

```bash
# Automated snapshot
make -f make/ops/loki.mk loki-backup-pvc-snapshot

# Or manually
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: loki-pvc-snapshot-$TIMESTAMP
  namespace: monitoring
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: loki-loki-0
EOF
```

#### Verify Snapshot

```bash
# Check snapshot status
kubectl get volumesnapshot -n monitoring loki-pvc-snapshot-$TIMESTAMP

# Get snapshot details
kubectl describe volumesnapshot -n monitoring loki-pvc-snapshot-$TIMESTAMP
```

#### Storage Requirements

- Size: Same as PVC (10-100 GB typical)
- Retention: 7-14 days
- Backup frequency: Weekly

---

## Backup Procedures

### Full Backup

Complete backup of all Loki components.

#### Automated Full Backup

```bash
# Full backup (config + data + index)
make -f make/ops/loki.mk loki-backup-all
```

#### Manual Full Backup Script

```bash
#!/bin/bash
# full-backup.sh - Complete Loki backup

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
POD_NAME="${POD_NAME:-loki-0}"
CONTAINER_NAME="${CONTAINER_NAME:-loki}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT="./backups/loki"
BACKUP_DIR="$BACKUP_ROOT/full/$TIMESTAMP"

mkdir -p $BACKUP_DIR/{config,data,index,metadata}

echo "=== Loki Full Backup Started: $TIMESTAMP ==="

# 1. Flush in-memory index
echo "[1/5] Flushing in-memory index..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- -X POST http://localhost:3100/flush

sleep 5

# 2. Backup configuration
echo "[2/5] Backing up configuration..."
kubectl get configmap -n $NAMESPACE loki -o yaml > \
  $BACKUP_DIR/config/configmap.yaml

kubectl get secret -n $NAMESPACE loki-s3-credentials -o yaml > \
  $BACKUP_DIR/config/secret.yaml 2>/dev/null || true

# 3. Backup metadata
echo "[3/5] Backing up metadata..."
kubectl get statefulset -n $NAMESPACE loki -o yaml > \
  $BACKUP_DIR/metadata/statefulset.yaml

kubectl get service -n $NAMESPACE loki -o yaml > \
  $BACKUP_DIR/metadata/service.yaml

kubectl get pvc -n $NAMESPACE loki-loki-0 -o yaml > \
  $BACKUP_DIR/metadata/pvc.yaml

# 4. Backup data (chunks)
echo "[4/5] Backing up log data..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  tar czf - /loki/chunks 2>/dev/null | \
  cat > $BACKUP_DIR/data/chunks.tar.gz || echo "Chunks backup skipped (empty or S3 mode)"

# 5. Backup index
echo "[5/5] Backing up index..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  tar czf - /loki/index 2>/dev/null | \
  cat > $BACKUP_DIR/index/index.tar.gz || echo "Index backup skipped (empty or S3 mode)"

# Create backup manifest
cat > $BACKUP_DIR/backup-manifest.yaml <<EOF
backup:
  timestamp: $TIMESTAMP
  namespace: $NAMESPACE
  pod: $POD_NAME
  components:
    - config
    - data
    - index
    - metadata
  loki_version: $(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- /usr/bin/loki --version | head -1)
EOF

echo "=== Loki Full Backup Complete ==="
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Backup contents:"
du -sh $BACKUP_DIR/*

# Optionally upload to S3/MinIO
if [ -n "$S3_BUCKET" ]; then
  echo ""
  echo "Uploading to S3..."
  tar czf - -C $BACKUP_ROOT/full $TIMESTAMP | \
    aws s3 cp - s3://$S3_BUCKET/loki/full/loki-backup-$TIMESTAMP.tar.gz
  echo "Upload complete: s3://$S3_BUCKET/loki/full/loki-backup-$TIMESTAMP.tar.gz"
fi
```

---

### Configuration-Only Backup

Lightweight backup for config changes.

```bash
# Automated config backup
make -f make/ops/loki.mk loki-backup-config

# Or manually
NAMESPACE=monitoring
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/loki/config/$TIMESTAMP

mkdir -p $BACKUP_DIR

kubectl get configmap -n $NAMESPACE loki -o yaml > \
  $BACKUP_DIR/configmap.yaml

kubectl get secret -n $NAMESPACE loki-s3-credentials -o yaml > \
  $BACKUP_DIR/secret.yaml 2>/dev/null || true

echo "Config backup complete: $BACKUP_DIR"
```

---

### Data-Only Backup

Backup log data without configuration.

```bash
# Automated data backup
make -f make/ops/loki.mk loki-backup-data

# Or manually
NAMESPACE=monitoring
POD_NAME=loki-0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/loki/data/$TIMESTAMP

mkdir -p $BACKUP_DIR

# Flush index first
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- \
  wget -qO- -X POST http://localhost:3100/flush

# Backup chunks
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- \
  tar czf - /loki/chunks 2>/dev/null | \
  cat > $BACKUP_DIR/chunks.tar.gz

# Backup index
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- \
  tar czf - /loki/index 2>/dev/null | \
  cat > $BACKUP_DIR/index.tar.gz

echo "Data backup complete: $BACKUP_DIR"
```

---

## Recovery Procedures

### Full Recovery

Complete restoration from full backup.

#### Automated Full Recovery

```bash
# Restore from backup
make -f make/ops/loki.mk loki-restore-all BACKUP_FILE=/path/to/backup.tar.gz
```

#### Manual Full Recovery Script

```bash
#!/bin/bash
# full-restore.sh - Complete Loki restoration

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <backup-directory>"
  exit 1
fi

BACKUP_DIR="$1"
NAMESPACE="${NAMESPACE:-monitoring}"
POD_NAME="${POD_NAME:-loki-0}"
CONTAINER_NAME="${CONTAINER_NAME:-loki}"

echo "=== Loki Full Recovery Started ==="
echo "Backup source: $BACKUP_DIR"

# 1. Verify backup
if [ ! -f "$BACKUP_DIR/backup-manifest.yaml" ]; then
  echo "ERROR: Invalid backup directory (no manifest found)"
  exit 1
fi

# 2. Scale down Loki
echo "[1/6] Scaling down Loki..."
kubectl scale statefulset loki -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=loki --timeout=120s

# 3. Restore configuration
echo "[2/6] Restoring configuration..."
if [ -f "$BACKUP_DIR/config/configmap.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/configmap.yaml
fi

if [ -f "$BACKUP_DIR/config/secret.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/secret.yaml
fi

# 4. Restore PVC data
echo "[3/6] Restoring PVC data..."

# Scale up temporarily to restore data
kubectl scale statefulset loki -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# Restore chunks
if [ -f "$BACKUP_DIR/data/chunks.tar.gz" ]; then
  echo "  Restoring chunks..."
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm -rf /loki/chunks/*
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- mkdir -p /loki/chunks
  kubectl cp $BACKUP_DIR/data/chunks.tar.gz $NAMESPACE/$POD_NAME:/tmp/chunks.tar.gz -c $CONTAINER_NAME
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- tar xzf /tmp/chunks.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm /tmp/chunks.tar.gz
fi

# Restore index
if [ -f "$BACKUP_DIR/index/index.tar.gz" ]; then
  echo "  Restoring index..."
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm -rf /loki/index/*
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- mkdir -p /loki/index
  kubectl cp $BACKUP_DIR/index/index.tar.gz $NAMESPACE/$POD_NAME:/tmp/index.tar.gz -c $CONTAINER_NAME
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- tar xzf /tmp/index.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm /tmp/index.tar.gz
fi

# 5. Restart Loki
echo "[4/6] Restarting Loki..."
kubectl rollout restart statefulset loki -n $NAMESPACE
kubectl rollout status statefulset loki -n $NAMESPACE

# 6. Wait for Loki to be ready
echo "[5/6] Waiting for Loki to be ready..."
kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# 7. Verify recovery
echo "[6/6] Verifying recovery..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3100/ready

echo ""
echo "=== Loki Full Recovery Complete ==="
echo ""
echo "Verification:"
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- ls -lh /loki
echo ""
echo "Test query: make -f make/ops/loki.mk loki-query QUERY='{job=\"loki\"}' TIME=1h"
```

---

### Configuration Recovery

Restore only configuration without data.

```bash
# Automated config restore
make -f make/ops/loki.mk loki-restore-config BACKUP_FILE=/path/to/config-backup.tar.gz

# Or manually
BACKUP_DIR=/path/to/config/backup
NAMESPACE=monitoring

# Apply ConfigMap
kubectl apply -f $BACKUP_DIR/configmap.yaml

# Apply Secret (if exists)
kubectl apply -f $BACKUP_DIR/secret.yaml 2>/dev/null || true

# Restart Loki to apply new config
kubectl rollout restart statefulset loki -n $NAMESPACE
kubectl rollout status statefulset loki -n $NAMESPACE
```

---

### Data Recovery

Restore log data and index.

```bash
# Automated data restore
make -f make/ops/loki.mk loki-restore-data BACKUP_FILE=/path/to/data-backup.tar.gz

# Or manually
BACKUP_DIR=/path/to/data/backup
NAMESPACE=monitoring
POD_NAME=loki-0

# Scale down Loki
kubectl scale statefulset loki -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=loki --timeout=120s

# Scale up
kubectl scale statefulset loki -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# Restore chunks
kubectl cp $BACKUP_DIR/chunks.tar.gz $NAMESPACE/$POD_NAME:/tmp/chunks.tar.gz -c loki
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- tar xzf /tmp/chunks.tar.gz -C /
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- rm /tmp/chunks.tar.gz

# Restore index
kubectl cp $BACKUP_DIR/index.tar.gz $NAMESPACE/$POD_NAME:/tmp/index.tar.gz -c loki
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- tar xzf /tmp/index.tar.gz -C /
kubectl exec -n $NAMESPACE $POD_NAME -c loki -- rm /tmp/index.tar.gz

# Restart
kubectl rollout restart statefulset loki -n $NAMESPACE
```

---

## Backup Automation

### CronJob for Scheduled Backups

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: loki-backup
  namespace: monitoring
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: loki-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              set -e
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_DIR=/backup/loki/$TIMESTAMP
              mkdir -p $BACKUP_DIR/{config,data,index}

              # Flush index
              kubectl exec -n monitoring loki-0 -c loki -- \
                wget -qO- -X POST http://localhost:3100/flush

              # Backup config
              kubectl get configmap -n monitoring loki -o yaml > \
                $BACKUP_DIR/config/configmap.yaml

              # Backup data
              kubectl exec -n monitoring loki-0 -c loki -- \
                tar czf - /loki/chunks 2>/dev/null | \
                cat > $BACKUP_DIR/data/chunks.tar.gz || true

              # Backup index
              kubectl exec -n monitoring loki-0 -c loki -- \
                tar czf - /loki/index 2>/dev/null | \
                cat > $BACKUP_DIR/index/index.tar.gz || true

              # Upload to S3
              tar czf - -C /backup/loki $TIMESTAMP | \
                aws s3 cp - s3://$S3_BUCKET/loki/loki-backup-$TIMESTAMP.tar.gz

              echo "Backup complete: s3://$S3_BUCKET/loki/loki-backup-$TIMESTAMP.tar.gz"
            env:
            - name: S3_BUCKET
              value: "my-backups"
            volumeMounts:
            - name: backup
              mountPath: /backup
          restartPolicy: OnFailure
          volumes:
          - name: backup
            emptyDir: {}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki-backup
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: loki-backup
  namespace: monitoring
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec"]
  verbs: ["get", "list", "create"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: loki-backup
  namespace: monitoring
subjects:
- kind: ServiceAccount
  name: loki-backup
  namespace: monitoring
roleRef:
  kind: Role
  name: loki-backup
  apiGroup: rbac.authorization.k8s.io
```

---

## Backup Verification

### Verify Backup Integrity

```bash
# Verify backup completeness
make -f make/ops/loki.mk loki-backup-verify BACKUP_FILE=/path/to/backup.tar.gz

# Or manually
BACKUP_DIR=/path/to/backup

# Check manifest
if [ -f "$BACKUP_DIR/backup-manifest.yaml" ]; then
  echo "✓ Manifest found"
  cat $BACKUP_DIR/backup-manifest.yaml
else
  echo "✗ Manifest missing"
fi

# Check config
if [ -f "$BACKUP_DIR/config/configmap.yaml" ]; then
  echo "✓ ConfigMap found"
else
  echo "✗ ConfigMap missing"
fi

# Check data
if [ -f "$BACKUP_DIR/data/chunks.tar.gz" ]; then
  echo "✓ Chunks found ($(du -sh $BACKUP_DIR/data/chunks.tar.gz))"
else
  echo "⚠ Chunks missing (S3 mode or empty)"
fi

# Check index
if [ -f "$BACKUP_DIR/index/index.tar.gz" ]; then
  echo "✓ Index found ($(du -sh $BACKUP_DIR/index/index.tar.gz))"
else
  echo "⚠ Index missing (S3 mode or empty)"
fi
```

### Test Restore (Dry Run)

```bash
# Test restore without actually restoring
BACKUP_DIR=/path/to/backup

# Extract to temporary location
TEMP_DIR=$(mktemp -d)
tar xzf $BACKUP_DIR.tar.gz -C $TEMP_DIR

# Verify files can be extracted
echo "Config files:"
ls -lh $TEMP_DIR/config/

echo "Data files:"
ls -lh $TEMP_DIR/data/

echo "Index files:"
ls -lh $TEMP_DIR/index/

# Cleanup
rm -rf $TEMP_DIR
```

---

## RTO & RPO Targets

### Recovery Time Objective (RTO)

| Scenario | RTO Target | Steps |
|---------|-----------|-------|
| Configuration only | < 5 minutes | ConfigMap apply + restart |
| Data restore (filesystem) | < 1 hour | PVC snapshot restore + restart |
| Data restore (S3) | < 10 minutes | Config apply + S3 data recovery |
| Full restore | < 2 hours | All components restoration |

### Recovery Point Objective (RPO)

| Component | RPO Target | Backup Frequency | Data Loss |
|----------|-----------|-----------------|----------|
| Configuration | 0 | Before changes | None |
| Log data (filesystem) | 1 hour | Hourly | Max 1 hour logs |
| Log data (S3) | 0 | Continuous | None (versioning) |
| Index | 1 hour | Hourly | Rebuildable from chunks |

---

## Best Practices

### Backup Strategy

1. **Use S3 storage for production:**
   - Continuous backup via S3 versioning
   - Lower RTO/RPO than filesystem
   - Easier to scale

2. **Implement 3-2-1 backup rule:**
   - 3 copies of data
   - 2 different storage types
   - 1 offsite backup

3. **Automate backups:**
   - Use CronJob for scheduled backups
   - Monitor backup job success/failure
   - Alert on backup failures

4. **Test restore procedures:**
   - Monthly restore test to non-production
   - Verify data integrity after restore
   - Document restore time

### Backup Retention

| Backup Type | Retention Policy | Storage Location |
|------------|-----------------|-----------------|
| Hourly (data) | 7 days | S3 Standard |
| Daily (config) | 30 days | S3 Standard |
| Weekly (PVC) | 90 days | S3 IA |
| Monthly | 1 year | S3 Glacier |

### Security

1. **Encrypt backups at rest:**
   ```bash
   # S3 encryption
   aws s3api put-bucket-encryption \
     --bucket loki-backups \
     --server-side-encryption-configuration \
     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```

2. **Restrict backup access:**
   - Use IAM roles for S3 access
   - Limit ServiceAccount permissions
   - Enable S3 bucket versioning

3. **Audit backup access:**
   - Enable CloudTrail for S3
   - Monitor backup job logs
   - Alert on unauthorized access

---

## Troubleshooting

### Issue 1: Backup Too Large

**Symptoms:**
- Backup exceeds storage quota
- S3 upload times out
- PVC snapshot fails

**Solutions:**

1. **Reduce retention period:**
   ```yaml
   loki:
     limits:
       retention_period: 168h  # 7 days instead of 30
   ```

2. **Implement log filtering:**
   ```yaml
   loki:
     limits:
       reject_old_samples: true
       reject_old_samples_max_age: 168h
   ```

3. **Use S3 lifecycle policies:**
   ```bash
   # Move old data to Glacier
   aws s3api put-bucket-lifecycle-configuration \
     --bucket loki-chunks \
     --lifecycle-configuration file://lifecycle.json
   ```

### Issue 2: Index Corruption After Restore

**Symptoms:**
- Queries fail after restore
- Index files missing
- BoltDB errors

**Solutions:**

1. **Rebuild index from chunks:**
   ```bash
   # Delete corrupted index
   kubectl exec -n monitoring loki-0 -c loki -- rm -rf /loki/index/*

   # Restart Loki (will rebuild index)
   kubectl rollout restart statefulset loki -n monitoring
   ```

2. **Run compactor to rebuild:**
   ```bash
   kubectl exec -n monitoring loki-0 -c loki -- \
     /usr/bin/loki -target=compactor -config.file=/etc/loki/loki.yaml
   ```

### Issue 3: S3 Backup Incomplete

**Symptoms:**
- Missing chunks in S3
- Queries return partial results
- S3 sync fails

**Solutions:**

1. **Check S3 permissions:**
   ```bash
   # Verify S3 access
   kubectl exec -n monitoring loki-0 -c loki -- \
     aws s3 ls s3://loki-chunks/
   ```

2. **Force chunk flush:**
   ```bash
   make -f make/ops/loki.mk loki-flush-index
   ```

3. **Resync S3 bucket:**
   ```bash
   aws s3 sync s3://loki-chunks s3://loki-backups/chunks/$(date +%Y%m%d)
   ```

### Issue 4: Restore Fails Due to Version Mismatch

**Symptoms:**
- Loki won't start after restore
- Config validation fails
- Schema version errors

**Solutions:**

1. **Check Loki version:**
   ```bash
   # Check backup manifest
   grep loki_version backup-manifest.yaml

   # Check current version
   kubectl exec -n monitoring loki-0 -c loki -- /usr/bin/loki --version
   ```

2. **Upgrade/downgrade Loki:**
   ```bash
   # Match version from backup
   helm upgrade loki scripton-charts/loki \
     --set image.tag=3.6.1 \
     --reuse-values
   ```

3. **Migrate configuration:**
   ```bash
   # Use Loki config migration tool
   /usr/bin/loki -config.file=/etc/loki/loki.yaml -validate-config
   ```

### Issue 5: PVC Snapshot Fails

**Symptoms:**
- VolumeSnapshot stuck in Pending
- CSI driver errors
- Snapshot creation timeout

**Solutions:**

1. **Check CSI driver:**
   ```bash
   kubectl get csidrivers
   kubectl get volumesnapshotclass
   ```

2. **Verify snapshot class:**
   ```bash
   kubectl describe volumesnapshotclass csi-snapclass
   ```

3. **Manually create snapshot:**
   ```bash
   # Create VolumeSnapshot manually
   cat <<EOF | kubectl apply -f -
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: loki-manual-snapshot
     namespace: monitoring
   spec:
     volumeSnapshotClassName: csi-snapclass
     source:
       persistentVolumeClaimName: loki-loki-0
   EOF
   ```

4. **Fallback to data extraction:**
   ```bash
   # If snapshots don't work, use kubectl cp
   make -f make/ops/loki.mk loki-backup-data
   ```

### Issue 6: High Backup Storage Costs

**Symptoms:**
- S3 costs exceed budget
- Backup storage growing exponentially
- Old backups not deleted

**Solutions:**

1. **Implement lifecycle policies:**
   ```bash
   # Auto-delete old backups
   aws s3api put-bucket-lifecycle-configuration \
     --bucket loki-backups \
     --lifecycle-configuration '{
       "Rules": [{
         "Id": "delete-old-backups",
         "Status": "Enabled",
         "Expiration": {"Days": 30}
       }]
     }'
   ```

2. **Use compression:**
   ```bash
   # Compress backups with higher ratio
   tar czf - /backup/loki | gzip -9 > loki-backup.tar.gz
   ```

3. **Move to cheaper storage class:**
   ```bash
   # Transition to Glacier
   aws s3 sync s3://loki-backups/old s3://loki-backups/archive \
     --storage-class GLACIER
   ```

---

## Related Documentation

- [Loki Upgrade Guide](loki-upgrade-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/loki/README.md)
- [Loki Makefile](../make/ops/loki.mk)

---

**Last Updated:** 2025-11-27
**Chart Version:** 0.3.0
**Loki Version:** 3.6.1
