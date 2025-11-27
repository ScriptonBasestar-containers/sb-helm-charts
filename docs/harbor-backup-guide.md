# Harbor Backup & Recovery Guide

Comprehensive guide for backing up and restoring Harbor container registry including configuration, database, and registry images.

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

Harbor backup consists of three critical components:

1. **Harbor Configuration** (projects, users, replication policies, registries)
   - Exported via Harbor REST API
   - Stored as JSON files
   - Critical for access control and replication setup

2. **PostgreSQL Database** (metadata, audit logs, scan results)
   - Backed up via `pg_dump`
   - Contains all Harbor metadata
   - Required for complete recovery

3. **Registry Data** (container images, Helm charts, artifacts)
   - Stored in PersistentVolume or object storage
   - Largest component by size
   - Backed up via PVC snapshots or S3 sync

### Why All Three?

- **Configuration exports**: Fast recovery of access controls and policies
- **Database dumps**: Complete state including audit logs and vulnerability scan results
- **Registry data**: Actual container images and artifacts
- **Combined**: Maximum data safety and complete disaster recovery capability

---

## Backup Strategy

### Recommended Backup Schedule

| Environment | Config Export | DB Dump | Registry Data | Retention |
|-------------|---------------|---------|---------------|-----------|
| **Production** | Daily (2 AM) | Daily (2 AM) | Daily (2 AM) | 30 days |
| **Staging** | Weekly | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | On-demand | 7 days |

### Storage Locations

```
tmp/harbor-backups/
├── config/                    # Configuration exports
│   ├── 20251127-020000/
│   │   ├── projects.json
│   │   ├── users.json
│   │   └── replication-policies.json
│   └── 20251126-020000/
├── db/                        # Database dumps
│   ├── harbor-db-20251127-020000.sql
│   └── harbor-db-20251126-020000.sql
└── registry/                  # Registry snapshots
    └── snapshot-info.txt
```

### RTO/RPO Targets

| Component | Recovery Time Objective (RTO) | Recovery Point Objective (RPO) |
|-----------|-------------------------------|--------------------------------|
| Configuration | < 10 minutes | 24 hours (daily backup) |
| Database | < 20 minutes | 24 hours (daily backup) |
| Registry Data | < 60 minutes | 24 hours (daily backup) |
| **Full System** | **< 90 minutes** | **24 hours** |

---

## Backup Procedures

### 1. Backup Harbor Configuration

**Export projects, users, and replication policies:**

```bash
make -f make/ops/harbor.mk harbor-config-backup
```

**What it does:**
1. Exports all projects via Harbor API (`/api/v2.0/projects`)
2. Exports all users via Harbor API (`/api/v2.0/users`)
3. Exports replication policies via Harbor API (`/api/v2.0/replication/policies`)
4. Saves to local `tmp/harbor-backups/config/<timestamp>/`

**Expected output:**
```
Backing up Harbor configuration...
Exporting projects...
Exporting users...
Exporting replication policies...
✓ Configuration backup completed: tmp/harbor-backups/config/20251127-143022
```

**Manual export (alternative):**
```bash
# Get admin password
ADMIN_PASS=$(kubectl get secret harbor-secret -o jsonpath='{.data.admin-password}' | base64 --decode)

# Export projects
curl -u "admin:$ADMIN_PASS" \
  http://harbor-core:8080/api/v2.0/projects > projects.json

# Export users
curl -u "admin:$ADMIN_PASS" \
  http://harbor-core:8080/api/v2.0/users > users.json

# Export replication policies
curl -u "admin:$ADMIN_PASS" \
  http://harbor-core:8080/api/v2.0/replication/policies > replication-policies.json
```

### 2. Backup PostgreSQL Database

**Create a database dump:**

```bash
make -f make/ops/harbor.mk harbor-db-backup
```

**What it does:**
1. Connects to PostgreSQL pod
2. Executes `pg_dump harbor` database
3. Saves to `tmp/harbor-backups/db/harbor-db-<timestamp>.sql`

**Expected output:**
```
Backing up Harbor PostgreSQL database...
Connecting to PostgreSQL: postgresql.default.svc.cluster.local/harbor
✓ Database backup completed: tmp/harbor-backups/db/harbor-db-20251127-143022.sql
  Size: 245 MB
```

**Manual backup (alternative):**
```bash
# Get database credentials
PGHOST=$(kubectl get secret harbor -o jsonpath='{.data.postgresql-host}' | base64 --decode)
PGUSER=$(kubectl get secret harbor -o jsonpath='{.data.postgresql-username}' | base64 --decode)

# Execute backup
kubectl exec -it harbor-core-0 -- \
  pg_dump -h $PGHOST -U $PGUSER -d harbor > harbor-backup.sql
```

### 3. Backup Registry Data

**Create PVC snapshot for registry images:**

```bash
make -f make/ops/harbor.mk harbor-registry-backup
```

**What it does:**
1. Identifies Harbor registry PVC
2. Creates VolumeSnapshot using CSI driver
3. Returns snapshot name for verification

**Expected output:**
```
Creating PVC snapshot for Harbor registry data...
Creating snapshot for PVC: harbor-registry
✓ Snapshot created: harbor-registry-snapshot-20251127-143022
  Verify with: kubectl get volumesnapshot -n harbor harbor-registry-snapshot-20251127-143022
```

**Alternative: S3/Object Storage Backup**

If using external object storage (S3/MinIO):

```bash
# Sync registry bucket
aws s3 sync s3://harbor-registry ./tmp/harbor-backups/registry/

# Or with MinIO client
mc cp --recursive minio/harbor-registry ./tmp/harbor-backups/registry/
```

### 4. Full Backup Workflow

**Recommended complete backup sequence:**

```bash
# 1. Backup configuration (projects, users, policies)
make -f make/ops/harbor.mk harbor-config-backup

# 2. Backup database
make -f make/ops/harbor.mk harbor-db-backup

# 3. Backup registry data
make -f make/ops/harbor.mk harbor-registry-backup

# 4. Verify backups
ls -lh tmp/harbor-backups/config/
ls -lh tmp/harbor-backups/db/
kubectl get volumesnapshot -n harbor
```

**Backup verification:**
```bash
# Check config files
cat tmp/harbor-backups/config/*/projects.json | jq '.[] | .name'

# Check database dump
file tmp/harbor-backups/db/harbor-db-*.sql

# Verify snapshot status
kubectl get volumesnapshot harbor-registry-snapshot-* -o yaml
```

---

## Recovery Procedures

### 1. Restore Configuration

**Restore projects and users manually via Harbor UI or API:**

```bash
# Copy backup files to core pod
kubectl cp tmp/harbor-backups/config/20251127-020000/projects.json \
  harbor-core-0:/tmp/projects.json

# Restore via API (manual process - Harbor doesn't have bulk import)
# Projects must be recreated via UI or individual API calls
```

**Note:** Harbor doesn't provide bulk import APIs. Configuration must be restored manually or via custom scripts.

### 2. Restore Database

**Restore PostgreSQL database from backup:**

```bash
make -f make/ops/harbor.mk harbor-db-restore FILE=tmp/harbor-backups/db/harbor-db-20251127-020000.sql
```

**What it does:**
1. Prompts for confirmation (⚠️ WARNING displayed)
2. Connects to PostgreSQL pod
3. Restores from SQL dump
4. Verifies completion

**Expected output:**
```
⚠️  WARNING: This will restore the Harbor database from backup.
Database: harbor
Backup file: tmp/harbor-backups/db/harbor-db-20251127-020000.sql
Continue? (yes/no): yes
Restoring database...
✓ Database restore completed
```

**Manual restore (alternative):**
```bash
# Scale down Harbor
kubectl scale deployment harbor-core --replicas=0
kubectl scale deployment harbor-registry --replicas=0

# Drop and recreate database
kubectl exec -it postgresql-0 -- psql -U postgres \
  -c "DROP DATABASE harbor WITH (FORCE);"
kubectl exec -it postgresql-0 -- psql -U postgres \
  -c "CREATE DATABASE harbor OWNER harbor;"

# Restore from backup
kubectl exec -i postgresql-0 -- \
  psql -U harbor -d harbor < tmp/harbor-backups/db/harbor-db-20251127-020000.sql

# Scale up Harbor
kubectl scale deployment harbor-core --replicas=1
kubectl scale deployment harbor-registry --replicas=1
```

### 3. Restore Registry Data

**Restore from VolumeSnapshot:**

```bash
# Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-registry-restored
  namespace: harbor
spec:
  storageClassName: csi-snapclass
  dataSource:
    name: harbor-registry-snapshot-20251127-020000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
EOF

# Update Harbor deployment to use restored PVC
kubectl patch deployment harbor-registry -p \
  '{"spec":{"template":{"spec":{"volumes":[{"name":"registry-data","persistentVolumeClaim":{"claimName":"harbor-registry-restored"}}]}}}}'
```

**Restore from S3/Object Storage:**

```bash
# Restore registry data from S3
aws s3 sync ./tmp/harbor-backups/registry/ s3://harbor-registry

# Or with MinIO client
mc cp --recursive ./tmp/harbor-backups/registry/ minio/harbor-registry
```

### 4. Full Recovery Workflow

**Complete disaster recovery procedure:**

```bash
# Step 1: Restore database (most important)
kubectl scale deployment harbor-core --replicas=0
kubectl scale deployment harbor-registry --replicas=0
make -f make/ops/harbor.mk harbor-db-restore FILE=tmp/harbor-backups/db/harbor-db-YYYYMMDD-HHMMSS.sql

# Step 2: Restore registry data
# Using VolumeSnapshot or S3 sync (see above)

# Step 3: Start Harbor components
kubectl scale deployment harbor-core --replicas=1
kubectl scale deployment harbor-registry --replicas=1

# Step 4: Verify recovery
make -f make/ops/harbor.mk harbor-health
make -f make/ops/harbor.mk harbor-projects

# Step 5: Manually restore configuration if needed
# Projects, users, and policies via Harbor UI
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
| Monthly | 1 year | Compliance/audit requirements |
| Pre-upgrade | Until next successful upgrade | Rollback safety |

### 3. Backup Verification

**Test restores quarterly:**
```bash
# Restore to test namespace
helm install harbor-test charts/harbor -n harbor-test
make -f make/ops/harbor.mk harbor-db-restore \
  FILE=backup.sql NAMESPACE=harbor-test

# Verify data integrity
kubectl exec -n harbor-test harbor-core-0 -- \
  wget -qO- http://localhost:8080/api/v2.0/projects
```

### 4. Security

- **Encrypt backups at rest**: Use encrypted S3 buckets or encrypted PVCs
- **Encrypt backups in transit**: Use TLS for S3/MinIO transfers
- **Access control**: Restrict backup access to authorized personnel
- **Secrets**: Harbor admin credentials and project secrets in backups - treat as sensitive

### 5. Monitoring

**Monitor backup jobs:**
```bash
# Check backup storage usage
du -sh tmp/harbor-backups/

# Verify recent backups exist
ls -lt tmp/harbor-backups/db/ | head -5
ls -lt tmp/harbor-backups/config/ | head -5

# Check snapshot status
kubectl get volumesnapshot -n harbor
```

---

## Troubleshooting

### Backup Failures

**Problem: `pg_dump` fails with "permission denied"**

**Solution:**
```bash
# Grant permissions
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "GRANT ALL ON DATABASE harbor TO harbor;"
```

**Problem: Configuration export returns empty JSON**

**Solution:**
```bash
# Verify Harbor API is accessible
kubectl exec -it harbor-core-0 -- \
  curl -f http://localhost:8080/health

# Check admin credentials
kubectl get secret harbor-secret -o jsonpath='{.data.admin-password}' | base64 --decode
```

**Problem: VolumeSnapshot fails**

**Solution:**
```bash
# Check if VolumeSnapshot CRD exists
kubectl get crd volumesnapshots.snapshot.storage.k8s.io

# Verify snapshot class
kubectl get volumesnapshotclass

# Check CSI driver
kubectl get csidrivers
```

### Restore Failures

**Problem: Database restore fails with "database already exists"**

**Solution:**
```bash
# Force drop and recreate
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "DROP DATABASE harbor WITH (FORCE);"
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "CREATE DATABASE harbor OWNER harbor;"
```

**Problem: Projects not visible after restore**

**Solution:**
```bash
# Check database restore
kubectl exec -it postgresql-0 -- \
  psql -U harbor -d harbor -c "SELECT COUNT(*) FROM project;"

# Restart Harbor core
kubectl rollout restart deployment harbor-core
```

**Problem: Registry images not accessible**

**Solution:**
```bash
# Verify registry PVC mount
kubectl exec -it harbor-registry-0 -- ls -la /storage

# Check registry logs
kubectl logs -l app.kubernetes.io/component=registry

# Verify image manifest
docker pull harbor.example.com/library/nginx:latest
```

---

## Additional Resources

- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor API Reference](https://goharbor.io/docs/latest/working-with-projects/working-with-projects/)
- [Harbor Upgrade Guide](harbor-upgrade-guide.md)
- [Chart README](../charts/harbor/README.md)

---

**Last Updated:** 2025-11-27
