# MinIO

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/minio)
[![Chart Version](https://img.shields.io/badge/chart-0.3.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-RELEASE.2025--10--15-green.svg)](https://min.io/)
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

## Backup & Recovery

### Backup Strategy

MinIO supports multiple backup strategies for comprehensive data protection:

| Component | Priority | Backup Method | Frequency |
|-----------|----------|---------------|-----------|
| Bucket Data | Critical | Site replication / mc mirror | Daily/Continuous |
| Bucket Metadata | Critical | mc admin policy export | Daily |
| Configuration | Important | kubectl export / mc admin config | On change |
| IAM Policies | Important | mc admin user/policy list | Daily |

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/minio.mk minio-full-backup

# Bucket data backup
make -f make/ops/minio.mk minio-backup-buckets

# Configuration backup
make -f make/ops/minio.mk minio-backup-config

# IAM backup
make -f make/ops/minio.mk minio-backup-iam

# List backups
make -f make/ops/minio.mk minio-backup-status
```

### Backup Methods

**1. Site Replication (Recommended for Production)**

Best for multi-site deployments with continuous replication:

```bash
# Configure site replication
mc admin replicate add minio-primary minio-secondary

# Verify replication status
mc admin replicate status minio-primary
```

**2. Bucket Replication**

For selective bucket-level replication:

```bash
# Enable versioning (required)
mc version enable minio-primary/mybucket
mc version enable minio-backup/mybucket-backup

# Set up replication
mc replicate add minio-primary/mybucket \
  --remote-bucket "minio-backup/mybucket-backup" \
  --priority 1

# Verify replication
mc replicate status minio-primary/mybucket
```

**3. Scheduled Mirror (Cron-based)**

For periodic backups:

```bash
# Mirror bucket to remote location
mc mirror minio-primary/mybucket s3/backup-bucket

# With bandwidth limit
mc mirror --limit-upload 10MiB minio-primary/mybucket s3/backup-bucket
```

**4. PVC Snapshots**

For Kubernetes-native snapshots (requires CSI driver):

```bash
# Create VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: minio-data-snapshot-$(date +%Y%m%d)
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: data-minio-0
EOF
```

### Recovery Procedures

**Bucket Metadata Restore:**

```bash
# Restore bucket policy
mc admin policy set minio-primary mybucket < metadata/mybucket-policy.json

# Restore lifecycle rules
mc ilm import minio-primary/mybucket < metadata/mybucket-lifecycle.json
```

**IAM Policy Restore:**

```bash
# Restore users
make -f make/ops/minio.mk minio-restore-users FILE=backup/users-20250109.json

# Restore policies
make -f make/ops/minio.mk minio-restore-policies FILE=backup/policies-20250109.json
```

**Full Disaster Recovery:**

```bash
# 1. Deploy new cluster
helm install minio sb-charts/minio -f values-prod-distributed.yaml

# 2. Restore configuration
make -f make/ops/minio.mk minio-restore-config FILE=backup/config-20250109.json

# 3. Restore IAM
make -f make/ops/minio.mk minio-restore-iam FILE=backup/iam-20250109.tar.gz

# 4. Restore bucket data (from site replication or backup)
mc mirror s3/backup-bucket minio-primary
```

### RTO/RPO Targets

| Scenario | RTO | RPO |
|----------|-----|-----|
| Bucket metadata restore | < 30 min | 24 hours |
| Configuration restore | < 15 min | 24 hours |
| IAM policy restore | < 15 min | 24 hours |
| Full disaster recovery | < 2 hours | 24 hours |
| Object-level restore | < 1 hour | Real-time (with versioning) |

**Comprehensive Guide:** See [MinIO Backup Guide](../../docs/minio-backup-guide.md) for detailed backup and recovery procedures.

## Security & RBAC

### RBAC Resources

This chart creates the following RBAC resources:

**Role** (`minio-role`):
- Namespace-scoped read-only permissions
- Access to ConfigMaps, Secrets, Pods, Services, Endpoints, PVCs

**RoleBinding** (`minio-rolebinding`):
- Binds Role to ServiceAccount

**ServiceAccount** (`minio`):
- Pod identity for MinIO operations

### RBAC Configuration

```yaml
# Enable RBAC (default: true)
rbac:
  create: true
  annotations: {}
```

### Security Best Practices

**DO** ✅

- ✅ Use TLS/SSL for production deployments
- ✅ Enable encryption at rest (SSE-S3, SSE-KMS)
- ✅ Rotate access keys regularly
- ✅ Use IAM policies for granular access control
- ✅ Enable bucket versioning for critical data
- ✅ Implement object lock for compliance
- ✅ Monitor access logs and audit trails
- ✅ Use NetworkPolicy to restrict traffic

**DON'T** ❌

- ❌ Don't use default credentials in production
- ❌ Don't disable TLS for external access
- ❌ Don't grant overly permissive IAM policies
- ❌ Don't store credentials in plain text
- ❌ Don't skip backup encryption
- ❌ Don't expose console publicly without authentication

### Pod Security Context

MinIO runs as non-root user (UID 1000):

```yaml
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: false
```

### NetworkPolicy Example

Restrict MinIO access to specific namespaces:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minio-network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: minio
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: allowed-namespace
      ports:
        - port: 9000
          protocol: TCP
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - port: 53
          protocol: UDP
```

### TLS/SSL Configuration

Enable TLS for secure communication:

```yaml
# values.yaml
tls:
  enabled: true
  certSecret: "minio-tls-cert"

# Create TLS secret
kubectl create secret tls minio-tls-cert \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n default
```

### RBAC Verification

```bash
# Verify Role permissions
kubectl describe role minio-role -n default

# Check RoleBinding
kubectl describe rolebinding minio-rolebinding -n default

# Verify ServiceAccount
kubectl get serviceaccount minio -n default
```

## Operations

### Daily Operations

**Access MinIO:**

```bash
# Port forward API (S3 endpoint)
make -f make/ops/minio.mk minio-port-forward-api

# Port forward Console (Web UI)
make -f make/ops/minio.mk minio-port-forward-console
# Access at: http://localhost:9001

# Get credentials
make -f make/ops/minio.mk minio-get-credentials
```

**Shell Access:**

```bash
# Open shell in MinIO container
make -f make/ops/minio.mk minio-shell

# View logs
make -f make/ops/minio.mk minio-logs
```

### Monitoring & Health Checks

**Cluster Health:**

```bash
# Check cluster status
make -f make/ops/minio.mk minio-health

# Check node status
make -f make/ops/minio.mk minio-cluster-info

# Monitor heal operations
make -f make/ops/minio.mk minio-heal-status
```

**Resource Monitoring:**

```bash
# Check resource usage
kubectl top pods -n default -l app.kubernetes.io/name=minio

# Check disk usage
make -f make/ops/minio.mk minio-disk-usage

# View Prometheus metrics
make -f make/ops/minio.mk minio-metrics
```

### Bucket Management

**Bucket Operations:**

```bash
# List buckets
make -f make/ops/minio.mk minio-list-buckets

# Create bucket
make -f make/ops/minio.mk minio-create-bucket BUCKET=my-bucket

# Delete bucket (WARNING: destructive!)
make -f make/ops/minio.mk minio-delete-bucket BUCKET=my-bucket

# Get bucket size
make -f make/ops/minio.mk minio-bucket-size BUCKET=my-bucket
```

**Bucket Policies:**

```bash
# Set bucket policy
make -f make/ops/minio.mk minio-set-policy BUCKET=my-bucket POLICY=public

# Get bucket policy
make -f make/ops/minio.mk minio-get-policy BUCKET=my-bucket

# Remove bucket policy
make -f make/ops/minio.mk minio-remove-policy BUCKET=my-bucket
```

### IAM Management

**User Management:**

```bash
# List users
make -f make/ops/minio.mk minio-list-users

# Create user
make -f make/ops/minio.mk minio-create-user USER=john ACCESS_KEY=xxx SECRET_KEY=yyy

# Delete user
make -f make/ops/minio.mk minio-delete-user USER=john
```

**Policy Management:**

```bash
# List policies
make -f make/ops/minio.mk minio-list-policies

# Create policy
make -f make/ops/minio.mk minio-create-policy POLICY=mypolicy FILE=policy.json

# Attach policy to user
make -f make/ops/minio.mk minio-attach-policy USER=john POLICY=readwrite
```

### Maintenance Operations

**Restart MinIO:**

```bash
# Rolling restart (distributed mode - zero downtime)
make -f make/ops/minio.mk minio-restart

# Full restart (standalone mode)
kubectl rollout restart statefulset minio -n default
```

**Storage Maintenance:**

```bash
# Run heal operation (repair corrupted data)
make -f make/ops/minio.mk minio-heal

# Check disk free space
make -f make/ops/minio.mk minio-disk-free

# Clean up incomplete uploads
make -f make/ops/minio.mk minio-cleanup-incomplete
```

### Troubleshooting

**Common Issues:**

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| Pod not starting | `kubectl describe pod minio-0` | Check PVC binding, resources |
| Quorum lost | `mc admin cluster info` | Ensure n/2+1 nodes online |
| Slow performance | `mc admin prometheus metrics` | Check heal status, disk I/O |
| Access denied | `mc admin user list` | Verify IAM policies |

**Debug Commands:**

```bash
# Check pod status
kubectl get pods -n default -l app.kubernetes.io/name=minio

# View pod events
kubectl describe pod minio-0 -n default

# Check persistent volumes
kubectl get pvc -n default -l app.kubernetes.io/name=minio

# View detailed logs
kubectl logs minio-0 -n default --tail=100
```

**Performance Tuning:**

```yaml
# Increase resources for better performance
resources:
  requests:
    memory: 4Gi
    cpu: 2000m
  limits:
    memory: 8Gi
    cpu: 4000m

# Adjust drive configuration
minio:
  drivesPerNode: 4  # More drives = better performance
```

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
