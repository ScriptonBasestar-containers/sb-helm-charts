# Thanos Sidecar Helm Chart

Thanos Sidecar runs alongside Prometheus to upload TSDB blocks to object storage and expose Store API for real-time metric queries.

## Overview

The Sidecar component:
1. Uploads Prometheus TSDB blocks to object storage for long-term retention
2. Exposes Store API for Thanos Query to access recent metrics
3. Optionally watches for config changes and triggers Prometheus reload

## Deployment Modes

### Standalone Deployment (This Chart)
Deploys Sidecar as a separate Deployment connecting to Prometheus via HTTP.

### Sidecar Container Mode
Add Thanos Sidecar as a container in your Prometheus pod spec (recommended for production).

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+
- Prometheus instance with accessible TSDB
- Object storage (optional, for block upload)

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-sidecar scripton-charts/thanos-sidecar \
  --set prometheus.url=http://prometheus:9090 \
  --set prometheusDataVolume.existingClaim=prometheus-data
```

## Configuration

### Prometheus Connection

```yaml
prometheus:
  url: "http://prometheus:9090"
  readyTimeout: "10m"

thanos:
  tsdb:
    path: "/prometheus"
```

### Object Storage (for block upload)

```yaml
objstore:
  enabled: true
  type: "s3"
  s3:
    endpoint: "minio:9000"
    bucket: "thanos"
    accessKey: "admin"
    secretKey: "password"
    insecure: true
```

### Config Reloader

```yaml
thanos:
  reloader:
    enabled: true
    configFile: "/etc/prometheus/prometheus.yml"
    ruleDir: "/etc/prometheus/rules"
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `prometheus.url` | Prometheus URL | `http://prometheus:9090` |
| `thanos.tsdb.path` | TSDB data path | `/prometheus` |
| `objstore.enabled` | Enable object storage | `true` |
| `objstore.type` | Storage type | `s3` |
| `prometheusDataVolume.existingClaim` | Prometheus PVC name | `""` |
| `service.grpcPort` | gRPC port | `10901` |
| `service.httpPort` | HTTP port | `10902` |

## Sidecar Container Example

For Prometheus Helm chart, add:

```yaml
prometheus:
  prometheusSpec:
    containers:
      - name: thanos-sidecar
        image: quay.io/thanos/thanos:v0.37.2
        args:
          - sidecar
          - --prometheus.url=http://localhost:9090
          - --tsdb.path=/prometheus
          - --objstore.config-file=/etc/thanos/objstore.yaml
        ports:
          - name: grpc
            containerPort: 10901
          - name: http
            containerPort: 10902
        volumeMounts:
          - name: prometheus-db
            mountPath: /prometheus
          - name: thanos-objstore
            mountPath: /etc/thanos
```

## License

BSD-3-Clause
