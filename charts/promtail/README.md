# Promtail Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.9.3](https://img.shields.io/badge/AppVersion-2.9.3-informational?style=flat-square)

Promtail log collection agent for Loki with Kubernetes integration

## Features

- **DaemonSet Deployment**: Runs on all nodes including masters
- **Kubernetes Service Discovery**: Automatic log collection from all pods
- **Pod Metadata as Labels**: namespace, pod, container, node automatically added
- **CRI/Docker Support**: Parsers for containerd, cri-o, and Docker
- **Log Level Extraction**: Automatic extraction of debug, info, warn, error levels
- **RBAC Support**: ClusterRole for Kubernetes API access
- **Configurable Pipelines**: Custom pipeline stages for log processing
- **Prometheus Metrics**: Metrics endpoint for monitoring Promtail itself
- **Operational Tools**: 15+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration
helm install my-promtail scripton-charts/promtail

# Install with custom Loki URL
helm install my-promtail scripton-charts/promtail \
  --set promtail.client.url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Loki instance for log storage

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `promtail.client.url` | Loki push URL | `http://loki:3100/loki/api/v1/push` |
| `promtail.server.logLevel` | Log level | `info` |
| `promtail.kubernetesSD.addPodAnnotations` | Add pod annotations as labels | `false` |
| `promtail.pipelineStages.cri.enabled` | Enable CRI parser | `true` |
| `promtail.pipelineStages.docker.enabled` | Enable Docker parser | `false` |
| `rbac.create` | Create RBAC resources | `true` |
| `service.enabled` | Enable service for metrics | `true` |

## Operational Commands

```bash
# View logs from all Promtail pods
make -f make/ops/promtail.mk promtail-logs

# View logs from specific node
make -f make/ops/promtail.mk promtail-logs-node NODE=node-name

# Shell into Promtail pod
make -f make/ops/promtail.mk promtail-shell

# Check DaemonSet status
make -f make/ops/promtail.mk promtail-status

# View configuration
make -f make/ops/promtail.mk promtail-config

# Show scrape targets
make -f make/ops/promtail.mk promtail-targets

# Test Loki connection
make -f make/ops/promtail.mk promtail-test-loki

# Debug information
make -f make/ops/promtail.mk promtail-debug

# List nodes running Promtail
make -f make/ops/promtail.mk promtail-list-nodes
```

## Production Setup

```yaml
# values-prod.yaml
promtail:
  client:
    url: "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
    externalLabels:
      cluster: "production"
      environment: "prod"

  kubernetesSD:
    addPodAnnotations: false  # Reduce label cardinality

  pipelineStages:
    cri:
      enabled: true
    custom:
      # Drop debug logs in production
      - match:
          selector: '{level="debug"}'
          action: drop
      # Sample info logs (keep 50%)
      - match:
          selector: '{level="info"}'
          action: keep
        sampling:
          rate: 0.5

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 200m
    memory: 128Mi

# Use high priority to ensure logs are always collected
priorityClassName: "system-node-critical"
```

## How It Works

### Log Collection Flow

1. **Discovery**: Promtail uses Kubernetes API to discover all pods
2. **Read Logs**: Reads logs from `/var/log/pods/*`
3. **Parse**: Applies CRI/Docker parser to extract log line
4. **Extract**: Extracts log level (debug, info, warn, error, fatal, panic)
5. **Label**: Adds Kubernetes metadata as Loki labels
6. **Push**: Sends logs to Loki via HTTP

### Kubernetes Labels Added

Automatically added to all logs:

- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `node`: Node name
- All pod labels (prefixed with `label_`)

### Example LogQL Query

```logql
# All logs from specific namespace
{namespace="production"}

# Error logs from specific pod
{namespace="production",pod="myapp-12345",level="error"}

# All logs from containers with specific label
{label_app="myapp"}
```

## Log Parsers

### CRI Parser (Default)

For containerd and cri-o runtimes:

```yaml
promtail:
  pipelineStages:
    cri:
      enabled: true
```

CRI log format:
```
2023-01-01T10:00:00.000Z stderr F This is the log message
```

### Docker Parser

For Docker runtime:

```yaml
promtail:
  pipelineStages:
    cri:
      enabled: false
    docker:
      enabled: true
```

Docker log format:
```json
{"log":"This is the log message\n","stream":"stderr","time":"2023-01-01T10:00:00.000Z"}
```

## Custom Pipeline Stages

Add custom processing to logs:

```yaml
promtail:
  pipelineStages:
    custom:
      # Extract JSON fields
      - json:
          expressions:
            level: level
            message: message

      # Parse timestamp
      - timestamp:
          source: timestamp
          format: RFC3339

      # Add static label
      - static_labels:
          environment: production

      # Drop noisy logs
      - match:
          selector: '{container="sidecar"}'
          action: drop

      # Sample logs (keep 10%)
      - match:
          selector: '{level="debug"}'
          action: keep
        sampling:
          rate: 0.1
```

## Label Cardinality

**Important**: Loki performance depends heavily on label cardinality.

### Good Labels (Low Cardinality)

- `namespace` (~10-100 unique values)
- `container` (~10-50 unique values)
- `level` (~5-10 unique values)
- `app` label (~10-100 unique values)

### Bad Labels (High Cardinality)

- Pod names (1000s of unique values)
- Request IDs (millions of unique values)
- Timestamps (infinite cardinality)

**Best Practice**: Use labels for filtering, use LogQL for searching within log lines.

### Disable Pod Annotations

Pod annotations can add high cardinality:

```yaml
promtail:
  kubernetesSD:
    addPodAnnotations: false  # Recommended for production
```

## Basic Authentication

If Loki requires authentication:

```yaml
promtail:
  client:
    url: "https://loki.example.com/loki/api/v1/push"
    basicAuth:
      enabled: true
      username: "promtail"
      password: "secret"
```

## Multi-Tenancy

For Loki multi-tenancy:

```yaml
promtail:
  client:
    url: "http://loki:3100/loki/api/v1/push"
    tenantId: "team-a"
```

## Additional Scrape Configs

Collect logs from other sources:

```yaml
promtail:
  additionalScrapeConfigs:
    # Syslog
    - job_name: syslog
      syslog:
        listen_address: 0.0.0.0:1514
      relabel_configs:
        - source_labels: ['__syslog_message_hostname']
          target_label: 'host'

    # Journal
    - job_name: journal
      journal:
        max_age: 12h
        labels:
          job: systemd-journal
      relabel_configs:
        - source_labels: ['__journal__systemd_unit']
          target_label: 'unit'
```

## Resource Requirements

### Development

```yaml
resources:
  limits:
    cpu: 200m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 32Mi
```

### Production

```yaml
resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 200m
    memory: 128Mi
```

## Troubleshooting

### Check Promtail Status

```bash
make -f make/ops/promtail.mk promtail-status
```

### View Logs

```bash
make -f make/ops/promtail.mk promtail-logs
```

### Test Loki Connection

```bash
make -f make/ops/promtail.mk promtail-test-loki
```

### Check Targets

```bash
make -f make/ops/promtail.mk promtail-targets
```

### Debug Information

```bash
make -f make/ops/promtail.mk promtail-debug
```

### Check Log Paths

```bash
make -f make/ops/promtail.mk promtail-check-logs-path
```

### Common Issues

**Issue**: Promtail not collecting logs

**Solution**:
1. Check if pods are running: `make -f make/ops/promtail.mk promtail-status`
2. Check if Loki is reachable: `make -f make/ops/promtail.mk promtail-test-loki`
3. Verify log paths are mounted: `make -f make/ops/promtail.mk promtail-check-logs-path`

**Issue**: Logs not appearing in Loki

**Solution**:
1. Check Promtail logs for errors: `make -f make/ops/promtail.mk promtail-logs`
2. Verify Loki URL is correct: `make -f make/ops/promtail.mk promtail-config`
3. Check Loki is receiving logs: Query `{namespace="default"}` in Grafana

**Issue**: High memory usage

**Solution**:
1. Reduce log collection with pipeline stages
2. Increase `resources.limits.memory`
3. Sample or drop debug logs in production

## Integration with Grafana

### Add Loki to Grafana

1. Navigate to Configuration → Data Sources
2. Click "Add data source"
3. Select "Loki"
4. URL: `http://loki.default.svc.cluster.local:3100`
5. Save & Test

### Example Queries

```logql
# View all logs from namespace
{namespace="production"}

# Error logs only
{namespace="production"} |= "error"

# Logs from specific app
{label_app="myapp"}

# Rate of error logs
rate({namespace="production"} |= "error" [5m])
```

## License

- Chart: BSD 3-Clause License
- Promtail: Apache License 2.0

## Additional Resources

- [Promtail Documentation](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Pipeline Stages](https://grafana.com/docs/loki/latest/clients/promtail/stages/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Promtail Version**: 2.9.3
