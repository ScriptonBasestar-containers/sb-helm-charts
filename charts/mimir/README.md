# Mimir Helm Chart

Grafana Mimir is a horizontally scalable, highly available, multi-tenant, long-term storage solution for Prometheus metrics.

## Overview

This chart deploys Mimir in monolithic mode, suitable for small to medium deployments. For large-scale deployments, consider using the microservices mode with the official Grafana Mimir Helm chart.

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- PV provisioner support (if persistence enabled)
- S3-compatible storage (recommended for production)

## Installation

```bash
# Add repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# Install with default values (filesystem storage)
helm install mimir sb-charts/mimir -n monitoring --create-namespace

# Install with S3/MinIO storage (recommended)
helm install mimir sb-charts/mimir -n monitoring \
  --set mimir.storage.backend=s3 \
  --set mimir.storage.s3.endpoint=minio.monitoring.svc:9000 \
  --set mimir.storage.s3.bucket=mimir-blocks \
  --set mimir.storage.s3.accessKeyId=admin \
  --set mimir.storage.s3.secretAccessKey=secretpassword \
  --set mimir.storage.s3.insecure=true
```

## Configuration

### Storage Backends

| Backend | Description | Production |
|---------|-------------|------------|
| filesystem | Local PVC storage | No |
| s3 | S3 or S3-compatible (MinIO) | Yes |
| gcs | Google Cloud Storage | Yes |
| azure | Azure Blob Storage | Yes |

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Mimir instances | `1` |
| `mimir.target` | Mimir target mode | `all` |
| `mimir.multitenancy.enabled` | Enable multi-tenancy | `false` |
| `mimir.storage.backend` | Storage backend | `filesystem` |
| `mimir.blocks.retentionPeriod` | Block retention | `2w` |
| `mimir.limits.ingestionRate` | Ingestion rate limit | `10000` |
| `mimir.limits.maxGlobalSeriesPerUser` | Max series per tenant | `150000` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `50Gi` |

### S3/MinIO Configuration

```yaml
mimir:
  storage:
    backend: "s3"
    s3:
      endpoint: "minio.monitoring.svc.cluster.local:9000"
      bucket: "mimir-blocks"
      region: "us-east-1"
      accessKeyId: "admin"
      secretAccessKey: "secretpassword"
      insecure: true  # Set to false for HTTPS
```

### Multi-tenancy

Enable multi-tenancy for isolating metrics by tenant:

```yaml
mimir:
  multitenancy:
    enabled: true
```

When multi-tenancy is enabled, clients must include the `X-Scope-OrgID` header:

```yaml
# Prometheus remote_write
remote_write:
  - url: http://mimir:8080/api/v1/push
    headers:
      X-Scope-OrgID: tenant-1
```

### Limits Configuration

```yaml
mimir:
  limits:
    ingestionRate: 50000
    ingestionBurstSize: 500000
    maxGlobalSeriesPerUser: 500000
    maxQueryLength: "2160h"  # 90 days
```

## Usage

### Configure Prometheus Remote Write

Add to your Prometheus configuration:

```yaml
remote_write:
  - url: http://mimir.monitoring.svc.cluster.local:8080/api/v1/push
```

### Configure Grafana Datasource

Add Mimir as a Prometheus datasource:

```yaml
datasources:
  - name: Mimir
    type: prometheus
    url: http://mimir.monitoring.svc.cluster.local:8080/prometheus
    access: proxy
```

### Query Metrics

Use the Prometheus query API:

```bash
# PromQL query
curl -G http://mimir:8080/prometheus/api/v1/query \
  --data-urlencode 'query=up'

# Range query
curl -G http://mimir:8080/prometheus/api/v1/query_range \
  --data-urlencode 'query=rate(http_requests_total[5m])' \
  --data-urlencode 'start=2024-01-01T00:00:00Z' \
  --data-urlencode 'end=2024-01-02T00:00:00Z' \
  --data-urlencode 'step=1h'
```

## Production Recommendations

### Storage

- **Always use object storage** (S3/MinIO/GCS/Azure) for production
- Filesystem storage is only suitable for testing

### Resources

```yaml
resources:
  limits:
    cpu: 4000m
    memory: 8Gi
  requests:
    cpu: 1000m
    memory: 2Gi
```

### High Availability

For HA deployments, increase replication:

```yaml
replicaCount: 3
mimir:
  ingester:
    ring:
      replicationFactor: 3
```

### Monitoring

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
  labels:
    release: prometheus
```

## Upgrading

```bash
helm upgrade mimir sb-charts/mimir -n monitoring -f values.yaml
```

## Uninstalling

```bash
helm uninstall mimir -n monitoring
```

**Note**: PVCs are not automatically deleted. Remove manually if needed:

```bash
kubectl delete pvc -n monitoring -l app.kubernetes.io/name=mimir
```

## Troubleshooting

### Check Mimir Status

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=mimir

# Logs
kubectl logs -n monitoring -l app.kubernetes.io/name=mimir -f

# Ready check
kubectl exec -n monitoring mimir-0 -- wget -qO- http://localhost:8080/ready
```

### Common Issues

1. **OOMKilled**: Increase memory limits
2. **Slow queries**: Check `maxQueryLength` limits
3. **Ingestion failures**: Check `ingestionRate` limits
4. **Storage errors**: Verify S3 credentials and bucket permissions

## Related Charts

- [prometheus](../prometheus) - Metrics collection
- [grafana](../grafana) - Visualization
- [alertmanager](../alertmanager) - Alert routing

## Resources

- [Grafana Mimir Documentation](https://grafana.com/docs/mimir/latest/)
- [Mimir GitHub](https://github.com/grafana/mimir)
- [Remote Write API](https://grafana.com/docs/mimir/latest/references/http-api/#remote-write)
