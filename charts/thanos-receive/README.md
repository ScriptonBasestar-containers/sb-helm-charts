# Thanos Receive Helm Chart

This chart deploys [Thanos Receive](https://thanos.io/tip/components/receive.md/) on Kubernetes.

Thanos Receive accepts Prometheus remote write requests and stores data in object storage. It supports multi-tenancy and horizontal scaling via hashring.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+
- Object storage (S3, GCS, Azure Blob, etc.)

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-receive scripton-charts/thanos-receive
```

## Configuration

### Object Storage

Configure object storage in `values.yaml`:

```yaml
objstore:
  type: "s3"
  s3:
    endpoint: "minio.minio.svc.cluster.local:9000"
    bucket: "thanos"
    accessKey: "minio"
    secretKey: "minio123"
    insecure: true
```

Or use an existing secret:

```yaml
objstore:
  existingSecret: "thanos-objstore-secret"
```

### Multi-Tenancy

Enable multi-tenancy:

```yaml
thanos:
  tenancy:
    enabled: true
    header: "THANOS-TENANT"
    defaultTenant: "default-tenant"
```

### Hashring Configuration

The chart automatically generates hashring configuration based on `replicaCount`. Adjust replication factor:

```yaml
replicaCount: 3

thanos:
  receive:
    replicationFactor: 2
    tsdbRetention: "2h"
```

### Prometheus Remote Write

Configure Prometheus to send metrics:

```yaml
prometheus:
  remoteWrite:
    - url: http://thanos-receive.monitoring.svc.cluster.local:10908/api/v1/receive
```

For multi-tenant setups:

```yaml
prometheus:
  remoteWrite:
    - url: http://thanos-receive.monitoring.svc.cluster.local:10908/api/v1/receive
      headers:
        THANOS-TENANT: my-tenant-id
```

## Ports

| Port  | Protocol | Description                   |
|-------|----------|-------------------------------|
| 10901 | gRPC     | Store API for Thanos Query    |
| 10902 | HTTP     | Metrics and status endpoints  |
| 10908 | HTTP     | Remote write receiver         |

## Integration with Thanos Query

Add Receive to Thanos Query stores:

```yaml
thanos:
  stores:
    - dnssrv+_grpc._tcp.thanos-receive-headless.monitoring.svc.cluster.local
```

## Parameters

### Common Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Receive replicas | `3` |
| `image.repository` | Image repository | `quay.io/thanos/thanos` |
| `image.tag` | Image tag | `""` (uses appVersion) |

### Thanos Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `thanos.receive.replicationFactor` | Replication factor | `1` |
| `thanos.receive.tsdbRetention` | TSDB retention before upload | `"2h"` |
| `thanos.tenancy.enabled` | Enable multi-tenancy | `false` |
| `thanos.tenancy.header` | Tenant header name | `"THANOS-TENANT"` |
| `thanos.labels` | Labels to add to metrics | `{}` |

### Service Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.httpPort` | HTTP port | `10909` |
| `service.grpcPort` | gRPC port | `10907` |
| `service.remoteWritePort` | Remote write port | `10908` |

### Persistence Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `50Gi` |
| `persistence.storageClass` | Storage class | `""` |

## License

BSD-3-Clause
