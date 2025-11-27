# Prometheus Backup and Recovery Guide

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Automation](#automation)
7. [Testing & Validation](#testing-validation)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive procedures for backing up and recovering Prometheus deployments managed by this Helm chart. Prometheus stores critical time-series metrics data, scrape configurations, recording rules, and alerting rules that require regular backup for disaster recovery.

### Backup Scope

This chart uses a **Makefile-driven backup approach** (no automated CronJobs) for maximum flexibility and control. All backup operations are manual or scheduled externally.

### RTO/RPO Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **RTO** (Recovery Time Objective) | < 1 hour | Time to restore Prometheus service |
| **RPO** (Recovery Point Objective) | 1 hour | Maximum acceptable data loss (hourly snapshots) |
| **Backup Frequency** | Hourly (TSDB), Daily (config) | TSDB snapshots hourly, configuration daily |
| **Retention** | 30 days (TSDB), 90 days (config) | Balance between storage cost and recovery needs |

---

## Backup Strategy

### Recommended Backup Strategy

The recommended backup strategy combines **four approaches** for comprehensive data protection:

1. **TSDB snapshots** - Time-series database data (metrics)
2. **Configuration backups** - Prometheus configuration, scrape configs
3. **Rules backups** - Recording rules and alerting rules
4. **PVC snapshots** - Disaster recovery with Kubernetes VolumeSnapshot API

### Backup Decision Matrix

| Scenario | TSDB Snapshot | Configuration | Rules | PVC Snapshot |
|----------|---------------|---------------|-------|--------------|
| **Regular Backups** | ✅ Hourly | ✅ Daily | ✅ Daily | ⚠️ Weekly |
| **Before Upgrades** | ✅ Required | ✅ Required | ✅ Required | ⚠️ Recommended |
| **Disaster Recovery** | ✅ Primary | ✅ Primary | ✅ Primary | ✅ Fallback |
| **Point-in-Time Recovery** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Cross-Cluster Migration** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |

### Backup Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus Backup Flow                    │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐   Snapshot    ┌──────────────────┐
│              │──────────────>│ TSDB Snapshots   │
│  Prometheus  │               │ (hourly)         │
│   Server     │   ConfigMap   ├──────────────────┤
│              │──────────────>│ Configuration    │
│  (StatefulSet)               │ (daily)          │
│              │   API Export  ├──────────────────┤
│              │──────────────>│ Rules            │
└──────────────┘               │ (daily)          │
       │                       └──────────────────┘
       │                                │
       │  PVC Snapshot                  │ Copy to
       │  (weekly)                      │ S3/MinIO
       ▼                                ▼
┌──────────────┐              ┌──────────────────┐
│ VolumeSnapshot│─────────────>│ Object Storage   │
│ (CSI)        │   Archive     │ (S3/MinIO)       │
└──────────────┘              └──────────────────┘
```

---

## Backup Components

### 1. TSDB Snapshots

**What**: Time-series database blocks containing metrics data

**Why Critical**: Contains all historical metrics data

**Backup Method**:
- Use Prometheus Admin API `/api/v1/admin/tsdb/snapshot`
- Creates a snapshot in `/prometheus/snapshots/` directory
- Requires `--web.enable-admin-api` flag enabled

**Size**: Varies (typically 100MB - 10GB depending on retention and cardinality)

**Retention Recommendation**: 30 days

### 2. Configuration Backups

**What**: Prometheus configuration file and scrape configurations

**Why Critical**: Defines how Prometheus collects metrics

**Backup Method**:
- Export ConfigMap containing `prometheus.yml`
- Export any additional scrape config files
- Includes service discovery configurations

**Size**: < 1MB

**Retention Recommendation**: 90 days

### 3. Rules Backups

**What**: Recording rules and alerting rules

**Why Critical**: Defines derived metrics and alert conditions

**Backup Method**:
- Export ConfigMap containing rule files
- Export PrometheusRule CRDs if using Prometheus Operator pattern
- Includes both recording and alerting rules

**Size**: < 500KB

**Retention Recommendation**: 90 days

### 4. PVC Snapshots

**What**: Complete persistent volume snapshot

**Why Critical**: Disaster recovery fallback, includes all data

**Backup Method**:
- Use Kubernetes VolumeSnapshot API
- Creates CSI-based storage snapshot
- Requires CSI driver support

**Size**: Same as PVC size (typically 10GB - 100GB)

**Retention Recommendation**: 7-14 days

---

## Backup Procedures

### Prerequisites

1. **Admin API Enabled**:
   ```yaml
   # values.yaml
   extraArgs:
     - --web.enable-admin-api
     - --web.enable-lifecycle
   ```

2. **Sufficient Storage**:
   - TSDB snapshots require additional storage (1.5x current data size)
   - S3/MinIO bucket for offsite backups

3. **Required Tools**:
   - kubectl with cluster access
   - aws-cli or mc (MinIO client) for S3 uploads
   - jq for JSON parsing

### 1. TSDB Snapshot Backup

#### Manual TSDB Snapshot

```bash
# Create TSDB snapshot
make -f make/ops/prometheus.mk prom-tsdb-snapshot

# Output example:
# {"status":"success","data":{"name":"20231127T120000Z-1a2b3c4d"}}
```

#### Extract Snapshot from Pod

```bash
#!/bin/bash
# snapshot-backup.sh

NAMESPACE="monitoring"
POD_NAME="prometheus-0"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./backups/prometheus/tsdb"
SNAPSHOT_NAME=""

# 1. Create snapshot
echo "Creating TSDB snapshot..."
SNAPSHOT_JSON=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot)

SNAPSHOT_NAME=$(echo $SNAPSHOT_JSON | jq -r '.data.name')

if [ -z "$SNAPSHOT_NAME" ] || [ "$SNAPSHOT_NAME" == "null" ]; then
  echo "Error: Failed to create snapshot"
  exit 1
fi

echo "Snapshot created: $SNAPSHOT_NAME"

# 2. Copy snapshot from pod
echo "Copying snapshot from pod..."
mkdir -p $BACKUP_DIR/$TIMESTAMP
kubectl cp $NAMESPACE/$POD_NAME:/prometheus/snapshots/$SNAPSHOT_NAME \
  $BACKUP_DIR/$TIMESTAMP/snapshot -c prometheus

# 3. Create metadata file
cat > $BACKUP_DIR/$TIMESTAMP/metadata.json <<EOF
{
  "snapshot_name": "$SNAPSHOT_NAME",
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "pod_name": "$POD_NAME",
  "backup_date": "$(date -Iseconds)"
}
EOF

# 4. Compress snapshot
echo "Compressing snapshot..."
cd $BACKUP_DIR
tar -czf $TIMESTAMP.tar.gz $TIMESTAMP/
rm -rf $TIMESTAMP/

echo "Backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# 5. Upload to S3/MinIO (optional)
if [ -n "$S3_BUCKET" ]; then
  echo "Uploading to S3: $S3_BUCKET"
  aws s3 cp $TIMESTAMP.tar.gz s3://$S3_BUCKET/prometheus/tsdb/$TIMESTAMP.tar.gz
  # or with MinIO client:
  # mc cp $TIMESTAMP.tar.gz minio/prometheus-backups/tsdb/$TIMESTAMP.tar.gz
fi

# 6. Clean up old snapshots in pod
echo "Cleaning up snapshot in pod..."
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  rm -rf /prometheus/snapshots/$SNAPSHOT_NAME
```

### 2. Configuration Backup

#### Backup Prometheus Configuration

```bash
#!/bin/bash
# config-backup.sh

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./backups/prometheus/config"

mkdir -p $BACKUP_DIR/$TIMESTAMP

# 1. Backup main ConfigMap
echo "Backing up Prometheus ConfigMap..."
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-server -o yaml > \
  $BACKUP_DIR/$TIMESTAMP/configmap.yaml

# 2. Backup current runtime config (from pod)
echo "Backing up runtime configuration..."
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  cat /etc/prometheus/prometheus.yml > $BACKUP_DIR/$TIMESTAMP/prometheus.yml

# 3. Validate configuration
echo "Validating configuration..."
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  promtool check config /etc/prometheus/prometheus.yml > \
  $BACKUP_DIR/$TIMESTAMP/validation.txt 2>&1

# 4. Create metadata
cat > $BACKUP_DIR/$TIMESTAMP/metadata.json <<EOF
{
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "release_name": "$RELEASE_NAME",
  "backup_date": "$(date -Iseconds)",
  "config_version": "$(kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-server -o jsonpath='{.metadata.resourceVersion}')"
}
EOF

# 5. Compress backup
cd $BACKUP_DIR
tar -czf $TIMESTAMP.tar.gz $TIMESTAMP/
rm -rf $TIMESTAMP/

echo "Configuration backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# 6. Upload to S3/MinIO (optional)
if [ -n "$S3_BUCKET" ]; then
  aws s3 cp $TIMESTAMP.tar.gz s3://$S3_BUCKET/prometheus/config/$TIMESTAMP.tar.gz
fi
```

### 3. Rules Backup

#### Backup Recording and Alerting Rules

```bash
#!/bin/bash
# rules-backup.sh

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./backups/prometheus/rules"

mkdir -p $BACKUP_DIR/$TIMESTAMP

# 1. Backup rules ConfigMap (if exists)
echo "Backing up Prometheus rules..."
if kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-rules &>/dev/null; then
  kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-rules -o yaml > \
    $BACKUP_DIR/$TIMESTAMP/rules-configmap.yaml
fi

# 2. Backup PrometheusRule CRDs (if using Prometheus Operator pattern)
echo "Backing up PrometheusRule CRDs..."
kubectl get prometheusrules -n $NAMESPACE -o yaml > \
  $BACKUP_DIR/$TIMESTAMP/prometheus-rules-crds.yaml 2>/dev/null || \
  echo "No PrometheusRule CRDs found"

# 3. Export current loaded rules via API
echo "Exporting loaded rules via API..."
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/rules > \
  $BACKUP_DIR/$TIMESTAMP/loaded-rules.json

# 4. Create metadata
cat > $BACKUP_DIR/$TIMESTAMP/metadata.json <<EOF
{
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "release_name": "$RELEASE_NAME",
  "backup_date": "$(date -Iseconds)"
}
EOF

# 5. Compress backup
cd $BACKUP_DIR
tar -czf $TIMESTAMP.tar.gz $TIMESTAMP/
rm -rf $TIMESTAMP/

echo "Rules backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# 6. Upload to S3/MinIO (optional)
if [ -n "$S3_BUCKET" ]; then
  aws s3 cp $TIMESTAMP.tar.gz s3://$S3_BUCKET/prometheus/rules/$TIMESTAMP.tar.gz
fi
```

### 4. PVC Snapshot Backup

#### Create Volume Snapshot

```yaml
# pvc-snapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: prometheus-snapshot-20231127
  namespace: monitoring
spec:
  volumeSnapshotClassName: csi-snapclass  # Your CSI snapshot class
  source:
    persistentVolumeClaimName: prometheus-prometheus-0
```

```bash
# Create snapshot
kubectl apply -f pvc-snapshot.yaml

# Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/prometheus-snapshot-20231127 -n monitoring --timeout=300s

# Verify snapshot
kubectl get volumesnapshot -n monitoring prometheus-snapshot-20231127 -o yaml

# Get snapshot handle (for external backup)
kubectl get volumesnapshot -n monitoring prometheus-snapshot-20231127 \
  -o jsonpath='{.status.snapshotHandle}'
```

### 5. Full Backup Script

```bash
#!/bin/bash
# full-backup.sh - Complete Prometheus backup

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
RELEASE_NAME="${RELEASE_NAME:-prometheus}"
POD_NAME="${POD_NAME:-prometheus-0}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT="./backups/prometheus"
S3_BUCKET="${S3_BUCKET:-}"

echo "=== Prometheus Full Backup Started ==="
echo "Timestamp: $TIMESTAMP"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Create backup directory structure
mkdir -p $BACKUP_ROOT/full/$TIMESTAMP/{tsdb,config,rules,metadata}

# 1. TSDB Snapshot
echo "[1/5] Creating TSDB snapshot..."
SNAPSHOT_JSON=$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot)

SNAPSHOT_NAME=$(echo $SNAPSHOT_JSON | jq -r '.data.name')

if [ -n "$SNAPSHOT_NAME" ] && [ "$SNAPSHOT_NAME" != "null" ]; then
  echo "  Snapshot created: $SNAPSHOT_NAME"
  kubectl cp $NAMESPACE/$POD_NAME:/prometheus/snapshots/$SNAPSHOT_NAME \
    $BACKUP_ROOT/full/$TIMESTAMP/tsdb/snapshot -c prometheus

  # Clean up snapshot in pod
  kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
    rm -rf /prometheus/snapshots/$SNAPSHOT_NAME
  echo "  TSDB snapshot backed up"
else
  echo "  Warning: TSDB snapshot failed, continuing..."
fi

# 2. Configuration
echo "[2/5] Backing up configuration..."
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-server -o yaml > \
  $BACKUP_ROOT/full/$TIMESTAMP/config/configmap.yaml
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  cat /etc/prometheus/prometheus.yml > \
  $BACKUP_ROOT/full/$TIMESTAMP/config/prometheus.yml
echo "  Configuration backed up"

# 3. Rules
echo "[3/5] Backing up rules..."
if kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-rules &>/dev/null; then
  kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-rules -o yaml > \
    $BACKUP_ROOT/full/$TIMESTAMP/rules/rules-configmap.yaml
fi
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/rules > \
  $BACKUP_ROOT/full/$TIMESTAMP/rules/loaded-rules.json
echo "  Rules backed up"

# 4. Metadata
echo "[4/5] Creating metadata..."
cat > $BACKUP_ROOT/full/$TIMESTAMP/metadata/backup-info.json <<EOF
{
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "release_name": "$RELEASE_NAME",
  "pod_name": "$POD_NAME",
  "backup_date": "$(date -Iseconds)",
  "prometheus_version": "$(kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- prometheus --version | head -1)",
  "backup_components": {
    "tsdb_snapshot": $([ -n "$SNAPSHOT_NAME" ] && echo "\"$SNAPSHOT_NAME\"" || echo "null"),
    "configuration": true,
    "rules": true
  }
}
EOF

# Get TSDB status
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb > \
  $BACKUP_ROOT/full/$TIMESTAMP/metadata/tsdb-status.json

echo "  Metadata created"

# 5. Compress and optionally upload
echo "[5/5] Compressing backup..."
cd $BACKUP_ROOT/full
tar -czf $TIMESTAMP.tar.gz $TIMESTAMP/
BACKUP_SIZE=$(du -h $TIMESTAMP.tar.gz | cut -f1)
rm -rf $TIMESTAMP/

echo "  Backup compressed: $BACKUP_SIZE"

# Upload to S3/MinIO if configured
if [ -n "$S3_BUCKET" ]; then
  echo "Uploading to S3: $S3_BUCKET"
  aws s3 cp $TIMESTAMP.tar.gz s3://$S3_BUCKET/prometheus/full/$TIMESTAMP.tar.gz
  echo "  Upload completed"
fi

echo ""
echo "=== Prometheus Full Backup Completed ==="
echo "Location: $BACKUP_ROOT/full/$TIMESTAMP.tar.gz"
echo "Size: $BACKUP_SIZE"
echo "Timestamp: $TIMESTAMP"
```

---

## Recovery Procedures

### 1. TSDB Snapshot Recovery

#### Scenario: Restore Historical Metrics Data

```bash
#!/bin/bash
# restore-tsdb.sh

set -e

NAMESPACE="monitoring"
POD_NAME="prometheus-0"
BACKUP_FILE="./backups/prometheus/tsdb/20231127-120000.tar.gz"
RESTORE_DIR="./restore-temp"

echo "=== TSDB Snapshot Restore ==="

# 1. Extract backup
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR
SNAPSHOT_DIR=$(ls -d $RESTORE_DIR/*/snapshot 2>/dev/null | head -1)

if [ -z "$SNAPSHOT_DIR" ]; then
  echo "Error: No snapshot directory found in backup"
  exit 1
fi

echo "Found snapshot: $SNAPSHOT_DIR"

# 2. Stop Prometheus (scale to 0)
echo "Stopping Prometheus..."
kubectl scale statefulset/prometheus -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod/$POD_NAME -n $NAMESPACE --timeout=120s

# 3. Copy snapshot to PVC via temporary pod
echo "Creating restore helper pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: prometheus-restore-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /prometheus
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: prometheus-prometheus-0
  restartPolicy: Never
EOF

# Wait for pod
kubectl wait --for=condition=Ready pod/prometheus-restore-helper -n $NAMESPACE --timeout=120s

# 4. Clear existing data and copy snapshot
echo "Restoring snapshot data..."
kubectl exec -n $NAMESPACE prometheus-restore-helper -- rm -rf /prometheus/*
kubectl cp $SNAPSHOT_DIR prometheus-restore-helper:/prometheus/data -n $NAMESPACE

# 5. Clean up helper pod
kubectl delete pod/prometheus-restore-helper -n $NAMESPACE

# 6. Restart Prometheus
echo "Restarting Prometheus..."
kubectl scale statefulset/prometheus -n $NAMESPACE --replicas=1
kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=300s

# 7. Verify restoration
echo "Verifying restoration..."
sleep 10
kubectl exec -n $NAMESPACE $POD_NAME -c prometheus -- \
  wget -qO- http://localhost:9090/-/healthy

echo "TSDB restoration completed successfully"

# Cleanup
rm -rf $RESTORE_DIR
```

### 2. Configuration Recovery

#### Scenario: Restore Prometheus Configuration

```bash
#!/bin/bash
# restore-config.sh

set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
BACKUP_FILE="./backups/prometheus/config/20231127-120000.tar.gz"
RESTORE_DIR="./restore-temp"

echo "=== Configuration Restore ==="

# 1. Extract backup
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR

CONFIGMAP_FILE=$(find $RESTORE_DIR -name "configmap.yaml" | head -1)

if [ -z "$CONFIGMAP_FILE" ]; then
  echo "Error: No configmap.yaml found in backup"
  exit 1
fi

# 2. Backup current configuration (just in case)
echo "Backing up current configuration..."
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-server -o yaml > \
  current-config-backup.yaml

# 3. Apply restored configuration
echo "Restoring configuration..."
kubectl apply -f $CONFIGMAP_FILE

# 4. Reload Prometheus configuration
echo "Reloading Prometheus..."
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload

# 5. Verify configuration
echo "Verifying configuration..."
sleep 5
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  promtool check config /etc/prometheus/prometheus.yml

echo "Configuration restoration completed successfully"

# Cleanup
rm -rf $RESTORE_DIR
```

### 3. Rules Recovery

```bash
#!/bin/bash
# restore-rules.sh

set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
BACKUP_FILE="./backups/prometheus/rules/20231127-120000.tar.gz"
RESTORE_DIR="./restore-temp"

echo "=== Rules Restore ==="

# 1. Extract backup
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR

RULES_CONFIGMAP=$(find $RESTORE_DIR -name "rules-configmap.yaml" | head -1)

# 2. Restore rules
if [ -n "$RULES_CONFIGMAP" ]; then
  echo "Restoring rules ConfigMap..."
  kubectl apply -f $RULES_CONFIGMAP

  # 3. Reload Prometheus
  echo "Reloading Prometheus..."
  kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
    wget -qO- --post-data='' http://localhost:9090/-/reload

  # 4. Verify rules
  echo "Verifying rules..."
  sleep 5
  kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
    wget -qO- http://localhost:9090/api/v1/rules | jq '.data.groups | length'

  echo "Rules restoration completed successfully"
else
  echo "No rules ConfigMap found in backup"
fi

# Cleanup
rm -rf $RESTORE_DIR
```

### 4. PVC Snapshot Recovery

```bash
#!/bin/bash
# restore-pvc-snapshot.sh

set -e

NAMESPACE="monitoring"
SNAPSHOT_NAME="prometheus-snapshot-20231127"
NEW_PVC_NAME="prometheus-restored"

echo "=== PVC Snapshot Restore ==="

# 1. Create PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $NEW_PVC_NAME
  namespace: $NAMESPACE
spec:
  storageClassName: standard  # Match original storage class
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi  # Match original size
EOF

# 2. Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/$NEW_PVC_NAME -n $NAMESPACE --timeout=300s

echo "PVC created from snapshot: $NEW_PVC_NAME"
echo "Update StatefulSet volumeClaimTemplates to use this PVC"
```

### 5. Full Disaster Recovery

```bash
#!/bin/bash
# full-disaster-recovery.sh

set -e

NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
BACKUP_FILE="./backups/prometheus/full/20231127-120000.tar.gz"
RESTORE_DIR="./restore-temp"

echo "=== Full Disaster Recovery Started ==="

# 1. Extract full backup
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR
BACKUP_ROOT=$(ls -d $RESTORE_DIR/*/ | head -1)

# 2. Restore configuration
echo "[1/3] Restoring configuration..."
kubectl apply -f $BACKUP_ROOT/config/configmap.yaml

# 3. Restore rules
echo "[2/3] Restoring rules..."
if [ -f $BACKUP_ROOT/rules/rules-configmap.yaml ]; then
  kubectl apply -f $BACKUP_ROOT/rules/rules-configmap.yaml
fi

# 4. Restore TSDB data
echo "[3/3] Restoring TSDB data..."
if [ -d $BACKUP_ROOT/tsdb/snapshot ]; then
  # Scale down
  kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=0
  kubectl wait --for=delete pod/prometheus-0 -n $NAMESPACE --timeout=120s

  # Create helper pod
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: prometheus-restore-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /prometheus
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: prometheus-prometheus-0
  restartPolicy: Never
EOF

  kubectl wait --for=condition=Ready pod/prometheus-restore-helper -n $NAMESPACE --timeout=120s

  # Copy data
  kubectl exec -n $NAMESPACE prometheus-restore-helper -- rm -rf /prometheus/*
  kubectl cp $BACKUP_ROOT/tsdb/snapshot prometheus-restore-helper:/prometheus/data -n $NAMESPACE

  # Cleanup helper
  kubectl delete pod/prometheus-restore-helper -n $NAMESPACE

  # Scale up
  kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=1
  kubectl wait --for=condition=Ready pod/prometheus-0 -n $NAMESPACE --timeout=300s
fi

echo ""
echo "=== Full Disaster Recovery Completed ==="
echo "Verifying Prometheus..."
kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/-/healthy

# Cleanup
rm -rf $RESTORE_DIR
```

---

## Automation

### Cron Job for Automated Backups

```yaml
# prometheus-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: prometheus-backup
  namespace: monitoring
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: prometheus-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            env:
            - name: NAMESPACE
              value: "monitoring"
            - name: RELEASE_NAME
              value: "prometheus"
            - name: S3_BUCKET
              value: "prometheus-backups"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: secret-access-key
            command:
            - /bin/bash
            - -c
            - |
              set -e
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)

              # Create TSDB snapshot
              SNAPSHOT_JSON=$(kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
                wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot)

              SNAPSHOT_NAME=$(echo $SNAPSHOT_JSON | jq -r '.data.name')

              # Copy snapshot to temporary location
              kubectl cp $NAMESPACE/prometheus-0:/prometheus/snapshots/$SNAPSHOT_NAME \
                /tmp/snapshot -c prometheus

              # Create archive
              cd /tmp
              tar -czf prometheus-backup-$TIMESTAMP.tar.gz snapshot/

              # Upload to S3
              aws s3 cp prometheus-backup-$TIMESTAMP.tar.gz \
                s3://$S3_BUCKET/tsdb/prometheus-backup-$TIMESTAMP.tar.gz

              # Clean up
              kubectl exec -n $NAMESPACE prometheus-0 -c prometheus -- \
                rm -rf /prometheus/snapshots/$SNAPSHOT_NAME
              rm -rf /tmp/snapshot /tmp/prometheus-backup-$TIMESTAMP.tar.gz

              echo "Backup completed: $TIMESTAMP"
          restartPolicy: OnFailure
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-backup
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prometheus-backup
  namespace: monitoring
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec"]
  verbs: ["get", "list", "create"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prometheus-backup
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: prometheus-backup
subjects:
- kind: ServiceAccount
  name: prometheus-backup
  namespace: monitoring
```

---

## Testing & Validation

### Backup Validation Checklist

```bash
#!/bin/bash
# validate-backup.sh

set -e

BACKUP_FILE="$1"
RESTORE_DIR="./test-restore"

echo "=== Backup Validation ==="

# 1. Extract backup
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR

# 2. Check required files
echo "Checking backup structure..."
REQUIRED_PATHS=(
  "*/metadata/backup-info.json"
  "*/config/prometheus.yml"
)

for path in "${REQUIRED_PATHS[@]}"; do
  if ! ls $RESTORE_DIR/$path &>/dev/null; then
    echo "ERROR: Missing required file: $path"
    exit 1
  fi
  echo "  ✓ Found: $path"
done

# 3. Validate prometheus.yml
echo "Validating Prometheus configuration..."
CONFIG_FILE=$(find $RESTORE_DIR -name "prometheus.yml" | head -1)
if command -v promtool &>/dev/null; then
  promtool check config $CONFIG_FILE
  echo "  ✓ Configuration is valid"
else
  echo "  ⚠ promtool not available, skipping validation"
fi

# 4. Check metadata
echo "Checking metadata..."
METADATA=$(find $RESTORE_DIR -name "backup-info.json" | head -1)
jq . $METADATA
BACKUP_DATE=$(jq -r '.backup_date' $METADATA)
echo "  ✓ Backup date: $BACKUP_DATE"

# 5. Check TSDB snapshot
if [ -d $RESTORE_DIR/*/tsdb/snapshot ]; then
  SNAPSHOT_SIZE=$(du -sh $RESTORE_DIR/*/tsdb/snapshot | cut -f1)
  echo "  ✓ TSDB snapshot size: $SNAPSHOT_SIZE"
else
  echo "  ⚠ No TSDB snapshot found"
fi

echo ""
echo "=== Backup Validation Completed ==="

# Cleanup
rm -rf $RESTORE_DIR
```

---

## Best Practices

### 1. Backup Frequency

- **TSDB Snapshots**: Hourly during business hours, every 6 hours otherwise
- **Configuration**: Daily or before any changes
- **Rules**: Daily or before any changes
- **PVC Snapshots**: Weekly for disaster recovery

### 2. Retention Policy

```bash
# Retention cleanup script
#!/bin/bash
# cleanup-old-backups.sh

BACKUP_DIR="./backups/prometheus"
TSDB_RETENTION_DAYS=30
CONFIG_RETENTION_DAYS=90
S3_BUCKET="prometheus-backups"

# Local cleanup
find $BACKUP_DIR/tsdb -name "*.tar.gz" -mtime +$TSDB_RETENTION_DAYS -delete
find $BACKUP_DIR/config -name "*.tar.gz" -mtime +$CONFIG_RETENTION_DAYS -delete

# S3 cleanup
aws s3 ls s3://$S3_BUCKET/tsdb/ | \
  awk '{if ($1 < "'$(date -d "$TSDB_RETENTION_DAYS days ago" +%Y-%m-%d)'") print $4}' | \
  xargs -I {} aws s3 rm s3://$S3_BUCKET/tsdb/{}
```

### 3. Monitoring Backup Health

```yaml
# Prometheus alert for backup monitoring
groups:
- name: backup-alerts
  rules:
  - alert: PrometheusBackupFailed
    expr: |
      time() - prometheus_backup_last_success_timestamp > 25200  # 7 hours
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "Prometheus backup has not succeeded in 7 hours"
      description: "Last successful backup: {{ $value | humanizeDuration }} ago"

  - alert: PrometheusBackupOld
    expr: |
      time() - prometheus_backup_last_success_timestamp > 172800  # 48 hours
    for: 1h
    labels:
      severity: critical
    annotations:
      summary: "Prometheus backup is critically old"
      description: "Last successful backup: {{ $value | humanizeDuration }} ago"
```

### 4. Security

- Store S3/MinIO credentials in Kubernetes Secrets
- Use encryption for backups at rest (S3 server-side encryption)
- Restrict access to backup storage with IAM policies
- Audit backup access regularly

### 5. Testing

- Test restoration monthly (not just backups!)
- Verify metrics data integrity after restoration
- Document recovery time actual (RTA)
- Update runbooks based on test results

---

## Troubleshooting

### Common Issues

#### 1. TSDB Snapshot Failed

**Symptom**: Snapshot API returns error or null snapshot name

**Causes**:
- Admin API not enabled
- Insufficient disk space
- Prometheus not ready

**Solution**:
```bash
# Check if admin API is enabled
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/flags | grep admin-api

# Check disk space
kubectl exec -n monitoring prometheus-0 -c prometheus -- df -h /prometheus

# Restart Prometheus if needed
kubectl rollout restart statefulset/prometheus -n monitoring
```

#### 2. kubectl cp Timeout

**Symptom**: kubectl cp hangs or times out when copying large snapshots

**Solution**:
```bash
# Use tar streaming instead
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  tar czf - -C /prometheus/snapshots $SNAPSHOT_NAME | \
  tar xzf - -C ./backups/prometheus/tsdb/
```

#### 3. Configuration Reload Failed

**Symptom**: Configuration reload returns error

**Causes**:
- Invalid YAML syntax
- Invalid scrape configs
- Lifecycle API not enabled

**Solution**:
```bash
# Validate config first
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  promtool check config /etc/prometheus/prometheus.yml

# Check if lifecycle is enabled
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/flags | grep lifecycle

# Manual pod restart if reload fails
kubectl delete pod prometheus-0 -n monitoring
```

#### 4. PVC Snapshot Not Ready

**Symptom**: VolumeSnapshot stuck in Pending state

**Causes**:
- CSI driver not installed
- Snapshot class not configured
- Insufficient storage

**Solution**:
```bash
# Check CSI driver
kubectl get csidriver

# Check snapshot class
kubectl get volumesnapshotclass

# Check events
kubectl describe volumesnapshot prometheus-snapshot-20231127 -n monitoring
```

#### 5. Restore Data Corruption

**Symptom**: Prometheus fails to start after restore or metrics missing

**Causes**:
- Incomplete snapshot copy
- Wrong data directory structure
- TSDB corruption

**Solution**:
```bash
# Verify snapshot integrity before restore
tar -tzf backup.tar.gz | head -20

# Use promtool to check TSDB
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  promtool tsdb analyze /prometheus/data

# If corrupted, restore from older backup
```

---

## Appendix

### A. Backup Storage Sizing

| Component | Daily Size | 30-Day Retention | Notes |
|-----------|------------|------------------|-------|
| TSDB Snapshots | 1-5 GB | 30-150 GB | Depends on cardinality |
| Configuration | < 1 MB | < 30 MB | Minimal |
| Rules | < 500 KB | < 15 MB | Minimal |
| PVC Snapshots | 10-50 GB | 70-350 GB | Weekly snapshots |
| **Total** | **11-56 GB** | **100-530 GB** | Compressed |

### B. Recovery Time Estimates

| Recovery Type | RTO | Complexity | Automation |
|---------------|-----|------------|------------|
| Configuration | < 5 min | Low | Full |
| Rules | < 5 min | Low | Full |
| TSDB (10GB) | 15-30 min | Medium | Partial |
| TSDB (100GB) | 1-2 hours | Medium | Partial |
| Full DR | 1-2 hours | High | Partial |

### C. Useful Commands

```bash
# Check Prometheus version
kubectl exec -n monitoring prometheus-0 -c prometheus -- prometheus --version

# Check TSDB stats
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/tsdb | jq .

# List all snapshots in pod
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  ls -lh /prometheus/snapshots/

# Check configuration validity
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  promtool check config /etc/prometheus/prometheus.yml

# Check active targets
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | jq .

# Get current retention settings
kubectl exec -n monitoring prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/api/v1/status/flags | jq -r '.data.["storage.tsdb.retention.time"]'
```

---

**Document Version**: 1.0.0
**Last Updated**: 2025-11-27
**Prometheus Version**: 3.7.3
**Chart Version**: v0.3.0
