# Thanos Helm Charts Guide

This guide covers the architecture, deployment patterns, and configuration of the 7 Thanos Helm charts in this repository.

## Overview

Thanos is a highly available Prometheus setup with long-term storage capabilities. It extends Prometheus with features like:

- **Long-term storage** via object storage (S3, GCS, Azure)
- **Global query view** across multiple Prometheus instances
- **Downsampling and compaction** for efficient storage
- **Multi-tenancy** support

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Thanos Architecture                             │
└─────────────────────────────────────────────────────────────────────────────┘

                         ┌─────────────────────┐
                         │  Query Frontend     │ ← Caching layer (optional)
                         │  (Deployment)       │
                         │  Port: 10913        │
                         └─────────┬───────────┘
                                   │
                         ┌─────────▼───────────┐
                         │  Query              │ ← Main query entry point
                         │  (Deployment)       │
                         │  HTTP: 10904        │
                         │  gRPC: 10903        │
                         └─────────┬───────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
  ┌─────────▼───────────┐ ┌───────▼─────────┐ ┌─────────▼───────────┐
  │  Store Gateway      │ │  Sidecar        │ │  Receive            │
  │  (StatefulSet)      │ │  (Deployment)   │ │  (StatefulSet)      │
  │  HTTP: 10906        │ │  HTTP: 10902    │ │  HTTP: 10909        │
  │  gRPC: 10905        │ │  gRPC: 10901    │ │  gRPC: 10907        │
  └─────────┬───────────┘ └───────┬─────────┘ │  RemoteWrite: 10908 │
            │                     │           └─────────┬───────────┘
            │                     │                     │
            ▼                     ▼                     ▼
  ┌───────────────────────────────────────────────────────────────┐
  │                     Object Storage (S3/GCS/Azure)              │
  └───────────────────────────────────────────────────────────────┘
            ▲                                           ▲
            │                                           │
  ┌─────────┴───────────┐                   ┌─────────┴───────────┐
  │  Compactor          │                   │  Ruler              │
  │  (StatefulSet)      │                   │  (StatefulSet)      │
  │  HTTP: 10912        │                   │  HTTP: 10911        │
  │  ⚠️  SINGLE REPLICA │                   │  gRPC: 10910        │
  └─────────────────────┘                   └─────────────────────┘
```

## Available Charts

| Chart | Type | Ports | Purpose |
|-------|------|-------|---------|
| **thanos-query** | Deployment | gRPC:10903, HTTP:10904 | Query aggregation from stores |
| **thanos-store** | StatefulSet | gRPC:10905, HTTP:10906 | Object storage gateway |
| **thanos-sidecar** | Deployment | gRPC:10901, HTTP:10902 | Prometheus sidecar |
| **thanos-receive** | StatefulSet | gRPC:10907, HTTP:10909, RW:10908 | Remote write ingestion |
| **thanos-compactor** | StatefulSet | HTTP:10912 | Compaction (single replica!) |
| **thanos-ruler** | StatefulSet | gRPC:10910, HTTP:10911 | Rule evaluation |
| **thanos-query-frontend** | Deployment | HTTP:10913 | Query caching |

## Deployment Patterns

### Pattern 1: Sidecar Mode

Use when you have existing Prometheus instances and want to add long-term storage.

```
┌──────────────────────────────────────────────────────────────┐
│  Prometheus Cluster (kube-prometheus-stack)                   │
│  ┌────────────────────────────────────────┐                  │
│  │ Prometheus Pod                          │                  │
│  │  ┌──────────────┐  ┌──────────────────┐│                  │
│  │  │ Prometheus   │  │ Thanos Sidecar   ││──┐               │
│  │  │              │──│ (built-in)       ││  │               │
│  │  └──────────────┘  └──────────────────┘│  │               │
│  └────────────────────────────────────────┘  │               │
└──────────────────────────────────────────────┼───────────────┘
                                               │
              ┌────────────────────────────────┼───────────────┐
              │ Thanos Components              │               │
              │                                ▼               │
              │  ┌────────────┐  ┌─────────────────────────┐   │
              │  │ Query      │  │ Object Storage          │   │
              │  │            │──│ (S3/GCS/Azure)          │   │
              │  └────────────┘  └─────────────────────────┘   │
              │        │                    ▲                  │
              │        │         ┌──────────┴────────┐         │
              │        └────────►│ Store Gateway     │         │
              │                  └───────────────────┘         │
              │                           ▲                    │
              │               ┌───────────┴─────────┐          │
              │               │ Compactor           │          │
              │               └─────────────────────┘          │
              └────────────────────────────────────────────────┘
```

**Required Charts:**
- kube-prometheus-stack (with Thanos sidecar enabled)
- thanos-query
- thanos-store
- thanos-compactor

**Optional:**
- thanos-ruler (for alerting)
- thanos-query-frontend (for caching)

**Configuration Example:**

```yaml
# kube-prometheus-stack values.yaml
prometheus:
  prometheusSpec:
    thanos:
      enabled: true
      image: quay.io/thanos/thanos:v0.34.0
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore
          key: objstore.yaml
```

### Pattern 2: Receive Mode

Use when you want to centralize metrics collection from multiple remote sources via remote write.

```
┌──────────────────────────────────────────────────────────────┐
│  Remote Prometheus Instances                                  │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                    │
│  │ Prom 1   │  │ Prom 2   │  │ Prom 3   │                    │
│  │ (Cluster │  │ (Cluster │  │ (Edge)   │                    │
│  │  A)      │  │  B)      │  │          │                    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                    │
│       │             │             │                           │
│       └─────────────┼─────────────┘                          │
│                     │ remote_write                            │
└─────────────────────┼────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│ Thanos Receive Cluster                                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ Receive (StatefulSet, 3 replicas)                     │       │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │       │
│  │  │ receive-0│  │ receive-1│  │ receive-2│            │       │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘            │       │
│  └───────┼──────────────┼──────────────┼────────────────┘       │
│          │              │              │                         │
│          └──────────────┼──────────────┘                        │
│                         ▼                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Object Storage (S3/GCS/Azure)                            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                         ▲                                        │
│            ┌────────────┴────────────┐                          │
│            │                         │                          │
│  ┌─────────┴───────┐      ┌─────────┴───────┐                   │
│  │ Store Gateway   │      │ Compactor       │                   │
│  └─────────────────┘      └─────────────────┘                   │
│            ▲                                                     │
│            │                                                     │
│  ┌─────────┴───────┐                                            │
│  │ Query           │                                            │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

**Required Charts:**
- thanos-receive
- thanos-query
- thanos-store
- thanos-compactor

**Remote Prometheus Configuration:**

```yaml
# prometheus.yml on remote Prometheus
remote_write:
  - url: http://thanos-receive.thanos.svc.cluster.local:10908/api/v1/receive
    headers:
      THANOS-TENANT: "cluster-a"  # Optional: for multi-tenancy
```

## Service Discovery

Thanos components discover each other using DNS-based service discovery (DNS-SD).

### DNS-SD Format

```
dnssrv+_grpc._tcp.<service>.<namespace>.svc.cluster.local
```

### Configuration Examples

**thanos-query discovering stores:**

```yaml
# thanos-query values.yaml
thanos:
  stores:
    # Discover Thanos Store Gateway
    - dnssrv+_grpc._tcp.thanos-store-headless.default.svc.cluster.local
    # Discover Thanos Sidecar (kube-prometheus-stack)
    - dnssrv+_grpc._tcp.prometheus-thanos-discovery.default.svc.cluster.local
    # Discover Thanos Receive
    - dnssrv+_grpc._tcp.thanos-receive-headless.default.svc.cluster.local
```

**thanos-ruler discovering query:**

```yaml
# thanos-ruler values.yaml
thanos:
  ruler:
    queryEndpoints:
      - dnssrv+_grpc._tcp.thanos-query.default.svc.cluster.local
```

## Object Storage Configuration

All charts use a unified object storage configuration pattern.

### Using Existing Secret (Recommended)

```yaml
objstore:
  existingSecret: "thanos-objstore-config"
  secretKeyName: "objstore.yaml"
```

**Create the secret:**

```yaml
# thanos-objstore-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-objstore-config
type: Opaque
stringData:
  objstore.yaml: |
    type: S3
    config:
      bucket: thanos-metrics
      endpoint: minio.minio.svc.cluster.local:9000
      access_key: minioadmin
      secret_key: minioadmin
      insecure: true
```

### Inline Configuration (Development)

```yaml
# S3 Configuration
objstore:
  type: "s3"
  s3:
    endpoint: "s3.amazonaws.com"
    bucket: "thanos-metrics"
    region: "us-east-1"
    accessKey: "AKIAIOSFODNN7EXAMPLE"
    secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    insecure: false

# GCS Configuration
objstore:
  type: "gcs"
  gcs:
    bucket: "thanos-metrics"
    serviceAccountKey: |
      {
        "type": "service_account",
        ...
      }

# Azure Configuration
objstore:
  type: "azure"
  azure:
    storageAccountName: "thanosmetrics"
    storageAccountKey: "..."
    containerName: "thanos"
```

## Multi-Tenancy

Thanos Receive supports multi-tenancy via HTTP headers.

```yaml
# thanos-receive values.yaml
thanos:
  tenancy:
    enabled: true
    header: "THANOS-TENANT"
    defaultTenant: "default-tenant"
```

**Sending metrics with tenant ID:**

```yaml
# Remote Prometheus configuration
remote_write:
  - url: http://thanos-receive:10908/api/v1/receive
    headers:
      THANOS-TENANT: "team-a"
```

## Component Deep Dive

### Thanos Query

The query component is the main entry point for PromQL queries. It aggregates data from multiple stores.

**Key configurations:**

```yaml
thanos:
  stores:
    - dnssrv+_grpc._tcp.thanos-store-headless.default.svc.cluster.local
  query:
    replicaLabels:
      - replica
      - prometheus_replica
    timeout: "2m"
    maxConcurrent: 20
    autoDownsampling: true
```

**Replica labels** are used to deduplicate data from HA Prometheus pairs.

### Thanos Store Gateway

The Store Gateway provides access to historical data in object storage.

**Key configurations:**

```yaml
thanos:
  store:
    indexCache:
      type: "in-memory"
      size: "250MB"
    chunkPoolSize: "2GB"
    syncBlockDuration: "3m"

persistence:
  enabled: true
  size: 10Gi  # For index cache
```

### Thanos Compactor

**CRITICAL: Must run as a single replica!**

The Compactor performs compaction and downsampling of historical data.

```yaml
# MUST be 1 - concurrent compactors will corrupt data!
replicaCount: 1

thanos:
  compactor:
    retention:
      raw: "30d"
      fiveMinutes: "90d"
      oneHour: "1y"
    downsampling:
      enabled: true
    consistencyDelay: "30m"

persistence:
  enabled: true
  size: 100Gi  # Compaction needs significant disk space
```

### Thanos Receive

Receives metrics via remote write protocol.

```yaml
replicaCount: 3  # For high availability

thanos:
  receive:
    replicationFactor: 1
    tsdbRetention: "2h"
    hashringSyncInterval: "5m"

persistence:
  enabled: true
  size: 50Gi
```

### Thanos Ruler

Evaluates recording and alerting rules against Thanos Query.

```yaml
thanos:
  ruler:
    queryEndpoints:
      - dnssrv+_grpc._tcp.thanos-query.default.svc.cluster.local
    alertmanagers:
      - http://alertmanager:9093
    evaluationInterval: "30s"

# Define rules
rules:
  recording-rules.yaml: |
    groups:
      - name: example
        rules:
          - record: job:http_requests:rate5m
            expr: sum(rate(http_requests_total[5m])) by (job)
```

### Thanos Query Frontend

Caching layer for queries.

```yaml
thanos:
  queryFrontend:
    downstreamUrl: "http://thanos-query:10904"
    splitInterval: "24h"
    maxRetries: 5
    cache:
      enabled: true
      type: "in-memory"
      inMemory:
        maxSize: "250MB"
        maxItems: 2048
```

## Production Recommendations

### High Availability

| Component | Recommended Replicas | Notes |
|-----------|---------------------|-------|
| Query | 2-3 | Stateless, can scale horizontally |
| Query Frontend | 2-3 | Stateless, improves query performance |
| Store Gateway | 2-3 | Can shard by time ranges |
| Receive | 3+ | Use with replication factor |
| Compactor | **1 only** | NEVER run multiple replicas |
| Ruler | 2-3 | For HA alerting |
| Sidecar | 1 per Prometheus | Deployed with Prometheus |

### Resource Recommendations

```yaml
# thanos-query
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# thanos-store
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 8Gi

# thanos-compactor
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 8Gi
```

### Monitoring

All charts include ServiceMonitor for Prometheus scraping:

```yaml
serviceMonitor:
  enabled: true
  namespace: "monitoring"
  interval: "30s"
  labels:
    release: prometheus
```

## Troubleshooting

### Common Issues

**1. Query returns no data**
- Check if stores are connected: `curl http://thanos-query:10904/api/v1/stores`
- Verify DNS-SD endpoints resolve correctly
- Check store gateway has synced blocks

**2. Compactor crashes**
- Ensure only ONE compactor is running
- Check disk space (compaction needs significant space)
- Review consistency delay settings

**3. Sidecar not uploading**
- Verify object storage credentials
- Check Prometheus data directory access
- Ensure minimum block duration matches Prometheus retention

**4. High memory usage in Store Gateway**
- Reduce index cache size
- Lower chunk pool size
- Consider sharding stores by time

### Useful Commands

```bash
# Check connected stores
make -f make/ops/thanos-query.mk tq-stores

# View compactor status
make -f make/ops/thanos-compactor.mk tc-status

# Check ruler alerts
make -f make/ops/thanos-ruler.mk tru-alerts

# View store info
make -f make/ops/thanos-store.mk ts-info
```

## Related Documentation

- [Official Thanos Documentation](https://thanos.io/tip/thanos/getting-started.md/)
- [Thanos GitHub Repository](https://github.com/thanos-io/thanos)
- [Observability Stack Guide](observability-stack-guide.md)
- [Production Checklist](PRODUCTION_CHECKLIST.md)

---

**Last Updated:** 2025-12-28
