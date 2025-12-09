# Uptime Kuma Upgrade Guide

Comprehensive upgrade procedures for Uptime Kuma Helm chart deployments on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Version-Specific Notes](#version-specific-notes)
- [Database Migration](#database-migration)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

### Upgrade Types

| Type | Example | Downtime | Complexity | Risk |
|------|---------|----------|------------|------|
| **Patch** | 1.23.11 → 1.23.12 | None | Low | Low |
| **Minor** | 1.23.x → 1.24.x | 2-5 min | Medium | Medium |
| **Major** | 1.x → 2.x | 10-20 min | High | High |
| **Database** | SQLite → MariaDB | 30-60 min | High | High |

### What Gets Upgraded

1. **Application**: Uptime Kuma Docker image
2. **Database Schema**: Automatic migration on startup
3. **Configuration**: Helm chart values
4. **Kubernetes Resources**: Deployment, Service, Ingress, etc.

### Critical Considerations

**Uptime Kuma-Specific**:
- **Database migration is automatic** on first startup after upgrade
- **No rollback** after database migration completes
- **Monitor checks pause** during pod restart (2-5 minutes)
- **Status pages offline** during upgrade
- **Notification queue persists** (no alerts lost)

---

## Pre-Upgrade Checklist

### Step 1: Backup Everything

**CRITICAL**: Always backup before upgrading. Database migrations are irreversible.

```bash
# Full backup (data PVC + database)
make -f make/ops/uptime-kuma.mk uk-full-backup

# Verify backup created
ls -lh tmp/uptime-kuma-backups/
```

**Backup validation**:
```bash
# Test backup integrity
tar tzf tmp/uptime-kuma-backups/data-20250109-143022.tar.gz | head -20
```

---

### Step 2: Check Current Version

```bash
# Current chart version
helm list -n default | grep uptime-kuma

# Current app version
kubectl get deployment uptime-kuma -o jsonpath='{.spec.template.spec.containers[0].image}'

# Uptime Kuma version via UI
# Access: Dashboard → About
```

---

### Step 3: Review Release Notes

**Important sources**:
- [Uptime Kuma Releases](https://github.com/louislam/uptime-kuma/releases)
- [Helm Chart CHANGELOG](../../CHANGELOG.md)

**Look for**:
- ⚠️ Breaking changes
- 🗄️ Database schema changes
- 🔧 Configuration changes
- 🐛 Known issues

---

### Step 4: Check Database Type

```bash
# Check if using SQLite or MariaDB
helm get values uptime-kuma | grep -A5 "database:"

# SQLite (default)
database:
  type: sqlite

# MariaDB
database:
  type: mariadb
```

**Impact**: MariaDB upgrades require external database upgrade procedures.

---

### Step 5: Verify Current State

**Run pre-upgrade check**:
```bash
make -f make/ops/uptime-kuma.mk uk-pre-upgrade-check
```

**Manual checks**:

```bash
# 1. Pod health
kubectl get pods -l app.kubernetes.io/name=uptime-kuma

# 2. Monitor count
# Via UI: Dashboard → Monitors (count total monitors)

# 3. Notification channels
# Via UI: Settings → Notifications (verify all channels configured)

# 4. Status pages
# Via UI: Status Pages (count active pages)

# 5. Storage usage
kubectl exec deployment/uptime-kuma -- df -h /app/data
```

---

### Step 6: Check Storage Space

**Database can grow during migration**:

```bash
# Check current database size
kubectl exec deployment/uptime-kuma -- du -sh /app/data/kuma.db

# Check available space (need 2x current DB size)
kubectl exec deployment/uptime-kuma -- df -h /app/data
```

**Expand PVC if needed**:
```bash
# Increase PVC size (if storage class supports expansion)
kubectl patch pvc uptime-kuma-data -p '{"spec":{"resources":{"requests":{"storage":"8Gi"}}}}'
```

---

### Step 7: Test in Staging

**Recommended for production upgrades**:

```bash
# 1. Create staging namespace
kubectl create namespace uptime-kuma-staging

# 2. Deploy current version
helm install uptime-kuma-staging sb-charts/uptime-kuma \
  -f values.yaml \
  -n uptime-kuma-staging

# 3. Restore production backup
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=prod-backup.tar.gz \
  RELEASE_NAME=uptime-kuma-staging \
  NAMESPACE=uptime-kuma-staging

# 4. Perform test upgrade
helm upgrade uptime-kuma-staging sb-charts/uptime-kuma \
  --reuse-values \
  --set image.tag=1.24.0 \
  -n uptime-kuma-staging

# 5. Validate functionality
# - Check monitors
# - Test notifications
# - Verify status pages

# 6. Cleanup
kubectl delete namespace uptime-kuma-staging
```

---

### Step 8: Plan Maintenance Window

**Choose strategy based on tolerance**:

| Strategy | Downtime | Risk | When to Use |
|----------|----------|------|-------------|
| **Rolling Upgrade** | 2-5 min | Low | Patch/minor versions |
| **Blue-Green** | < 1 min | Low | Zero-downtime required |
| **Maintenance Window** | 10-20 min | Medium | Major versions |

---

### Step 9: Notify Stakeholders

**Communication plan**:

```
Subject: Uptime Kuma Maintenance - [Date] [Time]

We will be upgrading Uptime Kuma from v1.23.11 to v1.24.0.

Expected downtime: 2-5 minutes
Start time: [Date] [Time]
Impact:
- Monitor checks will pause temporarily
- Status pages will be offline briefly
- No monitoring alerts will be lost

Contact: [Your contact info]
```

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Recommended)

**Best for**: Patch and minor version upgrades (1.23.11 → 1.23.12, 1.23.x → 1.24.x)

**Downtime**: 2-5 minutes (pod restart only)

**Procedure**:

```bash
# 1. Backup first
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Upgrade chart
helm upgrade uptime-kuma sb-charts/uptime-kuma \
  --reuse-values \
  --set image.tag=1.24.0

# 3. Monitor rollout
kubectl rollout status deployment/uptime-kuma

# 4. Verify health
make -f make/ops/uptime-kuma.mk uk-stats
kubectl get pods -l app.kubernetes.io/name=uptime-kuma

# 5. Check logs for migration
kubectl logs -f deployment/uptime-kuma | grep -i migration
```

**What happens**:
1. Helm updates Deployment with new image
2. Kubernetes creates new pod
3. Old pod terminates (monitor checks pause)
4. New pod starts, database migration runs automatically
5. Uptime Kuma becomes ready (monitor checks resume)

**Limitations**:
- ⚠️ Brief monitoring gap (2-5 minutes)
- ⚠️ Status pages offline during restart
- ⚠️ No rollback after database migration

---

### Strategy 2: Blue-Green Deployment

**Best for**: Zero-downtime requirement, risk-averse upgrades

**Downtime**: < 1 minute (traffic switch only)

**Procedure**:

```bash
# 1. Backup production
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Deploy green (new version) alongside blue (current)
helm install uptime-kuma-green sb-charts/uptime-kuma \
  -f values.yaml \
  --set image.tag=1.24.0 \
  --set nameOverride=uptime-kuma-green

# 3. Point green to same PVC (READ-ONLY initially)
# WARNING: This requires careful PVC sharing - see notes below

# 4. Validate green deployment
kubectl port-forward svc/uptime-kuma-green 3001:3001
# Test at http://localhost:3001

# 5. Stop blue to allow green exclusive PVC access
kubectl scale deployment/uptime-kuma --replicas=0

# 6. Start green with write access
kubectl scale deployment/uptime-kuma-green --replicas=1

# 7. Switch ingress to green
kubectl patch ingress uptime-kuma -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"uptime-kuma-green"}}}]}}]}}'

# 8. Verify traffic switched
curl -I https://uptime.example.com

# 9. Keep blue for 24h, then delete
# helm uninstall uptime-kuma
```

**Important Notes**:
- ⚠️ PVC cannot be mounted ReadWrite by multiple pods simultaneously
- ⚠️ Must stop blue before starting green
- ⚠️ Database migration happens when green starts
- ⚠️ Brief downtime during blue→green switch (~30 seconds)

**Rollback (before deleting blue)**:
```bash
# 1. Stop green
kubectl scale deployment/uptime-kuma-green --replicas=0

# 2. Start blue
kubectl scale deployment/uptime-kuma --replicas=1

# 3. Switch ingress back
kubectl patch ingress uptime-kuma -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"uptime-kuma"}}}]}}]}}'
```

---

### Strategy 3: Maintenance Window

**Best for**: Major version upgrades (1.x → 2.x), database migrations (SQLite → MariaDB)

**Downtime**: 10-20 minutes

**Procedure**:

```bash
# 1. Backup
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Announce maintenance window
# (Send notification to stakeholders)

# 3. Uninstall current version
helm uninstall uptime-kuma

# 4. Wait for resources to terminate
kubectl get pods -l app.kubernetes.io/name=uptime-kuma --watch

# 5. Install new version
helm install uptime-kuma sb-charts/uptime-kuma \
  -f values.yaml \
  --set image.tag=2.0.0

# 6. Wait for database migration
kubectl logs -f deployment/uptime-kuma

# 7. Verify
make -f make/ops/uptime-kuma.mk uk-post-upgrade-check
```

**When to use**:
- ✅ Major version changes requiring clean install
- ✅ Database type change (SQLite → MariaDB)
- ✅ Significant schema changes
- ✅ Downtime is acceptable

---

## Post-Upgrade Validation

### Automated Validation

```bash
make -f make/ops/uptime-kuma.mk uk-post-upgrade-check
```

**Checks performed**:
1. Pod status and readiness
2. New image version verification
3. Log error scanning
4. Database integrity check
5. Web UI accessibility
6. Monitor count verification

---

### Manual Validation

**1. Check pod status**:
```bash
kubectl get pods -l app.kubernetes.io/name=uptime-kuma

# Expected:
# NAME                           READY   STATUS    RESTARTS   AGE
# uptime-kuma-6d8f9c8b7d-abc12   1/1     Running   0          2m
```

**2. Verify version**:
```bash
kubectl exec deployment/uptime-kuma -- /app/uptime-kuma --version
# Or check via UI: Dashboard → About
```

**3. Check logs for errors**:
```bash
kubectl logs deployment/uptime-kuma --tail=100 | grep -i error

# Expected: No critical errors
# Acceptable: Temporary connection errors during startup
```

**4. Test web UI**:
```bash
make -f make/ops/uptime-kuma.mk uk-get-url
# Access URL and verify dashboard loads
```

**5. Verify monitors**:
```bash
# Via UI: Dashboard → Monitors
# Check:
# - Monitor count matches pre-upgrade
# - All monitors show correct status
# - Monitor checks are running (status updating)
```

**6. Test notifications**:
```bash
# Via UI: Settings → Notifications
# For each notification channel:
# 1. Click "Test"
# 2. Verify notification received
```

**7. Check status pages**:
```bash
# Via UI: Status Pages
# Verify:
# - All status pages listed
# - Public pages accessible via URL
# - Correct monitors assigned to pages
```

**8. Verify database integrity**:
```bash
make -f make/ops/uptime-kuma.mk uk-db-check

# Expected: ok
```

**9. Check monitor history**:
```bash
# Via UI: Select any monitor → Uptime
# Verify:
# - Historical data present
# - No data loss
# - Uptime percentage accurate
```

---

## Rollback Procedures

### Rollback via Helm (Preferred)

**Available if**: Database schema hasn't changed or changes are backward-compatible

```bash
# 1. Check release history
helm history uptime-kuma

# 2. Identify previous revision
# REVISION  UPDATED           STATUS      CHART                APP VERSION
# 1         2025-01-01 10:00  superseded  uptime-kuma-0.3.0    1.23.11
# 2         2025-01-09 14:00  deployed    uptime-kuma-0.4.0    1.24.0

# 3. Rollback to previous revision
helm rollback uptime-kuma

# Or rollback to specific revision
helm rollback uptime-kuma 1

# 4. Verify rollback
kubectl rollout status deployment/uptime-kuma
make -f make/ops/uptime-kuma.mk uk-stats
```

**Automated rollback**:
```bash
make -f make/ops/uptime-kuma.mk uk-upgrade-rollback
```

---

### Full Rollback (Database Restore)

**Use when**: Database schema changed and Helm rollback fails

```bash
# 1. Uninstall current version
helm uninstall uptime-kuma

# 2. Wait for pod termination
kubectl get pods -l app.kubernetes.io/name=uptime-kuma --watch

# 3. Reinstall old version
helm install uptime-kuma sb-charts/uptime-kuma \
  -f values-backup.yaml \
  --set image.tag=1.23.11

# 4. Restore from backup
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=tmp/uptime-kuma-backups/data-20250109-120000.tar.gz

# 5. Restart pod
kubectl rollout restart deployment/uptime-kuma

# 6. Verify
make -f make/ops/uptime-kuma.mk uk-post-upgrade-check
```

---

## Version-Specific Notes

### 1.23.x → 1.24.x (Minor Version)

**Release Date**: 2024-12-XX

**Changes**:
- Improved notification providers
- New monitor types
- UI enhancements
- Performance improvements

**Database Changes**: Schema updates (automatic migration)

**Upgrade Strategy**: Rolling Upgrade

**Steps**:
1. Backup data
2. Upgrade via Helm
3. Wait for migration (check logs)
4. Verify monitors and notifications

**Known Issues**:
- None reported

---

### 1.x → 2.x (Major Version)

**Release Date**: TBD

**Breaking Changes**:
- Database schema overhaul
- API changes
- Configuration format changes
- Minimum Node.js version increase

**Database Changes**: Major schema migration (one-way, irreversible)

**Upgrade Strategy**: Maintenance Window (recommended)

**Steps**:
1. **CRITICAL**: Full backup
2. Test upgrade in staging environment
3. Schedule maintenance window
4. Uninstall v1.x
5. Install v2.x
6. Monitor migration logs closely
7. Extensive post-upgrade testing

**Rollback**:
- ⚠️ Database migration is one-way
- ⚠️ Rollback requires full restore from backup
- ⚠️ Plan for 1-2 hour rollback time

**Known Issues**:
- Check release notes for known issues
- Monitor Uptime Kuma GitHub issues

---

## Database Migration

### SQLite → MariaDB Migration

**Why migrate**:
- Better performance for large installations (100+ monitors)
- Better concurrency handling
- Easier replication and HA setup

**Downtime**: 30-60 minutes (depending on database size)

**Prerequisites**:
- MariaDB/MySQL server available
- Empty database created
- Database credentials configured

**Procedure**:

```bash
# 1. Backup current SQLite database
make -f make/ops/uptime-kuma.mk uk-backup-database

# 2. Export SQLite data
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- sqlite3 /app/data/kuma.db .dump > kuma-export.sql

# 3. Convert SQLite dump to MariaDB format
# (Fix syntax differences: AUTOINCREMENT → AUTO_INCREMENT, etc.)
sed -i 's/AUTOINCREMENT/AUTO_INCREMENT/g' kuma-export.sql
sed -i 's/INTEGER PRIMARY KEY/INT PRIMARY KEY AUTO_INCREMENT/g' kuma-export.sql

# 4. Scale down Uptime Kuma
kubectl scale deployment/uptime-kuma --replicas=0

# 5. Import to MariaDB
mysql -h mariadb-host -u uptime_kuma -p uptime_kuma < kuma-export.sql

# 6. Update Helm values
cat <<EOF > values-mariadb.yaml
uptimeKuma:
  database:
    type: mariadb
    mariadb:
      host: mariadb-host
      port: 3306
      database: uptime_kuma
      username: uptime_kuma
      password: <password>
EOF

# 7. Upgrade chart with MariaDB config
helm upgrade uptime-kuma sb-charts/uptime-kuma -f values-mariadb.yaml

# 8. Scale up
kubectl scale deployment/uptime-kuma --replicas=1

# 9. Verify
kubectl logs -f deployment/uptime-kuma
make -f make/ops/uptime-kuma.mk uk-check-monitors
```

**Rollback**:
```bash
# 1. Scale down
kubectl scale deployment/uptime-kuma --replicas=0

# 2. Restore SQLite backup
make -f make/ops/uptime-kuma.mk uk-restore-database \
  FILE=tmp/uptime-kuma-backups/kuma-backup.db

# 3. Revert to SQLite config
helm upgrade uptime-kuma sb-charts/uptime-kuma \
  --set uptimeKuma.database.type=sqlite

# 4. Scale up
kubectl scale deployment/uptime-kuma --replicas=1
```

---

## Troubleshooting

### Issue 1: Database Migration Fails

**Symptom**: Pod crashes during startup with migration errors

**Logs**:
```
Error: Migration failed
Error: UNIQUE constraint failed
```

**Solution 1**: Check database integrity before upgrade
```bash
make -f make/ops/uptime-kuma.mk uk-db-check
```

**Solution 2**: Restore from backup and retry
```bash
helm rollback uptime-kuma
make -f make/ops/uptime-kuma.mk uk-restore-database FILE=backup.db
```

---

### Issue 2: Monitors Not Running After Upgrade

**Symptom**: Monitors show as "Pending" or "Paused"

**Cause**: Database migration incomplete or corruption

**Solution**:
```bash
# 1. Check logs
kubectl logs deployment/uptime-kuma | grep -i monitor

# 2. Restart deployment
kubectl rollout restart deployment/uptime-kuma

# 3. If persists, restore from backup
make -f make/ops/uptime-kuma.mk uk-restore-data FILE=backup.tar.gz
```

---

### Issue 3: Notifications Not Sending

**Symptom**: Test notifications fail after upgrade

**Cause**: API key encryption changes or provider API updates

**Solution**:
```bash
# Via UI: Settings → Notifications
# For each provider:
# 1. Click "Edit"
# 2. Re-enter API key/webhook URL
# 3. Click "Test"
# 4. Save
```

---

### Issue 4: Status Pages Broken

**Symptom**: Status pages return 404 or show incorrect data

**Cause**: Database schema changes affecting status page queries

**Solution**:
```bash
# 1. Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check

# 2. Via UI: Status Pages
# Edit each page:
# - Re-assign monitors
# - Re-save configuration

# 3. If persists, recreate status page from scratch
```

---

### Issue 5: High Memory Usage After Upgrade

**Symptom**: Pod using significantly more memory than before

**Cause**: Database migration created inefficient indexes or new features consuming more resources

**Solution**:
```bash
# 1. Vacuum database to reclaim space
make -f make/ops/uptime-kuma.mk uk-db-vacuum

# 2. Increase memory limit if needed
helm upgrade uptime-kuma sb-charts/uptime-kuma \
  --reuse-values \
  --set resources.limits.memory=1Gi

# 3. Restart pod
kubectl rollout restart deployment/uptime-kuma
```

---

## Best Practices

### DO

✅ **Always backup before upgrading**
- Full data PVC backup
- Database-only backup
- Helm values export

✅ **Test upgrades in staging first**
- Restore production backup to staging
- Perform upgrade
- Validate functionality
- Document issues

✅ **Review release notes carefully**
- Breaking changes
- Database schema changes
- Known issues
- Migration notes

✅ **Verify database integrity before upgrade**
```bash
make -f make/ops/uptime-kuma.mk uk-db-check
```

✅ **Monitor logs during migration**
```bash
kubectl logs -f deployment/uptime-kuma
```

✅ **Keep old backups for 30 days**
- In case rollback needed weeks later
- Store offsite (S3, etc.)

✅ **Upgrade during low-traffic periods**
- Minimize monitoring gaps
- Easier to validate post-upgrade

✅ **Validate thoroughly after upgrade**
- All monitors running
- Notifications working
- Status pages accessible
- Historical data intact

---

### DON'T

❌ **Skip backups**
- Database migrations are irreversible
- Rollback requires backup restore

❌ **Upgrade multiple major versions at once**
- 1.x → 3.x: High risk
- Upgrade incrementally: 1.x → 2.x → 3.x

❌ **Ignore database migration logs**
- Critical errors may appear during migration
- Address immediately or rollback

❌ **Assume monitors will auto-resume**
- Some upgrades require manual monitor restart
- Verify via UI after upgrade

❌ **Delete old backups immediately**
- Keep for 30 days minimum
- Issues may surface days later

❌ **Upgrade without testing**
- Production upgrades without staging test: High risk
- Always test first

❌ **Ignore resource limits**
- Migration may need more memory temporarily
- Monitor resource usage during upgrade

---

## Upgrade Checklist

### Pre-Upgrade

- [ ] Full backup completed and verified
- [ ] Current version documented
- [ ] Release notes reviewed
- [ ] Database type identified (SQLite/MariaDB)
- [ ] Storage space verified (2x database size available)
- [ ] Staging test completed (for production upgrades)
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified
- [ ] Rollback plan documented

### During Upgrade

- [ ] Backup location documented
- [ ] Upgrade command executed
- [ ] Pod rollout monitored
- [ ] Database migration logs reviewed
- [ ] No critical errors in logs
- [ ] Pod reached Ready state

### Post-Upgrade

- [ ] Automated validation passed
- [ ] Web UI accessible
- [ ] Monitor count verified
- [ ] All monitors running
- [ ] Notifications tested
- [ ] Status pages accessible
- [ ] Historical data intact
- [ ] Database integrity checked
- [ ] Performance acceptable
- [ ] Stakeholders notified of completion

### Post-Upgrade (24-48 hours)

- [ ] Monitor checks stable
- [ ] No unexpected errors in logs
- [ ] Resource usage normal
- [ ] Notification delivery confirmed
- [ ] Old version deleted (if applicable)
- [ ] Documentation updated

---

## Additional Resources

- **Uptime Kuma Releases**: https://github.com/louislam/uptime-kuma/releases
- **Uptime Kuma Wiki**: https://github.com/louislam/uptime-kuma/wiki
- **Database Migration**: https://github.com/louislam/uptime-kuma/wiki/Database
- **Helm Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Kubernetes Deployment Strategies**: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

---

**Last Updated**: 2025-12-09
**Chart Version**: v0.4.0
**Uptime Kuma Version**: 1.23.x
