# Nextcloud Upgrade Guide

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [Strategy 1: Rolling Upgrade (Recommended)](#strategy-1-rolling-upgrade-recommended)
  - [Strategy 2: In-Place Upgrade with Maintenance Mode](#strategy-2-in-place-upgrade-with-maintenance-mode)
  - [Strategy 3: Blue-Green Deployment](#strategy-3-blue-green-deployment)
  - [Strategy 4: Database Migration Upgrade](#strategy-4-database-migration-upgrade)
- [Version-Specific Upgrade Notes](#version-specific-upgrade-notes)
  - [Nextcloud 30.x → 31.x](#nextcloud-30x--31x)
  - [Nextcloud 29.x → 30.x](#nextcloud-29x--30x)
  - [Nextcloud 28.x → 29.x](#nextcloud-28x--29x)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for upgrading Nextcloud instances deployed via the Helm chart.

**Upgrade Philosophy:**
- **Minimize downtime**: Use rolling upgrades when possible
- **Version compatibility**: Never skip major versions (upgrade sequentially)
- **App compatibility**: Verify app compatibility before upgrading
- **Database migration**: Nextcloud automatically migrates database schema via occ
- **Backup first**: Always backup before upgrading (CRITICAL)

**Upgrade Complexity Matrix:**

| Upgrade Type | Complexity | Downtime | Risk | Recommended Strategy |
|--------------|------------|----------|------|----------------------|
| Patch (31.0.0 → 31.0.10) | Low | None | Low | Rolling Upgrade |
| Minor (31.0.x → 31.1.x) | Medium | Minimal | Low-Medium | Rolling Upgrade |
| Major (30.x → 31.x) | High | Optional | Medium-High | In-Place or Blue-Green |
| Multi-Major (29.x → 31.x) | Very High | Required | High | Sequential Upgrades |

**Important Version Compatibility Notes:**
- Nextcloud database schema is automatically migrated via `occ upgrade` (forward compatible only)
- Apps may not be compatible across major versions
- Breaking changes in major versions require configuration updates
- Downgrading requires database restore (schema downgrades not supported)
- **NEVER skip major versions** (e.g., 29.x → 31.x requires 29.x → 30.x → 31.x)

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**CRITICAL:** Always review Nextcloud release notes before upgrading.

```bash
# Check current Nextcloud version
kubectl exec -n default deployment/nextcloud -- php occ status

# Review release notes for target version
# Visit: https://nextcloud.com/changelog/
# Check for:
# - Breaking changes
# - Deprecated features
# - App compatibility
# - Database migration notes
# - PHP version requirements
# - Database version requirements
```

**Key areas to review:**
- PHP version compatibility (Nextcloud 31 requires PHP 8.2+)
- PostgreSQL version compatibility (Nextcloud 31 requires PostgreSQL 13+)
- Redis version compatibility (Nextcloud 31 requires Redis 6+)
- App compatibility (verify all installed apps support new version)
- Breaking changes in core APIs
- Configuration file changes (config.php)

### 2. Backup Everything

**MANDATORY:** Create comprehensive backups before any upgrade.

```bash
# Using Makefile (recommended - comprehensive backup)
make -f make/ops/nextcloud.mk nc-pre-upgrade-check
make -f make/ops/nextcloud.mk nc-full-backup

# Manual backup steps:
# 1. Backup database
make -f make/ops/nextcloud.mk nc-backup-database

# 2. Backup files
make -f make/ops/nextcloud.mk nc-backup-data

# 3. Backup configuration
make -f make/ops/nextcloud.mk nc-backup-config

# 4. Backup custom apps
make -f make/ops/nextcloud.mk nc-backup-apps

# 5. Create PVC snapshots
make -f make/ops/nextcloud.mk nc-snapshot-all
```

**Backup verification:**
```bash
# Verify all backup files exist
ls -lh backups/nextcloud-*

# Verify backup integrity
make -f make/ops/nextcloud.mk nc-verify-backups
```

### 3. Check System Requirements

Verify that your system meets the requirements for the target Nextcloud version.

```bash
# Check PHP version
kubectl exec -n default deployment/nextcloud -- php -v

# Check PostgreSQL version
kubectl exec -n default deployment/postgresql -- psql --version

# Check Redis version
kubectl exec -n default deployment/redis -- redis-server --version

# Check disk space
kubectl exec -n default deployment/nextcloud -- df -h

# Check memory
kubectl top pod -n default -l app.kubernetes.io/name=nextcloud
```

**Nextcloud 31.x Requirements:**
- PHP: 8.2, 8.3, or 8.4
- PostgreSQL: 13, 14, 15, or 16
- Redis: 6.x or 8.x
- Disk space: At least 2x current usage (for database migration)
- Memory: Minimum 512MB, recommended 1GB+

### 4. Check App Compatibility

Verify installed apps are compatible with target version.

```bash
# List all installed apps
kubectl exec -n default deployment/nextcloud -- php occ app:list

# Check app compatibility
# Visit Nextcloud App Store: https://apps.nextcloud.com/
# Search for each app and verify version compatibility

# Disable incompatible apps before upgrade
kubectl exec -n default deployment/nextcloud -- php occ app:disable <app-name>
```

**Critical apps to verify:**
- Files (core app, always compatible)
- Activity (core app)
- Calendar
- Contacts
- Files_external
- Photos
- All custom/third-party apps

### 5. Review Current Configuration

```bash
# Export current configuration
kubectl exec -n default deployment/nextcloud -- cat /var/www/html/config/config.php > backups/config-pre-upgrade.php

# Check for deprecated settings
# Review Nextcloud documentation for deprecated config options

# Verify trusted_domains
kubectl exec -n default deployment/nextcloud -- php occ config:system:get trusted_domains
```

### 6. Check Database Health

```bash
# Check database integrity
kubectl exec -n default deployment/nextcloud -- php occ db:convert-filecache-bigint --no-interaction

# Check for missing indices
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-indices

# Check for missing columns
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-columns

# Check for missing primary keys
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-primary-keys
```

### 7. Enable Maintenance Mode (for non-rolling upgrades)

```bash
# Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# Verify maintenance mode is active
kubectl exec -n default deployment/nextcloud -- php occ status
```

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Recommended)

**Best for:** Patch and minor version upgrades (e.g., 31.0.0 → 31.0.10 or 31.0.x → 31.1.x)

**Advantages:**
- Zero downtime
- Automatic rollback on failure
- No manual intervention required

**Disadvantages:**
- Only suitable for patch/minor versions
- Not recommended for major version upgrades

**Downtime:** None

**Complexity:** Low

#### Procedure

```bash
# 1. Pre-upgrade backup
make -f make/ops/nextcloud.mk nc-pre-upgrade-check
make -f make/ops/nextcloud.mk nc-full-backup

# 2. Update Helm chart values
cat > values-upgrade.yaml <<EOF
image:
  tag: "31.0.10-apache"  # New version

# Keep all other values the same
EOF

# 3. Perform rolling upgrade
helm upgrade nextcloud ./charts/nextcloud \
  -f values-production.yaml \
  -f values-upgrade.yaml \
  --wait \
  --timeout=10m

# 4. Monitor rollout
kubectl rollout status deployment/nextcloud

# 5. Verify Nextcloud is running
kubectl exec -n default deployment/nextcloud -- php occ status

# 6. Run database migrations (if needed)
kubectl exec -n default deployment/nextcloud -- php occ upgrade

# 7. Post-upgrade validation
make -f make/ops/nextcloud.mk nc-post-upgrade-check
```

**Expected output:**
```
deployment "nextcloud" successfully rolled out
Nextcloud is in maintenance mode, skipping
Running database migrations...
Database migrations completed successfully
Nextcloud version: 31.0.10
Database version: 31.0.10
```

---

### Strategy 2: In-Place Upgrade with Maintenance Mode

**Best for:** Major version upgrades (e.g., 30.x → 31.x) with minimal downtime tolerance

**Advantages:**
- Controlled upgrade process
- Clear rollback point
- Database migration visibility

**Disadvantages:**
- Requires downtime (typically 10-30 minutes)
- Manual intervention required

**Downtime:** 10-30 minutes (depends on database size)

**Complexity:** Medium

#### Procedure

```bash
# 1. Pre-upgrade backup
make -f make/ops/nextcloud.mk nc-pre-upgrade-check
make -f make/ops/nextcloud.mk nc-full-backup

# 2. Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# 3. Verify no users are connected
kubectl exec -n default deployment/nextcloud -- php occ user:list

# 4. Update image tag in values
cat > values-upgrade.yaml <<EOF
image:
  tag: "31.0.0-apache"  # New major version
EOF

# 5. Upgrade Helm release
helm upgrade nextcloud ./charts/nextcloud \
  -f values-production.yaml \
  -f values-upgrade.yaml \
  --wait \
  --timeout=10m

# 6. Wait for new pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nextcloud --timeout=5m

# 7. Run database upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade --no-interaction

# 8. Run post-upgrade tasks
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-indices
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-columns
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-primary-keys

# 9. Update app versions
kubectl exec -n default deployment/nextcloud -- php occ app:update --all

# 10. Disable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off

# 11. Post-upgrade validation
make -f make/ops/nextcloud.mk nc-post-upgrade-check
```

**Expected output:**
```
Nextcloud is in maintenance mode
Updating database schema
Updated database
Nextcloud is updated to version 31.0.0
Maintenance mode disabled
```

---

### Strategy 3: Blue-Green Deployment

**Best for:** Major version upgrades with zero downtime requirement

**Advantages:**
- Zero downtime
- Easy rollback (switch ingress back)
- Full testing before cutover

**Disadvantages:**
- Requires double resources
- Complex setup
- Database synchronization needed

**Downtime:** None (brief DNS/Ingress switch)

**Complexity:** High

#### Procedure

```bash
# 1. Pre-upgrade backup
make -f make/ops/nextcloud.mk nc-full-backup

# 2. Create new namespace for green environment
kubectl create namespace nextcloud-green

# 3. Clone database to new instance
# Option A: Database replication (recommended)
kubectl exec -n default deployment/postgresql -- \
  pg_dump -U nextcloud -d nextcloud -Fc -f /tmp/nextcloud-green.dump
kubectl cp default/postgresql-pod:/tmp/nextcloud-green.dump ./nextcloud-green.dump
kubectl cp ./nextcloud-green.dump nextcloud-green/postgresql-pod:/tmp/nextcloud-green.dump
kubectl exec -n nextcloud-green deployment/postgresql -- \
  createdb -U postgres nextcloud_green
kubectl exec -n nextcloud-green deployment/postgresql -- \
  pg_restore -U postgres -d nextcloud_green /tmp/nextcloud-green.dump

# 4. Create new PVCs from snapshots
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data-green
  namespace: nextcloud-green
spec:
  dataSource:
    name: nextcloud-data-snapshot-latest
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
  name: nextcloud-config-green
  namespace: nextcloud-green
spec:
  dataSource:
    name: nextcloud-config-snapshot-latest
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
  name: nextcloud-apps-green
  namespace: nextcloud-green
spec:
  dataSource:
    name: nextcloud-apps-snapshot-latest
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 5. Deploy new version in green environment
helm install nextcloud-green ./charts/nextcloud \
  --namespace nextcloud-green \
  -f values-production.yaml \
  --set image.tag="31.0.0-apache" \
  --set persistence.data.existingClaim=nextcloud-data-green \
  --set persistence.config.existingClaim=nextcloud-config-green \
  --set persistence.apps.existingClaim=nextcloud-apps-green \
  --set postgresql.external.database=nextcloud_green \
  --wait \
  --timeout=10m

# 6. Run database upgrade in green
kubectl exec -n nextcloud-green deployment/nextcloud -- php occ upgrade --no-interaction

# 7. Validate green environment
kubectl exec -n nextcloud-green deployment/nextcloud -- php occ status
kubectl exec -n nextcloud-green deployment/nextcloud -- php occ integrity:check-core

# 8. Test green environment
# Access green environment via port-forward or temporary ingress
kubectl port-forward -n nextcloud-green svc/nextcloud 8080:80

# 9. Switch Ingress to green (cutover)
kubectl patch ingress nextcloud -n default -p '{
  "spec": {
    "rules": [{
      "host": "nextcloud.example.com",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "Prefix",
          "backend": {
            "service": {
              "name": "nextcloud",
              "port": {"number": 80}
            }
          }
        }]
      }
    }]
  }
}'

# Replace with green service
kubectl patch ingress nextcloud -n default -p '{
  "spec": {
    "rules": [{
      "host": "nextcloud.example.com",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "Prefix",
          "backend": {
            "service": {
              "name": "nextcloud-green",
              "port": {"number": 80}
            }
          }
        }]
      }
    }]
  }
}'

# 10. Monitor green environment
kubectl logs -n nextcloud-green -l app.kubernetes.io/name=nextcloud --tail=100 -f

# 11. After validation, clean up blue environment
# (Keep blue environment for rollback window, e.g., 24-48 hours)
kubectl delete namespace nextcloud-blue
```

**Rollback (if needed):**
```bash
# Switch Ingress back to blue environment
kubectl patch ingress nextcloud -n default --type=json -p='[{
  "op": "replace",
  "path": "/spec/rules/0/http/paths/0/backend/service/name",
  "value": "nextcloud"
}]'
```

---

### Strategy 4: Database Migration Upgrade

**Best for:** Multi-major version upgrades (e.g., 29.x → 31.x) or database backend changes

**Advantages:**
- Clean database state
- Opportunity to optimize database
- Fresh start for major changes

**Disadvantages:**
- Extended downtime (hours)
- Complex procedure
- High risk

**Downtime:** 2-6 hours (depends on data volume)

**Complexity:** Very High

#### Procedure

```bash
# 1. CRITICAL: Full backup
make -f make/ops/nextcloud.mk nc-full-backup
make -f make/ops/nextcloud.mk nc-snapshot-all

# 2. Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# 3. Export all data via occ
# Export user files (already backed up via nc-backup-data)
# Export database
make -f make/ops/nextcloud.mk nc-backup-database

# 4. Scale down current deployment
kubectl scale deployment/nextcloud --replicas=0

# 5. Create new database
kubectl exec -n default deployment/postgresql -- \
  createdb -U postgres nextcloud_v31

# 6. Deploy new Nextcloud version
cat > values-migration.yaml <<EOF
image:
  tag: "31.0.0-apache"

postgresql:
  external:
    database: "nextcloud_v31"
EOF

helm upgrade nextcloud ./charts/nextcloud \
  -f values-production.yaml \
  -f values-migration.yaml \
  --wait

# 7. Initialize new Nextcloud instance
kubectl exec -n default deployment/nextcloud -- \
  php occ maintenance:install \
    --database pgsql \
    --database-name nextcloud_v31 \
    --database-host postgresql-service \
    --database-user nextcloud \
    --database-pass "password" \
    --admin-user admin \
    --admin-pass "admin-password"

# 8. Restore configuration
kubectl cp backups/config-pre-upgrade.php default/nextcloud-pod:/var/www/html/config/config.php

# 9. Import database from backup
kubectl cp backups/nextcloud-db-latest.dump default/postgresql-pod:/tmp/
kubectl exec -n default deployment/postgresql -- \
  pg_restore -U nextcloud -d nextcloud_v31 --clean --if-exists /tmp/nextcloud-db-latest.dump

# 10. Run upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade --no-interaction

# 11. Rescan files
kubectl exec -n default deployment/nextcloud -- php occ files:scan --all

# 12. Update apps
kubectl exec -n default deployment/nextcloud -- php occ app:update --all

# 13. Disable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off

# 14. Validate
make -f make/ops/nextcloud.mk nc-post-upgrade-check
```

---

## Version-Specific Upgrade Notes

### Nextcloud 30.x → 31.x

**Release Date:** December 2024

**Key Changes:**
- PHP 8.2+ required (PHP 8.1 no longer supported)
- PostgreSQL 13+ required (PostgreSQL 12 no longer supported)
- New dashboard widgets framework
- Enhanced Files app with AI features
- Improved performance for large file operations

**Breaking Changes:**
- `oc_jobs` table schema changed (automatic migration)
- Removed deprecated `oc_addressbookchanges` table
- Changed default file locking mechanism (Redis recommended)

**Migration Steps:**
```bash
# 1. Verify PHP version
kubectl exec -n default deployment/nextcloud -- php -v | grep "PHP 8"

# 2. Verify PostgreSQL version
kubectl exec -n default deployment/postgresql -- psql --version | grep -E "13|14|15|16"

# 3. Update Redis configuration (if not already using Redis)
# Edit values.yaml to enable Redis external connection

# 4. Run pre-upgrade database checks
kubectl exec -n default deployment/nextcloud -- php occ db:convert-filecache-bigint --no-interaction
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-indices
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-columns

# 5. Proceed with upgrade (use Strategy 2 or 3)
```

**Apps to verify:**
- Calendar: v4.8.0+ required
- Contacts: v6.2.0+ required
- Files_external: v1.22.0+ required
- Photos: v3.1.0+ required

---

### Nextcloud 29.x → 30.x

**Release Date:** July 2024

**Key Changes:**
- PHP 8.1+ required
- Enhanced Activity app
- Improved search performance
- New Whiteboard app integration

**Breaking Changes:**
- `oc_notifications` table schema changed
- Deprecated `oc_files_trash` cleanup behavior

**Migration Steps:**
```bash
# 1. Backup and verify
make -f make/ops/nextcloud.mk nc-full-backup

# 2. Update apps before upgrade
kubectl exec -n default deployment/nextcloud -- php occ app:update calendar
kubectl exec -n default deployment/nextcloud -- php occ app:update contacts

# 3. Proceed with upgrade
```

---

### Nextcloud 28.x → 29.x

**Release Date:** April 2024

**Key Changes:**
- PHP 8.0+ required
- New Photos app features
- Enhanced collaboration features

**Breaking Changes:**
- `oc_share_external` table removed (migrate to federated shares)

**Migration Steps:**
```bash
# 1. Migrate external shares
kubectl exec -n default deployment/nextcloud -- php occ sharing:migrate-external-shares

# 2. Proceed with upgrade
```

---

## Post-Upgrade Validation

### 1. Verify Nextcloud Status

```bash
# Using Makefile
make -f make/ops/nextcloud.mk nc-post-upgrade-check

# Manual checks
kubectl exec -n default deployment/nextcloud -- php occ status
kubectl exec -n default deployment/nextcloud -- php occ integrity:check-core
```

**Expected output:**
```
  - installed: true
  - version: 31.0.0
  - versionstring: 31.0.0
  - edition:
  - maintenance: false
  - needsDbUpgrade: false
  - productname: Nextcloud
  - extendedSupport: false
```

### 2. Check Database Integrity

```bash
# Check for database issues
kubectl exec -n default deployment/nextcloud -- php occ db:convert-filecache-bigint --no-interaction
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-indices
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-columns
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-primary-keys
```

### 3. Verify Apps

```bash
# List all apps
kubectl exec -n default deployment/nextcloud -- php occ app:list

# Update all apps
kubectl exec -n default deployment/nextcloud -- php occ app:update --all
```

### 4. Rescan Files

```bash
# Rescan all user files
kubectl exec -n default deployment/nextcloud -- php occ files:scan --all
```

**Expected output:**
```
Starting scan for user 1 out of 10 (admin)
...
Scanned 1234 files in 56 seconds
```

### 5. Test Functionality

```bash
# Test web UI
curl -I https://nextcloud.example.com/

# Test login
curl -u admin:password https://nextcloud.example.com/ocs/v1.php/cloud/capabilities

# Test file upload (via WebDAV)
curl -X PUT -u admin:password \
  --data-binary @test-file.txt \
  https://nextcloud.example.com/remote.php/dav/files/admin/test-file.txt
```

### 6. Check Background Jobs

```bash
# List background jobs
kubectl exec -n default deployment/nextcloud -- php occ background:queue:status

# Execute background jobs manually (one-time)
kubectl exec -n default deployment/nextcloud -- php occ background:job:execute
```

### 7. Monitor Logs

```bash
# Check Nextcloud logs
kubectl exec -n default deployment/nextcloud -- tail -f /var/www/html/data/nextcloud.log

# Check pod logs
kubectl logs -n default -l app.kubernetes.io/name=nextcloud --tail=100 -f
```

---

## Rollback Procedures

### Rollback Decision Tree

```
Is upgrade causing critical issues?
├── YES → Immediate rollback required
│   ├── Was database migrated?
│   │   ├── YES → Full database restore required (Strategy A)
│   │   └── NO → Simple image rollback (Strategy B)
│   └── ...
└── NO → Continue with post-upgrade fixes
```

### Strategy A: Full Database Restore (Major Version Rollback)

**Use when:** Database schema was migrated and is incompatible with previous version

**Downtime:** 30-60 minutes

```bash
# 1. Enable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --on

# 2. Scale down Nextcloud
kubectl scale deployment/nextcloud --replicas=0

# 3. Drop current database
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "DROP DATABASE nextcloud;"

# 4. Recreate database
kubectl exec -n default deployment/postgresql -- \
  psql -U postgres -c "CREATE DATABASE nextcloud OWNER nextcloud;"

# 5. Restore from pre-upgrade backup
kubectl cp backups/nextcloud-db-pre-upgrade.dump default/postgresql-pod:/tmp/
kubectl exec -n default deployment/postgresql -- \
  pg_restore -U nextcloud -d nextcloud /tmp/nextcloud-db-pre-upgrade.dump

# 6. Rollback image version
helm upgrade nextcloud ./charts/nextcloud \
  -f values-production.yaml \
  --set image.tag="30.0.10-apache" \
  --wait

# 7. Restore config if needed
kubectl cp backups/config-pre-upgrade.php default/nextcloud-pod:/var/www/html/config/config.php

# 8. Scale up Nextcloud
kubectl scale deployment/nextcloud --replicas=1

# 9. Disable maintenance mode
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off

# 10. Verify rollback
kubectl exec -n default deployment/nextcloud -- php occ status
```

### Strategy B: Simple Image Rollback (Patch/Minor Rollback)

**Use when:** Only image was upgraded, database not migrated

**Downtime:** 2-5 minutes

```bash
# 1. Rollback Helm release
helm rollback nextcloud

# 2. Wait for rollout
kubectl rollout status deployment/nextcloud

# 3. Verify version
kubectl exec -n default deployment/nextcloud -- php occ status
```

### Strategy C: Blue-Green Rollback

**Use when:** Blue-green deployment was used

**Downtime:** None

```bash
# Switch Ingress back to blue environment
kubectl patch ingress nextcloud -n default --type=json -p='[{
  "op": "replace",
  "path": "/spec/rules/0/http/paths/0/backend/service/name",
  "value": "nextcloud"
}]'
```

---

## Troubleshooting

### Common Upgrade Issues

#### Issue: Database Migration Fails

**Symptoms:**
```
Error while running database migrations
SQLSTATE[42S01]: Base table or view already exists
```

**Solution:**
```bash
# 1. Check database status
kubectl exec -n default deployment/nextcloud -- php occ status

# 2. Manually run specific migration
kubectl exec -n default deployment/nextcloud -- php occ migrations:status
kubectl exec -n default deployment/nextcloud -- php occ migrations:execute <version> --no-interaction

# 3. Force complete upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade --skip-migration-test
```

#### Issue: Apps Not Compatible

**Symptoms:**
```
App "calendar" is not compatible with this version of Nextcloud
```

**Solution:**
```bash
# 1. List incompatible apps
kubectl exec -n default deployment/nextcloud -- php occ app:list | grep -A 100 "Disabled"

# 2. Disable incompatible apps
kubectl exec -n default deployment/nextcloud -- php occ app:disable calendar

# 3. Complete upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade

# 4. Update apps
kubectl exec -n default deployment/nextcloud -- php occ app:update --all

# 5. Re-enable apps
kubectl exec -n default deployment/nextcloud -- php occ app:enable calendar
```

#### Issue: Maintenance Mode Stuck

**Symptoms:**
```
Nextcloud is in maintenance mode
```

**Solution:**
```bash
# Disable maintenance mode manually
kubectl exec -n default deployment/nextcloud -- php occ maintenance:mode --off

# If that fails, edit config.php
kubectl exec -n default deployment/nextcloud -- sed -i "s/'maintenance' => true/'maintenance' => false/" /var/www/html/config/config.php
kubectl rollout restart deployment/nextcloud
```

#### Issue: File Integrity Check Fails

**Symptoms:**
```
Technical error occurred during integrity check
```

**Solution:**
```bash
# Disable integrity check temporarily
kubectl exec -n default deployment/nextcloud -- \
  php occ config:system:set integrity.check.disabled --value true --type boolean

# Complete upgrade
kubectl exec -n default deployment/nextcloud -- php occ upgrade

# Re-enable integrity check
kubectl exec -n default deployment/nextcloud -- \
  php occ config:system:set integrity.check.disabled --value false --type boolean

# Verify integrity
kubectl exec -n default deployment/nextcloud -- php occ integrity:check-core
```

#### Issue: Performance Degradation After Upgrade

**Symptoms:**
- Slow page loads
- High database CPU usage
- Timeout errors

**Solution:**
```bash
# 1. Rebuild indices
kubectl exec -n default deployment/nextcloud -- php occ db:add-missing-indices

# 2. Optimize database
kubectl exec -n default deployment/postgresql -- \
  psql -U nextcloud -d nextcloud -c "VACUUM FULL ANALYZE;"

# 3. Clear Redis cache
kubectl exec -n default deployment/redis -- redis-cli FLUSHALL

# 4. Clear Nextcloud cache
kubectl exec -n default deployment/nextcloud -- php occ files:cleanup
kubectl exec -n default deployment/nextcloud -- php occ config:list | grep memcache

# 5. Restart Nextcloud
kubectl rollout restart deployment/nextcloud
```

#### Issue: "Trusted Domain" Error After Upgrade

**Symptoms:**
```
Access through untrusted domain
```

**Solution:**
```bash
# Add trusted domain
kubectl exec -n default deployment/nextcloud -- \
  php occ config:system:set trusted_domains 1 --value=nextcloud.example.com

# List all trusted domains
kubectl exec -n default deployment/nextcloud -- \
  php occ config:system:get trusted_domains
```

---

## Upgrade Checklist

Use this checklist for major version upgrades:

### Pre-Upgrade
- [ ] Review Nextcloud release notes
- [ ] Check PHP version compatibility
- [ ] Check PostgreSQL version compatibility
- [ ] Check Redis version compatibility
- [ ] Verify app compatibility
- [ ] Create full backup (`nc-full-backup`)
- [ ] Create PVC snapshots (`nc-snapshot-all`)
- [ ] Test backup restore in test environment
- [ ] Enable maintenance mode

### Upgrade
- [ ] Update Helm values with new image tag
- [ ] Run Helm upgrade
- [ ] Wait for pods to be ready
- [ ] Run database upgrade (`occ upgrade`)
- [ ] Add missing indices/columns/primary keys
- [ ] Update all apps

### Post-Upgrade
- [ ] Disable maintenance mode
- [ ] Verify Nextcloud status (`occ status`)
- [ ] Check integrity (`occ integrity:check-core`)
- [ ] Rescan files (`occ files:scan --all`)
- [ ] Test web UI access
- [ ] Test file upload/download
- [ ] Check background jobs
- [ ] Monitor logs for errors
- [ ] Update documentation

### Rollback (if needed)
- [ ] Identify rollback strategy
- [ ] Restore database from backup
- [ ] Rollback Helm release
- [ ] Restore configuration
- [ ] Verify rolled-back version
- [ ] Document issues encountered

---

**Last Updated**: 2025-12-08
**Chart Version**: 0.3.0
**Nextcloud Version**: 31.0.10
