# Loki Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.9.3](https://img.shields.io/badge/AppVersion-2.9.3-informational?style=flat-square)

Loki log aggregation system with Grafana integration for Kubernetes

## Features

- **Flexible Storage**: Filesystem (default) or S3-compatible object storage
- **High Availability**: StatefulSet with memberlist gossip protocol
- **Grafana Integration**: Native LogQL support for log queries
- **Replication**: Configurable replication factor for data redundancy
- **Persistent Storage**: PVC for local chunks and index
- **Health Probes**: Liveness and readiness checks
- **Operational Tools**: 20+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with filesystem storage (development)
helm install my-loki scripton-charts/loki

# Install with S3 storage (production)
helm install my-loki scripton-charts/loki \
  --set loki.storage.type=s3 \
  --set loki.storage.s3.endpoint=s3.amazonaws.com \
  --set loki.storage.s3.bucketNames=loki-chunks \
  --set loki.storage.s3.accessKeyId=AKIAIOSFODNN7EXAMPLE \
  --set loki.storage.s3.secretAccessKey=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
  --set replicaCount=3 \
  --set loki.replicationFactor=3
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner (for persistence)
- S3-compatible storage (for production S3 mode)

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Loki replicas | `1` |
| `loki.storage.type` | Storage backend (filesystem/s3) | `filesystem` |
| `loki.storage.s3.endpoint` | S3 endpoint | `""` |
| `loki.storage.s3.bucketNames` | S3 bucket name | `""` |
| `loki.replicationFactor` | Replication factor | `1` |
| `loki.limits.ingestionRateMB` | Ingestion rate limit (MB) | `4` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `10Gi` |

## Operational Commands

```bash
# View logs
make -f make/ops/loki.mk loki-logs

# Port forward
make -f make/ops/loki.mk loki-port-forward

# Check readiness
make -f make/ops/loki.mk loki-ready

# Get ring status
make -f make/ops/loki.mk loki-ring-status

# Query logs
make -f make/ops/loki.mk loki-query QUERY='{job="app"}' TIME=5m

# Get all labels
make -f make/ops/loki.mk loki-labels

# Send test log
make -f make/ops/loki.mk loki-test-push

# Get Grafana datasource URL
make -f make/ops/loki.mk loki-grafana-datasource

# Scale replicas
make -f make/ops/loki.mk loki-scale REPLICAS=3
```

## Production Setup

### Filesystem Storage (Small Scale)

```yaml
# values-filesystem-prod.yaml
replicaCount: 2

loki:
  storage:
    type: "filesystem"
  replicationFactor: 2

persistence:
  storageClass: "fast-ssd"
  size: 100Gi

resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

### S3 Storage (Large Scale)

```yaml
# values-s3-prod.yaml
replicaCount: 3

loki:
  storage:
    type: "s3"
    s3:
      endpoint: "s3.amazonaws.com"
      bucketNames: "loki-chunks"
      region: "us-east-1"
      accessKeyId: "AKIAIOSFODNN7EXAMPLE"
      secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      s3ForcePathStyle: false
  replicationFactor: 3
  limits:
    ingestionRateMB: 8
    ingestionBurstSizeMB: 12

persistence:
  storageClass: "fast-ssd"
  size: 50Gi

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - loki
        topologyKey: kubernetes.io/hostname
```

## Grafana Integration

### Add Loki as Data Source

1. **Via UI:**
   - Navigate to Configuration → Data Sources
   - Click "Add data source"
   - Select "Loki"
   - URL: `http://loki.default.svc.cluster.local:3100`

2. **Via API:**

```bash
make -f make/ops/loki.mk loki-grafana-datasource
```

3. **Query Logs:**
   - Use LogQL syntax in Grafana Explore
   - Example: `{namespace="production"} |= "error"`

## Log Shipping

### Promtail Configuration

```yaml
# promtail-config.yaml
clients:
  - url: http://loki.default.svc.cluster.local:3100/loki/api/v1/push

scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
```

### Fluent Bit Configuration

```ini
[OUTPUT]
    Name        loki
    Match       *
    Host        loki.default.svc.cluster.local
    Port        3100
    Labels      job=fluentbit
```

## LogQL Query Examples

```logql
# All logs from a namespace
{namespace="production"}

# Error logs
{namespace="production"} |= "error"

# Rate of errors per minute
rate({namespace="production"} |= "error" [1m])

# Logs matching regex pattern
{namespace="production"} |~ "user \\d+ logged in"

# Logs from specific pod
{pod="myapp-12345"}

# JSON parsing
{namespace="production"} | json | line_format "{{.message}}"
```

## Storage Backends

### Filesystem Storage

- **Use Case**: Development, small deployments
- **Pros**: Simple setup, no external dependencies
- **Cons**: Limited scalability, single-node storage

### S3-Compatible Storage

- **Use Case**: Production, large-scale deployments
- **Pros**: Unlimited storage, cost-effective, HA
- **Cons**: Network latency, S3 costs
- **Compatible Services**: AWS S3, MinIO, Ceph, GCS, Azure Blob

## High Availability

For HA deployment:

1. **Set replicas ≥ 3:**
   ```yaml
   replicaCount: 3
   loki:
     replicationFactor: 3
   ```

2. **Use S3 storage:**
   ```yaml
   loki:
     storage:
       type: "s3"
   ```

3. **Enable pod anti-affinity:**
   ```yaml
   affinity:
     podAntiAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
         - labelSelector:
             matchExpressions:
               - key: app.kubernetes.io/name
                 operator: In
                 values:
                   - loki
           topologyKey: kubernetes.io/hostname
   ```

## Troubleshooting

### Check Loki is Ready

```bash
make -f make/ops/loki.mk loki-ready
```

### View Ring Status

```bash
make -f make/ops/loki.mk loki-ring-status
```

### Test Log Ingestion

```bash
make -f make/ops/loki.mk loki-test-push
make -f make/ops/loki.mk loki-query QUERY='{job="test"}'
```

### Check Storage

```bash
make -f make/ops/loki.mk loki-check-storage
```

### View Configuration

```bash
make -f make/ops/loki.mk loki-config
```

## License

- Chart: BSD 3-Clause License
- Loki: Apache License 2.0

## Additional Resources

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/logql/)
- [Promtail Documentation](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**Loki Version**: 2.9.3
