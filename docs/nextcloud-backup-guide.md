# Nextcloud Backup and Recovery Guide

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Nextcloud Files Backup](#1-nextcloud-files-backup)
  - [2. PostgreSQL Database Backup](#2-postgresql-database-backup)
  - [3. Redis Cache Backup](#3-redis-cache-backup)
  - [4. Configuration Backup](#4-configuration-backup)
  - [5. PVC Snapshot Backup](#5-pvc-snapshot-backup)
- [Recovery Procedures](#recovery-procedures)
  - [Files Recovery](#files-recovery)
  - [Database Recovery](#database-recovery)
  - [Configuration Recovery](#configuration-recovery)
  - [Full Disaster Recovery](#full-disaster-recovery)
- [Backup Automation](#backup-automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for backing up and recovering Nextcloud instances deployed via the Helm chart.

**Backup Philosophy:**
- **Multi-layered approach**: Files, database, cache, configuration, PVC snapshots
- **Granular recovery**: Restore individual files or complete instance
- **Minimal downtime**: Most backups can be performed without service interruption
- **Version compatibility**: Consider Nextcloud version when restoring backups

**Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO):**
- **RTO Target**: < 2 hours for complete Nextcloud instance recovery
- **RPO Target**: 24 hours (daily backups recommended)
- **Files Recovery**: < 1 hour (via file restore)
- **Database Recovery**: < 30 minutes (via pg_restore)
- **Configuration Recovery**: < 15 minutes (via config restore)

---

## Backup Strategy

Nextcloud backup strategy consists of five complementary components:

### 1. **Nextcloud Files Backup**
- **What**: User files, uploads, thumbnails, app data
- **Why**: Core user content and media
- **Frequency**: Daily (incremental), weekly (full)
- **Method**: rsync, tar, or external backup tools

### 2. **PostgreSQL Database Backup**
- **What**: User metadata, sharing permissions, file versions, activity logs
- **Why**: Critical application state and relationships
- **Frequency**: Daily (before major changes)
- **Method**: pg_dump, WAL archiving

### 3. **Redis Cache Backup**
- **What**: Session data, file locks, transactional file locking
- **Why**: Session continuity and locking state
- **Frequency**: Optional (cache can be rebuilt)
- **Method**: SAVE/BGSAVE commands

### 4. **Configuration Backup**
- **What**: config.php, ConfigMaps, Secrets, custom apps
- **Why**: Instance configuration and customizations
- **Frequency**: On every configuration change
- **Method**: Kubernetes resource export + file copy

### 5. **PVC Snapshot Backup**
- **What**: Persistent volumes (data, config, apps)
- **Why**: Complete point-in-time recovery capability
- **Frequency**: Weekly
- **Method**: VolumeSnapshot API

**Backup Priority Matrix:**

| Component | Priority | Frequency | Method | Size |
|-----------|----------|-----------|--------|------|
| User Files | Critical | Daily | rsync/tar | Large (GB-TB) |
| PostgreSQL DB | Critical | Daily | pg_dump | Medium (MB-GB) |
| Configuration | High | On Change | K8s Export | Small (KB) |
| Custom Apps | Medium | On Change | Directory Copy | Small (MB) |
| Redis Cache | Low | Optional | SAVE | Small (MB) |
| PVC Snapshot | High | Weekly | VolumeSnapshot | Large (GB-TB) |

---

## Backup Components

### 1. Nextcloud Files Backup

Nextcloud files include all user data, uploads, thumbnails, and app-specific data.

#### 1.1 Backup User Data Directory

Full backup of user files:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-data

# Manual method
kubectl exec -n default deployment/nextcloud -- tar czf /tmp/nextcloud-data.tar.gz -C /var/www/html/data .
kubectl cp default/nextcloud-pod:/tmp/nextcloud-data.tar.gz ./backups/nextcloud-data-$(date +%Y%m%d).tar.gz
```

**Expected output:**
```
Creating backup: /tmp/nextcloud-data.tar.gz
Backup size: 15GB
Backup completed in 12m34s
```

#### 1.2 Incremental Backup with rsync

For large data volumes, use incremental backups:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-data-incremental

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  rsync -av --delete /var/www/html/data/ /backup/nextcloud-data-incremental/
```

**Incremental backup strategy:**
- **Daily incremental**: Backup only changed files
- **Weekly full**: Complete backup as baseline
- **Retention**: Keep 7 daily + 4 weekly backups

#### 1.3 Backup Specific User Data

Backup individual user directories:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-user USER=admin

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  tar czf /tmp/user-admin.tar.gz -C /var/www/html/data admin
kubectl cp default/nextcloud-pod:/tmp/user-admin.tar.gz ./backups/user-admin-$(date +%Y%m%d).tar.gz
```

#### 1.4 Verify Backup Integrity

Verify backup file integrity:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-verify-backup BACKUP_FILE=nextcloud-data-20250101.tar.gz

# Manual method
tar tzf backups/nextcloud-data-20250101.tar.gz | head -20
```

**Expected output:**
```
admin/
admin/files/
admin/files/Photos/
admin/files/Documents/
...
Backup verification: OK
```

---

### 2. PostgreSQL Database Backup

The PostgreSQL database contains all Nextcloud metadata, user information, sharing permissions, and file versions.

#### 2.1 Full Database Dump

Create complete database backup:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-database

# Manual method (assumes external PostgreSQL)
kubectl exec -n default deployment/postgresql -- \
  pg_dump -U nextcloud -d nextcloud -Fc -f /tmp/nextcloud-db.dump
kubectl cp default/postgresql-pod:/tmp/nextcloud-db.dump ./backups/nextcloud-db-$(date +%Y%m%d).dump
```

**Backup formats:**
- `-Fc`: Custom compressed format (recommended)
- `-Fp`: Plain SQL format (human-readable)
- `-Fd`: Directory format (parallel dump/restore)

**Expected output:**
```
pg_dump: dumping database "nextcloud"
pg_dump: finished
Backup size: 256 MB
```

#### 2.2 Schema-Only Backup

Backup database schema without data:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-schema

# Manual method
kubectl exec -n default deployment/postgresql -- \
  pg_dump -U nextcloud -d nextcloud -s -f /tmp/nextcloud-schema.sql
```

#### 2.3 Specific Table Backup

Backup individual tables:

```bash
# Backup oc_filecache table (file metadata)
kubectl exec -n default deployment/postgresql -- \
  pg_dump -U nextcloud -d nextcloud -t oc_filecache -Fc -f /tmp/oc_filecache.dump

# Backup oc_share table (sharing permissions)
kubectl exec -n default deployment/postgresql -- \
  pg_dump -U nextcloud -d nextcloud -t oc_share -Fc -f /tmp/oc_share.dump
```

#### 2.4 WAL Archiving (Point-in-Time Recovery)

For continuous backup, configure PostgreSQL WAL archiving:

```yaml
# values.yaml - PostgreSQL configuration
postgresql:
  external:
    walArchiving:
      enabled: true
      destination: "s3://backups/nextcloud-wal/"
      archiveCommand: "wal-g wal-push %p"
```

**Benefits:**
- **Continuous backup**: Every database change captured
- **PITR**: Restore to any point in time
- **RPO**: Near-zero (seconds)

---

### 3. Redis Cache Backup

Redis stores session data and file locking information. While optional (cache can be rebuilt), backing up Redis preserves user sessions.

#### 3.1 Create Redis Snapshot

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-redis

# Manual method
kubectl exec -n default deployment/redis -- redis-cli SAVE
kubectl exec -n default deployment/redis -- cat /data/dump.rdb > ./backups/redis-dump-$(date +%Y%m%d).rdb
```

**Note:** `SAVE` blocks Redis, use `BGSAVE` for production:

```bash
kubectl exec -n default deployment/redis -- redis-cli BGSAVE
```

#### 3.2 Verify Redis Backup

```bash
# Check RDB file integrity
kubectl exec -n default deployment/redis -- redis-check-rdb /data/dump.rdb
```

**Expected output:**
```
[offset 0] Checking RDB file dump.rdb
[offset 26] AUX FIELD redis-ver = '8.0.0'
[offset 40] AUX FIELD redis-bits = '64'
...
RDB looks OK
```

---

### 4. Configuration Backup

Nextcloud configuration includes config.php, Kubernetes resources, and custom apps.

#### 4.1 Backup config.php

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-config

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  cat /var/www/html/config/config.php > ./backups/config-$(date +%Y%m%d).php
```

**config.php contains:**
- Database credentials
- Redis configuration
- Trusted domains
- App configurations
- Security settings

**Security Note:** config.php contains sensitive credentials. Encrypt backups:

```bash
# Encrypt config backup
openssl enc -aes-256-cbc -salt -in config.php -out config.php.enc
```

#### 4.2 Backup Kubernetes Resources

Export all Nextcloud-related Kubernetes resources:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-k8s-resources

# Manual method
kubectl get deployment,service,ingress,configmap,secret,pvc -n default -l app.kubernetes.io/name=nextcloud -o yaml > \
  ./backups/nextcloud-k8s-$(date +%Y%m%d).yaml
```

#### 4.3 Backup Custom Apps

Backup installed Nextcloud apps:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-backup-apps

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  tar czf /tmp/nextcloud-apps.tar.gz -C /var/www/html custom_apps
kubectl cp default/nextcloud-pod:/tmp/nextcloud-apps.tar.gz ./backups/nextcloud-apps-$(date +%Y%m%d).tar.gz
```

#### 4.4 Export Installed Apps List

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-list-apps

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  php occ app:list > ./backups/nextcloud-apps-list-$(date +%Y%m%d).txt
```

**Expected output:**
```
Enabled:
  - calendar: 4.8.1
  - contacts: 6.2.0
  - files_external: 1.22.0
  - photos: 3.1.2
  - ...
Disabled:
  - ...
```

---

### 5. PVC Snapshot Backup

VolumeSnapshots provide point-in-time backups of persistent volumes.

#### 5.1 Create Data PVC Snapshot

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-snapshot-data

# Manual method
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-data-snapshot-$(date +%Y%m%d)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: nextcloud-data
EOF
```

#### 5.2 Create Config PVC Snapshot

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-snapshot-config

# Manual method
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-config-snapshot-$(date +%Y%m%d)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: nextcloud-config
EOF
```

#### 5.3 Create Apps PVC Snapshot

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-snapshot-apps

# Manual method
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-apps-snapshot-$(date +%Y%m%d)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: nextcloud-apps
EOF
```

#### 5.4 List All Snapshots

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-list-snapshots

# Manual method
kubectl get volumesnapshot -n default | grep nextcloud
```

**Expected output:**
```
NAME                                AGE     SOURCEPVC          READYTOUSE
nextcloud-data-snapshot-20250101    2d      nextcloud-data     true
nextcloud-config-snapshot-20250101  2d      nextcloud-config   true
nextcloud-apps-snapshot-20250101    2d      nextcloud-apps     true
```

---

## Recovery Procedures

### Files Recovery

#### Full Files Restore

Restore complete user data:

```bash
# 1. Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# 2. Restore files
kubectl cp ./backups/nextcloud-data-20250101.tar.gz default/nextcloud-pod:/tmp/
kubectl exec -n default deployment/nextcloud -- \
  tar xzf /tmp/nextcloud-data-20250101.tar.gz -C /var/www/html/data

# 3. Fix permissions
kubectl exec -n default deployment/nextcloud -- chown -R www-data:www-data /var/www/html/data

# 4. Rescan files
kubectl exec -n default deployment/nextcloud -- php occ files:scan --all

# 5. Disable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off
```

#### Incremental Files Restore

Restore from incremental backup:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-restore-data-incremental BACKUP_DATE=20250101

# Manual method
kubectl exec -n default deployment/nextcloud -- \
  rsync -av /backup/nextcloud-data-incremental/ /var/www/html/data/
```

#### Individual User Restore

Restore specific user's files:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-restore-user USER=admin BACKUP_FILE=user-admin-20250101.tar.gz

# Manual method
kubectl cp ./backups/user-admin-20250101.tar.gz default/nextcloud-pod:/tmp/
kubectl exec -n default deployment/nextcloud -- \
  tar xzf /tmp/user-admin-20250101.tar.gz -C /var/www/html/data
kubectl exec -n default deployment/nextcloud -- chown -R www-data:www-data /var/www/html/data/admin
kubectl exec -n default deployment/nextcloud -- php occ files:scan --path=/admin/files
```

---

### Database Recovery

#### Full Database Restore

Restore complete PostgreSQL database:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-restore-database BACKUP_FILE=nextcloud-db-20250101.dump

# Manual method
# 1. Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# 2. Drop existing database (DESTRUCTIVE!)
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "DROP DATABASE nextcloud;"

# 3. Recreate database
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "CREATE DATABASE nextcloud OWNER nextcloud;"

# 4. Restore from backup
kubectl cp ./backups/nextcloud-db-20250101.dump default/postgresql-pod:/tmp/
kubectl exec -n default deployment/postgresql -- \
  pg_restore -U nextcloud -d nextcloud /tmp/nextcloud-db-20250101.dump

# 5. Disable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off
```

#### Point-in-Time Recovery (PITR)

Restore database to specific timestamp (requires WAL archiving):

```bash
# 1. Stop Nextcloud
kubectl scale deployment/nextcloud --replicas=0

# 2. Restore base backup
kubectl exec -n default deployment/postgresql -- \
  pg_restore -U nextcloud -d nextcloud /backups/base-backup.dump

# 3. Configure recovery
kubectl exec -n default deployment/postgresql -- bash -c "cat > /var/lib/postgresql/data/recovery.conf <<EOF
restore_command = 'wal-g wal-fetch %f %p'
recovery_target_time = '2025-01-01 12:00:00'
EOF"

# 4. Restart PostgreSQL to apply recovery
kubectl rollout restart statefulset/postgresql

# 5. Restart Nextcloud
kubectl scale deployment/nextcloud --replicas=1
```

---

### Configuration Recovery

#### Restore config.php

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-restore-config BACKUP_FILE=config-20250101.php

# Manual method
# 1. Decrypt if encrypted
openssl enc -aes-256-cbc -d -in config.php.enc -out config.php

# 2. Copy to pod
kubectl cp ./backups/config-20250101.php default/nextcloud-pod:/var/www/html/config/config.php

# 3. Fix permissions
kubectl exec -n default deployment/nextcloud -- chown www-data:www-data /var/www/html/config/config.php

# 4. Restart Nextcloud
kubectl rollout restart deployment/nextcloud
```

#### Restore Custom Apps

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-restore-apps BACKUP_FILE=nextcloud-apps-20250101.tar.gz

# Manual method
kubectl cp ./backups/nextcloud-apps-20250101.tar.gz default/nextcloud-pod:/tmp/
kubectl exec -n default deployment/nextcloud -- \
  tar xzf /tmp/nextcloud-apps-20250101.tar.gz -C /var/www/html
kubectl exec -n default deployment/nextcloud -- chown -R www-data:www-data /var/www/html/custom_apps
kubectl exec -n default deployment/nextcloud -- php occ app:list
```

---

### Full Disaster Recovery

Complete Nextcloud instance recovery from backups.

#### Step-by-Step DR Procedure

**Prerequisites:**
- VolumeSnapshots available
- Database backups accessible
- Config backups accessible

**Recovery Steps:**

```bash
# 1. Create new PVCs from snapshots
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data-restored
  namespace: default
spec:
  dataSource:
    name: nextcloud-data-snapshot-20250101
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-config-restored
  namespace: default
spec:
  dataSource:
    name: nextcloud-config-snapshot-20250101
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-apps-restored
  namespace: default
spec:
  dataSource:
    name: nextcloud-apps-snapshot-20250101
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 2. Restore PostgreSQL database
make -f make/ops/nextcloud.mk nc-restore-database BACKUP_FILE=nextcloud-db-20250101.dump

# 3. Deploy Nextcloud with restored PVCs
helm upgrade --install nextcloud ./charts/nextcloud \
  --set persistence.data.existingClaim=nextcloud-data-restored \
  --set persistence.config.existingClaim=nextcloud-config-restored \
  --set persistence.apps.existingClaim=nextcloud-apps-restored \
  -f values-production.yaml

# 4. Wait for deployment
kubectl rollout status deployment/nextcloud

# 5. Verify Nextcloud status
kubectl exec -n default deployment/nextcloud -- php occ status

# 6. Run integrity check
kubectl exec -n default deployment/nextcloud -- php occ integrity:check-core

# 7. Rescan files
kubectl exec -n default deployment/nextcloud -- php occ files:scan --all
```

**Expected output:**
```
Nextcloud or one of the apps require upgrade - only a limited number of commands are available
You may use your browser or the occ upgrade command to do the upgrade
  - installed: true
  - version: 31.0.10
  - versionstring: 31.0.10
  - edition:
  - maintenance: false
  - needsDbUpgrade: false
  - productname: Nextcloud
  - extendedSupport: false
```

#### DR Testing

Test disaster recovery procedure quarterly:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-dr-test

# Manual steps:
# 1. Create test namespace
kubectl create namespace nextcloud-dr-test

# 2. Restore to test namespace
# (repeat DR steps above in test namespace)

# 3. Verify functionality
kubectl exec -n nextcloud-dr-test deployment/nextcloud -- php occ status

# 4. Cleanup test environment
kubectl delete namespace nextcloud-dr-test
```

---

## Backup Automation

### CronJob for Daily Backups

**Note:** The chart does not include automated backup CronJobs. Use Makefile targets via external schedulers.

Example external cron configuration:

```bash
# /etc/cron.d/nextcloud-backup
# Daily backups at 2 AM
0 2 * * * root cd /path/to/charts && make -f make/ops/nextcloud.mk nc-backup-all

# Weekly PVC snapshots on Sunday at 3 AM
0 3 * * 0 root cd /path/to/charts && make -f make/ops/nextcloud.mk nc-snapshot-all
```

### Backup Retention Policy

Recommended retention:
- **Daily backups**: Keep 7 days
- **Weekly backups**: Keep 4 weeks
- **Monthly backups**: Keep 12 months
- **Snapshots**: Keep last 4 weekly

**Cleanup old backups:**

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-cleanup-old-backups RETENTION_DAYS=7

# Manual method
find ./backups -name "nextcloud-*" -type f -mtime +7 -delete
```

### Backup Verification

Automated backup verification:

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-verify-backups

# Manual verification steps:
# 1. Check backup files exist
# 2. Verify file integrity (checksums)
# 3. Test restore to temporary location
# 4. Validate restored data
```

---

## Best Practices

### General Recommendations

1. **Test Restores Regularly**
   - Quarterly DR testing in test namespace
   - Verify backup integrity monthly
   - Document restore procedures

2. **Off-Site Backups**
   - Store backups in different availability zone
   - Use S3/MinIO for long-term retention
   - Encrypt sensitive backups

3. **Backup Before Changes**
   - Always backup before Nextcloud upgrades
   - Backup before major configuration changes
   - Backup before custom app installations

4. **Monitor Backup Jobs**
   - Alert on backup failures
   - Track backup sizes over time
   - Verify backup completion

5. **Document Backup Locations**
   - Maintain backup inventory
   - Document encryption keys
   - Keep recovery procedures accessible

### Security Considerations

1. **Encrypt Backups**
   ```bash
   # Encrypt backup
   openssl enc -aes-256-cbc -salt -in backup.tar.gz -out backup.tar.gz.enc

   # Decrypt backup
   openssl enc -aes-256-cbc -d -in backup.tar.gz.enc -out backup.tar.gz
   ```

2. **Secure Backup Storage**
   - Use IAM roles for S3 access
   - Restrict backup directory permissions
   - Audit backup access logs

3. **Credentials Management**
   - Never commit backup scripts with credentials
   - Use Kubernetes Secrets for backup jobs
   - Rotate backup encryption keys regularly

---

## Troubleshooting

### Common Backup Issues

#### Issue: Backup Fails with "Disk Space Full"

**Solution:**
```bash
# Check available space
kubectl exec -n default deployment/nextcloud -- df -h

# Clean up old files
kubectl exec -n default deployment/nextcloud -- php occ trashbin:cleanup --all-users
kubectl exec -n default deployment/nextcloud -- php occ versions:cleanup
```

#### Issue: Database Backup Timeout

**Solution:**
```bash
# Use directory format for parallel dump
pg_dump -U nextcloud -d nextcloud -Fd -j 4 -f /backup/nextcloud-db-dir/

# Or compress with lower level
pg_dump -U nextcloud -d nextcloud -Fc -Z1 -f /backup/nextcloud-db.dump
```

#### Issue: Files Missing After Restore

**Solution:**
```bash
# Rescan all files
kubectl exec -n default deployment/nextcloud -- php occ files:scan --all

# Check file cache
kubectl exec -n default deployment/nextcloud -- php occ files:cleanup

# Repair file cache
kubectl exec -n default deployment/nextcloud -- php occ maintenance:repair
```

### Common Recovery Issues

#### Issue: Database Restore Fails with "Role Does Not Exist"

**Solution:**
```bash
# Create missing role
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "CREATE ROLE nextcloud WITH LOGIN PASSWORD 'password';"

# Grant permissions
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "ALTER DATABASE nextcloud OWNER TO nextcloud;"
```

#### Issue: Nextcloud Shows "Database Needs Upgrade"

**Solution:**
```bash
# Run database upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade

# Verify upgrade
kubectl exec -n default deployment/nextcloud -- php occ status
```

#### Issue: Config Restore Breaks Nextcloud

**Solution:**
```bash
# Check config syntax
kubectl exec -n default deployment/nextcloud -- php -l /var/www/html/config/config.php

# Restore default config template
kubectl exec -n default deployment/nextcloud -- \
  cp /var/www/html/config/config.sample.php /var/www/html/config/config.php

# Manually configure essential settings
```

---

## Backup Checklist

Use this checklist for regular backup operations:

### Daily Backups
- [ ] Backup PostgreSQL database (`nc-backup-database`)
- [ ] Backup user files (`nc-backup-data` or `nc-backup-data-incremental`)
- [ ] Verify backup integrity
- [ ] Check backup logs for errors

### Weekly Backups
- [ ] Create PVC snapshots (`nc-snapshot-all`)
- [ ] Full files backup (baseline)
- [ ] Backup custom apps (`nc-backup-apps`)
- [ ] Test restore one random file

### Monthly Backups
- [ ] Off-site backup transfer
- [ ] Cleanup old backups (retention policy)
- [ ] DR test in test namespace
- [ ] Update backup documentation

### Quarterly Reviews
- [ ] Full DR simulation
- [ ] Review backup retention policy
- [ ] Update recovery procedures
- [ ] Security audit of backups

---

**Last Updated**: 2025-12-08
**Chart Version**: 0.3.0
**Nextcloud Version**: 31.0.10
