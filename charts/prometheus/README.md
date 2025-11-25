# Prometheus Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.7.3](https://img.shields.io/badge/AppVersion-3.7.3-informational?style=flat-square)

Prometheus monitoring system and time series database for Kubernetes

## Features

- **Kubernetes Service Discovery**: Automatic scraping of pods, services, nodes, and API server
- **Flexible Storage**: Persistent TSDB with configurable retention (time and size)
- **RBAC Support**: ClusterRole for Kubernetes API access
- **Annotation-Based Scraping**: `prometheus.io/scrape` annotation support
- **High Availability**: StatefulSet with headless service
- **Configuration Reload**: Web lifecycle endpoint for hot reload
- **Admin API**: Optional admin API for snapshots and maintenance
- **Operational Tools**: 30+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration
helm install my-prometheus scripton-charts/prometheus

# Install with custom retention
helm install my-prometheus scripton-charts/prometheus \
  --set prometheus.retention.time=30d \
  --set prometheus.retention.size=45GB \
  --set persistence.size=100Gi
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner (for persistence)

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Prometheus replicas | `1` |
| `prometheus.global.scrapeInterval` | Scrape interval | `15s` |
| `prometheus.retention.time` | Data retention time | `15d` |
| `prometheus.retention.size` | Data retention size | `0` (disabled) |
| `prometheus.kubernetesSD.enabled` | Enable Kubernetes SD | `true` |
| `prometheus.enableAdminAPI` | Enable admin API | `false` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `50Gi` |
| `rbac.create` | Create RBAC resources | `true` |

## Operational Commands

```bash
# View logs
make -f make/ops/prometheus.mk prom-logs

# Port forward
make -f make/ops/prometheus.mk prom-port-forward

# Check health
make -f make/ops/prometheus.mk prom-ready
make -f make/ops/prometheus.mk prom-healthy

# View configuration
make -f make/ops/prometheus.mk prom-config

# Validate configuration
make -f make/ops/prometheus.mk prom-config-check

# List targets
make -f make/ops/prometheus.mk prom-targets

# Execute PromQL query
make -f make/ops/prometheus.mk prom-query QUERY='up'

# Get TSDB status
make -f make/ops/prometheus.mk prom-tsdb-status

# Reload configuration
make -f make/ops/prometheus.mk prom-reload

# Show active alerts
make -f make/ops/prometheus.mk prom-alerts

# Scale replicas
make -f make/ops/prometheus.mk prom-scale REPLICAS=2
```

## Production Setup

```yaml
# values-prod.yaml
replicaCount: 2

prometheus:
  global:
    scrapeInterval: "15s"
    externalLabels:
      cluster: "production"
      environment: "prod"

  retention:
    time: "30d"
    size: "45GB"

  alerting:
    enabled: true
    alertmanagers:
      - alertmanager.monitoring.svc.cluster.local:9093

  ruleFiles:
    - /etc/prometheus/rules/*.yml

resources:
  limits:
    cpu: 4000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 2Gi

persistence:
  storageClass: "fast-ssd"
  size: 100Gi

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - prometheus
          topologyKey: kubernetes.io/hostname
```

## Grafana Integration

### Add Prometheus as Data Source

1. **Via UI:**
   - Navigate to Configuration → Data Sources
   - Click "Add data source"
   - Select "Prometheus"
   - URL: `http://prometheus.default.svc.cluster.local:9090`

2. **Via Makefile (if using Grafana chart):**
```bash
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus:9090
```

## Application Metrics Scraping

### Annotate Your Pods or Services

Prometheus will automatically discover and scrape metrics from pods and services with these annotations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    prometheus.io/scrape: "true"    # Enable scraping
    prometheus.io/port: "8080"      # Metrics port
    prometheus.io/path: "/metrics"  # Metrics endpoint (optional, default: /metrics)
spec:
  containers:
    - name: app
      ports:
        - containerPort: 8080
          name: metrics
```

### Service Annotation Example

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:
  ports:
    - port: 9090
      name: metrics
```

## PromQL Query Examples

### Basic Queries

```promql
# Check if targets are up
up

# CPU usage rate (5m average)
rate(container_cpu_usage_seconds_total[5m])

# Memory usage
container_memory_usage_bytes

# HTTP request rate
rate(http_requests_total[5m])

# HTTP error rate (5xx errors)
rate(http_requests_total{status=~"5.."}[5m])
```

### Aggregations

```promql
# Total requests per service
sum(rate(http_requests_total[5m])) by (service)

# Average response time
avg(http_request_duration_seconds) by (handler)

# 95th percentile latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Kubernetes Metrics

```promql
# Pods per namespace
count(kube_pod_info) by (namespace)

# Node CPU usage
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# Node memory usage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes
```

## Service Discovery

Prometheus is configured with Kubernetes service discovery for:

1. **Pods**: Scrapes pods with `prometheus.io/scrape: "true"` annotation
2. **Services**: Scrapes services with `prometheus.io/scrape: "true"` annotation
3. **Nodes**: Scrapes Kubernetes nodes metrics
4. **API Server**: Scrapes Kubernetes API server metrics

## Custom Scrape Configurations

Add custom scrape configs in `values.yaml`:

```yaml
prometheus:
  additionalScrapeConfigs:
    - job_name: 'my-app'
      static_configs:
        - targets: ['my-app:8080']
      metrics_path: /actuator/prometheus

    - job_name: 'external-service'
      static_configs:
        - targets: ['external.example.com:9100']
```

## Alert Rules

Create a ConfigMap with alert rules:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
data:
  alerts.yml: |
    groups:
      - name: example
        rules:
          - alert: HighErrorRate
            expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High error rate detected"
              description: "Error rate is {{ $value }} req/s"
```

Mount the rules in `values.yaml`:

```yaml
prometheus:
  ruleFiles:
    - /etc/prometheus/rules/*.yml
  extraVolumes:
    - name: rules
      configMap:
        name: prometheus-rules
  extraVolumeMounts:
    - name: rules
      mountPath: /etc/prometheus/rules
```

## Storage and Retention

### Time-Based Retention

```yaml
prometheus:
  retention:
    time: "30d"  # Keep data for 30 days
```

### Size-Based Retention

```yaml
prometheus:
  retention:
    time: "30d"
    size: "45GB"  # Delete old data when TSDB exceeds 45GB
```

### Storage Sizing

Estimate storage requirements:

```
Storage = Ingested samples/s × Retention time × 2 bytes per sample

Example:
- 100,000 samples/s
- 30 days retention
- Storage = 100,000 × 30 × 86400 × 2 = ~518 GB
```

Add 20-30% overhead for index and WAL.

## TSDB Snapshots

Create TSDB snapshots (requires `enableAdminAPI: true`):

```bash
# Create snapshot
make -f make/ops/prometheus.mk prom-tsdb-snapshot

# Snapshots are stored in /prometheus/snapshots/
```

## Configuration Reload

Reload Prometheus configuration without restart (requires `--web.enable-lifecycle` which is enabled by default):

```bash
# Reload configuration
make -f make/ops/prometheus.mk prom-reload
```

## Troubleshooting

### Check if Prometheus is Ready

```bash
make -f make/ops/prometheus.mk prom-ready
```

### Validate Configuration

```bash
make -f make/ops/prometheus.mk prom-config-check
```

### View Scrape Targets

```bash
make -f make/ops/prometheus.mk prom-targets
```

### Check TSDB Status

```bash
make -f make/ops/prometheus.mk prom-tsdb-status
```

### View Logs

```bash
make -f make/ops/prometheus.mk prom-logs
```

### Test Queries

```bash
make -f make/ops/prometheus.mk prom-test-query
```

## High Availability

For HA deployment, use multiple replicas with Thanos or Prometheus federation:

**Simple HA (2 replicas):**
```yaml
replicaCount: 2
```

**Note:** Simple replication results in duplicate data. For true HA with deduplication, consider:
- [Thanos](https://thanos.io/) - Long-term storage and global query view
- [Cortex](https://cortexmetrics.io/) - Horizontally scalable Prometheus
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) - Advanced Prometheus management

## Security Considerations

### Access Control

**Disable Admin API in Production:**
```yaml
prometheus:
  enableAdminAPI: false  # Prevents unauthorized deletions and snapshots
```

**Network Policy:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: grafana  # Allow only from Grafana
    ports:
    - protocol: TCP
      port: 9090
```

**RBAC Minimal Permissions:**
The chart creates RBAC with read-only cluster access. Review `ClusterRole` if deploying in security-sensitive environments.

### Ingress Security

**Basic Auth with Ingress:**
```yaml
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: prometheus-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
```

Create auth secret:
```bash
htpasswd -c auth admin
kubectl create secret generic prometheus-basic-auth --from-file=auth
```

**IP Whitelist:**
```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

### Data Security

- **PVC Encryption**: Use encrypted storage classes
- **Sensitive Labels**: Avoid scraping PII in metrics labels
- **Query Logging**: Consider enabling `--query.log-file` for audit trails

## Performance Tuning

### Memory Optimization

Prometheus memory usage scales with active time series and query complexity:

```yaml
# For ~500K active series
resources:
  limits:
    memory: 4Gi
  requests:
    memory: 2Gi

# For ~1M active series
resources:
  limits:
    memory: 8Gi
  requests:
    memory: 4Gi

# For ~5M active series
resources:
  limits:
    memory: 32Gi
  requests:
    memory: 16Gi
```

**Memory Formula:**
```
Memory ≈ (Active Series × 2KB) + (Ingested Samples/s × 5MB per 10k/s)
```

### Storage Optimization

**SSD Storage (Required for Production):**
```yaml
persistence:
  storageClass: "fast-ssd"
  size: 100Gi
```

**Size-Based Retention (Prevents Disk Full):**
```yaml
prometheus:
  retention:
    time: "30d"
    size: "90GB"  # Set to 90% of PVC size
```

**TSDB Block Duration:**
```yaml
prometheus:
  tsdb:
    minBlockDuration: "2h"  # Default
    maxBlockDuration: "24h"  # Reduces compaction overhead
```

### Scrape Performance

**Optimize Scrape Intervals:**
```yaml
prometheus:
  global:
    scrapeInterval: "30s"     # Reduce from 15s if not needed
    scrapeTimeout: "10s"
    evaluationInterval: "30s"
```

**Sample Limits:**
```yaml
prometheus:
  global:
    sampleLimit: 10000  # Per scrape target
```

**Relabeling for Cardinality Control:**
```yaml
prometheus:
  additionalScrapeConfigs:
    - job_name: 'app'
      metric_relabel_configs:
        - source_labels: [__name__]
          regex: 'go_.*'  # Drop verbose Go metrics
          action: drop
```

### Query Performance

**Recording Rules for Complex Queries:**
```yaml
groups:
  - name: performance
    interval: 1m
    rules:
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)
```

**Query Resource Limits:**
```yaml
prometheus:
  queryTimeout: "2m"
  queryConcurrency: 20
  queryMaxSamples: 50000000
```

### Benchmarks

| Active Series | Ingestion Rate | Memory | CPU | Storage (30d) |
|--------------|----------------|--------|-----|---------------|
| 100K | 10K/s | 2Gi | 500m | 50Gi |
| 500K | 50K/s | 4Gi | 1000m | 250Gi |
| 1M | 100K/s | 8Gi | 2000m | 500Gi |
| 5M | 500K/s | 32Gi | 8000m | 2.5Ti |

## License

- Chart: BSD 3-Clause License
- Prometheus: Apache License 2.0

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [PromQL Reference](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Recording Rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Prometheus Version**: 2.48.1
