# Thanos Compactor

Thanos Compactor - compacts, downsamples, and manages retention of TSDB blocks in object storage.

## Critical Warning

**Thanos Compactor MUST run as a single replica!** Running multiple compactors concurrently against the same object storage bucket will corrupt your data. This chart enforces `replicaCount: 1` regardless of configuration.

## Features

- Block compaction (merges small TSDB blocks into larger ones)
- Downsampling (creates 5-minute and 1-hour resolution data)
- Retention enforcement (deletes old data based on policies)
- Prometheus metrics for monitoring compaction status

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Object storage (S3, GCS, Azure Blob, or compatible)
- Thanos Sidecar or Thanos Receive writing blocks to object storage

## Installation

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install thanos-compactor scripton-charts/thanos-compactor -f values.yaml
```

## Configuration

### Object Storage

Configure object storage credentials. The compactor needs read/write access to the same bucket used by Thanos Sidecar or Receive.

#### S3 / MinIO

```yaml
objstore:
  type: "s3"
  s3:
    endpoint: "minio.storage.svc:9000"
    bucket: "thanos"
    accessKey: "minioadmin"
    secretKey: "minioadmin"
    insecure: true
```

#### Using Existing Secret

```yaml
objstore:
  existingSecret: "thanos-objstore-config"
  secretKeyName: "objstore.yaml"
```

### Retention Configuration

Configure how long to keep data at each resolution:

```yaml
thanos:
  compactor:
    retention:
      raw: "30d"         # Keep raw resolution for 30 days
      fiveMinutes: "90d" # Keep 5-minute samples for 90 days
      oneHour: "1y"      # Keep 1-hour samples for 1 year
```

### Downsampling

Downsampling creates lower resolution data for efficient long-term queries:

```yaml
thanos:
  compactor:
    downsampling:
      enabled: true  # Enable 5-minute and 1-hour downsampling
```

### Storage Requirements

The compactor needs significant disk space for temporary compaction work:

```yaml
persistence:
  enabled: true
  size: 100Gi  # Recommended: 2-3x size of largest block group
```

## Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (MUST be 1) | `1` |
| `thanos.compactor.retention.raw` | Raw resolution retention | `30d` |
| `thanos.compactor.retention.fiveMinutes` | 5-minute resolution retention | `90d` |
| `thanos.compactor.retention.oneHour` | 1-hour resolution retention | `1y` |
| `thanos.compactor.downsampling.enabled` | Enable downsampling | `true` |
| `thanos.compactor.compactionConcurrency` | Parallel compaction goroutines | `1` |
| `thanos.compactor.consistencyDelay` | Delay before processing new blocks | `30m` |
| `thanos.compactor.waitInterval` | Wait time between compaction cycles | `5m` |
| `persistence.size` | PVC size for compaction work | `100Gi` |
| `service.httpPort` | HTTP port for metrics | `10912` |

## Monitoring

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
  interval: "30s"
```

### Key Metrics

- `thanos_compact_group_compactions_total` - Total compactions
- `thanos_compact_group_compactions_failures_total` - Failed compactions
- `thanos_compact_downsample_total` - Downsampling operations
- `thanos_compact_garbage_collection_total` - GC operations
- `thanos_compact_halted` - 1 if compactor is halted due to error

## Troubleshooting

### Compactor Not Processing Blocks

1. Check object storage connectivity
2. Verify consistency delay hasn't been reached
3. Check for overlapping blocks (may require manual intervention)

### High Memory Usage

1. Reduce `compactionConcurrency`
2. Ensure adequate `resources.limits.memory`
3. Consider increasing PVC size for better I/O

### Halted Compactor

If `thanos_compact_halted` is 1:
1. Check logs for error details
2. May require manual block manipulation
3. Restart after resolving the issue

## License

BSD-3-Clause

## Links

- [Thanos Documentation](https://thanos.io/tip/components/compact.md/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)
