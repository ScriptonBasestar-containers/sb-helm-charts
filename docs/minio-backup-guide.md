# MinIO Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for MinIO object storage deployments.

## Table of Contents

1. [Backup Strategy Overview](#backup-strategy-overview)
2. [Backup Components](#backup-components)
3. [Backup Methods](#backup-methods)
4. [Recovery Procedures](#recovery-procedures)
5. [Automation](#automation)
6. [Testing Backups](#testing-backups)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Backup Strategy Overview

MinIO backup strategy consists of **4 main components**:

1. **Bucket Data** (Critical) - Object storage data
2. **Bucket Metadata** (Critical) - Bucket policies, versioning, lifecycle rules
3. **Configuration** (Important) - Server configuration, environment
4. **IAM Policies** (Important) - Users, groups, policies, access keys

### Backup Priorities

| Component | Priority | Size | Backup Frequency |
|-----------|----------|------|------------------|
| Bucket Data | Critical | Variable (GB-TB) | Daily/Continuous |
| Bucket Metadata | Critical | < 100MB | Daily |
| Configuration | Important | < 10MB | On change |
| IAM Policies | Important | < 10MB | Daily |

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|----------|---------------------|---------------------|
| Bucket metadata restore | < 30 minutes | 24 hours |
| Configuration restore | < 15 minutes | 24 hours |
| IAM policy restore | < 15 minutes | 24 hours |
| Full disaster recovery | < 2 hours | 24 hours |
| Object-level restore | < 1 hour | Real-time (versioning) |

---

## Backup Components

### 1. Bucket Data (Critical)

**What to backup:**
- All objects stored in MinIO buckets
- Object versions (if versioning enabled)
- Object metadata and tags
- Multipart upload parts

**Backup location:**
- Remote MinIO cluster (site replication)
- S3-compatible storage (AWS S3, GCS, Azure Blob)
- Local filesystem (for testing only)
- Tape storage (for long-term archival)

**Backup size estimation:**
```bash
# Get total bucket usage
mc admin info minio-primary | grep "Total Size"

# Get per-bucket size
mc du minio-primary/bucket-name

# List all buckets with sizes
mc ls --recursive --summarize minio-primary
```

### 2. Bucket Metadata (Critical)

**What to backup:**
- Bucket policies and configurations
- Versioning settings
- Lifecycle rules
- Replication configurations
- Encryption settings
- Notification configurations
- Object lock configurations

**Backup commands:**
```bash
# Export all bucket metadata
for bucket in $(mc ls minio-primary | awk '{print $5}'); do
  mc admin policy info minio-primary $bucket > metadata/${bucket}-policy.json
  mc version info minio-primary/$bucket > metadata/${bucket}-version.json
  mc ilm export minio-primary/$bucket > metadata/${bucket}-lifecycle.json
done
```

### 3. Configuration (Important)

**What to backup:**
- Server configuration (config.env)
- Environment variables
- Kubernetes ConfigMap/Secret
- MinIO server arguments
- TLS certificates

**Backup commands:**
```bash
# Backup Kubernetes resources
kubectl get configmap minio-config -n namespace -o yaml > backup/minio-config.yaml
kubectl get secret minio-secret -n namespace -o yaml > backup/minio-secret.yaml
kubectl get statefulset minio -n namespace -o yaml > backup/minio-statefulset.yaml

# Backup MinIO server config
mc admin config export minio-primary > backup/minio-server-config.json
```

### 4. IAM Policies (Important)

**What to backup:**
- User accounts
- Service accounts
- Groups
- Access policies
- Access keys
- STS credentials

**Backup commands:**
```bash
# Export all users
mc admin user list minio-primary --json > backup/users.json

# Export all policies
mc admin policy list minio-primary --json > backup/policies.json

# Export all groups
mc admin group list minio-primary --json > backup/groups.json

# Export specific policy
mc admin policy info minio-primary policy-name > backup/policy-name.json
```

---

## Backup Methods

### Method 1: Site Replication (Recommended for Production)

**Best for:** Multi-site deployments, disaster recovery, real-time replication

**Advantages:**
- Continuous replication (near real-time)
- Automatic failover support
- Metadata replication included
- No scheduled backup windows

**Setup:**
```bash
# Configure site replication between two MinIO clusters
mc admin replicate add minio-primary minio-secondary

# Verify replication status
mc admin replicate status minio-primary

# List replicated buckets
mc admin replicate info minio-primary
```

**Limitations:**
- Requires two MinIO clusters
- Network bandwidth dependent
- Higher infrastructure cost

### Method 2: Bucket Replication

**Best for:** Cross-region backup, selective bucket replication

**Advantages:**
- Granular bucket-level control
- One-way or two-way replication
- Works with any S3-compatible storage
- Lower cost than site replication

**Setup:**
```bash
# Create replication target (remote bucket)
mc mb minio-backup/mybucket-backup

# Enable versioning (required for replication)
mc version enable minio-primary/mybucket
mc version enable minio-backup/mybucket-backup

# Set up replication rule
mc replicate add minio-primary/mybucket \
  --remote-bucket "minio-backup/mybucket-backup" \
  --priority 1

# Verify replication
mc replicate status minio-primary/mybucket
```

**Configuration example:**
```json
{
  "Rules": [
    {
      "ID": "backup-rule",
      "Status": "Enabled",
      "Priority": 1,
      "DeleteMarkerReplication": { "Status": "Enabled" },
      "Destination": {
        "Bucket": "arn:minio:replication::mybucket-backup:*",
        "ReplicationTime": { "Status": "Enabled" }
      }
    }
  ]
}
```

### Method 3: mc mirror (Scheduled Sync)

**Best for:** Periodic backups, one-time migration, simple setups

**Advantages:**
- Simple command-line tool
- Works with any S3-compatible storage
- Can be scheduled with cron
- Bandwidth throttling support

**Backup commands:**
```bash
# Mirror bucket to remote location
mc mirror minio-primary/mybucket s3/backup-bucket

# Mirror with delete sync (dangerous - matches source exactly)
mc mirror --remove minio-primary/mybucket s3/backup-bucket

# Mirror with bandwidth limit
mc mirror --limit-upload 10MiB minio-primary/mybucket s3/backup-bucket

# Mirror multiple buckets
for bucket in $(mc ls minio-primary | awk '{print $5}'); do
  mc mirror minio-primary/$bucket s3/backup-$bucket
done
```

**Cron example (daily backup at 2 AM):**
```bash
# /etc/cron.d/minio-backup
0 2 * * * mc mirror minio-primary/mybucket s3/backup-bucket >> /var/log/minio-backup.log 2>&1
```

### Method 4: mc cp (Object Copy)

**Best for:** Selective backup, specific object restore, testing

**Advantages:**
- Precise object selection
- Supports wildcards and recursive copy
- Fast for small datasets
- No configuration required

**Backup commands:**
```bash
# Copy specific object
mc cp minio-primary/mybucket/file.txt s3/backup-bucket/

# Copy all objects recursively
mc cp --recursive minio-primary/mybucket/ s3/backup-bucket/

# Copy with metadata preservation
mc cp --preserve minio-primary/mybucket/ s3/backup-bucket/

# Copy with encryption
mc cp --encrypt "minio-primary/mybucket/=minio-primary/key" minio-primary/mybucket/file.txt s3/backup-bucket/
```

### Method 5: PVC Snapshots (For Kubernetes)

**Best for:** Quick recovery, testing, development

**Advantages:**
- Instant snapshots (CSI driver dependent)
- Space-efficient (incremental)
- Kubernetes-native
- Fast restore

**Requirements:**
- CSI driver with snapshot support
- VolumeSnapshotClass configured
- Sufficient storage quota

**Snapshot commands:**
```bash
# Create VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: minio-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: data-minio-0
EOF

# List snapshots
kubectl get volumesnapshot -n default

# Restore from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data-restored
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: minio-data-snapshot-20250109-120000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
```

### Method 6: Restic (Incremental Backups)

**Best for:** Long-term retention, cost-effective storage, deduplication

**Advantages:**
- Incremental backups
- Deduplication
- Encryption built-in
- Multiple backend support

**Setup:**
```bash
# Initialize restic repository
export RESTIC_REPOSITORY="s3:https://s3.amazonaws.com/my-backup-bucket/minio-backups"
export RESTIC_PASSWORD="secure-password"
restic init

# Backup MinIO data directory (from within pod)
kubectl exec -n default minio-0 -- restic backup /data

# List backups
restic snapshots

# Restore specific snapshot
restic restore latest --target /tmp/restore
```

---

## Recovery Procedures

### Recovery Scenario 1: Bucket Metadata Restore

**When to use:**
- Bucket policy accidentally deleted
- Lifecycle rules corrupted
- Versioning settings lost

**Recovery steps:**

```bash
# 1. Stop MinIO (optional, for safety)
kubectl scale statefulset minio --replicas=0 -n default

# 2. Restore bucket policy
mc admin policy set minio-primary mybucket < metadata/mybucket-policy.json

# 3. Restore versioning settings
mc version enable minio-primary/mybucket

# 4. Restore lifecycle rules
mc ilm import minio-primary/mybucket < metadata/mybucket-lifecycle.json

# 5. Restart MinIO
kubectl scale statefulset minio --replicas=4 -n default

# 6. Verify restoration
mc admin policy info minio-primary mybucket
mc version info minio-primary/mybucket
mc ilm export minio-primary/mybucket
```

**Recovery time:** < 30 minutes

### Recovery Scenario 2: IAM Policy Restore

**When to use:**
- User accounts lost
- Access policies deleted
- Service account compromised

**Recovery steps:**

```bash
# 1. Restore users
cat backup/users.json | while read user; do
  mc admin user add minio-primary $(echo $user | jq -r '.accessKey') $(echo $user | jq -r '.secretKey')
done

# 2. Restore policies
cat backup/policies.json | while read policy; do
  mc admin policy create minio-primary $(echo $policy | jq -r '.name') - < $(echo $policy | jq -r '.file')
done

# 3. Restore groups
cat backup/groups.json | while read group; do
  mc admin group add minio-primary $(echo $group | jq -r '.name')
  mc admin group attach minio-primary $(echo $group | jq -r '.policy') $(echo $group | jq -r '.name')
done

# 4. Verify restoration
mc admin user list minio-primary
mc admin policy list minio-primary
mc admin group list minio-primary
```

**Recovery time:** < 15 minutes

### Recovery Scenario 3: Configuration Restore

**When to use:**
- Server configuration corrupted
- Environment variables lost
- Kubernetes resources deleted

**Recovery steps:**

```bash
# 1. Restore Kubernetes resources
kubectl apply -f backup/minio-config.yaml
kubectl apply -f backup/minio-secret.yaml

# 2. Restore MinIO server config
mc admin config import minio-primary < backup/minio-server-config.json

# 3. Restart MinIO to apply config
kubectl rollout restart statefulset minio -n default

# 4. Verify configuration
mc admin info minio-primary
kubectl get configmap minio-config -n default -o yaml
```

**Recovery time:** < 15 minutes

### Recovery Scenario 4: Full Disaster Recovery

**When to use:**
- Complete cluster failure
- Data center outage
- Kubernetes cluster destroyed

**Recovery steps:**

```bash
# 1. Deploy new MinIO cluster
helm install minio sb-charts/minio -f values-prod-distributed.yaml -n default

# 2. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n default --timeout=5m

# 3. Restore configuration
kubectl apply -f backup/minio-config.yaml
kubectl apply -f backup/minio-secret.yaml
mc admin config import minio-primary < backup/minio-server-config.json

# 4. Restore IAM policies and users
./restore-iam.sh

# 5. Restore bucket metadata
./restore-buckets.sh

# 6. Restore bucket data (from site replication)
mc admin replicate add minio-primary minio-backup
# OR from backup storage
mc mirror s3/backup-bucket minio-primary/mybucket

# 7. Verify restoration
mc admin info minio-primary
mc ls minio-primary
mc du --recursive minio-primary

# 8. Test access and functionality
mc cp test-file.txt minio-primary/mybucket/
mc ls minio-primary/mybucket/test-file.txt
```

**Recovery time:** < 2 hours (depends on data size)

### Recovery Scenario 5: Object-Level Restore

**When to use:**
- Specific object accidentally deleted
- Object corrupted
- Need previous version

**Recovery steps (with versioning):**

```bash
# 1. List object versions
mc ls --versions minio-primary/mybucket/file.txt

# 2. Download specific version
mc cp --version-id "version-id" minio-primary/mybucket/file.txt restored-file.txt

# 3. Restore to original location
mc cp restored-file.txt minio-primary/mybucket/file.txt

# 4. Verify restoration
mc stat minio-primary/mybucket/file.txt
```

**Recovery steps (without versioning, from backup):**

```bash
# 1. Locate object in backup
mc ls s3/backup-bucket/file.txt

# 2. Restore object
mc cp s3/backup-bucket/file.txt minio-primary/mybucket/

# 3. Verify restoration
mc stat minio-primary/mybucket/file.txt
```

**Recovery time:** < 1 hour

---

## Automation

### Automated Backup CronJob (Kubernetes)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: minio-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: minio/mc:latest
            command:
            - /bin/sh
            - -c
            - |
              # Configure mc
              mc alias set minio-primary http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
              mc alias set backup-storage s3://backup-bucket $AWS_ACCESS_KEY $AWS_SECRET_KEY

              # Backup bucket data
              mc mirror minio-primary s3://backup-bucket/$(date +%Y%m%d)

              # Backup metadata
              mc admin config export minio-primary > /tmp/config.json
              mc cp /tmp/config.json backup-storage/config-$(date +%Y%m%d).json

              # Backup IAM
              mc admin user list minio-primary --json > /tmp/users.json
              mc cp /tmp/users.json backup-storage/users-$(date +%Y%m%d).json
            env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: minio-secret
                  key: root-user
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-secret
                  key: root-password
            - name: AWS_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: aws-access-key
            - name: AWS_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: aws-secret-key
          restartPolicy: OnFailure
```

### Backup Retention Script

```bash
#!/bin/bash
# cleanup-old-backups.sh

BUCKET="backup-bucket"
RETENTION_DAYS=30

# Delete backups older than retention period
mc rm --recursive --force --older-than ${RETENTION_DAYS}d s3://${BUCKET}/

# List remaining backups
mc ls s3://${BUCKET}/

echo "Backup cleanup completed. Backups older than $RETENTION_DAYS days removed."
```

---

## Testing Backups

### Test Plan

1. **Monthly Full Restore Test**
   - Restore to test environment
   - Verify all buckets and objects
   - Test IAM policies and access
   - Measure recovery time

2. **Weekly Metadata Test**
   - Restore bucket policies
   - Restore lifecycle rules
   - Verify replication settings

3. **Daily Verification**
   - Check backup completion
   - Verify backup size
   - Test random object restore

### Test Script

```bash
#!/bin/bash
# test-restore.sh

TEST_BUCKET="test-restore-$(date +%Y%m%d-%H%M%S)"

echo "=== MinIO Backup Test ==="
echo "Creating test bucket: $TEST_BUCKET"

# 1. Create test bucket and upload test file
mc mb minio-primary/$TEST_BUCKET
echo "Test data" > test-file.txt
mc cp test-file.txt minio-primary/$TEST_BUCKET/

# 2. Backup bucket
mc mirror minio-primary/$TEST_BUCKET s3/backup-bucket/$TEST_BUCKET

# 3. Delete original
mc rb --force minio-primary/$TEST_BUCKET

# 4. Restore from backup
mc mirror s3/backup-bucket/$TEST_BUCKET minio-primary/$TEST_BUCKET

# 5. Verify restoration
if mc stat minio-primary/$TEST_BUCKET/test-file.txt > /dev/null 2>&1; then
  echo "✅ Backup test PASSED"
  mc rb --force minio-primary/$TEST_BUCKET
  mc rm --recursive --force s3/backup-bucket/$TEST_BUCKET
else
  echo "❌ Backup test FAILED"
  exit 1
fi
```

---

## Troubleshooting

### Issue 1: Replication Lag

**Symptoms:**
- Objects not appearing in replica
- High replication queue size

**Diagnosis:**
```bash
# Check replication status
mc admin replicate status minio-primary

# Check replication metrics
mc admin prometheus metrics minio-primary | grep replication
```

**Solutions:**
- Increase network bandwidth
- Check replica cluster health
- Verify credentials and permissions
- Review replication rules configuration

### Issue 2: Backup Size Mismatch

**Symptoms:**
- Backup size doesn't match source
- Missing objects in backup

**Diagnosis:**
```bash
# Compare source and backup sizes
mc du --recursive minio-primary/mybucket
mc du --recursive s3/backup-bucket/mybucket

# List objects count
mc ls --recursive minio-primary/mybucket | wc -l
mc ls --recursive s3/backup-bucket/mybucket | wc -l
```

**Solutions:**
- Re-run backup with `--remove` flag (careful!)
- Check for incomplete multipart uploads
- Verify sufficient storage quota
- Review backup script logs

### Issue 3: IAM Restore Failures

**Symptoms:**
- User creation fails
- Policy import errors
- Access denied after restore

**Diagnosis:**
```bash
# Check current IAM state
mc admin user list minio-primary
mc admin policy list minio-primary

# Verify backup file integrity
cat backup/users.json | jq .
cat backup/policies.json | jq .
```

**Solutions:**
- Verify JSON syntax in backup files
- Check for duplicate users/policies
- Ensure admin credentials are correct
- Import policies before attaching to users

### Issue 4: Slow Backup Performance

**Symptoms:**
- Backup takes too long
- High CPU/memory usage
- Network saturation

**Diagnosis:**
```bash
# Check backup progress
mc mirror --watch minio-primary/mybucket s3/backup-bucket/

# Monitor MinIO metrics
mc admin prometheus metrics minio-primary

# Check network bandwidth
iftop -i eth0
```

**Solutions:**
- Use site replication for large datasets
- Implement bandwidth limiting
- Schedule backups during off-peak hours
- Use incremental backup tools (restic)

---

## Best Practices

### DO ✅

- ✅ **Enable versioning** on critical buckets for point-in-time recovery
- ✅ **Use site replication** for production HA and DR
- ✅ **Test restores regularly** (monthly full restore test)
- ✅ **Encrypt backups** at rest and in transit
- ✅ **Monitor backup jobs** for failures and alerts
- ✅ **Document recovery procedures** and keep updated
- ✅ **Store backups off-site** (3-2-1 backup rule)
- ✅ **Automate backup verification** with scripts
- ✅ **Implement retention policies** to manage storage costs
- ✅ **Backup IAM policies** separately from data

### DON'T ❌

- ❌ **Don't rely on single backup method** - use multiple strategies
- ❌ **Don't skip backup testing** - untested backups are useless
- ❌ **Don't store backups in same cluster** - defeats DR purpose
- ❌ **Don't ignore backup failures** - investigate immediately
- ❌ **Don't use `--remove` carelessly** - can delete data permanently
- ❌ **Don't forget to backup metadata** - policies and configs are critical
- ❌ **Don't exceed RTO/RPO targets** - adjust strategy if needed
- ❌ **Don't hardcode credentials** in scripts - use secrets
- ❌ **Don't backup temporary data** - exclude .tmp, cache files
- ❌ **Don't skip encryption** - protect sensitive data

### 3-2-1 Backup Rule for MinIO

1. **3 copies of data**
   - Primary: MinIO production cluster
   - Secondary: Replicated MinIO cluster (site replication)
   - Tertiary: Cloud storage backup (S3/GCS)

2. **2 different media types**
   - Local: Kubernetes PVC (SSD/NVMe)
   - Remote: Object storage (S3-compatible)

3. **1 copy off-site**
   - Different data center
   - Different cloud region
   - Different cloud provider

### Security Recommendations

- Use encryption for backups (SSE-S3, SSE-KMS)
- Rotate backup credentials regularly
- Implement access controls on backup storage
- Audit backup access logs
- Use immutable backups (WORM) for compliance

---

**See Also:**
- [MinIO Upgrade Guide](minio-upgrade-guide.md)
- MinIO README - Operations section
- MinIO values.yaml - Backup configuration

**Last Updated:** 2025-12-09
