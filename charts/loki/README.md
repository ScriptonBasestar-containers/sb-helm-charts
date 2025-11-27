# Loki Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.6.1](https://img.shields.io/badge/AppVersion-3.6.1-informational?style=flat-square)

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

## Backup & Recovery Strategy

### Overview

Loki backup strategy varies by storage backend:

| Storage Type | Components | RTO | RPO | Complexity |
|-------------|------------|-----|-----|-----------|
| **Filesystem** | Config + PVC snapshot | < 1 hour | 1 hour | Medium |
| **S3** | Config + S3 versioning | < 10 minutes | 0 (continuous) | Low |

### Backup Components

1. **Configuration** - ConfigMap, Secrets (RTO: < 5 min, RPO: 0)
2. **Log Data** - Chunks (filesystem: hourly, S3: continuous)
3. **Index** - BoltDB/TSDB index files (hourly, rebuildable)
4. **PVC** - Full volume snapshot (weekly, filesystem mode only)

### Quick Backup Commands

```bash
# Full backup (config + data + index)
make -f make/ops/loki.mk loki-backup-all

# Configuration only
make -f make/ops/loki.mk loki-backup-config

# Data only (chunks + index)
make -f make/ops/loki.mk loki-backup-data

# PVC snapshot (filesystem mode)
make -f make/ops/loki.mk loki-backup-pvc-snapshot

# Verify backup
make -f make/ops/loki.mk loki-backup-verify BACKUP_FILE=/path/to/backup
```

### Quick Recovery Commands

```bash
# Full recovery
make -f make/ops/loki.mk loki-restore-all BACKUP_FILE=/path/to/backup

# Configuration only
make -f make/ops/loki.mk loki-restore-config BACKUP_FILE=/path/to/config

# Data only
make -f make/ops/loki.mk loki-restore-data BACKUP_FILE=/path/to/data
```

### Backup Automation

```yaml
# CronJob for hourly backups
apiVersion: batch/v1
kind: CronJob
metadata:
  name: loki-backup
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              kubectl exec -n monitoring loki-0 -- \
                wget -qO- -X POST http://localhost:3100/flush
              # Backup chunks and index
              kubectl exec -n monitoring loki-0 -- \
                tar czf - /loki | aws s3 cp - s3://backups/loki-$(date +%Y%m%d).tar.gz
```

**Detailed documentation:** [Loki Backup Guide](../../docs/loki-backup-guide.md)

---

## Upgrading

### Upgrade Strategies

| Strategy | Downtime | Complexity | Recommended For |
|---------|----------|-----------|----------------|
| **Rolling Upgrade** | None (HA) | Low | Production |
| **Blue-Green** | 10-30 min | Medium | Large deployments |
| **Maintenance Window** | 15-30 min | Low | Dev/test |

### Pre-Upgrade Checklist

```bash
# 1. Run pre-upgrade validation
make -f make/ops/loki.mk loki-pre-upgrade-check

# 2. Create backup
make -f make/ops/loki.mk loki-backup-all

# 3. Review release notes
echo "Check: https://github.com/grafana/loki/releases"
```

### Rolling Upgrade (Zero Downtime)

**Prerequisites:** replicaCount ≥ 2, S3 storage recommended

```bash
# 1. Update Helm repository
helm repo update scripton-charts

# 2. Upgrade with new version
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.7.0 \
  --reuse-values \
  --wait \
  --timeout=10m

# 3. Verify upgrade
make -f make/ops/loki.mk loki-post-upgrade-check
```

### Maintenance Window Upgrade

```bash
# 1. Backup first
make -f make/ops/loki.mk loki-backup-all

# 2. Scale down
kubectl scale statefulset loki -n monitoring --replicas=0

# 3. Upgrade
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.7.0 \
  --reuse-values

# 4. Scale up
kubectl scale statefulset loki -n monitoring --replicas=1

# 5. Verify
make -f make/ops/loki.mk loki-ready
```

### Version-Specific Notes

#### Loki 2.x → 3.0 (Breaking Changes)

**Schema changes:**
```yaml
# Update schema_config in values.yaml
loki:
  config:
    schema_config:
      configs:
        - from: 2020-10-24
          store: tsdb        # Changed from boltdb-shipper
          schema: v12        # Changed from v11
          object_store: filesystem
```

**Configuration updates:**
- `storage_config.boltdb_shipper` → `storage_config.tsdb_shipper`
- Index format changed from BoltDB to TSDB
- Query frontend configuration simplified

#### Loki 3.0 → 3.6 (Minor Changes)

- No breaking changes
- Improved query performance
- Enhanced TSDB support
- Optional: Enable structured metadata

#### Loki 3.6 → 3.7 (Patch Updates)

- Straightforward rolling upgrade
- New features: log volume endpoint
- Bug fixes and stability improvements

### Post-Upgrade Validation

```bash
# Automated validation (8 checks)
make -f make/ops/loki.mk loki-post-upgrade-check

# Manual verification
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl exec -n monitoring loki-0 -- /usr/bin/loki --version
make -f make/ops/loki.mk loki-query QUERY='{job="loki"}' TIME=5m
```

### Rollback

```bash
# Method 1: Helm rollback
make -f make/ops/loki.mk loki-upgrade-rollback

# Method 2: Restore from backup
make -f make/ops/loki.mk loki-restore-all BACKUP_FILE=/path/to/backup

# Method 3: Revert image tag
helm upgrade loki scripton-charts/loki \
  --set image.tag=3.6.1 \
  --reuse-values
```

**Detailed documentation:** [Loki Upgrade Guide](../../docs/loki-upgrade-guide.md)

---

## Security & RBAC

### ServiceAccount Permissions

Loki ServiceAccount has minimal permissions:
- Read ConfigMaps (configuration)
- Read Secrets (S3 credentials)

### RBAC Configuration

```yaml
rbac:
  create: true
  annotations: {}
```

### Security Best Practices

1. **Enable authentication:**
   ```yaml
   loki:
     auth:
       enabled: true
   ```

2. **Use S3 encryption:**
   ```yaml
   loki:
     storage:
       s3:
         sse_enabled: true
   ```

3. **Restrict network access:**
   ```yaml
   # NetworkPolicy example
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: loki-network-policy
   spec:
     podSelector:
       matchLabels:
         app.kubernetes.io/name: loki
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: promtail  # Only allow Promtail
       ports:
       - protocol: TCP
         port: 3100
   ```

---

## Operations & Maintenance

### Health Monitoring

```bash
# Comprehensive health check
make -f make/ops/loki.mk loki-health-check

# Check readiness
make -f make/ops/loki.mk loki-ready

# View metrics
make -f make/ops/loki.mk loki-metrics
```

### Performance Tuning

**For high-volume environments:**

```yaml
loki:
  limits:
    ingestionRateMB: 8
    ingestionBurstSizeMB: 12
    max_query_parallelism: 32

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 2Gi
```

**For query-heavy workloads:**

```yaml
loki:
  config:
    query_range:
      results_cache:
        cache:
          enable_fifocache: true
          fifocache:
            max_size_bytes: 1GB
```

### Storage Management

**Check storage usage:**
```bash
make -f make/ops/loki.mk loki-check-storage
```

**Configure retention (reduce storage):**
```yaml
loki:
  limits:
    retention_period: 168h  # 7 days
```

**S3 lifecycle policy:**
```bash
# Move old data to Glacier after 30 days
aws s3api put-bucket-lifecycle-configuration \
  --bucket loki-chunks \
  --lifecycle-configuration file://lifecycle.json
```

### Scaling

**Vertical scaling:**
```yaml
resources:
  limits:
    memory: 4Gi  # Increase for more data
    cpu: 2000m
```

**Horizontal scaling:**
```bash
# Scale to 3 replicas
make -f make/ops/loki.mk loki-scale REPLICAS=3

# Enable replication
loki:
  replicationFactor: 3
```

---

## Monitoring & Diagnostics

### Metrics

Loki exposes Prometheus metrics on port 3100:

```bash
# Get all metrics
make -f make/ops/loki.mk loki-metrics

# Key metrics to monitor:
# - loki_ingester_chunks_stored_total
# - loki_ingester_memory_chunks
# - loki_distributor_ingester_append_failures_total
# - loki_query_frontend_requests_total
```

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: loki
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: loki
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### Grafana Dashboards

1. **Loki Overview:** https://grafana.com/grafana/dashboards/13407
2. **Loki Chunks:** https://grafana.com/grafana/dashboards/14055
3. **Loki Operational:** https://grafana.com/grafana/dashboards/12611

### Log Analysis

```bash
# Query logs
make -f make/ops/loki.mk loki-query \
  QUERY='{namespace="production"}' \
  TIME=1h

# Get all labels
make -f make/ops/loki.mk loki-labels

# Get label values
make -f make/ops/loki.mk loki-label-values LABEL=namespace

# Real-time tail (requires logcli)
make -f make/ops/loki.mk loki-tail QUERY='{job="app"}'
```

---

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

### Common Issues

**Issue: Queries return no results**
```bash
# Check if data is being ingested
make -f make/ops/loki.mk loki-labels

# Check index
kubectl exec -n monitoring loki-0 -- ls -lh /loki/index/

# Verify Promtail is sending logs
kubectl logs -n monitoring promtail-0
```

**Issue: High memory usage**
```bash
# Check memory usage
kubectl top pod -n monitoring loki-0

# Reduce query limits
helm upgrade loki scripton-charts/loki \
  --set loki.limits.max_query_series=500 \
  --reuse-values
```

**Issue: S3 connection failures**
```bash
# Verify S3 credentials
kubectl get secret loki-s3-credentials -n monitoring -o yaml

# Test S3 connectivity
kubectl exec -n monitoring loki-0 -- \
  aws s3 ls s3://loki-chunks/
```

---

## License

- Chart: BSD 3-Clause License
- Loki: Apache License 2.0

## Additional Resources

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/logql/)
- [Promtail Documentation](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Loki Backup Guide](../../docs/loki-backup-guide.md)
- [Loki Upgrade Guide](../../docs/loki-upgrade-guide.md)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**Loki Version**: 3.6.1
