# Thanos Query Helm Chart

Thanos Query provides a global query view across multiple Prometheus instances or other Thanos Store API endpoints with PromQL compatibility and deduplication.

## Overview

Thanos Query implements the Prometheus HTTP v1 API and can query data from any component implementing the Store API:
- Thanos Sidecar (Prometheus sidecar)
- Thanos Store (object storage gateway)
- Thanos Receive (remote write receiver)
- Thanos Ruler (rule evaluation results)
- Other Thanos Query instances (federation)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-query scripton-charts/thanos-query
```

## Configuration

### Store Endpoints

Configure Store API endpoints to query:

```yaml
thanos:
  stores:
    # DNS service discovery (recommended)
    - dnssrv+_grpc._tcp.thanos-sidecar.default.svc.cluster.local
    - dnssrv+_grpc._tcp.thanos-store.default.svc.cluster.local
    # Static endpoints
    - thanos-receive:10901
```

### Deduplication

Configure replica labels for deduplication:

```yaml
thanos:
  query:
    replicaLabels:
      - replica
      - prometheus_replica
```

### Query Settings

```yaml
thanos:
  query:
    timeout: "2m"
    maxConcurrent: 20
    partialResponse: "warn"  # warn, abort
    autoDownsampling: true
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Query replicas | `1` |
| `image.repository` | Image repository | `quay.io/thanos/thanos` |
| `image.tag` | Image tag | `""` (uses appVersion) |
| `thanos.stores` | Store API endpoints | `[]` |
| `thanos.query.replicaLabels` | Labels for deduplication | `[replica, prometheus_replica]` |
| `thanos.query.timeout` | Query timeout | `2m` |
| `thanos.query.maxConcurrent` | Max concurrent queries | `20` |
| `service.httpPort` | HTTP service port | `10904` |
| `service.grpcPort` | gRPC service port | `10903` |
| `ingress.enabled` | Enable ingress | `false` |
| `autoscaling.enabled` | Enable HPA | `false` |

## Grafana Integration

Add Thanos Query as a Prometheus data source in Grafana:

```yaml
apiVersion: 1
datasources:
  - name: Thanos
    type: prometheus
    url: http://thanos-query:10904
    access: proxy
```

## High Availability

For HA deployments:

```yaml
replicaCount: 3

podDisruptionBudget:
  enabled: true
  minAvailable: 2

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

## Troubleshooting

### Check connected stores

```bash
kubectl port-forward svc/thanos-query 10904:10904
curl http://localhost:10904/api/v1/stores
```

### Check query health

```bash
curl http://localhost:10904/-/ready
curl http://localhost:10904/-/healthy
```

## License

BSD-3-Clause
