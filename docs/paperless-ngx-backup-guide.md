# Paperless-ngx Backup Guide

This guide provides comprehensive backup and recovery procedures for Paperless-ngx deployed via the ScriptonBasestar Helm chart.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Prerequisites](#prerequisites)
- [Backup Procedures](#backup-procedures)
  - [1. Documents Backup](#1-documents-backup)
  - [2. PostgreSQL Database Backup](#2-postgresql-database-backup)
  - [3. Redis Backup](#3-redis-backup)
  - [4. Configuration Backup](#4-configuration-backup)
  - [5. PVC Snapshots](#5-pvc-snapshots)
- [Recovery Procedures](#recovery-procedures)
  - [Documents Recovery](#documents-recovery)
  - [Database Recovery](#database-recovery)
  - [Configuration Recovery](#configuration-recovery)
  - [Full Disaster Recovery](#full-disaster-recovery)
- [RTO/RPO Targets](#rtorpo-targets)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Paperless-ngx is a document management system that scans, indexes, and archives documents with OCR capabilities. A comprehensive backup strategy must cover:

1. **Documents** - PDF files, images, OCR data stored in PVCs
2. **Database** - PostgreSQL containing document metadata, tags, correspondents, custom fields
3. **Redis** - Task queue state and caching (optional, can be rebuilt)
4. **Configuration** - Kubernetes resources, Helm values, application settings
5. **PVC Snapshots** - Volume-level backups for disaster recovery

This guide focuses on **production-ready procedures** using the Makefile targets provided with the chart.

---

## Backup Strategy

### Component Overview

| Component | Backup Method | Frequency | Priority | Recovery Time |
|-----------|--------------|-----------|----------|---------------|
| **Documents (PVCs)** | tar/rsync + PVC snapshots | Daily | **CRITICAL** | 30-60 min |
| **PostgreSQL DB** | pg_dump | Daily | **CRITICAL** | 15-30 min |
| **Redis Cache** | RDB snapshots | Optional | LOW | 5-10 min (rebuild) |
| **Configuration** | Kubernetes manifests + Helm values | On change | HIGH | 10-15 min |
| **PVC Snapshots** | VolumeSnapshot API | Daily | **CRITICAL** | 1-2 hours |

### RTO/RPO Targets

- **RTO (Recovery Time Objective)**: < 2 hours (full disaster recovery)
- **RPO (Recovery Point Objective)**: 24 hours (daily backups)

---

## Prerequisites

### Required Tools

```bash
# 1. Kubernetes CLI
kubectl version --client

# 2. Helm
helm version

# 3. PostgreSQL client (for database backups)
psql --version

# 4. Redis CLI (optional, for cache backups)
redis-cli --version

# 5. Storage utilities (tar, rsync)
tar --version
rsync --version
```

### Required Access

- Kubernetes cluster access with appropriate RBAC permissions
- PostgreSQL database credentials (from Kubernetes Secret)
- Redis credentials (if password-protected)
- Storage credentials (for off-cluster backups to S3/MinIO/NFS)

### Environment Variables

```bash
# Helm release name
export RELEASE_NAME="paperless-ngx"

# Namespace
export NAMESPACE="default"

# Backup destination (adjust to your storage)
export BACKUP_DIR="/mnt/backups/paperless-ngx"
export S3_BUCKET="s3://backups/paperless-ngx"

# Timestamp for backup files
export BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
```

---

## Backup Procedures

### 1. Documents Backup

Paperless-ngx stores documents in multiple PVCs: consume, data, media, and export directories.

#### 1.1. Backup All Document PVCs (tar method)

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-documents
```

**Manual Procedure:**
```bash
# 1. Get pod name
export POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}')

# 2. Create backup directory
mkdir -p $BACKUP_DIR/$BACKUP_TIMESTAMP

# 3. Backup consume directory (incoming documents)
kubectl exec -n $NAMESPACE $POD -- tar czf - /usr/src/paperless/consume \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/consume.tar.gz

# 4. Backup data directory (application data, search index)
kubectl exec -n $NAMESPACE $POD -- tar czf - /usr/src/paperless/data \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/data.tar.gz

# 5. Backup media directory (processed documents, thumbnails, OCR)
kubectl exec -n $NAMESPACE $POD -- tar czf - /usr/src/paperless/media \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/media.tar.gz

# 6. Backup export directory (exported documents)
kubectl exec -n $NAMESPACE $POD -- tar czf - /usr/src/paperless/export \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/export.tar.gz

# 7. Verify backups
ls -lh $BACKUP_DIR/$BACKUP_TIMESTAMP/*.tar.gz
```

**Expected Output:**
```
-rw-r--r-- 1 user user  512M Dec  8 10:00 consume.tar.gz
-rw-r--r-- 1 user user  256M Dec  8 10:05 data.tar.gz
-rw-r--r-- 1 user user   2.5G Dec  8 10:15 media.tar.gz
-rw-r--r-- 1 user user  128M Dec  8 10:20 export.tar.gz
```

#### 1.2. Incremental Backup with rsync

For large document collections, use rsync for incremental backups:

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-documents-incremental
```

**Manual Procedure:**
```bash
# 1. Enable SSH access to pod (if not already configured)
# This requires a sidecar container or kubectl port-forward

# 2. Sync consume directory
kubectl exec -n $NAMESPACE $POD -- sh -c "cd /usr/src/paperless && tar cf - consume" | \
  tar xf - -C $BACKUP_DIR/$BACKUP_TIMESTAMP/

# 3. Sync data directory
kubectl exec -n $NAMESPACE $POD -- sh -c "cd /usr/src/paperless && tar cf - data" | \
  tar xf - -C $BACKUP_DIR/$BACKUP_TIMESTAMP/

# 4. Sync media directory (largest, most important)
kubectl exec -n $NAMESPACE $POD -- sh -c "cd /usr/src/paperless && tar cf - media" | \
  tar xf - -C $BACKUP_DIR/$BACKUP_TIMESTAMP/

# 5. Sync export directory
kubectl exec -n $NAMESPACE $POD -- sh -c "cd /usr/src/paperless && tar cf - export" | \
  tar xf - -C $BACKUP_DIR/$BACKUP_TIMESTAMP/
```

#### 1.3. Backup to S3/MinIO

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-documents-s3
```

**Manual Procedure:**
```bash
# 1. Install AWS CLI or MinIO client (mc)
# For AWS S3:
aws configure

# For MinIO:
mc alias set myminio https://minio.example.com ACCESS_KEY SECRET_KEY

# 2. Upload backups to S3
aws s3 cp $BACKUP_DIR/$BACKUP_TIMESTAMP/consume.tar.gz \
  $S3_BUCKET/$BACKUP_TIMESTAMP/consume.tar.gz

aws s3 cp $BACKUP_DIR/$BACKUP_TIMESTAMP/data.tar.gz \
  $S3_BUCKET/$BACKUP_TIMESTAMP/data.tar.gz

aws s3 cp $BACKUP_DIR/$BACKUP_TIMESTAMP/media.tar.gz \
  $S3_BUCKET/$BACKUP_TIMESTAMP/media.tar.gz

aws s3 cp $BACKUP_DIR/$BACKUP_TIMESTAMP/export.tar.gz \
  $S3_BUCKET/$BACKUP_TIMESTAMP/export.tar.gz

# 3. Verify uploads
aws s3 ls $S3_BUCKET/$BACKUP_TIMESTAMP/
```

---

### 2. PostgreSQL Database Backup

The PostgreSQL database contains document metadata, tags, correspondents, document types, custom fields, and user data.

#### 2.1. Full Database Backup

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-database
```

**Manual Procedure:**
```bash
# 1. Get PostgreSQL credentials from Secret
export POSTGRES_HOST=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBHOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBPORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBNAME}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBUSER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBPASS}' | base64 -d)

# 2. Create backup directory
mkdir -p $BACKUP_DIR/$BACKUP_TIMESTAMP

# 3. Run pg_dump via kubectl exec
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --format=custom --compress=9 --verbose" \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump

# 4. Verify backup
ls -lh $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump
pg_restore --list $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump | head -20
```

**Expected Output:**
```
-rw-r--r-- 1 user user 128M Dec  8 10:30 paperless-db.dump
```

#### 2.2. Plain SQL Backup (for version control)

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-database-sql
```

**Manual Procedure:**
```bash
# 1. Create plain SQL backup (easier to diff/version control)
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --format=plain --no-owner --no-privileges --clean --if-exists" \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.sql

# 2. Compress SQL backup
gzip $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.sql

# 3. Verify backup
ls -lh $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.sql.gz
zcat $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.sql.gz | head -50
```

#### 2.3. Schema-Only Backup

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-database-schema
```

**Manual Procedure:**
```bash
# Backup schema only (useful for testing recovery procedures)
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --schema-only --format=plain" \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db-schema.sql

# Verify schema backup
head -100 $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db-schema.sql
```

---

### 3. Redis Backup

Redis stores task queue state and caching data. This is **optional** as Redis can be rebuilt from the database.

#### 3.1. Redis RDB Snapshot

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-redis
```

**Manual Procedure:**
```bash
# 1. Get Redis credentials
export REDIS_HOST=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_REDIS}' | base64 -d | sed 's|redis://||' | cut -d'@' -f2 | cut -d'/' -f1 | cut -d':' -f1)
export REDIS_PORT=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_REDIS}' | base64 -d | sed 's|redis://||' | cut -d'@' -f2 | cut -d'/' -f1 | cut -d':' -f2)
export REDIS_PASSWORD=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_REDIS}' | base64 -d | sed 's|redis://||' | cut -d'@' -f1 | cut -d':' -f2)

# 2. Trigger Redis BGSAVE
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "redis-cli -h $REDIS_HOST -p $REDIS_PORT -a '$REDIS_PASSWORD' BGSAVE"

# 3. Wait for BGSAVE to complete
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "redis-cli -h $REDIS_HOST -p $REDIS_PORT -a '$REDIS_PASSWORD' LASTSAVE"

# 4. Copy RDB file (requires access to Redis pod)
# Note: This assumes Redis is accessible via a pod in the cluster
REDIS_POD=$(kubectl get pod -n $NAMESPACE -l app=redis -o jsonpath='{.items[0].metadata.name}')
kubectl cp -n $NAMESPACE $REDIS_POD:/data/dump.rdb \
  $BACKUP_DIR/$BACKUP_TIMESTAMP/redis-dump.rdb

# 5. Verify backup
ls -lh $BACKUP_DIR/$BACKUP_TIMESTAMP/redis-dump.rdb
```

**Note**: Redis backup is optional. If Redis is lost, Paperless-ngx will rebuild the task queue from the database.

---

### 4. Configuration Backup

Backup Kubernetes manifests, Helm values, and application configuration.

#### 4.1. Backup Helm Values

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-helm-values
```

**Manual Procedure:**
```bash
# 1. Export current Helm values
helm get values -n $NAMESPACE $RELEASE_NAME > $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml

# 2. Export full Helm release manifest
helm get manifest -n $NAMESPACE $RELEASE_NAME > $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-manifest.yaml

# 3. Verify backups
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml
```

#### 4.2. Backup Kubernetes Resources

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-backup-k8s-resources
```

**Manual Procedure:**
```bash
# 1. Backup Deployment
kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/deployment.yaml

# 2. Backup Service
kubectl get service -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/service.yaml

# 3. Backup ConfigMaps
kubectl get configmap -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/configmaps.yaml

# 4. Backup Secrets (encrypted storage recommended)
kubectl get secret -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/secrets.yaml

# 5. Backup PVCs
kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/pvcs.yaml

# 6. Backup ServiceAccount and RBAC
kubectl get serviceaccount -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/serviceaccount.yaml
kubectl get role -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx-role -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/role.yaml
kubectl get rolebinding -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx-rolebinding -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/rolebinding.yaml

# 7. Encrypt secrets backup (recommended)
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/$BACKUP_TIMESTAMP/secrets.yaml
rm $BACKUP_DIR/$BACKUP_TIMESTAMP/secrets.yaml  # Remove unencrypted file
```

---

### 5. PVC Snapshots

Use Kubernetes VolumeSnapshot API for volume-level backups (requires CSI driver support).

#### 5.1. Create VolumeSnapshots

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-create-pvc-snapshots
```

**Manual Procedure:**
```bash
# 1. Check if VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# 2. Create snapshot for consume PVC
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${RELEASE_NAME}-consume-snapshot-${BACKUP_TIMESTAMP}
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass  # Adjust to your VolumeSnapshotClass
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-consume
EOF

# 3. Create snapshot for data PVC
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${RELEASE_NAME}-data-snapshot-${BACKUP_TIMESTAMP}
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-data
EOF

# 4. Create snapshot for media PVC
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${RELEASE_NAME}-media-snapshot-${BACKUP_TIMESTAMP}
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-media
EOF

# 5. Create snapshot for export PVC
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${RELEASE_NAME}-export-snapshot-${BACKUP_TIMESTAMP}
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-export
EOF

# 6. Verify snapshots
kubectl get volumesnapshot -n $NAMESPACE
```

**Expected Output:**
```
NAME                                      READYTOUSE   SOURCEPVC               RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                                    CREATIONTIME   AGE
paperless-ngx-consume-snapshot-20241208   true         paperless-ngx-consume   10Gi          csi-snapclass   snapcontent-xxx                                    2m             2m
paperless-ngx-data-snapshot-20241208      true         paperless-ngx-data      10Gi          csi-snapclass   snapcontent-yyy                                    2m             2m
paperless-ngx-media-snapshot-20241208     true         paperless-ngx-media     50Gi          csi-snapclass   snapcontent-zzz                                    2m             2m
paperless-ngx-export-snapshot-20241208    true         paperless-ngx-export    10Gi          csi-snapclass   snapcontent-www                                    2m             2m
```

#### 5.2. Backup Snapshot Metadata

```bash
# Export snapshot definitions
kubectl get volumesnapshot -n $NAMESPACE -o yaml \
  > $BACKUP_DIR/$BACKUP_TIMESTAMP/volumesnapshots.yaml
```

---

## Recovery Procedures

### Documents Recovery

#### Restore from tar Backup

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-restore-documents BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# 1. Get pod name
export POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}')

# 2. Restore consume directory
kubectl exec -n $NAMESPACE $POD -- sh -c "rm -rf /usr/src/paperless/consume/*"
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/consume.tar.gz | \
  kubectl exec -n $NAMESPACE $POD -i -- tar xzf - -C /

# 3. Restore data directory
kubectl exec -n $NAMESPACE $POD -- sh -c "rm -rf /usr/src/paperless/data/*"
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/data.tar.gz | \
  kubectl exec -n $NAMESPACE $POD -i -- tar xzf - -C /

# 4. Restore media directory
kubectl exec -n $NAMESPACE $POD -- sh -c "rm -rf /usr/src/paperless/media/*"
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/media.tar.gz | \
  kubectl exec -n $NAMESPACE $POD -i -- tar xzf - -C /

# 5. Restore export directory
kubectl exec -n $NAMESPACE $POD -- sh -c "rm -rf /usr/src/paperless/export/*"
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/export.tar.gz | \
  kubectl exec -n $NAMESPACE $POD -i -- tar xzf - -C /

# 6. Fix permissions
kubectl exec -n $NAMESPACE $POD -- chown -R 1000:1000 /usr/src/paperless/consume
kubectl exec -n $NAMESPACE $POD -- chown -R 1000:1000 /usr/src/paperless/data
kubectl exec -n $NAMESPACE $POD -- chown -R 1000:1000 /usr/src/paperless/media
kubectl exec -n $NAMESPACE $POD -- chown -R 1000:1000 /usr/src/paperless/export

# 7. Restart pod to reload data
kubectl delete pod -n $NAMESPACE $POD
```

---

### Database Recovery

#### Restore from pg_dump Backup

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-restore-database BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# 1. Get PostgreSQL credentials
export POSTGRES_HOST=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBHOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBPORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBNAME}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBUSER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_DBPASS}' | base64 -d)

# 2. Scale down Paperless-ngx (prevent writes during restore)
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=0

# 3. Drop and recreate database
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d postgres \
  -c 'DROP DATABASE IF EXISTS $POSTGRES_DB;'"

kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d postgres \
  -c 'CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;'"

# 4. Restore database from backup
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump | \
  kubectl exec -n $NAMESPACE $POD -i -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_restore -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --clean --if-exists --no-owner --no-privileges --verbose"

# 5. Verify restore
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"

# 6. Scale up Paperless-ngx
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=1

# 7. Wait for pod to be ready
kubectl wait pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --for=condition=Ready --timeout=300s
```

---

### Configuration Recovery

#### Restore Helm Release

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-restore-helm-values BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# 1. Restore Helm release using backed-up values
helm upgrade --install $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  -f $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml

# 2. Verify deployment
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx
```

---

### Full Disaster Recovery

Complete recovery from catastrophic failure (cluster loss, namespace deletion, etc.).

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-full-recovery BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# Step 1: Recreate namespace (if deleted)
kubectl create namespace $NAMESPACE

# Step 2: Restore Secrets (decrypt if encrypted)
gpg --decrypt $BACKUP_DIR/$BACKUP_TIMESTAMP/secrets.yaml.gpg | kubectl apply -f -

# Step 3: Restore PVCs from VolumeSnapshots
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-consume
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-consume-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-data
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-data-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-media
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-media-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-export
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-export-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Step 4: Wait for PVCs to be bound
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-consume --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-data --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-media --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-export --for=jsonpath='{.status.phase}'=Bound --timeout=300s

# Step 5: Restore Helm release
helm upgrade --install $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  -f $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml

# Step 6: Wait for deployment to be ready
kubectl wait deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --for=condition=Available --timeout=600s

# Step 7: Restore database (if PVC restore didn't include database)
# Follow "Database Recovery" procedure above

# Step 8: Verify recovery
export POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"

# Step 9: Verify documents are accessible
kubectl exec -n $NAMESPACE $POD -- ls -l /usr/src/paperless/media/documents/originals/ | head -20

# Step 10: Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-paperless-ngx 8000:8000
# Access http://localhost:8000 in browser
```

**Recovery Time**: 1-2 hours (depending on data volume and network speed)

---

## RTO/RPO Targets

### Recovery Time Objective (RTO)

| Scenario | RTO | Notes |
|----------|-----|-------|
| **Document Recovery** | 30-60 minutes | Restore from tar backup |
| **Database Recovery** | 15-30 minutes | Restore from pg_dump |
| **Configuration Recovery** | 10-15 minutes | Restore Helm values |
| **Full Disaster Recovery** | 1-2 hours | Complete cluster rebuild + data restore |

### Recovery Point Objective (RPO)

| Component | RPO | Backup Frequency |
|-----------|-----|------------------|
| **Documents** | 24 hours | Daily |
| **Database** | 24 hours | Daily |
| **Configuration** | On change | After each configuration change |
| **PVC Snapshots** | 24 hours | Daily |

---

## Best Practices

### 1. Backup Frequency

```bash
# Automated daily backups via CronJob (example)
# Add to your cluster automation:

# Daily full backup at 2 AM
0 2 * * * /path/to/scripts/paperless-full-backup.sh

# Weekly off-cluster backup to S3 (Sunday 3 AM)
0 3 * * 0 /path/to/scripts/paperless-backup-s3.sh
```

### 2. Backup Retention

```bash
# Keep backups according to 3-2-1 rule:
# - 3 copies of data
# - 2 different media types
# - 1 off-site copy

# Example retention policy:
# - Daily backups: Keep last 7 days
# - Weekly backups: Keep last 4 weeks
# - Monthly backups: Keep last 12 months

# Cleanup old backups (example script)
find $BACKUP_DIR -type d -name "202*" -mtime +7 -exec rm -rf {} \;  # Daily
find $BACKUP_DIR -type d -name "202*" -mtime +28 -exec rm -rf {} \; # Weekly
```

### 3. Backup Validation

```bash
# Test recovery procedure monthly
# 1. Restore to test namespace
export NAMESPACE="paperless-test"
make -f make/ops/paperless-ngx.mk paperless-full-recovery BACKUP_DATE=<latest>

# 2. Verify document count matches production
kubectl exec -n paperless-test $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"

# 3. Cleanup test namespace
kubectl delete namespace paperless-test
```

### 4. Security

```bash
# Encrypt backups containing sensitive documents
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/$BACKUP_TIMESTAMP/media.tar.gz
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump

# Use separate encryption keys for different backup types
# Store keys in secure vault (HashiCorp Vault, AWS Secrets Manager, etc.)
```

### 5. Monitoring

```bash
# Monitor backup success/failure
# Add alerting for:
# - Backup job failures
# - Backup size anomalies (too small = incomplete backup)
# - Old backups (RPO violation)

# Example Prometheus alerting rule:
# - alert: PaperlessBackupFailed
#   expr: paperless_backup_last_success_timestamp < (time() - 86400)
#   annotations:
#     summary: "Paperless backup failed or not run in 24 hours"
```

---

## Troubleshooting

### Issue 1: Backup Fails with "No space left on device"

**Symptoms:**
```
tar: /usr/src/paperless/media: Cannot write: No space left on device
```

**Solution:**
```bash
# 1. Check disk usage
kubectl exec -n $NAMESPACE $POD -- df -h

# 2. Use external backup destination (S3/NFS)
make -f make/ops/paperless-ngx.mk paperless-backup-documents-s3

# 3. Increase PVC size if needed
kubectl patch pvc -n $NAMESPACE ${RELEASE_NAME}-media -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### Issue 2: Database Restore Fails with "role does not exist"

**Symptoms:**
```
pg_restore: error: could not execute query: ERROR:  role "paperless" does not exist
```

**Solution:**
```bash
# 1. Use --no-owner flag when restoring
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump | \
  kubectl exec -n $NAMESPACE $POD -i -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_restore -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --clean --if-exists --no-owner --no-privileges"

# 2. Or create the role before restore
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U postgres \
  -c 'CREATE ROLE paperless WITH LOGIN PASSWORD \"changeme\";'"
```

### Issue 3: PVC Snapshot Restore Fails

**Symptoms:**
```
Error: VolumeSnapshotContent not ready
```

**Solution:**
```bash
# 1. Check VolumeSnapshot status
kubectl get volumesnapshot -n $NAMESPACE ${RELEASE_NAME}-media-snapshot-${BACKUP_TIMESTAMP} -o yaml

# 2. Check VolumeSnapshotContent status
kubectl get volumesnapshotcontent -o yaml

# 3. Verify CSI driver supports snapshots
kubectl get csidriver

# 4. Check storage class supports volume expansion
kubectl get storageclass -o yaml
```

### Issue 4: Documents Not Appearing After Restore

**Symptoms:**
- Database restored successfully
- Documents missing from web interface

**Solution:**
```bash
# 1. Verify media files exist
kubectl exec -n $NAMESPACE $POD -- ls -l /usr/src/paperless/media/documents/originals/ | head -20

# 2. Rebuild search index
kubectl exec -n $NAMESPACE $POD -- python manage.py document_index reindex

# 3. Check permissions
kubectl exec -n $NAMESPACE $POD -- ls -ld /usr/src/paperless/media
# Should be: drwxr-xr-x 1000:1000

# 4. Fix permissions if needed
kubectl exec -n $NAMESPACE $POD -- chown -R 1000:1000 /usr/src/paperless/media

# 5. Restart pod
kubectl delete pod -n $NAMESPACE $POD
```

### Issue 5: Redis Connection Errors After Restore

**Symptoms:**
```
Error: Could not connect to Redis at redis-service:6379
```

**Solution:**
```bash
# 1. Verify Redis is running
kubectl get pods -n $NAMESPACE -l app=redis

# 2. Test Redis connection
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "redis-cli -h $REDIS_HOST -p $REDIS_PORT -a '$REDIS_PASSWORD' PING"

# 3. Check Redis credentials in Secret
kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o jsonpath='{.data.PAPERLESS_REDIS}' | base64 -d

# 4. Redis is optional - Paperless-ngx can run without it
# If Redis is unavailable, tasks will be processed synchronously
```

---

## Summary

This guide provides comprehensive backup and recovery procedures for Paperless-ngx. Key takeaways:

1. **4-Layer Backup Strategy**: Documents, Database, Redis (optional), Configuration, PVC Snapshots
2. **RTO < 2 hours**: Full disaster recovery can be completed within 2 hours
3. **RPO 24 hours**: Daily backups provide 24-hour recovery point objective
4. **Makefile Automation**: All procedures available via `make -f make/ops/paperless-ngx.mk` targets
5. **Testing**: Validate recovery procedures monthly in test namespace

**Next Steps:**
- Set up automated daily backups
- Configure off-cluster backup storage (S3/MinIO)
- Test disaster recovery procedure
- Implement backup monitoring and alerting
- Document organization-specific backup policies

For upgrade procedures, see [Paperless-ngx Upgrade Guide](paperless-ngx-upgrade-guide.md).
