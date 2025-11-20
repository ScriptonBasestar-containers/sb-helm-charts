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
