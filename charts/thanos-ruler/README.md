# Thanos Ruler Helm Chart

Thanos Ruler evaluates Prometheus recording and alerting rules against Thanos Query, stores rule evaluation results in object storage, and sends alerts to Alertmanager.

## Overview

The Ruler component is responsible for:
- Evaluating recording rules to create new time series
- Evaluating alerting rules and sending alerts to Alertmanager
- Storing rule evaluation results in object storage for long-term access
- Exposing StoreAPI for Thanos Query to access rule results

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+
- Object storage (S3, GCS, Azure, or MinIO)
- Thanos Query endpoint(s)
- Alertmanager (optional, for alerts)

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-ruler scripton-charts/thanos-ruler \
  --set objstore.s3.endpoint=minio:9000 \
  --set objstore.s3.bucket=thanos \
  --set objstore.s3.accessKey=admin \
  --set objstore.s3.secretKey=password \
  --set thanos.ruler.queryEndpoints[0]=thanos-query:10901
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

### Query Endpoints (Required)

```yaml
thanos:
  ruler:
    queryEndpoints:
      - dnssrv+_grpc._tcp.thanos-query.monitoring.svc.cluster.local
      # Or static endpoint:
      # - thanos-query:10901
```

### Alertmanager Configuration

```yaml
thanos:
  ruler:
    alertmanagers:
      - http://alertmanager:9093
```

### Rule Definitions

Define recording and alerting rules directly in values:

```yaml
rules:
  recording-rules.yaml: |
    groups:
      - name: cpu_rules
        rules:
          - record: job:cpu_usage:rate5m
            expr: sum(rate(process_cpu_seconds_total[5m])) by (job)

  alerting-rules.yaml: |
    groups:
      - name: alerts
        rules:
          - alert: HighMemoryUsage
            expr: process_resident_memory_bytes > 1e9
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "High memory usage detected"
```

### Rule Evaluation

```yaml
thanos:
  ruler:
    evaluationInterval: "30s"
    labels:
      ruler_cluster: "production"
    alertLabelDrop:
      - replica
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Ruler replicas | `1` |
| `image.repository` | Image repository | `quay.io/thanos/thanos` |
| `objstore.type` | Storage type (s3/gcs/azure) | `s3` |
| `objstore.existingSecret` | Existing secret for objstore config | `""` |
| `thanos.ruler.queryEndpoints` | Thanos Query endpoints | `["dnssrv+_grpc._tcp.thanos-query.default.svc.cluster.local"]` |
| `thanos.ruler.alertmanagers` | Alertmanager endpoints | `[]` |
| `thanos.ruler.evaluationInterval` | Rule evaluation interval | `30s` |
| `thanos.ruler.labels` | Labels to add to alerts | `{}` |
| `rules` | Rule file definitions | `{}` |
| `persistence.enabled` | Enable PVC for data | `true` |
| `persistence.size` | Data PVC size | `10Gi` |
| `service.grpcPort` | gRPC service port | `10910` |
| `service.httpPort` | HTTP service port | `10911` |

## Integration with Thanos Query

Ruler exposes StoreAPI, allowing Thanos Query to access rule evaluation results.
Add Ruler to Thanos Query stores:

```yaml
# thanos-query values
thanos:
  stores:
    - dnssrv+_grpc._tcp.thanos-ruler-headless.monitoring.svc.cluster.local
```

## High Availability

For HA deployments:

```yaml
replicaCount: 2

thanos:
  ruler:
    labels:
      ruler_replica: "$(POD_NAME)"

podDisruptionBudget:
  enabled: true
  minAvailable: 1

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: thanos-ruler
          topologyKey: kubernetes.io/hostname
```

Note: When running multiple replicas, each replica evaluates rules independently.
Use unique labels (e.g., `ruler_replica`) to deduplicate alerts.

## API Endpoints

- `/-/healthy` - Health check
- `/-/ready` - Readiness check
- `/metrics` - Prometheus metrics
- `/api/v1/rules` - List configured rules
- `/api/v1/alerts` - List active alerts

## Troubleshooting

### Check rule evaluation status

```bash
kubectl port-forward svc/thanos-ruler 10911:10911
curl http://localhost:10911/api/v1/rules
```

### View alerts

```bash
curl http://localhost:10911/api/v1/alerts
```

### Check connectivity to Query

```bash
kubectl logs -l app.kubernetes.io/name=thanos-ruler | grep -i query
```

### Verify Alertmanager connectivity

```bash
kubectl logs -l app.kubernetes.io/name=thanos-ruler | grep -i alertmanager
```

## License

BSD-3-Clause
