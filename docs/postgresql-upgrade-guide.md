# PostgreSQL Upgrade Guide

This guide provides comprehensive procedures for upgrading PostgreSQL deployed via the Helm chart.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [1. Minor Version Upgrade (Rolling)](#1-minor-version-upgrade-rolling)
  - [2. pg_upgrade (In-Place Major Version)](#2-pg_upgrade-in-place-major-version)
  - [3. Dump and Restore (Safest Major Version)](#3-dump-and-restore-safest-major-version)
  - [4. Blue-Green Deployment (Zero-Downtime)](#4-blue-green-deployment-zero-downtime)
  - [5. Logical Replication Upgrade](#5-logical-replication-upgrade)
- [Version-Specific Notes](#version-specific-notes)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

### Upgrade Types

PostgreSQL upgrades fall into two categories:

| Upgrade Type | Example | Method | Downtime | Risk |
|-------------|---------|--------|----------|------|
| **Minor Version** | 16.1 -> 16.2 | Binary replacement | Minimal | Low |
| **Major Version** | 15.x -> 16.x | pg_upgrade/dump-restore | Extended | Medium-High |

### Supported Upgrade Paths

| Current Version | Target Version | Method | Complexity | Notes |
|----------------|---------------|--------|------------|-------|
| 16.x | 16.y | Rolling | Low | Binary compatible |
| 15.x | 16.x | pg_upgrade | Medium | Recommended for large DBs |
| 14.x | 16.x | Dump/Restore | High | Skip version supported |
| 13.x | 16.x | Dump/Restore | High | Review all breaking changes |
| < 13 | 16.x | Sequential | Very High | Upgrade in steps |

### Upgrade Complexity Factors

- **Data volume**: Larger databases = longer upgrade time
- **Extension count**: More extensions = more compatibility testing
- **Custom configuration**: Custom postgresql.conf may need migration
- **Replication setup**: Replicas require coordinated upgrade
- **Table/Index count**: More objects = longer pg_upgrade time
- **Large objects (LOBs)**: May require special handling

### Key Components Affected During Upgrade

| Component | Impact | Recovery Time |
|-----------|--------|---------------|
| Primary | All writes blocked | Varies by method |
| Replicas | Streaming paused | Minutes |
| WAL files | Incompatible between major versions | N/A |
| System catalogs | Rebuilt during major upgrade | Minutes-Hours |
| Statistics | Lost, must run ANALYZE | Minutes |
| Extensions | May need reinstallation | Varies |

### RTO Targets

| Upgrade Strategy | Downtime | Complexity | Recommended For |
|-----------------|----------|------------|-----------------|
| Minor Version (Rolling) | 1-5 minutes | Low | All deployments |
| pg_upgrade (link mode) | 5-30 minutes | Medium | Large DBs (> 100GB) |
| pg_upgrade (copy mode) | Hours | Medium | When link mode unavailable |
| Dump and Restore | Hours-Days | Low | Small DBs (< 50GB) |
| Blue-Green | 10-30 minutes | High | Production critical |
| Logical Replication | Minutes | High | Zero-downtime required |

---

## Pre-Upgrade Checklist

### Automated Pre-Upgrade Check

```bash
# Run automated pre-upgrade validation
make -f make/ops/postgresql.mk pg-pre-upgrade-check
```

### Manual Pre-Upgrade Checklist

#### 1. Review Release Notes

```bash
# Check current PostgreSQL version
make -f make/ops/postgresql.mk pg-version

# Get current version from pod
CURRENT_VERSION=$(kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SELECT version();"' | head -1)
TARGET_VERSION=16.2

echo "Current: $CURRENT_VERSION"
echo "Target: $TARGET_VERSION"
echo ""
echo "Release notes: https://www.postgresql.org/docs/release/"
echo "Migration guide: https://www.postgresql.org/docs/16/upgrading.html"
```

#### 2. Check Current Health

```bash
# Verify PostgreSQL is healthy
make -f make/ops/postgresql.mk pg-ping

# Check replication status (if applicable)
make -f make/ops/postgresql.mk pg-replication-status

# Check active connections
make -f make/ops/postgresql.mk pg-connections

# Check for long-running transactions
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pid, now() - xact_start AS duration, query FROM pg_stat_activity WHERE xact_start IS NOT NULL ORDER BY duration DESC LIMIT 10;"'
```

#### 3. Check Extension Compatibility

```bash
# List all installed extensions
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"'

# Check extension dependencies
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT e.extname, e.extversion, d.refobjid::regclass AS depends_on FROM pg_extension e LEFT JOIN pg_depend d ON e.oid = d.objid WHERE d.deptype = '"'"'e'"'"' ORDER BY e.extname;"'
```

#### 4. Create Full Backup

```bash
# Create pre-upgrade backup
make -f make/ops/postgresql.mk pg-backup-all

# Create physical backup (pg_basebackup)
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup -D /tmp/backup -U postgres -Ft -z -P'

# Verify backup
ls -lh tmp/postgresql-backups/
```

#### 5. Check Storage Space

```bash
# Check PVC usage
kubectl exec -n default postgresql-0 -- df -h /var/lib/postgresql/data

# Check database sizes
make -f make/ops/postgresql.mk pg-all-databases-size

# Estimate pg_upgrade space requirement (2x data directory)
kubectl exec -n default postgresql-0 -- \
  sh -c 'du -sh /var/lib/postgresql/data'
```

#### 6. Review Configuration Changes

```bash
# Export current configuration
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT name, setting, unit FROM pg_settings WHERE source != '"'"'default'"'"' ORDER BY name;"' > postgresql-config-pre-upgrade.txt

# Save postgresql.conf
kubectl exec -n default postgresql-0 -- cat /var/lib/postgresql/data/postgresql.conf > postgresql.conf.pre-upgrade

# Save pg_hba.conf
kubectl exec -n default postgresql-0 -- cat /var/lib/postgresql/data/pg_hba.conf > pg_hba.conf.pre-upgrade
```

#### 7. Check Replication Slots

```bash
# List replication slots
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"'

# Check WAL retention
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"'
```

#### 8. Document Database Objects

```bash
# Count tables, indexes, and other objects
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT
      (SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"')) as tables,
      (SELECT count(*) FROM pg_indexes WHERE schemaname NOT IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"')) as indexes,
      (SELECT count(*) FROM pg_views WHERE schemaname NOT IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"')) as views,
      (SELECT count(*) FROM pg_proc WHERE pronamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"'))) as functions;
  "'

# List tablespaces
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT * FROM pg_tablespace;"'
```

#### 9. Check for Deprecated Features

```bash
# PostgreSQL 13 -> 14: Check for recovery.conf usage
kubectl exec -n default postgresql-0 -- \
  sh -c 'ls -la /var/lib/postgresql/data/recovery.conf 2>/dev/null || echo "No recovery.conf (good)"'

# Check for deprecated parameters
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT name, setting FROM pg_settings WHERE name IN ('"'"'wal_keep_segments'"'"', '"'"'default_with_oids'"'"', '"'"'operator_precedence_warning'"'"');"'
```

#### 10. Verify Helm Release State

```bash
# Document current Helm revision
helm history postgresql -n default

# Save current Helm values
helm get values postgresql -n default > postgresql-values-pre-upgrade.yaml

# Note current image tag
kubectl get statefulset postgresql -n default -o jsonpath='{.spec.template.spec.containers[0].image}'
```

#### 11. Plan Maintenance Window

```bash
# Check for scheduled jobs
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE backend_type = '"'"'autovacuum worker'"'"';"'

# Check autovacuum status
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SHOW autovacuum;"'
```

#### 12. Notify Dependent Applications

```bash
# List connected applications
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT DISTINCT application_name, client_addr FROM pg_stat_activity WHERE application_name != '"'"''"'"';"'
```

### Pre-Upgrade Checklist Script

```bash
#!/bin/bash
# pre-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-postgresql-0}"

echo "=== PostgreSQL Pre-Upgrade Checklist ==="
echo ""

# 1. Check current version
echo "[1/15] Checking current version..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SHOW server_version;"' | tr -d ' ')
echo "  Current version: $CURRENT_VERSION"

# 2. Check pod health
echo "[2/15] Checking pod health..."
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
  echo "  [X] Pod not running: $POD_STATUS"
  exit 1
fi
echo "  [OK] Pod is running"

# 3. Check PostgreSQL readiness
echo "[3/15] Checking PostgreSQL readiness..."
if kubectl exec -n $NAMESPACE $POD_NAME -- pg_isready -U postgres; then
  echo "  [OK] PostgreSQL is ready"
else
  echo "  [X] PostgreSQL is not ready"
  exit 1
fi

# 4. Check disk space
echo "[4/15] Checking disk space..."
DISK_USAGE=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  df -h /var/lib/postgresql/data | tail -1 | awk '{print $5}' | tr -d '%')
echo "  Disk usage: $DISK_USAGE%"
if [ "$DISK_USAGE" -gt 80 ]; then
  echo "  [WARN] Disk usage above 80%"
fi

# 5. Check database sizes
echo "[5/15] Checking database sizes..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC LIMIT 5;"'

# 6. Check active connections
echo "[6/15] Checking active connections..."
CONN_COUNT=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;"' | tr -d ' ')
echo "  Active connections: $CONN_COUNT"

# 7. Check long-running transactions
echo "[7/15] Checking long-running transactions..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pid, now() - xact_start AS duration, state FROM pg_stat_activity WHERE xact_start IS NOT NULL AND now() - xact_start > interval '"'"'5 minutes'"'"' LIMIT 5;"' || true

# 8. Check replication status
echo "[8/15] Checking replication status..."
REPLICA_COUNT=$(kubectl get statefulset postgresql -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
echo "  Configured replicas: $REPLICA_COUNT"
if [ "$REPLICA_COUNT" -gt 1 ]; then
  kubectl exec -n $NAMESPACE $POD_NAME -- \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"' 2>/dev/null || echo "  No replication info"
fi

# 9. Check installed extensions
echo "[9/15] Checking installed extensions..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"'

# 10. Check replication slots
echo "[10/15] Checking replication slots..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"' 2>/dev/null || echo "  No replication slots"

# 11. Check WAL status
echo "[11/15] Checking WAL status..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"' 2>/dev/null || echo "  WAL info unavailable"

# 12. Check for deprecated parameters
echo "[12/15] Checking for deprecated parameters..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SELECT count(*) FROM pg_settings WHERE name IN ('"'"'wal_keep_segments'"'"', '"'"'default_with_oids'"'"');"' | tr -d ' '

# 13. Check PVC status
echo "[13/15] Checking PVC status..."
PVC_STATUS=$(kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "N/A")
echo "  PVC status: $PVC_STATUS"

# 14. Check recent errors in logs
echo "[14/15] Checking recent errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD_NAME --tail=100 2>/dev/null | grep -i -E "(error|fatal|panic)" | wc -l)
echo "  Recent errors: $ERROR_COUNT"
if [ "$ERROR_COUNT" -gt 10 ]; then
  echo "  [WARN] High error count detected"
fi

# 15. Check Helm release
echo "[15/15] Checking Helm release..."
HELM_STATUS=$(helm status postgresql -n $NAMESPACE -o json 2>/dev/null | jq -r '.info.status' || echo "N/A")
echo "  Helm status: $HELM_STATUS"

echo ""
echo "=== Pre-Upgrade Check Complete ==="
echo ""
echo "Next steps:"
echo "1. Review PostgreSQL release notes for target version"
echo "2. Create full backup: make -f make/ops/postgresql.mk pg-backup-all"
echo "3. Determine upgrade method based on:"
echo "   - Minor version: Rolling upgrade"
echo "   - Major version: pg_upgrade or dump/restore"
echo "4. Proceed with appropriate upgrade strategy"
```

---

## Upgrade Strategies

### 1. Minor Version Upgrade (Rolling)

Zero-downtime upgrade for minor versions (e.g., 16.1 -> 16.2).

#### Prerequisites

- Same major version (e.g., 16.x)
- Replication configured (for HA)
- PodDisruptionBudget configured

#### Procedure

```bash
# 1. Create pre-upgrade backup
make -f make/ops/postgresql.mk pg-backup-all

# 2. Update Helm chart
helm repo update

# 3. Review changes
helm diff upgrade postgresql scripton-charts/postgresql \
  --set image.tag=16.2 \
  --reuse-values

# 4. Perform rolling upgrade
helm upgrade postgresql scripton-charts/postgresql \
  --set image.tag=16.2 \
  --reuse-values \
  --wait \
  --timeout=10m

# 5. Monitor rollout
kubectl rollout status statefulset postgresql -n default

# 6. Verify all pods updated
kubectl get pods -n default -l app.kubernetes.io/name=postgresql \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

#### Rolling Upgrade Script

```bash
#!/bin/bash
# minor-version-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
CHART_NAME="postgresql"
TARGET_VERSION="${TARGET_VERSION:-16.2}"

echo "=== PostgreSQL Minor Version Upgrade to $TARGET_VERSION ==="

# 1. Pre-upgrade backup
echo "[1/6] Creating pre-upgrade backup..."
make -f make/ops/postgresql.mk pg-backup-all

# 2. Update Helm repo
echo "[2/6] Updating Helm repository..."
helm repo update scripton-charts

# 3. Perform upgrade
echo "[3/6] Upgrading PostgreSQL..."
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

# 6. Verify PostgreSQL health
echo "[6/6] Verifying PostgreSQL health..."
POD_NAME="${CHART_NAME}-0"
kubectl wait --for=condition=ready pod/$POD_NAME -n $NAMESPACE --timeout=300s

# Verify version
echo ""
echo "New version:"
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT version();"'

echo ""
echo "=== Rolling Upgrade Complete ==="
```

---

### 2. pg_upgrade (In-Place Major Version)

Fast in-place upgrade for major versions using pg_upgrade tool.

#### Prerequisites

- Both PostgreSQL versions installed
- 2x disk space (link mode reduces this)
- Downtime window scheduled
- Full backup created

#### Link Mode vs Copy Mode

| Mode | Disk Space | Speed | Risk |
|------|------------|-------|------|
| **Link** (`-k`) | Minimal | Fast | Cannot rollback after first start |
| **Copy** | 2x data | Slow | Original data preserved |

#### Procedure

```bash
# 1. Create comprehensive backup
make -f make/ops/postgresql.mk pg-backup-all

# 2. Stop applications
echo "Stopping application connections..."
kubectl scale deployment myapp --replicas=0

# 3. Checkpoint and stop PostgreSQL
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CHECKPOINT;"'

# 4. Scale down PostgreSQL
kubectl scale statefulset postgresql -n default --replicas=0
kubectl wait --for=delete pod -n default -l app.kubernetes.io/name=postgresql --timeout=120s

# 5. Perform pg_upgrade (in a Job or manually)
# This requires both old and new PostgreSQL binaries

# 6. Update Helm chart to new version
helm upgrade postgresql scripton-charts/postgresql \
  --set image.tag=16.0 \
  --reuse-values \
  --wait

# 7. Scale up
kubectl scale statefulset postgresql -n default --replicas=1
kubectl wait --for=condition=ready pod postgresql-0 -n default --timeout=300s

# 8. Run post-upgrade tasks
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "ANALYZE;"'

# 9. Update statistics
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" vacuumdb -U postgres --all --analyze-only'

# 10. Restart applications
kubectl scale deployment myapp --replicas=3
```

#### pg_upgrade Check Mode

Always run pg_upgrade with `--check` first:

```bash
#!/bin/bash
# pg-upgrade-check.sh
# Run this BEFORE actual upgrade

set -e

OLD_DATA="/var/lib/postgresql/15/data"
NEW_DATA="/var/lib/postgresql/16/data"
OLD_BIN="/usr/lib/postgresql/15/bin"
NEW_BIN="/usr/lib/postgresql/16/bin"

echo "=== pg_upgrade Check Mode ==="

# Run check
$NEW_BIN/pg_upgrade \
  --old-datadir=$OLD_DATA \
  --new-datadir=$NEW_DATA \
  --old-bindir=$OLD_BIN \
  --new-bindir=$NEW_BIN \
  --check

echo ""
echo "Check completed. Review output above for any issues."
```

#### pg_upgrade Script (Link Mode)

```bash
#!/bin/bash
# pg-upgrade-link.sh

set -e

OLD_VERSION="15"
NEW_VERSION="16"
OLD_DATA="/var/lib/postgresql/${OLD_VERSION}/data"
NEW_DATA="/var/lib/postgresql/${NEW_VERSION}/data"
OLD_BIN="/usr/lib/postgresql/${OLD_VERSION}/bin"
NEW_BIN="/usr/lib/postgresql/${NEW_VERSION}/bin"

echo "=== pg_upgrade (Link Mode) from $OLD_VERSION to $NEW_VERSION ==="
echo ""
echo "WARNING: Link mode creates hard links. After starting the new cluster,"
echo "you cannot revert to the old cluster."
echo ""

# Initialize new data directory
echo "[1/4] Initializing new data directory..."
$NEW_BIN/initdb -D $NEW_DATA

# Run pg_upgrade with link mode
echo "[2/4] Running pg_upgrade..."
cd /tmp
$NEW_BIN/pg_upgrade \
  --old-datadir=$OLD_DATA \
  --new-datadir=$NEW_DATA \
  --old-bindir=$OLD_BIN \
  --new-bindir=$NEW_BIN \
  --link \
  --jobs=4

# Copy configuration files
echo "[3/4] Copying configuration files..."
cp $OLD_DATA/postgresql.conf $NEW_DATA/
cp $OLD_DATA/pg_hba.conf $NEW_DATA/
cp $OLD_DATA/pg_ident.conf $NEW_DATA/ 2>/dev/null || true

# Update configuration for new version
echo "[4/4] Updating configuration..."
# Adjust any deprecated parameters here

echo ""
echo "=== pg_upgrade Complete ==="
echo ""
echo "Next steps:"
echo "1. Review generated SQL scripts"
echo "2. Start PostgreSQL with new version"
echo "3. Run: ./analyze_new_cluster.sh"
echo "4. Delete old cluster when verified: ./delete_old_cluster.sh"
```

---

### 3. Dump and Restore (Safest Major Version)

Most reliable but slowest method for major version upgrades.

#### Prerequisites

- Sufficient disk space for dump file
- Extended downtime window
- Target environment prepared

#### Procedure

```bash
# 1. Create logical dump
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' > full-dump-$(date +%Y%m%d).sql

# 2. Verify dump integrity
head -100 full-dump-$(date +%Y%m%d).sql
tail -50 full-dump-$(date +%Y%m%d).sql
ls -lh full-dump-$(date +%Y%m%d).sql

# 3. Stop applications
kubectl scale deployment myapp --replicas=0

# 4. Delete old StatefulSet (preserve PVC)
helm uninstall postgresql -n default

# 5. Install new version
helm install postgresql scripton-charts/postgresql \
  --set image.tag=16.0 \
  --values postgresql-values.yaml

# 6. Wait for new instance
kubectl wait --for=condition=ready pod postgresql-0 -n default --timeout=300s

# 7. Restore dump
cat full-dump-$(date +%Y%m%d).sql | kubectl exec -i postgresql-0 -n default -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres'

# 8. Update statistics
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" vacuumdb -U postgres --all --analyze'

# 9. Restart applications
kubectl scale deployment myapp --replicas=3
```

#### Dump and Restore Script

```bash
#!/bin/bash
# dump-restore-upgrade.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
TARGET_VERSION="${TARGET_VERSION:-16.0}"
BACKUP_DIR="tmp/postgresql-upgrades"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== PostgreSQL Dump and Restore Upgrade ==="

# 1. Create backup directory
echo "[1/10] Creating backup directory..."
mkdir -p $BACKUP_DIR

# 2. Dump all databases
echo "[2/10] Dumping all databases (this may take a while)..."
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' > $BACKUP_DIR/full-dump-$TIMESTAMP.sql

# Verify dump
DUMP_SIZE=$(ls -lh $BACKUP_DIR/full-dump-$TIMESTAMP.sql | awk '{print $5}')
echo "  Dump size: $DUMP_SIZE"

# 3. Dump globals separately (users, roles)
echo "[3/10] Dumping globals..."
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --globals-only' > $BACKUP_DIR/globals-$TIMESTAMP.sql

# 4. Save current Helm values
echo "[4/10] Saving Helm values..."
helm get values postgresql -n $NAMESPACE > $BACKUP_DIR/values-$TIMESTAMP.yaml

# 5. Stop applications
echo "[5/10] Please stop all applications connecting to PostgreSQL"
echo "  Example: kubectl scale deployment myapp --replicas=0"
echo "  Press ENTER when ready..."
read

# 6. Uninstall old PostgreSQL
echo "[6/10] Uninstalling old PostgreSQL..."
helm uninstall postgresql -n $NAMESPACE

# Wait for cleanup
sleep 30

# 7. Install new version
echo "[7/10] Installing PostgreSQL $TARGET_VERSION..."
helm install postgresql scripton-charts/postgresql \
  --namespace $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --values $BACKUP_DIR/values-$TIMESTAMP.yaml \
  --wait \
  --timeout=10m

# 8. Restore dump
echo "[8/10] Restoring dump (this may take a while)..."
cat $BACKUP_DIR/full-dump-$TIMESTAMP.sql | kubectl exec -i postgresql-0 -n $NAMESPACE -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres'

# 9. Update statistics
echo "[9/10] Updating statistics..."
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" vacuumdb -U postgres --all --analyze'

# 10. Verify
echo "[10/10] Verifying..."
kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT version();"'

echo ""
echo "=== Dump and Restore Upgrade Complete ==="
echo ""
echo "Backup files saved in: $BACKUP_DIR"
echo "Please restart your applications and verify data integrity."
```

---

### 4. Blue-Green Deployment (Zero-Downtime)

Parallel deployment with traffic cutover for minimal downtime.

#### Prerequisites

- 2x compute resources
- Separate namespace for green deployment
- Logical replication configured
- Load balancer or service mesh

#### Procedure

```bash
# 1. Create full backup
make -f make/ops/postgresql.mk pg-backup-all

# 2. Deploy green environment
kubectl create namespace postgres-green

helm install postgresql-green scripton-charts/postgresql \
  --namespace postgres-green \
  --set image.tag=16.0 \
  --values postgresql-values.yaml

# 3. Wait for green to be ready
kubectl wait --for=condition=ready pod -n postgres-green -l app.kubernetes.io/name=postgresql --timeout=300s

# 4. Set up logical replication from blue to green
# On blue (publisher)
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CREATE PUBLICATION blue_pub FOR ALL TABLES;"'

# On green (subscriber)
kubectl exec -n postgres-green postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    CREATE SUBSCRIPTION green_sub
    CONNECTION '"'"'host=postgresql.default.svc.cluster.local port=5432 dbname=postgres user=postgres password=<password>'"'"'
    PUBLICATION blue_pub;
  "'

# 5. Wait for initial sync
# Monitor replication lag
kubectl exec -n postgres-green postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT * FROM pg_subscription_rel;"'

# 6. Verify data consistency
# Compare row counts, checksums, etc.

# 7. Switch traffic to green
# Update service endpoints or ingress

# 8. Drop subscription on green
kubectl exec -n postgres-green postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "ALTER SUBSCRIPTION green_sub DISABLE;"'

kubectl exec -n postgres-green postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "DROP SUBSCRIPTION green_sub;"'

# 9. Decommission blue
helm uninstall postgresql -n default
kubectl delete namespace default # or keep for rollback
```

#### Blue-Green Deployment Script

```bash
#!/bin/bash
# blue-green-upgrade.sh

set -e

BLUE_NAMESPACE="${BLUE_NAMESPACE:-default}"
GREEN_NAMESPACE="${GREEN_NAMESPACE:-postgres-green}"
TARGET_VERSION="${TARGET_VERSION:-16.0}"

echo "=== PostgreSQL Blue-Green Upgrade ==="

# 1. Backup blue
echo "[1/10] Backing up blue environment..."
make -f make/ops/postgresql.mk pg-backup-all NAMESPACE=$BLUE_NAMESPACE

# 2. Create green namespace
echo "[2/10] Creating green namespace..."
kubectl create namespace $GREEN_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 3. Copy secrets to green namespace
echo "[3/10] Copying secrets..."
kubectl get secret postgresql-secret -n $BLUE_NAMESPACE -o yaml | \
  sed "s/namespace: $BLUE_NAMESPACE/namespace: $GREEN_NAMESPACE/" | \
  kubectl apply -f -

# 4. Deploy green
echo "[4/10] Deploying green environment..."
helm get values postgresql -n $BLUE_NAMESPACE > /tmp/postgresql-values.yaml

helm install postgresql-green scripton-charts/postgresql \
  --namespace $GREEN_NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --values /tmp/postgresql-values.yaml \
  --wait \
  --timeout=10m

# 5. Verify green
echo "[5/10] Verifying green environment..."
kubectl wait --for=condition=ready pod -n $GREEN_NAMESPACE -l app.kubernetes.io/name=postgresql --timeout=300s

kubectl exec -n $GREEN_NAMESPACE postgresql-green-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT version();"'

# 6. Initial data sync (dump/restore or logical replication)
echo "[6/10] Syncing data to green..."
echo "  Option A: Use pg_dump/pg_restore"
echo "  Option B: Set up logical replication"
echo ""
echo "  For this script, we'll use dump/restore..."

# Dump from blue
kubectl exec -n $BLUE_NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' > /tmp/blue-dump.sql

# Restore to green
cat /tmp/blue-dump.sql | kubectl exec -i -n $GREEN_NAMESPACE postgresql-green-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres'

# 7. Verify data consistency
echo "[7/10] Verifying data consistency..."
# Add your verification logic here

# 8. Switch traffic
echo "[8/10] Ready to switch traffic..."
echo "  Update your application configuration to point to:"
echo "  postgresql-green.$GREEN_NAMESPACE.svc.cluster.local"
echo ""
echo "  Press ENTER when traffic is switched..."
read

# 9. Monitor
echo "[9/10] Monitoring green environment..."
echo "  Watch for errors in: kubectl logs -n $GREEN_NAMESPACE -l app.kubernetes.io/name=postgresql -f"
echo ""
echo "  Press ENTER to continue with decommissioning blue..."
read

# 10. Decommission blue
echo "[10/10] Decommissioning blue environment..."
helm uninstall postgresql -n $BLUE_NAMESPACE

echo ""
echo "=== Blue-Green Upgrade Complete ==="
echo "Green environment is now serving traffic in namespace: $GREEN_NAMESPACE"
```

---

### 5. Logical Replication Upgrade

Near-zero-downtime upgrade using PostgreSQL logical replication.

#### Prerequisites

- PostgreSQL 10+ (both source and target)
- `wal_level = logical` on source
- Tables must have primary keys or REPLICA IDENTITY
- Extensions compatible with logical replication

#### Limitations

- Does not replicate DDL changes
- Does not replicate sequences
- Does not replicate large objects
- Requires REPLICA IDENTITY on tables

#### Procedure

```bash
# 1. Configure source for logical replication
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    ALTER SYSTEM SET wal_level = logical;
    ALTER SYSTEM SET max_replication_slots = 10;
    ALTER SYSTEM SET max_wal_senders = 10;
  "'

# Restart to apply
kubectl rollout restart statefulset postgresql -n default
kubectl rollout status statefulset postgresql -n default

# 2. Create replication user
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    CREATE USER repl_user WITH REPLICATION PASSWORD '"'"'repl_password'"'"';
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_user;
  "'

# 3. Set REPLICA IDENTITY on tables without primary keys
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    DO \$\$
    DECLARE
      r RECORD;
    BEGIN
      FOR r IN SELECT schemaname, tablename FROM pg_tables
               WHERE schemaname = '"'"'public'"'"'
               AND tablename NOT IN (SELECT tablename FROM pg_indexes WHERE indexname LIKE '"'"'%_pkey'"'"')
      LOOP
        EXECUTE '"'"'ALTER TABLE '"'"' || r.schemaname || '"'"'.'"'"' || r.tablename || '"'"' REPLICA IDENTITY FULL'"'"';
      END LOOP;
    END \$\$;
  "'

# 4. Create publication
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    CREATE PUBLICATION upgrade_pub FOR ALL TABLES;
  "'

# 5. Deploy target (new version) in separate namespace
kubectl create namespace postgres-new
helm install postgresql-new scripton-charts/postgresql \
  --namespace postgres-new \
  --set image.tag=16.0 \
  --values postgresql-values.yaml

# 6. Create same schema on target (pg_dump --schema-only)
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres --schema-only mydb' | \
  kubectl exec -i -n postgres-new postgresql-new-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres mydb'

# 7. Create subscription on target
kubectl exec -n postgres-new postgresql-new-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d mydb -c "
    CREATE SUBSCRIPTION upgrade_sub
    CONNECTION '"'"'host=postgresql.default.svc.cluster.local port=5432 dbname=mydb user=repl_user password=repl_password'"'"'
    PUBLICATION upgrade_pub;
  "'

# 8. Monitor replication
kubectl exec -n default postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "
    SELECT slot_name, confirmed_flush_lsn, pg_current_wal_lsn(),
           (pg_current_wal_lsn() - confirmed_flush_lsn) AS lag_bytes
    FROM pg_replication_slots;
  "'

# 9. When lag is minimal, switch applications
# Update connection strings to point to new cluster

# 10. Cleanup
# Drop subscription on new cluster
# Drop publication on old cluster
# Decommission old cluster
```

---

## Version-Specific Notes

### PostgreSQL 13 to 14

**Breaking Changes:**

- `recovery.conf` file removed (use `postgresql.auto.conf` or `recovery.signal`)
- `wal_keep_segments` renamed to `wal_keep_size`
- Default changed: `password_encryption = scram-sha-256`
- `pg_stat_statements.track_planning` added
- `idle_session_timeout` added

**Migration Steps:**

1. **Update recovery configuration:**
   ```sql
   -- Old (recovery.conf - PostgreSQL 13)
   -- standby_mode = 'on'
   -- primary_conninfo = '...'
   -- recovery_target_timeline = 'latest'

   -- New (postgresql.conf - PostgreSQL 14+)
   -- Create recovery.signal file instead
   -- Add to postgresql.conf:
   -- primary_conninfo = '...'
   -- recovery_target_timeline = 'latest'
   ```

2. **Update WAL settings:**
   ```sql
   -- Old
   ALTER SYSTEM SET wal_keep_segments = 64;

   -- New
   ALTER SYSTEM SET wal_keep_size = '1GB';  -- 64 * 16MB = 1GB
   ```

3. **Check password encryption:**
   ```sql
   -- Verify current setting
   SHOW password_encryption;

   -- Update if needed (may require password reset for users)
   ALTER SYSTEM SET password_encryption = 'scram-sha-256';
   ```

### PostgreSQL 14 to 15

**Breaking Changes:**

- Public schema permissions changed: `REVOKE CREATE ON SCHEMA public FROM PUBLIC`
- `standard_conforming_strings` always ON (cannot be set to OFF)
- `array_to_string()` returns NULL for NULL array
- `NULLIF()` accepts only compatible types
- Remove deprecated operators (`~=` for box, etc.)

**Migration Steps:**

1. **Grant public schema permissions if needed:**
   ```sql
   -- For backward compatibility (not recommended for security)
   GRANT CREATE ON SCHEMA public TO PUBLIC;

   -- Or grant to specific roles (recommended)
   GRANT CREATE ON SCHEMA public TO myapp;
   ```

2. **Check for affected queries:**
   ```sql
   -- Identify queries using deprecated operators
   -- Review application code for:
   -- - NULLIF with incompatible types
   -- - array_to_string with NULL arrays
   -- - standard_conforming_strings = off
   ```

3. **Update extension compatibility:**
   ```sql
   -- Check extension compatibility
   SELECT extname, extversion FROM pg_extension;

   -- Update extensions after upgrade
   ALTER EXTENSION pg_stat_statements UPDATE;
   ```

### PostgreSQL 15 to 16

**Breaking Changes:**

- ICU library required for default collation
- `log_destination = 'stderr'` default changed
- `pg_dump` output format changes
- Logical replication improvements (row filters, column lists)
- `GRANT SET` and `ALTER DEFAULT` changes

**New Features:**

- Logical replication from standbys
- `pg_stat_io` view for I/O statistics
- Parallel execution of `FULL` and `FREEZE` vacuum
- Allow logical replication from standby servers

**Migration Steps:**

1. **Verify ICU support:**
   ```bash
   # Check ICU library
   ldd /usr/lib/postgresql/16/bin/postgres | grep icu
   ```

2. **Update log configuration:**
   ```sql
   -- Review log settings
   SHOW log_destination;
   SHOW logging_collector;

   -- Update if needed
   ALTER SYSTEM SET log_destination = 'stderr';
   ```

3. **Enable new features:**
   ```sql
   -- Use new I/O statistics
   SELECT * FROM pg_stat_io;

   -- Use logical replication from standby
   ALTER SYSTEM SET wal_level = logical;
   ```

### Jump Upgrade: PostgreSQL 13 to 16

**Considerations:**

- Review ALL breaking changes from 13 -> 14 -> 15 -> 16
- Test thoroughly in non-production environment
- Sequential upgrade (13 -> 14 -> 15 -> 16) is safer but slower
- Direct upgrade possible with dump/restore

**Migration Checklist:**

```sql
-- 1. Check for recovery.conf (must migrate)
-- 2. Check wal_keep_segments (must rename)
-- 3. Check password_encryption (upgrade to scram-sha-256)
-- 4. Check public schema grants (may need explicit grants)
-- 5. Check for deprecated operators
-- 6. Verify extension compatibility
-- 7. Test application queries
```

---

## Post-Upgrade Validation

### Automated Post-Upgrade Check

```bash
# Run automated validation
make -f make/ops/postgresql.mk pg-post-upgrade-check
```

### Manual Post-Upgrade Validation

```bash
#!/bin/bash
# post-upgrade-check.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
POD_NAME="${POD_NAME:-postgresql-0}"

echo "=== PostgreSQL Post-Upgrade Validation ==="
echo ""

# 1. Check version
echo "[1/12] Verifying new version..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT version();"'

# 2. Check pod status
echo "[2/12] Checking pod status..."
READY_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=postgresql \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=postgresql --no-headers | wc -l)
echo "  Ready pods: $READY_PODS/$TOTAL_PODS"

# 3. Check PostgreSQL readiness
echo "[3/12] Checking PostgreSQL readiness..."
kubectl exec -n $NAMESPACE $POD_NAME -- pg_isready -U postgres
echo "  [OK] PostgreSQL is ready"

# 4. Check database connectivity
echo "[4/12] Testing database connectivity..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT 1;"' >/dev/null
echo "  [OK] Database connectivity verified"

# 5. Check replication status (if applicable)
echo "[5/12] Checking replication status..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"' 2>/dev/null || echo "  No replicas or not primary"

# 6. Verify extensions
echo "[6/12] Checking extensions..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"'

# 7. Check for invalid indexes
echo "[7/12] Checking for invalid indexes..."
INVALID=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SELECT count(*) FROM pg_index WHERE NOT indisvalid;"' | tr -d ' ')
if [ "$INVALID" -gt 0 ]; then
  echo "  [WARN] Found $INVALID invalid indexes"
  kubectl exec -n $NAMESPACE $POD_NAME -- \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;"'
else
  echo "  [OK] No invalid indexes"
fi

# 8. Check statistics
echo "[8/12] Checking if statistics need update..."
STALE=$(kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SELECT count(*) FROM pg_stat_user_tables WHERE last_analyze IS NULL OR last_analyze < now() - interval '"'"'1 day'"'"';"' | tr -d ' ')
if [ "$STALE" -gt 10 ]; then
  echo "  [WARN] $STALE tables need ANALYZE"
  echo "  Run: make -f make/ops/postgresql.mk pg-analyze"
else
  echo "  [OK] Statistics up to date"
fi

# 9. Test write operation
echo "[9/12] Testing write operation..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CREATE TABLE IF NOT EXISTS _upgrade_test (id int); INSERT INTO _upgrade_test VALUES (1); DROP TABLE _upgrade_test;"'
echo "  [OK] Write operation successful"

# 10. Check for configuration warnings
echo "[10/12] Checking for configuration warnings..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT name, setting, pending_restart FROM pg_settings WHERE pending_restart;"'

# 11. Check error logs
echo "[11/12] Checking recent errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE $POD_NAME --tail=100 2>/dev/null | grep -i -E "(error|fatal|panic)" | wc -l)
echo "  Recent errors: $ERROR_COUNT"

# 12. Verify WAL status
echo "[12/12] Checking WAL status..."
kubectl exec -n $NAMESPACE $POD_NAME -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "SELECT pg_current_wal_lsn();"' 2>/dev/null || echo "  WAL info unavailable"

echo ""
echo "=== Post-Upgrade Validation Complete ==="
```

---

## Rollback Procedures

### Method 1: Helm Rollback (Minor Version Only)

```bash
# List Helm history
helm history postgresql -n default

# Rollback to previous revision
helm rollback postgresql -n default

# Or rollback to specific revision
helm rollback postgresql 5 -n default

# Verify rollback
kubectl rollout status statefulset postgresql -n default
```

### Method 2: Restore from Backup

```bash
# Scale down current deployment
kubectl scale statefulset postgresql -n default --replicas=0

# Delete PVC (careful - this deletes data)
kubectl delete pvc data-postgresql-0 -n default

# Reinstall with previous version
helm install postgresql scripton-charts/postgresql \
  --set image.tag=15.8 \
  --values postgresql-values.yaml

# Wait for pod
kubectl wait --for=condition=ready pod postgresql-0 -n default --timeout=300s

# Restore from backup
cat full-dump-backup.sql | kubectl exec -i postgresql-0 -n default -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres'
```

### Method 3: Point-in-Time Recovery (PITR)

```bash
# Requires WAL archiving configured before upgrade

# 1. Stop PostgreSQL
kubectl scale statefulset postgresql -n default --replicas=0

# 2. Restore base backup
# (depends on your backup solution)

# 3. Configure recovery
kubectl exec -n default postgresql-0 -- sh -c 'cat > /var/lib/postgresql/data/postgresql.auto.conf << EOF
restore_command = '"'"'cp /archive/%f %p'"'"'
recovery_target_time = '"'"'2025-12-01 10:00:00'"'"'
recovery_target_action = promote
EOF'

# 4. Create recovery signal
kubectl exec -n default postgresql-0 -- touch /var/lib/postgresql/data/recovery.signal

# 5. Start PostgreSQL
kubectl scale statefulset postgresql -n default --replicas=1
```

### Rollback Script

```bash
#!/bin/bash
# rollback.sh

set -e

NAMESPACE="${NAMESPACE:-default}"
PREVIOUS_VERSION="${PREVIOUS_VERSION:-15.8}"
BACKUP_FILE="${BACKUP_FILE:-}"

echo "=== PostgreSQL Rollback to $PREVIOUS_VERSION ==="

# 1. Check current state
echo "[1/5] Checking current state..."
CURRENT_VERSION=$(kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SHOW server_version;"' | tr -d ' ')
echo "  Current version: $CURRENT_VERSION"

# 2. Confirm rollback
echo ""
echo "[WARN] This will rollback PostgreSQL from $CURRENT_VERSION to $PREVIOUS_VERSION"
echo "This is a DESTRUCTIVE operation for major version rollbacks."
echo ""
echo "Press ENTER to continue or Ctrl+C to cancel..."
read

# 3. Create current backup
echo "[2/5] Creating backup of current state..."
make -f make/ops/postgresql.mk pg-backup-all

# 4. Perform rollback
echo "[3/5] Performing Helm rollback..."
helm rollback postgresql -n $NAMESPACE

# 5. Wait for rollback
echo "[4/5] Waiting for rollback to complete..."
kubectl rollout status statefulset postgresql -n $NAMESPACE

# 6. Verify rollback
echo "[5/5] Verifying rollback..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE postgresql-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -t -c "SHOW server_version;"' | tr -d ' ')
echo "  Rolled back to: $NEW_VERSION"

# Test connectivity
kubectl exec -n $NAMESPACE postgresql-0 -- pg_isready -U postgres

echo ""
echo "=== Rollback Complete ==="
```

---

## Troubleshooting

### Issue 1: pg_upgrade Fails with "database cluster state is not valid"

**Symptoms:**
- pg_upgrade --check fails
- "database cluster state is not valid"
- PostgreSQL not cleanly shut down

**Solutions:**

1. **Clean shutdown before upgrade:**
   ```bash
   # Ensure clean shutdown
   kubectl exec -n default postgresql-0 -- \
     sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -c "CHECKPOINT;"'

   # Stop PostgreSQL gracefully
   kubectl scale statefulset postgresql -n default --replicas=0
   sleep 60
   ```

2. **Reset WAL if corrupted:**
   ```bash
   # WARNING: May cause data loss
   pg_resetwal -f /var/lib/postgresql/data
   ```

### Issue 2: Extensions Incompatible After Upgrade

**Symptoms:**
- Extension functions fail
- "function does not exist" errors
- Extension version mismatch

**Solutions:**

1. **Update extensions:**
   ```sql
   -- List extensions needing update
   SELECT extname, extversion,
          (SELECT extversion FROM pg_available_extension_versions
           WHERE name = extname ORDER BY version DESC LIMIT 1) as latest
   FROM pg_extension;

   -- Update extension
   ALTER EXTENSION pg_stat_statements UPDATE;
   ALTER EXTENSION postgis UPDATE;
   ```

2. **Reinstall extension:**
   ```sql
   DROP EXTENSION pgcrypto;
   CREATE EXTENSION pgcrypto;
   ```

### Issue 3: Replication Not Working After Upgrade

**Symptoms:**
- Replicas not connecting
- Streaming replication broken
- WAL receiver not starting

**Solutions:**

1. **Check replication slots:**
   ```sql
   -- On primary
   SELECT slot_name, active FROM pg_replication_slots;

   -- Drop and recreate if needed
   SELECT pg_drop_replication_slot('replica_slot');
   SELECT pg_create_physical_replication_slot('replica_slot');
   ```

2. **Reinitialize replica:**
   ```bash
   # Stop replica
   kubectl scale statefulset postgresql -n default --replicas=1

   # Delete replica PVC
   kubectl delete pvc data-postgresql-1 -n default

   # Scale back up
   kubectl scale statefulset postgresql -n default --replicas=2
   ```

3. **Check pg_hba.conf:**
   ```bash
   kubectl exec -n default postgresql-0 -- cat /var/lib/postgresql/data/pg_hba.conf | grep replication
   ```

### Issue 4: Performance Degradation After Upgrade

**Symptoms:**
- Queries slower than before
- High CPU/Memory usage
- Timeout errors

**Solutions:**

1. **Update statistics:**
   ```bash
   # Run ANALYZE on all databases
   make -f make/ops/postgresql.mk pg-analyze

   # Or full vacuum
   make -f make/ops/postgresql.mk pg-vacuum-analyze
   ```

2. **Rebuild indexes:**
   ```sql
   -- Identify bloated indexes
   SELECT indexrelid::regclass, pg_size_pretty(pg_relation_size(indexrelid))
   FROM pg_stat_user_indexes
   ORDER BY pg_relation_size(indexrelid) DESC
   LIMIT 10;

   -- Reindex if needed
   REINDEX DATABASE mydb;
   ```

3. **Review configuration:**
   ```sql
   -- Check changed settings
   SELECT name, setting, boot_val, reset_val
   FROM pg_settings
   WHERE setting != boot_val;
   ```

### Issue 5: Invalid Indexes After pg_upgrade

**Symptoms:**
- "index corrupted" errors
- Queries returning wrong results
- Index scans failing

**Solutions:**

1. **Find invalid indexes:**
   ```sql
   SELECT indexrelid::regclass, indisvalid
   FROM pg_index
   WHERE NOT indisvalid;
   ```

2. **Reindex invalid indexes:**
   ```sql
   REINDEX INDEX CONCURRENTLY my_index;
   -- Or reindex entire database
   REINDEX DATABASE mydb;
   ```

3. **Run analyze_new_cluster.sh:**
   ```bash
   # Generated by pg_upgrade
   ./analyze_new_cluster.sh
   ```

### Issue 6: Public Schema Permission Errors (PG 15+)

**Symptoms:**
- "permission denied for schema public"
- Cannot create objects in public schema
- Application errors after upgrade

**Solutions:**

1. **Grant permissions:**
   ```sql
   -- For specific role
   GRANT CREATE ON SCHEMA public TO myapp_role;
   GRANT USAGE ON SCHEMA public TO myapp_role;

   -- For backward compatibility (less secure)
   GRANT CREATE ON SCHEMA public TO PUBLIC;
   ```

2. **Create dedicated schema:**
   ```sql
   CREATE SCHEMA myapp AUTHORIZATION myapp_role;
   SET search_path TO myapp, public;
   ```

### Issue 7: Logical Replication Sync Failure

**Symptoms:**
- Subscription in "sync" state forever
- "could not receive data from WAL stream"
- Initial table sync failing

**Solutions:**

1. **Check subscription status:**
   ```sql
   SELECT * FROM pg_subscription;
   SELECT * FROM pg_subscription_rel;
   ```

2. **Resync specific table:**
   ```sql
   ALTER SUBSCRIPTION mysub REFRESH PUBLICATION;
   ```

3. **Drop and recreate subscription:**
   ```sql
   DROP SUBSCRIPTION mysub;
   CREATE SUBSCRIPTION mysub
     CONNECTION 'host=... port=5432 ...'
     PUBLICATION mypub
     WITH (copy_data = true);
   ```

### Issue 8: Out of Disk Space During Upgrade

**Symptoms:**
- "No space left on device"
- pg_upgrade fails midway
- Database corruption

**Solutions:**

1. **Use link mode:**
   ```bash
   # Requires same filesystem
   pg_upgrade --link ...
   ```

2. **Clean up WAL files:**
   ```bash
   # Archive or delete old WAL
   pg_archivecleanup /var/lib/postgresql/data/pg_wal XXXXXXXXXXXX
   ```

3. **Expand PVC:**
   ```bash
   kubectl patch pvc data-postgresql-0 -n default -p \
     '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
   ```

---

## Best Practices

### Before Upgrade

1. **Always create full backup** before any upgrade
2. **Test upgrade in non-production** environment first
3. **Review release notes** for all versions in upgrade path
4. **Document current configuration** for potential rollback
5. **Plan maintenance window** for major version upgrades
6. **Notify dependent applications** about potential downtime
7. **Check extension compatibility** for target version
8. **Verify disk space** is sufficient (2x for pg_upgrade copy mode)

### During Upgrade

1. **Monitor logs** during upgrade process
2. **Check disk space** during data migration
3. **Verify replication status** after each replica upgrades
4. **Run pg_upgrade --check** before actual upgrade
5. **Be ready to rollback** if issues occur
6. **Keep old binaries/data** until upgrade is verified

### After Upgrade

1. **Run ANALYZE** to update statistics
2. **Verify all extensions** are working
3. **Test critical queries** and application functionality
4. **Monitor performance** for 24-48 hours
5. **Update connection strings** if needed
6. **Remove old cluster** only after verification
7. **Document upgrade** for future reference
8. **Update monitoring/alerting** thresholds if needed

### General Recommendations

1. **Use streaming replication** for HA setups
2. **Keep PostgreSQL up to date** (within 2 minor versions)
3. **Automate backup/restore** testing regularly
4. **Use pg_upgrade link mode** when possible
5. **Consider logical replication** for zero-downtime upgrades
6. **Test rollback procedure** before production upgrade
7. **Use health checks and readiness probes** in Kubernetes
8. **Configure proper resource limits** based on workload

### Upgrade Frequency

| Update Type | Recommended Frequency | Notes |
|------------|----------------------|-------|
| Minor version | Within 1-2 months | Bug and security fixes |
| Major version | Within 6 months of release | After thorough testing |
| Emergency patch | Immediately | Critical security fixes |

### Minimizing Downtime

1. **Use logical replication** for near-zero downtime
2. **Pre-stage new environment** before cutover
3. **Use blue-green deployments** for critical systems
4. **Schedule during low-traffic periods**
5. **Prepare rollback procedure** in advance

---

## Related Documentation

- [PostgreSQL Backup Guide](postgresql-backup-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Chart README](../charts/postgresql/README.md)
- [PostgreSQL Makefile](../make/ops/postgresql.mk)
- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [pg_upgrade Documentation](https://www.postgresql.org/docs/current/pgupgrade.html)

---

**Last Updated:** 2025-12-01
**Chart Version:** 0.3.0
**PostgreSQL Version:** 16.11
