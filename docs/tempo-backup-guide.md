# Tempo Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for Tempo deployed via the Helm chart.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Configuration Backup](#1-configuration-backup)
  - [2. Trace Data Backup](#2-trace-data-backup)
  - [3. WAL Backup](#3-wal-backup)
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

Tempo backup strategy depends on storage backend:

| Storage Type | Backup Strategy | Complexity | Data Loss Risk |
|-------------|----------------|-----------|---------------|
| **Local Filesystem** | ConfigMap + PVC snapshot | Medium | Low (1 hour RPO) |
| **S3/MinIO** | ConfigMap + S3 bucket snapshot | Low | Very Low (continuous) |

### Key Backup Components

1. **Configuration** - Tempo YAML config, receiver settings, retention policies
2. **Trace Data** - Blocks (compressed trace data stored in /var/tempo/traces)
3. **WAL** - Write-Ahead Log (incoming traces before flush)
4. **PVC** - Persistent volume data (local storage mode only)

### RTO/RPO Summary

| Component | RTO (Recovery Time) | RPO (Recovery Point) | Backup Frequency |
|-----------|-------------------|---------------------|-----------------|
| Configuration | < 5 minutes | 0 | Daily or before changes |
| Trace Data (local) | < 1 hour | 1 hour | Hourly |
| Trace Data (S3) | < 10 minutes | 0 | Continuous (S3 versioning) |
| WAL | < 30 minutes | 10 minutes | Every 10 minutes |
| PVC Snapshot | < 2 hours | 24 hours | Daily |

---

## Backup Strategy

### Architecture Overview

```
+---------------------------------------------------------------------+
|                    Tempo Backup Components                           |
+---------------------------------------------------------------------+
|                                                                      |
|  +----------------+  +----------------+  +----------------+          |
|  | ConfigMap      |  | Trace Blocks   |  | WAL Files      |          |
|  | (tempo.yaml)   |  | (/var/tempo/   |  | (/var/tempo/   |          |
|  |                |  |  traces/)      |  |  wal/)         |          |
|  +-------+--------+  +-------+--------+  +-------+--------+          |
|          |                   |                   |                   |
|          +-------------------+-------------------+                   |
|                              |                                       |
|                              v                                       |
|  +----------------------------------------------------------+       |
|  |         Backup Storage (S3/MinIO)                        |       |
|  |  - /backups/tempo/config/                                |       |
|  |  - /backups/tempo/blocks/                                |       |
|  |  - /backups/tempo/wal/                                   |       |
|  |  - /backups/tempo/pvc-snapshots/                         |       |
|  +----------------------------------------------------------+       |
|                                                                      |
+---------------------------------------------------------------------+
```

### Tempo Data Flow

```
+-------------------------------------------------------------------+
|                     Tempo Trace Data Flow                          |
+-------------------------------------------------------------------+
|                                                                    |
|  Incoming Traces                                                   |
|       |                                                            |
|       v                                                            |
|  +----------+     +----------+     +------------+     +----------+ |
|  | Receiver |---->| Ingester |---->| Compactor  |---->| Backend  | |
|  | (OTLP/   |     | (WAL)    |     | (Blocks)   |     | (S3 or   | |
|  |  Jaeger/ |     |          |     |            |     |  Local)  | |
|  |  Zipkin) |     |          |     |            |     |          | |
|  +----------+     +-----+----+     +-----+------+     +-----+----+ |
|                         |                |                  |      |
|                         v                v                  v      |
|                   /var/tempo/wal  /var/tempo/traces   S3 Bucket    |
|                   (Incoming)      (Compacted)         or Local     |
|                                                                    |
+-------------------------------------------------------------------+
```

### Storage-Specific Strategies

#### Local Filesystem Storage

**Components to backup:**
1. Configuration (ConfigMap)
2. Trace blocks (/var/tempo/traces directory)
3. WAL files (/var/tempo/wal directory)

**Backup method:**
- ConfigMap export via kubectl
- PVC snapshot using VolumeSnapshot API
- Data extraction via kubectl cp or tar

**Recovery method:**
- ConfigMap restore via kubectl apply
- PVC restore from snapshot
- Data restoration via kubectl cp

#### S3/MinIO Storage

**Components to backup:**
1. Configuration (ConfigMap + S3 credentials Secret)
2. S3 bucket data (trace blocks) - handled by S3 versioning
3. Local WAL files (temporary, before flush)

**Backup method:**
- ConfigMap + Secret export
- S3 bucket versioning/replication
- Cross-region replication for disaster recovery

**Recovery method:**
- ConfigMap + Secret restore
- S3 data recovery via versioning or replication
- WAL recovery from local backup

---

## Backup Components

### 1. Configuration Backup

Configuration includes Tempo YAML, receiver settings, compactor settings, and storage configuration.

#### Backup Configuration

```bash
# Backup ConfigMap using Makefile
make -f make/ops/tempo.mk tempo-backup-config

# Or manually export ConfigMap
kubectl get configmap -n default tempo -o yaml > tempo-config-backup.yaml

# Backup with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
kubectl get configmap -n default tempo -o yaml > tempo-config-$TIMESTAMP.yaml
```

#### What's Included in Configuration

- `tempo.yaml` - Main Tempo configuration containing:
  - `server` - HTTP server settings (port 3200)
  - `distributor.receivers` - OTLP/Jaeger/Zipkin receiver config
  - `ingester` - Trace idle time, block duration settings
  - `compactor` - Block retention, compaction window
  - `storage.trace` - Backend configuration (local or S3)
  - `query_frontend` - Search settings

#### S3 Credentials Backup

If using S3/MinIO storage, also backup the credentials Secret:

```bash
# Backup S3 credentials
kubectl get secret -n default tempo-secret -o yaml > tempo-secret-backup.yaml

# Backup with encryption using GPG
kubectl get secret -n default tempo-secret -o yaml | \
  gpg --encrypt --recipient your@email.com > tempo-secret-backup.yaml.gpg

# Backup with symmetric encryption
kubectl get secret -n default tempo-secret -o yaml | \
  gpg --symmetric --cipher-algo AES256 > tempo-secret-backup.yaml.gpg
```

#### Storage Requirements

- Size: ~20-100 KB
- Retention: 90 days recommended
- Backup frequency: Daily or before any configuration changes

---

### 2. Trace Data Backup

Trace data (blocks) contain compressed trace spans organized by time. These are the actual trace data that applications send to Tempo.

#### Understanding Tempo Blocks

Tempo stores traces in blocks, which are:
- Compressed trace data organized by time
- Created when WAL is flushed
- Managed by the compactor for retention and optimization
- Located at `/var/tempo/traces` (local) or S3 bucket

#### Filesystem Storage Backup

**Method 1: PVC Snapshot (Recommended)**

PVC snapshots are the fastest and most consistent way to backup data:

```bash
# Create PVC snapshot using Makefile
make -f make/ops/tempo.mk tempo-backup-pvc-snapshot

# Or manually create VolumeSnapshot
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: tempo-data-snapshot-$TIMESTAMP
  namespace: default
  labels:
    app.kubernetes.io/name: tempo
    backup-type: scheduled
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: tempo
EOF

# Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/tempo-data-snapshot-$TIMESTAMP -n default --timeout=300s
```

**Method 2: Data Extraction via tar**

For environments without CSI snapshot support:

```bash
# Extract trace blocks directory
make -f make/ops/tempo.mk tempo-backup-data

# Or manually extract
POD_NAME=tempo-0
NAMESPACE=default
BACKUP_DIR=./backups/tempo/data/$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

# Flush WAL before backup for consistency
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush || true
sleep 10

# Extract trace data
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  tar czf - /var/tempo/traces | tar xzf - -C $BACKUP_DIR

echo "Backup complete: $BACKUP_DIR"
ls -lh $BACKUP_DIR
```

#### S3 Storage Backup

For S3/MinIO storage, leverage native S3 features:

**Enable S3 Versioning**

```bash
# Enable versioning for point-in-time recovery
aws s3api put-bucket-versioning \
  --bucket tempo-traces \
  --versioning-configuration Status=Enabled

# Verify versioning is enabled
aws s3api get-bucket-versioning --bucket tempo-traces
```

**Configure Lifecycle Policy**

```bash
# Create lifecycle policy for cost optimization
cat > tempo-lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "Id": "tempo-traces-lifecycle",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
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
  --bucket tempo-traces \
  --lifecycle-configuration file://tempo-lifecycle-policy.json
```

**S3 Bucket Sync/Snapshot**

```bash
# Sync S3 bucket to backup location
aws s3 sync s3://tempo-traces s3://tempo-backups/traces/$(date +%Y%m%d-%H%M%S) \
  --storage-class GLACIER_IR

# Cross-region replication for disaster recovery
# Configure via AWS Console or CloudFormation
```

**MinIO Bucket Backup**

```bash
# Using MinIO Client (mc)
mc alias set myminio http://minio:9000 admin password
mc alias set backup-minio http://backup-minio:9000 admin password

# Mirror bucket to backup location
mc mirror myminio/tempo-traces backup-minio/tempo-traces

# Or copy with timestamp
mc cp --recursive myminio/tempo-traces myminio/tempo-backups/$(date +%Y%m%d-%H%M%S)/
```

#### Storage Requirements

| Storage Type | Data Size | Retention | Backup Frequency |
|-------------|-----------|----------|-----------------|
| Local Filesystem | 1-50 GB | 7 days | Hourly |
| S3/MinIO | Unlimited | 7-30 days | Continuous (versioning) |

---

### 3. WAL Backup

Write-Ahead Log (WAL) contains incoming traces before they are flushed to blocks. This is critical for preventing data loss during failures.

#### Understanding WAL

- **Location:** `/var/tempo/wal`
- **Purpose:** Stores incoming traces before flush to blocks
- **Flush interval:** Configurable via `ingester.trace_idle_period` (default: 10s)
- **Max block duration:** `ingester.max_block_duration` (default: 30m)
- **Behavior:** Automatically replayed on Tempo startup

#### Backup WAL

```bash
# Flush WAL to storage first (recommended before backup)
make -f make/ops/tempo.mk tempo-flush

# Wait for flush to complete
sleep 10

# Backup WAL files
make -f make/ops/tempo.mk tempo-backup-wal

# Or manually backup
POD_NAME=tempo-0
NAMESPACE=default
BACKUP_DIR=./backups/tempo/wal/$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  tar czf - /var/tempo/wal | tar xzf - -C $BACKUP_DIR

echo "WAL backup complete: $BACKUP_DIR"
```

#### WAL Recovery Considerations

WAL files are automatically replayed on Tempo startup. If WAL is corrupted:

```bash
# Option 1: Clear WAL and restart (loses unflushed traces)
kubectl exec -n default tempo-0 -c tempo -- rm -rf /var/tempo/wal/*
kubectl rollout restart statefulset tempo -n default

# Option 2: Restore WAL from backup
kubectl scale statefulset tempo -n default --replicas=0
kubectl wait --for=delete pod -n default -l app.kubernetes.io/name=tempo --timeout=120s

# Copy WAL backup
kubectl cp $BACKUP_DIR/wal tempo-0:/var/tempo/ -c tempo -n default

# Restart Tempo
kubectl scale statefulset tempo -n default --replicas=1
```

#### Storage Requirements

- Size: 100 MB - 5 GB (depending on trace volume)
- Retention: 7 days
- Backup frequency: Every 10 minutes (matches trace_idle_period)

---

### 4. PVC Snapshot Backup

Complete persistent volume backup using Kubernetes VolumeSnapshot API. This is the most reliable method for local storage mode.

#### Prerequisites

- CSI driver with snapshot support installed
- VolumeSnapshotClass configured
- Sufficient storage for snapshots

#### Create PVC Snapshot

```bash
# Check VolumeSnapshotClass availability
kubectl get volumesnapshotclass

# Create snapshot
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: tempo-pvc-snapshot-$TIMESTAMP
  namespace: default
  labels:
    app.kubernetes.io/name: tempo
    backup-date: "$(date +%Y-%m-%d)"
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: tempo
EOF
```

#### Verify Snapshot

```bash
# Check snapshot status
kubectl get volumesnapshot -n default tempo-pvc-snapshot-$TIMESTAMP

# Get detailed status
kubectl describe volumesnapshot -n default tempo-pvc-snapshot-$TIMESTAMP

# Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/tempo-pvc-snapshot-$TIMESTAMP -n default --timeout=300s
```

#### Restore from PVC Snapshot

```bash
# Create new PVC from snapshot
TIMESTAMP=20251201-120000  # Use actual snapshot timestamp
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tempo-restored
  namespace: default
spec:
  storageClassName: your-storage-class
  dataSource:
    name: tempo-pvc-snapshot-$TIMESTAMP
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Update Tempo deployment to use restored PVC
# (requires Helm values update or manual deployment edit)
```

#### Storage Requirements

- Size: Same as PVC (10-50 GB typical)
- Retention: 7-14 days
- Backup frequency: Daily

---

## Backup Procedures

### Full Backup

Complete backup of all Tempo components. Use this for disaster recovery preparation.

#### Automated Full Backup

```bash
# Full backup using Makefile
make -f make/ops/tempo.mk tempo-backup-all
```

#### Manual Full Backup Script

```bash
#!/bin/bash
# full-backup.sh - Complete Tempo backup
# Usage: NAMESPACE=default S3_BUCKET=my-backups ./full-backup.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-tempo-0}"
CONTAINER_NAME="${CONTAINER_NAME:-tempo}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT="./backups/tempo"
BACKUP_DIR="$BACKUP_ROOT/full/$TIMESTAMP"

mkdir -p $BACKUP_DIR/{config,data,wal,metadata}

echo "=== Tempo Full Backup Started: $TIMESTAMP ==="

# 1. Flush WAL to storage
echo "[1/6] Flushing WAL to storage..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- -X POST http://localhost:3200/flush || echo "Flush endpoint not available"
sleep 10

# 2. Backup configuration
echo "[2/6] Backing up configuration..."
kubectl get configmap -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/config/configmap.yaml
kubectl get secret -n $NAMESPACE tempo-secret -o yaml > $BACKUP_DIR/config/secret.yaml 2>/dev/null || \
  echo "No S3 secret found (local storage mode)"

# 3. Backup Kubernetes metadata
echo "[3/6] Backing up Kubernetes metadata..."
kubectl get statefulset -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/metadata/statefulset.yaml 2>/dev/null || \
kubectl get deployment -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/metadata/deployment.yaml 2>/dev/null
kubectl get service -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/metadata/service.yaml
kubectl get pvc -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/metadata/pvc.yaml 2>/dev/null || \
  echo "No PVC found (S3 storage mode)"

# 4. Backup trace data (blocks)
echo "[4/6] Backing up trace data..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  tar czf - /var/tempo/traces 2>/dev/null | \
  cat > $BACKUP_DIR/data/traces.tar.gz || echo "Traces backup skipped (empty or S3 mode)"

# 5. Backup WAL
echo "[5/6] Backing up WAL..."
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  tar czf - /var/tempo/wal 2>/dev/null | \
  cat > $BACKUP_DIR/wal/wal.tar.gz || echo "WAL backup skipped (empty)"

# 6. Create backup manifest
echo "[6/6] Creating backup manifest..."
TEMPO_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  /tempo --version 2>/dev/null | head -1 || echo "unknown")
STORAGE_TYPE=$(kubectl get configmap tempo -n $NAMESPACE -o jsonpath='{.data.tempo\.yaml}' | \
  grep -A5 "storage:" | grep "backend:" | awk '{print $2}' || echo "unknown")

cat > $BACKUP_DIR/backup-manifest.yaml <<EOF
backup:
  timestamp: $TIMESTAMP
  namespace: $NAMESPACE
  pod: $POD_NAME
  components:
    - config
    - data
    - wal
    - metadata
  tempo_version: $TEMPO_VERSION
  storage_type: $STORAGE_TYPE
  backup_size: $(du -sh $BACKUP_DIR | awk '{print $1}')
EOF

echo ""
echo "=== Tempo Full Backup Complete ==="
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Backup contents:"
du -sh $BACKUP_DIR/*

# Optional: Upload to S3/MinIO
if [ -n "$S3_BUCKET" ]; then
  echo ""
  echo "Uploading to S3..."
  tar czf - -C $BACKUP_ROOT/full $TIMESTAMP | \
    aws s3 cp - s3://$S3_BUCKET/tempo/full/tempo-backup-$TIMESTAMP.tar.gz
  echo "Upload complete: s3://$S3_BUCKET/tempo/full/tempo-backup-$TIMESTAMP.tar.gz"
fi
```

### Configuration-Only Backup

Lightweight backup for configuration changes. Use before making any configuration updates.

```bash
# Automated config backup
make -f make/ops/tempo.mk tempo-backup-config

# Or manually
NAMESPACE=default
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/tempo/config/$TIMESTAMP

mkdir -p $BACKUP_DIR

kubectl get configmap -n $NAMESPACE tempo -o yaml > $BACKUP_DIR/configmap.yaml
kubectl get secret -n $NAMESPACE tempo-secret -o yaml > $BACKUP_DIR/secret.yaml 2>/dev/null || true

echo "Config backup complete: $BACKUP_DIR"
ls -la $BACKUP_DIR
```

### Data-Only Backup

Backup trace data and WAL without configuration. Use for scheduled data backups.

```bash
# Automated data backup
make -f make/ops/tempo.mk tempo-backup-data

# Or manually
NAMESPACE=default
POD_NAME=tempo-0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/tempo/data/$TIMESTAMP

mkdir -p $BACKUP_DIR

# Flush WAL first for consistency
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  wget -qO- -X POST http://localhost:3200/flush || true
sleep 10

# Backup traces
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  tar czf - /var/tempo/traces 2>/dev/null | cat > $BACKUP_DIR/traces.tar.gz

# Backup WAL
kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- \
  tar czf - /var/tempo/wal 2>/dev/null | cat > $BACKUP_DIR/wal.tar.gz

echo "Data backup complete: $BACKUP_DIR"
ls -lh $BACKUP_DIR
```

---

## Recovery Procedures

### Full Recovery

Complete restoration from full backup. Use for disaster recovery scenarios.

#### Automated Full Recovery

```bash
# Restore from backup using Makefile
make -f make/ops/tempo.mk tempo-restore-all BACKUP_FILE=/path/to/backup.tar.gz
```

#### Manual Full Recovery Script

```bash
#!/bin/bash
# full-restore.sh - Complete Tempo restoration
# Usage: ./full-restore.sh /path/to/backup-directory

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <backup-directory>"
  exit 1
fi

BACKUP_DIR="$1"
NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-tempo-0}"
CONTAINER_NAME="${CONTAINER_NAME:-tempo}"

echo "=== Tempo Full Recovery Started ==="
echo "Backup source: $BACKUP_DIR"

# 1. Verify backup integrity
if [ ! -f "$BACKUP_DIR/backup-manifest.yaml" ]; then
  echo "ERROR: Invalid backup directory (no manifest found)"
  exit 1
fi

echo "Backup manifest:"
cat $BACKUP_DIR/backup-manifest.yaml

# 2. Scale down Tempo
echo "[1/7] Scaling down Tempo..."
kubectl scale statefulset tempo -n $NAMESPACE --replicas=0 2>/dev/null || \
kubectl scale deployment tempo -n $NAMESPACE --replicas=0 2>/dev/null

kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=tempo --timeout=120s || true

# 3. Restore configuration
echo "[2/7] Restoring configuration..."
if [ -f "$BACKUP_DIR/config/configmap.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/configmap.yaml
  echo "  ConfigMap restored"
fi

if [ -f "$BACKUP_DIR/config/secret.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/secret.yaml
  echo "  Secret restored"
fi

# 4. Scale up to restore data
echo "[3/7] Scaling up Tempo..."
kubectl scale statefulset tempo -n $NAMESPACE --replicas=1 2>/dev/null || \
kubectl scale deployment tempo -n $NAMESPACE --replicas=1 2>/dev/null

kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# 5. Restore trace data
echo "[4/7] Restoring trace data..."
if [ -f "$BACKUP_DIR/data/traces.tar.gz" ]; then
  echo "  Clearing existing traces..."
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm -rf /var/tempo/traces/*
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- mkdir -p /var/tempo/traces

  echo "  Restoring traces..."
  kubectl cp $BACKUP_DIR/data/traces.tar.gz $NAMESPACE/$POD_NAME:/tmp/traces.tar.gz -c $CONTAINER_NAME
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- tar xzf /tmp/traces.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm /tmp/traces.tar.gz
  echo "  Traces restored"
fi

# 6. Restore WAL
echo "[5/7] Restoring WAL..."
if [ -f "$BACKUP_DIR/wal/wal.tar.gz" ]; then
  echo "  Clearing existing WAL..."
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm -rf /var/tempo/wal/*
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- mkdir -p /var/tempo/wal

  echo "  Restoring WAL..."
  kubectl cp $BACKUP_DIR/wal/wal.tar.gz $NAMESPACE/$POD_NAME:/tmp/wal.tar.gz -c $CONTAINER_NAME
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- tar xzf /tmp/wal.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- rm /tmp/wal.tar.gz
  echo "  WAL restored"
fi

# 7. Restart Tempo to apply changes
echo "[6/7] Restarting Tempo..."
kubectl rollout restart statefulset tempo -n $NAMESPACE 2>/dev/null || \
kubectl rollout restart deployment tempo -n $NAMESPACE 2>/dev/null

kubectl rollout status statefulset tempo -n $NAMESPACE 2>/dev/null || \
kubectl rollout status deployment tempo -n $NAMESPACE 2>/dev/null

# 8. Verify recovery
echo "[7/7] Verifying recovery..."
kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

echo ""
echo "=== Tempo Full Recovery Complete ==="
echo ""
echo "Verification:"
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- \
  wget -qO- http://localhost:3200/ready && echo "Tempo is ready!"

echo ""
echo "Storage contents:"
kubectl exec -n $NAMESPACE $POD_NAME -c $CONTAINER_NAME -- ls -lh /var/tempo

echo ""
echo "Test query: make -f make/ops/tempo.mk tempo-search SERVICE=myapp"
```

### Configuration Recovery

Restore only configuration without data. Use for configuration rollback.

```bash
# Automated config restore
make -f make/ops/tempo.mk tempo-restore-config BACKUP_FILE=/path/to/config-backup.tar.gz

# Or manually
BACKUP_DIR=/path/to/config/backup
NAMESPACE=default

# Apply ConfigMap
kubectl apply -f $BACKUP_DIR/configmap.yaml

# Apply Secret (if exists)
kubectl apply -f $BACKUP_DIR/secret.yaml 2>/dev/null || true

# Restart Tempo to apply new configuration
kubectl rollout restart statefulset tempo -n $NAMESPACE 2>/dev/null || \
kubectl rollout restart deployment tempo -n $NAMESPACE

# Wait for rollout to complete
kubectl rollout status statefulset tempo -n $NAMESPACE 2>/dev/null || \
kubectl rollout status deployment tempo -n $NAMESPACE
```

### Data Recovery

Restore trace data and WAL without configuration changes.

```bash
# Automated data restore
make -f make/ops/tempo.mk tempo-restore-data BACKUP_FILE=/path/to/data-backup.tar.gz

# Or manually
BACKUP_DIR=/path/to/data/backup
NAMESPACE=default
POD_NAME=tempo-0

# Scale down Tempo
kubectl scale statefulset tempo -n $NAMESPACE --replicas=0 2>/dev/null || \
kubectl scale deployment tempo -n $NAMESPACE --replicas=0

kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=tempo --timeout=120s || true

# Scale up
kubectl scale statefulset tempo -n $NAMESPACE --replicas=1 2>/dev/null || \
kubectl scale deployment tempo -n $NAMESPACE --replicas=1

kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# Restore traces
if [ -f "$BACKUP_DIR/traces.tar.gz" ]; then
  kubectl cp $BACKUP_DIR/traces.tar.gz $NAMESPACE/$POD_NAME:/tmp/traces.tar.gz -c tempo
  kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- tar xzf /tmp/traces.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- rm /tmp/traces.tar.gz
fi

# Restore WAL
if [ -f "$BACKUP_DIR/wal.tar.gz" ]; then
  kubectl cp $BACKUP_DIR/wal.tar.gz $NAMESPACE/$POD_NAME:/tmp/wal.tar.gz -c tempo
  kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- tar xzf /tmp/wal.tar.gz -C /
  kubectl exec -n $NAMESPACE $POD_NAME -c tempo -- rm /tmp/wal.tar.gz
fi

# Restart to reload data
kubectl rollout restart statefulset tempo -n $NAMESPACE 2>/dev/null || \
kubectl rollout restart deployment tempo -n $NAMESPACE
```

---

## Backup Automation

### CronJob for Scheduled Backups

Deploy this CronJob for automated backups every 6 hours:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tempo-backup
  namespace: default
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: tempo-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command: ["/bin/bash", "-c"]
            args:
            - |
              set -e
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_DIR=/backup/tempo/$TIMESTAMP
              mkdir -p $BACKUP_DIR/{config,data,wal}

              echo "Starting Tempo backup: $TIMESTAMP"

              # Flush WAL
              kubectl exec -n default tempo-0 -c tempo -- \
                wget -qO- -X POST http://localhost:3200/flush || true
              sleep 10

              # Backup config
              kubectl get configmap -n default tempo -o yaml > $BACKUP_DIR/config/configmap.yaml
              kubectl get secret -n default tempo-secret -o yaml > $BACKUP_DIR/config/secret.yaml 2>/dev/null || true

              # Backup traces
              kubectl exec -n default tempo-0 -c tempo -- \
                tar czf - /var/tempo/traces 2>/dev/null | \
                cat > $BACKUP_DIR/data/traces.tar.gz || true

              # Backup WAL
              kubectl exec -n default tempo-0 -c tempo -- \
                tar czf - /var/tempo/wal 2>/dev/null | \
                cat > $BACKUP_DIR/wal/wal.tar.gz || true

              # Upload to S3
              tar czf - -C /backup/tempo $TIMESTAMP | \
                aws s3 cp - s3://$S3_BUCKET/tempo/tempo-backup-$TIMESTAMP.tar.gz

              echo "Backup complete: s3://$S3_BUCKET/tempo/tempo-backup-$TIMESTAMP.tar.gz"
            env:
            - name: S3_BUCKET
              value: "my-backups"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: aws-credentials
                  key: access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: aws-credentials
                  key: secret-access-key
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
  name: tempo-backup
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tempo-backup
  namespace: default
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
  name: tempo-backup
  namespace: default
subjects:
- kind: ServiceAccount
  name: tempo-backup
  namespace: default
roleRef:
  kind: Role
  name: tempo-backup
  apiGroup: rbac.authorization.k8s.io
```

---

## Backup Verification

### Verify Backup Integrity

```bash
# Verify backup using Makefile
make -f make/ops/tempo.mk tempo-backup-verify BACKUP_FILE=/path/to/backup.tar.gz

# Or manually verify
BACKUP_DIR=/path/to/backup

echo "=== Tempo Backup Verification ==="

# Check manifest
[ -f "$BACKUP_DIR/backup-manifest.yaml" ] && echo "[OK] Manifest found" || echo "[FAIL] Manifest missing"

# Check config
[ -f "$BACKUP_DIR/config/configmap.yaml" ] && echo "[OK] ConfigMap found" || echo "[FAIL] ConfigMap missing"

# Check secret (optional for local storage)
[ -f "$BACKUP_DIR/config/secret.yaml" ] && echo "[OK] Secret found" || echo "[WARN] Secret missing (expected for local storage)"

# Check traces
if [ -f "$BACKUP_DIR/data/traces.tar.gz" ]; then
  SIZE=$(du -sh $BACKUP_DIR/data/traces.tar.gz | awk '{print $1}')
  echo "[OK] Traces found ($SIZE)"
else
  echo "[WARN] Traces missing (S3 mode or empty)"
fi

# Check WAL
if [ -f "$BACKUP_DIR/wal/wal.tar.gz" ]; then
  SIZE=$(du -sh $BACKUP_DIR/wal/wal.tar.gz | awk '{print $1}')
  echo "[OK] WAL found ($SIZE)"
else
  echo "[WARN] WAL missing (flushed or empty)"
fi

# Validate ConfigMap syntax
echo ""
echo "Validating ConfigMap..."
kubectl apply --dry-run=client -f $BACKUP_DIR/config/configmap.yaml && echo "[OK] ConfigMap is valid"
```

---

## RTO & RPO Targets

### Recovery Time Objective (RTO)

| Scenario | RTO Target | Steps Required |
|---------|-----------|----------------|
| Configuration only | < 5 minutes | ConfigMap apply + restart |
| Data restore (local) | < 1 hour | PVC snapshot restore + restart |
| Data restore (S3) | < 10 minutes | Config apply + S3 data available |
| Full restore | < 2 hours | All components restoration |

### Recovery Point Objective (RPO)

| Component | RPO Target | Backup Frequency | Maximum Data Loss |
|----------|-----------|-----------------|-------------------|
| Configuration | 0 | Before changes | None |
| Trace data (local) | 1 hour | Hourly | Max 1 hour traces |
| Trace data (S3) | 0 | Continuous | None (versioning) |
| WAL | 10 minutes | Every 10 minutes | Max 10 min unflushed |

### Recovery Scenario Matrix

| Scenario | RTO | RPO | Priority |
|----------|-----|-----|----------|
| Config corruption | 5 min | 0 | High |
| Single pod failure | 2 min | 0 | High (auto-recovery) |
| PVC data loss | 1 hour | 1 hour | Medium |
| S3 bucket deletion | 30 min | 0 | High |
| Complete cluster loss | 2 hours | 24 hours | Critical |
| WAL corruption | 30 min | 10 min | Medium |

---

## Best Practices

### Backup Strategy

1. **Use S3 storage for production** - Continuous backup via S3 versioning provides lower RTO/RPO
2. **Implement 3-2-1 backup rule** - 3 copies, 2 different storage types, 1 offsite
3. **Automate backups** - Use CronJob for scheduled backups, monitor success/failure
4. **Test restore procedures** - Monthly restore test to non-production environment

### Backup Retention

| Backup Type | Retention Period | Storage Location |
|------------|-----------------|-----------------|
| Hourly (data) | 7 days | S3 Standard |
| Daily (config) | 30 days | S3 Standard |
| Weekly (PVC) | 90 days | S3 Infrequent Access |
| Monthly (archive) | 1 year | S3 Glacier |

### Security

1. **Encrypt backups at rest** - Enable S3 server-side encryption (SSE-AES256)
2. **Restrict backup access** - Use IAM roles with least-privilege access
3. **Protect S3 credentials** - Encrypt secret backups with GPG
4. **Audit backup access** - Enable CloudTrail logging for S3 buckets

---

## Troubleshooting

### Issue 1: Backup Too Large

**Symptoms:** Backup exceeds storage quota, S3 upload times out, PVC snapshot fails

**Solutions:**
1. Reduce trace retention: `tempo.retention.days: 3`
2. Reduce sampling rate at application level (OpenTelemetry probabilistic sampler)
3. Use S3 lifecycle policies for automatic Glacier transition
4. Compress with higher ratio: `pigz -9` or `xz -9`

### Issue 2: WAL Corruption After Restore

**Symptoms:** Tempo crashes on startup, "WAL replay failed" errors, missing recent traces

**Solutions:**
1. Clear WAL: `kubectl exec tempo-0 -- rm -rf /var/tempo/wal/*` (loses unflushed traces)
2. Restore WAL from most recent backup
3. Check WAL integrity: `ls -la /var/tempo/wal/`

### Issue 3: S3 Backup Incomplete

**Symptoms:** Missing blocks in S3, queries return partial results, S3 sync fails

**Solutions:**
1. Check S3 permissions and credentials
2. Force flush: `make -f make/ops/tempo.mk tempo-flush`
3. Resync bucket: `aws s3 sync s3://tempo-traces s3://tempo-backups/`
4. Check compactor status: `wget -qO- http://localhost:3200/compactor/ring`

### Issue 4: Version Mismatch After Restore

**Symptoms:** Tempo won't start, config validation fails, "incompatible version" errors

**Solutions:**
1. Check versions in backup manifest vs current deployment
2. Match Tempo version: `helm upgrade tempo sb-charts/tempo --set image.tag=2.9.0`
3. Validate config: `/tempo -config.file=/etc/tempo/tempo.yaml -config.verify`

### Issue 5: PVC Snapshot Fails

**Symptoms:** VolumeSnapshot stuck in Pending, CSI driver errors, snapshot timeout

**Solutions:**
1. Check CSI driver: `kubectl get csidrivers`, `kubectl get volumesnapshotclass`
2. Verify VolumeSnapshotClass exists and is properly configured
3. Fallback to data extraction: `make -f make/ops/tempo.mk tempo-backup-data`

### Issue 6: Traces Not Queryable After Restore

**Symptoms:** Tempo running but traces not found, "trace not found" errors, empty search

**Solutions:**
1. Verify blocks: `kubectl exec tempo-0 -- ls -la /var/tempo/traces/`
2. Check compactor status
3. Force reload: `kubectl rollout restart statefulset tempo`
4. Verify retention settings match backup timeframe

### Issue 7: High Backup Storage Costs

**Symptoms:** S3 costs exceed budget, backup storage growing exponentially

**Solutions:**
1. Implement lifecycle policies for auto-deletion of old backups
2. Use higher compression (xz -9)
3. Move old backups to Glacier storage class
4. Reduce backup frequency if RPO allows

### Issue 8: Receiver Protocol Mismatch

**Symptoms:** Applications can't send traces after restore, connection refused

**Solutions:**
1. Verify receiver config: `grep -A20 "receivers" tempo.yaml`
2. Check service ports: `kubectl get svc tempo -o yaml`
3. Test endpoints with grpcurl (OTLP gRPC) or curl (OTLP HTTP)

---

## Related Documentation

- [Tempo Upgrade Guide](tempo-upgrade-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/tempo/README.md)
- [Tempo Makefile](../make/ops/tempo.mk)
- [Observability Stack Guide](observability-stack-guide.md)

---

**Last Updated:** 2025-12-01
**Chart Version:** 0.3.0
**Tempo Version:** 2.9.0
