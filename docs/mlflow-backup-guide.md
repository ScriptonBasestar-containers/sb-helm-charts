# MLflow Backup & Recovery Guide

Comprehensive guide for backing up and restoring MLflow tracking server including experiments, models, artifacts, and metadata.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Procedures](#backup-procedures)
- [Recovery Procedures](#recovery-procedures)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Components

MLflow backup consists of three critical components:

1. **Experiments & Runs Metadata** (tracking server data)
   - Experiment definitions, run parameters, metrics
   - Exported via MLflow CLI or API
   - Stored as JSON files or database dumps
   - Critical for experiment history

2. **PostgreSQL Database** (backend store - if using external DB)
   - Complete MLflow metadata
   - Run history, parameters, metrics, tags
   - Backed up via `pg_dump`
   - Required for production deployments

3. **Artifacts** (model files, plots, data files)
   - Stored in S3/MinIO or local PVC
   - Largest component by size
   - Contains actual model binaries and outputs
   - Backed up via S3 sync or PVC snapshots

### Why All Three?

- **Metadata exports**: Quick recovery of experiment definitions and run history
- **Database dumps**: Complete state including all metrics and parameters
- **Artifacts**: Actual model files and outputs
- **Combined**: Maximum data safety and complete ML workflow recovery

---

## Backup Strategy

### Recommended Backup Schedule

| Environment | Metadata Export | DB Dump | Artifacts | Retention |
|-------------|-----------------|---------|-----------|-----------|
| **Production** | Daily (2 AM) | Daily (2 AM) | Daily (2 AM) | 30 days |
| **Staging** | Weekly | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | On-demand | 7 days |

### Storage Locations

```
tmp/mlflow-backups/
├── experiments/               # Metadata exports
│   ├── 20251127-020000/
│   │   ├── experiments.json
│   │   └── models.json
│   └── 20251126-020000/
├── db/                        # Database dumps
│   ├── mlflow-db-20251127-020000.sql
│   └── mlflow-db-20251126-020000.sql
└── artifacts/                 # Artifact backups
    ├── 20251127-020000/
    └── 20251126-020000/
```

### RTO/RPO Targets

| Component | Recovery Time Objective (RTO) | Recovery Point Objective (RPO) |
|-----------|-------------------------------|--------------------------------|
| Metadata | < 10 minutes | 24 hours (daily backup) |
| Database | < 20 minutes | 24 hours (daily backup) |
| Artifacts | < 60 minutes | 24 hours (daily backup) |
| **Full System** | **< 90 minutes** | **24 hours** |

---

## Backup Procedures

### 1. Backup Experiments Metadata

**Export all experiments and registered models:**

```bash
make -f make/ops/mlflow.mk mlflow-experiments-backup
```

**What it does:**
1. Executes `mlflow experiments search --view all` in MLflow pod
2. Executes `mlflow models list` to export registered models
3. Saves to local `tmp/mlflow-backups/experiments/<timestamp>/`

**Expected output:**
```
Backing up MLflow experiments and runs...
Exporting all experiments...
Exporting registered models...
✓ Experiments backup completed: tmp/mlflow-backups/experiments/20251127-143022
```

**Manual export (alternative):**
```bash
# Export experiments
kubectl exec -it mlflow-0 -- \
  mlflow experiments search --view all --max-results 10000 > experiments.json

# Export models
kubectl exec -it mlflow-0 -- \
  mlflow models list --max-results 1000 > models.json

# Export specific experiment
kubectl exec -it mlflow-0 -- \
  mlflow experiments export --experiment-id 1 --output-dir /tmp/experiment-1
```

### 2. Backup PostgreSQL Database

**Create a database dump (for external PostgreSQL):**

```bash
make -f make/ops/mlflow.mk mlflow-db-backup
```

**What it does:**
1. Connects to external PostgreSQL (if configured)
2. Executes `pg_dump mlflow` database
3. Saves to `tmp/mlflow-backups/db/mlflow-db-<timestamp>.sql`

**Expected output:**
```
Backing up MLflow PostgreSQL database...
Note: This requires external PostgreSQL configuration
Connecting to PostgreSQL: postgresql.default.svc.cluster.local/mlflow
✓ Database backup completed: tmp/mlflow-backups/db/mlflow-db-20251127-143022.sql
  Size: 125 MB
```

**Note:** If using SQLite (default), the database file is in the PVC and backed up with the PVC.

**Manual backup (alternative):**
```bash
# For external PostgreSQL
kubectl exec -it mlflow-0 -- \
  pg_dump -h postgresql -U mlflow -d mlflow > mlflow-backup.sql

# For SQLite (copy from PVC)
kubectl cp mlflow-0:/mlflow/mlflow.db ./mlflow.db.backup
```

### 3. Backup Artifacts

**Backup artifacts from S3/MinIO:**

```bash
make -f make/ops/mlflow.mk mlflow-artifacts-backup
```

**What it provides:**
- Instructions for AWS CLI or MinIO client
- Bucket name from configuration
- Command templates

**Manual S3 backup:**
```bash
# Sync artifacts from S3
aws s3 sync s3://mlflow-artifacts ./tmp/mlflow-backups/artifacts/$(date +%Y%m%d-%H%M%S)/

# Or with MinIO client
mc cp --recursive minio/mlflow-artifacts ./tmp/mlflow-backups/artifacts/$(date +%Y%m%d-%H%M%S)/
```

**For local PVC storage:**
```bash
# Create PVC snapshot (if using CSI)
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mlflow-artifacts-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: mlflow-artifacts
EOF
```

### 4. Full Backup Workflow

**Recommended complete backup sequence:**

```bash
# 1. Backup experiments metadata
make -f make/ops/mlflow.mk mlflow-experiments-backup

# 2. Backup database (if using external PostgreSQL)
make -f make/ops/mlflow.mk mlflow-db-backup

# 3. Backup artifacts
# For S3/MinIO:
aws s3 sync s3://mlflow-artifacts ./tmp/mlflow-backups/artifacts/$(date +%Y%m%d-%H%M%S)/
# For PVC: create snapshot (see above)

# 4. Verify backups
ls -lh tmp/mlflow-backups/experiments/
ls -lh tmp/mlflow-backups/db/
ls -lh tmp/mlflow-backups/artifacts/
```

**Backup verification:**
```bash
# Check experiments file
cat tmp/mlflow-backups/experiments/*/experiments.json | jq '.'

# Check database dump
file tmp/mlflow-backups/db/mlflow-db-*.sql

# Verify artifacts
ls -lh tmp/mlflow-backups/artifacts/*/
```

---

## Recovery Procedures

### 1. Restore Experiments Metadata

**Import experiments from backup:**

```bash
# Copy backup to pod
kubectl cp tmp/mlflow-backups/experiments/20251127-020000/ \
  mlflow-0:/tmp/experiments-backup/

# Import experiments
kubectl exec -it mlflow-0 -- \
  mlflow experiments import --src /tmp/experiments-backup/
```

**Note:** MLflow doesn't have built-in bulk import. Experiments may need to be recreated via API or UI.

### 2. Restore Database

**Restore PostgreSQL database from backup:**

```bash
make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/db/mlflow-db-20251127-020000.sql
```

**What it does:**
1. Prompts for confirmation (⚠️ WARNING displayed)
2. Connects to PostgreSQL pod
3. Restores from SQL dump
4. Verifies completion

**Expected output:**
```
⚠️  WARNING: This will restore the MLflow database from backup.
Database: mlflow
Backup file: tmp/mlflow-backups/db/mlflow-db-20251127-020000.sql
Continue? (yes/no): yes
Restoring database...
✓ Database restore completed
```

**For SQLite:**
```bash
# Stop MLflow
kubectl scale deployment mlflow --replicas=0

# Restore SQLite database
kubectl cp ./mlflow.db.backup mlflow-0:/mlflow/mlflow.db

# Start MLflow
kubectl scale deployment mlflow --replicas=1
```

### 3. Restore Artifacts

**Restore from S3/MinIO:**

```bash
# Restore artifacts to S3
aws s3 sync ./tmp/mlflow-backups/artifacts/20251127-020000/ s3://mlflow-artifacts/

# Or with MinIO client
mc cp --recursive ./tmp/mlflow-backups/artifacts/20251127-020000/ minio/mlflow-artifacts/
```

**Restore from VolumeSnapshot:**

```bash
# Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mlflow-artifacts-restored
  namespace: default
spec:
  storageClassName: csi-snapclass
  dataSource:
    name: mlflow-artifacts-snapshot-20251127-020000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Update MLflow deployment to use restored PVC
kubectl patch deployment mlflow -p \
  '{"spec":{"template":{"spec":{"volumes":[{"name":"artifacts","persistentVolumeClaim":{"claimName":"mlflow-artifacts-restored"}}]}}}}'
```

### 4. Full Recovery Workflow

**Complete disaster recovery procedure:**

```bash
# Step 1: Restore database (if using external PostgreSQL)
kubectl scale deployment mlflow --replicas=0
make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/db/mlflow-db-YYYYMMDD-HHMMSS.sql

# Step 2: Restore artifacts
# Using S3 sync or VolumeSnapshot (see above)

# Step 3: Start MLflow
kubectl scale deployment mlflow --replicas=1

# Step 4: Verify recovery
make -f make/ops/mlflow.mk mlflow-post-upgrade-check

# Step 5: Test experiment access
kubectl exec -it mlflow-0 -- \
  mlflow experiments search --max-results 5
```

---

## Best Practices

### 1. Backup Frequency

- **Production**: Daily automated backups + pre-upgrade backups
- **Staging**: Weekly backups
- **Development**: On-demand before major changes

### 2. Retention Policy

| Backup Type | Retention | Reason |
|-------------|-----------|--------|
| Daily | 30 days | Balance storage cost vs recovery needs |
| Weekly | 90 days | Long-term recovery options |
| Monthly | 1 year | Model compliance/audit requirements |
| Pre-upgrade | Until next successful upgrade | Rollback safety |

### 3. Backup Verification

**Test restores quarterly:**
```bash
# Restore to test namespace
helm install mlflow-test charts/mlflow -n mlflow-test
make -f make/ops/mlflow.mk mlflow-db-restore \
  FILE=backup.sql NAMESPACE=mlflow-test

# Verify experiments
kubectl exec -n mlflow-test mlflow-0 -- \
  mlflow experiments search
```

### 4. Security

- **Encrypt backups at rest**: Use encrypted S3 buckets or encrypted PVCs
- **Encrypt backups in transit**: Use TLS for S3/MinIO transfers
- **Access control**: Restrict backup access to authorized personnel
- **Model artifacts**: May contain sensitive data - treat backups accordingly

### 5. Artifact Management

**Implement artifact lifecycle:**
- **Active models**: Daily backups
- **Archived experiments**: Weekly backups
- **Old artifacts**: Consider archival to glacier storage

---

## Troubleshooting

### Backup Failures

**Problem: `pg_dump` fails with "database not found"**

**Solution:**
```bash
# Verify external PostgreSQL is configured
kubectl get secret mlflow -o yaml | grep postgresql

# Check if using SQLite instead
kubectl exec -it mlflow-0 -- ls -la /mlflow/mlflow.db
```

**Problem: Experiments export returns empty**

**Solution:**
```bash
# Verify MLflow service is running
kubectl exec -it mlflow-0 -- curl http://localhost:5000/health

# Check experiments exist
kubectl exec -it mlflow-0 -- \
  mlflow experiments search --max-results 5
```

**Problem: S3 artifacts backup fails**

**Solution:**
```bash
# Verify S3 credentials
kubectl get secret mlflow -o yaml | grep -E 'accessKey|secretKey'

# Test S3 connection
kubectl exec -it mlflow-0 -- \
  aws s3 ls s3://mlflow-artifacts
```

### Restore Failures

**Problem: Database restore fails with "permission denied"**

**Solution:**
```bash
# Grant permissions
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "GRANT ALL ON DATABASE mlflow TO mlflow;"
```

**Problem: Experiments not visible after restore**

**Solution:**
```bash
# Check database restore
kubectl exec -it postgresql-0 -- \
  psql -U mlflow -d mlflow -c "SELECT COUNT(*) FROM experiments;"

# Restart MLflow
kubectl rollout restart deployment mlflow
```

**Problem: Artifacts not accessible**

**Solution:**
```bash
# Verify artifact store configuration
kubectl exec -it mlflow-0 -- \
  env | grep MLFLOW_ARTIFACT

# Check S3/MinIO connectivity
kubectl exec -it mlflow-0 -- \
  aws s3 ls s3://mlflow-artifacts

# Verify PVC mount
kubectl exec -it mlflow-0 -- ls -la /mlflow/artifacts
```

---

## Additional Resources

- [MLflow Documentation](https://www.mlflow.org/docs/latest/index.html)
- [MLflow Tracking API](https://www.mlflow.org/docs/latest/tracking.html)
- [MLflow Upgrade Guide](mlflow-upgrade-guide.md)
- [Chart README](../charts/mlflow/README.md)

---

**Last Updated:** 2025-11-27
