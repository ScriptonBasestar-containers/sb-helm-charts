# Uptime Kuma Backup & Recovery Guide

Comprehensive backup and recovery procedures for Uptime Kuma Helm chart deployments on Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
- [Backup Methods](#backup-methods)
- [Recovery Procedures](#recovery-procedures)
- [Automation](#automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### What is Uptime Kuma?

Uptime Kuma is a self-hosted monitoring tool similar to Uptime Robot. It monitors:
- **HTTP(s) / TCP / HTTP(s) Keyword / Ping / DNS Record / Push / Steam Game Server / Docker Container**
- **Notifications** (90+ notification services)
- **Status Pages**

### Why Backup?

Critical data stored by Uptime Kuma:
- **Monitor configurations** (URLs, intervals, keywords, expected status codes)
- **Historical uptime data** (status check results, response times, incidents)
- **Notification settings** (Slack, Discord, Email, Telegram, etc.)
- **Status page configurations** (public/private pages, branding, custom domains)
- **User accounts** (admin and team members)

**Loss impact**: Monitor downtime goes undetected, historical data lost, notification alerts stop.

---

## Backup Strategy

### Components Overview

| Component | Priority | Size | Frequency | Method |
|-----------|----------|------|-----------|--------|
| **Data PVC** | 🔴 Critical | 100MB-2GB | Daily | tar, Restic, VolumeSnapshot |
| **Database** | 🔴 Critical | 50MB-1GB | Daily | SQLite .backup |
| **Configuration** | 🟡 Important | <1MB | Weekly | helm get values |
| **MariaDB** (optional) | 🟠 High | Varies | Daily | mysqldump |

**Total backup size**: Typically 100MB - 2GB (small compared to media server applications)

### Backup Principles

1. **Data PVC contains everything**:
   - SQLite database (`kuma.db`)
   - Upload files (icons, logos for status pages)
   - Configuration files

2. **Stateless application**: Uptime Kuma pod can be recreated anytime; data persists in PVC

3. **Optional MariaDB**: Can use external MariaDB instead of SQLite for better performance

---

## Backup Components

### 1. Data PVC (Critical)

**Location**: `/app/data` (default)

**Contains**:
- `kuma.db` - SQLite database with all monitor configs, uptime history, notifications
- `upload/` - Custom icons, logos for status pages
- `config/` - Additional configuration files

**Backup Method**: Direct tar backup or Restic for incremental backups

**Recovery Priority**: Highest (everything is here)

**Backup Command**:
```bash
make -f make/ops/uptime-kuma.mk uk-backup-data
```

**Size**: 100MB - 2GB (depends on historical data retention)

---

### 2. SQLite Database (Critical)

**File**: `/app/data/kuma.db`

**Contains**:
- Monitor configurations (name, type, URL, interval, timeout, etc.)
- Historical status check results
- Notification provider settings (API keys, webhooks)
- User accounts and authentication
- Status page configurations
- Incident history

**Backup Method**: SQLite `.backup` command for consistency

**Recovery Priority**: Highest (entire application state)

**Backup Command**:
```bash
make -f make/ops/uptime-kuma.mk uk-backup-database
```

**Size**: 50MB - 1GB (grows with historical data)

---

### 3. Configuration (Important)

**Location**: Kubernetes ConfigMaps, Secrets, Helm values

**Contains**:
- Helm chart values
- Kubernetes resource configurations
- RBAC settings
- Ingress configurations

**Backup Method**: `helm get values`, `kubectl get`

**Recovery Priority**: Medium (can be recreated but tedious)

**Backup Command**:
```bash
helm get values uptime-kuma -n default > uptime-kuma-values.yaml
```

**Size**: < 1MB

---

### 4. MariaDB Database (Optional, High Priority)

**Note**: Only relevant if using external MariaDB (`uptimeKuma.database.type: mariadb`)

**Contains**: Same data as SQLite but in MariaDB format

**Backup Method**: mysqldump with --single-transaction

**Recovery Priority**: Critical (if using MariaDB)

**Backup Command**:
```bash
make -f make/ops/uptime-kuma.mk uk-backup-mariadb
```

**Size**: Similar to SQLite (50MB - 1GB)

---

## Backup Methods

### Method 1: Direct PVC Backup (Recommended for Small Deployments)

**Pros**:
- ✅ Simple and fast
- ✅ No external dependencies
- ✅ Works with any storage backend

**Cons**:
- ❌ No incremental backups
- ❌ Full backup every time
- ❌ Requires pod access

**Procedure**:

```bash
# 1. Create backup directory
mkdir -p tmp/uptime-kuma-backups

# 2. Backup data PVC
make -f make/ops/uptime-kuma.mk uk-backup-data

# Output: tmp/uptime-kuma-backups/data-YYYYMMDD-HHMMSS.tar.gz
```

**Manual method** (if Makefile not available):

```bash
# Get pod name
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')

# Create backup
kubectl exec $POD -- tar czf - /app/data | cat > backup-$(date +%Y%m%d-%H%M%S).tar.gz
```

---

### Method 2: Restic Incremental Backups (Recommended for Production)

**Pros**:
- ✅ Incremental backups (only changed data)
- ✅ Deduplication (saves space)
- ✅ Encryption built-in
- ✅ Supports S3, Azure, GCS, local storage

**Cons**:
- ❌ Requires Restic installation
- ❌ More complex setup

**Setup**:

```bash
# 1. Initialize Restic repository (one-time)
export RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-backups/uptime-kuma
export RESTIC_PASSWORD=<secure-password>
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>

restic init

# 2. Create backup
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD -- tar czf - /app/data | \
  restic backup --stdin --stdin-filename uptime-kuma-data.tar.gz

# 3. List backups
restic snapshots

# 4. Restore specific snapshot
restic restore latest --target /restore/
```

**Automated Restic backup via CronJob**:

See [Automation](#automation) section for CronJob template.

---

### Method 3: VolumeSnapshot (Fastest, CSI Required)

**Pros**:
- ✅ Instant snapshots
- ✅ Storage-native (efficient)
- ✅ No pod downtime

**Cons**:
- ❌ Requires CSI driver with snapshot support
- ❌ Storage backend specific

**Procedure**:

```bash
# 1. Create VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: uptime-kuma-data-snapshot
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: uptime-kuma-data
EOF

# 2. Verify snapshot
kubectl get volumesnapshot uptime-kuma-data-snapshot

# 3. Restore from snapshot (creates new PVC)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: uptime-kuma-data-restored
spec:
  dataSource:
    name: uptime-kuma-data-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi
EOF
```

---

### Method 4: SQLite Database-Only Backup

**When to use**: Quick backups without upload files, or when upload directory is managed separately

**Procedure**:

```bash
# Using Makefile
make -f make/ops/uptime-kuma.mk uk-backup-database

# Manual method
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD -- sqlite3 /app/data/kuma.db ".backup /tmp/kuma-backup.db"
kubectl cp $POD:/tmp/kuma-backup.db ./kuma-$(date +%Y%m%d-%H%M%S).db
kubectl exec $POD -- rm /tmp/kuma-backup.db
```

---

## Recovery Procedures

### Full Disaster Recovery

**Scenario**: Complete data loss, need to restore from backup

**Prerequisites**:
- Backup file available
- Helm chart and values.yaml available
- Kubernetes cluster accessible

**Procedure**:

```bash
# 1. Install fresh Uptime Kuma chart
helm install uptime-kuma sb-charts/uptime-kuma -f values.yaml

# 2. Wait for pod to start
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=uptime-kuma --timeout=300s

# 3. Restore data from backup
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=tmp/uptime-kuma-backups/data-20250109-143022.tar.gz

# 4. Restart pod to reload data
kubectl rollout restart deployment/uptime-kuma

# 5. Verify restoration
make -f make/ops/uptime-kuma.mk uk-check-monitors
```

**Recovery Time**: < 30 minutes (RTO)

**Data Loss**: Up to 24 hours (RPO, depending on backup frequency)

---

### Database-Only Recovery

**Scenario**: Database corrupted but upload files intact

**Procedure**:

```bash
# 1. Stop Uptime Kuma
kubectl scale deployment uptime-kuma --replicas=0

# 2. Restore database
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl cp ./kuma-backup.db $POD:/app/data/kuma.db

# 3. Start Uptime Kuma
kubectl scale deployment uptime-kuma --replicas=1

# 4. Verify
make -f make/ops/uptime-kuma.mk uk-check-database
```

---

### Selective Monitor Recovery

**Scenario**: Need to restore specific monitor configurations without full restore

**Procedure**:

```bash
# 1. Extract database from backup
tar xzf data-backup.tar.gz app/data/kuma.db

# 2. Use SQLite to export specific monitors
sqlite3 app/data/kuma.db <<EOF
.mode insert
.output monitors.sql
SELECT * FROM monitor WHERE name LIKE '%production%';
.quit
EOF

# 3. Import to running instance
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl cp monitors.sql $POD:/tmp/
kubectl exec $POD -- sqlite3 /app/data/kuma.db < /tmp/monitors.sql
```

---

### MariaDB Recovery (if using external database)

**Procedure**:

```bash
# 1. Restore database dump
kubectl exec -it mariadb-pod -- mysql -u uptime_kuma -p uptime_kuma < backup.sql

# 2. Restart Uptime Kuma to reconnect
kubectl rollout restart deployment/uptime-kuma
```

---

## Automation

### CronJob for Automated Backups

**Create CronJob** for daily backups at 2 AM:

```yaml
# uptime-kuma-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: uptime-kuma-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: uptime-kuma
          containers:
          - name: backup
            image: alpine:3.18
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache tar gzip
              cd /app/data
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              tar czf /backup/data-${TIMESTAMP}.tar.gz .
              # Keep only last 7 days
              find /backup -name "data-*.tar.gz" -mtime +7 -delete
            volumeMounts:
            - name: data
              mountPath: /app/data
            - name: backup
              mountPath: /backup
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: uptime-kuma-data
          - name: backup
            persistentVolumeClaim:
              claimName: uptime-kuma-backups  # Create this PVC separately
          restartPolicy: OnFailure
```

**Apply**:

```bash
kubectl apply -f uptime-kuma-backup-cronjob.yaml
```

---

### Velero for Cluster-Wide Backups

**Install Velero**:

```bash
velero install \
  --provider aws \
  --bucket uptime-kuma-backups \
  --secret-file ./credentials-velero
```

**Create Backup Schedule**:

```bash
# Daily backups at 3 AM
velero schedule create uptime-kuma-daily \
  --schedule="0 3 * * *" \
  --include-namespaces default \
  --include-resources pvc,pv \
  --selector app.kubernetes.io/name=uptime-kuma
```

**Restore from Velero**:

```bash
# List backups
velero backup get

# Restore specific backup
velero restore create --from-backup uptime-kuma-daily-20250109030000
```

---

## Best Practices

### Backup Frequency

| Component | Frequency | Reason |
|-----------|-----------|--------|
| Data PVC | Daily | Monitor configs change frequently |
| Database | Daily | Historical data accumulates daily |
| Configuration | Weekly | Helm values change infrequently |
| Pre-upgrade | Always | Safety before version changes |

### Retention Policy

**Recommended retention**:
- **Daily backups**: Keep 7 days
- **Weekly backups**: Keep 4 weeks
- **Monthly backups**: Keep 3 months
- **Pre-upgrade backups**: Keep 30 days after upgrade

### Storage Recommendations

**Local backups**: Use separate PVC or node-local storage
**Offsite backups**: S3, Azure Blob, Google Cloud Storage (recommended)
**Encryption**: Always encrypt backups containing notification API keys

### Testing Recovery

**Quarterly recovery tests**:

```bash
# 1. Create test namespace
kubectl create namespace uptime-kuma-test

# 2. Deploy from backup
helm install uptime-kuma-test sb-charts/uptime-kuma \
  -f values.yaml \
  -n uptime-kuma-test

# 3. Restore data
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=backup.tar.gz \
  RELEASE_NAME=uptime-kuma-test \
  NAMESPACE=uptime-kuma-test

# 4. Verify monitors and notifications work
# 5. Cleanup
kubectl delete namespace uptime-kuma-test
```

---

## Troubleshooting

### Common Backup Issues

#### 1. Backup File Too Large

**Symptom**: Backup takes too long or fills storage

**Solution**:
- Clean up old historical data via Uptime Kuma UI (Settings → Maintenance → Shrink Database)
- Use incremental backups (Restic)
- Adjust data retention period in Uptime Kuma settings

```bash
# Check database size
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- du -sh /app/data/kuma.db
```

#### 2. SQLite Database Locked

**Symptom**: `Error: database is locked` during backup

**Solution**: Use SQLite `.backup` command instead of file copy

```bash
# Correct method (waits for lock)
make -f make/ops/uptime-kuma.mk uk-backup-database

# Incorrect method (may fail if locked)
# kubectl cp $POD:/app/data/kuma.db ./backup.db  # DON'T USE
```

#### 3. Restore Fails with Permission Errors

**Symptom**: Restored files not accessible by Uptime Kuma

**Solution**: Fix ownership after restore

```bash
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- chown -R 1000:1000 /app/data
```

#### 4. Notifications Not Working After Restore

**Symptom**: Monitors restored but notifications fail to send

**Cause**: Notification provider API keys/webhooks may be stored in environment variables or external secrets

**Solution**:
1. Verify notification settings in Uptime Kuma UI
2. Re-enter API keys if stored in Kubernetes Secrets
3. Test notification channels individually

#### 5. Monitor History Missing After Restore

**Symptom**: Monitors present but no historical uptime data

**Cause**: Partial database restore or database version mismatch

**Solution**:
- Ensure full database restored (check `kuma.db` file size)
- Verify backup was from same Uptime Kuma version
- Check SQLite integrity: `make -f make/ops/uptime-kuma.mk uk-db-check`

---

## Backup Checklist

### Pre-Backup

- [ ] Verify sufficient backup storage space
- [ ] Confirm backup destination is accessible
- [ ] Check current database size
- [ ] Ensure no active maintenance operations

### Backup Execution

- [ ] Create data PVC backup
- [ ] Create database backup
- [ ] Export Helm values
- [ ] Verify backup files created successfully
- [ ] Check backup file sizes are reasonable
- [ ] Test backup file integrity (extract/decompress)

### Post-Backup

- [ ] Move backups to offsite storage (S3, etc.)
- [ ] Verify backups uploaded successfully
- [ ] Remove old backups per retention policy
- [ ] Document backup location and timestamp
- [ ] Update backup log/tracking system

### Quarterly Recovery Test

- [ ] Deploy test instance in separate namespace
- [ ] Restore from latest backup
- [ ] Verify all monitors present and configured correctly
- [ ] Test notification channels
- [ ] Check historical uptime data integrity
- [ ] Verify status pages render correctly
- [ ] Document recovery time and any issues encountered
- [ ] Cleanup test environment

---

## Recovery Time Objectives (RTO/RPO)

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) | Notes |
|----------|---------------------|---------------------|-------|
| **Data PVC Restore** | < 30 minutes | 24 hours | Full restore from daily backup |
| **Database Restore** | < 15 minutes | 24 hours | Database-only restore |
| **Full Disaster Recovery** | < 1 hour | 24 hours | Fresh deployment + restore |
| **Selective Monitor Recovery** | < 10 minutes | 24 hours | Restore specific monitors |
| **MariaDB Recovery** | < 30 minutes | 24 hours | If using external MariaDB |

**Improving RTO**: Use VolumeSnapshot for instant recovery (< 5 minutes)
**Improving RPO**: Increase backup frequency to hourly (RPO 1 hour)

---

## Additional Resources

- **Uptime Kuma Documentation**: https://github.com/louislam/uptime-kuma/wiki
- **SQLite Backup Commands**: https://www.sqlite.org/backup.html
- **Restic Documentation**: https://restic.readthedocs.io/
- **Velero Documentation**: https://velero.io/docs/
- **Kubernetes VolumeSnapshot**: https://kubernetes.io/docs/concepts/storage/volume-snapshots/

---

**Last Updated**: 2025-12-09
**Chart Version**: v0.4.0
**Uptime Kuma Version**: 1.23.x
