# MongoDB Operator Migration Guide

Guide for migrating from the simple MongoDB Helm chart to production-ready MongoDB operators.

## Overview

This guide helps you migrate from the basic MongoDB chart in this repository to a production-ready MongoDB operator with high availability, automated backups, and advanced features.

**Why migrate to an operator?**
- ✅ Automated high availability (replica sets, sharding)
- ✅ Automated backups and point-in-time recovery
- ✅ Automatic failover and recovery
- ✅ Monitoring and metrics
- ✅ Automated upgrades and patching
- ✅ TLS/SSL encryption
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

### MongoDB Community Operator

**Project:** https://github.com/mongodb/mongodb-kubernetes-operator

**Pros:**
- ✅ Official operator from MongoDB Inc.
- ✅ Free and open source
- ✅ Replica set support
- ✅ TLS encryption
- ✅ User management
- ✅ Simple CRD design
- ✅ Active development

**Cons:**
- ❌ No sharding support (replica sets only)
- ❌ Limited backup features
- ❌ No enterprise features

**Use Case:** Development, small-medium production workloads

### MongoDB Enterprise Operator

**Project:** https://www.mongodb.com/docs/kubernetes-operator/

**Pros:**
- ✅ Official MongoDB Enterprise operator
- ✅ Ops Manager integration
- ✅ Sharding support
- ✅ Automated backups
- ✅ Advanced monitoring
- ✅ Enterprise security features
- ✅ Commercial support

**Cons:**
- ❌ Requires MongoDB Enterprise license
- ❌ Ops Manager dependency
- ❌ Complex setup
- ❌ Higher cost

**Use Case:** Enterprise deployments, large-scale production

### Percona Operator for MongoDB

**Project:** https://www.percona.com/doc/kubernetes-operator-for-psmongodb/

**Pros:**
- ✅ Free and open source
- ✅ Sharding support
- ✅ Automated backups (S3, Azure, GCS)
- ✅ Point-in-time recovery
- ✅ Prometheus metrics
- ✅ TLS encryption
- ✅ Active community

**Cons:**
- ❌ Uses Percona Server for MongoDB (not vanilla MongoDB)
- ❌ More complex than Community Operator
- ❌ Larger resource footprint

**Use Case:** Production HA deployments without enterprise license

**Our Recommendation:** **Percona Operator for MongoDB** for production deployments requiring HA and backups without enterprise licensing. For simpler deployments, **MongoDB Community Operator** is easier to manage.

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check current MongoDB version
kubectl exec -it <mongodb-pod> -- mongosh --eval "db.version()"

# Check database sizes
kubectl exec -it <mongodb-pod> -- mongosh --eval "
  db.adminCommand('listDatabases').databases.forEach(function(db) {
    print(db.name + ': ' + (db.sizeOnDisk / 1024 / 1024).toFixed(2) + ' MB');
  });
"

# List all databases
kubectl exec -it <mongodb-pod> -- mongosh --eval "show dbs"

# Check replication status (if applicable)
kubectl exec -it <mongodb-pod> -- mongosh --eval "rs.status()"

# Check current oplog size
kubectl exec -it <mongodb-pod> -- mongosh --eval "
  db.getReplicationInfo()
"
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-mongodb-values.yaml

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i mongo

# Check current configuration
kubectl exec -it <mongodb-pod> -- cat /etc/mongod.conf
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small databases (< 10GB): 15-30 minutes
- Medium databases (10-100GB): 30-90 minutes
- Large databases (> 100GB): 1-4 hours

**Factors affecting downtime:**
- Database size
- Number of collections
- Index complexity
- Network speed

## Backup Procedures

### Method 1: mongodump (Recommended for Small-Medium Databases)

**Advantages:** Portable, human-readable, selective backup
**Disadvantages:** Slower for large databases

```bash
# Backup all databases
kubectl exec -it <mongodb-pod> -- mongodump \
  --out=/tmp/backup \
  --oplog

# Copy backup from pod
kubectl cp <namespace>/<mongodb-pod>:/tmp/backup ./mongodb-backup

# Backup specific database
kubectl exec -it <mongodb-pod> -- mongodump \
  --db=<database-name> \
  --out=/tmp/backup

# Backup with authentication
kubectl exec -it <mongodb-pod> -- mongodump \
  --username=<user> \
  --password=<password> \
  --authenticationDatabase=admin \
  --out=/tmp/backup
```

### Method 2: Filesystem Snapshot (Recommended for Large Databases)

**Advantages:** Fast, complete backup
**Disadvantages:** Requires consistent state, storage-dependent

```bash
# Lock the database for consistent snapshot
kubectl exec -it <mongodb-pod> -- mongosh --eval "db.fsyncLock()"

# Create PVC snapshot (example for CSI snapshots)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mongodb-snapshot
  namespace: <namespace>
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: data-mongodb-0
EOF

# Unlock the database
kubectl exec -it <mongodb-pod> -- mongosh --eval "db.fsyncUnlock()"
```

### Method 3: MongoDB Atlas Backup (For Atlas migrations)

If migrating to MongoDB Atlas:

```bash
# Install mongodump with Atlas support
# Use MongoDB Database Tools 100.5.0+

# Export to Atlas
mongodump --uri="mongodb://<source>:27017" --out=/tmp/backup
mongorestore --uri="mongodb+srv://<atlas-cluster>" /tmp/backup
```

## Migration Process

### Option A: Migrate to MongoDB Community Operator

#### Step 1: Install the Operator

```bash
# Clone the operator repository
git clone https://github.com/mongodb/mongodb-kubernetes-operator.git
cd mongodb-kubernetes-operator

# Install CRDs
kubectl apply -f config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml

# Create operator namespace
kubectl create namespace mongodb-operator

# Install operator
kubectl apply -k config/default --namespace mongodb-operator

# Verify operator is running
kubectl get pods -n mongodb-operator
```

#### Step 2: Prepare MongoDB Replica Set Definition

```yaml
# mongodb-replicaset.yaml
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: mongodb-cluster
  namespace: <target-namespace>
spec:
  # Number of members (odd number recommended)
  members: 3

  # MongoDB version
  type: ReplicaSet
  version: "7.0.14"

  # Security
  security:
    authentication:
      modes: ["SCRAM"]
    tls:
      enabled: false  # Enable for production

  # Users
  users:
    - name: admin
      db: admin
      passwordSecretRef:
        name: mongodb-admin-password
      roles:
        - name: clusterAdmin
          db: admin
        - name: userAdminAnyDatabase
          db: admin
        - name: dbAdminAnyDatabase
          db: admin
        - name: readWriteAnyDatabase
          db: admin
      scramCredentialsSecretName: mongodb-admin-scram

  # Storage
  statefulSet:
    spec:
      volumeClaimTemplates:
        - metadata:
            name: data-volume
          spec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 20Gi

  # Resources
  additionalMongodConfig:
    storage.wiredTiger.engineConfig.journalCompressor: snappy
    net.compression.compressors: snappy,zlib
```

#### Step 3: Create Secrets

```bash
# Create password secret
kubectl create secret generic mongodb-admin-password \
  --namespace <target-namespace> \
  --from-literal=password=<your-admin-password>
```

#### Step 4: Deploy the Replica Set

```bash
kubectl apply -f mongodb-replicaset.yaml

# Wait for replica set to be ready
kubectl wait --for=condition=Ready mongodbcommunity/mongodb-cluster \
  -n <target-namespace> --timeout=600s

# Check status
kubectl get mongodbcommunity -n <target-namespace>
```

#### Step 5: Restore Data

```bash
# Get connection string
kubectl get secret mongodb-cluster-admin-admin \
  -n <target-namespace> \
  -o jsonpath='{.data.connectionString\.standard}' | base64 -d

# Port-forward to MongoDB
kubectl port-forward -n <target-namespace> svc/mongodb-cluster-svc 27017:27017

# Restore from backup
mongorestore --host=localhost:27017 \
  --username=admin \
  --password=<password> \
  --authenticationDatabase=admin \
  ./mongodb-backup
```

### Option B: Migrate to Percona Operator for MongoDB

#### Step 1: Install the Operator

```bash
# Add Percona Helm repository
helm repo add percona https://percona.github.io/percona-helm-charts/

# Create namespace
kubectl create namespace psmdb

# Install the operator
helm install psmdb-operator percona/psmdb-operator --namespace psmdb

# Verify operator is running
kubectl get pods -n psmdb
```

#### Step 2: Prepare PSMDB Cluster Definition

```yaml
# psmdb-cluster.yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: mongodb-cluster
  namespace: <target-namespace>
spec:
  crVersion: 1.16.0
  image: percona/percona-server-mongodb:7.0.14-8

  # Secrets
  secrets:
    users: mongodb-cluster-secrets

  # Replica Set
  replsets:
    - name: rs0
      size: 3
      configuration: |
        operationProfiling:
          mode: slowOp
          slowOpThresholdMs: 100
        storage:
          wiredTiger:
            engineConfig:
              journalCompressor: snappy
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 20Gi
      resources:
        limits:
          cpu: "2"
          memory: "4G"
        requests:
          cpu: "500m"
          memory: "1G"

  # MongoDB mongos (for sharding)
  sharding:
    enabled: false

  # Backup configuration
  backup:
    enabled: true
    image: percona/percona-backup-mongodb:2.4.1
    storages:
      s3-backup:
        type: s3
        s3:
          bucket: my-backup-bucket
          region: us-east-1
          credentialsSecret: mongodb-s3-credentials
    tasks:
      - name: daily-backup
        enabled: true
        schedule: "0 2 * * *"
        keep: 7
        storageName: s3-backup
        compressionType: gzip
```

#### Step 3: Create Secrets

```bash
# Create users secret
kubectl create secret generic mongodb-cluster-secrets \
  --namespace <target-namespace> \
  --from-literal=MONGODB_BACKUP_USER=backup \
  --from-literal=MONGODB_BACKUP_PASSWORD=<backup-password> \
  --from-literal=MONGODB_CLUSTER_ADMIN_USER=clusterAdmin \
  --from-literal=MONGODB_CLUSTER_ADMIN_PASSWORD=<cluster-admin-password> \
  --from-literal=MONGODB_CLUSTER_MONITOR_USER=clusterMonitor \
  --from-literal=MONGODB_CLUSTER_MONITOR_PASSWORD=<monitor-password> \
  --from-literal=MONGODB_USER_ADMIN_USER=userAdmin \
  --from-literal=MONGODB_USER_ADMIN_PASSWORD=<user-admin-password>

# Create S3 credentials (if using S3 backup)
kubectl create secret generic mongodb-s3-credentials \
  --namespace <target-namespace> \
  --from-literal=AWS_ACCESS_KEY_ID=<access-key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key>
```

#### Step 4: Deploy the Cluster

```bash
kubectl apply -f psmdb-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready psmdb/mongodb-cluster \
  -n <target-namespace> --timeout=900s

# Check status
kubectl get psmdb -n <target-namespace>
```

#### Step 5: Restore Data

```bash
# Get connection string
kubectl get secret mongodb-cluster-secrets \
  -n <target-namespace> \
  -o jsonpath='{.data.MONGODB_USER_ADMIN_PASSWORD}' | base64 -d

# Port-forward
kubectl port-forward -n <target-namespace> svc/mongodb-cluster-rs0 27017:27017

# Restore from backup
mongorestore --host=localhost:27017 \
  --username=userAdmin \
  --password=<password> \
  --authenticationDatabase=admin \
  ./mongodb-backup
```

## Verification

### 1. Check Cluster Status

```bash
# MongoDB Community Operator
kubectl get mongodbcommunity -n <target-namespace>
kubectl describe mongodbcommunity mongodb-cluster -n <target-namespace>

# Percona Operator
kubectl get psmdb -n <target-namespace>
kubectl describe psmdb mongodb-cluster -n <target-namespace>
```

### 2. Verify Replica Set Status

```bash
# Connect to MongoDB
kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh --eval "rs.status()"

# Check replication lag
kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh --eval "
  rs.printReplicationInfo()
"
```

### 3. Verify Data Integrity

```bash
# Connect and check databases
kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh --eval "show dbs"

# Check collection counts
kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh <database> --eval "
  db.getCollectionNames().forEach(function(c) {
    print(c + ': ' + db.getCollection(c).countDocuments());
  });
"

# Verify indexes
kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh <database> --eval "
  db.getCollectionNames().forEach(function(c) {
    print('Collection: ' + c);
    printjson(db.getCollection(c).getIndexes());
  });
"
```

### 4. Test Application Connectivity

```bash
# Get service endpoint
kubectl get svc -n <target-namespace>

# Test connection from application pod
kubectl exec -it <app-pod> -- mongosh \
  "mongodb://mongodb-cluster-svc.<namespace>.svc.cluster.local:27017" \
  --eval "db.adminCommand('ping')"
```

## Rollback Plan

### 1. Keep Original Deployment Running

```bash
# Scale down original deployment (but don't delete)
kubectl scale statefulset <mongodb-statefulset> --replicas=0 -n <namespace>
```

### 2. Rollback Procedure

If issues occur:

```bash
# Scale up original MongoDB
kubectl scale statefulset <mongodb-statefulset> --replicas=1 -n <namespace>

# Update application connection strings
kubectl set env deployment/<app> MONGODB_URI=<original-mongodb-uri>

# Delete operator cluster (if needed)
kubectl delete mongodbcommunity mongodb-cluster -n <target-namespace>
# or
kubectl delete psmdb mongodb-cluster -n <target-namespace>
```

## Post-Migration Tasks

### 1. Update Application Configurations

```yaml
# MongoDB Community Operator
MONGODB_URI: mongodb://admin:<password>@mongodb-cluster-svc.<namespace>.svc.cluster.local:27017/admin?replicaSet=mongodb-cluster

# Percona Operator
MONGODB_URI: mongodb://userAdmin:<password>@mongodb-cluster-rs0.<namespace>.svc.cluster.local:27017/admin?replicaSet=rs0
```

### 2. Configure Monitoring

```bash
# Percona Operator - Enable PMM (Percona Monitoring and Management)
kubectl patch psmdb mongodb-cluster -n <target-namespace> --type=merge \
  -p '{"spec":{"pmm":{"enabled":true,"serverHost":"pmm-server"}}}'

# Create ServiceMonitor for Prometheus
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-cluster
  namespace: <target-namespace>
spec:
  endpoints:
  - port: mongodb-exporter
    interval: 30s
  selector:
    matchLabels:
      app.kubernetes.io/instance: mongodb-cluster
EOF
```

### 3. Configure Backups (Percona Operator)

```bash
# Trigger manual backup
cat <<EOF | kubectl apply -f -
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: manual-backup
  namespace: <target-namespace>
spec:
  clusterName: mongodb-cluster
  storageName: s3-backup
EOF

# Check backup status
kubectl get psmdb-backup -n <target-namespace>
```

### 4. Clean Up Original Deployment

After verification period (1-2 weeks):

```bash
# Delete original MongoDB
helm uninstall <mongodb-release> -n <namespace>

# Delete PVCs
kubectl delete pvc -l app.kubernetes.io/name=mongodb -n <namespace>
```

## Troubleshooting

### Common Issues

1. **Replica set not initializing:**
   ```bash
   kubectl logs mongodb-cluster-0 -n <target-namespace>
   kubectl exec -it mongodb-cluster-0 -n <target-namespace> -- mongosh --eval "rs.initiate()"
   ```

2. **Authentication failures:**
   ```bash
   # Check secrets are properly created
   kubectl get secret -n <target-namespace>
   kubectl describe secret mongodb-cluster-secrets -n <target-namespace>
   ```

3. **Slow startup:**
   - Check PVC provisioning
   - Verify resource limits
   - Check for network policy issues

4. **Backup failures:**
   ```bash
   # Check backup pod logs
   kubectl logs -l app.kubernetes.io/component=backup -n <target-namespace>
   ```

## References

- [MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator)
- [MongoDB Enterprise Operator](https://www.mongodb.com/docs/kubernetes-operator/)
- [Percona Operator for MongoDB](https://www.percona.com/doc/kubernetes-operator-for-psmongodb/)
- [MongoDB Backup Best Practices](https://www.mongodb.com/docs/manual/core/backups/)
- [MongoDB Replica Set Configuration](https://www.mongodb.com/docs/manual/replication/)
