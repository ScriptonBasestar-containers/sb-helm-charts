# Harbor

<!-- Badges -->
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/harbor)
[![Chart Version](https://img.shields.io/badge/chart-0.3.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-2.13.3-green.svg)](https://goharbor.io/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

Private container registry with vulnerability scanning and image signing capabilities.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# Install chart with custom values
helm install harbor sb-charts/harbor \
  --set harbor.adminPassword=YourSecurePassword \
  --set postgresql.external.password=YourDBPassword
```

## Introduction

This chart bootstraps a Harbor container registry deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ Private Docker registry with web UI
- ✅ User authentication and RBAC
- ✅ Project-based repository management
- ✅ External PostgreSQL and Redis support
- ✅ Horizontal Pod Autoscaling
- ✅ Pod Disruption Budget for HA
- ✅ Network Policy for security
- ✅ Prometheus metrics support
- ✅ S3/MinIO storage backend support

## Important Notice

**This is a simplified Harbor chart** focusing on core registry functionality (push/pull images, web UI, user management).

For **production deployments** requiring advanced features like:
- Trivy vulnerability scanning
- Notary image signing
- Replication between registries
- Webhook notifications
- Robot accounts

Consider using the [official Harbor Helm chart](https://github.com/goharbor/harbor-helm) which provides the complete Harbor feature set.

**This chart is suitable for:**
- Development and testing environments
- Small teams needing basic registry functionality
- Home labs and personal projects
- Learning Harbor basics

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- **External PostgreSQL database** (required)
- **External Redis** (required)
- PersistentVolume provisioner support

### External Dependencies

This chart requires external services:

- **Database**: PostgreSQL 12+ (required)
- **Cache**: Redis 6+ (required)

See the [Database Strategy](#database-strategy) section for setup instructions.

## Installing the Chart

### Quick Start

⚠️ **Not recommended for production** - requires external services configuration

```bash
# Prerequisites: PostgreSQL and Redis must be running
helm install my-harbor sb-charts/harbor \
  --set harbor.adminPassword=HarborAdmin123 \
  --set harbor.externalURL=https://harbor.example.com \
  --set postgresql.external.host=postgresql.default.svc.cluster.local \
  --set postgresql.external.password=DBPassword123 \
  --set redis.external.host=redis.default.svc.cluster.local
```

### Production Deployment

**Step 1: Prepare External Services**

```bash
# Install PostgreSQL
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set auth.database=harbor \
  --set auth.username=harbor \
  --set auth.password=SecureDBPassword \
  --set primary.persistence.size=20Gi

# Install Redis
helm install redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set auth.password=SecureRedisPassword \
  --set master.persistence.size=8Gi
```

**Step 2: Create values file**

Create `harbor-values.yaml`:

```yaml
harbor:
  adminPassword: "YourSecureAdminPassword"
  externalURL: "https://harbor.example.com"

core:
  replicaCount: 2
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi

registry:
  replicaCount: 2
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi

postgresql:
  enabled: false
  external:
    enabled: true
    host: "postgres-postgresql.default.svc.cluster.local"
    port: 5432
    database: "harbor"
    username: "harbor"
    password: "SecureDBPassword"

redis:
  enabled: false
  external:
    enabled: true
    host: "redis-master.default.svc.cluster.local"
    port: 6379
    password: "SecureRedisPassword"

persistence:
  enabled: true
  size: 50Gi
  storageClass: ""  # Use default storage class

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - harbor.example.com
  tls:
    - secretName: harbor-tls
      hosts:
        - harbor.example.com

# Production features
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 75

podDisruptionBudget:
  enabled: true
  minAvailable: 1

serviceMonitor:
  enabled: true
  interval: 30s

networkPolicy:
  enabled: true
```

**Step 3: Install Harbor**

```bash
helm install harbor sb-charts/harbor -f harbor-values.yaml
```

## Configuration

### Database Strategy

This chart follows an **external database** pattern - databases are NOT included as subcharts.

#### PostgreSQL Database Requirements

Harbor requires the following database setup:

```sql
CREATE DATABASE harbor;
CREATE USER harbor WITH ENCRYPTED PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE harbor TO harbor;
```

Harbor will automatically create required tables on first startup.

#### Redis Cache Requirements

Harbor uses Redis for:
- Session storage
- Job queue management
- Cache storage

No special Redis configuration needed - standard Redis installation works.

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Harbor Configuration** | | |
| `harbor.adminPassword` | Admin user password | `Harbor12345` |
| `harbor.externalURL` | Public Harbor URL | Auto-generated |
| `harbor.secretKey` | Encryption secret key | Auto-generated |
| **Core Component** | | |
| `core.replicaCount` | Number of core replicas | `1` |
| `core.image.tag` | Harbor core image tag | `v2.13.3` |
| `core.resources.requests.cpu` | Core CPU request | `100m` |
| `core.resources.requests.memory` | Core memory request | `256Mi` |
| **Registry Component** | | |
| `registry.replicaCount` | Number of registry replicas | `1` |
| `registry.image.tag` | Registry image tag | `v2.13.3` |
| `registry.resources.requests.cpu` | Registry CPU request | `100m` |
| `registry.resources.requests.memory` | Registry memory request | `256Mi` |
| **PostgreSQL** | | |
| `postgresql.external.enabled` | Enable external PostgreSQL | `true` |
| `postgresql.external.host` | PostgreSQL host | `postgresql` |
| `postgresql.external.port` | PostgreSQL port | `5432` |
| `postgresql.external.database` | Database name | `harbor` |
| `postgresql.external.username` | Database username | `harbor` |
| `postgresql.external.password` | Database password | `CHANGEME` |
| **Redis** | | |
| `redis.external.enabled` | Enable external Redis | `true` |
| `redis.external.host` | Redis host | `redis` |
| `redis.external.port` | Redis port | `6379` |
| `redis.external.password` | Redis password | `""` |
| **Persistence** | | |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | Storage size | `50Gi` |
| `persistence.storageClass` | Storage class | `""` |
| **Ingress** | | |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class | `""` |
| `ingress.hosts` | Ingress hosts | `[harbor.local]` |

See [values.yaml](values.yaml) for all available options.

See [values-example.yaml](values-example.yaml) for production configuration example.

## Persistence

The chart mounts a Persistent Volume at `/storage`. The volume is created using dynamic volume provisioning.

**PVC Configuration:**

```yaml
persistence:
  enabled: true
  storageClass: ""  # Use cluster default
  accessMode: ReadWriteOnce
  size: 50Gi
  annotations: {}
```

**Storage Requirements:**

- **Minimum**: 20Gi for small deployments
- **Recommended**: 50Gi for typical usage
- **Production**: 100Gi+ depending on image volume

Harbor stores the following in persistent storage:
- Container images (registry data)
- Scan reports and vulnerability data
- Job logs
- Configuration backups

## Networking

### Service Configuration

```yaml
service:
  type: ClusterIP
  port: 80
```

Harbor exposes HTTP on port 80. For HTTPS, configure ingress with TLS.

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"  # Allow large image uploads
  hosts:
    - harbor.example.com
  tls:
    - secretName: harbor-tls
      hosts:
        - harbor.example.com
```

**Important ingress annotations:**
- `nginx.ingress.kubernetes.io/proxy-body-size: "0"` - Required for large image pushes
- `nginx.ingress.kubernetes.io/proxy-buffering: "off"` - Improves upload performance

## Security

### Network Policies

Enable network policies to restrict traffic:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
```

**Default policy allows:**
- Ingress: All namespaces on port 80
- Egress: DNS (53), PostgreSQL (5432), Redis (6379), HTTPS (443)

### Pod Security

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10000
  fsGroup: 10000

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Harbor requires writable filesystem
```

### Credentials Management

Harbor admin password is stored in Kubernetes Secret:

```bash
# Get admin password
kubectl get secret harbor -o jsonpath='{.data.admin-password}' | base64 -d
```

**Security best practices:**
1. Change default admin password immediately after installation
2. Use strong passwords for admin, database, and Redis
3. Enable ingress TLS for HTTPS
4. Enable network policies
5. Regularly update Harbor to latest security patches

## High Availability

### Horizontal Pod Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 75
  targetMemoryUtilizationPercentage: 80
```

HPA automatically scales core and registry components based on CPU/memory usage.

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

PDB ensures at least 1 replica remains available during voluntary disruptions (node maintenance, upgrades).

### High Availability Recommendations

For production HA deployment:

1. **Multiple replicas**: Set `core.replicaCount: 2` and `registry.replicaCount: 2`
2. **Pod anti-affinity**: Spread replicas across nodes
3. **External HA database**: Use PostgreSQL HA solution (Patroni, CloudNativePG)
4. **External HA Redis**: Use Redis Sentinel or Redis Cluster
5. **Shared storage**: Use ReadWriteMany storage for multi-replica registry (NFS, CephFS, EFS)

## Monitoring

### Prometheus Metrics

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  labels:
    prometheus: kube-prometheus
```

**Available metrics:**
- `harbor_project_total` - Total number of projects
- `harbor_repo_total` - Total number of repositories
- `harbor_artifact_total` - Total number of artifacts
- Registry and API performance metrics

## Harbor Usage

### Docker Login

```bash
# Login to Harbor registry
docker login harbor.example.com
Username: admin
Password: <admin-password>

# Tag and push image
docker tag myapp:latest harbor.example.com/library/myapp:latest
docker push harbor.example.com/library/myapp:latest

# Pull image
docker pull harbor.example.com/library/myapp:latest
```

### Creating Projects

Harbor organizes repositories into **projects**:

1. Login to Harbor UI at `https://harbor.example.com`
2. Click **Projects** → **New Project**
3. Configure project:
   - Name: `my-project`
   - Access Level: Public or Private
   - Storage Quota: Optional

Push images to project: `harbor.example.com/my-project/image:tag`

### User Management

**Admin operations:**

```bash
# Get admin password
make -f make/ops/harbor.mk harbor-get-admin-password

# Port forward to UI
make -f make/ops/harbor.mk harbor-port-forward
# Then access: http://localhost:8080
```

Login as admin, then:
1. Go to **Administration** → **Users**
2. Create new user or integrate with LDAP/OIDC

### Operational Commands

This chart includes comprehensive operational commands via Makefile:

```bash
# Access & Credentials
make -f make/ops/harbor.mk harbor-get-admin-password
make -f make/ops/harbor.mk harbor-port-forward

# Health Checks
make -f make/ops/harbor.mk harbor-status
make -f make/ops/harbor.mk harbor-health

# View Logs
make -f make/ops/harbor.mk harbor-core-logs
make -f make/ops/harbor.mk harbor-registry-logs

# Registry Operations
make -f make/ops/harbor.mk harbor-catalog        # List repositories
make -f make/ops/harbor.mk harbor-projects       # List projects
make -f make/ops/harbor.mk harbor-gc             # Garbage collection

# Database Operations
make -f make/ops/harbor.mk harbor-db-test        # Test PostgreSQL connection
make -f make/ops/harbor.mk harbor-redis-test     # Test Redis connection

# Management
make -f make/ops/harbor.mk harbor-restart
make -f make/ops/harbor.mk harbor-scale REPLICAS=3
```

See [make/ops/harbor.mk](../../make/ops/harbor.mk) for all available commands.

## Upgrading

### From 0.2.x to 0.3.0

Version 0.3.0 adds production features (HPA, PDB, ServiceMonitor, NetworkPolicy).

```bash
# Backup database first
kubectl exec -it postgres-postgresql-0 -- pg_dump -U harbor harbor > harbor-backup.sql

# Upgrade chart
helm upgrade my-harbor sb-charts/harbor \
  --reuse-values \
  --set autoscaling.enabled=true \
  --set podDisruptionBudget.enabled=true \
  --set serviceMonitor.enabled=true

# Verify upgrade
kubectl rollout status deployment/harbor-core
kubectl rollout status deployment/harbor-registry
```

See [CHANGELOG.md](../../CHANGELOG.md) for version-specific upgrade notes.

## Uninstalling the Chart

```bash
# Uninstall release
helm uninstall my-harbor

# Delete PVC (optional - data will be lost!)
kubectl delete pvc storage-my-harbor-registry-0

# Clean up external services (if no longer needed)
helm uninstall postgres
helm uninstall redis
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=harbor

# View pod logs
make -f make/ops/harbor.mk harbor-core-logs
make -f make/ops/harbor.mk harbor-registry-logs

# Describe pod for events
kubectl describe pod <harbor-core-pod-name>
```

### Database Connection Issues

```bash
# Test database connectivity
make -f make/ops/harbor.mk harbor-db-test

# Check database secret
kubectl get secret harbor -o yaml

# Verify PostgreSQL is running
kubectl get pods -l app.kubernetes.io/name=postgresql
```

### Redis Connection Issues

```bash
# Test Redis connectivity
make -f make/ops/harbor.mk harbor-redis-test

# Verify Redis is running
kubectl get pods -l app.kubernetes.io/name=redis
```

### Image Push/Pull Failures

```bash
# Check registry logs
make -f make/ops/harbor.mk harbor-registry-logs

# Verify storage
kubectl get pvc -l app.kubernetes.io/name=harbor

# Test registry health
make -f make/ops/harbor.mk harbor-registry-health
```

### Ingress/Access Issues

```bash
# Check ingress configuration
kubectl get ingress harbor -o yaml

# Verify external URL
kubectl get configmap harbor -o yaml | grep externalURL

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://harbor.default.svc.cluster.local
```

### Common Issues

1. **PVC not binding**: Check storage class availability and persistent volume provisioner
2. **Database connection failed**: Verify PostgreSQL credentials and network connectivity
3. **Redis connection failed**: Verify Redis password and service name
4. **Image pull errors**: Check Docker credentials and Harbor project access permissions
5. **Large image upload timeout**: Add `nginx.ingress.kubernetes.io/proxy-body-size: "0"` annotation

For more troubleshooting help, see [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md).

## Development

### Local Testing

```bash
# Render templates locally
helm template my-harbor ./charts/harbor -f values.yaml

# Lint chart
helm lint ./charts/harbor

# Dry-run installation
helm install my-harbor ./charts/harbor --dry-run --debug

# Install in local cluster (kind/minikube)
helm install my-harbor ./charts/harbor \
  --set postgresql.external.host=host.docker.internal \
  --set redis.external.host=host.docker.internal
```

### Testing with Kind

```bash
# Create kind cluster
kind create cluster --name harbor-test

# Install PostgreSQL
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set auth.database=harbor \
  --set auth.username=harbor \
  --set auth.password=TestPassword

# Install Redis
helm install redis oci://registry-1.docker.io/bitnamicharts/redis \
  --set auth.password=TestPassword

# Install Harbor
helm install harbor ./charts/harbor \
  --set harbor.adminPassword=TestAdmin123 \
  --set postgresql.external.password=TestPassword \
  --set redis.external.password=TestPassword

# Test
make -f make/ops/harbor.mk harbor-status
make -f make/ops/harbor.mk harbor-port-forward
```

## Migration to Official Harbor Chart

If you need advanced Harbor features, migrate to the [official Harbor Helm chart](https://github.com/goharbor/harbor-helm):

**Migration steps:**

1. **Backup data**:
   ```bash
   kubectl exec -it postgres-postgresql-0 -- pg_dump -U harbor harbor > harbor-backup.sql
   kubectl cp harbor-registry-0:/storage ./harbor-storage-backup
   ```

2. **Export projects and users** (via Harbor API or UI)

3. **Install official chart**:
   ```bash
   helm repo add harbor https://helm.goharbor.io
   helm install harbor-official harbor/harbor \
     --set externalDatabase.host=postgres-postgresql \
     --set externalDatabase.username=harbor \
     --set externalDatabase.password=SecureDBPassword
   ```

4. **Restore data** if needed

5. **Update DNS/Ingress** to point to new Harbor instance

6. **Uninstall this chart** after validation

## Contributing

Contributions are welcome! Please see our [Contributing Guide](../../.github/CONTRIBUTING.md) for details.

## License

This Helm chart is licensed under the BSD 3-Clause License.

**Note**: Harbor itself is licensed under the Apache License 2.0. See the [Harbor project](https://goharbor.io/) for details.

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Chart Catalog**: [docs/CHARTS.md](../../docs/CHARTS.md) - Browse all available charts
- **Harbor Homepage**: https://goharbor.io/
- **Harbor Documentation**: https://goharbor.io/docs/
- **Harbor GitHub**: https://github.com/goharbor/harbor
- **Official Harbor Helm Chart**: https://github.com/goharbor/harbor-helm
- **Chart Development Guide**: [docs/CHART_DEVELOPMENT_GUIDE.md](../../docs/CHART_DEVELOPMENT_GUIDE.md)
- **Makefile Commands**: [docs/MAKEFILE_COMMANDS.md](../../docs/MAKEFILE_COMMANDS.md)

## Related Charts

Consider these complementary charts from this repository:

- **[postgresql](../postgresql)** - PostgreSQL database for Harbor backend
- **[redis](../redis)** - Redis cache for Harbor sessions
- **[minio](../minio)** - S3-compatible storage for Harbor artifacts
- **[prometheus](../prometheus)** - Monitoring for Harbor metrics
- **[grafana](../grafana)** - Visualization of Harbor metrics

---

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
