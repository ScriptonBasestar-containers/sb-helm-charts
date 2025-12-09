# MongoDB Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 7.0.14](https://img.shields.io/badge/AppVersion-7.0.14-informational?style=flat-square)

MongoDB NoSQL database with replica set support for Kubernetes

## Features

- **StatefulSet Deployment**: Stable pod identities with persistent storage
- **Replica Set Support**: Automatic replica set initialization and management
- **Persistent Storage**: PersistentVolumeClaim with configurable storage class
- **Configuration Management**: Complete mongod.conf via ConfigMap
- **Security**: Authentication enabled, secrets for passwords, non-root execution
- **Health Probes**: Liveness and readiness using mongosh
- **Resource Management**: Configurable CPU/memory limits
- **Operational Tools**: 40+ Makefile commands for database management

## TL;DR

```bash
# Add the repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install single node
helm install my-mongodb scripton-charts/mongodb

# Install replica set (3 members)
helm install my-mongodb scripton-charts/mongodb \
  --set replicaCount=3 \
  --set mongodb.replicaSet.enabled=true \
  --set mongodb.rootPassword=securePassword \
  --set mongodb.replicaSet.key=your32CharacterReplicaSetKey
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support

## Installing the Chart

### Basic Installation

```bash
helm install my-mongodb scripton-charts/mongodb
```

### Development Installation

```bash
helm install my-mongodb scripton-charts/mongodb \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mongodb/values-dev.yaml
```

### Production with Replica Set

```bash
helm install my-mongodb scripton-charts/mongodb \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mongodb/values-small-prod.yaml \
  --set mongodb.rootPassword=securePassword \
  --set mongodb.replicaSet.key=your32CharacterReplicaSetKey
```

## Uninstalling the Chart

```bash
helm uninstall my-mongodb
```

**Note**: PVCs are not auto-deleted. Delete manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=my-mongodb
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of MongoDB replicas | `1` |
| `mongodb.database` | Initial database name | `admin` |
| `mongodb.rootPassword` | Root password (auto-generated if empty) | `""` |
| `mongodb.auth.enabled` | Enable authentication | `true` |
| `mongodb.wiredTiger.cacheSizeGB` | WiredTiger cache size | `0.25` |
| `mongodb.replicaSet.enabled` | Enable replica set | `false` |
| `mongodb.replicaSet.name` | Replica set name | `rs0` |
| `mongodb.replicaSet.key` | Replica set key | `""` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC storage size | `10Gi` |
| `persistence.storageClass` | PVC storage class | `""` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.limits.cpu` | CPU limit | `1000m` |

## Replica Set Architecture

```
┌──────────────────┐
│   mongodb-0      │
│   (Primary)      │
│   Read + Write   │
└────────┬─────────┘
         │ Oplog replication
         ├──────────────┬────────────────┐
         │              │                │
         ▼              ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  mongodb-1   │ │  mongodb-2   │ │  mongodb-N   │
│  (Secondary) │ │  (Secondary) │ │  (Secondary) │
│  Read Only   │ │  Read Only   │ │  Read Only   │
└──────────────┘ └──────────────┘ └──────────────┘
```

### Replica Set Setup

1. Install with odd number of members (3, 5, or 7 recommended):

```bash
helm install my-mongodb scripton-charts/mongodb \
  --set replicaCount=3 \
  --set mongodb.replicaSet.enabled=true \
  --set mongodb.replicaSet.name=rs0 \
  --set mongodb.rootPassword=myPassword \
  --set mongodb.replicaSet.key=$(openssl rand -base64 24)
```

2. Check replica set status:

```bash
make -f make/ops/mongodb.mk mongo-rs-status
```

3. Connection URI for applications:

```
mongodb://mongodb-0.mongodb-headless:27017,mongodb-1.mongodb-headless:27017,mongodb-2.mongodb-headless:27017/mydb?replicaSet=rs0
```

## Backup and Restore

### Backup

```bash
make -f make/ops/mongodb.mk mongo-backup
```

This creates a compressed backup in `tmp/mongodb-backups/`.

### Restore

```bash
make -f make/ops/mongodb.mk mongo-restore FILE=tmp/mongodb-backups/mongodb-backup-20240101.gz
```

## Operational Commands

### Basic Operations

```bash
make -f make/ops/mongodb.mk mongo-shell
make -f make/ops/mongodb.mk mongo-logs
make -f make/ops/mongodb.mk mongo-port-forward
```

### Database Management

```bash
make -f make/ops/mongodb.mk mongo-list-dbs
make -f make/ops/mongodb.mk mongo-list-collections DB=mydb
make -f make/ops/mongodb.mk mongo-db-stats DB=mydb
```

### Replica Set Operations

```bash
make -f make/ops/mongodb.mk mongo-rs-status
make -f make/ops/mongodb.mk mongo-rs-config
make -f make/ops/mongodb.mk mongo-rs-stepdown
```

### User Management

```bash
make -f make/ops/mongodb.mk mongo-create-user DB=mydb USER=myuser PASSWORD=mypass ROLE=readWrite
make -f make/ops/mongodb.mk mongo-list-users DB=mydb
```

### Performance Monitoring

```bash
make -f make/ops/mongodb.mk mongo-server-status
make -f make/ops/mongodb.mk mongo-current-ops
make -f make/ops/mongodb.mk mongo-top
```

For complete list:

```bash
make -f make/ops/mongodb.mk help
```

## Troubleshooting

### Replica Set Not Initializing

Check pod logs:

```bash
kubectl logs mongodb-0 -c setup-replica-set
```

Manually initialize:

```bash
make -f make/ops/mongodb.mk mongo-rs-initiate POD=mongodb-0
```

### Connection Issues

1. Verify service:
```bash
kubectl get svc my-mongodb
```

2. Test connection:
```bash
make -f make/ops/mongodb.mk mongo-ping
```

### Performance Issues

1. Check resource usage:
```bash
kubectl top pod mongodb-0
```

2. Increase WiredTiger cache:
```yaml
mongodb:
  wiredTiger:
    cacheSizeGB: 2.0  # 50-80% of available memory
```

## Backup & Recovery

### Backup Strategy

MongoDB backups consist of 4 primary components:

| Component | Priority | Method | RTO | RPO |
|-----------|----------|--------|-----|-----|
| **Database Data** | Critical | mongodump, snapshots | < 1 hour | 24 hours |
| **Oplog** | Critical | mongodump --oplog | < 30 min | 15 minutes |
| **Configuration** | Important | ConfigMap/Secret export | < 15 min | 24 hours |
| **Users & Roles** | Important | mongodump --authenticationDatabase | < 15 min | 24 hours |

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/mongodb.mk mongo-full-backup

# Database backup
make -f make/ops/mongodb.mk mongo-backup-database

# Oplog backup (replica sets)
make -f make/ops/mongodb.mk mongo-backup-oplog

# Configuration backup
make -f make/ops/mongodb.mk mongo-backup-config

# Users & roles backup
make -f make/ops/mongodb.mk mongo-backup-users

# List available backups
make -f make/ops/mongodb.mk mongo-backup-status
```

### Backup Methods

**1. mongodump (Recommended)**
- Regular backups with selective database support
- Oplog support for point-in-time recovery (PITR)
- Works with any MongoDB version
- Human-readable BSON/JSON format

```bash
# Full backup with oplog (replica sets)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --oplog \
  --gzip \
  --out=/tmp/backup
```

**2. PVC Snapshots (VolumeSnapshot)**
- Fast storage-level snapshots
- Requires CSI driver support
- Instant snapshot creation

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mongodb-snapshot-20250109
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: data-mongodb-0
```

**3. Filesystem Copy**
- Simple and fast for small databases
- Requires database lock for consistency

```bash
# Lock database, copy, unlock
kubectl exec -n default $POD -- mongo admin --eval "db.fsyncLock()"
kubectl exec -n default $POD -- tar czf /tmp/data-backup.tar.gz /data/db
kubectl exec -n default $POD -- mongo admin --eval "db.fsyncUnlock()"
```

**4. Replica Set Delayed Secondary**
- Continuous replication with time delay
- Protection against logical errors
- Requires replica set configuration

**5. MongoDB Cloud Manager / Ops Manager**
- Enterprise automated backups
- Point-in-time recovery
- Centralized management

### Recovery Procedures

**Full Database Restore:**
```bash
# Restore from mongodump backup
make -f make/ops/mongodb.mk mongo-restore-database FILE=/backups/mongodb/20250109/

# Manual restore
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl cp /backups/mongodb/20250109/ $POD:/tmp/restore/
kubectl exec -n default $POD -- mongorestore --drop /tmp/restore/
```

**Point-in-Time Recovery (PITR):**
```bash
# Restore base backup + apply oplog to specific timestamp
kubectl exec -n default $POD -- mongorestore --drop /tmp/restore/base-backup/
kubectl exec -n default $POD -- mongorestore \
  --oplogReplay \
  --oplogLimit="1641024000:1" \
  /tmp/restore/oplog/
```

**Selective Database/Collection Restore:**
```bash
# Restore specific database
kubectl exec -n default $POD -- mongorestore \
  --db=myapp \
  --drop \
  /tmp/restore/myapp/

# Restore specific collection
kubectl exec -n default $POD -- mongorestore \
  --db=myapp \
  --collection=users \
  /tmp/restore/myapp/users.bson
```

### RTO/RPO Targets

| Recovery Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|-------------------|---------------------|----------------------|
| Full Database | < 1 hour | 24 hours |
| Point-in-Time (PITR) | < 1 hour | 15 minutes |
| Selective Database | < 30 minutes | 24 hours |
| Configuration | < 15 minutes | 24 hours |
| Users & Roles | < 15 minutes | 24 hours |
| Disaster Recovery | < 2 hours | 24 hours |

**For comprehensive backup/recovery procedures, see:** [MongoDB Backup Guide](../../docs/mongodb-backup-guide.md)

---

## Security & RBAC

### RBAC Resources

This chart includes namespace-scoped RBAC resources:

**Role:** Grants read-only access to:
- ConfigMaps (configuration management)
- Secrets (credential access)
- Pods (health checks and operations)
- Services (service discovery)
- Endpoints (service discovery)
- PersistentVolumeClaims (storage operations)

**RoleBinding:** Binds the Role to the ServiceAccount

**ServiceAccount:** Pod identity for MongoDB operations

### RBAC Configuration

```yaml
rbac:
  # Enable/disable RBAC resource creation
  create: true
  # Custom annotations for Role and RoleBinding
  annotations:
    description: "MongoDB operational permissions"
```

### Security Best Practices

**DO:**
- ✅ Enable authentication (`mongodb.auth.enabled: true`)
- ✅ Use strong passwords (16+ characters, random)
- ✅ Store credentials in Kubernetes Secrets
- ✅ Enable TLS/SSL for production
- ✅ Use RBAC to restrict access
- ✅ Run as non-root user (UID 999)
- ✅ Enable network policies
- ✅ Rotate credentials regularly
- ✅ Enable audit logging
- ✅ Use replica sets for HA

**DON'T:**
- ❌ Use default passwords
- ❌ Disable authentication
- ❌ Run as root user
- ❌ Expose MongoDB directly to internet
- ❌ Store passwords in values.yaml
- ❌ Skip TLS in production
- ❌ Use overly permissive RBAC roles

### Pod Security Context

```yaml
podSecurityContext:
  fsGroup: 999              # MongoDB group
  runAsUser: 999            # MongoDB user
  runAsNonRoot: true        # Enforce non-root

securityContext:
  capabilities:
    drop:
      - ALL                 # Drop all capabilities
  readOnlyRootFilesystem: false  # MongoDB needs writable /tmp
  allowPrivilegeEscalation: false
```

### NetworkPolicy Example

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mongodb-network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: mongodb
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from application pods
  - from:
    - podSelector:
        matchLabels:
          app: myapp
    ports:
    - protocol: TCP
      port: 27017
  # Allow from same namespace (replica set)
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: mongodb
    ports:
    - protocol: TCP
      port: 27017
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow replica set communication
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: mongodb
    ports:
    - protocol: TCP
      port: 27017
```

### TLS/SSL Configuration

```yaml
mongodb:
  config:
    net:
      tls:
        mode: requireTLS
        certificateKeyFile: /etc/mongodb/certs/mongodb.pem
        CAFile: /etc/mongodb/certs/ca.pem

extraVolumes:
  - name: mongodb-certs
    secret:
      secretName: mongodb-tls
      defaultMode: 0400

extraVolumeMounts:
  - name: mongodb-certs
    mountPath: /etc/mongodb/certs
    readOnly: true
```

### Verify RBAC

```bash
# Check Role
kubectl get role mongodb-role -n default -o yaml

# Check RoleBinding
kubectl get rolebinding mongodb-rolebinding -n default -o yaml

# Check ServiceAccount
kubectl get serviceaccount mongodb -n default -o yaml

# Test permissions
kubectl auth can-i get pods --as=system:serviceaccount:default:mongodb -n default
```

---

## Operations

### Daily Operations

**Access MongoDB:**
```bash
# Port forward to localhost
make -f make/ops/mongodb.mk mongo-port-forward
# Access at: mongodb://localhost:27017

# Get connection string
make -f make/ops/mongodb.mk mongo-get-connection-string

# Shell access
make -f make/ops/mongodb.mk mongo-shell
```

**View Logs:**
```bash
# View MongoDB logs
make -f make/ops/mongodb.mk mongo-logs

# View logs from all replicas
make -f make/ops/mongodb.mk mongo-logs-all
```

### Monitoring & Health Checks

**Cluster Health:**
```bash
# Check server status
make -f make/ops/mongodb.mk mongo-server-status

# Check replica set status
make -f make/ops/mongodb.mk mongo-replica-status

# Check disk usage
make -f make/ops/mongodb.mk mongo-disk-usage

# Resource usage
make -f make/ops/mongodb.mk mongo-stats
```

**Performance Monitoring:**
```bash
# Current operations
make -f make/ops/mongodb.mk mongo-current-ops

# Slow queries
make -f make/ops/mongodb.mk mongo-slow-queries

# Database statistics
make -f make/ops/mongodb.mk mongo-db-stats

# Collection statistics
make -f make/ops/mongodb.mk mongo-collection-stats
```

### Database Operations

**Database Management:**
```bash
# List databases
make -f make/ops/mongodb.mk mongo-list-databases

# List collections
make -f make/ops/mongodb.mk mongo-list-collections DB=myapp

# Database size
make -f make/ops/mongodb.mk mongo-db-size DB=myapp

# Drop database (careful!)
make -f make/ops/mongodb.mk mongo-drop-database DB=testdb
```

**Index Management:**
```bash
# List indexes
make -f make/ops/mongodb.mk mongo-list-indexes DB=myapp COLLECTION=users

# Create index
make -f make/ops/mongodb.mk mongo-create-index DB=myapp COLLECTION=users FIELD=email

# Rebuild indexes
make -f make/ops/mongodb.mk mongo-rebuild-indexes DB=myapp
```

### User Management

**User Operations:**
```bash
# List users
make -f make/ops/mongodb.mk mongo-list-users

# Create user
make -f make/ops/mongodb.mk mongo-create-user USER=myuser PASSWORD=mypass DB=myapp ROLE=readWrite

# Delete user
make -f make/ops/mongodb.mk mongo-delete-user USER=myuser

# Change password
make -f make/ops/mongodb.mk mongo-change-password USER=myuser PASSWORD=newpass
```

### Replica Set Operations

**Replica Set Management:**
```bash
# Replica set status
make -f make/ops/mongodb.mk mongo-replica-status

# Step down primary
make -f make/ops/mongodb.mk mongo-stepdown

# Reconfigure replica set
make -f make/ops/mongodb.mk mongo-replica-reconfig

# Check replication lag
make -f make/ops/mongodb.mk mongo-replication-lag
```

### Maintenance Operations

**Restart:**
```bash
# Restart MongoDB StatefulSet
make -f make/ops/mongodb.mk mongo-restart

# Rolling restart (zero downtime for replica sets)
kubectl rollout restart statefulset mongodb -n default
```

**Compact Database:**
```bash
# Compact to reclaim space
make -f make/ops/mongodb.mk mongo-compact DB=myapp
```

**Repair Database:**
```bash
# Repair database (use with caution)
make -f make/ops/mongodb.mk mongo-repair DB=myapp
```

### Troubleshooting

| Issue | Command | Solution |
|-------|---------|----------|
| Connection refused | `mongo-describe` | Check pod status, service |
| Slow queries | `mongo-slow-queries` | Review indexes, optimize queries |
| High memory | `mongo-stats` | Adjust WiredTiger cache size |
| Replica not syncing | `mongo-replica-status` | Check network, oplog size |
| Disk full | `mongo-disk-usage` | Compact, expand PVC |

**Debug Commands:**
```bash
# Describe pod
make -f make/ops/mongodb.mk mongo-describe

# View events
make -f make/ops/mongodb.mk mongo-events

# Check configuration
make -f make/ops/mongodb.mk mongo-check-config

# Validate setup
make -f make/ops/mongodb.mk mongo-validate
```

---

## Upgrading

### Upgrade Strategy

Choose upgrade strategy based on deployment mode:

| Strategy | Downtime | Best For | Complexity |
|----------|----------|----------|------------|
| **Rolling Upgrade** | None | Replica sets (3+ nodes) | Medium |
| **In-Place Upgrade** | 5-15 min | Standalone deployments | Low |
| **Blue-Green** | <1 min | Critical production | High |
| **Dump & Restore** | 1-4 hours | Major version jumps | Medium |

### Pre-Upgrade Checklist

**Before upgrading:**

1. **Backup Everything:**
   ```bash
   make -f make/ops/mongodb.mk mongo-full-backup
   ```

2. **Check Current State:**
   ```bash
   make -f make/ops/mongodb.mk mongo-pre-upgrade-check
   ```

3. **Review Release Notes:**
   - MongoDB: https://docs.mongodb.com/manual/release-notes/
   - Chart: CHANGELOG.md

4. **Verify Compatibility:**
   - Application driver versions
   - MongoDB version compatibility
   - Feature Compatibility Version (FCV)

### Upgrade Procedures

**Rolling Upgrade (Replica Sets - Zero Downtime):**

```bash
# 1. Verify replica set health
kubectl exec -n default mongodb-0 -- mongo --eval "rs.status()"

# 2. Upgrade secondaries first (partition strategy)
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set updateStrategy.type=RollingUpdate \
  --set updateStrategy.rollingUpdate.partition=2

# 3. Wait and verify
kubectl rollout status statefulset mongodb -n default

# 4. Continue with remaining replicas (decrease partition)
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set updateStrategy.rollingUpdate.partition=0

# 5. Upgrade Feature Compatibility Version
kubectl exec -n default mongodb-0 -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"
```

**In-Place Upgrade (Standalone):**

```bash
# 1. Stop applications (optional but recommended)
kubectl scale deployment myapp --replicas=0

# 2. Backup
make -f make/ops/mongodb.mk mongo-full-backup

# 3. Upgrade chart
helm upgrade mongodb sb-charts/mongodb --set image.tag=7.0.5

# 4. Wait for pod restart
kubectl rollout status statefulset mongodb -n default

# 5. Upgrade FCV
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"

# 6. Restart applications
kubectl scale deployment myapp --replicas=3
```

**Blue-Green Deployment:**

```bash
# 1. Deploy new "green" cluster
helm install mongodb-green sb-charts/mongodb \
  --set image.tag=7.0.5 \
  -n mongodb-green

# 2. Restore data to green cluster
make -f make/ops/mongodb.mk mongo-restore-database \
  NAMESPACE=mongodb-green \
  FILE=/backups/mongodb/latest/

# 3. Test green cluster
# Run application tests against green cluster

# 4. Switch traffic
kubectl patch svc mongodb -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"mongodb-green"}}}'

# 5. Decommission blue cluster after validation
helm uninstall mongodb -n default
```

### Post-Upgrade Validation

**Automated checks:**
```bash
make -f make/ops/mongodb.mk mongo-post-upgrade-check
```

**Manual verification:**
- [ ] MongoDB version correct
- [ ] Feature Compatibility Version upgraded
- [ ] All pods running
- [ ] Replica set healthy (if applicable)
- [ ] No errors in logs
- [ ] Database connectivity working
- [ ] Application functionality verified
- [ ] Performance metrics normal

### Rollback Procedures

**Helm Rollback (before FCV upgrade):**
```bash
# Check history
helm history mongodb -n default

# Rollback
make -f make/ops/mongodb.mk mongo-upgrade-rollback

# Or manually
helm rollback mongodb -n default
```

**Restore from Backup (after FCV upgrade):**
```bash
# Downgrade chart
helm rollback mongodb -n default

# Restore database
make -f make/ops/mongodb.mk mongo-restore-database \
  FILE=/backups/mongodb/pre-upgrade/
```

### Version-Specific Notes

**MongoDB 6.0 → 7.0:**
- Improved Time Series collections
- New aggregation operators
- Enhanced change streams
- Requires driver updates (Java 4.11+, PyMongo 4.5+, Node.js 6.0+)

**MongoDB 5.0 → 6.0:**
- Time Series collections GA
- Native array filters
- Improved sharding

**MongoDB 4.4 → 5.0:**
- Native time series collections
- Versioned API
- Removed `geoNear`, `mapReduce` commands

**For comprehensive upgrade procedures, see:** [MongoDB Upgrade Guide](../../docs/mongodb-upgrade-guide.md)

---

## Production Considerations

### For Simple Production

This chart is suitable for:
- Small to medium workloads (< 1TB data)
- Development/testing environments
- Non-critical applications
- Single-region deployments

### For Enterprise Production

Consider MongoDB Operators:

- **[MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator)**: Official operator
- **[MongoDB Enterprise Operator](https://www.mongodb.com/docs/kubernetes-operator/)**: Advanced features, Ops Manager integration
- **[Percona Operator for MongoDB](https://github.com/percona/percona-server-mongodb-operator)**: Open source, automated backups

**Operator benefits:**
- Automated failover and recovery
- Multi-region replication
- Automated backups to cloud storage
- Sharding support
- Point-in-time recovery
- Advanced monitoring

## Security

### Password Management

Use Kubernetes secrets:

```bash
kubectl create secret generic mongodb-passwords \
  --from-literal=mongodb-root-password=myRootPass \
  --from-literal=mongodb-replica-set-key=$(openssl rand -base64 24)

helm install my-mongodb scripton-charts/mongodb \
  --set mongodb.existingSecret=mongodb-passwords
```

### TLS/SSL

Enable TLS in production:

```yaml
mongodb:
  config:
    net:
      tls:
        mode: requireTLS
        certificateKeyFile: /etc/mongodb/certs/mongodb.pem
        CAFile: /etc/mongodb/certs/ca.pem
```

## License

- Chart: BSD 3-Clause License
- MongoDB: Server Side Public License (SSPL)

## Additional Resources

- [MongoDB Documentation](https://docs.mongodb.com/)
- [Replica Sets](https://docs.mongodb.com/manual/replication/)
- [Production Notes](https://docs.mongodb.com/manual/administration/production-notes/)
- [Security Checklist](https://docs.mongodb.com/manual/administration/security-checklist/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**MongoDB Version**: 7.0.14
