# MinIO

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/minio)
[![Chart Version](https://img.shields.io/badge/chart-0.3.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-RELEASE.2024--10--02-green.svg)](https://min.io/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

High-performance S3-compatible object storage with distributed architecture and erasure coding support.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install chart with default values (standalone mode)
helm install minio sb-charts/minio --set minio.rootPassword=your-secure-password

# Install with distributed mode (production)
helm install minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-prod-distributed.yaml \
  --set minio.rootPassword=your-secure-password
```

## Introduction

This chart bootstraps a MinIO deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ S3-compatible object storage API
- ✅ Distributed mode with erasure coding for data protection
- ✅ Multi-drive support per node (up to 4 drives recommended)
- ✅ Web-based management console
- ✅ Prometheus metrics integration
- ✅ No external database required
- ✅ Production-ready with HA support

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- PersistentVolume provisioner support in the underlying infrastructure

### External Dependencies

**None required!** MinIO is self-contained and does not require external databases.

## Installing the Chart

### Quick Start

```bash
# Install with default values (standalone mode, not recommended for production)
helm install my-minio sb-charts/minio --set minio.rootPassword=your-secure-password
```

### Deployment Scenarios

This chart includes pre-configured values for three deployment scenarios:

#### Home Server / Personal Use

```bash
helm install my-minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-home-single.yaml \
  --set minio.rootPassword=your-secure-password
```

**Resources**: 250m-1000m CPU, 512Mi-1Gi RAM, 2 drives, 50Gi per drive

#### Startup / Cost-Optimized

```bash
helm install my-minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-startup-single.yaml \
  --set minio.rootPassword=your-secure-password
```

**Resources**: 100m-500m CPU, 256Mi-1Gi RAM, 1 drive, 50Gi

#### Production / Distributed HA

```bash
helm install my-minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-prod-distributed.yaml \
  --set minio.rootPassword=your-secure-password
```

**Resources**: 2000m-4000m CPU, 4Gi-8Gi RAM, 4 nodes × 4 drives, 500Gi per drive, HA with erasure coding

See [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md) for detailed specifications.

## Configuration

### Deployment Modes

MinIO supports two deployment modes:

**Standalone Mode:**
- Single server deployment
- 1 or more drives
- Suitable for development/testing
- Lower resource requirements

**Distributed Mode:**
- 4+ servers (must be even number)
- 4+ drives per server recommended
- Erasure coding for data protection
- Production HA deployment
- Automatic self-healing

```yaml
minio:
  mode: distributed  # or standalone
replicaCount: 4  # Minimum 4 for distributed mode
minio:
  drivesPerNode: 4  # 4 drives per node
```

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `minio.mode` | Deployment mode (standalone/distributed) | `standalone` |
| `replicaCount` | Number of MinIO servers | `1` |
| `minio.drivesPerNode` | Number of drives per server | `1` |
| `minio.rootUser` | Root user name | `admin` |
| `minio.rootPassword` | Root password | `""` (required) |
| `minio.region` | MinIO region | `us-east-1` |
| `image.repository` | Image repository | `minio/minio` |
| `image.tag` | Image tag (overrides appVersion) | `""` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | Storage size per drive | `100Gi` |
| `persistence.storageClass` | Storage class name | `""` |
| `service.api.port` | S3 API port | `9000` |
| `service.console.port` | Web console port | `9001` |
| `ingress.api.enabled` | Enable API ingress | `false` |
| `ingress.console.enabled` | Enable console ingress | `false` |
| `monitoring.enabled` | Enable Prometheus metrics | `false` |

See [values.yaml](values.yaml) for all available options.

### Using Existing Secrets

```yaml
minio:
  existingSecret: "my-minio-secret"
  rootUserKey: "root-user"
  rootPasswordKey: "root-password"
```

## Persistence

The chart creates multiple Persistent Volumes (one per drive per pod). Volumes are created using dynamic volume provisioning.

**PVC Configuration:**

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # Use SSD for better performance
  accessMode: ReadWriteOnce
  size: 500Gi  # Size per drive
  annotations: {}
```

**Total Storage Calculation:**
```
Total = replicaCount × drivesPerNode × size
Example: 4 nodes × 4 drives × 500Gi = 8TB raw (4TB usable with EC:4)
```

## Networking

### Service Configuration

MinIO exposes two services:
- **API Service** (port 9000): S3-compatible API
- **Console Service** (port 9001): Web management UI

```yaml
service:
  type: ClusterIP  # or LoadBalancer/NodePort
  api:
    port: 9000
    nodePort: 30900  # If using NodePort
  console:
    port: 9001
    nodePort: 30901
```

### Ingress Configuration

Separate ingress for API and Console:

```yaml
ingress:
  api:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - host: s3.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: minio-api-tls
        hosts:
          - s3.example.com

  console:
    enabled: true
    className: nginx
    hosts:
      - host: minio-console.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: minio-console-tls
        hosts:
          - minio-console.example.com
```

### Browser Redirect URL

When using ingress for console:

```yaml
minio:
  browserRedirectURL: "https://minio-console.example.com"
```

## Security

### Network Policies

Enable network policies to restrict traffic:

```yaml
networkPolicy:
  enabled: true
  ingress:
    api:
      from:
        - namespaceSelector:
            matchLabels:
              name: applications
    console:
      from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
```

### Pod Security Context

```yaml
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000

securityContext:
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
```

## High Availability

### Pod Disruption Budget

Maintain quorum during maintenance:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 3  # For 4-node distributed deployment
```

### Pod Anti-Affinity

Distribute pods across nodes/zones:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - minio
        topologyKey: kubernetes.io/hostname
```

## Monitoring

### Prometheus Integration

Enable Prometheus metrics:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
```

Metrics endpoint: `http://minio:9000/minio/v2/metrics/cluster`

### Public Metrics Access

```yaml
minio:
  prometheusAuthType: "public"  # Allow unauthenticated metrics access
```

## MinIO Client (mc) Setup

```bash
# Install mc client
brew install minio/stable/mc  # macOS
# or download from https://min.io/docs/minio/linux/reference/minio-mc.html

# Get credentials
export MINIO_ROOT_USER=$(kubectl get secret minio-secret -o jsonpath='{.data.root-user}' | base64 -d)
export MINIO_ROOT_PASSWORD=$(kubectl get secret minio-secret -o jsonpath='{.data.root-password}' | base64 -d)

# Set up alias (port-forward method)
kubectl port-forward svc/minio 9000:9000 &
mc alias set myminio http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# Or use ingress URL
mc alias set myminio https://s3.example.com $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# Create bucket
mc mb myminio/mybucket

# Upload file
mc cp myfile.txt myminio/mybucket/

# List buckets
mc ls myminio
```

## S3 Integration

### Application S3 Configuration

```python
# Python example with boto3
import boto3

s3_client = boto3.client(
    's3',
    endpoint_url='http://minio:9000',  # or https://s3.example.com
    aws_access_key_id='admin',
    aws_secret_access_key='your-password',
    region_name='us-east-1'
)
```

```javascript
// Node.js example with aws-sdk
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
  endpoint: 'http://minio:9000',
  accessKeyId: 'admin',
  secretAccessKey: 'your-password',
  s3ForcePathStyle: true,
  signatureVersion: 'v4'
});
```

See [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md) for integrating with:
- Immich (photo/video management)
- Paperless-ngx (document storage)
- Nextcloud (primary storage)

## Operational Commands

Using Makefile:

```bash
# Get credentials
make -f make/ops/minio.mk minio-get-credentials

# Port forward services
make -f make/ops/minio.mk minio-port-forward-api
make -f make/ops/minio.mk minio-port-forward-console

# Setup mc alias
make -f make/ops/minio.mk minio-mc-alias

# Health check
make -f make/ops/minio.mk minio-health

# View logs
make -f make/ops/minio.mk minio-logs

# Access shell
make -f make/ops/minio.mk minio-shell
```

## Upgrading

```bash
# Update repository
helm repo update

# Upgrade release
helm upgrade my-minio sb-charts/minio

# Upgrade with new values
helm upgrade my-minio sb-charts/minio -f my-values.yaml
```

## Uninstalling

```bash
# Uninstall release
helm uninstall my-minio

# Optionally delete PVCs (WARNING: This deletes all data!)
kubectl delete pvc -l app.kubernetes.io/instance=my-minio
```

## Troubleshooting

### Pod not starting

Check logs:
```bash
kubectl logs -l app.kubernetes.io/name=minio
```

Common issues:
- **Permission denied**: Check `podSecurityContext.fsGroup` matches volume permissions
- **Distributed mode failure**: Ensure exactly 4+ pods and even number of replicas
- **PVC not bound**: Check StorageClass and PV provisioner

### Distributed Mode Not Working

Verify headless service:
```bash
kubectl get svc minio-headless
nslookup minio-0.minio-headless.default.svc.cluster.local
```

### Performance Issues

- Use SSD storage class for better I/O
- Increase resources (CPU/memory)
- Use multiple drives per node
- Enable prometheus metrics to identify bottlenecks

## Additional Resources

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [MinIO Console Guide](https://min.io/docs/minio/linux/administration/minio-console.html)
- [Erasure Coding Calculator](https://min.io/product/erasure-code-calculator)
- [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md)
- [Chart Development Guide](../../docs/CHART_DEVELOPMENT_GUIDE.md)

## License

This Helm chart is licensed under the BSD-3-Clause License.
MinIO itself is licensed under the GNU AGPLv3 License.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.
