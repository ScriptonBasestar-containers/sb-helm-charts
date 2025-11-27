# Airflow Backup & Recovery Guide

Comprehensive guide for backing up and restoring Apache Airflow metadata, DAGs, and database.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Procedures](#backup-procedures)
- [Recovery Procedures](#recovery-procedures)
- [Automation](#automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Components

Airflow backup consists of three critical components:

1. **Airflow Metadata**
   - Connections, variables, pools, XCom data
   - DAG run history, task instances
   - Exported via `airflow db export-archived` or direct metadata queries
   - Stored as YAML/JSON files

2. **DAGs (Workflow Definitions)**
   - Python DAG files
   - Backed up from PVC or Git repository
   - Critical for workflow recovery

3. **PostgreSQL Database**
   - Complete Airflow state (all metadata, history, logs)
   - Backed up via `pg_dump`
   - Stored as SQL dump files

### Why All Three?

- **Metadata exports**: Fast, selective recovery (specific connections/variables)
- **DAG backups**: Restore workflow definitions without database
- **Database dumps**: Complete state recovery, including task history and XCom data
- **Combined**: Maximum data safety and flexibility

---

## Backup Strategy

### Recommended Backup Schedule

| Environment | Metadata Export | DAGs Backup | Database Dump | Retention |
|-------------|-----------------|-------------|---------------|-----------|
| **Production** | Daily (2 AM) | Daily (2 AM) | Daily (2 AM) | 30 days |
| **Staging** | Weekly | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | On-demand | 7 days |

### Storage Locations

```
tmp/airflow-backups/
├── metadata/                  # Metadata exports
│   ├── metadata-20251127-020000.yaml
│   ├── connections-20251127-020000.json
│   └── variables-20251127-020000.json
├── dags/                      # DAG backups
│   ├── dags-20251127-020000/
│   │   ├── example_dag.py
│   │   └── etl_pipeline.py
│   └── dags-20251126-020000/
└── db/                        # Database dumps
    ├── airflow-db-20251127-020000.sql
    └── airflow-db-20251126-020000.sql
```

### RTO/RPO Targets

| Component | Recovery Time Objective (RTO) | Recovery Point Objective (RPO) |
|-----------|-------------------------------|--------------------------------|
| Metadata | < 15 minutes | 24 hours (daily backup) |
| DAGs | < 5 minutes | 24 hours (daily backup) |
| Database | < 30 minutes | 24 hours (daily backup) |
| **Full System** | **< 1 hour** | **24 hours** |

---

## Backup Procedures

### 1. Backup Airflow Metadata

**Export connections, variables, and pools:**

```bash
make -f make/ops/airflow.mk af-backup-metadata
```

**What it does:**
1. Executes `airflow db export-archived` in webserver pod
2. Exports connections, variables, pools to YAML
3. Saves to local `tmp/airflow-backups/metadata-<timestamp>.yaml`

**Expected output:**
```
Backing up Airflow metadata...
Backup completed: tmp/airflow-backups/metadata-20251127-143022.yaml
```

**Manual backup (alternative):**
```bash
kubectl exec -it airflow-webserver-0 -- \
  airflow connections export /tmp/connections.json

kubectl exec -it airflow-webserver-0 -- \
  airflow variables export /tmp/variables.json

kubectl cp airflow-webserver-0:/tmp/connections.json ./tmp/airflow-backups/connections.json
kubectl cp airflow-webserver-0:/tmp/variables.json ./tmp/airflow-backups/variables.json
```

### 2. Backup DAGs

**Backup DAGs from PVC:**

```bash
make -f make/ops/airflow.mk af-backup-dags
```

**What it does:**
1. Creates temporary pod with DAG PVC mounted
2. Archives all DAG files to tar.gz
3. Copies to local `tmp/airflow-backups/dags-<timestamp>/`

**Expected output:**
```
Backing up DAGs from PVC...
Backup completed: tmp/airflow-backups/dags-20251127-143022/
Total files: 42
```

**For git-sync deployments:**
```bash
# DAGs are already version-controlled in Git
git clone https://github.com/your-org/airflow-dags.git tmp/airflow-backups/dags-git/
cd tmp/airflow-backups/dags-git/
git log -1 --format="%H %ai" > backup-info.txt
```

### 3. Backup PostgreSQL Database

**Create a database dump:**

```bash
make -f make/ops/airflow.mk af-db-backup
```

**What it does:**
1. Connects to PostgreSQL pod
2. Executes `pg_dump airflow` database
3. Saves to `tmp/airflow-backups/db/airflow-db-<timestamp>.sql`

**Expected output:**
```
Backing up Airflow PostgreSQL database...
Backup completed: tmp/airflow-backups/db/airflow-db-20251127-143022.sql
Size: 245 MB
```

**Manual backup (alternative):**
```bash
kubectl exec -it postgresql-0 -- \
  pg_dump -U airflow -d airflow -F c -b -v \
  -f /tmp/airflow-backup.dump

kubectl cp postgresql-0:/tmp/airflow-backup.dump \
  ./tmp/airflow-backups/db/airflow-db-$(date +%Y%m%d-%H%M%S).dump
```

### 4. Full Backup Workflow

**Recommended full backup sequence:**

```bash
# 1. Backup metadata (connections, variables)
make -f make/ops/airflow.mk af-backup-metadata

# 2. Backup DAGs
make -f make/ops/airflow.mk af-backup-dags

# 3. Backup database
make -f make/ops/airflow.mk af-db-backup

# 4. Verify backups
ls -lh tmp/airflow-backups/metadata/
ls -lh tmp/airflow-backups/dags/
ls -lh tmp/airflow-backups/db/
```

**Backup verification:**
```bash
# Check metadata file
cat tmp/airflow-backups/metadata/metadata-*.yaml | head -20

# Check DAG files
ls tmp/airflow-backups/dags/dags-*/

# Check database dump
file tmp/airflow-backups/db/airflow-db-*.sql
```

---

## Recovery Procedures

### 1. Restore Metadata

**Restore connections and variables:**

```bash
# Copy backup to pod
kubectl cp tmp/airflow-backups/metadata/connections.json \
  airflow-webserver-0:/tmp/connections.json

kubectl cp tmp/airflow-backups/metadata/variables.json \
  airflow-webserver-0:/tmp/variables.json

# Import metadata
kubectl exec -it airflow-webserver-0 -- \
  airflow connections import /tmp/connections.json

kubectl exec -it airflow-webserver-0 -- \
  airflow variables import /tmp/variables.json
```

**Verify restoration:**
```bash
kubectl exec -it airflow-webserver-0 -- airflow connections list
kubectl exec -it airflow-webserver-0 -- airflow variables list
```

### 2. Restore DAGs

**Restore DAGs to PVC:**

```bash
kubectl cp tmp/airflow-backups/dags/dags-20251127-020000/ \
  airflow-webserver-0:/opt/airflow/dags/
```

**Verify DAG restoration:**
```bash
kubectl exec -it airflow-webserver-0 -- ls -la /opt/airflow/dags/
make -f make/ops/airflow.mk airflow-dag-list
```

**For git-sync deployments:**
```bash
# Restore to specific Git commit
cd /path/to/airflow-dags-repo
git checkout <commit-hash-from-backup>
git push origin main --force  # ⚠️ Use with caution
```

### 3. Restore Database

**Restore PostgreSQL database from backup:**

```bash
make -f make/ops/airflow.mk af-db-restore FILE=tmp/airflow-backups/db/airflow-db-20251127-020000.sql
```

**What it does:**
1. Connects to PostgreSQL pod
2. Drops existing `airflow` database (⚠️ WARNING)
3. Creates new empty `airflow` database
4. Restores from SQL dump

**Manual restore (alternative):**
```bash
# Copy backup to PostgreSQL pod
kubectl cp tmp/airflow-backups/db/airflow-backup.dump postgresql-0:/tmp/

# Drop and recreate database
kubectl exec -it postgresql-0 -- psql -U postgres -c "DROP DATABASE airflow;"
kubectl exec -it postgresql-0 -- psql -U postgres -c "CREATE DATABASE airflow OWNER airflow;"

# Restore from dump
kubectl exec -it postgresql-0 -- \
  pg_restore -U airflow -d airflow -v /tmp/airflow-backup.dump
```

**Verify restoration:**
```bash
kubectl exec -it postgresql-0 -- \
  psql -U airflow -d airflow -c "SELECT COUNT(*) FROM dag;"

kubectl exec -it postgresql-0 -- \
  psql -U airflow -d airflow -c "SELECT COUNT(*) FROM task_instance;"
```

### 4. Full Recovery Workflow

**Complete disaster recovery procedure:**

```bash
# Step 1: Restore database (most important)
make -f make/ops/airflow.mk af-db-restore FILE=tmp/airflow-backups/db/airflow-db-YYYYMMDD-HHMMSS.sql

# Step 2: Restore DAGs
kubectl cp tmp/airflow-backups/dags/dags-YYYYMMDD-HHMMSS/ airflow-webserver-0:/opt/airflow/dags/

# Step 3: Restore metadata (connections/variables)
kubectl cp tmp/airflow-backups/metadata/connections.json airflow-webserver-0:/tmp/
kubectl cp tmp/airflow-backups/metadata/variables.json airflow-webserver-0:/tmp/
kubectl exec -it airflow-webserver-0 -- airflow connections import /tmp/connections.json
kubectl exec -it airflow-webserver-0 -- airflow variables import /tmp/variables.json

# Step 4: Restart Airflow components
make -f make/ops/airflow.mk airflow-webserver-restart
make -f make/ops/airflow.mk airflow-scheduler-restart

# Step 5: Verify recovery
make -f make/ops/airflow.mk airflow-health
make -f make/ops/airflow.mk airflow-dag-list
kubectl exec -it airflow-webserver-0 -- airflow connections list
```

---

## Automation

### Automated Backup with CronJob

**⚠️ Note:** Chart does NOT include CronJob. Use external automation (Kubernetes CronJob, cron on backup server).

**Example Kubernetes CronJob:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: airflow-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: airflow-backup-sa
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # Backup metadata
              kubectl exec airflow-webserver-0 -- \
                airflow db export-archived /tmp/metadata.yaml
              kubectl cp airflow-webserver-0:/tmp/metadata.yaml \
                /backups/metadata-$(date +%Y%m%d-%H%M%S).yaml

              # Backup database
              kubectl exec postgresql-0 -- \
                pg_dump -U airflow -d airflow > /backups/db/airflow-$(date +%Y%m%d-%H%M%S).sql

              # Cleanup old backups (> 30 days)
              find /backups -type f -mtime +30 -delete
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: airflow-backup-pvc
          restartPolicy: OnFailure
```

### Backup to S3/MinIO

```bash
# Export to S3
aws s3 cp tmp/airflow-backups/ s3://my-bucket/airflow-backups/ --recursive

# Export to MinIO
mc cp --recursive tmp/airflow-backups/ minio/airflow-backups/
```

---

## Best Practices

### 1. Backup Frequency

- **Production**: Daily backups + pre-upgrade backups
- **Staging**: Weekly backups
- **Development**: On-demand backups before major changes

### 2. Retention Policy

| Backup Type | Retention | Reason |
|-------------|-----------|--------|
| Daily | 30 days | Balance storage cost vs recovery needs |
| Weekly | 90 days | Long-term recovery |
| Monthly | 1 year | Compliance/audit requirements |
| Pre-upgrade | Until next successful upgrade | Rollback safety |

### 3. Backup Verification

**Test restores quarterly:**
```bash
# Restore to test namespace
helm install airflow-test sb-charts/airflow -n airflow-test
make -f make/ops/airflow.mk af-db-restore FILE=backup.sql NAMESPACE=airflow-test

# Verify data integrity
kubectl exec -n airflow-test airflow-webserver-0 -- airflow dags list
```

### 4. Security

- **Encrypt backups at rest**: Use encrypted S3 buckets or encrypted PVCs
- **Encrypt backups in transit**: Use TLS for S3/MinIO transfers
- **Access control**: Restrict backup access to authorized personnel
- **Secrets**: Airflow connections may contain passwords - treat backups as sensitive

### 5. Monitoring

**Monitor backup jobs:**
```bash
# Check backup CronJob status
kubectl get cronjobs airflow-backup
kubectl get jobs -l cronjob=airflow-backup

# Check backup storage usage
kubectl exec -it backup-pod -- df -h /backups
```

---

## Troubleshooting

### Backup Failures

**Problem: `pg_dump` fails with "permission denied"**

**Solution:**
```bash
# Grant permissions
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "GRANT ALL ON DATABASE airflow TO airflow;"
```

**Problem: Metadata export fails**

**Solution:**
```bash
# Check Airflow webserver logs
make -f make/ops/airflow.mk airflow-webserver-logs

# Manually export connections
kubectl exec -it airflow-webserver-0 -- \
  airflow connections export /tmp/connections.json --format json
```

**Problem: DAG backup incomplete**

**Solution:**
```bash
# Verify PVC mount
kubectl exec -it airflow-webserver-0 -- ls -la /opt/airflow/dags/

# Check PVC size
kubectl get pvc -l app.kubernetes.io/name=airflow
```

### Restore Failures

**Problem: Database restore fails with "database already exists"**

**Solution:**
```bash
# Force drop and recreate
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "DROP DATABASE airflow WITH (FORCE);"
kubectl exec -it postgresql-0 -- \
  psql -U postgres -c "CREATE DATABASE airflow OWNER airflow;"
```

**Problem: DAG imports fail after restore**

**Solution:**
```bash
# Check DAG syntax errors
kubectl exec -it airflow-webserver-0 -- \
  python -m py_compile /opt/airflow/dags/*.py

# Check import errors
kubectl exec -it airflow-webserver-0 -- \
  airflow dags list-import-errors
```

**Problem: Connections not restored**

**Solution:**
```bash
# Check backup file format
cat tmp/airflow-backups/metadata/connections.json | jq .

# Import with verbose output
kubectl exec -it airflow-webserver-0 -- \
  airflow connections import /tmp/connections.json --format json --verbose
```

### Performance Issues

**Large database dumps take too long**

**Solution:**
```bash
# Use parallel dump
kubectl exec -it postgresql-0 -- \
  pg_dump -U airflow -d airflow -F d -j 4 -f /tmp/airflow-backup/

# Use compression
kubectl exec -it postgresql-0 -- \
  pg_dump -U airflow -d airflow | gzip > /tmp/airflow-backup.sql.gz
```

---

## Additional Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Airflow Upgrade Guide](airflow-upgrade-guide.md)
- [Chart README](../charts/airflow/README.md)

---

**Last Updated:** 2025-11-27
