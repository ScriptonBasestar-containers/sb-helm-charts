# Grafana Mimir Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for Grafana Mimir deployed via the `sb-helm-charts/mimir` chart.

---

## Table of Contents

1. [Backup Strategy Overview](#backup-strategy-overview)
2. [Backup Components](#backup-components)
3. [Backup Procedures](#backup-procedures)
4. [Recovery Procedures](#recovery-procedures)
5. [Backup Automation](#backup-automation)
6. [RTO/RPO Targets](#rtorpo-targets)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Backup Strategy Overview

Grafana Mimir backup consists of **three critical components**:

1. **Block Storage** (TSDB blocks from ingester, compactor, store-gateway)
2. **Configuration** (Mimir YAML configuration, runtime config, tenant limits)
3. **Data Volumes** (PVC snapshots for disaster recovery)

**Why three components?**

- **Block storage**: Time-series data (metrics, samples, labels)
- **Configuration**: Operational settings (storage backend, limits, multi-tenancy)
- **Data volumes**: Complete state preservation (WAL, blocks, compactor state)

---

## Backup Components

### 1. Block Storage

**What it backs up:**
- TSDB blocks from all components:
  - Ingester blocks (active data, 2-hour blocks)
  - Compactor blocks (compacted historical data)
  - Store-gateway blocks (queryable historical data)
- Block metadata (meta.json files)
- Tenant-specific blocks (when multi-tenancy enabled)

**Storage locations (depending on backend):**
- **Filesystem mode**: `/data/blocks/` within PVCs
- **S3/MinIO**: Configured S3 bucket (`mimir-blocks`)
- **GCS**: Google Cloud Storage bucket
- **Azure**: Azure Blob Storage container

**Backup strategy by storage backend:**

#### Filesystem Backend (Dev/Test)
```bash
# Backup blocks directory
make -f make/ops/mimir.mk mimir-backup-blocks

# Equivalent manual command:
kubectl exec mimir-0 -- tar czf /tmp/blocks-backup.tar.gz /data/blocks/
kubectl cp mimir-0:/tmp/blocks-backup.tar.gz ./tmp/mimir-backups/blocks-$(date +%Y%m%d-%H%M%S).tar.gz
```

#### S3/MinIO Backend (Production)
```bash
# S3 bucket snapshots (recommended for production)
aws s3 sync s3://mimir-blocks s3://mimir-blocks-backup-$(date +%Y%m%d)

# Or use AWS Backup for automated S3 bucket backups
# Or versioning-enabled S3 buckets for point-in-time recovery
```

**Advantages:**
- Point-in-time recovery for metrics data
- Tenant-specific restore (multi-tenancy mode)
- Incremental backups (only new blocks since last backup)

**Makefile commands:**
```bash
# Backup blocks (filesystem mode)
make -f make/ops/mimir.mk mimir-backup-blocks

# Backup blocks with verification
make -f make/ops/mimir.mk mimir-backup-blocks-verify

# List backed up blocks
make -f make/ops/mimir.mk mimir-list-block-backups
```

---

### 2. Configuration

**What it backs up:**
- Mimir configuration YAML (`/etc/mimir/mimir.yaml`)
- Runtime configuration (if enabled)
- Tenant limits configuration
- Alert rules (if using Mimir ruler)
- ConfigMap and Secret references

**Configuration components:**
1. **Static configuration** - mimir.yaml from ConfigMap
2. **Runtime config** - Dynamic configuration (optional)
3. **Tenant limits** - Per-tenant resource limits
4. **Alert rules** - Ruler alert rules (if enabled)

**Backup procedures:**

```bash
# Backup all configuration
make -f make/ops/mimir.mk mimir-backup-config

# Individual component backups:

# 1. Backup Mimir YAML configuration
kubectl get configmap mimir-config -o yaml > mimir-config-$(date +%Y%m%d).yaml

# 2. Backup runtime configuration (if enabled)
kubectl exec mimir-0 -- curl -s http://localhost:8080/runtime_config > runtime-config-$(date +%Y%m%d).yaml

# 3. Backup tenant limits
kubectl exec mimir-0 -- cat /etc/mimir/overrides.yaml > tenant-limits-$(date +%Y%m%d).yaml

# 4. Backup alert rules (if ruler enabled)
kubectl get configmap mimir-ruler-rules -o yaml > ruler-rules-$(date +%Y%m%d).yaml
```

**Makefile commands:**
```bash
# Backup all configuration
make -f make/ops/mimir.mk mimir-backup-config

# Backup configuration to specific directory
make -f make/ops/mimir.mk mimir-backup-config DIR=./backups/config-20231127

# Verify configuration backup
make -f make/ops/mimir.mk mimir-backup-config-verify DIR=./backups/config-20231127
```

---

### 3. Data Volumes (PVC Snapshots)

**What it backs up:**
- Complete PVC state:
  - `/data/ingester` - WAL and active blocks
  - `/data/compactor` - Compaction state
  - `/data/store-gateway` - Block indexes
  - `/data/ruler` - Rule evaluation state (if enabled)

**Use cases:**
- Disaster recovery (complete cluster loss)
- Kubernetes cluster migration
- Quick restore to known-good state

**VolumeSnapshot requirements:**
- CSI driver with snapshot support (e.g., AWS EBS CSI, GCE PD CSI)
- VolumeSnapshotClass configured
- Sufficient storage quota for snapshots

**Backup procedures:**

```bash
# Create VolumeSnapshot for Mimir PVC
make -f make/ops/mimir.mk mimir-create-pvc-snapshot

# List all VolumeSnapshots
kubectl get volumesnapshots -l app.kubernetes.io/name=mimir

# Verify snapshot readyToUse status
kubectl get volumesnapshot mimir-snapshot-20231127 -o jsonpath='{.status.readyToUse}'
```

**Manual VolumeSnapshot creation:**

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mimir-snapshot-20231127
spec:
  volumeSnapshotClassName: csi-aws-vsc  # Your VolumeSnapshotClass
  source:
    persistentVolumeClaimName: data-mimir-0
```

**Makefile commands:**
```bash
# Create PVC snapshot
make -f make/ops/mimir.mk mimir-create-pvc-snapshot

# List PVC snapshots
make -f make/ops/mimir.mk mimir-list-pvc-snapshots

# Restore from PVC snapshot
make -f make/ops/mimir.mk mimir-restore-from-snapshot SNAPSHOT_NAME=mimir-snapshot-20231127
```

---

## Backup Procedures

### Full Backup Workflow

**Comprehensive backup of all components:**

```bash
# Step 1: Pre-backup health check
make -f make/ops/mimir.mk mimir-health-check

# Step 2: Backup all components
make -f make/ops/mimir.mk mimir-backup-all

# Step 3: Verify backup integrity
make -f make/ops/mimir.mk mimir-backup-verify DIR=./tmp/mimir-backups/backup-$(date +%Y%m%d)

# Step 4: Upload to remote storage (optional)
aws s3 sync ./tmp/mimir-backups/backup-$(date +%Y%m%d) s3://my-backup-bucket/mimir/
```

**What `mimir-backup-all` does:**

1. Creates timestamped backup directory
2. Backs up block storage (filesystem or S3 metadata)
3. Backs up all configuration files
4. Creates PVC snapshots (if supported)
5. Generates backup manifest with checksums
6. Validates backup integrity

---

### Incremental Backup Strategy

**For production environments with large data volumes:**

```bash
# Daily: Block storage backup (incremental - only new blocks)
0 2 * * * make -f make/ops/mimir.mk mimir-backup-blocks

# Weekly: Full configuration backup
0 3 * * 0 make -f make/ops/mimir.mk mimir-backup-config

# Weekly: PVC snapshots
0 4 * * 0 make -f make/ops/mimir.mk mimir-create-pvc-snapshot

# Monthly: Full backup with verification
0 5 1 * * make -f make/ops/mimir.mk mimir-backup-all
```

---

### Backup Storage Recommendations

**S3/Object Storage (Production):**
```bash
# Enable versioning for S3 bucket
aws s3api put-bucket-versioning \
  --bucket mimir-blocks \
  --versioning-configuration Status=Enabled

# Enable lifecycle policies for old versions
aws s3api put-bucket-lifecycle-configuration \
  --bucket mimir-blocks \
  --lifecycle-configuration file://lifecycle.json

# lifecycle.json example:
{
  "Rules": [{
    "Id": "ExpireOldVersions",
    "Status": "Enabled",
    "NoncurrentVersionExpiration": { "NoncurrentDays": 90 }
  }]
}
```

**Local Backup Storage (Dev/Test):**
```bash
# Create backup directory structure
mkdir -p /backups/mimir/{blocks,config,snapshots}

# Set retention policy (keep last 7 days)
find /backups/mimir/blocks -type f -mtime +7 -delete
```

---

## Recovery Procedures

### Scenario 1: Configuration Recovery

**Use case:** Configuration corruption or accidental changes

```bash
# Step 1: Stop Mimir (optional, for consistency)
kubectl scale statefulset mimir --replicas=0

# Step 2: Restore configuration from backup
kubectl apply -f backups/config-20231127/mimir-config.yaml

# Step 3: Verify configuration
kubectl get configmap mimir-config -o yaml

# Step 4: Restart Mimir
kubectl scale statefulset mimir --replicas=1

# Step 5: Verify health
make -f make/ops/mimir.mk mimir-health-check
```

**Makefile command:**
```bash
# Restore configuration from backup directory
make -f make/ops/mimir.mk mimir-restore-config DIR=./backups/config-20231127
```

---

### Scenario 2: Block Storage Recovery (Filesystem Mode)

**Use case:** Data corruption or accidental deletion

```bash
# Step 1: Stop Mimir
kubectl scale statefulset mimir --replicas=0

# Step 2: Restore blocks from backup
kubectl cp backups/blocks-20231127.tar.gz mimir-0:/tmp/
kubectl exec mimir-0 -- tar xzf /tmp/blocks-20231127.tar.gz -C /data/

# Step 3: Verify block integrity
kubectl exec mimir-0 -- ls -lh /data/blocks/

# Step 4: Restart Mimir
kubectl scale statefulset mimir --replicas=1

# Step 5: Verify query functionality
make -f make/ops/mimir.mk mimir-query-test
```

**Makefile command:**
```bash
# Restore blocks from backup
make -f make/ops/mimir.mk mimir-restore-blocks FILE=./backups/blocks-20231127.tar.gz
```

---

### Scenario 3: S3/Object Storage Recovery

**Use case:** Restore from S3 bucket backup

```bash
# Step 1: Restore S3 bucket from backup
aws s3 sync s3://mimir-blocks-backup-20231127 s3://mimir-blocks --delete

# Step 2: Restart Mimir to re-index blocks
kubectl rollout restart statefulset mimir

# Step 3: Wait for rollout completion
kubectl rollout status statefulset mimir

# Step 4: Verify block discovery
make -f make/ops/mimir.mk mimir-storage-status

# Step 5: Validate queries
make -f make/ops/mimir.mk mimir-query-test
```

---

### Scenario 4: Complete Disaster Recovery (PVC Snapshots)

**Use case:** Complete cluster loss or migration

```bash
# Step 1: Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-mimir-0
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3  # Match original storage class
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: mimir-snapshot-20231127
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# Step 2: Deploy Mimir with restored PVC
helm upgrade --install mimir sb-charts/mimir \
  -f values-restore.yaml

# Step 3: Verify data integrity
make -f make/ops/mimir.mk mimir-health-check
make -f make/ops/mimir.mk mimir-storage-status

# Step 4: Validate historical queries
make -f make/ops/mimir.mk mimir-query-test QUERY='up{job="mimir"}[7d]'
```

**Makefile command:**
```bash
# Complete disaster recovery from snapshot
make -f make/ops/mimir.mk mimir-disaster-recovery SNAPSHOT_NAME=mimir-snapshot-20231127
```

---

### Scenario 5: Tenant-Specific Recovery (Multi-Tenancy)

**Use case:** Recover data for specific tenant

```bash
# Step 1: Extract tenant blocks from backup
aws s3 sync s3://mimir-blocks-backup-20231127/<tenant-id>/ s3://mimir-blocks/<tenant-id>/

# Step 2: Trigger compactor to discover new blocks
kubectl exec mimir-0 -- curl -X POST http://localhost:8080/compactor/ring

# Step 3: Verify tenant data
make -f make/ops/mimir.mk mimir-query-test TENANT=<tenant-id> QUERY='up'

# Step 4: Check tenant metrics
kubectl exec mimir-0 -- curl -H "X-Scope-OrgID: <tenant-id>" \
  http://localhost:8080/prometheus/api/v1/query?query=up
```

---

## Backup Automation

### Kubernetes CronJob for Scheduled Backups

**Example CronJob for daily backups:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mimir-backup-daily
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: mimir-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # Backup configuration
              kubectl get configmap mimir-config -o yaml > /backups/config-$(date +%Y%m%d).yaml

              # Create PVC snapshot
              kubectl apply -f - <<EOF
              apiVersion: snapshot.storage.k8s.io/v1
              kind: VolumeSnapshot
              metadata:
                name: mimir-snapshot-$(date +%Y%m%d-%H%M)
              spec:
                volumeSnapshotClassName: csi-aws-vsc
                source:
                  persistentVolumeClaimName: data-mimir-0
              EOF

              # Upload to S3 (if needed)
              aws s3 cp /backups/config-$(date +%Y%m%d).yaml s3://my-backups/mimir/config/
            volumeMounts:
            - name: backups
              mountPath: /backups
          volumes:
          - name: backups
            emptyDir: {}
          restartPolicy: OnFailure
```

**Required RBAC permissions for backup CronJob:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mimir-backup
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["create", "get", "list"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]
```

---

### Backup Retention Policies

**Recommended retention:**

| Backup Type | Frequency | Retention | Storage Location |
|-------------|-----------|-----------|------------------|
| Block storage (S3) | Continuous | 90 days | S3 versioning |
| Configuration | Daily | 30 days | S3 + Git |
| PVC snapshots | Weekly | 4 weeks | EBS snapshots |
| Full backup | Monthly | 12 months | S3 Glacier |

**Automated cleanup script:**

```bash
#!/bin/bash
# Cleanup old backups (keep last 30 days)

BACKUP_DIR="/backups/mimir"
RETENTION_DAYS=30

find $BACKUP_DIR/blocks -type f -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR/config -type f -mtime +$RETENTION_DAYS -delete

# Cleanup old VolumeSnapshots
kubectl get volumesnapshots -l app.kubernetes.io/name=mimir \
  -o json | jq -r \
  ".items[] | select(.metadata.creationTimestamp < \"$(date -d "$RETENTION_DAYS days ago" -Iseconds)\") | .metadata.name" | \
  xargs -I {} kubectl delete volumesnapshot {}
```

---

## RTO/RPO Targets

**Recovery Time Objective (RTO):**
- **Configuration recovery**: < 5 minutes
- **Block storage recovery (filesystem)**: < 30 minutes (depends on data size)
- **S3 bucket restore**: < 1 hour (depends on S3 sync speed)
- **Complete disaster recovery (PVC snapshot)**: < 2 hours

**Recovery Point Objective (RPO):**
- **Block storage (S3 versioning)**: Near-zero (continuous)
- **Configuration backups**: 24 hours (daily backups)
- **PVC snapshots**: 7 days (weekly snapshots)
- **Full backups**: 30 days (monthly backups)

**Recommended for production:**
- **RPO target**: 1 hour or less
- **RTO target**: 2 hours or less
- **Strategy**: S3 versioning + daily configuration backups + weekly PVC snapshots

---

## Best Practices

### Pre-Production Testing

**Always test backup/recovery in non-production:**

```bash
# 1. Create test namespace
kubectl create namespace mimir-test

# 2. Deploy Mimir test instance
helm install mimir-test sb-charts/mimir -n mimir-test \
  -f values-example.yaml

# 3. Generate test data
make -f make/ops/mimir.mk mimir-test-data-generate

# 4. Perform backup
make -f make/ops/mimir.mk mimir-backup-all

# 5. Simulate disaster (delete StatefulSet)
kubectl delete statefulset mimir -n mimir-test

# 6. Restore from backup
make -f make/ops/mimir.mk mimir-restore-all DIR=./backups/latest

# 7. Validate data integrity
make -f make/ops/mimir.mk mimir-query-test QUERY='up[24h]'

# 8. Cleanup test namespace
kubectl delete namespace mimir-test
```

---

### Backup Verification

**Always verify backup integrity:**

```bash
# 1. Verify block checksums
make -f make/ops/mimir.mk mimir-backup-verify-blocks DIR=./backups/blocks-20231127

# 2. Verify configuration syntax
kubectl apply --dry-run=client -f ./backups/config-20231127/mimir-config.yaml

# 3. Test restore in isolated environment (recommended)
make -f make/ops/mimir.mk mimir-test-restore DIR=./backups/latest

# 4. Generate backup manifest with checksums
make -f make/ops/mimir.mk mimir-backup-manifest DIR=./backups/latest
```

---

### Storage Considerations

**Filesystem mode (Dev/Test):**
- Use PVC snapshots as primary backup method
- Supplement with manual `tar` backups for portability
- Consider storage overhead (snapshots consume space)

**S3/Object storage mode (Production):**
- Enable S3 versioning for automatic point-in-time recovery
- Use S3 bucket replication for disaster recovery
- Implement lifecycle policies for cost optimization
- Monitor S3 costs (versioning can increase storage costs)

**Hybrid approach:**
- S3 versioning for block storage
- Git repository for configuration files
- Weekly PVC snapshots for disaster recovery
- Monthly full backups to S3 Glacier (archival)

---

### Multi-Tenancy Considerations

**Tenant-specific backups:**

```bash
# Backup specific tenant data
aws s3 sync s3://mimir-blocks/<tenant-id>/ \
  s3://mimir-backups/<tenant-id>/backup-$(date +%Y%m%d)/

# Restore specific tenant
aws s3 sync s3://mimir-backups/<tenant-id>/backup-20231127/ \
  s3://mimir-blocks/<tenant-id>/
```

**Tenant isolation during restore:**
- Restore tenant data to isolated S3 prefix
- Verify tenant queries before production cutover
- Use tenant-specific ingestion rate limits during restore

---

## Troubleshooting

### Issue: Backup Taking Too Long

**Symptoms:**
- Backup jobs timeout
- High I/O wait during backup
- Backup completion > 1 hour

**Causes:**
- Large data volumes (TBs of blocks)
- Slow storage backend (filesystem mode)
- Network bandwidth limitations (S3 mode)

**Solutions:**

```bash
# 1. Use incremental backups
make -f make/ops/mimir.mk mimir-backup-blocks-incremental

# 2. Backup during low-traffic periods
# Schedule backups at night: 0 2 * * *

# 3. Use S3 versioning instead of manual backups (S3 mode)
aws s3api put-bucket-versioning --bucket mimir-blocks \
  --versioning-configuration Status=Enabled

# 4. Increase backup job timeout
kubectl edit cronjob mimir-backup-daily
# Set: .spec.jobTemplate.spec.activeDeadlineSeconds: 7200

# 5. Optimize block compaction settings (reduce block count)
# Edit mimir.yaml: limits.compactor.blocks_retention_period: 7d
```

---

### Issue: Restore Incomplete or Corrupt

**Symptoms:**
- Queries return partial data after restore
- Mimir logs show "block not found" errors
- Store-gateway reports missing blocks

**Causes:**
- Incomplete backup (backup interrupted)
- Corrupted backup archive
- Mismatch between backup and restore versions

**Solutions:**

```bash
# 1. Verify backup integrity before restore
make -f make/ops/mimir.mk mimir-backup-verify DIR=./backups/backup-20231127

# 2. Check backup manifest checksums
cd ./backups/backup-20231127
sha256sum -c checksums.txt

# 3. Restore from earlier backup
make -f make/ops/mimir.mk mimir-restore-all DIR=./backups/backup-20231126

# 4. Force compactor to re-scan blocks
kubectl exec mimir-0 -- curl -X POST http://localhost:8080/compactor/ring

# 5. Verify block metadata
kubectl exec mimir-0 -- ls -lR /data/blocks/ | grep meta.json
```

---

### Issue: S3 Restore Slow

**Symptoms:**
- S3 sync taking hours
- Store-gateway slow to discover blocks
- High S3 API request costs

**Solutions:**

```bash
# 1. Use AWS S3 Transfer Acceleration
aws s3 sync s3://mimir-blocks-backup s3://mimir-blocks \
  --endpoint-url https://s3-accelerate.amazonaws.com

# 2. Parallel S3 sync with aws-cli multipart
aws configure set default.s3.max_concurrent_requests 100
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.multipart_chunksize 16MB

# 3. Use S3 Batch Operations for large restores
# Create restore job via AWS Console or CLI

# 4. Pre-warm store-gateway cache
kubectl exec mimir-0 -- curl -X POST http://localhost:8080/store-gateway/prewarm

# 5. Monitor S3 metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BucketSizeBytes \
  --dimensions Name=BucketName,Value=mimir-blocks
```

---

### Issue: PVC Snapshot Creation Fails

**Symptoms:**
- VolumeSnapshot stuck in Pending state
- Error: "snapshot controller not installed"
- Snapshot shows ReadyToUse: false

**Causes:**
- CSI driver missing or misconfigured
- VolumeSnapshotClass not found
- Insufficient storage quota

**Solutions:**

```bash
# 1. Verify CSI driver installed
kubectl get csidrivers

# 2. Check VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# 3. Install snapshot controller if missing
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

# 4. Create VolumeSnapshotClass (AWS EBS example)
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-aws-vsc
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF

# 5. Check snapshot status and events
kubectl describe volumesnapshot mimir-snapshot-20231127
```

---

### Issue: Configuration Restore Causes Startup Failures

**Symptoms:**
- Mimir pods CrashLoopBackOff after config restore
- Logs show "invalid configuration" errors
- ConfigMap applied but pods fail to start

**Causes:**
- Configuration version mismatch (Mimir version incompatibility)
- Invalid YAML syntax
- Missing required fields

**Solutions:**

```bash
# 1. Validate configuration syntax
kubectl apply --dry-run=client -f backups/config-20231127/mimir-config.yaml

# 2. Check Mimir version compatibility
kubectl get statefulset mimir -o jsonpath='{.spec.template.spec.containers[0].image}'
# Compare with backup Mimir version

# 3. Validate configuration with Mimir CLI
kubectl exec mimir-0 -- /bin/mimir -config.file=/etc/mimir/mimir.yaml -validate-config

# 4. Review Mimir logs for specific errors
kubectl logs mimir-0 | grep -i "error\|fatal"

# 5. Restore to last known-good configuration
kubectl apply -f backups/config-20231126/mimir-config.yaml
kubectl rollout restart statefulset mimir
```

---

## Related Documentation

- [Mimir Upgrade Guide](mimir-upgrade-guide.md) - Version upgrade procedures
- [Mimir README](../charts/mimir/README.md) - Chart documentation
- [Makefile Commands](MAKEFILE_COMMANDS.md) - All operational commands
- [Production Checklist](PRODUCTION_CHECKLIST.md) - Production readiness validation

---

**Last Updated:** 2025-11-27
**Chart Version:** 0.3.0
**Mimir Version:** 2.15.0
