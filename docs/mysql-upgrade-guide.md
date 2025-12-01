# MySQL Upgrade Guide

This comprehensive guide covers upgrade procedures for the MySQL Helm chart deployment in Kubernetes, including minor version upgrades, major version upgrades, and rollback procedures.

## Table of Contents

1. [Overview](#overview)
2. [Upgrade Strategies](#upgrade-strategies)
3. [Pre-Upgrade Preparation](#pre-upgrade-preparation)
4. [Minor Version Upgrades](#minor-version-upgrades)
5. [Major Version Upgrades](#major-version-upgrades)
6. [In-Place Upgrade Procedure](#in-place-upgrade-procedure)
7. [Blue-Green Upgrade](#blue-green-upgrade)
8. [Rollback Procedures](#rollback-procedures)
9. [Version-Specific Notes](#version-specific-notes)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### Upgrade Philosophy

MySQL upgrades in Kubernetes should prioritize:
- **Minimal downtime** for production systems
- **Data integrity** throughout the upgrade process
- **Rollback capability** if issues arise
- **Testing** before production deployment

### MySQL Versioning

MySQL follows semantic versioning: `MAJOR.MINOR.PATCH`

**Examples**:
- `8.0.32` → `8.0.35`: **Patch upgrade** (bug fixes only)
- `8.0.35` → `8.1.0`: **Minor upgrade** (new features, backward compatible)
- `8.0.35` → `9.0.0`: **Major upgrade** (breaking changes possible)

**Supported upgrade paths**:
- ✅ MySQL 5.7 → MySQL 8.0 (one major version at a time)
- ✅ MySQL 8.0.32 → MySQL 8.0.35 (within same minor version)
- ✅ MySQL 8.0 → MySQL 8.1 (minor version upgrade)
- ❌ MySQL 5.7 → MySQL 9.0 (skipping major versions not supported)

---

## Upgrade Strategies

### Strategy Comparison

| Strategy | Downtime | Complexity | Rollback | Use Case |
|----------|----------|------------|----------|----------|
| **Rolling Upgrade** | None (with replicas) | Low | Easy (Helm rollback) | Minor versions, patch upgrades |
| **In-Place Upgrade** | 10-30 minutes | Medium | Medium (restore from backup) | Major versions, single instance |
| **Dump/Restore** | 1-4 hours | Low | Easy (keep old instance) | Major version jumps, clean start |
| **Blue-Green** | 5-10 minutes (cutover) | High | Easy (switch back) | Critical systems, zero-downtime |
| **Replication Upgrade** | < 1 minute | High | Easy (failback) | Near-zero downtime, major versions |

### Recommended Approaches

**Development/Testing**:
- Use **in-place upgrade** or **dump/restore**
- Downtime acceptable
- Focus on testing upgrade process

**Production**:
- Use **rolling upgrade** for minor versions
- Use **blue-green** or **replication upgrade** for major versions
- Minimize downtime and risk

---

## Pre-Upgrade Preparation

### Pre-Upgrade Checklist

**Critical steps** (complete ALL before upgrading):

- [ ] **1. Backup all databases**
  ```bash
  make -f make/ops/mysql.mk mysql-backup-all
  ```

- [ ] **2. Backup configuration**
  ```bash
  make -f make/ops/mysql.mk mysql-backup-config
  ```

- [ ] **3. Archive binary logs**
  ```bash
  make -f make/ops/mysql.mk mysql-archive-binlogs
  ```

- [ ] **4. Create PVC snapshot** (optional but recommended)
  ```bash
  make -f make/ops/mysql.mk mysql-backup-pvc-snapshot
  ```

- [ ] **5. Run pre-upgrade checks**
  ```bash
  make -f make/ops/mysql.mk mysql-pre-upgrade-check
  ```

- [ ] **6. Check MySQL release notes**
  - Review breaking changes: https://dev.mysql.com/doc/relnotes/mysql/8.0/en/
  - Note deprecated features
  - Review new features and configuration changes

- [ ] **7. Test upgrade in non-production environment**
  - Clone production data to staging
  - Perform full upgrade test
  - Run application tests

- [ ] **8. Check disk space**
  - Data directory: At least 20% free
  - Backup storage: Enough for full backup
  - Temporary space: For upgrade process

- [ ] **9. Check replication status** (if applicable)
  ```bash
  make -f make/ops/mysql.mk mysql-replication-status
  ```

- [ ] **10. Document current state**
  - MySQL version: `SELECT VERSION();`
  - Database sizes: `make -f make/ops/mysql.mk mysql-database-size`
  - Table counts: Document for post-upgrade verification
  - Configuration: Current my.cnf settings

- [ ] **11. Schedule maintenance window**
  - Notify stakeholders
  - Plan for rollback time if needed
  - Have team available for support

- [ ] **12. Verify backup integrity**
  ```bash
  make -f make/ops/mysql.mk mysql-backup-verify FILE=tmp/mysql-backups/latest.sql.gz
  ```

- [ ] **13. Check storage class and PVC**
  ```bash
  kubectl get pvc -l app.kubernetes.io/name=mysql
  ```

- [ ] **14. Review Helm chart changes**
  ```bash
  helm show values sb-charts/mysql --version NEW_VERSION
  diff <(helm get values mysql) <(helm show values sb-charts/mysql --version NEW_VERSION)
  ```

- [ ] **15. Prepare rollback plan**
  - Document rollback steps
  - Test rollback procedure
  - Identify rollback decision point

### Pre-Upgrade Validation

```bash
# Run comprehensive pre-upgrade checks
make -f make/ops/mysql.mk mysql-pre-upgrade-check
```

**What it checks**:
1. Current MySQL version
2. Database sizes (for capacity planning)
3. Active connections (ensure graceful shutdown)
4. Replication status (if enabled)
5. Binary log status
6. InnoDB status (tablespace health)
7. Deprecated features usage
8. Storage capacity
9. Resource utilization

**Sample output**:
```
Running pre-upgrade checks...

1. MySQL Version:
mysql  Ver 8.0.35 for Linux on x86_64 (MySQL Community Server - GPL)

2. Database Sizes:
+--------------------+------------+
| database_name      | size       |
+--------------------+------------+
| mysql              | 2.45 MB    |
| information_schema | 0 bytes    |
| myapp              | 123.45 MB  |
+--------------------+------------+

3. Active Connections: 12

4. Replication Status: 1 replica connected, lag = 0 seconds

5. Binary Log: Enabled, 15 logs, 1.2 GB total

6. InnoDB Status: OK

7. Deprecated Features:
  - utf8mb3 charset detected (use utf8mb4)
  - mysql_native_password plugin (upgrade to caching_sha2_password)

8. Storage Capacity: 65% used (3.5 GB free)

9. Resource Usage: CPU 25%, Memory 45%

✅ Pre-upgrade checks completed.
⚠️  Warnings: 2 deprecated features detected (see above)
📝 Recommendation: Create backup with: make -f make/ops/mysql.mk mysql-backup-all
```

---

## Minor Version Upgrades

**Example**: MySQL 8.0.32 → MySQL 8.0.35 (patch/minor upgrade within 8.0)

### Rolling Upgrade (Zero Downtime)

**Prerequisites**:
- `replicaCount >= 2` (for rolling update)
- `readinessProbe` configured
- Load balancer or service mesh

**Procedure**:

#### Step 1: Update Helm chart

```bash
# Check current version
helm list -n default | grep mysql

# Update to new version
helm upgrade mysql sb-charts/mysql \
  --set image.tag=8.0.35 \
  --reuse-values

# Monitor rollout
kubectl rollout status statefulset/mysql
```

**What happens**:
1. Kubernetes updates pods one by one
2. Each pod:
   - Stops accepting new connections
   - Waits for existing connections to finish
   - Shuts down gracefully
   - Starts with new version
   - Becomes ready (passes readinessProbe)
3. Service routes traffic to ready pods only
4. **Zero downtime** if replicas >= 2

#### Step 2: Verify upgrade

```bash
# Check all pods are running new version
kubectl exec -it mysql-0 -- mysql --version
kubectl exec -it mysql-1 -- mysql --version

# Run post-upgrade checks
make -f make/ops/mysql.mk mysql-post-upgrade-check
```

#### Step 3: Monitor for issues

```bash
# Watch logs for errors
kubectl logs -f mysql-0

# Check replication status
make -f make/ops/mysql.mk mysql-replication-status

# Monitor performance
kubectl top pods -l app.kubernetes.io/name=mysql
```

**Rollback** (if issues occur):

```bash
# Rollback to previous version
helm rollback mysql
```

**Total time**: 10-30 minutes
**Downtime**: None (with replicas >= 2)

---

## Major Version Upgrades

**Example**: MySQL 5.7 → MySQL 8.0 or MySQL 8.0 → MySQL 8.1

### Strategy Selection

**Choose based on requirements**:

| Requirement | Strategy |
|-------------|----------|
| **Minimal downtime** | Blue-Green or Replication Upgrade |
| **Simple procedure** | In-Place Upgrade or Dump/Restore |
| **Clean state** | Dump/Restore |
| **Testing flexibility** | Blue-Green |
| **Limited resources** | In-Place Upgrade |

---

### Option 1: In-Place Upgrade

**Downtime**: 10-30 minutes
**Complexity**: Medium
**Recommended for**: Small databases, maintenance window acceptable

#### Procedure

**Step 1: Stop applications**

```bash
# Scale down applications to prevent writes
kubectl scale deployment myapp --replicas=0
```

**Step 2: Create backup** (critical!)

```bash
make -f make/ops/mysql.mk mysql-backup-all
```

**Step 3: Run mysql_upgrade_check** (MySQL 8.0.16+)

```bash
kubectl exec -it mysql-0 -- mysqlcheck -u root -p$MYSQL_ROOT_PASSWORD \
  --all-databases --check-upgrade
```

**Sample output**:
```
myapp.users  OK
myapp.orders  OK
mysql.user  Needs upgrade  # ← Will be upgraded
```

**Step 4: Upgrade MySQL image**

```bash
# Upgrade to MySQL 8.0
helm upgrade mysql sb-charts/mysql \
  --set image.tag=8.0 \
  --reuse-values

# Wait for pod restart
kubectl rollout status statefulset/mysql
```

**Step 5: Run mysql_upgrade** (MySQL 5.7 to 8.0)

**MySQL 8.0.16+**: Auto-upgrade on startup (no manual step needed)

**MySQL 5.7 to 8.0.15**: Manual upgrade required

```bash
kubectl exec -it mysql-0 -- mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD
```

**Output**:
```
Checking if update is needed.
Checking server version.
Running queries to upgrade MySQL server.
Checking system database.
mysql.columns_priv                                 OK
mysql.db                                           OK
mysql.engine_cost                                  OK
...
Upgrade process completed successfully.
```

**Step 6: Verify upgrade**

```bash
# Check version
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SELECT VERSION();"

# Run post-upgrade checks
make -f make/ops/mysql.mk mysql-post-upgrade-check
```

**Step 7: Restart applications**

```bash
kubectl scale deployment myapp --replicas=3
```

**Total time**: 10-30 minutes
**Downtime**: 10-30 minutes

---

### Option 2: Dump/Restore Upgrade

**Downtime**: 1-4 hours (depends on DB size)
**Complexity**: Low
**Recommended for**: Major version jumps, clean installation

#### Procedure

**Step 1: Backup from old version**

```bash
# Connect to MySQL 5.7 instance
make -f make/ops/mysql.mk mysql-backup-all

# Save to tmp/mysql-backups/mysql-all-5.7-final.sql.gz
```

**Step 2: Deploy new MySQL version**

```bash
# Deploy MySQL 8.0 (new instance)
helm install mysql8 sb-charts/mysql \
  --set image.tag=8.0 \
  --set persistence.size=20Gi \
  -f values.yaml

# Wait for pod ready
kubectl wait --for=condition=ready pod/mysql8-0 --timeout=300s
```

**Step 3: Restore data to new version**

```bash
# Restore backup to MySQL 8.0
zcat tmp/mysql-backups/mysql-all-5.7-final.sql.gz | \
  kubectl exec -i mysql8-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD

# Or use Makefile
make -f make/ops/mysql.mk mysql-restore-all \
  FILE=tmp/mysql-backups/mysql-all-5.7-final.sql.gz
```

**Step 4: Verify data integrity**

```bash
# Compare database list
kubectl exec -it mysql8-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"

# Compare table counts
kubectl exec -it mysql8-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp -e "
  SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
  UNION ALL
  SELECT 'orders', COUNT(*) FROM orders;
"

# Check data samples
kubectl exec -it mysql8-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp -e "
  SELECT * FROM users LIMIT 5;
  SELECT * FROM orders ORDER BY id DESC LIMIT 5;
"
```

**Step 5: Update application configuration**

```bash
# Update connection string to point to mysql8 service
kubectl set env deployment/myapp MYSQL_HOST=mysql8
```

**Step 6: Test application**

```bash
# Deploy test instance
kubectl scale deployment myapp --replicas=1

# Verify functionality
# (application-specific tests)

# Scale up after verification
kubectl scale deployment myapp --replicas=3
```

**Step 7: Decommission old MySQL instance**

```bash
# After 1 week of stable operation
helm uninstall mysql
kubectl delete pvc data-mysql-0
```

**Total time**: 1-4 hours
**Downtime**: 1-4 hours

---

### Option 3: Blue-Green Upgrade

**Downtime**: 5-10 minutes (DNS/service cutover)
**Complexity**: High
**Recommended for**: Critical systems, zero-downtime requirement

#### Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Blue-Green Upgrade                  │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [Applications] ──→ [Service: mysql]                │
│                         ↓                            │
│                   ┌─────────┐                       │
│  BLUE (old):     │ MySQL   │ (version 5.7)          │
│                   │ 5.7     │                        │
│                   └─────────┘                       │
│                                                      │
│  GREEN (new):    ┌─────────┐                       │
│                   │ MySQL   │ (version 8.0)          │
│                   │ 8.0     │                        │
│                   └─────────┘                       │
│                         ↑                            │
│  After cutover:  [Service selector updated]         │
│                                                      │
└─────────────────────────────────────────────────────┘
```

#### Procedure

**Step 1: Deploy GREEN environment** (MySQL 8.0)

```bash
# Deploy new MySQL 8.0 instance
helm install mysql-green sb-charts/mysql \
  --set image.tag=8.0 \
  --set fullnameOverride=mysql-green \
  --set service.port=3306 \
  -f values.yaml
```

**Step 2: Setup replication** (BLUE → GREEN)

**On BLUE (MySQL 5.7)**:
```sql
-- Create replication user
CREATE USER 'replicator'@'%' IDENTIFIED BY 'secret';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH PRIVILEGES;

-- Get binlog position
SHOW MASTER STATUS;
-- Note: File=mysql-bin.000005, Position=12345
```

**On GREEN (MySQL 8.0)**:
```sql
-- Configure replication
CHANGE MASTER TO
  MASTER_HOST='mysql',  -- BLUE service name
  MASTER_USER='replicator',
  MASTER_PASSWORD='secret',
  MASTER_LOG_FILE='mysql-bin.000005',
  MASTER_LOG_POS=12345;

-- Start replication
START SLAVE;

-- Verify
SHOW SLAVE STATUS\G
```

**Step 3: Monitor replication lag**

```bash
# Check lag on GREEN
kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SHOW SLAVE STATUS\G
" | grep Seconds_Behind_Master

# Wait for lag = 0
```

**Step 4: Cutover** (switch applications to GREEN)

```bash
# Stop writes to BLUE
kubectl scale deployment myapp --replicas=0

# Wait for replication to catch up (lag = 0)
kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SHOW SLAVE STATUS\G
" | grep Seconds_Behind_Master

# Stop replication on GREEN
kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  STOP SLAVE;
  RESET SLAVE ALL;
"

# Update service selector to point to GREEN
kubectl patch svc mysql -p '{"spec":{"selector":{"app.kubernetes.io/instance":"mysql-green"}}}'

# Or rename services:
kubectl delete svc mysql
kubectl get svc mysql-green -o yaml | \
  sed 's/mysql-green/mysql/g' | kubectl apply -f -

# Restart applications (now pointing to GREEN/MySQL 8.0)
kubectl scale deployment myapp --replicas=3
```

**Step 5: Verify and monitor**

```bash
# Check application logs
kubectl logs -f deployment/myapp

# Monitor GREEN database
make -f make/ops/mysql.mk mysql-stats

# Run post-upgrade checks
make -f make/ops/mysql.mk mysql-post-upgrade-check
```

**Step 6: Decommission BLUE** (after 1 week of stable operation)

```bash
helm uninstall mysql  # Old BLUE instance
kubectl delete pvc data-mysql-0
```

**Total time**: 2-4 hours (replication sync) + 5-10 minutes (cutover)
**Downtime**: 5-10 minutes (application restart)

---

### Option 4: Replication Upgrade (Near-Zero Downtime)

**Downtime**: < 1 minute
**Complexity**: High
**Recommended for**: Critical 24/7 systems

#### Procedure

**Similar to Blue-Green**, but with replica promotion:

1. Deploy new version as **replica** of old version
2. Sync data via replication (lag → 0)
3. **Promote replica to primary** (minimal downtime)
4. Redirect applications to new primary

**Key difference**: Use replication promotion instead of service cutover

**Commands**:
```bash
# Step 1: Deploy MySQL 8.0 as replica
helm install mysql8-replica sb-charts/mysql \
  --set image.tag=8.0 \
  --set mysql.replication.enabled=true

# Step 2: Setup replication (see Blue-Green)

# Step 3: Promote replica
make -f make/ops/mysql.mk mysql-promote-replica POD=mysql8-replica-0

# Step 4: Update application config
kubectl set env deployment/myapp MYSQL_HOST=mysql8-replica
```

**Total time**: 2-4 hours (replication sync)
**Downtime**: < 1 minute

---

## In-Place Upgrade Procedure

### Detailed Walkthrough

**Use case**: MySQL 5.7.44 → MySQL 8.0.35

#### Phase 1: Preparation (Day before upgrade)

```bash
# 1. Backup everything
make -f make/ops/mysql.mk mysql-backup-all
make -f make/ops/mysql.mk mysql-backup-config
make -f make/ops/mysql.mk mysql-archive-binlogs

# 2. Run pre-upgrade checks
make -f make/ops/mysql.mk mysql-pre-upgrade-check

# 3. Test upgrade in staging environment
# (staging-specific steps)

# 4. Schedule maintenance window
# Notify: "MySQL upgrade scheduled for tomorrow 2 AM - 3 AM"
```

#### Phase 2: Upgrade (Maintenance window)

```bash
# 1. Stop applications (2:00 AM)
kubectl scale deployment myapp --replicas=0

# 2. Verify no active connections
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SELECT COUNT(*) AS active_connections
  FROM information_schema.processlist
  WHERE command != 'Sleep';
"
# Should return 0 (or only your connection)

# 3. Final backup (2:05 AM)
make -f make/ops/mysql.mk mysql-backup-all

# 4. Upgrade MySQL image (2:10 AM)
helm upgrade mysql sb-charts/mysql \
  --set image.tag=8.0.35 \
  --reuse-values

# 5. Wait for pod restart (2:12 AM)
kubectl wait --for=condition=ready pod/mysql-0 --timeout=300s

# 6. Verify version (2:15 AM)
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SELECT VERSION();"
# Output: 8.0.35

# 7. Run mysql_upgrade if needed (< 8.0.16)
# (MySQL 8.0.16+ auto-upgrades)

# 8. Post-upgrade checks (2:20 AM)
make -f make/ops/mysql.mk mysql-post-upgrade-check

# 9. Restart applications (2:25 AM)
kubectl scale deployment myapp --replicas=3

# 10. Monitor (2:30 AM)
kubectl logs -f mysql-0
kubectl logs -f deployment/myapp
```

#### Phase 3: Validation (Next day)

```bash
# 1. Check application logs
kubectl logs --since=24h deployment/myapp | grep -i error

# 2. Verify data integrity
make -f make/ops/mysql.mk mysql-database-size
# Compare with pre-upgrade snapshot

# 3. Monitor performance
kubectl top pods -l app.kubernetes.io/name=mysql

# 4. Backup new version
make -f make/ops/mysql.mk mysql-backup-all
```

**Total time**: 25 minutes
**Downtime**: 25 minutes

---

## Blue-Green Upgrade

### Detailed Walkthrough

**Use case**: MySQL 8.0.35 → MySQL 8.1.0 (zero-downtime requirement)

#### Phase 1: Deploy GREEN environment

```bash
# 1. Deploy MySQL 8.1 (GREEN)
helm install mysql-green sb-charts/mysql \
  --set image.tag=8.1.0 \
  --set fullnameOverride=mysql-green \
  --set persistence.size=20Gi \
  -f values-green.yaml

# 2. Wait for ready
kubectl wait --for=condition=ready pod/mysql-green-0 --timeout=600s
```

#### Phase 2: Data synchronization

```bash
# 1. Setup replication (BLUE → GREEN)
# See "Blue-Green Upgrade" section above

# 2. Monitor replication lag
watch -n 5 'kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW SLAVE STATUS\G" | grep Seconds_Behind_Master'

# Wait for: Seconds_Behind_Master: 0
```

#### Phase 3: Cutover

```bash
# 1. Enable read-only on BLUE (prevent new writes)
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SET GLOBAL read_only = 1;
"

# 2. Wait for GREEN to catch up (should be instant since no new writes)
kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SHOW SLAVE STATUS\G
" | grep Seconds_Behind_Master
# Should show: Seconds_Behind_Master: 0

# 3. Stop replication on GREEN
kubectl exec -it mysql-green-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  STOP SLAVE;
  RESET SLAVE ALL;
  SET GLOBAL read_only = 0;  -- Enable writes
"

# 4. Update application configuration
kubectl set env deployment/myapp MYSQL_HOST=mysql-green

# 5. Rolling restart applications
kubectl rollout restart deployment/myapp
kubectl rollout status deployment/myapp

# 6. Verify applications are using GREEN
kubectl logs deployment/myapp | grep -i "connected to"
```

#### Phase 4: Cleanup

```bash
# After 1 week of stable operation:

# 1. Backup GREEN
make -f make/ops/mysql.mk mysql-backup-all

# 2. Delete BLUE
helm uninstall mysql
kubectl delete pvc data-mysql-0

# 3. Rename GREEN to mysql (optional)
helm upgrade mysql-green sb-charts/mysql \
  --set fullnameOverride=mysql \
  -f values.yaml
```

---

## Rollback Procedures

### Rollback Decision Points

**When to rollback**:
- Application errors after upgrade
- Performance degradation (> 20% slower)
- Data corruption detected
- Replication failures
- Critical bugs discovered in new version

**When NOT to rollback**:
- Minor performance differences (< 10%)
- Warning messages (investigate first)
- Expected deprecation warnings

### Rollback Methods

#### Method 1: Helm Rollback (Rolling Upgrade)

**Use case**: Rolling upgrade failed, need to revert to previous version

```bash
# Check rollback history
helm history mysql

# Rollback to previous version
helm rollback mysql

# Or rollback to specific revision
helm rollback mysql 2

# Verify rollback
kubectl exec -it mysql-0 -- mysql --version
```

**Time**: 5-10 minutes
**Downtime**: None (with replicas >= 2)

#### Method 2: Restore from Backup (In-Place Upgrade)

**Use case**: In-place upgrade completed but issues discovered

```bash
# 1. Stop applications
kubectl scale deployment myapp --replicas=0

# 2. Delete current data (dangerous - ensure backup is good!)
kubectl delete statefulset mysql --cascade=false
kubectl delete pvc data-mysql-0

# 3. Redeploy old version
helm upgrade mysql sb-charts/mysql \
  --set image.tag=5.7.44 \
  -f values.yaml

# 4. Wait for pod ready
kubectl wait --for=condition=ready pod/mysql-0 --timeout=300s

# 5. Restore backup
make -f make/ops/mysql.mk mysql-restore-all \
  FILE=tmp/mysql-backups/mysql-all-pre-upgrade.sql.gz

# 6. Verify data
make -f make/ops/mysql.mk mysql-database-size

# 7. Restart applications
kubectl scale deployment myapp --replicas=3
```

**Time**: 30 minutes - 2 hours
**Downtime**: 30 minutes - 2 hours

#### Method 3: Switch Back (Blue-Green)

**Use case**: Blue-Green upgrade completed but issues in GREEN

```bash
# 1. Stop applications
kubectl scale deployment myapp --replicas=0

# 2. Switch service back to BLUE
kubectl patch svc mysql -p '{"spec":{"selector":{"app.kubernetes.io/instance":"mysql"}}}'

# 3. Enable writes on BLUE
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  SET GLOBAL read_only = 0;
"

# 4. Restart applications
kubectl scale deployment myapp --replicas=3

# 5. Investigate GREEN issues
kubectl logs mysql-green-0
```

**Time**: 5-10 minutes
**Downtime**: 5-10 minutes

#### Method 4: Point-in-Time Recovery

**Use case**: Data corruption occurred after upgrade, need to restore to before upgrade

```bash
# Restore to exact time before upgrade started
make -f make/ops/mysql.mk mysql-pitr \
  RECOVERY_TIME='2025-01-15 02:00:00' \
  BASE_BACKUP=tmp/mysql-backups/mysql-all-pre-upgrade.sql.gz
```

**Time**: 1-2 hours
**Downtime**: 1-2 hours

---

## Version-Specific Notes

### MySQL 5.7 to 8.0

**Breaking changes**:

1. **Authentication plugin change**:
   - MySQL 5.7: `mysql_native_password` (default)
   - MySQL 8.0: `caching_sha2_password` (default)
   - **Action**: Update client libraries or use `default_authentication_plugin=mysql_native_password`

2. **Reserved keywords added**:
   - New keywords: `SYSTEM`, `WINDOW`, `LATERAL`, etc.
   - **Action**: Quote table/column names if they conflict

3. **SQL modes changed**:
   - `NO_AUTO_CREATE_USER` removed
   - **Action**: Update scripts that rely on this mode

4. **Character set utf8mb3 deprecated**:
   - `utf8mb3` → use `utf8mb4` instead
   - **Action**: Convert character sets before or after upgrade

**Configuration changes**:

```ini
# MySQL 5.7
[mysqld]
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION

# MySQL 8.0
[mysqld]
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
# NO_AUTO_CREATE_USER removed
```

**Recommended upgrade steps**:

```bash
# 1. Check for deprecated features
mysqlcheck -u root -p --all-databases --check-upgrade

# 2. Run mysql_upgrade after in-place upgrade
mysql_upgrade -u root -p

# 3. Update authentication plugin (if needed)
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';

# 4. Convert character sets
ALTER DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### MySQL 8.0 to 8.1

**New features**:
- Instant DDL enhancements
- Performance improvements
- New system variables

**Breaking changes**: Minimal (mostly backward compatible)

**Recommended upgrade**: Rolling upgrade or blue-green

### MySQL 8.1 to 9.0

**Note**: MySQL 9.0 not yet released as of January 2025

**Expected changes**:
- Major performance improvements
- Possible breaking changes (review release notes when available)

---

## Post-Upgrade Validation

### Automated Validation

```bash
make -f make/ops/mysql.mk mysql-post-upgrade-check
```

**What it checks**:
1. MySQL version (should be new version)
2. Pod status (should be Running)
3. Database accessibility (can connect and query)
4. Replication status (if enabled)
5. Database sizes (compare with pre-upgrade)
6. Table counts (verify data integrity)
7. Sample data queries
8. Performance metrics (connections, queries/sec)

### Manual Validation

```bash
# 1. Verify version
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SELECT VERSION();"

# 2. Check all databases present
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"

# 3. Verify table counts match pre-upgrade
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp -e "
  SELECT COUNT(*) FROM users;
  SELECT COUNT(*) FROM orders;
"

# 4. Check data samples
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD myapp -e "
  SELECT * FROM users LIMIT 5;
  SELECT * FROM orders ORDER BY id DESC LIMIT 5;
"

# 5. Verify replication (if applicable)
make -f make/ops/mysql.mk mysql-replication-status

# 6. Check binary logs enabled
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW BINARY LOGS;"

# 7. Monitor error log
kubectl logs mysql-0 | grep -i error

# 8. Application smoke tests
# (Application-specific validation)
```

---

## Troubleshooting

### Common Issues

#### 1. Upgrade fails with "Table 'mysql.plugin' doesn't exist"

**Cause**: Corrupted system tables

**Solution**:
```bash
# Run mysql_upgrade with --force
kubectl exec -it mysql-0 -- mysql_upgrade -u root -p --force
```

#### 2. Application can't connect after upgrade: "Authentication plugin 'caching_sha2_password' cannot be loaded"

**Cause**: Old client libraries don't support new authentication plugin

**Solution** (Option 1 - Update clients):
```bash
# Update client libraries to support caching_sha2_password
# Example for PHP:
apt-get update && apt-get install php-mysql
```

**Solution** (Option 2 - Use old authentication):
```sql
# Change user to use old plugin
ALTER USER 'myapp'@'%' IDENTIFIED WITH mysql_native_password BY 'password';
FLUSH PRIVILEGES;
```

**Solution** (Option 3 - Change default):
```ini
# In my.cnf
[mysqld]
default_authentication_plugin=mysql_native_password
```

#### 3. Performance degradation after upgrade

**Cause**: Optimizer statistics outdated

**Solution**:
```bash
# Rebuild optimizer statistics
make -f make/ops/mysql.mk mysql-analyze-tables

# Or manual:
kubectl exec -it mysql-0 -- mysqlcheck -u root -p --all-databases --analyze
```

#### 4. Replication lag increasing after upgrade

**Cause**: Replica running old version, incompatible with new primary

**Solution**:
```bash
# Upgrade replica to same version as primary
helm upgrade mysql-replica sb-charts/mysql \
  --set image.tag=8.0.35

# Restart replication
kubectl exec -it mysql-replica-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  STOP SLAVE;
  START SLAVE;
"
```

#### 5. "ERROR 3098 (HY000): The table does not comply with the requirements by an external plugin"

**Cause**: InnoDB upgrade required

**Solution**:
```bash
# Rebuild table
ALTER TABLE myapp.problematic_table ENGINE=InnoDB;
```

#### 6. Helm rollback fails

**Cause**: StatefulSet immutable fields changed

**Solution**:
```bash
# Delete and recreate (risky - ensure backup exists!)
kubectl delete statefulset mysql --cascade=false
helm upgrade mysql sb-charts/mysql --set image.tag=OLD_VERSION -f values.yaml
```

#### 7. mysql_upgrade fails with "Access denied"

**Cause**: Insufficient privileges

**Solution**:
```bash
# Grant necessary privileges
kubectl exec -it mysql-0 -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "
  GRANT ALL PRIVILEGES ON mysql.* TO 'root'@'localhost';
  FLUSH PRIVILEGES;
"

# Retry mysql_upgrade
kubectl exec -it mysql-0 -- mysql_upgrade -u root -p
```

#### 8. Out of disk space during upgrade

**Cause**: mysql_upgrade creates temporary tables

**Solution**:
```bash
# Increase PVC size before upgrade
kubectl patch pvc data-mysql-0 -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Wait for resize
kubectl get pvc data-mysql-0 -w
```

---

## Best Practices

### Planning

1. **Always test upgrades in non-production first**
2. **Read release notes** for breaking changes
3. **Schedule maintenance windows** during low-traffic periods
4. **Have rollback plan ready** with decision criteria
5. **Communicate upgrade schedule** to stakeholders

### Execution

1. **Backup everything** before upgrade (databases, config, binlogs)
2. **Verify backups** can be restored
3. **Run pre-upgrade checks** to identify issues
4. **Monitor closely** during and after upgrade
5. **Validate thoroughly** before declaring success

### Post-Upgrade

1. **Keep old backup for 30 days** (in case delayed issues found)
2. **Monitor performance** for 1 week
3. **Update documentation** (runbooks, architecture diagrams)
4. **Document lessons learned** for next upgrade

---

## Appendix

### Upgrade Checklist

**Pre-Upgrade**:
- [ ] Backup all databases
- [ ] Backup configuration
- [ ] Archive binary logs
- [ ] Create PVC snapshot
- [ ] Run pre-upgrade checks
- [ ] Test in non-production
- [ ] Schedule maintenance window
- [ ] Prepare rollback plan

**During Upgrade**:
- [ ] Stop applications (if needed)
- [ ] Verify no active connections
- [ ] Perform upgrade (method-specific steps)
- [ ] Wait for pods ready
- [ ] Run mysql_upgrade (if needed)

**Post-Upgrade**:
- [ ] Verify MySQL version
- [ ] Run post-upgrade checks
- [ ] Verify data integrity
- [ ] Check replication status
- [ ] Monitor error logs
- [ ] Restart applications
- [ ] Perform smoke tests

**Post-Validation** (Next day):
- [ ] Check application logs
- [ ] Monitor performance
- [ ] Backup new version
- [ ] Document issues encountered

### Reference Commands

```bash
# Pre-upgrade
make -f make/ops/mysql.mk mysql-backup-all
make -f make/ops/mysql.mk mysql-pre-upgrade-check

# Upgrade
helm upgrade mysql sb-charts/mysql --set image.tag=NEW_VERSION

# Post-upgrade
make -f make/ops/mysql.mk mysql-post-upgrade-check
make -f make/ops/mysql.mk mysql-analyze-tables

# Rollback
helm rollback mysql
make -f make/ops/mysql.mk mysql-restore-all FILE=backup.sql.gz
```

### External Resources

- [MySQL 8.0 Upgrade Guide](https://dev.mysql.com/doc/refman/8.0/en/upgrading.html)
- [MySQL Release Notes](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)
- [mysql_upgrade Documentation](https://dev.mysql.com/doc/refman/8.0/en/mysql-upgrade.html)
- [Replication Upgrade Best Practices](https://dev.mysql.com/doc/refman/8.0/en/replication-upgrade.html)

---

**Document version**: 1.0
**Last updated**: 2025-01-15
**Author**: ScriptonBasestar Helm Charts Team
