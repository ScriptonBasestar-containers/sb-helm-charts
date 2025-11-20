# MySQL Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 8.0.35](https://img.shields.io/badge/AppVersion-8.0.35-informational?style=flat-square)

MySQL relational database with replication support for Kubernetes

## Features

- **StatefulSet Deployment**: Stable pod identities and persistent storage for data durability
- **Master-Replica Replication**: Optional MySQL replication for high availability and read scaling
- **Persistent Storage**: PersistentVolumeClaim support with configurable storage class and size
- **Configuration Management**: Complete my.cnf configuration via ConfigMap
- **Security**: Kubernetes secrets for password management, security contexts, and non-root execution
- **Health Probes**: Liveness and readiness probes using `mysqladmin ping`
- **Resource Management**: Configurable CPU and memory limits/requests
- **Flexible Deployment**: Development and production value profiles included
- **Operational Tools**: Comprehensive Makefile commands for database operations

## TL;DR

```bash
# Add the repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration (single node)
helm install my-mysql scripton-charts/mysql

# Install with custom root password
helm install my-mysql scripton-charts/mysql \
  --set mysql.password=mySecurePassword

# Install with replication (2 replicas)
helm install my-mysql scripton-charts/mysql \
  --set replicaCount=2 \
  --set mysql.replication.enabled=true \
  --set mysql.replication.password=replicatorPassword
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure (for persistence)

## Installing the Chart

### Basic Installation

Install the chart with the release name `my-mysql`:

```bash
helm install my-mysql scripton-charts/mysql
```

### Development Installation

Use the development values for local testing:

```bash
helm install my-mysql scripton-charts/mysql \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mysql/values-dev.yaml
```

### Production Installation

Use the production values with replication:

```bash
helm install my-mysql scripton-charts/mysql \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mysql/values-small-prod.yaml \
  --set mysql.password=mySecurePassword \
  --set mysql.replication.password=replicatorPassword
```

## Uninstalling the Chart

To uninstall/delete the `my-mysql` deployment:

```bash
helm uninstall my-mysql
```

This command removes all the Kubernetes components associated with the chart and deletes the release.

**Note**: PersistentVolumeClaims are not automatically deleted. You must delete them manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=my-mysql
```

## Configuration

The following table lists the configurable parameters of the MySQL chart and their default values.

### Global Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of MySQL replicas | `1` |
| `image.repository` | MySQL image repository | `mysql` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.tag` | MySQL image tag (overrides chart appVersion) | `""` |
| `imagePullSecrets` | Docker registry secret names | `[]` |
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full chart name | `""` |

### MySQL Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mysql.database` | Database to create on first startup | `mysql` |
| `mysql.username` | Username to create on first startup | `mysql` |
| `mysql.password` | Password for the user (auto-generated if empty) | `""` |
| `mysql.maxConnections` | Maximum concurrent connections | `100` |
| `mysql.innodbBufferPoolSize` | InnoDB buffer pool size | `128M` |
| `mysql.innodbLogFileSize` | InnoDB log file size | `48M` |
| `mysql.replication.enabled` | Enable MySQL replication | `false` |
| `mysql.replication.user` | Replication user | `replicator` |
| `mysql.replication.password` | Replication user password | `""` |
| `mysql.replication.serverId` | Server ID for replication | `1` |
| `mysql.config` | Additional MySQL configuration | `{}` |
| `mysql.existingConfigMap` | Use existing ConfigMap for configuration | `""` |
| `mysql.existingSecret` | Use existing Secret for passwords | `""` |
| `mysql.extraEnv` | Additional environment variables | `[]` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | MySQL service port | `3306` |
| `service.nodePort` | NodePort (if service type is NodePort) | `""` |
| `service.annotations` | Service annotations | `{}` |

### Persistence Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence using PVC | `true` |
| `persistence.storageClass` | PVC storage class | `""` |
| `persistence.accessMode` | PVC access mode | `ReadWriteOnce` |
| `persistence.size` | PVC storage size | `10Gi` |
| `persistence.annotations` | PVC annotations | `{}` |

### Security Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.annotations` | Service account annotations | `{}` |
| `serviceAccount.name` | Service account name | `""` |
| `podAnnotations` | Pod annotations | `{}` |
| `podSecurityContext.fsGroup` | Pod fsGroup | `999` |
| `podSecurityContext.runAsUser` | Pod runAsUser | `999` |
| `podSecurityContext.runAsNonRoot` | Run as non-root user | `true` |
| `securityContext.capabilities.drop` | Dropped Linux capabilities | `[ALL]` |
| `securityContext.readOnlyRootFilesystem` | Read-only root filesystem | `false` |
| `securityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |

### Resource Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `512Mi` |

### Health Probe Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe.initialDelaySeconds` | Liveness probe initial delay | `30` |
| `livenessProbe.periodSeconds` | Liveness probe period | `10` |
| `livenessProbe.timeoutSeconds` | Liveness probe timeout | `5` |
| `livenessProbe.failureThreshold` | Liveness probe failure threshold | `6` |
| `readinessProbe.initialDelaySeconds` | Readiness probe initial delay | `10` |
| `readinessProbe.periodSeconds` | Readiness probe period | `10` |
| `readinessProbe.timeoutSeconds` | Readiness probe timeout | `5` |
| `readinessProbe.failureThreshold` | Readiness probe failure threshold | `3` |

### Node Selection

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodeSelector` | Node labels for pod assignment | `{}` |
| `tolerations` | Tolerations for pod assignment | `[]` |
| `affinity` | Affinity rules for pod assignment | `{}` |

## Common Configurations

### Single Node Development

```yaml
# values-dev.yaml
replicaCount: 1
mysql:
  database: "testdb"
  username: "testuser"
  password: "testpass"
  maxConnections: 50
  innodbBufferPoolSize: "64M"
persistence:
  size: 5Gi
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 256Mi
```

### Production with Replication

```yaml
# values-prod.yaml
replicaCount: 2
mysql:
  database: "production_db"
  username: "app_user"
  password: ""  # Set via --set or external secret
  maxConnections: 200
  innodbBufferPoolSize: "512M"
  innodbLogFileSize: "128M"
  replication:
    enabled: true
    password: ""  # Set via --set or external secret
persistence:
  storageClass: "fast-ssd"
  size: 50Gi
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - mysql
          topologyKey: kubernetes.io/hostname
```

### Custom Configuration

```yaml
mysql:
  config:
    max_allowed_packet: "64M"
    innodb_flush_log_at_trx_commit: "1"
    innodb_flush_method: "O_DIRECT"
    query_cache_size: "0"
    query_cache_type: "0"
```

## Replication Setup

MySQL replication provides high availability and read scaling. This chart supports master-replica replication.

### Enable Replication

1. Install with at least 2 replicas:

```bash
helm install my-mysql scripton-charts/mysql \
  --set replicaCount=2 \
  --set mysql.replication.enabled=true \
  --set mysql.replication.password=replicatorPassword
```

2. The first pod (`my-mysql-0`) becomes the master
3. Subsequent pods (`my-mysql-1`, `my-mysql-2`, etc.) become replicas

### Check Replication Status

```bash
# Check all pods
make -f make/ops/mysql.mk mysql-replication-info

# Check master status
make -f make/ops/mysql.mk mysql-master-status POD=my-mysql-0

# Check replica status
make -f make/ops/mysql.mk mysql-replica-status POD=my-mysql-1

# Check replication lag
make -f make/ops/mysql.mk mysql-replica-lag
```

### Replication Architecture

```
┌─────────────────────┐
│   my-mysql-0        │
│   (Master)          │
│   Read + Write      │
└──────────┬──────────┘
           │ Binary Log
           ├────────────────┐
           │                │
           ▼                ▼
┌──────────────────┐ ┌──────────────────┐
│  my-mysql-1      │ │  my-mysql-2      │
│  (Replica)       │ │  (Replica)       │
│  Read Only       │ │  Read Only       │
└──────────────────┘ └──────────────────┘
```

## Backup and Restore

### Manual Backup

Backup all databases:

```bash
make -f make/ops/mysql.mk mysql-backup
```

This creates a compressed SQL dump in `tmp/mysql-backups/`.

### Backup Specific Database

```bash
kubectl exec my-mysql-0 -- bash -c \
  "mysqldump -uroot -p\$MYSQL_ROOT_PASSWORD mydb --single-transaction" \
  | gzip > mydb-backup.sql.gz
```

### Restore from Backup

```bash
make -f make/ops/mysql.mk mysql-restore FILE=tmp/mysql-backups/mysql-backup-20240101-120000.sql.gz
```

### Automated Backups

For production, consider using external backup solutions:

- **Velero**: Kubernetes backup and restore
- **mysqldump CronJob**: Scheduled backups to object storage
- **Percona XtraBackup**: Hot backups for large databases

## Operational Commands

This chart includes comprehensive Makefile commands for database operations.

### Basic Operations

```bash
# Open MySQL shell
make -f make/ops/mysql.mk mysql-shell

# View logs
make -f make/ops/mysql.mk mysql-logs

# Port forward to localhost:3306
make -f make/ops/mysql.mk mysql-port-forward
```

### Database Management

```bash
# Create database
make -f make/ops/mysql.mk mysql-create-db DB=mydb

# List all databases
make -f make/ops/mysql.mk mysql-list-dbs

# Show database sizes
make -f make/ops/mysql.mk mysql-db-size

# Optimize database
make -f make/ops/mysql.mk mysql-optimize DB=mydb
```

### User Management

```bash
# Create user
make -f make/ops/mysql.mk mysql-create-user USER=myuser PASSWORD=mypass

# Grant privileges
make -f make/ops/mysql.mk mysql-grant-privileges USER=myuser DB=mydb

# List users
make -f make/ops/mysql.mk mysql-list-users

# Show user grants
make -f make/ops/mysql.mk mysql-show-grants USER=myuser
```

### Performance Monitoring

```bash
# Show server status
make -f make/ops/mysql.mk mysql-status

# Show running processes
make -f make/ops/mysql.mk mysql-processlist

# Show server variables
make -f make/ops/mysql.mk mysql-variables

# Show InnoDB status
make -f make/ops/mysql.mk mysql-innodb-status
```

### Maintenance

```bash
# Check tables
make -f make/ops/mysql.mk mysql-check DB=mydb

# Repair tables
make -f make/ops/mysql.mk mysql-repair DB=mydb

# Analyze tables
make -f make/ops/mysql.mk mysql-analyze DB=mydb
```

### Custom Commands

```bash
# Run MySQL command
make -f make/ops/mysql.mk mysql-cli CMD="SELECT VERSION();"

# Run mysqladmin command
make -f make/ops/mysql.mk mysql-admin CMD=ping

# Check version
make -f make/ops/mysql.mk mysql-version
```

For a complete list of commands:

```bash
make -f make/ops/mysql.mk help
```

## Troubleshooting

### Pod Not Starting

Check pod events and logs:

```bash
kubectl describe pod my-mysql-0
kubectl logs my-mysql-0
```

Common issues:
- **PVC not bound**: Check storage class and PV availability
- **Image pull errors**: Verify image repository and pull secrets
- **Permission denied**: Check security contexts and fsGroup

### Connection Refused

1. Verify service is running:
```bash
kubectl get svc my-mysql
```

2. Check if MySQL is ready:
```bash
kubectl exec my-mysql-0 -- mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD ping
```

3. Port forward and test locally:
```bash
make -f make/ops/mysql.mk mysql-port-forward
mysql -h 127.0.0.1 -uroot -p
```

### Replication Issues

Check replication status:

```bash
# Check master
make -f make/ops/mysql.mk mysql-master-status POD=my-mysql-0

# Check replica
make -f make/ops/mysql.mk mysql-replica-status POD=my-mysql-1
```

Common issues:
- **Replica I/O thread not running**: Network connectivity or authentication issues
- **Replica SQL thread not running**: SQL errors on replica (check error log)
- **High replication lag**: Master write load or network latency

### Performance Issues

1. Check resource usage:
```bash
kubectl top pod my-mysql-0
```

2. Review MySQL status:
```bash
make -f make/ops/mysql.mk mysql-status
make -f make/ops/mysql.mk mysql-processlist
```

3. Tune InnoDB settings:
```yaml
mysql:
  innodbBufferPoolSize: "1G"  # Set to 70-80% of available memory
  innodbLogFileSize: "256M"
```

### Data Recovery

If data is corrupted:

1. Try automatic repair:
```bash
make -f make/ops/mysql.mk mysql-repair DB=mydb
```

2. Restore from backup:
```bash
make -f make/ops/mysql.mk mysql-restore FILE=backup.sql.gz
```

3. For critical issues, consult MySQL documentation on crash recovery.

## Security Considerations

### Password Management

- **Never hardcode passwords** in values.yaml for production
- Use Kubernetes secrets or external secret management:

```bash
# Create secret manually
kubectl create secret generic mysql-passwords \
  --from-literal=mysql-root-password=myRootPassword \
  --from-literal=mysql-replication-password=myReplPassword

# Use existing secret
helm install my-mysql scripton-charts/mysql \
  --set mysql.existingSecret=mysql-passwords
```

### Network Security

- Use NetworkPolicies to restrict access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mysql-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: mysql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: myapp
      ports:
        - protocol: TCP
          port: 3306
```

### TLS Encryption

For production, enable TLS for client connections:

1. Create TLS certificates
2. Mount certificates via ConfigMap/Secret
3. Configure MySQL to use TLS:

```yaml
mysql:
  config:
    require_secure_transport: "ON"
    ssl-ca: "/etc/mysql/certs/ca.pem"
    ssl-cert: "/etc/mysql/certs/server-cert.pem"
    ssl-key: "/etc/mysql/certs/server-key.pem"
```

## Production Considerations

### For Simple Production Use

This chart is suitable for:
- **Small to medium workloads** (< 100 GB data)
- **Development and testing** environments
- **Non-critical applications** with basic HA needs
- **Single-region deployments** with master-replica replication

### For Enterprise Production

Consider using MySQL Operators for advanced features:

- **[Oracle MySQL Operator](https://github.com/mysql/mysql-operator)**: Official MySQL operator with InnoDB Cluster support
- **[Percona Operator for MySQL](https://github.com/percona/percona-server-mysql-operator)**: XtraDB Cluster, automated backups
- **[Vitess](https://vitess.io/)**: Horizontal sharding for massive scale (YouTube, Slack, GitHub use cases)

**Why use an operator?**
- Automated failover and recovery
- Multi-region replication
- Automated backups to object storage
- Database sharding and horizontal scaling
- Advanced monitoring and alerting
- Zero-downtime upgrades

## Migration from Other Charts

### From Bitnami MySQL

1. Export data from Bitnami MySQL:
```bash
kubectl exec bitnami-mysql-0 -- mysqldump -uroot -p$MYSQL_ROOT_PASSWORD --all-databases > backup.sql
```

2. Install this chart:
```bash
helm install my-mysql scripton-charts/mysql
```

3. Restore data:
```bash
make -f make/ops/mysql.mk mysql-restore FILE=backup.sql
```

### From StatefulSet

If you have an existing MySQL StatefulSet:

1. Scale down to 0:
```bash
kubectl scale statefulset mysql --replicas=0
```

2. Install chart using same PVCs:
```bash
helm install my-mysql scripton-charts/mysql \
  --set persistence.existingClaim=mysql-data-mysql-0
```

## License

This Helm chart is licensed under the BSD 3-Clause License.

MySQL is licensed under the GNU General Public License (GPL) version 2.

## Additional Resources

- [MySQL Documentation](https://dev.mysql.com/doc/)
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [MySQL Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [MySQL Security](https://dev.mysql.com/doc/refman/8.0/en/security.html)
- [Kubernetes MySQL Best Practices](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)
- [MySQL High Availability Solutions](https://dev.mysql.com/doc/mysql-ha-scalability/en/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**MySQL Version**: 8.0.35
