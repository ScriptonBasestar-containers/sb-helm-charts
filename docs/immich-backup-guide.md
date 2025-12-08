# Immich Backup & Recovery Guide

## Overview

This guide provides comprehensive backup and recovery procedures for Immich, a self-hosted photo and video management solution. Immich stores critical data across multiple components, and this guide covers strategies for protecting all aspects of your deployment.

### What Gets Backed Up

Immich backup strategy involves five key components:

1. **Photos and Videos (Library PVC)** - The largest component containing all uploaded media files
2. **PostgreSQL Database** - Photo metadata, albums, sharing settings, users, and ML-generated embeddings
3. **Redis Cache** - Optional, can be rebuilt but improves performance
4. **ML Model Cache** - Machine learning models (can be re-downloaded but time-consuming)
5. **Configuration** - Kubernetes resources, Helm values, and ConfigMaps

### Backup Strategy Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Immich Backup Strategy                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ Library PVC      │  │ PostgreSQL DB    │  │ Redis Cache  │ │
│  │ (Photos/Videos)  │  │ (Metadata)       │  │ (Optional)   │ │
│  │ Priority: HIGH   │  │ Priority: HIGH   │  │ Priority: LOW│ │
│  └──────────────────┘  └──────────────────┘  └──────────────┘ │
│           │                     │                     │         │
│           ▼                     ▼                     ▼         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Backup Storage (S3/MinIO/NFS/Local)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │ ML Model Cache   │  │ Configuration    │                   │
│  │ (Can rebuild)    │  │ (Kubernetes)     │                   │
│  │ Priority: MEDIUM │  │ Priority: HIGH   │                   │
│  └──────────────────┘  └──────────────────┘                   │
│           │                     │                               │
│           ▼                     ▼                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Backup Storage (S3/MinIO/NFS/Local)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Component | RTO | RPO | Notes |
|-----------|-----|-----|-------|
| Library PVC | < 2 hours | 24 hours | Large data volume, depends on storage speed |
| PostgreSQL DB | < 30 minutes | 24 hours | Fast restore with pg_restore |
| Redis Cache | < 10 minutes | N/A | Can be skipped, will rebuild automatically |
| ML Model Cache | < 1 hour | N/A | Can be re-downloaded from Immich servers |
| Configuration | < 10 minutes | On-change | Git-based versioning recommended |

**Overall RTO:** < 2 hours (primarily limited by library PVC restore time)
**Overall RPO:** 24 hours (daily backups recommended)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Component 1: Library PVC Backup](#component-1-library-pvc-backup)
3. [Component 2: PostgreSQL Database Backup](#component-2-postgresql-database-backup)
4. [Component 3: Redis Cache Backup](#component-3-redis-cache-backup)
5. [Component 4: ML Model Cache Backup](#component-4-ml-model-cache-backup)
6. [Component 5: Configuration Backup](#component-5-configuration-backup)
7. [Full Backup Procedures](#full-backup-procedures)
8. [Disaster Recovery Procedures](#disaster-recovery-procedures)
9. [Automated Backup Strategies](#automated-backup-strategies)
10. [Backup Verification](#backup-verification)
11. [Best Practices](#best-practices)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

```bash
# Install required CLI tools
# kubectl (Kubernetes CLI)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# PostgreSQL client tools
sudo apt-get install postgresql-client  # Debian/Ubuntu
sudo yum install postgresql             # RHEL/CentOS

# Optional: Restic for incremental backups
sudo apt-get install restic             # Debian/Ubuntu
brew install restic                     # macOS

# Optional: Rclone for cloud storage sync
sudo apt-get install rclone             # Debian/Ubuntu
brew install rclone                     # macOS
```

### Environment Variables

Create a backup configuration file:

```bash
# backup-config.env
export RELEASE_NAME="immich"
export NAMESPACE="default"
export BACKUP_DIR="/backup/immich"
export S3_BUCKET="immich-backups"
export S3_ENDPOINT="s3.amazonaws.com"
export POSTGRES_HOST="postgres.example.com"
export POSTGRES_PORT="5432"
export POSTGRES_DB="immich"
export POSTGRES_USER="immich"
export RETENTION_DAYS=30
```

Load the configuration:

```bash
source backup-config.env
```

### Access Requirements

Ensure you have:

1. **Kubernetes Access**: `kubectl` access to the cluster with appropriate RBAC permissions
2. **Database Access**: PostgreSQL credentials with backup privileges
3. **Storage Access**: Write permissions to backup destination (S3, NFS, local storage)
4. **Network Access**: Ability to reach Immich pods, database, and storage backends

### Storage Requirements

Estimate backup storage needs:

```bash
# Calculate library PVC size
kubectl get pvc -n $NAMESPACE ${RELEASE_NAME}-library -o jsonpath='{.status.capacity.storage}'

# Calculate PostgreSQL database size
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c \
  "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));"

# Estimate total backup size (Library + DB + overhead)
# Recommended: 1.5x library size + 2x database size
```

Typical storage estimates:
- **Small deployment** (< 10,000 photos): 50-100 GB
- **Medium deployment** (10,000-100,000 photos): 100-500 GB
- **Large deployment** (> 100,000 photos): 500 GB - 5 TB

---

## Component 1: Library PVC Backup

The library PVC contains all uploaded photos, videos, profile pictures, and thumbnails. This is the most critical and largest backup component.

### 1.1 Direct PVC Backup (Using Helper Pod)

**Pros:** Simple, no special tools required
**Cons:** Slower for large datasets, requires pod scheduling

#### Create Backup Helper Pod

```bash
# Create a backup helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immich-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: library
      mountPath: /data
      readOnly: true
  volumes:
  - name: library
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-library
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/immich-backup-helper -n $NAMESPACE --timeout=120s
```

#### Backup Library Data

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/library/$(date +%Y%m%d)

# Backup using tar (with compression)
kubectl exec -n $NAMESPACE immich-backup-helper -- \
  tar czf - /data | \
  cat > $BACKUP_DIR/library/$(date +%Y%m%d)/library.tar.gz

# Backup using rsync (incremental)
kubectl exec -n $NAMESPACE immich-backup-helper -- \
  tar cf - /data | \
  tar xf - -C $BACKUP_DIR/library/$(date +%Y%m%d)/

# Generate checksums
cd $BACKUP_DIR/library/$(date +%Y%m%d)
find . -type f -exec sha256sum {} \; > checksums.sha256
```

#### Cleanup

```bash
# Delete backup helper pod
kubectl delete pod immich-backup-helper -n $NAMESPACE
```

### 1.2 Restic Backup (Incremental, Recommended)

**Pros:** Incremental, deduplication, encryption, multiple backends
**Cons:** Requires Restic installation

#### Initialize Restic Repository

```bash
# Initialize Restic repository (one-time setup)
export RESTIC_REPOSITORY="s3:${S3_ENDPOINT}/${S3_BUCKET}/immich-library"
export RESTIC_PASSWORD="your-secure-password"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

restic init
```

#### Backup with Restic

```bash
# Create backup helper pod (same as section 1.1)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immich-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: restic/restic:latest
    command: ["sleep", "infinity"]
    env:
    - name: RESTIC_REPOSITORY
      value: "s3:${S3_ENDPOINT}/${S3_BUCKET}/immich-library"
    - name: RESTIC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: restic-backup-secret
          key: password
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: s3-credentials
          key: access-key
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: s3-credentials
          key: secret-key
    volumeMounts:
    - name: library
      mountPath: /data
      readOnly: true
  volumes:
  - name: library
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-library
  restartPolicy: Never
EOF

# Run Restic backup
kubectl exec -n $NAMESPACE immich-backup-helper -- \
  restic backup /data --tag daily --host immich-library

# Check snapshots
kubectl exec -n $NAMESPACE immich-backup-helper -- \
  restic snapshots

# Cleanup
kubectl delete pod immich-backup-helper -n $NAMESPACE
```

### 1.3 Volume Snapshot (Fastest, Requires CSI Driver)

**Pros:** Near-instant, storage-level efficiency
**Cons:** Requires CSI snapshot support, vendor-specific

#### Create VolumeSnapshot

```bash
# Check if VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# Create VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: immich-library-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapshot-class  # Adjust to your CSI driver
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-library
EOF

# Wait for snapshot to be ready
kubectl get volumesnapshot -n $NAMESPACE -w
```

#### Export Snapshot to External Storage (Optional)

```bash
# Clone snapshot to temporary PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: immich-library-snapshot-export
  namespace: $NAMESPACE
spec:
  dataSource:
    name: immich-library-snapshot-$(date +%Y%m%d-%H%M%S)
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi  # Match library PVC size
EOF

# Use backup helper pod to export
# (Follow section 1.1 or 1.2 procedures)
```

### 1.4 Makefile Targets

```bash
# Backup library using tar
make -f make/ops/immich.mk immich-backup-library

# Backup library using Restic
make -f make/ops/immich.mk immich-backup-library-restic

# Create volume snapshot
make -f make/ops/immich.mk immich-snapshot-library

# Verify library backup
make -f make/ops/immich.mk immich-verify-library-backup
```

---

## Component 2: PostgreSQL Database Backup

The PostgreSQL database contains all photo metadata, albums, sharing settings, users, and ML-generated embeddings. This is a critical component for full recovery.

### 2.1 Logical Backup (pg_dump)

**Pros:** Portable, version-independent, selective restore
**Cons:** Slower for large databases

#### Full Database Dump

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/postgresql/$(date +%Y%m%d)

# Backup using pg_dump (custom format, compressed)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -Fc -f - > $BACKUP_DIR/postgresql/$(date +%Y%m%d)/immich-db.dump

# Backup using pg_dump (SQL format, human-readable)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -f - > $BACKUP_DIR/postgresql/$(date +%Y%m%d)/immich-db.sql

# Generate backup metadata
cat > $BACKUP_DIR/postgresql/$(date +%Y%m%d)/backup-info.txt <<EOF
Backup Date: $(date)
Database: $POSTGRES_DB
Database Version: $(kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT version();")
Database Size: $(kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -t -c \
  "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));")
EOF
```

#### Table-Level Backup (Selective)

```bash
# Backup specific tables (useful for large databases)
TABLES="users assets albums shared_links smart_search"

for table in $TABLES; do
  kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
    pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
    -t $table -Fc -f - > $BACKUP_DIR/postgresql/$(date +%Y%m%d)/${table}.dump
done
```

### 2.2 Physical Backup (pg_basebackup)

**Pros:** Faster for large databases, point-in-time recovery (with WAL archiving)
**Cons:** Version-specific, requires more storage

#### Base Backup

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/postgresql/basebackup/$(date +%Y%m%d)

# Run pg_basebackup
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_basebackup -h $POSTGRES_HOST -U $POSTGRES_USER -D - \
  -Ft -z -P > $BACKUP_DIR/postgresql/basebackup/$(date +%Y%m%d)/base.tar.gz
```

### 2.3 Backup Verification

```bash
# Verify pg_dump backup
pg_restore --list $BACKUP_DIR/postgresql/$(date +%Y%m%d)/immich-db.dump | head -20

# Check backup file size
du -sh $BACKUP_DIR/postgresql/$(date +%Y%m%d)/immich-db.dump

# Verify checksums
cd $BACKUP_DIR/postgresql/$(date +%Y%m%d)
sha256sum immich-db.dump > immich-db.dump.sha256
sha256sum -c immich-db.dump.sha256
```

### 2.4 Makefile Targets

```bash
# Full database dump
make -f make/ops/immich.mk immich-backup-db

# Table-level backup
make -f make/ops/immich.mk immich-backup-db-tables

# Verify database backup
make -f make/ops/immich.mk immich-verify-db-backup
```

---

## Component 3: Redis Cache Backup

Redis cache in Immich is used for session management, job queues, and performance optimization. Backing up Redis is optional since it can rebuild automatically, but it improves recovery time.

### 3.1 Redis RDB Snapshot

**Pros:** Fast, native Redis format
**Cons:** Not human-readable

#### Create RDB Snapshot

```bash
# Trigger BGSAVE (background save)
kubectl exec -n $NAMESPACE redis-0 -- redis-cli BGSAVE

# Wait for save to complete
kubectl exec -n $NAMESPACE redis-0 -- redis-cli LASTSAVE

# Copy RDB file from Redis pod
kubectl cp $NAMESPACE/redis-0:/data/dump.rdb $BACKUP_DIR/redis/$(date +%Y%m%d)/dump.rdb
```

### 3.2 Redis AOF Backup (If Enabled)

```bash
# Check if AOF is enabled
kubectl exec -n $NAMESPACE redis-0 -- redis-cli CONFIG GET appendonly

# If enabled, copy AOF file
kubectl cp $NAMESPACE/redis-0:/data/appendonly.aof $BACKUP_DIR/redis/$(date +%Y%m%d)/appendonly.aof
```

### 3.3 Makefile Targets

```bash
# Backup Redis RDB
make -f make/ops/immich.mk immich-backup-redis

# Verify Redis backup
make -f make/ops/immich.mk immich-verify-redis-backup
```

**Note:** Redis backup is **LOW priority**. If storage or time is limited, skip Redis backups. Immich will rebuild cache automatically on restart.

---

## Component 4: ML Model Cache Backup

The ML model cache contains downloaded machine learning models used for face recognition, object detection, and CLIP embeddings. Backing up this cache is optional but saves time during recovery (models can be re-downloaded from Immich servers).

### 4.1 ML Cache Backup

```bash
# Create backup helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immich-ml-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: ml-cache
      mountPath: /cache
      readOnly: true
  volumes:
  - name: ml-cache
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-ml-cache
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/immich-ml-backup-helper -n $NAMESPACE --timeout=120s

# Backup ML cache
mkdir -p $BACKUP_DIR/ml-cache/$(date +%Y%m%d)
kubectl exec -n $NAMESPACE immich-ml-backup-helper -- \
  tar czf - /cache | \
  cat > $BACKUP_DIR/ml-cache/$(date +%Y%m%d)/ml-cache.tar.gz

# Cleanup
kubectl delete pod immich-ml-backup-helper -n $NAMESPACE
```

### 4.2 Model Inventory

```bash
# List downloaded models
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-machine-learning-0 -- \
  ls -lh /cache

# Save model inventory
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-machine-learning-0 -- \
  find /cache -type f -exec ls -lh {} \; > $BACKUP_DIR/ml-cache/$(date +%Y%m%d)/model-inventory.txt
```

### 4.3 Makefile Targets

```bash
# Backup ML cache
make -f make/ops/immich.mk immich-backup-ml-cache

# List ML models
make -f make/ops/immich.mk immich-list-ml-models
```

**Note:** ML cache backup is **MEDIUM priority**. Models total ~5-10 GB and can be re-downloaded in 30-60 minutes with good internet connection.

---

## Component 5: Configuration Backup

Backing up Kubernetes configuration ensures you can recreate the exact deployment state.

### 5.1 Helm Values Backup

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/config/$(date +%Y%m%d)

# Export current Helm values
helm get values $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/config/$(date +%Y%m%d)/values.yaml

# Export full Helm release manifest
helm get manifest $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/config/$(date +%Y%m%d)/manifest.yaml

# Export Helm release metadata
helm get all $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/config/$(date +%Y%m%d)/release-full.yaml
```

### 5.2 Kubernetes Resources Backup

```bash
# Export all Immich resources
kubectl get all -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/config/$(date +%Y%m%d)/k8s-resources.yaml

# Export ConfigMaps
kubectl get configmap -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/config/$(date +%Y%m%d)/configmaps.yaml

# Export Secrets (CAUTION: Contains sensitive data)
kubectl get secret -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/config/$(date +%Y%m%d)/secrets.yaml

# Encrypt secrets backup
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/config/$(date +%Y%m%d)/secrets.yaml
rm $BACKUP_DIR/config/$(date +%Y%m%d)/secrets.yaml  # Remove plaintext
```

### 5.3 Git-Based Configuration Management (Recommended)

```bash
# Initialize Git repository for configuration
cd $BACKUP_DIR/config
git init
git add values.yaml manifest.yaml
git commit -m "Backup Immich config $(date +%Y%m%d)"
git remote add origin git@github.com:yourorg/immich-config-backup.git
git push origin master
```

### 5.4 Makefile Targets

```bash
# Backup Helm values
make -f make/ops/immich.mk immich-backup-config

# Backup all Kubernetes resources
make -f make/ops/immich.mk immich-backup-k8s-resources
```

---

## Full Backup Procedures

### 7.1 Full Backup Script

Create a comprehensive backup script:

```bash
#!/bin/bash
# immich-full-backup.sh

set -euo pipefail

# Load configuration
source backup-config.env

# Create timestamped backup directory
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$BACKUP_TIMESTAMP"
mkdir -p "$BACKUP_PATH"

echo "Starting full Immich backup: $BACKUP_TIMESTAMP"

# 1. Backup configuration (fastest, do first)
echo "[1/5] Backing up configuration..."
make -f make/ops/immich.mk immich-backup-config

# 2. Backup PostgreSQL database
echo "[2/5] Backing up PostgreSQL database..."
make -f make/ops/immich.mk immich-backup-db

# 3. Backup library PVC (largest, most time-consuming)
echo "[3/5] Backing up library PVC..."
make -f make/ops/immich.mk immich-backup-library-restic

# 4. Backup Redis (optional)
echo "[4/5] Backing up Redis cache..."
make -f make/ops/immich.mk immich-backup-redis || echo "Redis backup failed, continuing..."

# 5. Backup ML cache (optional)
echo "[5/5] Backing up ML model cache..."
make -f make/ops/immich.mk immich-backup-ml-cache || echo "ML cache backup failed, continuing..."

# Generate backup manifest
cat > "$BACKUP_PATH/backup-manifest.txt" <<EOF
Immich Full Backup
==================
Timestamp: $BACKUP_TIMESTAMP
Release: $RELEASE_NAME
Namespace: $NAMESPACE

Components:
- Configuration: ✓
- PostgreSQL Database: ✓
- Library PVC: ✓
- Redis Cache: ✓
- ML Model Cache: ✓

Backup Location: $BACKUP_PATH
EOF

echo "Full backup completed: $BACKUP_PATH"
```

### 7.2 Makefile Target

```bash
# Run full backup
make -f make/ops/immich.mk immich-full-backup
```

### 7.3 Backup Retention

```bash
# Delete backups older than retention period
find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# List current backups
ls -lh $BACKUP_DIR/
```

---

## Disaster Recovery Procedures

### 8.1 Full Recovery Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                  Disaster Recovery Workflow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Prepare Kubernetes Environment                              │
│     ├─ Create namespace                                         │
│     ├─ Restore secrets (database credentials, S3 keys)          │
│     └─ Verify external dependencies (PostgreSQL, Redis)         │
│                                                                 │
│  2. Restore Configuration                                       │
│     ├─ Apply Helm values                                        │
│     └─ Verify configuration                                     │
│                                                                 │
│  3. Restore PostgreSQL Database                                 │
│     ├─- Create empty database                                   │
│     ├─ Restore from pg_dump                                     │
│     └─ Verify database integrity                                │
│                                                                 │
│  4. Restore Library PVC                                         │
│     ├─ Create PVC                                               │
│     ├─ Restore photos/videos from backup                        │
│     └─ Verify file integrity                                    │
│                                                                 │
│  5. Restore Optional Components                                 │
│     ├─ Redis cache (optional, can skip)                         │
│     └─ ML model cache (optional, can skip)                      │
│                                                                 │
│  6. Deploy Immich                                               │
│     ├─ Install Helm chart                                       │
│     ├─ Wait for pods to be ready                                │
│     └─ Verify application health                                │
│                                                                 │
│  7. Post-Recovery Validation                                    │
│     ├─ Test web interface                                       │
│     ├─ Verify photo/video access                                │
│     ├─ Check user accounts and permissions                      │
│     └─ Validate ML functionality                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Step-by-Step Recovery

#### Step 1: Prepare Kubernetes Environment

```bash
# Set recovery variables
export RELEASE_NAME="immich"
export NAMESPACE="default"
export BACKUP_TIMESTAMP="20250115-143000"  # Adjust to your backup
export BACKUP_PATH="$BACKUP_DIR/$BACKUP_TIMESTAMP"

# Create namespace (if needed)
kubectl create namespace $NAMESPACE

# Restore database credentials secret
kubectl apply -f $BACKUP_PATH/config/secrets.yaml.gpg
```

#### Step 2: Restore Configuration

```bash
# Verify Helm values
cat $BACKUP_PATH/config/values.yaml

# Create custom values file for recovery
cp $BACKUP_PATH/config/values.yaml /tmp/immich-recovery-values.yaml
```

#### Step 3: Restore PostgreSQL Database

```bash
# Create empty database (if needed)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U postgres -c "CREATE DATABASE $POSTGRES_DB;"

# Restore from pg_dump
cat $BACKUP_PATH/postgresql/immich-db.dump | \
  kubectl exec -i -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_restore -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -v

# Verify database restoration
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt"
```

#### Step 4: Restore Library PVC

```bash
# Option A: Restore from tar backup
# Create PVC
helm install $RELEASE_NAME scripton-charts/immich -n $NAMESPACE \
  -f /tmp/immich-recovery-values.yaml \
  --set immich.server.enabled=false \
  --set immich.machineLearning.enabled=false

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${RELEASE_NAME}-library -n $NAMESPACE --timeout=300s

# Create restore helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immich-restore-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: library
      mountPath: /data
  volumes:
  - name: library
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-library
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/immich-restore-helper -n $NAMESPACE --timeout=120s

# Restore library data
cat $BACKUP_PATH/library/library.tar.gz | \
  kubectl exec -i -n $NAMESPACE immich-restore-helper -- \
  tar xzf - -C /

# Cleanup
kubectl delete pod immich-restore-helper -n $NAMESPACE

# Option B: Restore from Restic backup
# (Use same helper pod with Restic image, run restic restore)

# Option C: Restore from VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-library
  namespace: $NAMESPACE
spec:
  dataSource:
    name: immich-library-snapshot-20250115-143000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF
```

#### Step 5: Restore Optional Components

```bash
# Restore Redis (optional, can skip)
kubectl cp $BACKUP_PATH/redis/dump.rdb $NAMESPACE/redis-0:/data/dump.rdb
kubectl exec -n $NAMESPACE redis-0 -- redis-cli SHUTDOWN SAVE
kubectl delete pod redis-0 -n $NAMESPACE  # Will restart and load dump.rdb

# Restore ML cache (optional, can skip)
# If skipped, Immich will download models automatically on first use
cat $BACKUP_PATH/ml-cache/ml-cache.tar.gz | \
  kubectl exec -i -n $NAMESPACE immich-ml-restore-helper -- \
  tar xzf - -C /
```

#### Step 6: Deploy Immich

```bash
# Install or upgrade Helm release
helm upgrade --install $RELEASE_NAME scripton-charts/immich \
  -n $NAMESPACE \
  -f /tmp/immich-recovery-values.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=600s

# Check deployment status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
```

#### Step 7: Post-Recovery Validation

```bash
# Test database connectivity
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM assets;"

# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 2283:2283 &
curl -I http://localhost:2283

# Verify photo access (check random photo)
# Login to web UI at http://localhost:2283 and verify:
# - User accounts are present
# - Albums are visible
# - Photos and videos load correctly
# - Face recognition works (if using ML features)

# Check ML service
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-machine-learning-0 --tail=50
```

### 8.3 Makefile Targets

```bash
# Full recovery (interactive)
make -f make/ops/immich.mk immich-full-recovery

# Recovery validation
make -f make/ops/immich.mk immich-post-recovery-check
```

---

## Automated Backup Strategies

### 9.1 CronJob-Based Backup

**Note:** As per chart design principles, automated backup CronJobs are **NOT included** in the Helm chart. Use external scheduling tools (Kubernetes CronJob, cron, systemd timers, etc.).

#### Create Backup CronJob

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: immich-daily-backup
  namespace: $NAMESPACE
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: scripton/immich-backup:latest  # Custom image with backup tools
            env:
            - name: BACKUP_DIR
              value: "/backup"
            - name: S3_BUCKET
              value: "immich-backups"
            command:
            - /bin/bash
            - -c
            - |
              /scripts/immich-full-backup.sh
          restartPolicy: OnFailure
EOF
```

### 9.2 Velero Integration

[Velero](https://velero.io/) provides disaster recovery for Kubernetes clusters.

#### Install Velero

```bash
# Install Velero CLI
brew install velero  # macOS
# or download from https://github.com/vmware-tanzu/velero/releases

# Install Velero in cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket immich-velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=true \
  --backup-location-config region=us-east-1
```

#### Create Velero Backup

```bash
# Backup entire namespace
velero backup create immich-backup-$(date +%Y%m%d) \
  --include-namespaces $NAMESPACE \
  --wait

# Backup specific resources
velero backup create immich-backup-$(date +%Y%m%d) \
  --selector app.kubernetes.io/instance=$RELEASE_NAME \
  --include-namespaces $NAMESPACE \
  --wait

# Schedule daily backups
velero schedule create immich-daily \
  --schedule="0 2 * * *" \
  --include-namespaces $NAMESPACE
```

#### Restore with Velero

```bash
# List backups
velero backup get

# Restore from backup
velero restore create --from-backup immich-backup-20250115

# Restore to different namespace
velero restore create --from-backup immich-backup-20250115 \
  --namespace-mappings default:immich-recovery
```

### 9.3 External Backup Tools

#### Restic with systemd timer (Linux)

```bash
# Create systemd service
cat > /etc/systemd/system/immich-backup.service <<EOF
[Unit]
Description=Immich Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/immich-full-backup.sh
User=backup
Group=backup
EOF

# Create systemd timer
cat > /etc/systemd/system/immich-backup.timer <<EOF
[Unit]
Description=Immich Daily Backup Timer

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start timer
systemctl enable immich-backup.timer
systemctl start immich-backup.timer
```

---

## Backup Verification

### 10.1 Backup Integrity Checks

```bash
# Verify PostgreSQL backup
pg_restore --list $BACKUP_PATH/postgresql/immich-db.dump | wc -l

# Verify library backup checksums
cd $BACKUP_PATH/library
sha256sum -c checksums.sha256

# Verify Restic backup integrity
restic check
```

### 10.2 Test Restore (Dry Run)

```bash
# Create test namespace
kubectl create namespace immich-test

# Restore to test namespace
# (Follow disaster recovery procedures in test namespace)

# Verify test restoration
kubectl exec -n immich-test ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d immich_test -c "SELECT COUNT(*) FROM assets;"

# Cleanup test namespace
kubectl delete namespace immich-test
```

### 10.3 Makefile Targets

```bash
# Verify all backup components
make -f make/ops/immich.mk immich-verify-backup

# Test restore in separate namespace
make -f make/ops/immich.mk immich-test-restore
```

---

## Best Practices

### 11.1 Backup Frequency Recommendations

| Component | Recommended Frequency | Reason |
|-----------|----------------------|--------|
| Library PVC | Daily | Large data volume, high user impact |
| PostgreSQL DB | Daily | Critical metadata, frequent changes |
| Redis Cache | Weekly or skip | Can rebuild automatically |
| ML Model Cache | Monthly or skip | Can re-download from Immich servers |
| Configuration | On-change | Git-based versioning recommended |

### 11.2 3-2-1 Backup Rule

Follow the **3-2-1 backup rule**:
- **3 copies** of data (1 primary + 2 backups)
- **2 different media types** (local disk + cloud storage)
- **1 offsite backup** (different geographic location)

Example implementation:
```
Primary: Kubernetes PVC (local cluster)
Backup 1: NFS/local disk (same datacenter)
Backup 2: S3/cloud storage (different region)
```

### 11.3 Encryption

Always encrypt backups containing sensitive data:

```bash
# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 $BACKUP_PATH/postgresql/immich-db.dump

# Encrypt with OpenSSL
openssl enc -aes-256-cbc -salt -in immich-db.dump -out immich-db.dump.enc

# Restic uses encryption by default
export RESTIC_PASSWORD="your-secure-password"
```

### 11.4 Monitoring and Alerting

Monitor backup job success:

```bash
# Create Prometheus alert rule
groups:
- name: immich-backup
  rules:
  - alert: ImmichBackupFailed
    expr: time() - immich_last_successful_backup_timestamp > 86400
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "Immich backup failed or hasn't run in 24 hours"
```

### 11.5 Documentation

Maintain backup runbooks:

```
docs/
├── immich-backup-runbook.md       # Backup procedures
├── immich-recovery-runbook.md     # Recovery procedures
├── backup-schedules.md            # Backup schedules and retention
└── disaster-recovery-plan.md      # Full DR plan
```

---

## Troubleshooting

### 12.1 Common Issues

#### Issue: Backup Job Fails with "No space left on device"

**Cause:** Backup destination storage is full

**Solution:**
```bash
# Check backup destination storage
df -h $BACKUP_DIR

# Clean up old backups
find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# Increase storage allocation or change backup destination
export BACKUP_DIR="/mnt/large-storage/immich-backups"
```

#### Issue: pg_dump fails with "permission denied"

**Cause:** Insufficient PostgreSQL privileges

**Solution:**
```bash
# Grant backup privileges to user
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U postgres -c \
  "GRANT SELECT ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;"

# Or use postgres superuser for backup
export POSTGRES_USER="postgres"
```

#### Issue: Library PVC restore fails with "file already exists"

**Cause:** PVC is not empty before restore

**Solution:**
```bash
# Delete existing PVC and recreate
kubectl delete pvc ${RELEASE_NAME}-library -n $NAMESPACE
kubectl apply -f pvc-library.yaml

# Or clear PVC contents before restore
kubectl exec -n $NAMESPACE immich-restore-helper -- rm -rf /data/*
```

#### Issue: Restic backup extremely slow

**Cause:** Large number of small files, slow network

**Solution:**
```bash
# Use tar + Restic for better performance
tar czf - /data | restic backup --stdin --stdin-filename library.tar.gz

# Increase Restic parallelism
restic backup /data -o s3.connections=10

# Use local backup destination first, then sync to S3
restic backup /data --repo /local/backup
rclone sync /local/backup s3:immich-backups/restic
```

#### Issue: VolumeSnapshot not supported

**Cause:** CSI driver doesn't support snapshots

**Solution:**
```bash
# Check CSI driver capabilities
kubectl get csidriver

# Use alternative backup method (tar, Restic)
make -f make/ops/immich.mk immich-backup-library-restic

# Or upgrade to CSI driver with snapshot support
```

### 12.2 Recovery Failures

#### Issue: Database restore fails with "schema already exists"

**Cause:** Database is not empty

**Solution:**
```bash
# Drop and recreate database
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U postgres -c "DROP DATABASE $POSTGRES_DB;"
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U postgres -c "CREATE DATABASE $POSTGRES_DB;"

# Restore again
cat $BACKUP_PATH/postgresql/immich-db.dump | \
  kubectl exec -i -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_restore -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -v
```

#### Issue: Immich web UI shows "No photos found" after restore

**Cause:** Library PVC mount path mismatch, file permissions

**Solution:**
```bash
# Check PVC mount in deployment
kubectl get deployment ${RELEASE_NAME}-server -n $NAMESPACE -o yaml | grep -A5 volumeMounts

# Verify file ownership
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- ls -la /data

# Fix file ownership (if needed)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- chown -R 1000:1000 /data
```

### 12.3 Performance Issues

#### Issue: Backup takes too long (> 4 hours)

**Cause:** Large library PVC, slow storage

**Solution:**
```bash
# Use incremental backup (Restic)
restic backup /data  # Only backs up changed files

# Use VolumeSnapshot (near-instant)
make -f make/ops/immich.mk immich-snapshot-library

# Parallelize backups (backup DB and library simultaneously)
make -f make/ops/immich.mk immich-backup-db &
make -f make/ops/immich.mk immich-backup-library-restic &
wait
```

### 12.4 Makefile Targets

```bash
# Troubleshoot backup issues
make -f make/ops/immich.mk immich-troubleshoot-backup

# Check backup storage
make -f make/ops/immich.mk immich-check-backup-storage

# Verify backup integrity
make -f make/ops/immich.mk immich-verify-backup
```

---

## Summary

### Key Takeaways

1. **Backup Strategy**: Focus on Library PVC and PostgreSQL database (highest priority)
2. **RTO/RPO**: < 2 hours recovery time, 24-hour recovery point with daily backups
3. **Tools**: Use Restic for incremental backups, VolumeSnapshot for fastest backups
4. **Automation**: Use external CronJob or systemd timers (not in Helm chart)
5. **Verification**: Always verify backups and test recovery procedures
6. **3-2-1 Rule**: Keep 3 copies on 2 different media with 1 offsite

### Quick Reference

```bash
# Full backup
make -f make/ops/immich.mk immich-full-backup

# Full recovery
make -f make/ops/immich.mk immich-full-recovery

# Verify backup
make -f make/ops/immich.mk immich-verify-backup
```

### Related Documentation

- [Immich Upgrade Guide](immich-upgrade-guide.md)
- [Immich README](../charts/immich/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)

---

**Last Updated:** 2025-01-27
**Version:** 1.0.0
