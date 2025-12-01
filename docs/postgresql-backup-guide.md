# PostgreSQL Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for PostgreSQL deployed via the Helm chart, including Point-in-Time Recovery (PITR) capabilities.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Configuration Backup](#1-configuration-backup)
  - [2. Database Dumps](#2-database-dumps)
  - [3. WAL Archiving](#3-wal-archiving)
  - [4. Replication Metadata](#4-replication-metadata)
  - [5. PVC Snapshot Backup](#5-pvc-snapshot-backup)
- [Backup Procedures](#backup-procedures)
  - [Full Backup](#full-backup)
  - [Logical Backup (pg_dump)](#logical-backup-pg_dump)
  - [Physical Backup (pg_basebackup)](#physical-backup-pg_basebackup)
  - [Continuous Archiving](#continuous-archiving)
- [Recovery Procedures](#recovery-procedures)
  - [Full Recovery](#full-recovery)
  - [Logical Recovery (pg_restore)](#logical-recovery-pg_restore)
  - [Point-in-Time Recovery](#point-in-time-recovery)
  - [Replication Recovery](#replication-recovery)
- [Backup Automation](#backup-automation)
- [Backup Verification](#backup-verification)
- [RTO & RPO Targets](#rto--rpo-targets)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Strategy

PostgreSQL backup strategy depends on deployment mode and recovery requirements:

| Backup Type | Method | RPO | Use Case |
|-------------|--------|-----|----------|
| **Logical** | pg_dump/pg_dumpall | Hours-Days | Schema changes, migrations, portability |
| **Physical** | pg_basebackup | Minutes | Full cluster recovery, fast restore |
| **Continuous** | WAL archiving | Seconds-Minutes | Point-in-Time Recovery (PITR) |
| **Snapshot** | PVC snapshot | Minutes | Disaster recovery, fast clone |

### Key Backup Components

1. **Configuration** - ConfigMaps (postgresql.conf, pg_hba.conf), Secrets (passwords)
2. **Database Dumps** - pg_dump (single database), pg_dumpall (all databases, roles, tablespaces)
3. **WAL Archives** - Write-Ahead Log files for Point-in-Time Recovery
4. **Replication Metadata** - Replication slots, standby configuration
5. **PVC Snapshots** - Complete data directory snapshot

### RTO/RPO Summary

| Component | RTO (Recovery Time) | RPO (Recovery Point) | Backup Frequency |
|-----------|-------------------|---------------------|-----------------|
| Configuration | < 5 minutes | 0 | Before changes |
| pg_dump (single DB) | 10-60 minutes | 24 hours | Daily |
| pg_dumpall (cluster) | 30-120 minutes | 24 hours | Daily |
| WAL archiving | < 1 hour | 15 minutes | Continuous |
| pg_basebackup | 30-60 minutes | 24 hours | Daily |
| PVC Snapshot | < 30 minutes | 24 hours | Daily |

---

## Backup Strategy

### Architecture Overview

```
+-------------------------------------------------------------------------+
|                    PostgreSQL Backup Components                          |
+-------------------------------------------------------------------------+
|                                                                          |
|  +------------------+  +------------------+  +------------------+        |
|  | Configuration    |  | Database Dumps   |  | WAL Archives     |        |
|  | - postgresql.conf|  | - pg_dump        |  | - Continuous     |        |
|  | - pg_hba.conf    |  | - pg_dumpall     |  | - PITR enabled   |        |
|  | - Secrets        |  | - Custom format  |  | - 16MB segments  |        |
|  +--------+---------+  +--------+---------+  +--------+---------+        |
|           |                     |                     |                  |
|           +---------------------+---------------------+                  |
|                                 |                                        |
|                                 v                                        |
|  +------------------------------------------------------------------+   |
|  |               Backup Storage (S3/MinIO/NFS)                       |   |
|  |  - /backups/postgresql/config/                                    |   |
|  |  - /backups/postgresql/dumps/                                     |   |
|  |  - /backups/postgresql/wal/                                       |   |
|  |  - /backups/postgresql/basebackup/                                |   |
|  |  - /backups/postgresql/pvc-snapshots/                             |   |
|  +------------------------------------------------------------------+   |
|                                                                          |
+-------------------------------------------------------------------------+
```

### PostgreSQL Data Flow

```
+-----------------------------------------------------------------------+
|                     PostgreSQL Data Flow                               |
+-----------------------------------------------------------------------+
|                                                                        |
|  Client Connections                                                    |
|        |                                                               |
|        v                                                               |
|  +-----------+     +-------------+     +---------------+              |
|  | Shared    |---->| WAL Buffer  |---->| WAL Files     |              |
|  | Buffers   |     | (in memory) |     | (pg_wal/)     |              |
|  +-----------+     +-------------+     +-------+-------+              |
|        |                                       |                       |
|        v                                       v                       |
|  +-----------+                        +----------------+               |
|  | Data Files|                        | WAL Archive    |               |
|  | (base/)   |                        | (S3/NFS/local) |               |
|  +-----------+                        +----------------+               |
|        |                                       |                       |
|        v                                       v                       |
|  [pg_basebackup]                      [Point-in-Time Recovery]         |
|  [pg_dump/pg_dumpall]                 [Streaming Replication]          |
|                                                                        |
+-----------------------------------------------------------------------+
```

### Replication Architecture

```
+-----------------------------------------------------------------------+
|                     Primary-Replica Replication                        |
+-----------------------------------------------------------------------+
|                                                                        |
|  +------------------+       WAL Streaming      +------------------+    |
|  |    Primary       |------------------------->|    Replica       |    |
|  |  (postgresql-0)  |                          |  (postgresql-1)  |    |
|  |                  |                          |                  |    |
|  |  - Read/Write    |                          |  - Read-only     |    |
|  |  - WAL generation|                          |  - Hot standby   |    |
|  |  - Archive       |                          |  - Backup target |    |
|  +--------+---------+                          +--------+---------+    |
|           |                                             |              |
|           |            +------------------+             |              |
|           +----------->| WAL Archive      |<------------+              |
|                        | (S3/MinIO/NFS)   |                            |
|                        +------------------+                            |
|                                 |                                      |
|                                 v                                      |
|                        +------------------+                            |
|                        | Point-in-Time    |                            |
|                        | Recovery (PITR)  |                            |
|                        +------------------+                            |
|                                                                        |
+-----------------------------------------------------------------------+
```

### Backup Strategy Decision Matrix

| Scenario | Recommended Strategy | RTO | RPO |
|----------|---------------------|-----|-----|
| Development | pg_dump daily | 1 hour | 24 hours |
| Small Production | pg_dump + WAL archiving | 30 min | 15 min |
| Large Production | pg_basebackup + WAL + Snapshots | 15 min | 5 min |
| Critical Systems | Streaming replication + PITR | 5 min | 0-1 min |

---

## Backup Components

### 1. Configuration Backup

Configuration includes PostgreSQL settings, authentication rules, and secrets.

#### Backup Configuration

```bash
# Backup ConfigMap using Makefile
make -f make/ops/postgresql.mk pg-backup-config

# Or manually export ConfigMap and Secrets
NAMESPACE=default
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/config/$TIMESTAMP

mkdir -p $BACKUP_DIR

# Backup ConfigMap
kubectl get configmap -n $NAMESPACE postgresql -o yaml > \
  $BACKUP_DIR/configmap.yaml

# Backup Secrets (encrypted)
kubectl get secret -n $NAMESPACE postgresql-secret -o yaml > \
  $BACKUP_DIR/secret.yaml

# Backup with encryption (recommended for secrets)
kubectl get secret -n $NAMESPACE postgresql-secret -o yaml | \
  gpg --symmetric --cipher-algo AES256 > $BACKUP_DIR/secret.yaml.gpg
```

#### What's Included

**ConfigMap contents:**
- `postgresql.conf` - Main PostgreSQL configuration
  - Connection settings (max_connections, listen_addresses)
  - Memory settings (shared_buffers, work_mem, effective_cache_size)
  - WAL settings (wal_level, max_wal_senders, wal_keep_size)
  - Replication settings (synchronous_standby_names)
  - Logging settings (log_statement, log_duration)
- `pg_hba.conf` - Host-based authentication rules
  - Local connections (trust/md5/scram-sha-256)
  - Host connections (IP ranges, SSL requirements)
  - Replication connections

**Secret contents:**
- `postgres-password` - PostgreSQL superuser password
- `replication-password` - Replication user password (if enabled)
- Custom user passwords (if configured)

#### Storage Requirements

- Size: ~10-50 KB
- Retention: 90 days recommended
- Backup frequency: Before any configuration changes

---

### 2. Database Dumps

Database dumps provide logical backups of databases, schemas, and data.

#### pg_dump - Single Database Backup

```bash
# Backup single database using Makefile
make -f make/ops/postgresql.mk pg-backup

# Or manually
NAMESPACE=default
POD_NAME=postgresql-0
DATABASE=postgres
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/dumps

mkdir -p $BACKUP_DIR

# Plain SQL format (human-readable, portable)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE > \
  $BACKUP_DIR/$DATABASE-$TIMESTAMP.sql

# Custom format (compressed, supports parallel restore)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' -Fc' > \
  $BACKUP_DIR/$DATABASE-$TIMESTAMP.dump

# Directory format (parallel backup/restore)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' -Fd -j 4 -f /tmp/backup'
kubectl cp $NAMESPACE/$POD_NAME:/tmp/backup $BACKUP_DIR/$DATABASE-$TIMESTAMP-dir

echo "Backup saved to $BACKUP_DIR"
```

#### pg_dumpall - Cluster-Wide Backup

```bash
# Backup all databases using Makefile
make -f make/ops/postgresql.mk pg-backup-all

# Or manually
NAMESPACE=default
POD_NAME=postgresql-0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/dumps

mkdir -p $BACKUP_DIR

# Backup everything (databases, roles, tablespaces)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' > \
  $BACKUP_DIR/cluster-$TIMESTAMP.sql

# Backup only global objects (roles, tablespaces)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --globals-only' > \
  $BACKUP_DIR/globals-$TIMESTAMP.sql

# Backup only schema (no data)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --schema-only' > \
  $BACKUP_DIR/schema-$TIMESTAMP.sql

echo "Cluster backup saved to $BACKUP_DIR"
```

#### Backup Formats Comparison

| Format | Extension | Compression | Parallel Restore | Selective Restore |
|--------|-----------|-------------|------------------|-------------------|
| Plain SQL | .sql | No (gzip externally) | No | Manual |
| Custom | .dump | Yes (built-in) | Yes | Yes (pg_restore) |
| Directory | folder | Yes (per table) | Yes (best) | Yes |
| Tar | .tar | No | No | Yes |

#### Large Object (BLOB) Backup

```bash
# Include large objects in backup
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d mydb --blobs -Fc' > \
  $BACKUP_DIR/mydb-with-blobs-$TIMESTAMP.dump

# Backup only large objects
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d mydb --blobs --data-only -t pg_largeobject -Fc' > \
  $BACKUP_DIR/mydb-blobs-only-$TIMESTAMP.dump
```

#### Storage Requirements

| Database Size | Dump Size (compressed) | Backup Time | Retention |
|---------------|------------------------|-------------|-----------|
| < 1 GB | 50-200 MB | < 5 min | 30 days |
| 1-10 GB | 200 MB - 2 GB | 5-30 min | 14 days |
| 10-100 GB | 2-20 GB | 30 min - 4 hours | 7 days |
| > 100 GB | 20+ GB | 4+ hours | 3 days |

---

### 3. WAL Archiving

Write-Ahead Log (WAL) archiving enables Point-in-Time Recovery (PITR) and continuous backup.

#### Understanding WAL

- **Location:** `/var/lib/postgresql/data/pg_wal/`
- **Segment size:** 16 MB per file
- **Naming:** 24-character hexadecimal (e.g., `000000010000000000000001`)
- **Purpose:** Transaction log for crash recovery and replication
- **PITR capability:** Restore to any point in time

#### Enable WAL Archiving

**Configure in values.yaml:**

```yaml
postgresql:
  config:
    archive_mode: "on"
    archive_command: "cp %p /var/lib/postgresql/archive/%f"
    # Or for S3:
    # archive_command: "aws s3 cp %p s3://my-bucket/wal-archive/%f"
    wal_level: "replica"
    max_wal_senders: 10
    wal_keep_size: "1GB"
```

#### Manual WAL Archiving Setup

```bash
# Create archive directory
kubectl exec -n $NAMESPACE $POD_NAME -- mkdir -p /var/lib/postgresql/archive

# Configure archive_command
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    ALTER SYSTEM SET archive_mode = on;
    ALTER SYSTEM SET archive_command = '\''cp %p /var/lib/postgresql/archive/%f'\'';
    ALTER SYSTEM SET wal_level = replica;
  "'

# Reload configuration
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_reload_conf();"'

# Note: archive_mode requires restart to take effect
kubectl rollout restart statefulset postgresql -n $NAMESPACE
```

#### Backup WAL Archives

```bash
# Backup WAL archives using Makefile
make -f make/ops/postgresql.mk pg-backup-wal

# Or manually
NAMESPACE=default
POD_NAME=postgresql-0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/wal

mkdir -p $BACKUP_DIR

# Force a WAL switch to archive current WAL
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_switch_wal();"'

# Wait for archive to complete
sleep 5

# Backup archived WAL files
kubectl exec -n $NAMESPACE $POD_NAME -- \
  tar czf - /var/lib/postgresql/archive 2>/dev/null | \
  cat > $BACKUP_DIR/wal-archive-$TIMESTAMP.tar.gz

echo "WAL archive backup saved to $BACKUP_DIR"
```

#### S3 WAL Archiving with pgBackRest

```bash
# Example pgBackRest configuration
cat > /etc/pgbackrest.conf <<EOF
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=7
repo1-type=s3
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-bucket=my-pg-backups
repo1-s3-region=us-east-1

[mydb]
pg1-path=/var/lib/postgresql/data
EOF

# Configure archive_command
archive_command = 'pgbackrest --stanza=mydb archive-push %p'

# Configure restore_command
restore_command = 'pgbackrest --stanza=mydb archive-get %f %p'
```

#### WAL Archiving Monitoring

```bash
# Check archive status
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT * FROM pg_stat_archiver;
  "'

# Check WAL files pending archive
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT * FROM pg_stat_activity WHERE backend_type = '\''archiver'\'';
  "'

# Check current WAL position
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());
  "'
```

#### Storage Requirements

| Transaction Rate | WAL per Hour | Daily Storage | Retention |
|------------------|--------------|---------------|-----------|
| Low (< 100 TPS) | 16-48 MB | 400 MB - 1 GB | 7 days |
| Medium (100-1000 TPS) | 48-480 MB | 1-10 GB | 3 days |
| High (> 1000 TPS) | 480 MB - 4 GB | 10-100 GB | 1 day |

---

### 4. Replication Metadata

Replication metadata includes slots, configurations, and standby settings.

#### Backup Replication Slots

```bash
# List replication slots
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn
    FROM pg_replication_slots;
  "'

# Backup replication slot information
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "
    SELECT '\''SELECT pg_create_physical_replication_slot('\''||quote_literal(slot_name)||'\'');'\''
    FROM pg_replication_slots
    WHERE slot_type = '\''physical'\'';
  "' > $BACKUP_DIR/replication-slots-$TIMESTAMP.sql
```

#### Backup Replication Status

```bash
# Check replication status using Makefile
make -f make/ops/postgresql.mk pg-replication-status

# Or manually
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT
      client_addr,
      state,
      sent_lsn,
      write_lsn,
      flush_lsn,
      replay_lsn,
      sync_state,
      pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
    FROM pg_stat_replication;
  "'
```

#### Backup Tablespace Definitions

```bash
# Backup tablespace definitions
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT
      spcname AS name,
      pg_tablespace_location(oid) AS location,
      pg_size_pretty(pg_tablespace_size(oid)) AS size
    FROM pg_tablespace
    WHERE spcname NOT IN ('\''pg_default'\'', '\''pg_global'\'');
  "' > $BACKUP_DIR/tablespaces-$TIMESTAMP.txt

# Create tablespace recreation script
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "
    SELECT '\''CREATE TABLESPACE '\'' || spcname || '\'' LOCATION '\'''\'''' || pg_tablespace_location(oid) || '\''\'''\'';'\''
    FROM pg_tablespace
    WHERE spcname NOT IN ('\''pg_default'\'', '\''pg_global'\'');
  "' > $BACKUP_DIR/create-tablespaces-$TIMESTAMP.sql
```

---

### 5. PVC Snapshot Backup

Complete persistent volume backup using Kubernetes VolumeSnapshot API.

#### Prerequisites

- CSI driver with snapshot support installed
- VolumeSnapshotClass configured
- Sufficient storage for snapshots

#### Create PVC Snapshot

```bash
# Create PVC snapshot using Makefile
make -f make/ops/postgresql.mk pg-backup-pvc-snapshot

# Or manually
NAMESPACE=default
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Force checkpoint before snapshot for consistency
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CHECKPOINT;"'

# Create VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgresql-pvc-snapshot-$TIMESTAMP
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: postgresql
    backup-date: "$(date +%Y-%m-%d)"
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: data-postgresql-0
EOF

# Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/postgresql-pvc-snapshot-$TIMESTAMP -n $NAMESPACE --timeout=300s
```

#### Verify Snapshot

```bash
# Check snapshot status
kubectl get volumesnapshot -n $NAMESPACE postgresql-pvc-snapshot-$TIMESTAMP

# Get detailed status
kubectl describe volumesnapshot -n $NAMESPACE postgresql-pvc-snapshot-$TIMESTAMP

# List all PostgreSQL snapshots
kubectl get volumesnapshot -n $NAMESPACE -l app.kubernetes.io/name=postgresql
```

#### Storage Requirements

- Size: Same as PVC (typically 10-100+ GB)
- Retention: 7-14 days
- Backup frequency: Daily (after business hours)

---

## Backup Procedures

### Full Backup

Complete backup of all PostgreSQL components for disaster recovery.

#### Automated Full Backup

```bash
# Full backup using Makefile
make -f make/ops/postgresql.mk pg-backup-full
```

#### Manual Full Backup Script

```bash
#!/bin/bash
# full-backup.sh - Complete PostgreSQL backup
# Usage: NAMESPACE=default S3_BUCKET=my-backups ./full-backup.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-postgresql-0}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT="./backups/postgresql"
BACKUP_DIR="$BACKUP_ROOT/full/$TIMESTAMP"

mkdir -p $BACKUP_DIR/{config,dumps,wal,metadata,slots}

echo "=== PostgreSQL Full Backup Started: $TIMESTAMP ==="

# 1. Force checkpoint for consistency
echo "[1/8] Creating checkpoint..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CHECKPOINT;"'

# 2. Backup configuration
echo "[2/8] Backing up configuration..."
kubectl get configmap -n $NAMESPACE postgresql -o yaml > \
  $BACKUP_DIR/config/configmap.yaml
kubectl get secret -n $NAMESPACE postgresql-secret -o yaml > \
  $BACKUP_DIR/config/secret.yaml

# 3. Backup Kubernetes metadata
echo "[3/8] Backing up Kubernetes metadata..."
kubectl get statefulset -n $NAMESPACE postgresql -o yaml > \
  $BACKUP_DIR/metadata/statefulset.yaml
kubectl get service -n $NAMESPACE postgresql -o yaml > \
  $BACKUP_DIR/metadata/service.yaml
kubectl get pvc -n $NAMESPACE data-postgresql-0 -o yaml > \
  $BACKUP_DIR/metadata/pvc.yaml

# 4. Backup global objects (roles, tablespaces)
echo "[4/8] Backing up global objects..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --globals-only' > \
  $BACKUP_DIR/dumps/globals.sql

# 5. Backup all databases
echo "[5/8] Backing up all databases..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' > \
  $BACKUP_DIR/dumps/cluster.sql

# 6. Backup individual databases with custom format
echo "[6/8] Backing up individual databases (custom format)..."
DATABASES=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "
    SELECT datname FROM pg_database
    WHERE datistemplate = false AND datname != '\''postgres'\'';"')

for DB in $DATABASES; do
  DB=$(echo $DB | tr -d ' ')
  if [ -n "$DB" ]; then
    echo "  Backing up database: $DB"
    kubectl exec -n $NAMESPACE $POD_NAME -- \
      sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DB' -Fc' > \
      $BACKUP_DIR/dumps/$DB.dump
  fi
done

# 7. Backup replication slots
echo "[7/8] Backing up replication metadata..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT * FROM pg_replication_slots;"' > \
  $BACKUP_DIR/slots/replication-slots.txt

kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT * FROM pg_stat_replication;"' > \
  $BACKUP_DIR/slots/replication-status.txt 2>/dev/null || echo "No replicas connected"

# 8. Force WAL switch and backup archives
echo "[8/8] Backing up WAL archives..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_switch_wal();"' \
  2>/dev/null || echo "WAL switch not available"

kubectl exec -n $NAMESPACE $POD_NAME -- \
  tar czf - /var/lib/postgresql/archive 2>/dev/null | \
  cat > $BACKUP_DIR/wal/wal-archive.tar.gz || echo "WAL archiving not enabled"

# Create backup manifest
PG_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SHOW server_version;"' | tr -d ' ')

cat > $BACKUP_DIR/backup-manifest.yaml <<EOF
backup:
  timestamp: $TIMESTAMP
  namespace: $NAMESPACE
  pod: $POD_NAME
  type: full
  components:
    - config
    - dumps
    - wal
    - metadata
    - slots
  postgresql_version: $PG_VERSION
  backup_size: $(du -sh $BACKUP_DIR | awk '{print $1}')
  databases: $(echo $DATABASES | tr '\n' ' ')
EOF

echo ""
echo "=== PostgreSQL Full Backup Complete ==="
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Backup contents:"
du -sh $BACKUP_DIR/*

# Optional: Upload to S3/MinIO
if [ -n "$S3_BUCKET" ]; then
  echo ""
  echo "Uploading to S3..."
  tar czf - -C $BACKUP_ROOT/full $TIMESTAMP | \
    aws s3 cp - s3://$S3_BUCKET/postgresql/full/postgresql-backup-$TIMESTAMP.tar.gz
  echo "Upload complete: s3://$S3_BUCKET/postgresql/full/postgresql-backup-$TIMESTAMP.tar.gz"
fi
```

---

### Logical Backup (pg_dump)

Logical backups for database migration, schema changes, and portability.

#### Single Database Backup

```bash
# Backup specific database using Makefile
make -f make/ops/postgresql.mk pg-backup POSTGRES_DB=myapp

# Or manually with various formats
NAMESPACE=default
POD_NAME=postgresql-0
DATABASE=myapp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/dumps

mkdir -p $BACKUP_DIR

# Plain SQL (human-readable)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE > \
  $BACKUP_DIR/$DATABASE-$TIMESTAMP.sql

# Custom format (recommended for large databases)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' -Fc -Z9' > \
  $BACKUP_DIR/$DATABASE-$TIMESTAMP.dump

# Schema only
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' --schema-only' > \
  $BACKUP_DIR/$DATABASE-schema-$TIMESTAMP.sql

# Data only (for selective restore)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' --data-only -Fc' > \
  $BACKUP_DIR/$DATABASE-data-$TIMESTAMP.dump
```

#### Selective Table Backup

```bash
# Backup specific tables
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' \
    -t users -t orders -t products -Fc' > \
  $BACKUP_DIR/$DATABASE-selected-tables-$TIMESTAMP.dump

# Exclude specific tables
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' \
    --exclude-table=logs --exclude-table=audit_trail -Fc' > \
  $BACKUP_DIR/$DATABASE-without-logs-$TIMESTAMP.dump

# Backup specific schema
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d '$DATABASE' \
    -n public -Fc' > \
  $BACKUP_DIR/$DATABASE-public-schema-$TIMESTAMP.dump
```

---

### Physical Backup (pg_basebackup)

Physical backups for fast recovery and PITR base backups.

#### Create pg_basebackup

```bash
# Full physical backup using Makefile
make -f make/ops/postgresql.mk pg-basebackup

# Or manually
NAMESPACE=default
POD_NAME=postgresql-0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=./backups/postgresql/basebackup

mkdir -p $BACKUP_DIR

# Create base backup inside pod
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup \
    -h localhost -U postgres \
    -D /tmp/basebackup-'$TIMESTAMP' \
    -Fp -Xs -P -R'

# Copy backup to local
kubectl exec -n $NAMESPACE $POD_NAME -- \
  tar czf - /tmp/basebackup-$TIMESTAMP | \
  cat > $BACKUP_DIR/basebackup-$TIMESTAMP.tar.gz

# Cleanup temp backup in pod
kubectl exec -n $NAMESPACE $POD_NAME -- \
  rm -rf /tmp/basebackup-$TIMESTAMP

echo "Base backup saved to $BACKUP_DIR/basebackup-$TIMESTAMP.tar.gz"
```

#### pg_basebackup Options

```bash
# Standard backup with progress
pg_basebackup -h localhost -U postgres -D /backup/data -Fp -Xs -P

# Compressed tar format
pg_basebackup -h localhost -U postgres -D /backup -Ft -z -P

# Include WAL files needed for recovery
pg_basebackup -h localhost -U postgres -D /backup/data -Fp -Xs -P

# Create standby configuration (for replica)
pg_basebackup -h localhost -U postgres -D /backup/data -Fp -Xs -P -R

# Parallel backup (PostgreSQL 15+)
pg_basebackup -h localhost -U postgres -D /backup/data -Fp -Xs -P --jobs=4
```

#### Verify pg_basebackup

```bash
# Verify backup integrity (PostgreSQL 13+)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  pg_verifybackup /tmp/basebackup-$TIMESTAMP

# Check backup contents
tar tzf $BACKUP_DIR/basebackup-$TIMESTAMP.tar.gz | head -20
```

---

### Continuous Archiving

Set up continuous WAL archiving for Point-in-Time Recovery.

#### Enable Continuous Archiving to S3

```yaml
# values.yaml configuration
postgresql:
  config:
    archive_mode: "on"
    archive_command: "aws s3 cp %p s3://my-bucket/wal-archive/%f"
    archive_timeout: "300"  # Force archive every 5 minutes
    wal_level: "replica"
```

#### Enable Continuous Archiving to NFS/Local

```yaml
postgresql:
  config:
    archive_mode: "on"
    archive_command: "cp %p /var/lib/postgresql/archive/%f && sync"
    archive_timeout: "60"
    wal_level: "replica"

  extraVolumes:
    - name: wal-archive
      persistentVolumeClaim:
        claimName: postgresql-wal-archive

  extraVolumeMounts:
    - name: wal-archive
      mountPath: /var/lib/postgresql/archive
```

#### Monitor Archive Status

```bash
# Check archive stats
make -f make/ops/postgresql.mk pg-archive-status

# Or manually
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT
      archived_count,
      last_archived_wal,
      last_archived_time,
      failed_count,
      last_failed_wal,
      last_failed_time
    FROM pg_stat_archiver;
  "'
```

---

## Recovery Procedures

### Full Recovery

Complete restoration from full backup for disaster recovery.

#### Automated Full Recovery

```bash
# Full recovery using Makefile
make -f make/ops/postgresql.mk pg-restore-full BACKUP_DIR=/path/to/backup
```

#### Manual Full Recovery Script

```bash
#!/bin/bash
# full-restore.sh - Complete PostgreSQL restoration
# Usage: ./full-restore.sh /path/to/backup-directory

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <backup-directory>"
  exit 1
fi

BACKUP_DIR="$1"
NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-postgresql-0}"

echo "=== PostgreSQL Full Recovery Started ==="
echo "Backup source: $BACKUP_DIR"

# 1. Verify backup
if [ ! -f "$BACKUP_DIR/backup-manifest.yaml" ]; then
  echo "ERROR: Invalid backup directory (no manifest found)"
  exit 1
fi

echo "Backup manifest:"
cat $BACKUP_DIR/backup-manifest.yaml

# 2. Confirm recovery
echo ""
read -p "This will REPLACE ALL DATA. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Recovery cancelled."
  exit 0
fi

# 3. Scale down PostgreSQL
echo "[1/7] Scaling down PostgreSQL..."
kubectl scale statefulset postgresql -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql --timeout=300s || true

# 4. Restore configuration
echo "[2/7] Restoring configuration..."
if [ -f "$BACKUP_DIR/config/configmap.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/configmap.yaml
  echo "  ConfigMap restored"
fi

if [ -f "$BACKUP_DIR/config/secret.yaml" ]; then
  kubectl apply -f $BACKUP_DIR/config/secret.yaml
  echo "  Secret restored"
fi

# 5. Scale up PostgreSQL
echo "[3/7] Scaling up PostgreSQL..."
kubectl scale statefulset postgresql -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE $POD_NAME --timeout=300s

# 6. Wait for PostgreSQL to be ready
echo "[4/7] Waiting for PostgreSQL to initialize..."
sleep 30

# Test connection
until kubectl exec -n $NAMESPACE $POD_NAME -- \
  pg_isready -U postgres -d postgres; do
  echo "  Waiting for PostgreSQL..."
  sleep 5
done

# 7. Restore global objects
echo "[5/7] Restoring global objects (roles, tablespaces)..."
if [ -f "$BACKUP_DIR/dumps/globals.sql" ]; then
  cat $BACKUP_DIR/dumps/globals.sql | \
    kubectl exec -i -n $NAMESPACE $POD_NAME -- \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres' || true
  echo "  Global objects restored"
fi

# 8. Restore cluster data
echo "[6/7] Restoring cluster data..."
if [ -f "$BACKUP_DIR/dumps/cluster.sql" ]; then
  cat $BACKUP_DIR/dumps/cluster.sql | \
    kubectl exec -i -n $NAMESPACE $POD_NAME -- \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres'
  echo "  Cluster data restored"
fi

# 9. Verify recovery
echo "[7/7] Verifying recovery..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "\l"'

echo ""
echo "=== PostgreSQL Full Recovery Complete ==="
echo ""
echo "Verification:"
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database
    WHERE datistemplate = false
    ORDER BY pg_database_size(datname) DESC;
  "'
```

---

### Logical Recovery (pg_restore)

Restore databases from pg_dump backups.

#### Restore Single Database

```bash
# Restore database using Makefile
make -f make/ops/postgresql.mk pg-restore FILE=/path/to/backup.dump

# Restore from SQL file
cat backup.sql | kubectl exec -i -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d myapp'

# Restore from custom format (.dump)
kubectl cp backup.dump $NAMESPACE/$POD_NAME:/tmp/backup.dump
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp -Fc /tmp/backup.dump'
kubectl exec -n $NAMESPACE $POD_NAME -- rm /tmp/backup.dump

# Restore with parallel jobs (faster for large databases)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp -Fc -j 4 /tmp/backup.dump'
```

#### Restore to New Database

```bash
# Create new database and restore
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CREATE DATABASE myapp_restored;"'

kubectl cp backup.dump $NAMESPACE/$POD_NAME:/tmp/backup.dump

kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp_restored -Fc /tmp/backup.dump'
```

#### Selective Restore

```bash
# Restore specific tables only
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp -Fc \
    -t users -t orders /tmp/backup.dump'

# Restore schema only (no data)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp -Fc \
    --schema-only /tmp/backup.dump'

# Restore data only (schema already exists)
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d myapp -Fc \
    --data-only /tmp/backup.dump'

# List contents of backup before restore
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'pg_restore -l /tmp/backup.dump'
```

---

### Point-in-Time Recovery

Restore database to a specific point in time using base backup and WAL archives.

#### PITR Requirements

1. Base backup (pg_basebackup) before the target recovery time
2. All WAL archives from base backup to target time
3. PostgreSQL stopped during recovery

#### PITR Architecture

```
+-----------------------------------------------------------------------+
|                     Point-in-Time Recovery Flow                        |
+-----------------------------------------------------------------------+
|                                                                        |
|  [Base Backup]          [WAL Archive]           [Target Time]          |
|  2024-01-01 00:00       00:00 -----> 15:30      2024-01-01 12:00      |
|       |                      |                        |                |
|       v                      v                        v                |
|  +----------+          +----------+            +-----------+           |
|  | Restore  |    +     | Replay   |    =       | Recovered |           |
|  | Base     |          | WAL to   |            | Database  |           |
|  | Backup   |          | Target   |            | at 12:00  |           |
|  +----------+          +----------+            +-----------+           |
|                                                                        |
+-----------------------------------------------------------------------+
```

#### Perform PITR

```bash
#!/bin/bash
# pitr-restore.sh - Point-in-Time Recovery
# Usage: ./pitr-restore.sh <base-backup-path> <wal-archive-path> <target-time>

set -e

BASE_BACKUP="$1"           # /path/to/basebackup.tar.gz
WAL_ARCHIVE="$2"           # /path/to/wal-archive/
TARGET_TIME="$3"           # '2024-01-15 12:00:00'
NAMESPACE="${NAMESPACE:-default}"

echo "=== PostgreSQL Point-in-Time Recovery ==="
echo "Base backup: $BASE_BACKUP"
echo "WAL archive: $WAL_ARCHIVE"
echo "Target time: $TARGET_TIME"

# 1. Scale down PostgreSQL
echo "[1/6] Scaling down PostgreSQL..."
kubectl scale statefulset postgresql -n $NAMESPACE --replicas=0
kubectl wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql --timeout=300s || true

# 2. Clear existing data (DESTRUCTIVE)
echo "[2/6] Clearing existing data..."
# Note: Use PVC restore or manual cleanup depending on your setup

# 3. Scale up with empty data
kubectl scale statefulset postgresql -n $NAMESPACE --replicas=1
kubectl wait --for=condition=ready pod -n $NAMESPACE postgresql-0 --timeout=300s

# 4. Stop PostgreSQL process (keep pod running)
echo "[3/6] Stopping PostgreSQL..."
kubectl exec -n $NAMESPACE postgresql-0 -- pg_ctl stop -D /var/lib/postgresql/data -m fast

# 5. Restore base backup
echo "[4/6] Restoring base backup..."
kubectl exec -n $NAMESPACE postgresql-0 -- rm -rf /var/lib/postgresql/data/*
kubectl cp $BASE_BACKUP $NAMESPACE/postgresql-0:/tmp/basebackup.tar.gz
kubectl exec -n $NAMESPACE postgresql-0 -- \
  tar xzf /tmp/basebackup.tar.gz -C /var/lib/postgresql/data --strip-components=1

# 6. Copy WAL archives
echo "[5/6] Restoring WAL archives..."
kubectl exec -n $NAMESPACE postgresql-0 -- mkdir -p /var/lib/postgresql/archive
kubectl cp $WAL_ARCHIVE/. $NAMESPACE/postgresql-0:/var/lib/postgresql/archive/

# 7. Configure recovery
echo "[6/6] Configuring recovery..."
kubectl exec -n $NAMESPACE postgresql-0 -- bash -c 'cat > /var/lib/postgresql/data/postgresql.auto.conf << EOF
restore_command = '\''cp /var/lib/postgresql/archive/%f %p'\''
recovery_target_time = '\''$TARGET_TIME'\''
recovery_target_action = '\''promote'\''
EOF'

# Create recovery signal file (PostgreSQL 12+)
kubectl exec -n $NAMESPACE postgresql-0 -- touch /var/lib/postgresql/data/recovery.signal

# 8. Start recovery
echo "Starting recovery..."
kubectl exec -n $NAMESPACE postgresql-0 -- \
  pg_ctl start -D /var/lib/postgresql/data -l /var/lib/postgresql/data/logfile

# Wait for recovery to complete
echo "Waiting for recovery to complete..."
until kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_is_in_recovery();"' 2>/dev/null | grep -q 'f'; do
  echo "  Recovery in progress..."
  sleep 10
done

echo ""
echo "=== Point-in-Time Recovery Complete ==="
echo "Database restored to: $TARGET_TIME"

# Verify
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT pg_is_in_recovery() AS in_recovery,
           pg_last_wal_replay_lsn() AS last_replay_lsn,
           pg_last_xact_replay_timestamp() AS last_replay_time;
  "'
```

#### PITR Target Options

```bash
# Recover to specific time
recovery_target_time = '2024-01-15 12:00:00 UTC'

# Recover to specific transaction ID
recovery_target_xid = '12345'

# Recover to specific named restore point
recovery_target_name = 'before_migration'

# Recover to specific WAL position
recovery_target_lsn = '0/1000000'

# Recover and pause (for verification)
recovery_target_action = 'pause'

# Recover and promote to primary
recovery_target_action = 'promote'

# Recover including the target (default)
recovery_target_inclusive = 'true'
```

#### Create Restore Points

```bash
# Create named restore point for future PITR
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT pg_create_restore_point('\''before_migration_v2'\'');
  "'

# List restore points in WAL
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT * FROM pg_stat_archiver;
  "'
```

---

### Replication Recovery

Restore and rebuild replication after failures.

#### Rebuild Replica from Primary

```bash
#!/bin/bash
# rebuild-replica.sh - Rebuild replica from primary
# Usage: ./rebuild-replica.sh <replica-pod-name>

REPLICA_POD="$1"
PRIMARY_POD="${PRIMARY_POD:-postgresql-0}"
NAMESPACE="${NAMESPACE:-default}"

echo "=== Rebuilding Replica: $REPLICA_POD ==="

# 1. Stop replica
echo "[1/4] Stopping replica..."
kubectl exec -n $NAMESPACE $REPLICA_POD -- pg_ctl stop -D /var/lib/postgresql/data -m fast || true

# 2. Clear replica data
echo "[2/4] Clearing replica data..."
kubectl exec -n $NAMESPACE $REPLICA_POD -- rm -rf /var/lib/postgresql/data/*

# 3. Get primary host
PRIMARY_HOST=$(kubectl get svc postgresql -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')

# 4. Create base backup from primary
echo "[3/4] Creating base backup from primary..."
kubectl exec -n $NAMESPACE $REPLICA_POD -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup \
    -h '$PRIMARY_HOST' -U replicator \
    -D /var/lib/postgresql/data \
    -Fp -Xs -P -R'

# 5. Start replica
echo "[4/4] Starting replica..."
kubectl exec -n $NAMESPACE $REPLICA_POD -- \
  pg_ctl start -D /var/lib/postgresql/data -l /var/lib/postgresql/data/logfile

echo ""
echo "=== Replica Rebuild Complete ==="

# Verify replication
sleep 10
kubectl exec -n $NAMESPACE $PRIMARY_POD -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT client_addr, state, sent_lsn, replay_lsn
    FROM pg_stat_replication;
  "'
```

#### Promote Replica to Primary

```bash
# Promote replica to primary (for failover)
kubectl exec -n $NAMESPACE postgresql-1 -- \
  pg_ctl promote -D /var/lib/postgresql/data

# Verify promotion
kubectl exec -n $NAMESPACE postgresql-1 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_is_in_recovery();"'
# Should return 'f' (false) after promotion
```

---

## Backup Automation

### CronJob for Scheduled Backups

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: postgresql-backup
          containers:
          - name: backup
            image: postgres:16
            command: ["/bin/bash", "-c"]
            args:
            - |
              set -e
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_DIR=/backup/postgresql/$TIMESTAMP

              echo "=== PostgreSQL Backup Started: $TIMESTAMP ==="

              mkdir -p $BACKUP_DIR/{dumps,wal}

              # Get PostgreSQL password
              export PGPASSWORD=$(cat /secrets/postgres-password)

              # 1. Backup globals
              echo "[1/4] Backing up global objects..."
              pg_dumpall -h postgresql -U postgres --globals-only > \
                $BACKUP_DIR/dumps/globals.sql

              # 2. Backup all databases
              echo "[2/4] Backing up cluster..."
              pg_dumpall -h postgresql -U postgres > \
                $BACKUP_DIR/dumps/cluster.sql

              # 3. Backup individual databases (custom format)
              echo "[3/4] Backing up individual databases..."
              DATABASES=$(psql -h postgresql -U postgres -t -c "
                SELECT datname FROM pg_database
                WHERE datistemplate = false AND datname != 'postgres';")

              for DB in $DATABASES; do
                DB=$(echo $DB | tr -d ' ')
                if [ -n "$DB" ]; then
                  echo "  Backing up: $DB"
                  pg_dump -h postgresql -U postgres -d $DB -Fc > \
                    $BACKUP_DIR/dumps/$DB.dump
                fi
              done

              # 4. Upload to S3
              echo "[4/4] Uploading to S3..."
              cd /backup/postgresql
              tar czf - $TIMESTAMP | \
                aws s3 cp - s3://${S3_BUCKET}/postgresql/postgresql-backup-$TIMESTAMP.tar.gz

              # Cleanup local backup
              rm -rf $BACKUP_DIR

              echo "=== Backup Complete ==="
              echo "Uploaded to: s3://${S3_BUCKET}/postgresql/postgresql-backup-$TIMESTAMP.tar.gz"
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
            - name: postgres-secret
              mountPath: /secrets
          restartPolicy: OnFailure
          volumes:
          - name: backup
            emptyDir: {}
          - name: postgres-secret
            secret:
              secretName: postgresql-secret
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgresql-backup
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: postgresql-backup
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec"]
  verbs: ["get", "list", "create"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: postgresql-backup
  namespace: default
subjects:
- kind: ServiceAccount
  name: postgresql-backup
  namespace: default
roleRef:
  kind: Role
  name: postgresql-backup
  apiGroup: rbac.authorization.k8s.io
```

### WAL Archive Cleanup CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-wal-cleanup
  namespace: default
spec:
  schedule: "0 4 * * *"  # Daily at 4 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: postgres:16
            command: ["/bin/bash", "-c"]
            args:
            - |
              # Delete WAL archives older than 7 days
              find /archive -name "*.gz" -mtime +7 -delete
              echo "Cleaned up WAL archives older than 7 days"
            volumeMounts:
            - name: wal-archive
              mountPath: /archive
          restartPolicy: OnFailure
          volumes:
          - name: wal-archive
            persistentVolumeClaim:
              claimName: postgresql-wal-archive
```

---

## Backup Verification

### Verify Backup Integrity

```bash
# Verify backup using Makefile
make -f make/ops/postgresql.mk pg-backup-verify BACKUP_DIR=/path/to/backup

# Or manually
BACKUP_DIR=/path/to/backup

echo "=== PostgreSQL Backup Verification ==="

# Check manifest
[ -f "$BACKUP_DIR/backup-manifest.yaml" ] && echo "[OK] Manifest found" || echo "[FAIL] Manifest missing"

# Check configuration
[ -f "$BACKUP_DIR/config/configmap.yaml" ] && echo "[OK] ConfigMap found" || echo "[FAIL] ConfigMap missing"
[ -f "$BACKUP_DIR/config/secret.yaml" ] && echo "[OK] Secret found" || echo "[WARN] Secret missing"

# Check dumps
[ -f "$BACKUP_DIR/dumps/globals.sql" ] && echo "[OK] Globals dump found" || echo "[FAIL] Globals missing"
[ -f "$BACKUP_DIR/dumps/cluster.sql" ] && echo "[OK] Cluster dump found" || echo "[FAIL] Cluster dump missing"

# Check dump sizes
echo ""
echo "Dump files:"
ls -lh $BACKUP_DIR/dumps/

# Validate SQL syntax (basic check)
echo ""
echo "Validating SQL syntax..."
for sql in $BACKUP_DIR/dumps/*.sql; do
  if head -1 "$sql" | grep -q "^--"; then
    echo "[OK] $sql has valid header"
  else
    echo "[WARN] $sql may be corrupted"
  fi
done

# Validate custom format dumps
echo ""
echo "Validating custom format dumps..."
for dump in $BACKUP_DIR/dumps/*.dump; do
  if [ -f "$dump" ]; then
    # pg_restore -l lists the TOC without restoring
    if pg_restore -l "$dump" > /dev/null 2>&1; then
      echo "[OK] $dump is valid"
    else
      echo "[FAIL] $dump is corrupted"
    fi
  fi
done
```

### Test Restore (Dry Run)

```bash
# Test restore to temporary database
NAMESPACE=default
POD_NAME=postgresql-0
BACKUP_FILE=/path/to/myapp.dump

# Create temporary database
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CREATE DATABASE restore_test;"'

# Restore to temporary database
kubectl cp $BACKUP_FILE $NAMESPACE/$POD_NAME:/tmp/test-restore.dump

kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d restore_test -Fc /tmp/test-restore.dump'

# Verify restore
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d restore_test -c "\dt"'

# Check row counts
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d restore_test -c "
    SELECT schemaname, relname, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY n_live_tup DESC
    LIMIT 10;
  "'

# Cleanup
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "DROP DATABASE restore_test;"'
kubectl exec -n $NAMESPACE $POD_NAME -- rm /tmp/test-restore.dump

echo "Restore test completed successfully"
```

---

## RTO & RPO Targets

### Recovery Time Objective (RTO)

| Scenario | RTO Target | Steps Required |
|----------|-----------|----------------|
| Configuration only | < 5 minutes | ConfigMap/Secret restore + restart |
| Single database restore | 10-60 minutes | pg_restore from backup |
| Full cluster restore | 30-120 minutes | Full backup restore + verification |
| Point-in-Time Recovery | < 1 hour | Base backup + WAL replay |
| Replica rebuild | 15-60 minutes | pg_basebackup from primary |
| PVC snapshot restore | < 30 minutes | Snapshot restore + startup |

### Recovery Point Objective (RPO)

| Component | RPO Target | Backup Method | Maximum Data Loss |
|-----------|-----------|---------------|-------------------|
| Configuration | 0 | Before changes | None |
| Database (pg_dump) | 24 hours | Daily backups | Max 24 hours |
| Database (PITR) | 15 minutes | WAL archiving | Max 15 minutes |
| Database (Streaming) | < 1 minute | Sync replication | Near-zero |
| PVC Snapshot | 24 hours | Daily snapshots | Max 24 hours |

### Recovery Scenario Matrix

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Config corruption | 5 min | 0 | ConfigMap restore |
| Single table drop | 15-30 min | 24 hours or PITR target | pg_restore selective |
| Database corruption | 30-60 min | 24 hours or PITR target | Full database restore |
| Storage failure | 30 min | 24 hours | PVC snapshot restore |
| Complete cluster loss | 1-2 hours | PITR target | Full cluster restore |
| Datacenter failure | 2-4 hours | Streaming lag | Failover to replica |

---

## Best Practices

### Backup Strategy

1. **Implement 3-2-1 backup rule:**
   - 3 copies of data
   - 2 different storage types (local + S3)
   - 1 offsite backup (different region)

2. **Use appropriate backup types:**
   - pg_dump for logical backups (portability, selective restore)
   - pg_basebackup for physical backups (fast recovery)
   - WAL archiving for PITR (minimal data loss)

3. **Automate backups:**
   - Use CronJobs for scheduled backups
   - Monitor backup job success/failure
   - Alert on backup failures

4. **Test restores regularly:**
   - Monthly restore tests to separate environment
   - Verify data integrity after restore
   - Document restore procedures and timing

### Backup Retention

| Backup Type | Retention Period | Storage Class |
|------------|-----------------|---------------|
| Hourly WAL | 48 hours | S3 Standard |
| Daily pg_dump | 30 days | S3 Standard |
| Weekly full backup | 90 days | S3 Infrequent Access |
| Monthly archive | 1 year | S3 Glacier |

### Security

1. **Encrypt backups at rest:**
   ```bash
   # Encrypt backup with GPG
   pg_dump mydb | gpg --symmetric --cipher-algo AES256 > backup.sql.gpg

   # S3 server-side encryption
   aws s3 cp backup.sql s3://bucket/backup.sql --sse AES256
   ```

2. **Restrict backup access:**
   - Use IAM roles with minimal permissions
   - Separate backup credentials from application credentials
   - Enable MFA delete for S3 buckets

3. **Audit backup access:**
   - Enable CloudTrail for S3 operations
   - Monitor backup job logs
   - Alert on unauthorized access attempts

### Performance Optimization

1. **Use parallel backup/restore:**
   ```bash
   # Parallel backup (directory format)
   pg_dump -Fd -j 4 -f /backup/mydb mydb

   # Parallel restore
   pg_restore -j 4 -d mydb /backup/mydb
   ```

2. **Schedule during low-activity periods:**
   - Avoid backup during peak hours
   - Consider read replica for backups

3. **Compress backups:**
   ```bash
   # Custom format with maximum compression
   pg_dump -Fc -Z9 mydb > mydb.dump

   # External compression for SQL format
   pg_dump mydb | pigz -9 > mydb.sql.gz
   ```

---

## Troubleshooting

### Issue 1: pg_dump Fails with Memory Error

**Symptoms:** "out of memory" error during pg_dump, backup process killed

**Solutions:**

1. **Use directory format with parallel workers:**
   ```bash
   pg_dump -Fd -j 2 -f /backup/mydb mydb
   ```

2. **Exclude large tables and backup separately:**
   ```bash
   # Backup without large tables
   pg_dump --exclude-table=large_logs mydb > mydb-partial.sql

   # Backup large tables with COPY
   psql -c "\copy large_logs TO '/backup/large_logs.csv' CSV" mydb
   ```

3. **Increase pod memory limits:**
   ```yaml
   resources:
     limits:
       memory: 4Gi
   ```

### Issue 2: WAL Archiving Fails

**Symptoms:** `pg_stat_archiver` shows failed_count increasing, missing WAL files

**Solutions:**

1. **Check archive command permissions:**
   ```bash
   kubectl exec -n $NAMESPACE $POD_NAME -- ls -la /var/lib/postgresql/archive/
   ```

2. **Test archive command manually:**
   ```bash
   kubectl exec -n $NAMESPACE $POD_NAME -- \
     sh -c 'cp /var/lib/postgresql/data/pg_wal/000000010000000000000001 /var/lib/postgresql/archive/test'
   ```

3. **Check disk space:**
   ```bash
   kubectl exec -n $NAMESPACE $POD_NAME -- df -h /var/lib/postgresql/archive/
   ```

4. **Reset archive stats:**
   ```bash
   kubectl exec -n $NAMESPACE $POD_NAME -- \
     sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_stat_reset_shared('\''archiver'\'');"'
   ```

### Issue 3: PITR Recovery Fails

**Symptoms:** Recovery stalls, WAL files not found, timeline mismatch

**Solutions:**

1. **Verify WAL continuity:**
   ```bash
   # List WAL files and check for gaps
   ls -la /var/lib/postgresql/archive/ | sort

   # Verify sequence (files should be consecutive)
   ```

2. **Check restore_command:**
   ```bash
   # Test restore_command manually
   cp /archive/000000010000000000000001 /tmp/test_restore
   ```

3. **Use correct recovery target:**
   ```bash
   # Ensure target time is within WAL range
   recovery_target_time = '2024-01-15 12:00:00+00'  # Include timezone
   ```

4. **Check timeline:**
   ```bash
   # List timeline history
   cat /var/lib/postgresql/archive/00000002.history
   ```

### Issue 4: Restore Takes Too Long

**Symptoms:** pg_restore running for hours, slow restore performance

**Solutions:**

1. **Use parallel restore:**
   ```bash
   pg_restore -j 4 -d mydb backup.dump
   ```

2. **Disable constraints during restore:**
   ```bash
   pg_restore --disable-triggers -d mydb backup.dump
   ```

3. **Increase work_mem temporarily:**
   ```sql
   SET work_mem = '256MB';
   SET maintenance_work_mem = '1GB';
   ```

4. **Drop indexes before restore, recreate after:**
   ```bash
   # Restore without indexes
   pg_restore --section=pre-data --section=data -d mydb backup.dump

   # Recreate indexes in parallel
   pg_restore --section=post-data -j 4 -d mydb backup.dump
   ```

### Issue 5: Replication Slot WAL Retention Growing

**Symptoms:** Disk space filling up, WAL files not being cleaned

**Solutions:**

1. **Check inactive replication slots:**
   ```sql
   SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
   FROM pg_replication_slots
   WHERE NOT active;
   ```

2. **Drop inactive slots:**
   ```sql
   SELECT pg_drop_replication_slot('inactive_slot_name');
   ```

3. **Set max_slot_wal_keep_size (PostgreSQL 13+):**
   ```sql
   ALTER SYSTEM SET max_slot_wal_keep_size = '10GB';
   SELECT pg_reload_conf();
   ```

### Issue 6: Backup Verification Fails

**Symptoms:** pg_restore -l fails, corrupted backup files

**Solutions:**

1. **Check backup file integrity:**
   ```bash
   # Check file header
   file backup.dump

   # Verify custom format
   pg_restore -l backup.dump
   ```

2. **Test backup transfer integrity:**
   ```bash
   # Calculate checksum before transfer
   sha256sum backup.dump > backup.dump.sha256

   # Verify after transfer
   sha256sum -c backup.dump.sha256
   ```

3. **Re-run backup with verbose output:**
   ```bash
   pg_dump -v -Fc -f backup.dump mydb 2>&1 | tee backup.log
   ```

### Issue 7: Permission Denied During Restore

**Symptoms:** "permission denied" errors, role does not exist

**Solutions:**

1. **Restore globals first:**
   ```bash
   # Create roles before database restore
   psql -f globals.sql postgres
   pg_restore -d mydb backup.dump
   ```

2. **Use --no-owner for different environment:**
   ```bash
   pg_restore --no-owner --no-acl -d mydb backup.dump
   ```

3. **Create missing roles:**
   ```sql
   CREATE ROLE missing_role LOGIN PASSWORD 'password';
   ```

### Issue 8: Large Object Restore Fails

**Symptoms:** "large object does not exist" errors, OID mismatch

**Solutions:**

1. **Include large objects in backup:**
   ```bash
   pg_dump --blobs -Fc mydb > backup-with-blobs.dump
   ```

2. **Restore large objects separately:**
   ```bash
   pg_restore --section=data -t pg_largeobject mydb backup.dump
   ```

3. **Use lo_export/lo_import for manual migration:**
   ```sql
   -- Export
   SELECT lo_export(oid, '/tmp/lo_' || oid) FROM pg_largeobject_metadata;

   -- Import
   SELECT lo_import('/tmp/lo_12345');
   ```

---

## Related Documentation

- [PostgreSQL Upgrade Guide](postgresql-upgrade-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/postgresql/README.md)
- [PostgreSQL Makefile](../make/ops/postgresql.mk)
- [PostgreSQL Official Backup Documentation](https://www.postgresql.org/docs/16/backup.html)

---

**Last Updated:** 2025-12-01
**Chart Version:** 0.3.0
**PostgreSQL Version:** 16.11
