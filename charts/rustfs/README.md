# RustFS Helm Chart

High-performance S3-compatible object storage built with Rust. This Helm chart deploys RustFS on Kubernetes with production-ready features including high availability, tiered storage, and comprehensive monitoring.

[![Chart Version](https://img.shields.io/badge/chart-0.1.0-blue)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/rustfs-1.0.0--alpha.66-orange)](https://github.com/rustfs/rustfs)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](https://opensource.org/licenses/BSD-3-Clause)

## Features

- 🚀 **High Performance**: 2.3x faster than MinIO for 4K small files
- 🔄 **S3 Compatible**: Full AWS S3 API compatibility
- 🏗️ **Tiered Storage**: Mix SSD (hot) and HDD (cold) storage tiers
- 📊 **Production Ready**: NetworkPolicy, PodDisruptionBudget, ServiceMonitor
- 🔐 **Secure**: RBAC, secret management, security contexts
- 🎯 **Optimized Configs**: Separate configs for home servers and startups
- 📈 **Scalable**: Horizontal pod autoscaling support
- 🛠️ **Operational**: Comprehensive Makefile for day-2 operations

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- PersistentVolume provisioner (for persistent storage)
- Ingress controller (optional, for HTTP/HTTPS access)
- Prometheus Operator (optional, for monitoring)

## Application License

**Chart License**: BSD-3-Clause (this repository)
**Application License**: Apache-2.0 ([RustFS](https://github.com/rustfs/rustfs))

## Quick Start

### Installation

```bash
# Add the Helm repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install RustFS with default configuration
helm install rustfs scripton-charts/rustfs \
  --namespace rustfs \
  --create-namespace \
  --set rustfs.rootPassword="your-secure-password"

# Or install from source
helm install rustfs ./charts/rustfs \
  --namespace rustfs \
  --create-namespace \
  --set rustfs.rootPassword="your-secure-password"
```

### Access RustFS

```bash
# Port forward to access locally
kubectl port-forward -n rustfs svc/rustfs 9000:9000  # S3 API
kubectl port-forward -n rustfs svc/rustfs 9001:9001  # Web Console

# Get credentials
kubectl get secret rustfs-secret -n rustfs -o jsonpath='{.data.root-user}' | base64 -d
kubectl get secret rustfs-secret -n rustfs -o jsonpath='{.data.root-password}' | base64 -d

# Access Web Console
open http://localhost:9001
```

## Configuration Variants

This chart includes three pre-configured values files for different use cases:

### 1. Default Configuration (`values.yaml`)

General-purpose configuration with balanced settings.

```bash
helm install rustfs ./charts/rustfs --namespace rustfs --create-namespace
```

**Key Settings:**
- Single replica (no HA)
- 100Gi per data directory (4 directories = 400Gi total)
- 2 CPU cores, 4Gi RAM
- ClusterIP service
- No ingress

### 2. Home Server / NAS Configuration (`values-homeserver.yaml`)

Optimized for home servers, Raspberry Pi, Intel NUC, Synology NAS, etc.

```bash
helm install rustfs ./charts/rustfs \
  -f ./charts/rustfs/values-homeserver.yaml \
  --namespace rustfs \
  --create-namespace \
  --set rustfs.rootPassword="your-password"
```

**Key Features:**
- ✅ Reduced resource usage (1 CPU, 2Gi RAM)
- ✅ HDD storage optimization
- ✅ Single replica (no HA overhead)
- ✅ Minimal monitoring
- ✅ Internal network only
- ✅ 2 data directories (200Gi total)
- ✅ Permission fix init container for NAS/NFS

**Best For:**
- Personal NAS storage
- Home lab experiments
- Development environments
- Single-node Kubernetes (k3s, MicroK8s)

### 3. Startup / Production Configuration (`values-startup.yaml`)

Enterprise-grade configuration for 10K+ users.

```bash
helm install rustfs ./charts/rustfs \
  -f ./charts/rustfs/values-startup.yaml \
  --namespace rustfs \
  --create-namespace \
  --set rustfs.rootPassword="your-secure-password" \
  --set ingress.api.hosts[0].host="s3.yourdomain.com" \
  --set ingress.console.hosts[0].host="console.s3.yourdomain.com"
```

**Key Features:**
- ✅ High availability (4 replicas)
- ✅ Tiered storage (SSD hot + HDD cold)
- ✅ Autoscaling (4-10 replicas)
- ✅ PodDisruptionBudget (75% availability)
- ✅ NetworkPolicy (security)
- ✅ ServiceMonitor (Prometheus)
- ✅ LoadBalancer service
- ✅ Ingress with TLS
- ✅ 4 CPU cores, 8Gi RAM per pod
- ✅ Total capacity: ~4.2Ti

**Best For:**
- Production S3 replacement
- Startup/SMB storage infrastructure
- Multi-tenant environments
- High-availability requirements

## Storage Configuration

### Single Storage Class

Use default or specify a single storage class:

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # or "hdd-storage", "" for default
  size: 100Gi
rustfs:
  dataDirs: 4  # Total: 400Gi per replica
```

### Tiered Storage (Hot/Cold)

Mix SSD and HDD for cost optimization:

```yaml
storageTiers:
  enabled: true
  hot:
    storageClass: "fast-ssd"
    size: 50Gi
    dataDirs: 2  # 100Gi hot tier per pod
  cold:
    storageClass: "standard-hdd"
    size: 500Gi
    dataDirs: 2  # 1Ti cold tier per pod
```

**Use Cases:**
- **Hot tier**: Frequently accessed data, databases, active files
- **Cold tier**: Backups, archives, logs, large media files

## Common Configuration Examples

### External Access via Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
  api:
    enabled: true
    hosts:
      - host: s3.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: s3-tls
        hosts:
          - s3.example.com
  console:
    enabled: true
    hosts:
      - host: console.s3.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: console-tls
        hosts:
          - console.s3.example.com
```

### High Availability Cluster

```yaml
replicaCount: 4

podDisruptionBudget:
  enabled: true
  minAvailable: 3  # Keep 75% availability

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: rustfs
        topologyKey: kubernetes.io/hostname
```

### Monitoring with Prometheus

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    labels:
      prometheus: kube-prometheus
```

### Using Existing Secrets

```yaml
rustfs:
  existingSecret: "my-rustfs-credentials"
  rootUserKey: "username"
  rootPasswordKey: "password"
```

## Operational Commands

This chart includes a comprehensive Makefile for day-2 operations:

```bash
# Get credentials
make -f Makefile.rustfs.mk rustfs-get-credentials

# Port forward services
make -f Makefile.rustfs.mk rustfs-port-forward-api      # S3 API on localhost:9000
make -f Makefile.rustfs.mk rustfs-port-forward-console  # Console on localhost:9001

# Test S3 API (requires MinIO Client 'mc')
make -f Makefile.rustfs.mk rustfs-test-s3

# View logs and shell
make -f Makefile.rustfs.mk rustfs-logs
make -f Makefile.rustfs.mk rustfs-shell

# Health and metrics
make -f Makefile.rustfs.mk rustfs-health
make -f Makefile.rustfs.mk rustfs-metrics

# Scale cluster
make -f Makefile.rustfs.mk rustfs-scale REPLICAS=6

# Backup (requires VolumeSnapshot CRD)
make -f Makefile.rustfs.mk rustfs-backup

# View all resources
make -f Makefile.rustfs.mk rustfs-all

# Full help
make -f Makefile.rustfs.mk help
```

## S3 API Usage

### AWS CLI

```bash
# Configure AWS CLI
aws configure --profile rustfs
# AWS Access Key ID: <root-user>
# AWS Secret Access Key: <root-password>
# Default region name: us-east-1
# Default output format: json

# Create bucket
aws --profile rustfs --endpoint-url http://localhost:9000 s3 mb s3://mybucket

# Upload file
aws --profile rustfs --endpoint-url http://localhost:9000 s3 cp myfile.txt s3://mybucket/

# List buckets
aws --profile rustfs --endpoint-url http://localhost:9000 s3 ls
```

### MinIO Client (mc)

```bash
# Add alias
mc alias set myrustfs http://localhost:9000 <root-user> <root-password>

# Create bucket
mc mb myrustfs/mybucket

# Upload file
mc cp myfile.txt myrustfs/mybucket/

# List objects
mc ls myrustfs/mybucket
```

### Python (boto3)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='<root-user>',
    aws_secret_access_key='<root-password>',
    region_name='us-east-1'
)

# Create bucket
s3.create_bucket(Bucket='mybucket')

# Upload file
s3.upload_file('myfile.txt', 'mybucket', 'myfile.txt')

# List buckets
response = s3.list_buckets()
print([bucket['Name'] for bucket in response['Buckets']])
```

## Configuration Parameters

### RustFS Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `rustfs.rootUser` | Admin username | `rustfsadmin` |
| `rustfs.rootPassword` | Admin password (required) | `""` |
| `rustfs.existingSecret` | Use existing Secret | `""` |
| `rustfs.region` | S3 region name | `us-east-1` |
| `rustfs.apiPort` | S3 API port | `9000` |
| `rustfs.consolePort` | Web console port | `9001` |
| `rustfs.dataDirs` | Number of data directories | `4` |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.storageClass` | Storage class | `""` |
| `persistence.size` | Size per data directory | `100Gi` |
| `persistence.accessMode` | Access mode | `ReadWriteOnce` |

### Tiered Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storageTiers.enabled` | Enable tiered storage | `false` |
| `storageTiers.hot.storageClass` | Hot tier storage class | `ssd-storage` |
| `storageTiers.hot.size` | Hot tier size per dir | `50Gi` |
| `storageTiers.hot.dataDirs` | Number of hot dirs | `2` |
| `storageTiers.cold.storageClass` | Cold tier storage class | `hdd-storage` |
| `storageTiers.cold.size` | Cold tier size per dir | `200Gi` |
| `storageTiers.cold.dataDirs` | Number of cold dirs | `2` |

### Clustering

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `headlessService.enabled` | Enable headless service | `true` |

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.api.port` | API service port | `9000` |
| `service.console.port` | Console service port | `9001` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class | `nginx` |
| `ingress.api.hosts` | API hostnames | `[]` |
| `ingress.console.hosts` | Console hostnames | `[]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `2000m` |
| `resources.limits.memory` | Memory limit | `4Gi` |
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `1Gi` |

### Production Features

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Min replicas | `1` |
| `autoscaling.maxReplicas` | Max replicas | `10` |
| `podDisruptionBudget.enabled` | Enable PDB | `false` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `monitoring.serviceMonitor.enabled` | Enable ServiceMonitor | `false` |

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n rustfs -l app.kubernetes.io/name=rustfs

# Check events
kubectl get events -n rustfs --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n rustfs <pod-name>

# Describe pod
kubectl describe pod -n rustfs <pod-name>
```

### Permission issues (NFS/NAS)

Add init container to fix permissions:

```yaml
initContainers:
  - name: fix-permissions
    image: busybox:1.36
    command: ['sh', '-c', 'chown -R 1000:1000 /data && chmod -R 755 /data']
    volumeMounts:
      - name: data-0
        mountPath: /data/rustfs0
    securityContext:
      runAsUser: 0
```

### PVC not binding

```bash
# Check PVCs
kubectl get pvc -n rustfs

# Check storage class
kubectl get storageclass

# Check PV provisioner logs
kubectl logs -n kube-system -l app=local-path-provisioner
```

### S3 API not responding

```bash
# Check service
kubectl get svc -n rustfs

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://rustfs.rustfs.svc.cluster.local:9000/rustfs/health/live

# Check ingress
kubectl get ingress -n rustfs
kubectl describe ingress -n rustfs rustfs-api
```

## Upgrading

```bash
# Backup data first!
make -f Makefile.rustfs.mk rustfs-backup

# Upgrade chart
helm upgrade rustfs ./charts/rustfs \
  --namespace rustfs \
  -f ./charts/rustfs/values-homeserver.yaml

# Monitor rollout
kubectl rollout status statefulset rustfs -n rustfs
```

## Uninstallation

```bash
# Uninstall release
helm uninstall rustfs --namespace rustfs

# Optionally delete PVCs (WARNING: Data loss!)
kubectl delete pvc -n rustfs -l app.kubernetes.io/name=rustfs

# Delete namespace
kubectl delete namespace rustfs
```

## Important Notes

⚠️ **Alpha Software**: RustFS is in alpha stage. Do NOT use in production environments requiring high stability.

⚠️ **Data Safety**: Always enable persistence (`persistence.enabled=true`) and use `reclaimPolicy: Retain`.

⚠️ **Security**: Change default `rustfs.rootPassword` immediately after installation.

⚠️ **Backups**: Implement regular backup strategy using VolumeSnapshots or external backup tools.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.

## License

- **Chart License**: BSD-3-Clause (this repository)
- **Application License**: Apache-2.0 ([RustFS](https://github.com/rustfs/rustfs))

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **RustFS Official Site**: https://rustfs.com/
- **RustFS GitHub**: https://github.com/rustfs/rustfs
- **RustFS Documentation**: https://docs.rustfs.com/
- **Issue Tracker**: https://github.com/scriptonbasestar-container/sb-helm-charts/issues
