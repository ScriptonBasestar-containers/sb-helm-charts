# Vaultwarden Upgrade Guide

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [Strategy 1: Rolling Upgrade (Recommended)](#strategy-1-rolling-upgrade-recommended)
  - [Strategy 2: In-Place Upgrade with Downtime](#strategy-2-in-place-upgrade-with-downtime)
  - [Strategy 3: Blue-Green Deployment](#strategy-3-blue-green-deployment)
- [Version-Specific Upgrade Notes](#version-specific-upgrade-notes)
  - [Vaultwarden 1.32.x → 1.34.x](#vaultwarden-132x--134x)
  - [Vaultwarden 1.30.x → 1.32.x](#vaultwarden-130x--132x)
  - [Database Backend Migration (SQLite → PostgreSQL)](#database-backend-migration-sqlite--postgresql)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for upgrading Vaultwarden instances deployed via the Helm chart.

**Upgrade Philosophy:**
- **Minimize downtime**: Use rolling upgrades for minor version updates
- **Database compatibility**: Vaultwarden automatically migrates database schema
- **Backward compatibility**: Vaultwarden maintains stable data format across versions
- **Backup first**: Always backup before upgrading (CRITICAL - vault data is irreplaceable)
- **Test in staging**: Test upgrades in non-production environment first

**Upgrade Complexity Matrix:**

| Upgrade Type | Complexity | Downtime | Risk | Recommended Strategy |
|--------------|------------|----------|------|----------------------|
| Patch (1.34.0 → 1.34.3) | Low | None | Low | Rolling Upgrade |
| Minor (1.34.x → 1.35.x) | Medium | None-Minimal | Low-Medium | Rolling Upgrade |
| Major (1.30.x → 1.34.x) | Medium-High | Optional | Medium | In-Place or Blue-Green |
| Backend Migration (SQLite → PostgreSQL) | Very High | Required | High | Database Migration |

**Important Version Compatibility Notes:**
- Vaultwarden database schema is automatically migrated on startup (forward compatible)
- Rolling back requires database restore (schema downgrades not supported)
- SQLite → PostgreSQL migration requires downtime and data export/import
- Docker image changes (e.g., Alpine Linux updates) may require PVC permission fixes
- Breaking changes are rare but always review release notes

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**CRITICAL:** Always review Vaultwarden release notes before upgrading.

```bash
# Check current Vaultwarden version
kubectl exec -n default deployment/vaultwarden -- /vaultwarden --version

# Review release notes for target version
# Visit: https://github.com/dani-garcia/vaultwarden/releases
# Check for:
# - Breaking changes
# - Database migration notes
# - Configuration changes
# - Docker image updates (base OS, dependencies)
# - Security advisories
```

**Key areas to review:**
- Database migration complexity
- Configuration environment variable changes
- Docker base image updates (Alpine Linux version)
- Rust dependencies updates (may affect build)
- API compatibility for clients (mobile apps, browser extensions)
- Known issues or regressions

### 2. Backup Everything

**CRITICAL:** Create full backups before upgrading.

```bash
# Full backup (includes data directory + database + config)
make -f make/ops/vaultwarden.mk vw-full-backup

# OR individual components:

# Backup data directory (SQLite mode or attachments)
make -f make/ops/vaultwarden.mk vw-backup-data-full

# Backup PostgreSQL database (PostgreSQL mode)
make -f make/ops/vaultwarden.mk vw-backup-postgres

# Backup MySQL database (MySQL mode)
make -f make/ops/vaultwarden.mk vw-backup-mysql

# Backup configuration
make -f make/ops/vaultwarden.mk vw-backup-config

# Create PVC snapshot (for quick rollback)
make -f make/ops/vaultwarden.mk vw-snapshot-data
```

**Verify backups:**
```bash
# List backup files
ls -lh /tmp/vaultwarden-backups/

# Verify SQLite backup integrity
sqlite3 /tmp/vaultwarden-backups/vaultwarden-sqlite-*.db "PRAGMA integrity_check;"

# Verify PostgreSQL backup
pg_restore --list /tmp/vaultwarden-backups/vaultwarden-pg-*.sql.gz | head -20
```

### 3. Check Database Health

**SQLite Mode:**
```bash
# Check database integrity
kubectl exec -n default deployment/vaultwarden -- \
  sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;"

# Check database size
kubectl exec -n default deployment/vaultwarden -- \
  du -sh /data/db.sqlite3

# Optimize database (reduces fragmentation)
kubectl exec -n default deployment/vaultwarden -- \
  sqlite3 /data/db.sqlite3 "VACUUM;"
```

**PostgreSQL Mode:**
```bash
# Check database connections
make -f make/ops/vaultwarden.mk vw-db-connections

# Check table sizes
make -f make/ops/vaultwarden.mk vw-db-table-sizes

# Vacuum and analyze
make -f make/ops/vaultwarden.mk vw-db-vacuum
```

### 4. Review Current Configuration

```bash
# Export current Helm values
helm get values vaultwarden -n default > /tmp/vaultwarden-values-backup.yaml

# Check current image version
kubectl get deployment vaultwarden -n default -o jsonpath='{.spec.template.spec.containers[0].image}'

# Review environment variables
kubectl exec -n default deployment/vaultwarden -- env | grep -v PASSWORD | sort
```

### 5. Test Backup Restore (Optional but Recommended)

**Test restore in separate namespace:**
```bash
# Create test namespace
kubectl create namespace vaultwarden-test

# Restore from backup to test namespace
helm install vaultwarden-test sb-charts/vaultwarden \
  -n vaultwarden-test \
  -f /tmp/vaultwarden-values-backup.yaml

# Restore data
make -f make/ops/vaultwarden.mk vw-restore-data \
  NAMESPACE=vaultwarden-test \
  BACKUP_FILE=/tmp/vaultwarden-backups/vaultwarden-data-*.tar.gz

# Test vault access
# - Open web vault
# - Login with test account
# - Verify password items
# - Test file attachments

# Cleanup test namespace
kubectl delete namespace vaultwarden-test
```

### 6. Plan Maintenance Window

**Recommended maintenance windows:**
- **Rolling upgrade**: No maintenance window required (zero downtime)
- **In-place upgrade**: 10-15 minutes (brief service interruption)
- **Blue-green deployment**: No maintenance window (instant cutover)
- **Database migration**: 1-2 hours (full downtime required)

**Communicate with users:**
- Notify users of planned upgrade
- Request users sync vaults before maintenance
- Provide estimated downtime window
- Share rollback plan and contact information

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Recommended)

**Best for:** Patch and minor version upgrades (1.34.0 → 1.34.3, 1.34.x → 1.35.x)

**Downtime:** None (zero-downtime upgrade)

**Risk Level:** Low

**Prerequisites:**
- Using Deployment workload type (PostgreSQL or MySQL backend)
- Multiple replicas configured (`replicaCount >= 2`)
- ReadWriteMany PVC or external storage for attachments (if using shared storage)

**Procedure:**

```bash
# 1. Pre-upgrade checks
make -f make/ops/vaultwarden.mk vw-pre-upgrade-check

# 2. Create backup
make -f make/ops/vaultwarden.mk vw-full-backup

# 3. Update chart repository
helm repo update sb-charts

# 4. Review chart changes
helm diff upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values.yaml \
  --set image.tag=1.34.3

# 5. Perform rolling upgrade
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values.yaml \
  --set image.tag=1.34.3 \
  --wait \
  --timeout=10m

# 6. Monitor rollout
kubectl rollout status deployment/vaultwarden -n default

# 7. Verify new pods are running
kubectl get pods -n default -l app.kubernetes.io/name=vaultwarden

# 8. Check application logs
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden --tail=100

# 9. Post-upgrade validation
make -f make/ops/vaultwarden.mk vw-post-upgrade-check

# 10. Test vault functionality
# - Login to web vault
# - Verify password items load
# - Test password sync from mobile app
# - Verify file attachments work
```

**Rollback (if issues occur):**
```bash
# Rollback to previous release
helm rollback vaultwarden -n default

# Verify rollback
kubectl rollout status deployment/vaultwarden -n default
```

**Estimated Duration:** 5-10 minutes

---

### Strategy 2: In-Place Upgrade with Downtime

**Best for:** Major version upgrades (1.30.x → 1.34.x), StatefulSet deployments

**Downtime:** 10-15 minutes

**Risk Level:** Medium

**Prerequisites:**
- Full backup completed
- Maintenance window scheduled
- Users notified

**Procedure:**

```bash
# 1. Pre-upgrade checks
make -f make/ops/vaultwarden.mk vw-pre-upgrade-check

# 2. Create backup
make -f make/ops/vaultwarden.mk vw-full-backup

# 3. Create PVC snapshot (for quick rollback)
make -f make/ops/vaultwarden.mk vw-snapshot-data

# 4. Scale down to zero (stop service)
kubectl scale deployment/vaultwarden -n default --replicas=0
# OR for StatefulSet:
kubectl scale statefulset/vaultwarden -n default --replicas=0

# 5. Wait for pod termination
kubectl wait --for=delete pod -n default -l app.kubernetes.io/name=vaultwarden --timeout=120s

# 6. Backup SQLite database one more time (if using SQLite)
# (pod is stopped, safe to copy database file directly)
POD_NAME=$(kubectl get pod -n default -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].metadata.name}')
kubectl cp default/$POD_NAME:/data/db.sqlite3 /tmp/vaultwarden-pre-upgrade.db

# 7. Update chart repository
helm repo update sb-charts

# 8. Perform upgrade
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values.yaml \
  --set image.tag=1.34.3 \
  --wait \
  --timeout=10m

# 9. Verify pod is running
kubectl wait --for=condition=Ready pod -n default -l app.kubernetes.io/name=vaultwarden --timeout=300s

# 10. Check database migration logs
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden --tail=200 | grep -i "migrat"

# 11. Post-upgrade validation
make -f make/ops/vaultwarden.mk vw-post-upgrade-check

# 12. Test vault functionality
# - Login to web vault
# - Verify all vaults and folders
# - Test password creation/update
# - Verify file attachments
# - Test Send feature
# - Verify mobile app sync
```

**Rollback (if database migration fails):**
```bash
# 1. Scale down new version
kubectl scale deployment/vaultwarden -n default --replicas=0

# 2. Restore database from backup
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/tmp/vaultwarden-pre-upgrade.db
# OR restore from PVC snapshot
make -f make/ops/vaultwarden.mk vw-restore-from-snapshot SNAPSHOT_NAME=vaultwarden-data-snapshot-*

# 3. Rollback Helm release
helm rollback vaultwarden -n default

# 4. Verify rollback
kubectl rollout status deployment/vaultwarden -n default
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

**Estimated Duration:** 10-15 minutes

---

### Strategy 3: Blue-Green Deployment

**Best for:** Zero-downtime major upgrades, high-availability production deployments

**Downtime:** None (instant cutover)

**Risk Level:** Low (easy rollback)

**Prerequisites:**
- Separate namespace or cluster for green environment
- Shared database (PostgreSQL/MySQL) or database replication
- Ingress controller for traffic switching
- Sufficient cluster resources for running both environments

**Procedure:**

```bash
# 1. Prepare blue environment (current production)
BLUE_NAMESPACE="default"
GREEN_NAMESPACE="vaultwarden-green"

# 2. Create backup
make -f make/ops/vaultwarden.mk vw-full-backup

# 3. Create green namespace
kubectl create namespace $GREEN_NAMESPACE

# 4. Deploy green environment with new version
helm install vaultwarden-green sb-charts/vaultwarden \
  -n $GREEN_NAMESPACE \
  -f values.yaml \
  --set image.tag=1.34.3 \
  --set ingress.enabled=false \
  --wait

# 5. Wait for green deployment to be ready
kubectl rollout status deployment/vaultwarden-green -n $GREEN_NAMESPACE

# 6. Run database migrations (if using shared database)
# Migrations run automatically on first pod startup
kubectl logs -n $GREEN_NAMESPACE -l app.kubernetes.io/name=vaultwarden --tail=200 | grep -i "migrat"

# 7. Validate green environment
# Test via port-forward (not public ingress)
kubectl port-forward -n $GREEN_NAMESPACE deployment/vaultwarden-green 8080:80 &
# Open http://localhost:8080 and test vault functionality
# - Login with test account
# - Verify password items
# - Test file attachments
# - Verify Send feature
pkill -f "port-forward.*vaultwarden-green"

# 8. Switch ingress to green environment (cutover)
# Option A: Update ingress annotation
kubectl patch ingress vaultwarden -n $BLUE_NAMESPACE \
  -p '{"spec":{"rules":[{"host":"vault.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"vaultwarden-green","namespace":"vaultwarden-green","port":{"number":80}}}}]}}]}}'

# Option B: Use separate ingress and DNS switch
helm upgrade vaultwarden-green sb-charts/vaultwarden \
  -n $GREEN_NAMESPACE \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=vault.example.com \
  --reuse-values

# Disable blue ingress
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n $BLUE_NAMESPACE \
  --set ingress.enabled=false \
  --reuse-values

# 9. Monitor green environment
kubectl logs -n $GREEN_NAMESPACE -l app.kubernetes.io/name=vaultwarden --tail=100 -f

# 10. Keep blue environment running for 24 hours (rollback safety)
# After 24 hours, if no issues:
# helm uninstall vaultwarden -n $BLUE_NAMESPACE
# kubectl delete namespace $BLUE_NAMESPACE
```

**Rollback (instant cutover back to blue):**
```bash
# Switch ingress back to blue environment
kubectl patch ingress vaultwarden -n $GREEN_NAMESPACE \
  -p '{"spec":{"rules":[{"host":"vault.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"vaultwarden","namespace":"default","port":{"number":80}}}}]}}]}}'

# OR re-enable blue ingress
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n $BLUE_NAMESPACE \
  --set ingress.enabled=true \
  --reuse-values
```

**Estimated Duration:** 20-30 minutes (including validation)

---

## Version-Specific Upgrade Notes

### Vaultwarden 1.32.x → 1.34.x

**Release Date:** 1.34.0 (December 2024)

**Key Changes:**
- **Alpine Linux 3.20**: Updated base image (may require permission fixes)
- **Rust 1.82**: Updated Rust compiler (performance improvements)
- **Database optimizations**: Improved query performance for large vaults
- **WebAuthn improvements**: Better support for passkeys and FIDO2
- **Organization improvements**: Enhanced organization management features

**Breaking Changes:**
- None (backward compatible)

**Database Migration:**
- Automatic migration on startup (no manual intervention)
- Migration adds new indices for organization features
- Estimated migration time: < 1 minute for typical databases

**Configuration Changes:**
- No breaking configuration changes
- New optional environment variables for organization features

**Pre-Upgrade Steps:**
```bash
# 1. Backup data
make -f make/ops/vaultwarden.mk vw-full-backup

# 2. Check current database size (large databases may take longer to migrate)
kubectl exec -n default deployment/vaultwarden -- du -sh /data/db.sqlite3

# 3. Update values.yaml (if using Alpine-specific configurations)
# No changes required for standard deployments
```

**Post-Upgrade Steps:**
```bash
# 1. Verify database migration logs
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden --tail=200 | grep -i "migrat"

# 2. Check for permission issues (Alpine 3.20 change)
kubectl exec -n default deployment/vaultwarden -- ls -la /data

# Fix permissions if needed:
kubectl exec -n default deployment/vaultwarden -- chown -R 1000:1000 /data

# 3. Test WebAuthn/passkey functionality
# - Login with passkey (if configured)
# - Verify FIDO2 hardware keys work

# 4. Test organization features
# - Verify organization access
# - Test collection sharing
# - Verify group permissions
```

**Known Issues:**
- None reported for 1.34.x upgrade path

---

### Vaultwarden 1.30.x → 1.32.x

**Release Date:** 1.32.0 (September 2024)

**Key Changes:**
- **Emergency access**: Added emergency access feature for vault recovery
- **Event logging improvements**: Enhanced audit logging
- **SQLite performance**: Optimized SQLite queries for better performance
- **Docker multi-arch**: Improved ARM64 support

**Breaking Changes:**
- None

**Database Migration:**
- Automatic migration adds `emergency_access` table
- Adds new columns to `users` table
- Estimated migration time: < 1 minute

**Configuration Changes:**
- No breaking changes

**Pre-Upgrade Steps:**
```bash
# Standard backup procedure
make -f make/ops/vaultwarden.mk vw-full-backup
```

**Post-Upgrade Steps:**
```bash
# Test emergency access feature
# - Configure emergency access in web vault
# - Test emergency access workflow
# - Verify notifications work
```

---

### Database Backend Migration (SQLite → PostgreSQL)

**Use Case:** Migrating from embedded SQLite to external PostgreSQL for:
- **High availability**: Multiple replicas with shared database
- **Performance**: Better concurrency handling for many users
- **Backup/restore**: Standard PostgreSQL backup tools
- **Scaling**: Horizontal scaling with multiple Vaultwarden instances

**Downtime:** 1-2 hours (depending on database size)

**Risk Level:** High (requires data migration)

**Prerequisites:**
- PostgreSQL 13+ instance available
- Sufficient storage for PostgreSQL database
- Full backup of SQLite database and data directory

**Procedure:**

```bash
# 1. Backup current SQLite deployment
make -f make/ops/vaultwarden.mk vw-full-backup

# 2. Scale down Vaultwarden (stop service)
kubectl scale deployment/vaultwarden -n default --replicas=0

# 3. Export SQLite database to SQL format
POD_NAME=$(kubectl get pod -n default -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD_NAME -- sqlite3 /data/db.sqlite3 .dump > /tmp/vaultwarden-sqlite-dump.sql

# 4. Prepare PostgreSQL database
PGPASSWORD=<password> psql -h <pg-host> -U postgres -c "CREATE DATABASE vaultwarden OWNER vaultwarden;"

# 5. Convert SQLite dump to PostgreSQL-compatible SQL
# Use migration script (provided in docs/scripts/sqlite-to-postgres.sh)
./docs/scripts/sqlite-to-postgres.sh /tmp/vaultwarden-sqlite-dump.sql /tmp/vaultwarden-postgres.sql

# 6. Import to PostgreSQL
PGPASSWORD=<password> psql -h <pg-host> -U vaultwarden -d vaultwarden < /tmp/vaultwarden-postgres.sql

# 7. Verify PostgreSQL data
PGPASSWORD=<password> psql -h <pg-host> -U vaultwarden -d vaultwarden -c "\dt"
PGPASSWORD=<password> psql -h <pg-host> -U vaultwarden -d vaultwarden -c "SELECT COUNT(*) FROM users;"

# 8. Update values.yaml to use PostgreSQL
cat <<EOF > values-postgres.yaml
sqlite:
  enabled: false

postgresql:
  enabled: true
  external:
    enabled: true
    host: "<pg-host>"
    port: 5432
    database: "vaultwarden"
    username: "vaultwarden"
    password: "<password>"
EOF

# 9. Upgrade Helm release with new configuration
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values-postgres.yaml \
  --wait

# 10. Verify Vaultwarden connects to PostgreSQL
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden | grep -i "database"

# 11. Test vault functionality
# - Login to web vault
# - Verify all password items
# - Test password creation/update
# - Verify file attachments
# - Test organization features

# 12. Keep SQLite backup for 30 days (rollback safety)
```

**Rollback (if migration fails):**
```bash
# 1. Scale down Vaultwarden
kubectl scale deployment/vaultwarden -n default --replicas=0

# 2. Restore SQLite values.yaml
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values-sqlite.yaml \
  --wait

# 3. Restore SQLite database from backup
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/tmp/vaultwarden-backups/vaultwarden-data-*.tar.gz

# 4. Verify restoration
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden
```

**Estimated Duration:** 1-2 hours (depending on vault size)

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Run comprehensive post-upgrade checks
make -f make/ops/vaultwarden.mk vw-post-upgrade-check

# This performs:
# - Pod health checks
# - Database connectivity tests
# - Volume mount verification
# - Configuration validation
```

### Manual Validation Checklist

**1. Verify Vaultwarden is running:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=vaultwarden
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden --tail=50
```

**2. Test web vault access:**
- Open https://vault.example.com
- Verify login page loads
- Login with admin account
- Verify vault dashboard displays correctly

**3. Test password functionality:**
- Create new password item
- Update existing password item
- Delete test password item
- Verify password generator works

**4. Test file attachments:**
- Upload file attachment to existing item
- Download file attachment
- Delete file attachment
- Verify attachment storage usage

**5. Test Send feature:**
- Create new Send (text or file)
- Verify Send link works
- Access Send from incognito browser
- Delete Send

**6. Test organization features (if used):**
- Verify organization access
- Test collection sharing
- Verify group permissions
- Test organization admin functions

**7. Test client synchronization:**
- Sync from browser extension
- Sync from mobile app (iOS/Android)
- Sync from desktop app
- Verify cross-device consistency

**8. Test emergency access (if configured):**
- Verify emergency access contacts
- Test emergency access request workflow
- Verify emergency access notifications

**9. Check logs for errors:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden --tail=500 | grep -i "error\|warn\|fail"
```

**10. Verify metrics (if monitoring enabled):**
```bash
# Check Prometheus metrics endpoint (if configured)
kubectl port-forward -n default deployment/vaultwarden 9090:80 &
curl http://localhost:9090/metrics
pkill -f "port-forward.*vaultwarden"
```

---

## Rollback Procedures

### Scenario 1: Rollback via Helm (No Database Changes)

**Use Case:** New version has issues but database schema unchanged

**Procedure:**
```bash
# 1. Rollback to previous Helm release
helm rollback vaultwarden -n default

# 2. Wait for rollout
kubectl rollout status deployment/vaultwarden -n default

# 3. Verify old version is running
kubectl get deployment vaultwarden -n default -o jsonpath='{.spec.template.spec.containers[0].image}'

# 4. Test functionality
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

**Estimated Duration:** 2-5 minutes

---

### Scenario 2: Rollback with Database Restore (Schema Migrated)

**Use Case:** Database schema was migrated and needs to be restored

**Procedure:**
```bash
# 1. Scale down Vaultwarden
kubectl scale deployment/vaultwarden -n default --replicas=0

# 2. Restore database from backup
# SQLite mode:
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/tmp/vaultwarden-backups/vaultwarden-data-*.tar.gz

# PostgreSQL mode:
make -f make/ops/vaultwarden.mk vw-restore-postgres BACKUP_FILE=/tmp/vaultwarden-backups/vaultwarden-pg-*.sql.gz

# 3. Rollback Helm release
helm rollback vaultwarden -n default

# 4. Verify rollout
kubectl rollout status deployment/vaultwarden -n default

# 5. Test functionality
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

**Estimated Duration:** 15-30 minutes (depending on database size)

---

### Scenario 3: Rollback via PVC Snapshot (Fastest)

**Use Case:** Quick rollback using storage snapshot

**Procedure:**
```bash
# 1. Scale down Vaultwarden
kubectl scale deployment/vaultwarden -n default --replicas=0

# 2. Restore from PVC snapshot
make -f make/ops/vaultwarden.mk vw-restore-from-snapshot SNAPSHOT_NAME=vaultwarden-data-snapshot-*

# 3. Rollback Helm release
helm rollback vaultwarden -n default

# 4. Verify rollout
kubectl rollout status deployment/vaultwarden -n default

# 5. Test functionality
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

**Estimated Duration:** 5-10 minutes

---

## Troubleshooting

### Common Upgrade Issues

#### 1. Database Migration Failed

**Symptom:** Pod crashes with database migration error

**Logs:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden

# Example error:
# [ERROR] Database migration failed: ...
# [ERROR] PANIC: Could not run migrations
```

**Cause:** Incompatible database schema or corrupted database

**Solution:**
```bash
# Option 1: Restore database from backup
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/tmp/vaultwarden-backups/vaultwarden-data-*.tar.gz
helm rollback vaultwarden -n default

# Option 2: Check SQLite integrity and repair
kubectl exec -n default deployment/vaultwarden -- sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;"
kubectl exec -n default deployment/vaultwarden -- sqlite3 /data/db.sqlite3 "VACUUM;"
kubectl rollout restart deployment/vaultwarden -n default

# Option 3: Contact Vaultwarden community for migration assistance
# https://github.com/dani-garcia/vaultwarden/discussions
```

#### 2. Permission Denied on /data

**Symptom:** Pod crashes with permission errors

**Logs:**
```bash
# [ERROR] Error opening database file: Permission denied
# [ERROR] Could not write to /data
```

**Cause:** Alpine Linux base image update changed user UID/GID

**Solution:**
```bash
# Fix PVC permissions
kubectl exec -n default deployment/vaultwarden -- chown -R 1000:1000 /data
kubectl exec -n default deployment/vaultwarden -- chmod -R 755 /data

# Restart pod
kubectl rollout restart deployment/vaultwarden -n default
```

#### 3. Out of Memory / OOMKilled

**Symptom:** Pod repeatedly crashes with OOMKilled status

**Cause:** Database migration or large vault requires more memory

**Solution:**
```bash
# Increase memory limits temporarily
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  --set resources.limits.memory=1Gi \
  --reuse-values

# After upgrade completes, return to normal limits
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  --set resources.limits.memory=512Mi \
  --reuse-values
```

#### 4. Clients Can't Sync After Upgrade

**Symptom:** Browser extensions and mobile apps show "sync failed"

**Cause:** API compatibility issue or CORS configuration

**Solution:**
```bash
# Check Vaultwarden logs for API errors
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden | grep -i "api\|sync"

# Verify DOMAIN configuration
kubectl exec -n default deployment/vaultwarden -- env | grep DOMAIN

# Update DOMAIN if needed
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  --set vaultwarden.domain=https://vault.example.com \
  --reuse-values

# Force client re-login
# Logout from all clients and login again
```

#### 5. WebAuthn/Passkey Stopped Working

**Symptom:** Passkey authentication fails after upgrade

**Cause:** WebAuthn configuration or browser compatibility

**Solution:**
```bash
# Verify DOMAIN matches public URL (required for WebAuthn)
kubectl exec -n default deployment/vaultwarden -- env | grep DOMAIN

# Check browser console for WebAuthn errors
# Open browser DevTools → Console

# Verify Vaultwarden WebAuthn logs
kubectl logs -n default -l app.kubernetes.io/name=vaultwarden | grep -i "webauthn\|fido"

# Re-register passkey if needed
# Web Vault → Settings → Security → Two-step Login → Manage → Remove and re-add
```

#### 6. Ingress Not Routing After Upgrade

**Symptom:** 404 or 502 errors accessing web vault

**Cause:** Ingress configuration changed or service name mismatch

**Solution:**
```bash
# Check ingress configuration
kubectl get ingress vaultwarden -n default -o yaml

# Verify service is running
kubectl get service vaultwarden -n default

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify backend service endpoints
kubectl get endpoints vaultwarden -n default

# Recreate ingress if needed
kubectl delete ingress vaultwarden -n default
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  --set ingress.enabled=true \
  --reuse-values
```

---

## Summary

**Pre-Upgrade Checklist:**
- [ ] Review release notes
- [ ] Create full backup (data + database + config)
- [ ] Create PVC snapshot (optional but recommended)
- [ ] Check database health
- [ ] Test backup restore (recommended)
- [ ] Plan maintenance window (if downtime required)
- [ ] Notify users of upgrade schedule

**Upgrade Execution:**
- [ ] Choose upgrade strategy (rolling/in-place/blue-green)
- [ ] Perform pre-upgrade checks
- [ ] Execute upgrade procedure
- [ ] Monitor upgrade progress
- [ ] Verify pod health and logs

**Post-Upgrade Validation:**
- [ ] Run automated validation checks
- [ ] Test web vault access
- [ ] Verify password functionality
- [ ] Test file attachments
- [ ] Test Send feature
- [ ] Test organization features (if used)
- [ ] Test client synchronization
- [ ] Check logs for errors
- [ ] Document actual RTO/downtime

**Rollback Preparation:**
- [ ] Keep backup files for 30 days
- [ ] Document rollback procedure
- [ ] Test rollback in staging environment
- [ ] Communicate rollback plan to team

**For More Information:**
- Vaultwarden releases: https://github.com/dani-garcia/vaultwarden/releases
- Vaultwarden wiki: https://github.com/dani-garcia/vaultwarden/wiki
- Vaultwarden discussions: https://github.com/dani-garcia/vaultwarden/discussions
