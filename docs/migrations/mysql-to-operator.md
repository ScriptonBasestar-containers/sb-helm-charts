# MySQL Operator Migration Guide

Guide for migrating from the simple MySQL Helm chart to production-ready MySQL operators.

## Overview

This guide helps you migrate from the basic MySQL chart in this repository to a production-ready MySQL operator with high availability, automated backups, and advanced features.

**Why migrate to an operator?**
- ✅ Automated high availability (HA) with failover
- ✅ Automated backups and point-in-time recovery
- ✅ Group Replication (MySQL InnoDB Cluster)
- ✅ Monitoring and metrics
- ✅ Automated upgrades and patching
- ✅ Connection routing (MySQL Router)
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

### MySQL Operator for Kubernetes (Oracle)

**Project:** https://github.com/mysql/mysql-operator

**Pros:**
- ✅ Official MySQL operator from Oracle
- ✅ InnoDB Cluster integration (Group Replication)
- ✅ MySQL Router for connection routing
- ✅ Automated backups to object storage
- ✅ Clone plugin for fast provisioning
- ✅ Active development

**Cons:**
- ❌ Requires MySQL 8.0+
- ❌ Less flexible than Percona
- ❌ Tied to Oracle's release cycle

**Use Case:** Standard MySQL deployments, Oracle ecosystem

### Percona Operator for MySQL

**Project:** https://www.percona.com/doc/kubernetes-operator-for-pxc/

**Pros:**
- ✅ Percona XtraDB Cluster (PXC) - proven HA solution
- ✅ ProxySQL for intelligent query routing
- ✅ Percona Backup for MySQL (PBM)
- ✅ Point-in-time recovery
- ✅ TLS encryption
- ✅ Prometheus metrics
- ✅ Battle-tested

**Cons:**
- ❌ More complex than Oracle operator
- ❌ Percona-specific patches
- ❌ Larger resource footprint

**Use Case:** High availability critical, enterprise deployments

### Vitess

**Project:** https://vitess.io/

**Pros:**
- ✅ CNCF graduated project
- ✅ Horizontal scaling (sharding)
- ✅ Used by YouTube, Slack, Square
- ✅ Connection pooling built-in
- ✅ Online schema migrations

**Cons:**
- ❌ Complex architecture (VTGate, VTTablet)
- ❌ Significant learning curve
- ❌ Overkill for simple deployments
- ❌ Not drop-in MySQL compatible

**Use Case:** Large-scale deployments requiring sharding

**Our Recommendation:** **Percona Operator for MySQL** for most users due to its proven HA solution and comprehensive feature set. For simpler deployments, **MySQL Operator (Oracle)** is easier to set up.

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check current MySQL version
kubectl exec -it <mysql-pod> -- mysql -u root -p -e "SELECT VERSION();"

# Check database size
kubectl exec -it <mysql-pod> -- mysql -u root -p -e "
  SELECT table_schema AS 'Database',
         ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
  FROM information_schema.TABLES
  GROUP BY table_schema;
"

# List all databases
kubectl exec -it <mysql-pod> -- mysql -u root -p -e "SHOW DATABASES;"

# Check active connections
kubectl exec -it <mysql-pod> -- mysql -u root -p -e "SHOW PROCESSLIST;"

# Check current replication status (if applicable)
kubectl exec -it <mysql-pod> -- mysql -u root -p -e "SHOW SLAVE STATUS\G"
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-mysql-values.yaml

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i mysql

# Check current my.cnf settings
kubectl exec -it <mysql-pod> -- cat /etc/mysql/conf.d/mysql.cnf
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small databases (< 10GB): 15-30 minutes
- Medium databases (10-100GB): 30-90 minutes
- Large databases (> 100GB): 1-4 hours

**Factors affecting downtime:**
- Database size
- Network speed
- Backup/restore method
- Number of databases/tables

## Backup Procedures

### Method 1: mysqldump (Recommended for Small-Medium Databases)

**Advantages:** Clean, version-independent, selective backup
**Disadvantages:** Slower for large databases, locks tables

```bash
# Backup all databases
kubectl exec -it <mysql-pod> -- mysqldump -u root -p --all-databases --single-transaction > mysql-full-backup.sql

# Backup specific database
kubectl exec -it <mysql-pod> -- mysqldump -u root -p --single-transaction <database-name> > mysql-db-backup.sql

# Backup with routines and triggers
kubectl exec -it <mysql-pod> -- mysqldump -u root -p \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers \
  --events > mysql-complete-backup.sql

# Copy backup from pod
kubectl cp <namespace>/<mysql-pod>:/tmp/mysql-full-backup.sql ./mysql-full-backup.sql
```

### Method 2: mysqlpump (Parallel Backup)

**Advantages:** Faster than mysqldump, parallel processing
**Disadvantages:** MySQL 5.7+ required

```bash
kubectl exec -it <mysql-pod> -- mysqlpump -u root -p \
  --all-databases \
  --default-parallelism=4 > mysql-pump-backup.sql
```

### Method 3: Percona XtraBackup (Recommended for Large Databases)

**Advantages:** No locks, fast, incremental support
**Disadvantages:** Requires same MySQL version

```bash
# Install xtrabackup in MySQL pod (or use separate pod)
kubectl exec -it <mysql-pod> -- apt-get update && apt-get install -y percona-xtrabackup-80

# Full backup
kubectl exec -it <mysql-pod> -- xtrabackup --backup \
  --target-dir=/tmp/backup \
  --user=root \
  --password=<password>

# Prepare backup
kubectl exec -it <mysql-pod> -- xtrabackup --prepare --target-dir=/tmp/backup

# Compress and copy
kubectl exec -it <mysql-pod> -- tar -czvf /tmp/mysql-xtrabackup.tar.gz /tmp/backup
kubectl cp <namespace>/<mysql-pod>:/tmp/mysql-xtrabackup.tar.gz ./mysql-xtrabackup.tar.gz
```

## Migration Process

### Option A: Migrate to MySQL Operator (Oracle)

#### Step 1: Install the Operator

```bash
# Add helm repository
helm repo add mysql-operator https://mysql.github.io/mysql-operator/

# Install the operator
kubectl create namespace mysql-operator
helm install mysql-operator mysql-operator/mysql-operator \
  --namespace mysql-operator

# Verify operator is running
kubectl get pods -n mysql-operator
```

#### Step 2: Prepare InnoDB Cluster Definition

```yaml
# mysql-cluster.yaml
apiVersion: mysql.oracle.com/v2
kind: InnoDBCluster
metadata:
  name: mysql-cluster
  namespace: <target-namespace>
spec:
  # Number of instances (minimum 3 for HA)
  instances: 3

  # MySQL version
  version: "8.0.35"

  # MySQL Router instances
  router:
    instances: 1

  # Storage
  datadirVolumeClaimTemplate:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 20Gi

  # Secrets
  secretName: mysql-cluster-credentials

  # Resources
  podSpec:
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
```

#### Step 3: Create Credentials Secret

```bash
kubectl create secret generic mysql-cluster-credentials \
  --namespace <target-namespace> \
  --from-literal=rootPassword=<your-root-password> \
  --from-literal=rootUser=root \
  --from-literal=rootHost="%"
```

#### Step 4: Deploy the Cluster

```bash
kubectl apply -f mysql-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready innodbcluster/mysql-cluster -n <target-namespace> --timeout=600s
```

#### Step 5: Restore Data

```bash
# Get MySQL Router service
kubectl get svc -n <target-namespace>

# Port-forward to MySQL Router
kubectl port-forward -n <target-namespace> svc/mysql-cluster 3306:3306

# Restore from backup
mysql -h 127.0.0.1 -P 3306 -u root -p < mysql-full-backup.sql
```

### Option B: Migrate to Percona Operator for MySQL

#### Step 1: Install the Operator

```bash
# Add Percona Helm repository
helm repo add percona https://percona.github.io/percona-helm-charts/

# Create namespace
kubectl create namespace pxc

# Install the operator
helm install pxc-operator percona/pxc-operator --namespace pxc

# Verify operator is running
kubectl get pods -n pxc
```

#### Step 2: Prepare PXC Cluster Definition

```yaml
# pxc-cluster.yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBCluster
metadata:
  name: pxc-cluster
  namespace: <target-namespace>
spec:
  crVersion: 1.14.0

  # Secrets
  secretsName: pxc-cluster-secrets

  # PXC nodes
  pxc:
    size: 3
    image: percona/percona-xtradb-cluster:8.0.35
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
    volumeSpec:
      persistentVolumeClaim:
        resources:
          requests:
            storage: 20Gi

  # HAProxy for load balancing
  haproxy:
    enabled: true
    size: 2
    image: percona/percona-xtradb-cluster-operator:1.14.0-haproxy

  # ProxySQL (alternative to HAProxy)
  proxysql:
    enabled: false

  # Backup configuration
  backup:
    image: percona/percona-xtradb-cluster-operator:1.14.0-pxc8.0-backup
    storages:
      s3-backup:
        type: s3
        s3:
          bucket: my-backup-bucket
          credentialsSecret: pxc-s3-credentials
          region: us-east-1
    schedule:
      - name: daily-backup
        schedule: "0 2 * * *"
        keep: 7
        storageName: s3-backup
```

#### Step 3: Create Secrets

```bash
# Generate passwords
kubectl create secret generic pxc-cluster-secrets \
  --namespace <target-namespace> \
  --from-literal=root=<root-password> \
  --from-literal=xtrabackup=<xtrabackup-password> \
  --from-literal=monitor=<monitor-password> \
  --from-literal=clustercheck=<clustercheck-password> \
  --from-literal=proxyadmin=<proxyadmin-password> \
  --from-literal=operator=<operator-password> \
  --from-literal=replication=<replication-password>
```

#### Step 4: Deploy the Cluster

```bash
kubectl apply -f pxc-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready pxc/pxc-cluster -n <target-namespace> --timeout=900s
```

#### Step 5: Restore Data

```bash
# Get HAProxy service
kubectl get svc -n <target-namespace> | grep haproxy

# Port-forward
kubectl port-forward -n <target-namespace> svc/pxc-cluster-haproxy 3306:3306

# Restore from backup
mysql -h 127.0.0.1 -P 3306 -u root -p < mysql-full-backup.sql
```

## Verification

### 1. Check Cluster Status

```bash
# MySQL Operator (Oracle)
kubectl get innodbcluster -n <target-namespace>
kubectl describe innodbcluster mysql-cluster -n <target-namespace>

# Percona Operator
kubectl get pxc -n <target-namespace>
kubectl describe pxc pxc-cluster -n <target-namespace>
```

### 2. Verify Data Integrity

```bash
# Connect to new cluster
mysql -h <new-cluster-service> -u root -p

# Check databases
SHOW DATABASES;

# Check table counts
SELECT table_schema, COUNT(*) as tables
FROM information_schema.tables
GROUP BY table_schema;

# Verify specific tables
SELECT COUNT(*) FROM <important_table>;
```

### 3. Test Application Connectivity

```bash
# Update application connection strings to point to new cluster
# For MySQL Operator: mysql-cluster.<namespace>.svc.cluster.local:3306
# For Percona Operator: pxc-cluster-haproxy.<namespace>.svc.cluster.local:3306

# Test connection from application pod
kubectl exec -it <app-pod> -- mysql -h <new-service> -u <user> -p -e "SELECT 1;"
```

### 4. Verify Replication

```bash
# MySQL Operator - Check InnoDB Cluster status
kubectl exec -it mysql-cluster-0 -- mysqlsh root@localhost --password=<password> \
  -e "cluster=dba.getCluster(); print(cluster.status());"

# Percona Operator - Check Galera status
kubectl exec -it pxc-cluster-pxc-0 -- mysql -u root -p \
  -e "SHOW STATUS LIKE 'wsrep_cluster%';"
```

## Rollback Plan

### 1. Keep Original Deployment Running

Do NOT delete the original MySQL deployment until migration is verified:

```bash
# Scale down original deployment to save resources (but don't delete)
kubectl scale statefulset <mysql-statefulset> --replicas=0 -n <namespace>
```

### 2. Rollback Procedure

If issues occur:

```bash
# Scale up original MySQL
kubectl scale statefulset <mysql-statefulset> --replicas=1 -n <namespace>

# Update application connection strings back to original
kubectl set env deployment/<app> DATABASE_HOST=<original-mysql-service>

# Delete operator cluster (if needed)
kubectl delete innodbcluster mysql-cluster -n <target-namespace>
# or
kubectl delete pxc pxc-cluster -n <target-namespace>
```

### 3. Post-Rollback Verification

```bash
# Verify original MySQL is running
kubectl get pods -l app.kubernetes.io/name=mysql -n <namespace>

# Test application connectivity
kubectl exec -it <app-pod> -- mysql -h <original-service> -u <user> -p -e "SELECT 1;"
```

## Post-Migration Tasks

### 1. Update Application Configurations

Update all applications to use the new connection string:

```yaml
# For MySQL Operator
DATABASE_HOST: mysql-cluster.<namespace>.svc.cluster.local
DATABASE_PORT: "6446"  # MySQL Router read-write port

# For Percona Operator (HAProxy)
DATABASE_HOST: pxc-cluster-haproxy.<namespace>.svc.cluster.local
DATABASE_PORT: "3306"
```

### 2. Configure Monitoring

```bash
# MySQL Operator - Enable metrics
kubectl patch innodbcluster mysql-cluster -n <target-namespace> --type=merge \
  -p '{"spec":{"metrics":{"enabled":true}}}'

# Percona Operator - Create ServiceMonitor
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pxc-cluster
  namespace: <target-namespace>
spec:
  endpoints:
  - port: metrics
    interval: 30s
  selector:
    matchLabels:
      app.kubernetes.io/instance: pxc-cluster
EOF
```

### 3. Set Up Automated Backups

```bash
# Percona Operator - Configure backup schedule (already in cluster spec)
# MySQL Operator - Create backup schedule
cat <<EOF | kubectl apply -f -
apiVersion: mysql.oracle.com/v2
kind: MySQLBackup
metadata:
  name: daily-backup
  namespace: <target-namespace>
spec:
  clusterName: mysql-cluster
  backupProfileName: s3-backup
EOF
```

### 4. Clean Up Original Deployment

After successful migration and verification period (recommended: 1-2 weeks):

```bash
# Delete original MySQL deployment
helm uninstall <mysql-release> -n <namespace>

# Delete PVCs (after confirming backup)
kubectl delete pvc -l app.kubernetes.io/name=mysql -n <namespace>
```

### 5. Document Changes

- Update infrastructure documentation
- Update runbooks with new procedures
- Document new backup/restore procedures
- Update disaster recovery plans

## Troubleshooting

### MySQL Operator Issues

```bash
# Check operator logs
kubectl logs -n mysql-operator deploy/mysql-operator

# Check cluster events
kubectl get events -n <target-namespace> --sort-by='.lastTimestamp'

# Check individual pod logs
kubectl logs mysql-cluster-0 -n <target-namespace>
```

### Percona Operator Issues

```bash
# Check operator logs
kubectl logs -n pxc deploy/percona-xtradb-cluster-operator

# Check PXC pod logs
kubectl logs pxc-cluster-pxc-0 -n <target-namespace> -c pxc

# Check HAProxy logs
kubectl logs pxc-cluster-haproxy-0 -n <target-namespace>
```

### Common Issues

1. **Cluster not forming:** Check network policies, ensure pods can communicate
2. **Backup failures:** Verify S3 credentials and bucket permissions
3. **Slow performance:** Check resource limits, PVC IOPS
4. **Connection refused:** Verify service endpoints and firewall rules

## References

- [MySQL Operator Documentation](https://dev.mysql.com/doc/mysql-operator/en/)
- [Percona Operator Documentation](https://www.percona.com/doc/kubernetes-operator-for-pxc/index.html)
- [Vitess Documentation](https://vitess.io/docs/)
- [MySQL Group Replication](https://dev.mysql.com/doc/refman/8.0/en/group-replication.html)
- [Percona XtraDB Cluster](https://www.percona.com/doc/percona-xtradb-cluster/LATEST/index.html)
