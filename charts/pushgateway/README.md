# Prometheus Pushgateway Helm Chart

Prometheus Pushgateway allows ephemeral and batch jobs to expose their metrics to Prometheus. This chart provides a production-ready deployment with persistence support and security best practices.

## Features

- **Push-based Metrics Collection**: Accept metrics from batch jobs, cron jobs, and short-lived processes
- **Metric Persistence**: Optional file-based persistence for metrics across restarts
- **High Availability**: Multi-replica support with anti-affinity
- **Security**: Non-root user, network policies, read-only filesystem
- **Prometheus Integration**: ServiceMonitor support for Prometheus Operator

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Prometheus for scraping metrics
- PV provisioner support (for persistence, optional)

## Installation

### Quick Start

\`\`\`bash
helm install pushgateway charts/pushgateway --namespace monitoring --create-namespace
\`\`\`

### Production Installation

\`\`\`bash
helm install pushgateway charts/pushgateway \\
  --namespace monitoring \\
  --values charts/pushgateway/values-small-prod.yaml
\`\`\`

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| \`replicaCount\` | Number of replicas | \`1\` |
| \`image.repository\` | Pushgateway image | \`prom/pushgateway\` |
| \`image.tag\` | Image tag | \`v1.6.2\` |

### Persistence

\`\`\`yaml
pushgateway:
  persistence:
    enabled: true
    file: "/data/metrics.db"

persistence:
  enabled: true
  size: 2Gi
  storageClass: "standard"
\`\`\`

### ServiceMonitor

\`\`\`yaml
serviceMonitor:
  enabled: true
  interval: 15s
  scrapeTimeout: 10s
\`\`\`

## Usage

### Pushing Metrics

**Using curl:**
\`\`\`bash
echo "some_metric 3.14" | curl --data-binary @- http://pushgateway.monitoring.svc.cluster.local:9091/metrics/job/batch_job
\`\`\`

**Using Python:**
\`\`\`python
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

registry = CollectorRegistry()
g = Gauge('job_last_success_unixtime', 'Last time a batch job successfully finished', registry=registry)
g.set_to_current_time()
push_to_gateway('pushgateway.monitoring.svc.cluster.local:9091', job='batch_job', registry=registry)
\`\`\`

### Deleting Metrics

\`\`\`bash
# Delete all metrics for a job
curl -X DELETE http://pushgateway.monitoring.svc.cluster.local:9091/metrics/job/batch_job

# Delete metrics for job with instance label
curl -X DELETE http://pushgateway.monitoring.svc.cluster.local:9091/metrics/job/batch_job/instance/worker01
\`\`\`

### Configure Prometheus Scraping

\`\`\`yaml
scrape_configs:
  - job_name: 'pushgateway'
    honor_labels: true  # Important!
    static_configs:
      - targets: ['pushgateway.monitoring.svc.cluster.local:9091']
\`\`\`

## Operational Commands

\`\`\`bash
# Port forward
make -f make/ops/pushgateway.mk pushgateway-port-forward

# View all metrics
make -f make/ops/pushgateway.mk pushgateway-metrics

# Delete metrics group
make -f make/ops/pushgateway.mk pushgateway-delete-group JOB=batch_job

# Check health
make -f make/ops/pushgateway.mk pushgateway-health

# View logs
make -f make/ops/pushgateway.mk pushgateway-logs

# Restart
make -f make/ops/pushgateway.mk pushgateway-restart
\`\`\`

## Best Practices

1. **Use \`honor_labels: true\` in Prometheus**
   - Prevents Pushgateway from overwriting job/instance labels

2. **Clean Up Stale Metrics**
   - Delete metrics after job completion
   - Set up automatic cleanup jobs

3. **Use Descriptive Job Names**
   - Include timestamp or unique identifier
   - Example: \`backup_job_20231201\`

4. **Security**
   - Enable NetworkPolicy
   - Use authentication proxy (OAuth2 Proxy, etc.)
   - Never expose to public internet

5. **Monitoring**
   - Alert on \`push_time_seconds\` staleness
   - Monitor \`pushgateway_build_info\`

## Troubleshooting

### Metrics Not Appearing in Prometheus

1. Check Prometheus scrape config has \`honor_labels: true\`
2. Verify ServiceMonitor or static config is correct
3. Check Pushgateway logs

### High Memory Usage

- Increase resources or enable persistence to disk
- Clean up old metrics regularly

## Values Profiles

### Development (values-dev.yaml)
- 1 replica
- Debug logging
- No persistence
- Minimal resources

### Small Production (values-small-prod.yaml)
- 2 replicas for HA
- File-based persistence
- PodDisruptionBudget
- ServiceMonitor enabled
- Network policies

## License

BSD-3-Clause

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Pushgateway**: https://github.com/prometheus/pushgateway
- **Documentation**: https://prometheus.io/docs/practices/pushing/
