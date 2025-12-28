# Thanos Store Gateway Helm Chart

Thanos Store Gateway serves historical metrics from object storage (S3, GCS, Azure) via the Store API, enabling Thanos Query to access long-term metric data.

## Overview

The Store Gateway reads TSDB blocks from object storage and makes them available for querying through the Thanos Store API. It maintains an index cache for efficient queries.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+
- Object storage (S3, GCS, Azure, or MinIO)

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-store scripton-charts/thanos-store \
  --set objstore.s3.endpoint=minio:9000 \
  --set objstore.s3.bucket=thanos \
  --set objstore.s3.accessKey=admin \
  --set objstore.s3.secretKey=password
```

## Configuration

### Object Storage (Required)

#### S3/MinIO

```yaml
objstore:
  type: "s3"
  s3:
    endpoint: "minio:9000"
    bucket: "thanos"
    region: "us-east-1"
    accessKey: "admin"
    secretKey: "password"
    insecure: true  # For MinIO without TLS
```

#### GCS

```yaml
objstore:
  type: "gcs"
  gcs:
    bucket: "thanos-bucket"
    serviceAccountKey: "<base64-encoded-key>"
```

#### Azure

```yaml
objstore:
  type: "azure"
  azure:
    storageAccountName: "account"
    storageAccountKey: "key"
    containerName: "thanos"
```

### Index Cache

```yaml
thanos:
  indexCache:
    type: "in-memory"
    size: "500MB"
```

### Time Range Filtering

```yaml
thanos:
  store:
    minTime: "-30d"  # Only serve last 30 days
    maxTime: ""       # No upper limit
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Store replicas | `1` |
| `image.repository` | Image repository | `quay.io/thanos/thanos` |
| `objstore.type` | Storage type (s3/gcs/azure) | `s3` |
| `objstore.existingSecret` | Existing secret for objstore config | `""` |
| `thanos.indexCache.size` | Index cache size | `250MB` |
| `thanos.chunkPoolSize` | Chunk pool size | `2GB` |
| `persistence.enabled` | Enable PVC for cache | `true` |
| `persistence.size` | Cache PVC size | `10Gi` |
| `service.grpcPort` | gRPC service port | `10905` |
| `service.httpPort` | HTTP service port | `10906` |

## Integration with Thanos Query

Add Store Gateway to Thanos Query:

```yaml
# thanos-query values
thanos:
  stores:
    - dnssrv+_grpc._tcp.thanos-store-headless.monitoring.svc.cluster.local
```

## High Availability

For HA deployments with sharding:

```yaml
replicaCount: 3

thanos:
  store:
    # Use time-based sharding
    minTime: "-30d"

podDisruptionBudget:
  enabled: true
  minAvailable: 2
```

## Troubleshooting

### Check block synchronization

```bash
kubectl port-forward svc/thanos-store 10906:10906
curl http://localhost:10906/api/v1/blocks
```

### View object storage connectivity

```bash
kubectl logs -l app.kubernetes.io/name=thanos-store
```

## License

BSD-3-Clause
