# MongoDB Backup & Recovery Guide

This guide provides comprehensive MongoDB backup and recovery procedures for the sb-helm-charts MongoDB deployment.

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Methods](#backup-methods)
5. [Recovery Procedures](#recovery-procedures)
6. [Automation](#automation)
7. [Testing Backups](#testing-backups)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Overview

MongoDB backups are critical for data protection and disaster recovery. This guide covers both standalone and replica set deployments.

### Backup Scope

**What Gets Backed Up:**
- Database data (all databases or selective)
- Indexes
- Oplog (replica sets)
- Configuration
- Users and roles
- Replica set configuration

**What Doesn't Need Backup:**
- Temporary data
- Cached data
- System databases (can be recreated)

### RTO/RPO Targets

| Backup Component | RTO (Recovery Time) | RPO (Recovery Point) | Priority |
|------------------|---------------------|----------------------|----------|
| Database Dump | < 1 hour | 24 hours | Critical |
| Oplog Backup | < 30 minutes | 15 minutes | Critical (replica sets) |
| Configuration | < 15 minutes | 24 hours | Important |
| Users & Roles | < 15 minutes | 24 hours | Important |
| Full Disaster Recovery | < 2 hours | 24 hours | Critical |
| Point-in-Time Recovery | < 1 hour | 15 minutes | Critical (replica sets) |

## Backup Strategy

### Components to Backup

MongoDB backups consist of 4 primary components:

| Component | Size Estimate | Frequency | Method | Priority |
|-----------|---------------|-----------|---------|----------|
| **Database Data** | Variable (GB-TB) | Daily | mongodump, snapshots | Critical |
| **Oplog** | 10-100 MB/day | Continuous | mongodump --oplog | Critical (replica sets) |
| **Configuration** | < 10 MB | Weekly | ConfigMap/Secret export | Important |
| **Users & Roles** | < 1 MB | Weekly | mongodump --authenticationDatabase | Important |

### Recommended Backup Schedule

**Production Environment:**
```
Daily:   Full database dump (mongodump)
Hourly:  Oplog backup (replica sets only)
Weekly:  Configuration backup
Weekly:  Users & roles backup
Monthly: Full disaster recovery test
```

**Development/Staging:**
```
Daily:   Full database dump
Weekly:  Configuration backup
```

## Backup Components

### 1. Database Data Backup

**Critical Component** - Full database dump using mongodump.

**What It Includes:**
- All databases (or selected databases)
- All collections
- All indexes
- Document data
- Collection metadata

**Backup Command:**
```bash
# Access MongoDB pod
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

# Full backup (all databases)
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --out=/tmp/backup

# Copy backup from pod
kubectl cp -n default $POD:/tmp/backup ./mongodb-backup-$(date +%Y%m%d-%H%M%S)

# Clean up pod
kubectl exec -n default $POD -- rm -rf /tmp/backup
```

**Selective Backup (specific database):**
```bash
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=myapp \
  --out=/tmp/backup
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-backup-database
```

### 2. Oplog Backup (Replica Sets)

**Critical Component** - Oplog backup for point-in-time recovery (PITR).

**What It Includes:**
- Operation log entries
- Timestamp information
- All database operations since last backup

**Oplog Backup Command:**
```bash
# Backup with oplog (replica sets only)
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --oplog \
  --out=/tmp/backup-oplog

# Copy backup from pod
kubectl cp -n default $POD:/tmp/backup-oplog ./mongodb-oplog-$(date +%Y%m%d-%H%M%S)
```

**Continuous Oplog Archiving:**
```bash
# Archive oplog continuously (for PITR)
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=local \
  --collection=oplog.rs \
  --out=/tmp/oplog-archive
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-backup-oplog
```

### 3. Configuration Backup

**Important Component** - MongoDB configuration and Kubernetes resources.

**What It Includes:**
- mongod.conf configuration
- ConfigMaps
- Secrets
- Replica set configuration
- Environment variables

**Backup Commands:**
```bash
# Backup ConfigMaps
kubectl get configmap -n default mongodb-config -o yaml > mongodb-configmap-$(date +%Y%m%d).yaml

# Backup Secrets
kubectl get secret -n default mongodb-secret -o yaml > mongodb-secret-$(date +%Y%m%d).yaml

# Backup mongod.conf from pod
kubectl exec -n default $POD -- cat /etc/mongod.conf > mongod-conf-$(date +%Y%m%d).conf

# Backup replica set configuration (replica sets only)
kubectl exec -n default $POD -- mongo --eval "rs.conf()" > rs-config-$(date +%Y%m%d).json
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-backup-config
```

### 4. Users & Roles Backup

**Important Component** - Authentication and authorization data.

**What It Includes:**
- User accounts
- Roles and permissions
- Authentication database

**Backup Commands:**
```bash
# Backup users and roles
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=admin \
  --collection=system.users \
  --collection=system.roles \
  --out=/tmp/users-backup

kubectl cp -n default $POD:/tmp/users-backup ./mongodb-users-$(date +%Y%m%d-%H%M%S)
```

**Export Users as JSON:**
```bash
# List all users
kubectl exec -n default $POD -- mongo admin --eval "db.getUsers()" > users-$(date +%Y%m%d).json

# List all roles
kubectl exec -n default $POD -- mongo admin --eval "db.getRoles({showPrivileges: true})" > roles-$(date +%Y%m%d).json
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-backup-users
```

## Backup Methods

### Method 1: mongodump (Recommended)

**Best For:** Regular backups, point-in-time recovery, selective backups

**Advantages:**
- ✅ Works with any MongoDB version
- ✅ Selective database/collection backup
- ✅ Oplog support for PITR
- ✅ Human-readable BSON/JSON format
- ✅ Cross-platform compatibility

**Disadvantages:**
- ❌ Slower than snapshots for large datasets
- ❌ Requires database access during backup
- ❌ Impact on database performance

**Full Backup Procedure:**
```bash
# 1. Create backup directory
mkdir -p /backups/mongodb/$(date +%Y%m%d)

# 2. Run mongodump with oplog (replica sets)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --oplog \
  --gzip \
  --out=/tmp/backup

# 3. Copy backup from pod
kubectl cp -n default $POD:/tmp/backup /backups/mongodb/$(date +%Y%m%d)/

# 4. Clean up pod
kubectl exec -n default $POD -- rm -rf /tmp/backup

# 5. Verify backup
ls -lh /backups/mongodb/$(date +%Y%m%d)/
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-full-backup
```

### Method 2: PVC Snapshots (VolumeSnapshot)

**Best For:** Fast backups, disaster recovery, infrastructure-level backups

**Advantages:**
- ✅ Very fast (snapshot-based)
- ✅ No performance impact on database
- ✅ Storage-level consistency
- ✅ Instant snapshot creation

**Disadvantages:**
- ❌ Requires CSI driver support
- ❌ Platform-specific
- ❌ May require database quiesce for consistency

**Prerequisites:**
```bash
# Check if VolumeSnapshot CRD is available
kubectl get crd volumesnapshots.snapshot.storage.k8s.io

# Check available VolumeSnapshotClasses
kubectl get volumesnapshotclass
```

**Create VolumeSnapshot:**
```yaml
# mongodb-snapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mongodb-snapshot-20250109
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass  # Your VolumeSnapshotClass
  source:
    persistentVolumeClaimName: data-mongodb-0
```

**Apply Snapshot:**
```bash
# Create snapshot
kubectl apply -f mongodb-snapshot.yaml

# Check snapshot status
kubectl get volumesnapshot mongodb-snapshot-20250109 -o yaml

# List all MongoDB snapshots
kubectl get volumesnapshot -n default | grep mongodb
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-snapshot-create
```

### Method 3: Filesystem Copy (Hot Backup)

**Best For:** Quick backups, testing, development environments

**Advantages:**
- ✅ Simple and fast
- ✅ No special tools required
- ✅ Full filesystem copy

**Disadvantages:**
- ❌ Requires database lock for consistency
- ❌ Not suitable for large databases
- ❌ May cause brief downtime

**Backup Procedure with fsync Lock:**
```bash
# 1. Lock database (ensure consistency)
kubectl exec -n default $POD -- mongo admin \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --eval "db.fsyncLock()"

# 2. Copy data directory
kubectl exec -n default $POD -- tar czf /tmp/data-backup.tar.gz /data/db

# 3. Unlock database
kubectl exec -n default $POD -- mongo admin \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --eval "db.fsyncUnlock()"

# 4. Copy backup from pod
kubectl cp -n default $POD:/tmp/data-backup.tar.gz ./mongodb-fs-backup-$(date +%Y%m%d).tar.gz

# 5. Clean up
kubectl exec -n default $POD -- rm /tmp/data-backup.tar.gz
```

### Method 4: Replica Set Delayed Secondary

**Best For:** Continuous backup, protection against logical errors

**Advantages:**
- ✅ Continuous replication
- ✅ Protection against accidental deletions
- ✅ Time-delayed recovery window
- ✅ No impact on primary

**Disadvantages:**
- ❌ Requires replica set
- ❌ Additional infrastructure
- ❌ Storage overhead

**Configuration:**
```javascript
// Configure delayed secondary (1 hour delay)
cfg = rs.conf()
cfg.members[2].priority = 0
cfg.members[2].hidden = true
cfg.members[2].slaveDelay = 3600  // 1 hour delay
rs.reconfig(cfg)
```

**Verify Delayed Secondary:**
```bash
kubectl exec -n default mongodb-2 -- mongo --eval "rs.printSlaveReplicationInfo()"
```

### Method 5: MongoDB Cloud Manager / Ops Manager

**Best For:** Enterprise deployments, automated backups, compliance

**Advantages:**
- ✅ Automated backup scheduling
- ✅ Point-in-time recovery
- ✅ Centralized management
- ✅ Compliance reporting

**Disadvantages:**
- ❌ Additional cost
- ❌ External dependency
- ❌ Requires internet access

**Setup:**
```bash
# Install Ops Manager agent (example)
kubectl exec -n default $POD -- curl -OL https://downloads.mongodb.com/on-prem-mms/agent/automation-agent.rpm
kubectl exec -n default $POD -- rpm -U automation-agent.rpm
```

## Recovery Procedures

### 1. Full Database Restore (mongorestore)

**Use Case:** Complete database recovery from mongodump backup

**Recovery Time:** < 1 hour (depends on data size)

**Procedure:**
```bash
# 1. Identify backup to restore
ls -lh /backups/mongodb/20250109/

# 2. Get MongoDB pod
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

# 3. Copy backup to pod
kubectl cp /backups/mongodb/20250109/ $POD:/tmp/restore/

# 4. Stop applications (optional but recommended)
kubectl scale deployment myapp --replicas=0

# 5. Restore database
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --drop \
  /tmp/restore/

# 6. Verify data
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('listDatabases')"

# 7. Restart applications
kubectl scale deployment myapp --replicas=3

# 8. Clean up
kubectl exec -n default $POD -- rm -rf /tmp/restore/
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-restore-database FILE=/backups/mongodb/20250109/
```

### 2. Point-in-Time Recovery (PITR)

**Use Case:** Recover to specific point in time using oplog

**Recovery Time:** < 1 hour

**Procedure:**
```bash
# 1. Restore base backup
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --drop \
  /tmp/restore/base-backup/

# 2. Apply oplog to specific timestamp
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --oplogReplay \
  --oplogLimit="1641024000:1" \
  /tmp/restore/oplog/

# 3. Verify recovery point
kubectl exec -n default $POD -- mongo --eval "db.getCollectionNames()"
```

**Timestamp Format:**
- Format: `<seconds>:<increment>`
- Example: `1641024000:1` = January 1, 2022 12:00:00 UTC

### 3. Selective Database/Collection Restore

**Use Case:** Restore specific database or collection

**Recovery Time:** < 30 minutes

**Procedure:**
```bash
# Restore specific database
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=myapp \
  --drop \
  /tmp/restore/myapp/

# Restore specific collection
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=myapp \
  --collection=users \
  /tmp/restore/myapp/users.bson
```

### 4. Configuration Restore

**Use Case:** Restore MongoDB configuration

**Recovery Time:** < 15 minutes

**Procedure:**
```bash
# 1. Restore ConfigMaps
kubectl apply -f mongodb-configmap-20250109.yaml

# 2. Restore Secrets
kubectl apply -f mongodb-secret-20250109.yaml

# 3. Restart MongoDB pods to apply configuration
kubectl rollout restart statefulset mongodb -n default

# 4. Wait for rollout
kubectl rollout status statefulset mongodb -n default

# 5. Verify configuration
kubectl exec -n default $POD -- cat /etc/mongod.conf
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-restore-config FILE=mongodb-configmap-20250109.yaml
```

### 5. Users & Roles Restore

**Use Case:** Restore user accounts and permissions

**Recovery Time:** < 15 minutes

**Procedure:**
```bash
# 1. Copy users backup to pod
kubectl cp /backups/mongodb/users-20250109/ $POD:/tmp/users-restore/

# 2. Restore users and roles
kubectl exec -n default $POD -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --db=admin \
  --collection=system.users \
  --collection=system.roles \
  /tmp/users-restore/admin/

# 3. Verify users
kubectl exec -n default $POD -- mongo admin --eval "db.getUsers()"

# 4. Clean up
kubectl exec -n default $POD -- rm -rf /tmp/users-restore/
```

### 6. Disaster Recovery from VolumeSnapshot

**Use Case:** Complete disaster recovery using storage snapshots

**Recovery Time:** < 2 hours

**Procedure:**
```bash
# 1. Create PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-mongodb-0-restored
  namespace: default
spec:
  storageClassName: fast-ssd
  dataSource:
    name: mongodb-snapshot-20250109
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF

# 2. Update StatefulSet to use new PVC (or create new deployment)
# Edit volumeClaimTemplates in StatefulSet

# 3. Restart MongoDB
kubectl rollout restart statefulset mongodb -n default

# 4. Verify data
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('listDatabases')"
```

## Automation

### CronJob for Daily Backups

```yaml
# mongodb-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: mongodb-backup
          containers:
          - name: backup
            image: mongo:7.0
            command:
            - /bin/bash
            - -c
            - |
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              mongodump \
                --host=mongodb.default.svc.cluster.local \
                --username=root \
                --password=$MONGO_ROOT_PASSWORD \
                --authenticationDatabase=admin \
                --oplog \
                --gzip \
                --out=/backup/$TIMESTAMP
              
              # Upload to S3 (example)
              aws s3 cp /backup/$TIMESTAMP s3://my-backups/mongodb/$TIMESTAMP/ --recursive
            env:
            - name: MONGO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongodb-secret
                  key: root-password
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            emptyDir: {}
          restartPolicy: OnFailure
```

### Backup Retention Script

```bash
#!/bin/bash
# mongodb-backup-retention.sh

BACKUP_DIR="/backups/mongodb"
RETENTION_DAYS=30

# Delete backups older than retention period
find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# Keep last 7 daily backups
ls -t $BACKUP_DIR | tail -n +8 | xargs -I {} rm -rf $BACKUP_DIR/{}

echo "Backup retention cleanup completed"
```

### S3/MinIO Upload Script

```bash
#!/bin/bash
# upload-to-s3.sh

BACKUP_DIR="/backups/mongodb/$(date +%Y%m%d)"
S3_BUCKET="s3://my-backups/mongodb/"

# Upload to S3
aws s3 sync $BACKUP_DIR $S3_BUCKET$(date +%Y%m%d)/ \
  --storage-class STANDARD_IA \
  --only-show-errors

# Verify upload
aws s3 ls $S3_BUCKET$(date +%Y%m%d)/

echo "Backup uploaded to S3: $S3_BUCKET$(date +%Y%m%d)/"
```

## Testing Backups

### Backup Validation Checklist

**Monthly Backup Test Plan:**

1. **Integrity Check:**
   ```bash
   # Verify backup files exist and are not corrupted
   ls -lh /backups/mongodb/20250109/
   
   # Check backup size (should not be 0 or suspiciously small)
   du -sh /backups/mongodb/20250109/
   ```

2. **Restore Test (Test Environment):**
   ```bash
   # Restore to test MongoDB instance
   kubectl exec -n test mongodb-test-0 -- mongorestore \
     --drop \
     /tmp/backup/
   
   # Verify data integrity
   kubectl exec -n test mongodb-test-0 -- mongo --eval "db.stats()"
   ```

3. **Application Test:**
   ```bash
   # Connect application to restored database
   # Verify application functionality
   curl http://test-app/health
   ```

4. **Performance Test:**
   ```bash
   # Check restore time
   time kubectl exec -n test mongodb-test-0 -- mongorestore /tmp/backup/
   
   # Verify RTO target (< 1 hour)
   ```

### Automated Backup Test Script

```bash
#!/bin/bash
# test-mongodb-backup.sh

BACKUP_FILE="/backups/mongodb/20250109"
TEST_NAMESPACE="test"

echo "=== MongoDB Backup Test ==="

# 1. Create test MongoDB instance
helm install mongodb-test sb-charts/mongodb \
  --namespace $TEST_NAMESPACE \
  --set persistence.size=10Gi

# 2. Wait for pod ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb -n $TEST_NAMESPACE --timeout=300s

# 3. Copy backup to test pod
POD=$(kubectl get pods -n $TEST_NAMESPACE -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl cp $BACKUP_FILE $TEST_NAMESPACE/$POD:/tmp/backup/

# 4. Restore backup
kubectl exec -n $TEST_NAMESPACE $POD -- mongorestore --drop /tmp/backup/

# 5. Verify databases
kubectl exec -n $TEST_NAMESPACE $POD -- mongo --eval "db.adminCommand('listDatabases')"

# 6. Cleanup
helm uninstall mongodb-test -n $TEST_NAMESPACE

echo "✅ Backup test completed successfully"
```

## Troubleshooting

### Issue 1: mongodump Connection Refused

**Symptoms:**
```
Error connecting to MongoDB: connection refused
```

**Diagnosis:**
```bash
# Check MongoDB pod status
kubectl get pods -n default -l app.kubernetes.io/name=mongodb

# Check MongoDB logs
kubectl logs -n default mongodb-0 --tail=50

# Check service
kubectl get svc mongodb -n default
```

**Solutions:**
```bash
# Ensure MongoDB is running
kubectl rollout status statefulset mongodb -n default

# Verify credentials
kubectl get secret mongodb-secret -o yaml

# Test connection
kubectl exec -n default mongodb-0 -- mongo --eval "db.adminCommand('ping')"
```

### Issue 2: Insufficient Disk Space

**Symptoms:**
```
Error: no space left on device
```

**Diagnosis:**
```bash
# Check pod disk usage
kubectl exec -n default mongodb-0 -- df -h

# Check PVC capacity
kubectl get pvc -n default
```

**Solutions:**
```bash
# Clean up old backups
kubectl exec -n default mongodb-0 -- rm -rf /tmp/backup/*

# Expand PVC (if supported)
kubectl patch pvc data-mongodb-0 -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# Use external backup location (S3/MinIO)
```

### Issue 3: Oplog Too Small for PITR

**Symptoms:**
```
Error: oplog is too small to perform point-in-time recovery
```

**Diagnosis:**
```bash
# Check oplog size
kubectl exec -n default mongodb-0 -- mongo --eval "db.getReplicationInfo()"
```

**Solutions:**
```bash
# Increase oplog size (requires restart)
# Add to mongod.conf:
# replication:
#   oplogSizeMB: 2048

# Restart MongoDB
kubectl rollout restart statefulset mongodb -n default
```

### Issue 4: Restore Fails Due to Index Conflicts

**Symptoms:**
```
Error: duplicate key error on index
```

**Solutions:**
```bash
# Use --drop flag to drop existing collections
kubectl exec -n default $POD -- mongorestore --drop /tmp/restore/

# Or manually drop database first
kubectl exec -n default $POD -- mongo --eval "db.dropDatabase()"
```

## Best Practices

### 1. Backup Strategy

**DO:**
- ✅ Implement 3-2-1 backup rule (3 copies, 2 different media, 1 offsite)
- ✅ Test backups monthly in isolated environment
- ✅ Use oplog for point-in-time recovery (replica sets)
- ✅ Automate backups with CronJobs
- ✅ Monitor backup success/failure
- ✅ Document recovery procedures
- ✅ Keep backups encrypted at rest

**DON'T:**
- ❌ Store backups only on same cluster
- ❌ Skip backup testing
- ❌ Run backups during peak hours
- ❌ Ignore backup failures
- ❌ Keep unlimited backups (manage retention)

### 2. Security

**DO:**
- ✅ Encrypt backup files at rest
- ✅ Use secure transport (TLS) for backup transfers
- ✅ Restrict access to backup files (RBAC)
- ✅ Rotate backup encryption keys
- ✅ Audit backup access logs

**DON'T:**
- ❌ Store backups unencrypted
- ❌ Use weak credentials for backup access
- ❌ Allow public access to backup storage

### 3. Performance

**DO:**
- ✅ Schedule backups during low-traffic periods
- ✅ Use secondaries for backups (replica sets)
- ✅ Monitor backup performance metrics
- ✅ Use compression (--gzip) for large backups
- ✅ Use incremental backups when possible

**DON'T:**
- ❌ Run backups on primary during peak hours
- ❌ Run multiple concurrent backups
- ❌ Ignore backup impact on database performance

### 4. Monitoring

**Key Metrics to Monitor:**
- Backup completion time
- Backup file size
- Backup success/failure rate
- Storage usage
- Restore test results

**Alerting Rules:**
```yaml
# Prometheus alert example
- alert: MongoDBBackupFailed
  expr: mongodb_backup_last_success_timestamp < (time() - 86400)
  for: 1h
  annotations:
    summary: "MongoDB backup failed for {{ $labels.instance }}"
```

### 5. Documentation

**Maintain Documentation For:**
- Backup schedule and retention policy
- Recovery procedures for each backup type
- RTO/RPO targets
- Backup storage locations
- Contact information for backup administrators
- Disaster recovery runbook

---

**Last Updated:** 2025-12-09
**Chart Version:** v0.4.0
**MongoDB Version:** 7.0+
