# Nextcloud Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/nextcloud)

Production-ready Nextcloud deployment on Kubernetes with external PostgreSQL 16 and Redis 8 support.

## Features

- **Nextcloud Apache Image**: Official Nextcloud with Apache HTTP Server
- **External Database**: PostgreSQL 16 support (no embedded database)
- **External Cache**: Redis 8 for session and memory cache
- **Persistent Storage**: Separate volumes for data, config, and custom apps
- **Security**: Running as non-root user (www-data)
- **High Availability**: Configurable replicas and autoscaling
- **Production Ready**: Resource limits, health checks, and monitoring
- **Background Jobs**: Kubernetes CronJob for Nextcloud background tasks

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install nextcloud-home charts/nextcloud \
  -f charts/nextcloud/values-home-single.yaml \
  --set nextcloud.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 10Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install nextcloud-startup charts/nextcloud \
  -f charts/nextcloud/values-startup-single.yaml \
  --set nextcloud.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 20Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with multiple replicas and monitoring:

```bash
helm install nextcloud-prod charts/nextcloud \
  -f charts/nextcloud/values-prod-master-replica.yaml \
  --set nextcloud.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Features:** 3 replicas, pod anti-affinity, HPA, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 50Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#nextcloud).


- Kubernetes 1.19+
- Helm 3.0+
- External PostgreSQL 16 database
- External Redis 8 server
- PersistentVolume support (for data persistence)
- Ingress controller (for external access)

## Quick Start

### 1. Prepare External Dependencies

Before installing Nextcloud, ensure you have:

**PostgreSQL 16:**
```bash
# Create database and user
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
```

**Redis 8:**
```bash
# Redis should be accessible with host:port
# Optional: Configure password for Redis
```

### 2. Create Values File

Create a `my-values.yaml` file:

```yaml
# Basic Nextcloud configuration
nextcloud:
  adminUser: admin
  adminPassword: "YourSecureAdminPassword"
  trustedDomains:
    - nextcloud.example.com

# External PostgreSQL configuration
postgresql:
  external:
    enabled: true
    host: "postgres-postgresql.default.svc.cluster.local"
    port: 5432
    database: "nextcloud"
    username: "nextcloud"
    password: "your-secure-password"

# External Redis configuration
redis:
  external:
    enabled: true
    host: "redis-master.default.svc.cluster.local"
    port: 6379
    password: "your-redis-password"  # Optional

# Ingress configuration
ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: nextcloud.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: nextcloud-tls
      hosts:
        - nextcloud.example.com

# Storage configuration
persistence:
  data:
    size: 20Gi  # Adjust based on your needs
  config:
    size: 1Gi
  apps:
    size: 2Gi

# Resource limits
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

### 3. Install the Chart

```bash
# Add the repository (if needed)
# helm repo add scripton https://your-helm-repo.example.com
# helm repo update

# Install Nextcloud
helm install nextcloud ./nextcloud -f my-values.yaml

# Or upgrade if already installed
helm upgrade --install nextcloud ./nextcloud -f my-values.yaml
```

### 4. Access Nextcloud

```bash
# Check the deployment status
kubectl get pods -l app.kubernetes.io/name=nextcloud

# Get the Ingress URL
kubectl get ingress -l app.kubernetes.io/name=nextcloud

# Access via browser
https://nextcloud.example.com
```

## Configuration

### Nextcloud Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nextcloud.adminUser` | Admin username | `admin` |
| `nextcloud.adminPassword` | Admin password (required) | `""` |
| `nextcloud.version` | Nextcloud version | `"28.0"` |
| `nextcloud.trustedDomains` | List of trusted domains | `[]` |

### Image Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Nextcloud image repository | `nextcloud` |
| `image.tag` | Image tag | `"28.0-apache"` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### External PostgreSQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.external.enabled` | Enable external PostgreSQL | `true` |
| `postgresql.external.host` | PostgreSQL host | `""` |
| `postgresql.external.port` | PostgreSQL port | `5432` |
| `postgresql.external.database` | Database name | `"nextcloud"` |
| `postgresql.external.username` | Database username | `"nextcloud"` |
| `postgresql.external.password` | Database password | `""` |
| `postgresql.external.existingSecret.enabled` | Use existing secret | `false` |

### External Redis

| Parameter | Description | Default |
|-----------|-------------|---------|
| `redis.external.enabled` | Enable external Redis | `true` |
| `redis.external.host` | Redis host | `""` |
| `redis.external.port` | Redis port | `6379` |
| `redis.external.password` | Redis password (optional) | `""` |
| `redis.external.database` | Redis database number | `0` |
| `redis.external.existingSecret.enabled` | Use existing secret | `false` |

### Persistent Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.data.enabled` | Enable data volume | `true` |
| `persistence.data.size` | Data volume size | `8Gi` |
| `persistence.data.storageClass` | Storage class | `""` (default) |
| `persistence.config.enabled` | Enable config volume | `true` |
| `persistence.config.size` | Config volume size | `1Gi` |
| `persistence.apps.enabled` | Enable custom apps volume | `true` |
| `persistence.apps.size` | Apps volume size | `1Gi` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `"nginx"` |
| `ingress.annotations` | Ingress annotations | See values.yaml |
| `ingress.hosts` | Ingress hosts configuration | `[]` |
| `ingress.tls` | Ingress TLS configuration | `[]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `2000m` |
| `resources.limits.memory` | Memory limit | `2Gi` |
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `512Mi` |

### Cron Job

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cronjob.enabled` | Enable background cron job | `true` |
| `cronjob.schedule` | Cron schedule | `"*/15 * * * *"` |
| `cronjob.resources` | Cron job resources | See values.yaml |

### High Availability & Security

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget | `false` |
| `podDisruptionBudget.minAvailable` | Minimum pods available | `1` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `monitoring.serviceMonitor.enabled` | Enable Prometheus monitoring | `false` |

#### Pod Disruption Budget

Protects Nextcloud during cluster maintenance:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1  # Ensure at least 1 pod is always running
```

**Benefits:**
- Prevents all pods from being drained simultaneously
- Ensures service availability during node maintenance
- Critical for production deployments

#### Network Policy

Restricts network access for security:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      - podSelector:
          matchLabels:
            app: frontend  # Only allow frontend pods
      ports:
        - protocol: TCP
          port: 80
```

**Benefits:**
- Network-level security isolation
- Restricts access to authorized clients only
- Defense-in-depth security posture

#### Prometheus Monitoring

Enable metrics collection (requires Nextcloud serverinfo app):

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    path: /ocs/v2.php/apps/serverinfo/api/v1/info?format=json
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus
```

**Note:** The serverinfo app must be installed in Nextcloud for metrics to work.

## Advanced Configuration

### Using Existing Secrets

Instead of putting passwords in values.yaml, you can use existing Kubernetes secrets:

```yaml
postgresql:
  external:
    existingSecret:
      enabled: true
      secretName: "postgres-credentials"
      usernameKey: "username"
      passwordKey: "password"

redis:
  external:
    existingSecret:
      enabled: true
      secretName: "redis-credentials"
      passwordKey: "password"
```

Create the secrets:

```bash
# PostgreSQL secret
kubectl create secret generic postgres-credentials \
  --from-literal=username=nextcloud \
  --from-literal=password=your-secure-password

# Redis secret
kubectl create secret generic redis-credentials \
  --from-literal=password=your-redis-password
```

### Using Existing PVCs

If you already have PersistentVolumeClaims:

```yaml
persistence:
  data:
    existingClaim: "my-nextcloud-data-pvc"
  config:
    existingClaim: "my-nextcloud-config-pvc"
  apps:
    existingClaim: "my-nextcloud-apps-pvc"
```

### SMTP Configuration

Enable email functionality:

```yaml
nextcloud:
  smtp:
    enabled: true
    host: "smtp.gmail.com"
    port: 587
    secure: "tls"
    authType: "LOGIN"
    from: "nextcloud@example.com"
    username: "your-email@gmail.com"
    password: "your-app-password"
```

### Custom Environment Variables

Add custom environment variables:

```yaml
extraEnv:
  - name: PHP_MEMORY_LIMIT
    value: "1024M"
  - name: PHP_UPLOAD_LIMIT
    value: "20G"
```

## Maintenance

### Backup

Backup your PersistentVolumes regularly:

```bash
# Backup data volume
kubectl exec -it <nextcloud-pod> -- tar czf /backup/nextcloud-data.tar.gz /var/www/html

# Backup database
kubectl exec -it <postgres-pod> -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql
```

### Upgrade Nextcloud

```bash
# Update image tag in values.yaml
image:
  tag: "29.0-apache"

# Upgrade the release
helm upgrade nextcloud ./nextcloud -f my-values.yaml

# Check upgrade status
kubectl logs -f <nextcloud-pod> -c init-nextcloud
```

### Scaling

Adjust replicas for high availability:

```yaml
replicaCount: 3

# Note: Requires ReadWriteMany (RWX) storage class
persistence:
  data:
    accessMode: ReadWriteMany
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=nextcloud
kubectl describe pod <nextcloud-pod>
kubectl logs <nextcloud-pod>
```

### Check Initialization

```bash
# View init container logs
kubectl logs <nextcloud-pod> -c init-nextcloud
```

### Database Connection Issues

```bash
# Test PostgreSQL connection from pod
kubectl exec -it <nextcloud-pod> -- pg_isready -h <postgres-host> -p 5432 -U nextcloud
```

### Redis Connection Issues

```bash
# Test Redis connection from pod
kubectl exec -it <nextcloud-pod> -- redis-cli -h <redis-host> -p 6379 ping
```

### Access Nextcloud OCC Command

```bash
# Run occ commands
kubectl exec -it <nextcloud-pod> -- php /var/www/html/occ status
kubectl exec -it <nextcloud-pod> -- php /var/www/html/occ config:list
```

## Security Considerations

1. **Always use strong passwords** for admin and database users
2. **Enable HTTPS** via Ingress TLS configuration
3. **Use Kubernetes Secrets** for sensitive data
4. **Regularly update** Nextcloud and dependencies
5. **Enable Redis password** for additional security
6. **Configure firewall rules** for database and Redis access
7. **Monitor logs** for suspicious activities

## Performance Tuning

### Recommended Resource Allocation

For production workloads:

```yaml
resources:
  limits:
    cpu: 4000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 1Gi

# Increase PHP limits
extraEnv:
  - name: PHP_MEMORY_LIMIT
    value: "1024M"
  - name: PHP_UPLOAD_LIMIT
    value: "20G"
```

### Storage Performance

Use high-performance storage classes for better performance:

```yaml
persistence:
  data:
    storageClass: "fast-ssd"  # Use SSD-backed storage
```

## Contributing

Contributions are welcome! Please submit issues and pull requests.

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

This Helm chart is provided as-is under the MIT License.

## Support

- Nextcloud Documentation: https://docs.nextcloud.com/
- Nextcloud Forums: https://help.nextcloud.com/
- Issue Tracker: https://github.com/your-repo/issues
