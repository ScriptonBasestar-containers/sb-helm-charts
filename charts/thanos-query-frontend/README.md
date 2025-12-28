# Thanos Query Frontend

Thanos Query Frontend is a caching and query splitting layer that sits in front of Thanos Query. It improves query performance by caching responses and splitting large queries into smaller ones.

## Features

- **Query Caching**: In-memory or Memcached response caching
- **Query Splitting**: Splits long time range queries into smaller chunks
- **Query Retries**: Automatic retry of failed downstream queries
- **Slow Query Logging**: Identify problematic queries
- **Response Compression**: Reduce bandwidth usage
- **Horizontal Scaling**: Stateless design enables easy HPA

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2+
- Thanos Query running and accessible

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-query-frontend scripton-charts/thanos-query-frontend \
  --set thanos.queryFrontend.downstreamUrl=http://thanos-query:10904
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Query Frontend replicas | `1` |
| `thanos.queryFrontend.downstreamUrl` | Thanos Query URL | `http://thanos-query:10904` |
| `thanos.queryFrontend.splitInterval` | Query range splitting interval | `24h` |
| `thanos.queryFrontend.cache.enabled` | Enable response caching | `true` |
| `thanos.queryFrontend.cache.type` | Cache type (in-memory/memcached) | `in-memory` |
| `service.httpPort` | HTTP service port | `10913` |
| `ingress.enabled` | Enable ingress | `false` |
| `autoscaling.enabled` | Enable HPA | `false` |

### Cache Configuration

#### In-Memory Cache (Default)

```yaml
thanos:
  queryFrontend:
    cache:
      enabled: true
      type: "in-memory"
      inMemory:
        maxSize: "250MB"
        maxItems: 2048
```

#### Memcached Cache

```yaml
thanos:
  queryFrontend:
    cache:
      enabled: true
      type: "memcached"
      memcached:
        addresses:
          - memcached-0.memcached:11211
          - memcached-1.memcached:11211
        timeout: "500ms"
        maxIdleConnections: 100
```

### High Availability

```yaml
replicaCount: 3

podDisruptionBudget:
  enabled: true
  minAvailable: 2

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: thanos-query-frontend
```

## Architecture

```
                     +---------------------+
    Grafana -------->| Query Frontend (QF) |-----> Thanos Query
                     +---------------------+
                            |
                     +------+------+
                     |    Cache    |
                     | (in-memory/ |
                     |  memcached) |
                     +-------------+
```

Query Frontend provides:
1. **Caching Layer**: Caches query results to reduce load on Query
2. **Query Splitting**: Splits queries by time range (e.g., 24h chunks)
3. **Retry Logic**: Automatically retries failed queries

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 10902 | HTTP | Internal container port |
| 10913 | HTTP | Default service port |

## Metrics

Query Frontend exposes Prometheus metrics at `/metrics`:

- `thanos_query_frontend_queries_total` - Total queries processed
- `thanos_query_frontend_split_queries_total` - Queries that were split
- `thanos_query_frontend_cache_hits_total` - Cache hit count
- `thanos_query_frontend_cache_requests_total` - Total cache requests

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
  interval: "30s"
```

## Troubleshooting

### Query Frontend Not Connecting to Query

1. Verify downstream URL is correct:
   ```bash
   kubectl exec -it <pod> -- wget -qO- http://thanos-query:10904/-/ready
   ```

2. Check Query Frontend logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name=thanos-query-frontend
   ```

### Cache Not Working

1. Verify cache configuration in logs
2. Check cache metrics at `/metrics`
3. For memcached, ensure addresses are reachable

### High Latency

1. Increase `splitInterval` for fewer query splits
2. Scale up replicas with HPA
3. Consider using memcached for larger deployments

## Values Reference

See [values.yaml](values.yaml) for all configuration options.

## License

BSD-3-Clause
