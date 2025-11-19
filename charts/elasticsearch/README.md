# Elasticsearch

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/elasticsearch)
[![Chart Version](https://img.shields.io/badge/chart-0.1.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-8.11.0-green.svg)](https://www.elastic.co/elasticsearch/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

Distributed search and analytics engine with integrated Kibana web UI for visualization and exploration.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install chart with default values (single-node mode)
helm install elasticsearch sb-charts/elasticsearch

# Install with production cluster (3 nodes + security)
helm install elasticsearch sb-charts/elasticsearch \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/elasticsearch/values-small-prod.yaml \
  --set elasticsearch.password=your-secure-password
```

## Introduction

This chart bootstraps an Elasticsearch deployment with optional Kibana on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ Single-node and cluster mode support
- ✅ Integrated Kibana for visualization and management
- ✅ Optional security with password authentication
- ✅ Production-ready with HA support (3+ nodes)
- ✅ Persistent storage with StatefulSet
- ✅ Snapshot/backup to S3 (MinIO compatible)
- ✅ No external database required

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- PersistentVolume provisioner support in the underlying infrastructure

### External Dependencies

**None required!** Elasticsearch is self-contained and does not require external databases.

**Optional:**
- **MinIO/S3**: For snapshot repository (backup/restore)
- **Prometheus**: For metrics collection

## Installing the Chart

### Quick Start

```bash
# Install with default values (single-node mode, security disabled)
helm install my-elasticsearch sb-charts/elasticsearch
```

### Deployment Scenarios

This chart includes pre-configured values for different deployment scenarios:

#### Development Environment

```bash
helm install my-elasticsearch sb-charts/elasticsearch \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/elasticsearch/values-dev.yaml
```

**Configuration:**
- Single node (no clustering)
- Security disabled (no password)
- CORS enabled for browser-based tools
- Kibana ingress enabled
- Resources: 500m-2000m CPU, 1Gi-2Gi RAM
- Storage: 10Gi per node

**Use Case:** Local development, testing, quick prototyping

#### Small Production Cluster

```bash
helm install my-elasticsearch sb-charts/elasticsearch \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/elasticsearch/values-small-prod.yaml \
  --set elasticsearch.password=your-secure-password
```

**Configuration:**
- 3-node cluster with quorum
- Security enabled (password required)
- Kibana HA (2 replicas)
- Production ingress with TLS
- Pod anti-affinity for HA
- PodDisruptionBudget (minAvailable: 2)
- Resources: 2000m-4000m CPU, 2Gi-4Gi RAM per node
- Storage: 100Gi per node (SSD recommended)
- Init container for sysctl tuning

**Use Case:** Small production deployments, logging infrastructure, search applications

## Configuration

### Deployment Modes

Elasticsearch supports two deployment modes:

**Single-Node Mode:**
- Single server deployment
- `discovery.type=single-node`
- Suitable for development/testing
- Lower resource requirements
- No cluster quorum required

**Cluster Mode:**
- 3+ nodes (minimum for quorum)
- Cluster discovery via headless service
- Master election and distributed data
- Production HA deployment
- Automatic shard allocation

```yaml
elasticsearch:
  clusterMode: true  # Enable cluster mode
  replicas: 3        # Minimum 3 for quorum
  clusterName: "elasticsearch-prod"
```

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `elasticsearch.replicas` | Number of Elasticsearch nodes | `1` |
| `elasticsearch.clusterMode` | Enable cluster mode (requires 3+ nodes) | `false` |
| `elasticsearch.clusterName` | Cluster name | `elasticsearch` |
| `elasticsearch.password` | Elastic user password (empty = security disabled) | `""` |
| `elasticsearch.javaOpts` | JVM heap options | `-Xms1g -Xmx1g` |
| `elasticsearch.httpCorsEnabled` | Enable CORS (for browser clients) | `false` |
| `kibana.enabled` | Enable Kibana deployment | `true` |
| `kibana.replicas` | Number of Kibana replicas | `1` |
| `kibana.ingress.enabled` | Enable Kibana ingress | `false` |
| `image.repository` | Elasticsearch image | `docker.elastic.co/elasticsearch/elasticsearch` |
| `image.tag` | Image tag (overrides appVersion) | `""` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | Storage size per node | `30Gi` |
| `persistence.storageClass` | Storage class name | `""` |
| `resources.limits.memory` | Memory limit | `2Gi` |
| `resources.limits.cpu` | CPU limit | `2000m` |

See [values.yaml](values.yaml) for all available options.

### JVM Heap Size

**IMPORTANT**: Set heap size to 50% of container memory limit, maximum 31GB.

```yaml
elasticsearch:
  javaOpts: "-Xms2g -Xmx2g"  # For 4Gi memory limit

resources:
  limits:
    memory: 4Gi
```

### Using Existing Secrets

```yaml
elasticsearch:
  existingSecret: "my-es-secret"
  # Secret must contain key: elastic-password
```

### Using Existing ConfigMap

```yaml
elasticsearch:
  existingConfigMap: "my-es-config"
  # ConfigMap must contain key: elasticsearch.yml
```

## Persistence

The chart creates Persistent Volumes using StatefulSet `volumeClaimTemplates` (one per pod).

**PVC Configuration:**

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # Use SSD for better performance
  accessMode: ReadWriteOnce
  size: 100Gi  # Size per node
  annotations: {}
```

**Total Storage Calculation:**
```
Total = replicas × size
Example: 3 nodes × 100Gi = 300Gi raw
With replication factor 1: ~150Gi usable (excluding overhead)
```

## Networking

### Service Configuration

Elasticsearch exposes two services:
- **HTTP Service** (port 9200): REST API for queries and indexing
- **Headless Service** (port 9300): Cluster discovery and node-to-node transport

```yaml
service:
  type: ClusterIP
  http:
    port: 9200

headlessService:
  annotations: {}
```

### Kibana Ingress

```yaml
kibana:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
    hosts:
      - host: kibana.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: kibana-tls
        hosts:
          - kibana.example.com
```

## Security

### Password Authentication

Enable security by setting password:

```yaml
elasticsearch:
  password: "your-secure-password"
```

This enables:
- `xpack.security.enabled=true`
- `elastic` user with password
- HTTP authentication required

### CORS Settings (Development)

Enable for browser-based Elasticsearch clients:

```yaml
elasticsearch:
  httpCorsEnabled: true
  httpCorsAllowOrigin: "*"  # or specific origin
```

⚠️ **Production**: Disable CORS or restrict to specific origins.

### Pod Security Context

```yaml
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000
  fsGroupChangePolicy: "OnRootMismatch"

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
      - ALL
```

### System Configuration

For production, set `vm.max_map_count=262144` on Kubernetes nodes:

```bash
# On each node
sysctl -w vm.max_map_count=262144

# Persistent
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
```

Or use init container (values-small-prod.yaml includes this):

```yaml
initContainers:
  - name: init-sysctl
    image: busybox:latest
    command:
      - sh
      - -c
      - |
        sysctl -w vm.max_map_count=262144
        sysctl -w fs.file-max=65536
    securityContext:
      privileged: true
```

## High Availability

### Cluster Quorum

Minimum 3 nodes for cluster mode with master election:

```yaml
elasticsearch:
  replicas: 3  # Minimum for quorum
  clusterMode: true
```

Cluster will set `cluster.initial_master_nodes=elasticsearch-0,elasticsearch-1,elasticsearch-2`.

### Pod Disruption Budget

Maintain quorum during updates:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 2  # For 3-node cluster
```

### Pod Anti-Affinity

Distribute pods across nodes/zones:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/component
              operator: In
              values:
                - elasticsearch
        topologyKey: kubernetes.io/hostname
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/component
                operator: In
                values:
                  - elasticsearch
          topologyKey: topology.kubernetes.io/zone
```

## Monitoring

### Health Probes

Chart includes comprehensive health checks:

```yaml
livenessProbe:
  httpGet:
    path: /_cluster/health?local=true
    port: 9200
  initialDelaySeconds: 90
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /_cluster/health?local=true
    port: 9200
  initialDelaySeconds: 30
  periodSeconds: 10

startupProbe:
  httpGet:
    path: /_cluster/health?local=true
    port: 9200
  failureThreshold: 60  # Up to 10 minutes for startup
```

### Prometheus Integration

Enable monitoring (optional):

```yaml
elasticsearch:
  monitoring:
    enabled: true

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9200"
  prometheus.io/path: "/_prometheus/metrics"
```

## Kibana Setup

Kibana is enabled by default and automatically connects to Elasticsearch.

### Accessing Kibana

**Port Forward:**
```bash
kubectl port-forward svc/kibana 5601:5601
# Access at http://localhost:5601
```

**Ingress:**
```yaml
kibana:
  ingress:
    enabled: true
    hosts:
      - host: kibana.example.com
```

### Kibana Authentication

When Elasticsearch security is enabled, Kibana uses elastic user:

```bash
# Get password
kubectl get secret elasticsearch-secret -o jsonpath='{.data.elastic-password}' | base64 -d

# Login:
# Username: elastic
# Password: (from above)
```

## Elasticsearch Client Setup

### Using cURL

```bash
# Port forward
kubectl port-forward svc/elasticsearch 9200:9200 &

# No authentication (security disabled)
curl http://localhost:9200

# With authentication
PASSWORD=$(kubectl get secret elasticsearch-secret -o jsonpath='{.data.elastic-password}' | base64 -d)
curl -u elastic:$PASSWORD http://localhost:9200

# Cluster health
curl -u elastic:$PASSWORD http://localhost:9200/_cluster/health?pretty

# List indices
curl -u elastic:$PASSWORD http://localhost:9200/_cat/indices?v
```

### Python Client

```python
from elasticsearch import Elasticsearch

# No authentication
es = Elasticsearch(['http://elasticsearch:9200'])

# With authentication
es = Elasticsearch(
    ['http://elasticsearch:9200'],
    basic_auth=('elastic', 'your-password')
)

# Create index
es.indices.create(index='myindex')

# Index document
es.index(index='myindex', id=1, document={'field': 'value'})

# Search
result = es.search(index='myindex', query={'match_all': {}})
```

### Node.js Client

```javascript
const { Client } = require('@elastic/elasticsearch');

// No authentication
const client = new Client({ node: 'http://elasticsearch:9200' });

// With authentication
const client = new Client({
  node: 'http://elasticsearch:9200',
  auth: {
    username: 'elastic',
    password: 'your-password'
  }
});

// Create index
await client.indices.create({ index: 'myindex' });

// Index document
await client.index({
  index: 'myindex',
  id: 1,
  document: { field: 'value' }
});

// Search
const result = await client.search({
  index: 'myindex',
  query: { match_all: {} }
});
```

## Snapshot and Backup

### S3/MinIO Snapshot Repository

Elasticsearch supports S3-compatible snapshot repositories (MinIO, AWS S3, etc.).

**Prerequisites:**
- MinIO/S3 bucket created
- Access credentials

**Create Snapshot Repository:**

```bash
# Using Makefile
make -f make/ops/elasticsearch.mk es-create-snapshot-repo \
  REPO=minio \
  BUCKET=elasticsearch-backups \
  ENDPOINT=http://minio:9000 \
  ACCESS_KEY=admin \
  SECRET_KEY=password123

# Or manually
kubectl exec -it elasticsearch-0 -- curl -X PUT "http://localhost:9200/_snapshot/minio?pretty" \
  -u elastic:password \
  -H 'Content-Type: application/json' -d'{
  "type": "s3",
  "settings": {
    "bucket": "elasticsearch-backups",
    "endpoint": "http://minio:9000",
    "access_key": "admin",
    "secret_key": "password123",
    "path_style_access": true
  }
}'
```

**Create Snapshot:**

```bash
# Using Makefile
make -f make/ops/elasticsearch.mk es-create-snapshot REPO=minio SNAPSHOT=snapshot_1

# Or manually
curl -X PUT "http://localhost:9200/_snapshot/minio/snapshot_1?wait_for_completion=false&pretty" -u elastic:password
```

**List Snapshots:**

```bash
make -f make/ops/elasticsearch.mk es-snapshots REPO=minio
```

**Restore Snapshot:**

```bash
make -f make/ops/elasticsearch.mk es-restore-snapshot REPO=minio SNAPSHOT=snapshot_1
```

See [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md) for MinIO integration.

## Operational Commands

Using Makefile (`make/ops/elasticsearch.mk`):

### Credentials and Access

```bash
# Get elastic user password
make -f make/ops/elasticsearch.mk es-get-password

# Port forward Elasticsearch API
make -f make/ops/elasticsearch.mk es-port-forward

# Port forward Kibana
make -f make/ops/elasticsearch.mk kibana-port-forward
```

### Health and Status

```bash
# Cluster health check
make -f make/ops/elasticsearch.mk es-health

# Cluster status (pods, nodes, PVCs)
make -f make/ops/elasticsearch.mk es-cluster-status

# Node information
make -f make/ops/elasticsearch.mk es-nodes

# Elasticsearch version
make -f make/ops/elasticsearch.mk es-version

# Kibana health
make -f make/ops/elasticsearch.mk kibana-health
```

### Index Management

```bash
# List all indices
make -f make/ops/elasticsearch.mk es-indices

# Create index
make -f make/ops/elasticsearch.mk es-create-index INDEX=myindex

# Delete index
make -f make/ops/elasticsearch.mk es-delete-index INDEX=myindex

# Shard allocation
make -f make/ops/elasticsearch.mk es-shards

# Disk allocation
make -f make/ops/elasticsearch.mk es-allocation
```

### Monitoring

```bash
# Cluster statistics
make -f make/ops/elasticsearch.mk es-stats

# Running tasks
make -f make/ops/elasticsearch.mk es-tasks

# Elasticsearch logs
make -f make/ops/elasticsearch.mk es-logs

# All Elasticsearch pods logs
make -f make/ops/elasticsearch.mk es-logs-all

# Kibana logs
make -f make/ops/elasticsearch.mk kibana-logs
```

### Operations

```bash
# Open shell in Elasticsearch pod
make -f make/ops/elasticsearch.mk es-shell

# Open shell in Kibana pod
make -f make/ops/elasticsearch.mk kibana-shell

# Restart Elasticsearch
make -f make/ops/elasticsearch.mk es-restart

# Restart Kibana
make -f make/ops/elasticsearch.mk kibana-restart

# Scale Elasticsearch (min 3 for cluster mode)
make -f make/ops/elasticsearch.mk es-scale REPLICAS=3
```

### Snapshot/Backup

```bash
# List snapshot repositories
make -f make/ops/elasticsearch.mk es-snapshot-repos

# Create S3 snapshot repository
make -f make/ops/elasticsearch.mk es-create-snapshot-repo \
  REPO=minio BUCKET=backups ENDPOINT=http://minio:9000 \
  ACCESS_KEY=admin SECRET_KEY=password

# List snapshots
make -f make/ops/elasticsearch.mk es-snapshots REPO=minio

# Create snapshot
make -f make/ops/elasticsearch.mk es-create-snapshot REPO=minio SNAPSHOT=snapshot_1

# Restore snapshot
make -f make/ops/elasticsearch.mk es-restore-snapshot REPO=minio SNAPSHOT=snapshot_1
```

## Upgrading

```bash
# Update repository
helm repo update

# Upgrade release
helm upgrade my-elasticsearch sb-charts/elasticsearch

# Upgrade with new values
helm upgrade my-elasticsearch sb-charts/elasticsearch -f my-values.yaml

# Check rollout status
kubectl rollout status statefulset/elasticsearch
```

**Note**: StatefulSet updates are performed one pod at a time. With PodDisruptionBudget, cluster remains available during upgrade.

## Uninstalling

```bash
# Uninstall release
helm uninstall my-elasticsearch

# Optionally delete PVCs (WARNING: This deletes all data!)
kubectl delete pvc -l app.kubernetes.io/component=elasticsearch
```

## Troubleshooting

### Pod not starting

Check logs:
```bash
kubectl logs -l app.kubernetes.io/component=elasticsearch
```

Common issues:
- **vm.max_map_count too low**: Use init container or configure on nodes
- **Memory limit too low**: Increase resources.limits.memory
- **Heap size misconfigured**: Set javaOpts to 50% of memory limit
- **PVC not bound**: Check StorageClass and PV provisioner
- **Permission denied**: Check podSecurityContext.fsGroup (1000)

### Cluster mode not forming

Verify headless service and DNS:
```bash
kubectl get svc elasticsearch-headless
nslookup elasticsearch-0.elasticsearch-headless.default.svc.cluster.local
```

Check cluster settings:
```bash
make -f make/ops/elasticsearch.mk es-cluster-status
```

Ensure:
- `elasticsearch.clusterMode=true`
- `elasticsearch.replicas >= 3`
- Headless service exists
- All pods can communicate on port 9300

### Kibana cannot connect

Check Elasticsearch health:
```bash
make -f make/ops/elasticsearch.mk es-health
```

Check Kibana logs:
```bash
make -f make/ops/elasticsearch.mk kibana-logs
```

Verify:
- Elasticsearch is running and healthy
- Password matches (if security enabled)
- Service name is correct

### Performance Issues

- Use SSD storage class for better I/O
- Increase JVM heap size (up to 31GB max)
- Increase resources (CPU/memory)
- Enable monitoring to identify bottlenecks
- Optimize index settings (refresh_interval, number_of_replicas)
- Use bulk API for indexing

### Red Cluster Status

Check shard allocation:
```bash
make -f make/ops/elasticsearch.mk es-shards
make -f make/ops/elasticsearch.mk es-allocation
```

Common causes:
- Insufficient disk space
- Node failures
- Unassigned shards (check replica settings)
- Index corruption

## Additional Resources

- [Elasticsearch Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Kibana Documentation](https://www.elastic.co/guide/en/kibana/current/index.html)
- [Elasticsearch Client Libraries](https://www.elastic.co/guide/en/elasticsearch/client/index.html)
- [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md)
- [Chart Development Guide](../../docs/CHART_DEVELOPMENT_GUIDE.md)
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md)

## License

This Helm chart is licensed under the BSD-3-Clause License.
Elasticsearch and Kibana are licensed under the Elastic License 2.0 (ELv2) and Server Side Public License (SSPL).

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.
