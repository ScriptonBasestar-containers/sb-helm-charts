# PostgreSQL Operator Migration Guide

Guide for migrating from the simple PostgreSQL Helm chart to production-ready PostgreSQL operators.

## Overview

This guide helps you migrate from the basic PostgreSQL chart in this repository to a production-ready PostgreSQL operator with high availability, automated backups, and advanced features.

**Why migrate to an operator?**
- ✅ Automated high availability (HA) with failover
- ✅ Automated backups and point-in-time recovery
- ✅ Connection pooling (PgBouncer)
- ✅ Monitoring and metrics
- ✅ Automated upgrades and patching
- ✅ Logical replication support
- ✅ Production-grade reliability

## Table of Contents

- [Operator Comparison](#operator-comparison)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Backup Procedures](#backup-procedures)
- [Migration Process](#migration-process)
- [Verification](#verification)
- [Rollback Plan](#rollback-plan)
- [Post-Migration Tasks](#post-migration-tasks)

## Operator Comparison

### CloudNativePG (Recommended)

**Project:** https://cloudnative-pg.io/

**Pros:**
- ✅ Cloud Native Computing Foundation (CNCF) Sandbox project
- ✅ Modern Kubernetes-native design
- ✅ Built-in backup/restore (Barman)
- ✅ Connection pooling (PgBouncer)
- ✅ Excellent monitoring (Prometheus)
- ✅ Active development and community
- ✅ Simple CRD-based configuration

**Cons:**
- ❌ Newer project (less battle-tested than Zalando)
- ❌ Smaller community than Zalando

**Use Case:** Modern Kubernetes deployments, cloud-native architecture

### Zalando Postgres Operator

**Project:** https://github.com/zalando/postgres-operator

**Pros:**
- ✅ Battle-tested in production (Zalando uses it internally)
- ✅ Patroni-based (proven HA solution)
- ✅ Mature project with long history
- ✅ Good WAL-E/WAL-G backup support
- ✅ Multi-master support

**Cons:**
- ❌ More complex setup
- ❌ Older architecture patterns
- ❌ Less intuitive CRD design

**Use Case:** Enterprises needing proven stability, existing Patroni users

### Crunchy Data Postgres Operator

**Project:** https://access.crunchydata.com/documentation/postgres-operator/

**Pros:**
- ✅ Commercial support available
- ✅ Comprehensive feature set
- ✅ Good backup/restore options
- ✅ TLS/encryption support
- ✅ pgBackRest integration

**Cons:**
- ❌ Complex CRD structure
- ❌ Heavier resource usage
- ❌ Enterprise-focused (more features than needed for simple deployments)

**Use Case:** Enterprises requiring commercial support

**Our Recommendation:** **CloudNativePG** for most users due to its modern design, simplicity, and active development.

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check current PostgreSQL version
kubectl exec -it <postgres-pod> -- psql -U postgres -c "SELECT version();"

# Check database size
kubectl exec -it <postgres-pod> -- psql -U postgres -c "
  SELECT pg_size_pretty(pg_database_size('postgres')) as size;
"

# List all databases
kubectl exec -it <postgres-pod> -- psql -U postgres -c "\l"

# Check active connections
kubectl exec -it <postgres-pod> -- psql -U postgres -c "
  SELECT count(*) FROM pg_stat_activity;
"
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-postgres-values.yaml

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i postgres
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small databases (< 10GB): 10-30 minutes
- Medium databases (10-100GB): 30-90 minutes
- Large databases (> 100GB): 1-4 hours

**Factors affecting downtime:**
- Database size
- Network speed
- Backup/restore method
- Number of databases/tables

## Backup Procedures

### Method 1: pg_dump (Recommended for Small-Medium Databases)

**Advantages:** Clean, version-independent, selective backup
**Disadvantages:** Slower for large databases

```bash
# Create backup directory
kubectl exec -it <postgres-pod> -- mkdir -p /tmp/backup

# Backup all databases
kubectl exec -it <postgres-pod> -- pg_dumpall -U postgres > postgres-full-backup.sql

# Or backup individual databases
kubectl exec -it <postgres-pod> -- pg_dump -U postgres <database-name> > postgres-db-backup.sql

# Copy backup from pod to local machine
kubectl cp <namespace>/<postgres-pod>:/tmp/backup/postgres-full-backup.sql ./postgres-full-backup.sql

# Verify backup
grep -i "PostgreSQL database dump" postgres-full-backup.sql
```

### Method 2: Physical Backup (For Large Databases)

**Advantages:** Faster for large databases, includes WAL
**Disadvantages:** Version-specific, requires more disk space

```bash
# Stop PostgreSQL (if possible, for consistent backup)
kubectl exec -it <postgres-pod> -- su - postgres -c "pg_ctl stop -D /var/lib/postgresql/data"

# Create tar backup of data directory
kubectl exec -it <postgres-pod> -- tar czf /tmp/postgres-data-backup.tar.gz /var/lib/postgresql/data

# Copy backup
kubectl cp <namespace>/<postgres-pod>:/tmp/postgres-data-backup.tar.gz ./postgres-data-backup.tar.gz

# Restart PostgreSQL
kubectl exec -it <postgres-pod> -- su - postgres -c "pg_ctl start -D /var/lib/postgresql/data"
```

### Method 3: PVC Snapshot (Cloud Native)

```bash
# Create VolumeSnapshot (if your storage class supports it)
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot
  namespace: <namespace>
spec:
  volumeSnapshotClassName: <snapshot-class>
  source:
    persistentVolumeClaimName: <postgres-pvc-name>
EOF

# Verify snapshot
kubectl get volumesnapshot postgres-snapshot -n <namespace>
```

## Migration Process

### Option A: CloudNativePG Migration (Recommended)

**Step 1: Install CloudNativePG Operator**

```bash
# Add CloudNativePG Helm repository
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

# Install operator
helm install cnpg cnpg/cloudnative-pg \
  -n cnpg-system \
  --create-namespace
```

**Step 2: Create CloudNativePG Cluster**

```yaml
# postgres-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
  namespace: default
spec:
  instances: 3  # HA with 3 replicas

  # PostgreSQL version
  imageName: ghcr.io/cloudnative-pg/postgresql:16.1

  # Bootstrap from backup (we'll use this for migration)
  bootstrap:
    initdb:
      database: postgres
      owner: postgres
      secret:
        name: postgres-superuser

  # Storage
  storage:
    size: 20Gi
    storageClass: standard

  # Backup configuration
  backup:
    barmanObjectStore:
      destinationPath: s3://postgres-backups/
      s3Credentials:
        accessKeyId:
          name: backup-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-creds
          key: ACCESS_SECRET_KEY
      wal:
        compression: gzip
    retentionPolicy: "30d"

  # Connection pooling
  pooler:
    enabled: true
    instances: 2
    type: rw
    pgbouncer:
      poolMode: session
      parameters:
        max_client_conn: "1000"
        default_pool_size: "25"

  # Monitoring
  monitoring:
    enabled: true
    podMonitorEnabled: true

  # Resources
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

**Step 3: Create Secrets**

```bash
# Create superuser password
kubectl create secret generic postgres-superuser \
  -n default \
  --from-literal=password=<secure-password>

# Create backup credentials (if using S3)
kubectl create secret generic backup-creds \
  -n default \
  --from-literal=ACCESS_KEY_ID=<access-key> \
  --from-literal=ACCESS_SECRET_KEY=<secret-key>
```

**Step 4: Apply Cluster Configuration**

```bash
kubectl apply -f postgres-cluster.yaml
```

**Step 5: Wait for Cluster Ready**

```bash
# Watch cluster status
kubectl get cluster postgres-cluster -n default -w

# Check pods
kubectl get pods -n default -l cnpg.io/cluster=postgres-cluster
```

**Step 6: Restore Data**

```bash
# Copy backup to operator pod
kubectl cp postgres-full-backup.sql default/postgres-cluster-1:/tmp/

# Restore data
kubectl exec -it postgres-cluster-1 -n default -- \
  psql -U postgres -f /tmp/postgres-full-backup.sql
```

**Step 7: Update Application Connection Strings**

```yaml
# Old connection (simple chart)
postgresql.default.svc.cluster.local:5432

# New connection (CloudNativePG)
postgres-cluster-rw.default.svc.cluster.local:5432  # Read-Write service
postgres-cluster-ro.default.svc.cluster.local:5432  # Read-Only service
postgres-cluster-r.default.svc.cluster.local:5432   # Any replica

# With pooler
postgres-cluster-pooler-rw.default.svc.cluster.local:5432
```

**Step 8: Verify and Test**

```bash
# Test connection
kubectl run -it --rm psql-test --image=postgres:16 --restart=Never -- \
  psql -h postgres-cluster-rw.default.svc.cluster.local -U postgres

# Verify data
kubectl exec -it postgres-cluster-1 -n default -- \
  psql -U postgres -c "SELECT count(*) FROM <your-table>;"

# Check replication status
kubectl exec -it postgres-cluster-1 -n default -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**Step 9: Decommission Old Chart**

```bash
# Scale down applications to prevent writes
kubectl scale deployment <app> --replicas=0

# Uninstall old PostgreSQL chart
helm uninstall <postgres-release> -n <namespace>

# Optional: Delete old PVC (after verifying new setup works)
kubectl delete pvc <old-pvc-name> -n <namespace>
```

### Option B: Zalando Operator Migration

**Step 1: Install Zalando Operator**

```bash
# Install operator
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update

helm install postgres-operator postgres-operator-charts/postgres-operator \
  -n postgres-operator \
  --create-namespace
```

**Step 2: Create Postgres Cluster**

```yaml
# postgres-manifest.yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: acid-postgres-cluster
  namespace: default
spec:
  teamId: "myteam"
  volume:
    size: 20Gi
  numberOfInstances: 3
  users:
    zalando:  # database owner
    - superuser
    - createdb
  databases:
    myapp: zalando  # dbname: owner
  postgresql:
    version: "16"
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "1"
      memory: 2Gi
  patroni:
    initdb:
      encoding: "UTF8"
      locale: "en_US.UTF-8"
      data-checksums: "true"
    pg_hba:
      - hostssl all all 0.0.0.0/0 md5
      - host    all all 0.0.0.0/0 md5
```

```bash
kubectl apply -f postgres-manifest.yaml
```

**Step 3: Restore Data** (similar to CloudNativePG process)

## Verification

### Connection Test

```bash
# Test read-write connection
kubectl run -it --rm psql-test --image=postgres:16 --restart=Never -- \
  psql -h <new-postgres-service> -U postgres -c "SELECT version();"

# Test write
kubectl run -it --rm psql-test --image=postgres:16 --restart=Never -- \
  psql -h <new-postgres-service> -U postgres -c "
    CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);
    INSERT INTO test (data) VALUES ('migration test');
    SELECT * FROM test;
    DROP TABLE test;
  "
```

### Data Validation

```bash
# Compare row counts
kubectl exec -it <new-postgres-pod> -- \
  psql -U postgres -d <database> -c "
    SELECT
      schemaname,
      tablename,
      n_tup_ins as inserts,
      n_tup_upd as updates,
      n_tup_del as deletes
    FROM pg_stat_user_tables;
  "

# Check database sizes
kubectl exec -it <new-postgres-pod> -- \
  psql -U postgres -c "
    SELECT datname, pg_size_pretty(pg_database_size(datname))
    FROM pg_database;
  "
```

### High Availability Test

```bash
# Delete primary pod (should trigger automatic failover)
kubectl delete pod <primary-pod> -n <namespace>

# Watch failover
kubectl get pods -n <namespace> -w

# Verify new primary
kubectl exec -it <new-primary-pod> -n <namespace> -- \
  psql -U postgres -c "SELECT pg_is_in_recovery();"  # Should return 'f' for primary
```

## Rollback Plan

### If Migration Fails

**Step 1: Reinstall Old Chart**

```bash
# Reinstall from backup values
helm install <postgres-release> sb-charts/postgresql \
  -n <namespace> \
  -f current-postgres-values.yaml
```

**Step 2: Restore Data**

```bash
# Wait for pod ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n <namespace>

# Restore from backup
kubectl cp postgres-full-backup.sql <namespace>/<postgres-pod>:/tmp/
kubectl exec -it <postgres-pod> -n <namespace> -- \
  psql -U postgres -f /tmp/postgres-full-backup.sql
```

**Step 3: Update Applications**

```bash
# Update connection strings back to old service
kubectl set env deployment/<app> \
  DATABASE_HOST=postgresql.default.svc.cluster.local
```

## Post-Migration Tasks

### 1. Configure Backups

**CloudNativePG:**
```bash
# Trigger manual backup
kubectl cnpg backup postgres-cluster -n default

# View backups
kubectl get backup -n default

# Schedule automated backups (already configured in cluster spec)
```

### 2. Set Up Monitoring

**Enable Prometheus ServiceMonitor:**
```yaml
# Already enabled in cluster spec
monitoring:
  enabled: true
  podMonitorEnabled: true
```

**Import Grafana Dashboard:**
- CloudNativePG Dashboard: https://grafana.com/grafana/dashboards/16645

### 3. Configure Connection Pooling

**CloudNativePG Pooler:**
```yaml
# Already configured in cluster spec
pooler:
  enabled: true
  type: rw
  pgbouncer:
    poolMode: session  # or transaction
    parameters:
      max_client_conn: "1000"
```

**Update application to use pooler:**
```
postgres-cluster-pooler-rw.default.svc.cluster.local:5432
```

### 4. Test Disaster Recovery

```bash
# Simulate disaster
kubectl delete cluster postgres-cluster -n default

# Restore from backup
kubectl cnpg restore postgres-cluster \
  --backup postgres-cluster-backup-20240101120000 \
  -n default
```

### 5. Update Documentation

- Document new connection strings
- Update runbooks with operator-specific commands
- Train team on operator management

## Troubleshooting

### Issue: Connection refused after migration

```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Check pod logs
kubectl logs -n <namespace> <postgres-pod>

# Verify network policies
kubectl get networkpolicy -n <namespace>
```

### Issue: Data inconsistency

```bash
# Check replication lag
kubectl exec -it <primary-pod> -n <namespace> -- \
  psql -U postgres -c "
    SELECT
      client_addr,
      state,
      sync_state,
      replay_lag
    FROM pg_stat_replication;
  "

# Force checkpoint
kubectl exec -it <primary-pod> -n <namespace> -- \
  psql -U postgres -c "CHECKPOINT;"
```

### Issue: Performance degradation

```bash
# Check connection pooling is working
kubectl logs -n <namespace> <pooler-pod>

# Analyze slow queries
kubectl exec -it <primary-pod> -n <namespace> -- \
  psql -U postgres -c "
    SELECT query, calls, total_time, mean_time
    FROM pg_stat_statements
    ORDER BY total_time DESC
    LIMIT 10;
  "
```

## Additional Resources

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Zalando Postgres Operator](https://postgres-operator.readthedocs.io/)
- [PostgreSQL High Availability Guide](https://www.postgresql.org/docs/current/high-availability.html)
- [Chart Catalog](../CHARTS.md) - Browse all available charts

---

**Need help?** Open an issue at https://github.com/scriptonbasestar-container/sb-helm-charts/issues

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
