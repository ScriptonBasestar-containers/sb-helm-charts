# MySQL Backup & Recovery Guide

This comprehensive guide covers backup and recovery procedures for the MySQL Helm chart deployment in Kubernetes.

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Point-in-Time Recovery (PITR)](#point-in-time-recovery-pitr)
7. [Disaster Recovery](#disaster-recovery)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Philosophy

MySQL backup strategy in Kubernetes focuses on:
- **Logical dumps** for portability and version compatibility
- **Binary log archiving** for Point-in-Time Recovery (PITR)
- **Replication** for high availability and near-zero RPO
- **PVC snapshots** for disaster recovery
- **Configuration backups** for infrastructure-as-code

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) | Method |
|----------|---------------------|---------------------|--------|
| **Single database restore** | < 30 minutes | 24 hours | mysqldump restore |
| **Full cluster restore** | < 2 hours | 24 hours | Full logical backup |
| **Point-in-Time Recovery** | < 1 hour | 5-15 minutes | Binary log replay |
| **Replica failover** | < 5 minutes | Near-zero | Replication promotion |
| **Disaster recovery** | < 4 hours | 24 hours | PVC snapshot restore |

### Backup Types Comparison

| Type | Speed | Size | Use Case | Downtime |
|------|-------|------|----------|----------|
| **mysqldump** | Slow (for large DBs) | Large (uncompressed SQL) | Logical backups, version upgrades | None (with --single-transaction) |
| **Binary logs** | Fast (continuous) | Small (incremental) | PITR, replication | None |
| **Replication** | Real-time | N/A (live replica) | HA, read scaling | None |
| **PVC snapshot** | Very fast | Full volume size | Disaster recovery | Brief (seconds) |
| **Physical backup** | Fast | Full data directory size | Large databases | Yes (requires shutdown or hot backup tool) |

---

## Backup Strategy

### Multi-Layered Approach

The MySQL chart supports a **5-component backup strategy**:

```
┌─────────────────────────────────────────────────────────────┐
│                    MySQL Backup Strategy                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Configuration Backups (ConfigMap + Secret)               │
│     ├─ Frequency: Daily / Before changes                    │
│     ├─ Retention: 90 days                                   │
│     └─ Size: < 100 KB                                       │
│                                                              │
│  2. Logical Dumps (mysqldump)                                │
│     ├─ Frequency: Daily (full) / Hourly (incremental)       │
│     ├─ Retention: 30 days (daily), 7 days (hourly)          │
│     └─ Size: Varies (10 MB - 100 GB+)                       │
│                                                              │
│  3. Binary Log Archiving (mysqlbinlog)                       │
│     ├─ Frequency: Continuous (every flush)                  │
│     ├─ Retention: 7 days (matches full backup cycle)        │
│     └─ Size: ~1-10 GB/day (depends on write volume)         │
│                                                              │
│  4. Replication (Hot Standby)                                │
│     ├─ Frequency: Real-time (synchronous/asynchronous)      │
│     ├─ Retention: N/A (live replica)                        │
│     └─ RPO: Near-zero (sync) or seconds (async)             │
│                                                              │
│  5. PVC Snapshots (VolumeSnapshot API)                       │
│     ├─ Frequency: Weekly                                    │
│     ├─ Retention: 4 weeks                                   │
│     └─ Size: Same as PVC size (with snapshot efficiency)    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Recommended Configuration

**Development environments:**
```yaml
backup:
  logical:
    enabled: true
    schedule: "0 2 * * *"  # Daily at 2 AM
    retention: 7
  binlog:
    enabled: false  # Not critical for dev
```

**Production environments:**
```yaml
backup:
  logical:
    enabled: true
    schedule: "0 2 * * *"  # Daily full backup
    retention: 30
  binlog:
    enabled: true
    expireLogsDays: 7
    archiveToS3: true
  replication:
    enabled: true
    replicas: 2
  pvcSnapshot:
    enabled: true
    schedule: "0 3 * * 0"  # Weekly on Sunday at 3 AM
    retention: 4
```

---

## Backup Components

### 1. Configuration Backups

**What**: ConfigMap (my.cnf configuration) and Secret (passwords)

**Why**:
- Restore MySQL configuration after cluster recreation
- Track configuration changes over time
- Enable infrastructure-as-code workflows

**Storage**:
- Local filesystem: `tmp/mysql-backups/`
- S3/MinIO: `s3://backups/mysql/config/`
- Git repository (recommended for ConfigMap only)

**Backup frequency**:
- Daily (automated)
- Before any configuration change (manual)

**Retention**: 90 days

**Backup command**:
```bash
make -f make/ops/mysql.mk mysql-backup-config
```

**What's backed up**:
- ConfigMap: `mysql-config` (my.cnf, custom configuration)
- Secret: `mysql-secret` (root password, replication password)
- Kubernetes manifests (Deployment/StatefulSet, Service, PVC)

**Recovery time**: < 5 minutes

---

### 2. Logical Dumps (mysqldump)

**What**: SQL dumps of databases using `mysqldump`

**Why**:
- Portable across MySQL versions and platforms
- Human-readable SQL format
- Selective restore (database, table, or row level)
- No downtime with `--single-transaction` (InnoDB)

**Methods**:

#### Full Database Dump (Single Database)
```bash
mysqldump -u root -p \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  database_name > database_name.sql
```

#### All Databases Dump
```bash
mysqldump -u root -p \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --master-data=2 > all-databases.sql
```

**Key options**:
- `--single-transaction`: Consistent backup without locking tables (InnoDB only)
- `--master-data=2`: Include binary log position (for PITR)
- `--routines`: Include stored procedures and functions
- `--triggers`: Include triggers
- `--events`: Include event scheduler events
- `--flush-logs`: Rotate binary logs after backup

**Storage formats**:
- Plain SQL (`.sql`): Human-readable, largest size
- Compressed SQL (`.sql.gz`): 5-10x smaller, slower restore
- Delimited text (`--tab`): Fast for large tables, requires filesystem access

**Backup frequency**:
- Full backup: Daily (small DBs) or Weekly (large DBs)
- Incremental: Hourly (via binary logs)

**Retention**: 30 days (full), 7 days (incremental)

**Backup commands**:
```bash
# Single database
make -f make/ops/mysql.mk mysql-backup DATABASE=myapp

# All databases
make -f make/ops/mysql.mk mysql-backup-all

# Compressed backup
make -f make/ops/mysql.mk mysql-backup-compressed DATABASE=myapp
```

**Recovery time**:
- Small DB (< 1 GB): 5-15 minutes
- Medium DB (1-10 GB): 30 minutes - 2 hours
- Large DB (> 10 GB): 2-8 hours

---

### 3. Binary Log Archiving

**What**: MySQL binary logs (binlog) containing all data modifications

**Why**:
- **Point-in-Time Recovery (PITR)**: Restore to specific timestamp
- **Incremental backups**: Minimal storage, continuous protection
- **Replication**: Foundation for MySQL replication
- **Audit trail**: Track all database changes

**How binary logs work**:
```
[Base Backup]  →  [binlog.000001]  →  [binlog.000002]  →  [binlog.000003]
   (Day 0)           (Day 1)             (Day 2)             (Day 3)

Each binlog file contains:
- INSERT, UPDATE, DELETE operations
- DDL changes (CREATE, ALTER, DROP)
- Timestamps for PITR
- Event positions for consistency
```

**Configuration** (`my.cnf`):
```ini
[mysqld]
# Enable binary logging
log-bin=mysql-bin
server-id=1

# Binary log format
binlog_format=ROW  # ROW, STATEMENT, or MIXED

# Binary log retention
expire_logs_days=7  # Auto-delete logs older than 7 days

# Binary log size
max_binlog_size=100M  # Rotate at 100 MB

# Sync to disk (durability vs performance)
sync_binlog=1  # 1 = durable, 0 = faster but risky
```

**Binary log formats**:

| Format | Description | Use Case | Size |
|--------|-------------|----------|------|
| **STATEMENT** | SQL statements | Simple queries, smaller logs | Smallest |
| **ROW** | Row changes | Complex queries, deterministic | Largest |
| **MIXED** | Auto-switch | Best of both worlds | Medium |

**Archiving strategies**:

#### Local Filesystem
```bash
# Copy binary logs to backup directory
mysqlbinlog mysql-bin.000001 > /backups/mysql-bin.000001.sql
gzip /backups/mysql-bin.000001.sql
```

#### S3/MinIO
```bash
# Archive to S3
aws s3 cp mysql-bin.000001 s3://mysql-backups/binlogs/
```

#### Automated archiving script
```bash
#!/bin/bash
# Archive binary logs to S3
for binlog in $(mysql -e "SHOW BINARY LOGS" | awk '{print $1}' | grep -v Log_name); do
  aws s3 cp /var/lib/mysql/$binlog s3://mysql-backups/binlogs/$binlog
done

# Purge old logs (after successful archive)
mysql -e "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);"
```

**Backup frequency**: Continuous (every binlog rotation or flush)

**Retention**: 7 days (matches full backup retention for PITR)

**Commands**:
```bash
# List binary logs
make -f make/ops/mysql.mk mysql-show-binlogs

# Flush and rotate binary logs
make -f make/ops/mysql.mk mysql-flush-logs

# Archive binary logs
make -f make/ops/mysql.mk mysql-archive-binlogs

# Purge old binary logs
make -f make/ops/mysql.mk mysql-purge-binlogs BEFORE='2025-01-01'
```

**Recovery time**: 5-30 minutes (depends on binlog volume)

---

### 4. Replication (Hot Standby)

**What**: Real-time MySQL replication for high availability

**Why**:
- **Near-zero RPO**: Continuous data replication
- **Fast failover**: < 5 minutes RTO
- **Read scaling**: Offload read queries to replicas
- **No backup window**: Always available

**Replication topologies**:

#### Primary-Replica (Master-Slave)
```
┌──────────┐     Async       ┌──────────┐
│ Primary  │ ────────────→  │ Replica  │
│ (RW)     │                 │ (RO)     │
└──────────┘                 └──────────┘
```

#### Primary-Replica with Delayed Replication
```
┌──────────┐  Async   ┌──────────┐  Delayed   ┌──────────┐
│ Primary  │ ────────→│ Replica1 │ ────────→ │ Replica2 │
│ (RW)     │           │ (RO)     │  (1 hour)  │ (RO)     │
└──────────┘           └──────────┘             └──────────┘
                                                (Safety net for
                                                 accidental deletes)
```

**Configuration**:

**Primary** (`values.yaml`):
```yaml
mysql:
  replication:
    enabled: true
    serverId: 1  # Unique server ID
  extraEnv:
    - name: MYSQL_REPLICATION_MODE
      value: "master"
```

**Replica** (`values.yaml`):
```yaml
mysql:
  replication:
    enabled: true
    serverId: 2  # Different server ID
    user: "replicator"
    password: "secret"
  extraEnv:
    - name: MYSQL_REPLICATION_MODE
      value: "slave"
    - name: MYSQL_MASTER_HOST
      value: "mysql-primary"
    - name: MYSQL_MASTER_PORT
      value: "3306"
```

**Setup replication** (manual steps):

1. **On Primary**: Create replication user
```sql
CREATE USER 'replicator'@'%' IDENTIFIED BY 'secret';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;
```

2. **On Primary**: Get binary log position
```sql
SHOW MASTER STATUS;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| mysql-bin.000003 | 73       | test         | manual,mysql     |
+------------------+----------+--------------+------------------+
```

3. **On Replica**: Configure and start replication
```sql
CHANGE MASTER TO
  MASTER_HOST='mysql-primary',
  MASTER_USER='replicator',
  MASTER_PASSWORD='secret',
  MASTER_LOG_FILE='mysql-bin.000003',
  MASTER_LOG_POS=73;

START SLAVE;
```

4. **Verify replication**:
```sql
SHOW SLAVE STATUS\G
```

**Commands**:
```bash
# Check replication status
make -f make/ops/mysql.mk mysql-replication-status

# Check replication lag
make -f make/ops/mysql.mk mysql-replication-lag

# Promote replica to primary
make -f make/ops/mysql.mk mysql-promote-replica POD=mysql-1
```

**Replication lag monitoring**:
```sql
SELECT TIMESTAMPDIFF(SECOND,
  CONVERT_TZ(SQL_THREAD_TIME, '+00:00', 'SYSTEM'),
  CONVERT_TZ(SYSDATE(), '+00:00', 'SYSTEM')
) AS seconds_behind_master;
```

**Failover procedure**:
1. Stop application writes to primary
2. Wait for replica to catch up (lag = 0)
3. Promote replica to primary: `STOP SLAVE; RESET SLAVE ALL;`
4. Update application connection string
5. Optionally rebuild old primary as new replica

**Recovery time**: < 5 minutes (automated failover)

---

### 5. PVC Snapshots

**What**: Kubernetes VolumeSnapshot of MySQL data volume

**Why**:
- **Fast backup**: Snapshot entire volume in seconds
- **Fast restore**: No need to replay binlogs
- **Disaster recovery**: Recover entire cluster quickly
- **Storage-efficient**: Uses copy-on-write

**Requirements**:
- Kubernetes 1.17+ (VolumeSnapshot API)
- CSI driver with snapshot support
- VolumeSnapshotClass configured

**Snapshot workflow**:
```
1. Flush tables and acquire read lock
2. Create VolumeSnapshot
3. Release read lock
4. Snapshot captured (copy-on-write in background)
```

**Configuration** (`volumesnapshotclass.yaml`):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
```

**Backup command**:
```bash
make -f make/ops/mysql.mk mysql-backup-pvc-snapshot
```

**Manual snapshot creation**:
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-snapshot-20250115
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: data-mysql-0
```

**Backup frequency**: Weekly

**Retention**: 4 weeks (monthly snapshots for longer retention)

**Recovery time**: 30 minutes - 2 hours (depends on volume size)

---

## Backup Procedures

### Daily Backup Routine

**Automated CronJob** (recommended):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mysql-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mysql-backup
            image: mysql:8.0
            env:
            - name: MYSQL_PWD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: mysql-root-password
            command:
            - /bin/bash
            - -c
            - |
              BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
              mysqldump -h mysql -u root \
                --all-databases \
                --single-transaction \
                --master-data=2 \
                --flush-logs \
                --routines \
                --triggers \
                --events | gzip > /backup/mysql-all-$BACKUP_DATE.sql.gz

              # Upload to S3
              aws s3 cp /backup/mysql-all-$BACKUP_DATE.sql.gz \
                s3://mysql-backups/daily/

              # Cleanup local backups older than 7 days
              find /backup -name "mysql-all-*.sql.gz" -mtime +7 -delete
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: mysql-backup-pvc
          restartPolicy: OnFailure
```

### Manual Backup Procedures

#### 1. Full Backup (All Databases)

```bash
# Using Makefile
make -f make/ops/mysql.mk mysql-backup-all

# Manual execution
kubectl exec -it mysql-0 -- bash -c '
  MYSQL_PWD=$MYSQL_ROOT_PASSWORD mysqldump -u root \
    --all-databases \
    --single-transaction \
    --master-data=2 \
    --flush-logs \
    --routines \
    --triggers \
    --events | gzip
' > mysql-all-$(date +%Y%m%d-%H%M%S).sql.gz
```

**Output**: `mysql-all-20250115-140000.sql.gz`

#### 2. Single Database Backup

```bash
# Using Makefile
make -f make/ops/mysql.mk mysql-backup DATABASE=myapp

# Manual execution
kubectl exec -it mysql-0 -- bash -c '
  MYSQL_PWD=$MYSQL_ROOT_PASSWORD mysqldump -u root \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    myapp | gzip
' > myapp-$(date +%Y%m%d-%H%M%S).sql.gz
```

#### 3. Specific Tables Backup

```bash
kubectl exec -it mysql-0 -- bash -c '
  MYSQL_PWD=$MYSQL_ROOT_PASSWORD mysqldump -u root \
    --single-transaction \
    myapp users orders | gzip
' > myapp-users-orders-$(date +%Y%m%d-%H%M%S).sql.gz
```

#### 4. Configuration Backup

```bash
# Using Makefile
make -f make/ops/mysql.mk mysql-backup-config

# Manual execution
kubectl get configmap mysql-config -o yaml > mysql-config-$(date +%Y%m%d).yaml
kubectl get secret mysql-secret -o yaml > mysql-secret-$(date +%Y%m%d).yaml
```

#### 5. Binary Log Archive

```bash
# Using Makefile
make -f make/ops/mysql.mk mysql-archive-binlogs

# Manual execution
kubectl exec -it mysql-0 -- bash -c '
  for binlog in $(mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW BINARY LOGS" | awk "{print \$1}" | grep -v Log_name); do
    mysqlbinlog /var/lib/mysql/$binlog | gzip > /backup/$binlog.gz
  done
'
```

### Pre-Upgrade Backup

**Always backup before upgrades:**

```bash
# Step 1: Full database backup
make -f make/ops/mysql.mk mysql-backup-all

# Step 2: Configuration backup
make -f make/ops/mysql.mk mysql-backup-config

# Step 3: Binary log archive
make -f make/ops/mysql.mk mysql-archive-binlogs

# Step 4: PVC snapshot (optional but recommended)
make -f make/ops/mysql.mk mysql-backup-pvc-snapshot

# Step 5: Verify backups
make -f make/ops/mysql.mk mysql-backup-verify FILE=tmp/mysql-backups/mysql-all-latest.sql.gz
```

### Backup Verification

**Always verify backups before relying on them:**

```bash
# Check backup file size
ls -lh tmp/mysql-backups/mysql-all-20250115.sql.gz

# Verify SQL syntax (first 100 lines)
zcat tmp/mysql-backups/mysql-all-20250115.sql.gz | head -100

# Test restore to temporary database
kubectl exec -it mysql-0 -- bash -c '
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE test_restore;"
  zcat < /backup/mysql-all-20250115.sql.gz | \
    mysql -u root -p$MYSQL_ROOT_PASSWORD test_restore
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW TABLES;" test_restore
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE test_restore;"
'
```

---

## Recovery Procedures

### Recovery Decision Tree

```
Is the database corrupted or deleted?
  ├─ Yes: Full restore required
  │   └─ Do you need a specific point in time?
  │       ├─ Yes: PITR (Base backup + Binary logs)
  │       └─ No: Latest full backup
  │
  └─ No: Partial issue
      ├─ Single table corrupted → Table-level restore
      ├─ Accidental DELETE/UPDATE → PITR to before incident
      └─ Need to rollback migration → PITR or full restore
```

### 1. Full Database Restore (All Databases)

**Scenario**: Complete cluster failure, need to restore all databases

**Steps**:

```bash
# Step 1: Stop applications (prevent writes)
kubectl scale deployment myapp --replicas=0

# Step 2: Ensure MySQL pod is running
kubectl get pods -l app.kubernetes.io/name=mysql

# Step 3: Restore backup
make -f make/ops/mysql.mk mysql-restore-all FILE=tmp/mysql-backups/mysql-all-20250115.sql.gz

# Or manual restore:
zcat tmp/mysql-backups/mysql-all-20250115.sql.gz | \
  kubectl exec -i mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD

# Step 4: Verify restore
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"

# Step 5: Restart applications
kubectl scale deployment myapp --replicas=3
```

**Recovery time**: 30 minutes - 4 hours (depends on DB size)

### 2. Single Database Restore

**Scenario**: One database corrupted, others are fine

**Steps**:

```bash
# Step 1: Drop corrupted database (optional, if exists)
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE IF EXISTS myapp;"

# Step 2: Recreate database
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Step 3: Restore from backup
make -f make/ops/mysql.mk mysql-restore DATABASE=myapp FILE=tmp/mysql-backups/myapp-20250115.sql.gz

# Or manual restore:
zcat tmp/mysql-backups/myapp-20250115.sql.gz | \
  kubectl exec -i mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp

# Step 4: Verify data
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW TABLES; SELECT COUNT(*) FROM users;" myapp
```

**Recovery time**: 10 minutes - 1 hour

### 3. Table-Level Restore

**Scenario**: Single table corrupted, need to restore only that table

**Method 1: Extract table from full backup**

```bash
# Extract specific table from full backup
zcat mysql-all-20250115.sql.gz | \
  sed -n '/^-- Table structure for table `users`/,/^-- Table structure for table/p' | \
  kubectl exec -i mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp
```

**Method 2: Restore to temporary database, then export table**

```bash
# Restore to temporary database
kubectl exec -it mysql-0 -- bash -c '
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE temp_restore;"
  zcat /backup/myapp-20250115.sql.gz | \
    mysql -u root -p$MYSQL_ROOT_PASSWORD temp_restore

  # Export specific table
  mysqldump -u root -p$MYSQL_ROOT_PASSWORD temp_restore users | \
    mysql -u root -p$MYSQL_ROOT_PASSWORD myapp

  # Cleanup
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE temp_restore;"
'
```

**Recovery time**: 5-30 minutes

### 4. Configuration Restore

**Scenario**: Lost ConfigMap or Secret, need to restore configuration

```bash
# Restore ConfigMap
kubectl apply -f mysql-config-20250115.yaml

# Restore Secret (remove resourceVersion and uid first)
kubectl apply -f mysql-secret-20250115.yaml

# Restart MySQL to apply new configuration
kubectl rollout restart statefulset/mysql
kubectl rollout status statefulset/mysql
```

**Recovery time**: 5-10 minutes

### 5. PVC Snapshot Restore

**Scenario**: Complete disaster, need fastest recovery

**Steps**:

1. **Create PVC from snapshot**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data-restored
spec:
  dataSource:
    name: mysql-snapshot-20250115
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

2. **Update StatefulSet to use restored PVC**:
```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: [ "ReadWriteOnce" ]
    storageClassName: standard
    resources:
      requests:
        storage: 10Gi
    dataSource:
      name: mysql-snapshot-20250115
      kind: VolumeSnapshot
      apiGroup: snapshot.storage.k8s.io
```

3. **Deploy MySQL with restored volume**:
```bash
helm upgrade mysql sb-charts/mysql -f values.yaml

# Verify data
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"
```

**Recovery time**: 30 minutes - 2 hours

---

## Point-in-Time Recovery (PITR)

**Scenario**: Accidental DELETE or UPDATE, need to restore to specific timestamp

### PITR Workflow

```
[Base Backup]  →  [Binary Logs]  →  [Desired Point]  →  [Current State]
   (Day 0)         (Day 1-3)       (Recovery target)    (Don't want this)
                                   ↓
                            [Restore to here]
```

### PITR Steps

**Example**: Restore to January 15, 2025 at 14:30:00 (before accidental DELETE)

#### Step 1: Find base backup

```bash
# Find latest full backup before incident
ls -lh tmp/mysql-backups/mysql-all-*.sql.gz

# Assume: mysql-all-20250115-020000.sql.gz (from 2 AM backup)
```

#### Step 2: Identify binary logs

```bash
# Check which binary logs cover the time range
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW BINARY LOGS;"

# Output:
# mysql-bin.000015  (contains events from 2 AM to 12 PM)
# mysql-bin.000016  (contains events from 12 PM to 6 PM - includes 14:30)
```

#### Step 3: Stop applications

```bash
kubectl scale deployment myapp --replicas=0
```

#### Step 4: Restore base backup

```bash
# Restore to temporary instance (recommended) or production
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE myapp_pitr;"

zcat tmp/mysql-backups/mysql-all-20250115-020000.sql.gz | \
  kubectl exec -i mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD
```

#### Step 5: Apply binary logs up to recovery point

```bash
# Replay binary logs up to 14:30:00
kubectl exec -it mysql-0 -- bash -c '
  mysqlbinlog \
    --stop-datetime="2025-01-15 14:30:00" \
    /var/lib/mysql/mysql-bin.000015 \
    /var/lib/mysql/mysql-bin.000016 | \
    mysql -u root -p$MYSQL_ROOT_PASSWORD
'
```

**Alternative: Stop at specific position** (more precise):

```bash
# Find exact position before DELETE
kubectl exec -it mysql-0 -- mysqlbinlog /var/lib/mysql/mysql-bin.000016 | grep -B5 "DELETE FROM users"

# Output shows position: at 12345

# Replay up to position 12344
kubectl exec -it mysql-0 -- bash -c '
  mysqlbinlog \
    --stop-position=12344 \
    /var/lib/mysql/mysql-bin.000016 | \
    mysql -u root -p$MYSQL_ROOT_PASSWORD
'
```

#### Step 6: Verify recovery

```bash
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SELECT COUNT(*) FROM myapp.users;
  SELECT * FROM myapp.users WHERE id = 12345;  -- Verify specific record
"
```

#### Step 7: Restart applications

```bash
kubectl scale deployment myapp --replicas=3
```

### PITR with Makefile

```bash
# Automated PITR (using Makefile wrapper)
make -f make/ops/mysql.mk mysql-pitr \
  RECOVERY_TIME='2025-01-15 14:30:00' \
  BASE_BACKUP=tmp/mysql-backups/mysql-all-20250115-020000.sql.gz
```

**Recovery time**: 30 minutes - 2 hours (depends on binlog volume)

**RPO**: 5-15 minutes (binlog flush interval)

---

## Disaster Recovery

### Complete Cluster Loss

**Scenario**: Entire Kubernetes cluster is lost, need to rebuild from scratch

**Recovery procedure**:

#### 1. Rebuild Kubernetes cluster

```bash
# (Cluster-specific steps - out of scope)
```

#### 2. Restore MySQL chart configuration

```bash
# Restore from Git or backup location
kubectl apply -f mysql-config-20250115.yaml
kubectl apply -f mysql-secret-20250115.yaml
```

#### 3. Deploy MySQL chart

```bash
helm install mysql sb-charts/mysql \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  -f values.yaml
```

#### 4. Wait for MySQL pod to be ready

```bash
kubectl wait --for=condition=ready pod/mysql-0 --timeout=300s
```

#### 5. Restore from backup

**Option A: From PVC snapshot** (fastest):
```bash
# Restore PVC from snapshot (see PVC Snapshot Restore section)
```

**Option B: From logical backup**:
```bash
# Restore latest full backup
make -f make/ops/mysql.mk mysql-restore-all \
  FILE=s3://mysql-backups/daily/mysql-all-20250114.sql.gz

# Apply binary logs since backup (if available)
make -f make/ops/mysql.mk mysql-pitr \
  RECOVERY_TIME='2025-01-15 09:00:00' \
  BASE_BACKUP=s3://mysql-backups/daily/mysql-all-20250114.sql.gz
```

#### 6. Verify data integrity

```bash
# Check database list
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"

# Check table counts
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SELECT
    table_schema,
    COUNT(*) as table_count,
    SUM(table_rows) as total_rows
  FROM information_schema.tables
  WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
  GROUP BY table_schema;
"

# Validate critical tables
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp -e "
  SELECT COUNT(*) FROM users;
  SELECT COUNT(*) FROM orders;
  SELECT MAX(created_at) FROM orders;  -- Check latest data
"
```

#### 7. Rebuild replication (if applicable)

```bash
# Deploy replica pods
helm upgrade mysql sb-charts/mysql --set replicaCount=2

# Setup replication from primary
make -f make/ops/mysql.mk mysql-setup-replication
```

#### 8. Resume application traffic

```bash
kubectl scale deployment myapp --replicas=3
```

**Total recovery time**: 2-6 hours (depends on data volume and backup location)

---

## Best Practices

### Backup Best Practices

1. **3-2-1 Rule**:
   - 3 copies of data (production + 2 backups)
   - 2 different storage types (local + cloud)
   - 1 offsite copy (S3/GCS/Azure)

2. **Test restores regularly**:
   - Monthly: Full restore test
   - Quarterly: Disaster recovery drill
   - Document recovery procedures

3. **Automate everything**:
   - Daily automated backups (CronJob)
   - Automated binary log archiving
   - Automated cleanup (retention policy)
   - Automated backup verification

4. **Monitor backup status**:
   - Backup success/failure alerts
   - Backup size trending (growth monitoring)
   - Last successful backup timestamp
   - Backup storage capacity

5. **Secure backups**:
   - Encrypt backups at rest (S3 SSE, encrypted PVCs)
   - Encrypt backups in transit (TLS)
   - Restrict access (RBAC, S3 bucket policies)
   - Separate backup credentials from production

6. **Document everything**:
   - Backup schedules and retention
   - Recovery procedures (this guide)
   - Recent restore tests
   - Contacts for escalation

### Performance Optimization

1. **Use --single-transaction** for InnoDB tables (no locking)
2. **Compress backups** to save storage and transfer time
3. **Use --master-data=2** to include binlog position
4. **Schedule backups during low-traffic periods** (e.g., 2-4 AM)
5. **Use parallel mysqldump** for very large databases (mydumper/myloader)
6. **Consider incremental backups** (binary logs) between full backups

### Retention Strategy

| Backup Type | Frequency | Retention | Storage Location |
|-------------|-----------|-----------|------------------|
| **Full logical backup** | Daily | 30 days | S3 (Standard) |
| **Incremental (binlogs)** | Continuous | 7 days | S3 (Standard) |
| **Weekly full backup** | Weekly | 90 days | S3 (Infrequent Access) |
| **Monthly backup** | Monthly | 1 year | S3 (Glacier) |
| **Configuration** | Daily | 90 days | Git + S3 |
| **PVC snapshot** | Weekly | 4 weeks | CSI Snapshots |

---

## Troubleshooting

### Common Issues

#### 1. mysqldump: Got error: 1044: Access denied

**Cause**: Insufficient privileges

**Solution**:
```sql
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
```

#### 2. Binary log replay fails: "Error in Log_event::read_log_event()"

**Cause**: Corrupted binary log file

**Solution**:
```bash
# Skip corrupted events (use with caution)
mysqlbinlog --start-position=12345 /var/lib/mysql/mysql-bin.000016

# Or manually inspect and extract good events
mysqlbinlog --base64-output=DECODE-ROWS /var/lib/mysql/mysql-bin.000016 | less
```

#### 3. Restore hangs during import

**Cause**: Large transaction or foreign key checks

**Solution**:
```sql
-- Disable checks during restore
SET FOREIGN_KEY_CHECKS=0;
SET UNIQUE_CHECKS=0;
SET AUTOCOMMIT=0;

-- Restore data

-- Re-enable checks
SET FOREIGN_KEY_CHECKS=1;
SET UNIQUE_CHECKS=1;
COMMIT;
```

#### 4. Out of disk space during backup

**Cause**: Backup volume full

**Solution**:
```bash
# Cleanup old backups
find /backup -name "*.sql.gz" -mtime +7 -delete

# Increase PVC size
kubectl patch pvc mysql-backup-pvc -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Or backup directly to S3 (skip local storage)
mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases | \
  gzip | aws s3 cp - s3://mysql-backups/mysql-all-$(date +%Y%m%d).sql.gz
```

#### 5. Replication lag increasing

**Cause**: Primary overloaded or replica underpowered

**Solution**:
```bash
# Check replication status
kubectl exec -it mysql-1 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW SLAVE STATUS\G" | grep Seconds_Behind_Master

# Increase replica resources
kubectl patch statefulset mysql-replica -p '{"spec":{"template":{"spec":{"containers":[{"name":"mysql","resources":{"limits":{"cpu":"2000m","memory":"4Gi"}}}]}}}}'

# Or temporarily stop replication during high load
kubectl exec -it mysql-1 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "STOP SLAVE;"
# ... high load period ...
kubectl exec -it mysql-1 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "START SLAVE;"
```

#### 6. Cannot restore: "ERROR 1840 (HY000): @@GLOBAL.GTID_PURGED can only be set when @@GLOBAL.GTID_EXECUTED is empty"

**Cause**: GTID mode enabled, need to reset

**Solution**:
```sql
RESET MASTER;  -- Clears GTID_EXECUTED
-- Then restore backup
```

#### 7. Backup verification fails

**Cause**: Backup file corrupted or incomplete

**Solution**:
```bash
# Check file integrity
gzip -t mysql-all-20250115.sql.gz

# Check SQL syntax
zcat mysql-all-20250115.sql.gz | mysql --help > /dev/null 2>&1 && echo "Valid SQL"

# Verify backup size is reasonable
ls -lh mysql-all-20250115.sql.gz

# Re-create backup if corrupted
make -f make/ops/mysql.mk mysql-backup-all
```

#### 8. PVC snapshot fails to restore

**Cause**: Snapshot corrupted or VolumeSnapshotClass misconfigured

**Solution**:
```bash
# Check snapshot status
kubectl get volumesnapshot mysql-snapshot-20250115 -o yaml

# Check snapshot logs
kubectl describe volumesnapshot mysql-snapshot-20250115

# Verify VolumeSnapshotClass
kubectl get volumesnapshotclass

# Try restoring from different snapshot
kubectl get volumesnapshot
```

---

## Appendix

### Backup Checklist

**Daily tasks**:
- [ ] Verify automated backup completed
- [ ] Check backup logs for errors
- [ ] Monitor backup storage usage

**Weekly tasks**:
- [ ] Test single database restore
- [ ] Verify binary log archiving working
- [ ] Review and cleanup old backups
- [ ] Create PVC snapshot

**Monthly tasks**:
- [ ] Full disaster recovery drill
- [ ] Review and update backup retention policy
- [ ] Verify offsite backups accessible
- [ ] Audit backup access logs

**Quarterly tasks**:
- [ ] Review backup strategy alignment with RTO/RPO goals
- [ ] Update disaster recovery documentation
- [ ] Validate backup encryption
- [ ] Capacity planning for backup storage

### Reference Commands

```bash
# Backup commands
make -f make/ops/mysql.mk mysql-backup DATABASE=myapp
make -f make/ops/mysql.mk mysql-backup-all
make -f make/ops/mysql.mk mysql-backup-config
make -f make/ops/mysql.mk mysql-archive-binlogs
make -f make/ops/mysql.mk mysql-backup-pvc-snapshot

# Restore commands
make -f make/ops/mysql.mk mysql-restore DATABASE=myapp FILE=backup.sql.gz
make -f make/ops/mysql.mk mysql-restore-all FILE=all-databases.sql.gz
make -f make/ops/mysql.mk mysql-pitr RECOVERY_TIME='2025-01-15 14:30:00'

# Verification commands
make -f make/ops/mysql.mk mysql-backup-verify FILE=backup.sql.gz
make -f make/ops/mysql.mk mysql-show-binlogs
make -f make/ops/mysql.mk mysql-replication-status

# Maintenance commands
make -f make/ops/mysql.mk mysql-flush-logs
make -f make/ops/mysql.mk mysql-purge-binlogs BEFORE='2025-01-01'
make -f make/ops/mysql.mk mysql-optimize-tables
```

### External Resources

- [MySQL Official Backup Documentation](https://dev.mysql.com/doc/refman/8.0/en/backup-and-recovery.html)
- [mysqldump Reference](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
- [mysqlbinlog Reference](https://dev.mysql.com/doc/refman/8.0/en/mysqlbinlog.html)
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [Kubernetes VolumeSnapshot Documentation](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

---

**Document version**: 1.0
**Last updated**: 2025-01-15
**Author**: ScriptonBasestar Helm Charts Team
