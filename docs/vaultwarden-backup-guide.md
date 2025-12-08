# Vaultwarden Backup and Recovery Guide

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Data Directory Backup](#1-data-directory-backup)
  - [2. Database Backup](#2-database-backup)
  - [3. Configuration Backup](#3-configuration-backup)
  - [4. PVC Snapshot Backup](#4-pvc-snapshot-backup)
- [Recovery Procedures](#recovery-procedures)
  - [Data Directory Recovery](#data-directory-recovery)
  - [Database Recovery](#database-recovery)
  - [Configuration Recovery](#configuration-recovery)
  - [Full Disaster Recovery](#full-disaster-recovery)
- [Backup Automation](#backup-automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for backing up and recovering Vaultwarden instances deployed via the Helm chart.

**Backup Philosophy:**
- **Multi-layered approach**: Data directory, database, configuration, PVC snapshots
- **Granular recovery**: Restore individual components or complete instance
- **Minimal downtime**: Most backups can be performed without service interruption
- **Database flexibility**: Supports both SQLite (default) and PostgreSQL/MySQL backends
- **Encryption-aware**: Vault data is encrypted at rest, backups preserve encrypted state

**Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO):**
- **RTO Target**: < 1 hour for complete Vaultwarden instance recovery
- **RPO Target**: 24 hours (daily backups recommended, hourly for critical deployments)
- **Data Directory Recovery**: < 30 minutes (via rsync/tar restore)
- **Database Recovery**: < 15 minutes (SQLite copy or PostgreSQL restore)
- **Configuration Recovery**: < 10 minutes (via ConfigMap restore)

---

## Backup Strategy

Vaultwarden backup strategy consists of four complementary components:

### 1. **Data Directory Backup**
- **What**: Vault database (SQLite), attachments, icons, RSA keys, sends
- **Why**: Core vault data and user attachments
- **Frequency**: Hourly or daily (depending on criticality)
- **Method**: rsync (incremental) or tar (full)
- **Size**: Small to medium (MB to GB, depending on attachments)
- **Priority**: **CRITICAL** (contains all vault data in SQLite mode)

### 2. **Database Backup (PostgreSQL/MySQL mode)**
- **What**: Vault metadata, user accounts, items, attachments metadata
- **Why**: Relational database when not using SQLite
- **Frequency**: Daily (hourly for critical deployments)
- **Method**: pg_dump (PostgreSQL) or mysqldump (MySQL)
- **Size**: Small to medium (MB to GB)
- **Priority**: **CRITICAL** (when using external database)

### 3. **Configuration Backup**
- **What**: Kubernetes resources, environment variables, Vaultwarden config
- **Why**: Deployment configuration and secrets
- **Frequency**: On every configuration change
- **Method**: kubectl export, ConfigMap export
- **Size**: Very small (KB)
- **Priority**: **HIGH** (required for deployment)

### 4. **PVC Snapshot Backup**
- **What**: Point-in-time snapshots of data PVC
- **Why**: Fast disaster recovery and storage-level consistency
- **Frequency**: Weekly (via VolumeSnapshot API)
- **Method**: Kubernetes VolumeSnapshot API
- **Size**: Same as data directory
- **Priority**: **MEDIUM** (disaster recovery only)

**Backup Component Summary:**

| Component | Priority | Frequency | Method | RTO | Size |
|-----------|----------|-----------|--------|-----|------|
| Data Directory | **CRITICAL** | Hourly/Daily | rsync/tar | 30 min | MB-GB |
| Database (External) | **CRITICAL** | Daily | pg_dump/mysqldump | 15 min | MB-GB |
| Configuration | HIGH | On change | kubectl | 10 min | KB |
| PVC Snapshots | MEDIUM | Weekly | VolumeSnapshot | 30 min | MB-GB |

---

## Backup Components

### 1. Data Directory Backup

The data directory (`/data`) contains all Vaultwarden vault data when using SQLite mode, or attachments/icons when using external database.

**Directory Structure:**
```
/data/
├── db.sqlite3           # Vault database (SQLite mode only)
├── db.sqlite3-shm       # SQLite shared memory (runtime)
├── db.sqlite3-wal       # SQLite write-ahead log (runtime)
├── attachments/         # File attachments uploaded by users
├── sends/               # Temporary file shares (Send feature)
├── tmp/                 # Temporary files
├── icon_cache/          # Website icons cache
└── rsa_key.{pem,pub}    # RSA keys for JWT signing
```

#### 1.1 Full Data Directory Backup (tar)

**Use Case**: Complete backup, initial backups, disaster recovery preparation

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="/tmp/vaultwarden-backups"
BACKUP_FILE="vaultwarden-data-full-$(date +%Y%m%d-%H%M%S).tar.gz"

# 2. Create backup directory
mkdir -p $BACKUP_DIR

# 3. Create tar archive of data directory
kubectl exec -n $NAMESPACE $POD_NAME -- tar czf - /data > $BACKUP_DIR/$BACKUP_FILE

# 4. Verify backup
tar tzf $BACKUP_DIR/$BACKUP_FILE | head -20

# 5. Record backup metadata
echo "Backup created: $BACKUP_FILE" >> $BACKUP_DIR/backup.log
echo "Timestamp: $(date -Iseconds)" >> $BACKUP_DIR/backup.log
echo "Pod: $POD_NAME" >> $BACKUP_DIR/backup.log
echo "Size: $(du -h $BACKUP_DIR/$BACKUP_FILE | cut -f1)" >> $BACKUP_DIR/backup.log
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-data-full
```

#### 1.2 Incremental Data Directory Backup (rsync)

**Use Case**: Daily backups, minimal storage usage, fast backups

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="/tmp/vaultwarden-backups/incremental"
DATE=$(date +%Y%m%d-%H%M%S)

# 2. Create backup directory structure
mkdir -p $BACKUP_DIR/{current,snapshots}

# 3. Incremental backup using rsync
kubectl exec -n $NAMESPACE $POD_NAME -- tar czf - /data | tar xzf - -C $BACKUP_DIR/tmp
rsync -av --delete --link-dest=$BACKUP_DIR/current \
  $BACKUP_DIR/tmp/data/ \
  $BACKUP_DIR/snapshots/$DATE/

# 4. Update current pointer
rm -rf $BACKUP_DIR/current
ln -s $BACKUP_DIR/snapshots/$DATE $BACKUP_DIR/current

# 5. Cleanup old snapshots (keep last 30 days)
find $BACKUP_DIR/snapshots -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \;
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-data-incremental
```

#### 1.3 SQLite Database Backup (SQLite mode only)

**Use Case**: Database-only backup, faster than full data backup

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="/tmp/vaultwarden-backups"
BACKUP_FILE="vaultwarden-sqlite-$(date +%Y%m%d-%H%M%S).db"

# 2. Create backup directory
mkdir -p $BACKUP_DIR

# 3. Copy SQLite database using .backup command (ensures consistency)
kubectl exec -n $NAMESPACE $POD_NAME -- sqlite3 /data/db.sqlite3 ".backup /tmp/backup.db"
kubectl cp $NAMESPACE/$POD_NAME:/tmp/backup.db $BACKUP_DIR/$BACKUP_FILE

# 4. Cleanup temporary file
kubectl exec -n $NAMESPACE $POD_NAME -- rm /tmp/backup.db

# 5. Verify backup
sqlite3 $BACKUP_DIR/$BACKUP_FILE "PRAGMA integrity_check;"
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-sqlite
```

**⚠️ Important Notes:**
- **Never copy `db.sqlite3` directly** while Vaultwarden is running - use `.backup` command or stop service first
- **Include WAL files** (`db.sqlite3-wal`, `db.sqlite3-shm`) if copying directly after stopping service
- **Test restore** regularly to ensure backup integrity

---

### 2. Database Backup (PostgreSQL/MySQL mode)

When using external PostgreSQL or MySQL database, vault data is stored in relational tables.

#### 2.1 PostgreSQL Database Backup

**Procedure:**

```bash
# 1. Set variables (from values.yaml)
PG_HOST="postgres-service.default.svc.cluster.local"
PG_PORT="5432"
PG_DATABASE="vaultwarden"
PG_USERNAME="vaultwarden"
PG_PASSWORD="<your-password>"
BACKUP_DIR="/tmp/vaultwarden-backups"
BACKUP_FILE="vaultwarden-pg-$(date +%Y%m%d-%H%M%S).sql.gz"

# 2. Create backup directory
mkdir -p $BACKUP_DIR

# 3. Create PostgreSQL dump
PGPASSWORD=$PG_PASSWORD pg_dump \
  -h $PG_HOST \
  -p $PG_PORT \
  -U $PG_USERNAME \
  -d $PG_DATABASE \
  --format=custom \
  --compress=9 \
  --verbose \
  --file=$BACKUP_DIR/$BACKUP_FILE

# 4. Verify backup
pg_restore --list $BACKUP_DIR/$BACKUP_FILE | head -20

# 5. Record backup metadata
echo "PostgreSQL Backup: $BACKUP_FILE" >> $BACKUP_DIR/backup.log
echo "Timestamp: $(date -Iseconds)" >> $BACKUP_DIR/backup.log
echo "Database: $PG_DATABASE" >> $BACKUP_DIR/backup.log
echo "Size: $(du -h $BACKUP_DIR/$BACKUP_FILE | cut -f1)" >> $BACKUP_DIR/backup.log
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-postgres
```

#### 2.2 MySQL Database Backup

**Procedure:**

```bash
# 1. Set variables (from values.yaml)
MYSQL_HOST="mysql-service.default.svc.cluster.local"
MYSQL_PORT="3306"
MYSQL_DATABASE="vaultwarden"
MYSQL_USERNAME="vaultwarden"
MYSQL_PASSWORD="<your-password>"
BACKUP_DIR="/tmp/vaultwarden-backups"
BACKUP_FILE="vaultwarden-mysql-$(date +%Y%m%d-%H%M%S).sql.gz"

# 2. Create backup directory
mkdir -p $BACKUP_DIR

# 3. Create MySQL dump
mysqldump \
  -h $MYSQL_HOST \
  -P $MYSQL_PORT \
  -u $MYSQL_USERNAME \
  -p$MYSQL_PASSWORD \
  --databases $MYSQL_DATABASE \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  | gzip > $BACKUP_DIR/$BACKUP_FILE

# 4. Verify backup
gunzip -c $BACKUP_DIR/$BACKUP_FILE | head -50

# 5. Record backup metadata
echo "MySQL Backup: $BACKUP_FILE" >> $BACKUP_DIR/backup.log
echo "Timestamp: $(date -Iseconds)" >> $BACKUP_DIR/backup.log
echo "Database: $MYSQL_DATABASE" >> $BACKUP_DIR/backup.log
echo "Size: $(du -h $BACKUP_DIR/$BACKUP_FILE | cut -f1)" >> $BACKUP_DIR/backup.log
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-mysql
```

---

### 3. Configuration Backup

Backup Kubernetes resources and Vaultwarden configuration.

#### 3.1 Kubernetes Resources Backup

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
BACKUP_DIR="/tmp/vaultwarden-backups"
CONFIG_BACKUP_DIR="$BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S)"

# 2. Create backup directory
mkdir -p $CONFIG_BACKUP_DIR

# 3. Export all Vaultwarden resources
kubectl get deployment,statefulset,service,ingress,configmap,secret,pvc,serviceaccount \
  -n $NAMESPACE \
  -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" \
  -o yaml > $CONFIG_BACKUP_DIR/vaultwarden-resources.yaml

# 4. Export Helm values
helm get values $RELEASE_NAME -n $NAMESPACE > $CONFIG_BACKUP_DIR/values.yaml

# 5. Export Helm release manifest
helm get manifest $RELEASE_NAME -n $NAMESPACE > $CONFIG_BACKUP_DIR/manifest.yaml

# 6. Create backup archive
tar czf $BACKUP_DIR/vaultwarden-config-$(date +%Y%m%d-%H%M%S).tar.gz -C $CONFIG_BACKUP_DIR .

# 7. List backup contents
tar tzf $BACKUP_DIR/vaultwarden-config-*.tar.gz
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-backup-config
```

#### 3.2 Environment Variables Backup

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="/tmp/vaultwarden-backups"

# 2. Export environment variables (sanitize sensitive data)
kubectl exec -n $NAMESPACE $POD_NAME -- env | grep -E '^(DATABASE_URL|SMTP_|ADMIN_TOKEN|DOMAIN)' > $BACKUP_DIR/vaultwarden-env-$(date +%Y%m%d-%H%M%S).txt

# ⚠️ WARNING: This file contains sensitive data - encrypt before storing
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/vaultwarden-env-*.txt
rm $BACKUP_DIR/vaultwarden-env-*.txt
```

---

### 4. PVC Snapshot Backup

Use Kubernetes VolumeSnapshot API for storage-level backups.

**Prerequisites:**
- VolumeSnapshot CRDs installed
- VolumeSnapshotClass configured
- CSI driver supporting snapshots

#### 4.1 Create PVC Snapshot

**Procedure:**

```bash
# 1. Create VolumeSnapshot resource
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: vaultwarden-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: vaultwarden-data
EOF

# 2. Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/vaultwarden-data-snapshot-* \
  -n default \
  --timeout=300s

# 3. Verify snapshot
kubectl get volumesnapshot -n default
kubectl describe volumesnapshot vaultwarden-data-snapshot-* -n default
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-snapshot-data
```

#### 4.2 List All Snapshots

```bash
kubectl get volumesnapshot -n default -l "app.kubernetes.io/name=vaultwarden"
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-list-snapshots
```

#### 4.3 Delete Old Snapshots

```bash
# Delete snapshots older than 30 days
kubectl get volumesnapshot -n default -l "app.kubernetes.io/name=vaultwarden" \
  -o json | jq -r '.items[] | select(.metadata.creationTimestamp < (now - 30*86400 | todate)) | .metadata.name' \
  | xargs -r kubectl delete volumesnapshot -n default
```

---

## Recovery Procedures

### Data Directory Recovery

#### Full Data Directory Restore

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
RELEASE_NAME="vaultwarden"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
BACKUP_FILE="/tmp/vaultwarden-backups/vaultwarden-data-full-20250101-120000.tar.gz"

# 2. Stop Vaultwarden (scale down)
kubectl scale deployment/$RELEASE_NAME -n $NAMESPACE --replicas=0
# OR for StatefulSet:
kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=0

# 3. Wait for pod termination
kubectl wait --for=delete pod/$POD_NAME -n $NAMESPACE --timeout=120s

# 4. Start a temporary restore pod
kubectl run vaultwarden-restore \
  -n $NAMESPACE \
  --image=busybox:latest \
  --restart=Never \
  --command -- sleep 3600

# 5. Wait for restore pod
kubectl wait --for=condition=Ready pod/vaultwarden-restore -n $NAMESPACE --timeout=120s

# 6. Copy backup to restore pod
kubectl cp $BACKUP_FILE $NAMESPACE/vaultwarden-restore:/tmp/restore.tar.gz

# 7. Extract backup (this assumes you mount the PVC to the restore pod)
# First, patch the pod to mount the PVC (requires pod restart)
# OR use a Job with proper volume mounts

# 8. Cleanup restore pod
kubectl delete pod vaultwarden-restore -n $NAMESPACE

# 9. Restart Vaultwarden
kubectl scale deployment/$RELEASE_NAME -n $NAMESPACE --replicas=1
# OR for StatefulSet:
kubectl scale statefulset/$RELEASE_NAME -n $NAMESPACE --replicas=1

# 10. Verify restoration
POD_NAME=$(kubectl get pod -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD_NAME -- ls -lah /data
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/path/to/backup.tar.gz
```

---

### Database Recovery

#### PostgreSQL Database Restore

**Procedure:**

```bash
# 1. Set variables
PG_HOST="postgres-service.default.svc.cluster.local"
PG_PORT="5432"
PG_DATABASE="vaultwarden"
PG_USERNAME="vaultwarden"
PG_PASSWORD="<your-password>"
BACKUP_FILE="/tmp/vaultwarden-backups/vaultwarden-pg-20250101-120000.sql.gz"

# 2. Stop Vaultwarden (to prevent connections during restore)
kubectl scale deployment/vaultwarden -n default --replicas=0

# 3. Drop existing database and recreate (⚠️ DESTRUCTIVE)
PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U $PG_USERNAME -d postgres -c "DROP DATABASE IF EXISTS $PG_DATABASE;"
PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U $PG_USERNAME -d postgres -c "CREATE DATABASE $PG_DATABASE OWNER $PG_USERNAME;"

# 4. Restore database
PGPASSWORD=$PG_PASSWORD pg_restore \
  -h $PG_HOST \
  -p $PG_PORT \
  -U $PG_USERNAME \
  -d $PG_DATABASE \
  --verbose \
  --no-owner \
  --no-acl \
  $BACKUP_FILE

# 5. Verify restoration
PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U $PG_USERNAME -d $PG_DATABASE -c "\dt"

# 6. Restart Vaultwarden
kubectl scale deployment/vaultwarden -n default --replicas=1
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-restore-postgres BACKUP_FILE=/path/to/backup.sql.gz
```

---

### Configuration Recovery

**Procedure:**

```bash
# 1. Set variables
NAMESPACE="default"
BACKUP_FILE="/tmp/vaultwarden-backups/vaultwarden-config-20250101-120000.tar.gz"
RESTORE_DIR="/tmp/vaultwarden-restore"

# 2. Extract backup
mkdir -p $RESTORE_DIR
tar xzf $BACKUP_FILE -C $RESTORE_DIR

# 3. Restore Kubernetes resources
kubectl apply -f $RESTORE_DIR/vaultwarden-resources.yaml -n $NAMESPACE

# 4. Verify restoration
kubectl get all -n $NAMESPACE -l "app.kubernetes.io/name=vaultwarden"
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-restore-config BACKUP_FILE=/path/to/config.tar.gz
```

---

### Full Disaster Recovery

Complete instance recovery from backups.

**Scenario**: Complete cluster failure, need to rebuild Vaultwarden from backups.

**Prerequisites:**
- Kubernetes cluster available
- Helm installed
- Backup files available
- External database available (if using PostgreSQL/MySQL mode)

**Procedure:**

```bash
# 1. Restore external database (if using PostgreSQL/MySQL)
make -f make/ops/vaultwarden.mk vw-restore-postgres BACKUP_FILE=/path/to/database.sql.gz
# OR
make -f make/ops/vaultwarden.mk vw-restore-mysql BACKUP_FILE=/path/to/database.sql.gz

# 2. Deploy Vaultwarden via Helm (with same values.yaml)
helm install vaultwarden sb-charts/vaultwarden \
  -n default \
  -f /path/to/backup/values.yaml

# 3. Wait for deployment
kubectl rollout status deployment/vaultwarden -n default
# OR
kubectl rollout status statefulset/vaultwarden -n default

# 4. Restore data directory
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/path/to/data.tar.gz

# 5. Restart Vaultwarden
kubectl rollout restart deployment/vaultwarden -n default
# OR
kubectl rollout restart statefulset/vaultwarden -n default

# 6. Verify recovery
kubectl exec -n default deployment/vaultwarden -- ls -lah /data
# Access Vaultwarden web vault and test login

# 7. Verify vault data integrity
# - Login to web vault
# - Check password items
# - Test file attachments
# - Verify Send feature (if used)
```

**Makefile Target:**
```bash
make -f make/ops/vaultwarden.mk vw-full-recovery \
  DATA_BACKUP=/path/to/data.tar.gz \
  DB_BACKUP=/path/to/database.sql.gz \
  CONFIG_BACKUP=/path/to/config.tar.gz
```

**Recovery Time Estimate:**
- Database restore: 15-30 minutes
- Helm deployment: 5-10 minutes
- Data directory restore: 15-30 minutes
- Verification: 10-15 minutes
- **Total**: 45-85 minutes (within 1 hour RTO target)

---

## Backup Automation

### Automated Backup Script

**Script Location**: `scripts/backup-vaultwarden.sh`

**Example Automation (Cron-based):**

```bash
#!/bin/bash
# Vaultwarden Automated Backup Script
# Usage: ./backup-vaultwarden.sh [sqlite|postgres|mysql|all]

set -euo pipefail

BACKUP_TYPE="${1:-all}"
BACKUP_BASE_DIR="/backups/vaultwarden"
RETENTION_DAYS=30

# Create timestamped backup directory
BACKUP_DIR="$BACKUP_BASE_DIR/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

case "$BACKUP_TYPE" in
  sqlite|all)
    echo "Backing up SQLite database..."
    make -f make/ops/vaultwarden.mk vw-backup-sqlite BACKUP_DIR="$BACKUP_DIR"
    ;;
esac

case "$BACKUP_TYPE" in
  postgres|all)
    echo "Backing up PostgreSQL database..."
    make -f make/ops/vaultwarden.mk vw-backup-postgres BACKUP_DIR="$BACKUP_DIR"
    ;;
esac

case "$BACKUP_TYPE" in
  mysql|all)
    echo "Backing up MySQL database..."
    make -f make/ops/vaultwarden.mk vw-backup-mysql BACKUP_DIR="$BACKUP_DIR"
    ;;
esac

if [ "$BACKUP_TYPE" = "all" ]; then
  echo "Backing up data directory..."
  make -f make/ops/vaultwarden.mk vw-backup-data-full BACKUP_DIR="$BACKUP_DIR"

  echo "Backing up configuration..."
  make -f make/ops/vaultwarden.mk vw-backup-config BACKUP_DIR="$BACKUP_DIR"
fi

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Backup completed: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
```

**Crontab Entry:**

```bash
# Daily full backup at 2 AM
0 2 * * * /path/to/backup-vaultwarden.sh all >> /var/log/vaultwarden-backup.log 2>&1

# Hourly SQLite backup (for critical deployments)
0 * * * * /path/to/backup-vaultwarden.sh sqlite >> /var/log/vaultwarden-backup.log 2>&1
```

---

## Best Practices

### Backup Best Practices

1. **Test Restore Procedures Quarterly**
   - Schedule quarterly disaster recovery drills
   - Document actual RTO/RPO achieved
   - Update procedures based on test results

2. **Store Backups Off-Site**
   - Use different availability zone or region
   - Consider S3, MinIO, or cloud storage
   - Encrypt backups in transit and at rest

3. **Encrypt Sensitive Backups**
   - Configuration backups contain admin tokens and SMTP passwords
   - Database backups contain encrypted vault data (but keys are in config)
   - Use GPG or age for backup encryption

4. **Verify Backup Integrity**
   - Check SQLite integrity: `sqlite3 backup.db "PRAGMA integrity_check;"`
   - Verify PostgreSQL dump: `pg_restore --list backup.sql.gz`
   - Test random file restore monthly

5. **Automate Backup Retention**
   - Keep 7 daily backups
   - Keep 4 weekly backups
   - Keep 12 monthly backups
   - Keep 1 yearly backup

6. **Monitor Backup Success**
   - Alert on failed backups
   - Track backup sizes and durations
   - Monitor backup storage usage

7. **Document Backup Locations**
   - Maintain inventory of all backups
   - Document encryption keys securely
   - Share backup access with team (encrypted)

### Database-Specific Best Practices

**SQLite Mode:**
- Always use `.backup` command, never direct file copy while running
- Include WAL and SHM files if copying after stopping service
- Test SQLite integrity after every backup
- Consider hourly backups for critical deployments (small overhead)

**PostgreSQL/MySQL Mode:**
- Use `--format=custom` for PostgreSQL (faster, smaller, parallel restore)
- Always backup before major Vaultwarden upgrades
- Monitor database size growth
- Keep data directory backups (attachments, icons) separate from database

---

## Troubleshooting

### Common Backup Issues

#### 1. SQLite Database Locked

**Symptom**: `Error: database is locked`

**Cause**: Vaultwarden is writing to database during backup attempt

**Solution**:
```bash
# Option 1: Use .backup command (handles locks)
kubectl exec -n default $POD_NAME -- sqlite3 /data/db.sqlite3 ".backup /tmp/backup.db"

# Option 2: Stop service before backup
kubectl scale deployment/vaultwarden -n default --replicas=0
# ... perform backup ...
kubectl scale deployment/vaultwarden -n default --replicas=1
```

#### 2. Backup File Too Large

**Symptom**: Backup fails due to storage constraints

**Cause**: Large attachments or icon cache

**Solution**:
```bash
# Check data directory size breakdown
kubectl exec -n default $POD_NAME -- du -sh /data/*

# Backup attachments separately
kubectl exec -n default $POD_NAME -- tar czf - /data/attachments > attachments-backup.tar.gz

# Exclude icon cache from backup (can be regenerated)
kubectl exec -n default $POD_NAME -- tar czf - --exclude=/data/icon_cache /data > data-backup.tar.gz
```

#### 3. PostgreSQL Restore Fails

**Symptom**: `ERROR: role "vaultwarden" does not exist`

**Cause**: User/role missing in target database

**Solution**:
```bash
# Create user before restore
PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U postgres -c "CREATE USER vaultwarden WITH PASSWORD 'password';"

# Use --no-owner --no-acl flags
pg_restore --no-owner --no-acl -d vaultwarden backup.sql.gz
```

#### 4. Data Directory Restore Incomplete

**Symptom**: Missing attachments or vault items after restore

**Cause**: Incomplete tar extraction or wrong backup file

**Solution**:
```bash
# Verify tar archive integrity
tar tzf backup.tar.gz | wc -l

# Extract with verbose output
tar xzvf backup.tar.gz -C /data

# Check directory permissions
chown -R 1000:1000 /data
chmod -R 755 /data
```

### Recovery Issues

#### 1. Vaultwarden Won't Start After Restore

**Symptom**: Pod crashes or fails health checks

**Cause**: Database connection issue or corrupted database

**Solution**:
```bash
# Check logs
kubectl logs -n default deployment/vaultwarden --tail=100

# Verify database connectivity
kubectl exec -n default $POD_NAME -- nc -zv postgres-service.default.svc.cluster.local 5432

# Test SQLite integrity
kubectl exec -n default $POD_NAME -- sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;"

# Check file permissions
kubectl exec -n default $POD_NAME -- ls -la /data
```

#### 2. Users Can't Login After Restore

**Symptom**: Login fails with "invalid credentials"

**Cause**: Database/data mismatch or RSA keys issue

**Solution**:
```bash
# Verify RSA keys exist
kubectl exec -n default $POD_NAME -- ls -la /data/rsa_key.*

# Check database mode matches deployment
kubectl exec -n default $POD_NAME -- env | grep DATABASE_URL

# Restore matching database and data backups
# Ensure backups are from same timestamp
```

---

## Summary

**Backup Checklist:**

- [ ] Data directory backup (daily full, hourly incremental for critical)
- [ ] Database backup (daily, hourly for critical)
- [ ] Configuration backup (on every change)
- [ ] PVC snapshots (weekly)
- [ ] Off-site backup storage configured
- [ ] Backup encryption enabled
- [ ] Automated backup script running
- [ ] Backup monitoring and alerting configured
- [ ] Quarterly restore test scheduled

**Recovery Checklist:**

- [ ] Identify backup files (data, database, config)
- [ ] Verify backup integrity
- [ ] Stop Vaultwarden service
- [ ] Restore database (if using external DB)
- [ ] Deploy Vaultwarden via Helm
- [ ] Restore data directory
- [ ] Restart service
- [ ] Test vault access and functionality
- [ ] Document recovery time and issues

**For More Information:**
- Vaultwarden documentation: https://github.com/dani-garcia/vaultwarden/wiki
- Kubernetes VolumeSnapshot: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- PostgreSQL backup: https://www.postgresql.org/docs/current/backup.html
