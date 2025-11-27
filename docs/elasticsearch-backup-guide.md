# Elasticsearch Backup & Recovery Guide

This guide provides comprehensive backup and recovery procedures for Elasticsearch deployed via the `sb-helm-charts/elasticsearch` chart.

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

Elasticsearch backup consists of **four critical components**:

1. **Snapshot Repository** (indices, cluster state, snapshots)
2. **Index-level Backups** (specific indices via `_snapshot` API)
3. **Cluster Settings** (templates, ILM policies, ingest pipelines)
4. **Data Volumes** (PVC snapshots for disaster recovery)

**Why four components?**

- **Snapshots**: Application-level backup (fastest recovery, point-in-time restore)
- **Index backups**: Granular recovery (individual index restore)
- **Cluster settings**: Configuration preservation (templates, policies, pipelines)
- **Data volumes**: Disaster recovery (complete cluster rebuild from PVCs)

---

## Backup Components

### 1. Snapshot Repository

**What it backs up:**
- All indices and their data
- Cluster metadata and state
- Index mappings and settings
- Aliases and templates

**Storage options:**
- S3-compatible object storage (recommended)
- NFS shared storage
- Local filesystem (development only)

**Advantages:**
- Point-in-time recovery
- Incremental backups (only changed segments)
- Cross-cluster restore support
- Fastest recovery method

**Makefile commands:**
```bash
# Create snapshot repository (one-time setup)
make -f make/ops/elasticsearch.mk es-create-snapshot-repo

# Create full cluster snapshot
make -f make/ops/elasticsearch.mk es-create-snapshot

# List all snapshots
make -f make/ops/elasticsearch.mk es-list-snapshots

# Get snapshot details
make -f make/ops/elasticsearch.mk es-get-snapshot SNAPSHOT_NAME=snapshot_20231127
```

---

### 2. Index-level Backups

**What it backs up:**
- Specific indices (by name or pattern)
- Index mappings and settings
- Document data

**Use cases:**
- Selective restore (recover single index without full restore)
- Index migration (move index to different cluster)
- Compliance backups (retain specific indices longer)

**Makefile commands:**
```bash
# Backup specific index
make -f make/ops/elasticsearch.mk es-backup-index INDEX_NAME=my-index

# Backup all indices matching pattern
make -f make/ops/elasticsearch.mk es-backup-index INDEX_NAME='logs-*'
```

---

### 3. Cluster Settings

**What it backs up:**
- Index templates (define index structure)
- ILM (Index Lifecycle Management) policies
- Ingest pipelines (data transformation)
- Cluster-level settings
- Component templates

**Why separate backup?**

Snapshots include cluster state, but cluster settings backup provides:
- Human-readable JSON files (for version control)
- Easy comparison between clusters
- Simplified migration to new clusters

**Makefile commands:**
```bash
# Backup all cluster settings, templates, and policies
make -f make/ops/elasticsearch.mk es-cluster-settings-backup
```

**Backup contents:**
```
tmp/elasticsearch-backups/cluster-settings/20231127-143022/
├── cluster-settings.json      # Cluster-wide settings
├── index-templates.json       # Index templates
├── component-templates.json   # Component templates
├── ilm-policies.json         # ILM policies
└── ingest-pipelines.json     # Ingest pipelines
```

---

### 4. Data Volumes (PVC Snapshots)

**What it backs up:**
- Complete Elasticsearch data directory (`/usr/share/elasticsearch/data`)
- Node-local state
- Transaction logs

**Use cases:**
- Disaster recovery (complete cluster loss)
- Migration to different storage class
- Kubernetes cluster migration

**Requirements:**
- Kubernetes CSI driver with VolumeSnapshot support
- VolumeSnapshotClass configured

**Makefile commands:**
```bash
# Create VolumeSnapshot for all Elasticsearch PVCs
make -f make/ops/elasticsearch.mk es-data-backup
```

**Advantages:**
- Storage-level backup (filesystem consistent)
- Fast recovery (no Elasticsearch API overhead)
- Complete disaster recovery capability

**Disadvantages:**
- Larger backup size (no deduplication)
- Slower than snapshot restore (full data copy)
- Requires compatible storage backend

---

## Backup Procedures

### Full Cluster Backup (Recommended)

**Frequency:** Daily (automated via cron/CI)

**Procedure:**

```bash
# 1. Backup cluster settings (templates, ILM policies)
make -f make/ops/elasticsearch.mk es-cluster-settings-backup

# 2. Create cluster snapshot (all indices)
make -f make/ops/elasticsearch.mk es-create-snapshot

# 3. Create PVC snapshot (disaster recovery)
make -f make/ops/elasticsearch.mk es-data-backup

# 4. Verify snapshot health
make -f make/ops/elasticsearch.mk es-verify-snapshot SNAPSHOT_NAME=snapshot_$(date +%Y%m%d)
```

**Expected duration:**
- Cluster settings backup: < 1 minute
- Snapshot creation: 5-30 minutes (depends on data size)
- PVC snapshot: 5-15 minutes (depends on storage backend)

---

### Incremental Backup (Daily)

**Elasticsearch snapshots are automatically incremental** - only new or changed segments are backed up.

```bash
# Create daily snapshot (incremental by default)
make -f make/ops/elasticsearch.mk es-create-snapshot
```

**How it works:**
- First snapshot: Full backup of all data
- Subsequent snapshots: Only changed/new segments
- Shared segments referenced from previous snapshots

**Storage efficiency example:**
```
Snapshot 1 (Day 1): 100 GB (full backup)
Snapshot 2 (Day 2):   5 GB (only changes, total 105 GB)
Snapshot 3 (Day 3):   8 GB (only changes, total 113 GB)
```

---

### Selective Index Backup

**Use case:** Backup critical indices more frequently than others.

```bash
# Backup critical indices hourly
make -f make/ops/elasticsearch.mk es-backup-index INDEX_NAME='critical-logs-*'

# Backup audit logs separately (compliance requirement)
make -f make/ops/elasticsearch.mk es-backup-index INDEX_NAME='audit-*'
```

---

### Pre-Production Backup

**Before major changes (upgrades, configuration changes, schema migrations):**

```bash
# 1. Disable shard allocation (optional, prevents rebalancing)
make -f make/ops/elasticsearch.mk es-disable-shard-allocation

# 2. Create named snapshot
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=pre_upgrade_$(date +%Y%m%d)

# 3. Backup cluster settings
make -f make/ops/elasticsearch.mk es-cluster-settings-backup

# 4. Create PVC snapshot (disaster recovery)
make -f make/ops/elasticsearch.mk es-data-backup

# 5. Re-enable shard allocation
make -f make/ops/elasticsearch.mk es-enable-shard-allocation
```

---

## Recovery Procedures

### Full Cluster Restore

**Scenario:** Complete cluster loss or corruption.

**Procedure:**

```bash
# 1. Deploy fresh Elasticsearch cluster (same version)
helm install elasticsearch scripton-charts/elasticsearch \
  -f values.yaml \
  --namespace default

# 2. Wait for cluster to be healthy
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elasticsearch --timeout=5m

# 3. Register snapshot repository (same config as backup)
make -f make/ops/elasticsearch.mk es-create-snapshot-repo

# 4. List available snapshots
make -f make/ops/elasticsearch.mk es-list-snapshots

# 5. Restore latest snapshot (closes all existing indices first)
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=snapshot_20231127

# 6. Monitor restore progress
make -f make/ops/elasticsearch.mk es-restore-status

# 7. Verify cluster health
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**Expected duration:**
- Cluster deployment: 3-5 minutes
- Snapshot restore: 10-60 minutes (depends on data size)
- Index recovery: 5-30 minutes (shard allocation and replication)

---

### Selective Index Restore

**Scenario:** Recover specific index without affecting other indices.

**Procedure:**

```bash
# 1. List snapshots containing the index
make -f make/ops/elasticsearch.mk es-list-snapshots

# 2. Restore specific index (do not close existing indices)
kubectl exec -it elasticsearch-0 -- curl -X POST "http://localhost:9200/_snapshot/backup_repo/snapshot_20231127/_restore?pretty" \
  -H 'Content-Type: application/json' -d '{
    "indices": "my-index",
    "ignore_unavailable": true,
    "include_global_state": false,
    "rename_pattern": "(.+)",
    "rename_replacement": "restored_$1"
  }'

# 3. Monitor restore progress
make -f make/ops/elasticsearch.mk es-restore-status

# 4. Verify index recovered
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/restored_my-index/_count?pretty"
```

**Options:**
- `ignore_unavailable`: Skip missing indices (continue restore)
- `include_global_state`: Restore cluster settings (usually false for selective restore)
- `rename_pattern`/`rename_replacement`: Restore with different name (avoid overwriting existing index)

---

### Point-in-Time Recovery

**Scenario:** Restore cluster to specific point in time.

**Procedure:**

```bash
# 1. List all snapshots with timestamps
make -f make/ops/elasticsearch.mk es-list-snapshots

# 2. Select snapshot closest to desired recovery point
# Example: Restore to state on 2023-11-27 14:30
SNAPSHOT_NAME=snapshot_20231127_1430

# 3. Close all indices (or delete cluster and redeploy)
kubectl exec -it elasticsearch-0 -- curl -X POST "http://localhost:9200/_all/_close?pretty"

# 4. Restore snapshot
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=$SNAPSHOT_NAME

# 5. Verify cluster state
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

---

### Disaster Recovery (PVC Restore)

**Scenario:** Snapshot repository unavailable, or complete Kubernetes cluster loss.

**Requirements:**
- VolumeSnapshot created before disaster
- Access to same storage backend

**Procedure:**

```bash
# 1. Create PVC from VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: elasticsearch-data-restore
spec:
  dataSource:
    name: elasticsearch-snapshot-20231127
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
EOF

# 2. Deploy Elasticsearch using restored PVC
helm install elasticsearch scripton-charts/elasticsearch \
  -f values.yaml \
  --set persistence.existingClaim=elasticsearch-data-restore \
  --namespace default

# 3. Wait for cluster to start
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elasticsearch --timeout=10m

# 4. Verify data recovered
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

---

## Backup Automation

### Cron-based Automation (External)

**Note:** The Elasticsearch chart does **not** include automated CronJobs. Backup automation should be handled externally.

**Example cron job (Linux server):**

```bash
# /etc/cron.d/elasticsearch-backup
# Daily full backup at 2 AM
0 2 * * * /path/to/backup-script.sh

# Weekly PVC snapshot on Sunday at 3 AM
0 3 * * 0 /path/to/pvc-snapshot-script.sh
```

**Backup script example:**

```bash
#!/bin/bash
# elasticsearch-backup.sh

set -e

NAMESPACE="default"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Starting Elasticsearch backup: $TIMESTAMP"

# 1. Cluster settings backup
make -f make/ops/elasticsearch.mk es-cluster-settings-backup

# 2. Create snapshot
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=auto_backup_$TIMESTAMP

# 3. Verify snapshot
make -f make/ops/elasticsearch.mk es-verify-snapshot SNAPSHOT_NAME=auto_backup_$TIMESTAMP

# 4. Cleanup old snapshots (retain last 30 days)
CUTOFF_DATE=$(date -d '30 days ago' +%Y%m%d)
# ... snapshot deletion logic ...

echo "Backup completed successfully"
```

---

### CI/CD Integration (GitLab CI, GitHub Actions)

**Example GitHub Actions workflow:**

```yaml
name: Elasticsearch Backup
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:      # Manual trigger

jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure kubectl
        run: |
          echo "${{ secrets.KUBECONFIG }}" > kubeconfig
          export KUBECONFIG=./kubeconfig

      - name: Cluster Settings Backup
        run: make -f make/ops/elasticsearch.mk es-cluster-settings-backup

      - name: Create Snapshot
        run: make -f make/ops/elasticsearch.mk es-create-snapshot

      - name: Verify Snapshot
        run: make -f make/ops/elasticsearch.mk es-verify-snapshot

      - name: Upload Backup Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: elasticsearch-backups
          path: tmp/elasticsearch-backups/
```

---

## RTO/RPO Targets

### Recovery Time Objective (RTO)

**RTO:** Maximum acceptable downtime after disaster.

| Recovery Scenario | Target RTO | Notes |
|------------------|------------|-------|
| Snapshot restore (single index) | < 30 minutes | Depends on index size |
| Snapshot restore (full cluster) | < 2 hours | 100 GB cluster |
| PVC restore (disaster recovery) | < 4 hours | Includes cluster redeployment |
| Cluster settings restore | < 5 minutes | JSON file restoration |

### Recovery Point Objective (RPO)

**RPO:** Maximum acceptable data loss (time between backups).

| Backup Type | Target RPO | Frequency |
|-------------|-----------|-----------|
| Snapshot backups | 24 hours | Daily |
| Critical indices | 1 hour | Hourly |
| Cluster settings | 24 hours | Daily |
| PVC snapshots | 24 hours | Daily |

**Achieving lower RPO:**

- **Hourly snapshots:** For critical indices
- **Continuous replication:** Use Cross-Cluster Replication (CCR) to secondary cluster
- **Write-ahead logging:** Enable transaction log persistence

---

## Best Practices

### Snapshot Repository Configuration

**Use S3-compatible storage (recommended):**

```yaml
# S3 snapshot repository configuration
{
  "type": "s3",
  "settings": {
    "bucket": "elasticsearch-snapshots",
    "region": "us-east-1",
    "base_path": "production/snapshots",
    "compress": true,
    "max_snapshot_bytes_per_sec": "100mb",
    "max_restore_bytes_per_sec": "100mb"
  }
}
```

**Advantages:**
- Unlimited storage capacity
- Cross-region durability
- Versioning and lifecycle policies
- Cost-effective for long-term retention

---

### Snapshot Naming Convention

**Use descriptive, timestamped names:**

```bash
# Production snapshots
snapshot_prod_20231127_020000

# Pre-upgrade snapshots
snapshot_pre_upgrade_v8.11.0_20231127

# Manual snapshots
snapshot_manual_critical_fix_20231127
```

---

### Retention Policy

**Recommended retention:**

- **Daily snapshots:** Retain 30 days
- **Weekly snapshots:** Retain 90 days
- **Monthly snapshots:** Retain 1 year
- **Pre-upgrade snapshots:** Retain until upgrade validated (7-30 days)

**Cleanup script example:**

```bash
# Delete snapshots older than 30 days
CUTOFF_DATE=$(date -d '30 days ago' +%s)
for snapshot in $(make -f make/ops/elasticsearch.mk es-list-snapshots | grep snapshot_ | awk '{print $1}'); do
  SNAPSHOT_DATE=$(echo $snapshot | grep -oP '\d{8}')
  SNAPSHOT_EPOCH=$(date -d "$SNAPSHOT_DATE" +%s)
  if [ $SNAPSHOT_EPOCH -lt $CUTOFF_DATE ]; then
    make -f make/ops/elasticsearch.mk es-delete-snapshot SNAPSHOT_NAME=$snapshot
  fi
done
```

---

### Test Restore Procedures

**Monthly restore testing:**

```bash
# 1. Deploy test Elasticsearch cluster
helm install elasticsearch-test scripton-charts/elasticsearch \
  -f values-test.yaml \
  --namespace elasticsearch-test

# 2. Restore latest production snapshot
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=snapshot_latest

# 3. Validate data integrity
kubectl exec -it elasticsearch-test-0 -- curl "http://localhost:9200/_cat/indices?v"

# 4. Cleanup test cluster
helm uninstall elasticsearch-test --namespace elasticsearch-test
```

---

### Monitor Backup Health

**Check snapshot status regularly:**

```bash
# List recent snapshots and their status
make -f make/ops/elasticsearch.mk es-list-snapshots

# Check for failed snapshots
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_snapshot/backup_repo/_all?pretty" | grep -A 5 '"state": "FAILED"'

# Verify snapshot integrity
make -f make/ops/elasticsearch.mk es-verify-snapshot SNAPSHOT_NAME=snapshot_latest
```

---

## Troubleshooting

### Snapshot Creation Fails

**Symptom:** `es-create-snapshot` fails with error.

**Common causes:**

1. **Snapshot repository not registered:**
```bash
# Solution: Register repository first
make -f make/ops/elasticsearch.mk es-create-snapshot-repo
```

2. **Insufficient storage space:**
```bash
# Check available storage
kubectl exec -it elasticsearch-0 -- df -h /usr/share/elasticsearch/snapshots

# Solution: Cleanup old snapshots or increase storage
```

3. **Snapshot already in progress:**
```bash
# Check snapshot status
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_snapshot/_status?pretty"

# Solution: Wait for snapshot to complete or cancel it
kubectl exec -it elasticsearch-0 -- curl -X DELETE "http://localhost:9200/_snapshot/backup_repo/snapshot_in_progress"
```

---

### Restore Fails - Incompatible Version

**Symptom:** `Cannot restore index [my-index] because it was created on version [8.10.0] which is newer than current version [8.9.0]`

**Solution:**

1. **Upgrade Elasticsearch to compatible version:**
```bash
# Check snapshot Elasticsearch version
make -f make/ops/elasticsearch.mk es-get-snapshot SNAPSHOT_NAME=snapshot_latest

# Upgrade cluster to match or newer version
helm upgrade elasticsearch scripton-charts/elasticsearch --set image.tag=8.10.0
```

2. **Reindex to compatible version (alternative):**
```bash
# Use older snapshot if available
make -f make/ops/elasticsearch.mk es-list-snapshots
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=snapshot_older
```

---

### Slow Snapshot/Restore Performance

**Symptom:** Snapshot creation or restore takes hours.

**Solutions:**

1. **Increase snapshot rate limits:**
```bash
# Update snapshot repository settings
kubectl exec -it elasticsearch-0 -- curl -X PUT "http://localhost:9200/_snapshot/backup_repo?pretty" \
  -H 'Content-Type: application/json' -d '{
    "type": "fs",
    "settings": {
      "location": "/usr/share/elasticsearch/snapshots",
      "max_snapshot_bytes_per_sec": "500mb",
      "max_restore_bytes_per_sec": "500mb"
    }
  }'
```

2. **Check storage I/O performance:**
```bash
# Monitor storage performance during snapshot
kubectl exec -it elasticsearch-0 -- iostat -x 5
```

3. **Reduce shard count (future indices):**
```yaml
# Index template with fewer shards
{
  "index_patterns": ["logs-*"],
  "settings": {
    "number_of_shards": 1,  # Reduce from 5 to 1
    "number_of_replicas": 1
  }
}
```

---

### PVC Snapshot Not Created

**Symptom:** `es-data-backup` fails to create VolumeSnapshot.

**Common causes:**

1. **VolumeSnapshotClass not available:**
```bash
# Check available VolumeSnapshotClasses
kubectl get volumesnapshotclass

# Solution: Install CSI driver and create VolumeSnapshotClass
```

2. **CSI driver not installed:**
```bash
# Example: Install AWS EBS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"
```

3. **Storage class not compatible:**
```bash
# Check PVC storage class
kubectl get pvc elasticsearch-data-0 -o jsonpath='{.spec.storageClassName}'

# Solution: Use CSI-compatible storage class
```

---

**Last Updated:** 2025-11-27
**Chart Version:** v0.3.0
**Elasticsearch Version:** 8.11.x
