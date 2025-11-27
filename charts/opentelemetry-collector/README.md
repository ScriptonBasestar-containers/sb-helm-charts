# OpenTelemetry Collector Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.96.0](https://img.shields.io/badge/AppVersion-0.96.0-informational?style=flat-square)

OpenTelemetry Collector for unified telemetry collection (traces, metrics, logs)

## Overview

The OpenTelemetry Collector is a vendor-agnostic proxy that can receive, process, and export telemetry data. This chart deploys the collector-contrib image which includes all community-contributed components.

## Features

- **OTLP Support**: Native OTLP gRPC and HTTP receivers
- **Multiple Exporters**: Prometheus, Loki, Tempo, Jaeger, and more
- **Kubernetes Integration**: k8sattributes processor for enrichment
- **Flexible Deployment**: Deployment (gateway) or DaemonSet (agent) modes
- **Production Ready**: HPA, PDB, ServiceMonitor support

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration
helm install otel-collector scripton-charts/opentelemetry-collector -n monitoring

# Install with production configuration
helm install otel-collector scripton-charts/opentelemetry-collector -n monitoring \
  -f values-example.yaml
```

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- For k8sattributes processor: ClusterRole permissions

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of collector replicas | `1` |
| `mode` | Deployment mode (deployment/daemonset) | `deployment` |
| `image.repository` | Collector image | `otel/opentelemetry-collector-contrib` |
| `image.tag` | Image tag | `""` (appVersion) |
| `config` | Collector configuration (YAML) | See values.yaml |
| `rbac.create` | Create RBAC resources | `true` |
| `rbac.clusterRole` | Create ClusterRole | `true` |
| `serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `podDisruptionBudget.enabled` | Enable PDB | `false` |

### Deployment Modes

**Gateway Mode (deployment):**
```yaml
mode: deployment
replicaCount: 2
```
Use for centralized collection where applications send telemetry to a central collector.

**Agent Mode (daemonset):**
```yaml
mode: daemonset
```
Use for per-node collection where a collector runs on each node.

### Pipeline Configuration

The collector configuration follows the OpenTelemetry Collector config format:

```yaml
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      timeout: 5s
    memory_limiter:
      limit_percentage: 80

  exporters:
    prometheusremotewrite:
      endpoint: http://mimir:8080/api/v1/push
    otlp/tempo:
      endpoint: tempo:4317
    loki:
      endpoint: http://loki:3100/loki/api/v1/push

  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [batch]
        exporters: [prometheusremotewrite]
      logs:
        receivers: [otlp]
        processors: [batch]
        exporters: [loki]
```

### Kubernetes Attributes

Enable k8sattributes processor to enrich telemetry with Kubernetes metadata:

```yaml
config:
  processors:
    k8sattributes:
      auth_type: "serviceAccount"
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.pod.name
          - k8s.node.name

  service:
    pipelines:
      traces:
        processors: [k8sattributes, batch]
```

## Usage

### Configure Applications

Set environment variables in your applications:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.monitoring.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
```

### SDK Examples

**Python:**
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(endpoint="otel-collector:4317", insecure=True)
```

**Go:**
```go
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"

exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("otel-collector:4317"),
    otlptracegrpc.WithInsecure(),
)
```

**Node.js:**
```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const exporter = new OTLPTraceExporter({
  url: 'http://otel-collector:4317',
});
```

## Production Setup

```yaml
# values-prod.yaml
replicaCount: 3

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      timeout: 5s
      send_batch_size: 10000
    memory_limiter:
      check_interval: 1s
      limit_percentage: 80
      spike_limit_percentage: 25
    k8sattributes:
      auth_type: "serviceAccount"

  exporters:
    prometheusremotewrite:
      endpoint: http://mimir:8080/api/v1/push
    otlp/tempo:
      endpoint: tempo:4317
    loki:
      endpoint: http://loki:3100/loki/api/v1/push

  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, k8sattributes, batch]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheusremotewrite]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, k8sattributes, batch]
        exporters: [loki]

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 1Gi

serviceMonitor:
  enabled: true

podDisruptionBudget:
  enabled: true
  minAvailable: 2

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10

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
                  - opentelemetry-collector
          topologyKey: kubernetes.io/hostname
```

## Backup & Recovery Strategy

This chart follows a **Makefile-driven backup approach** (no CronJob in chart) for maximum flexibility and control.

### Backup Strategy

The recommended backup strategy focuses on configuration (OpenTelemetry Collector is stateless):

1. **Configuration backups** - Collector YAML configuration, ConfigMaps
2. **Kubernetes resource manifests** - Deployment/DaemonSet, Service, RBAC
3. **Custom extensions** - Custom receivers/processors/exporters (if applicable)

**Backup frequency recommendations:**
- Configuration: Before changes (RTO: < 30 minutes, RPO: 0)
- Manifests: Weekly (RTO: < 1 hour, RPO: 1 week)

**Note**: OpenTelemetry Collector is stateless. Data flows through it without persistence, so focus is on configuration backup for rapid recovery.

### Backup Operations

**Backup configuration:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-backup-config
# Saves to: tmp/otel-collector-backups/config-<timestamp>/
```

**Backup Kubernetes manifests:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-backup-manifests
# Saves to: tmp/otel-collector-backups/manifests-<timestamp>/
```

**Full backup (config + manifests + metadata):**
```bash
make -f make/ops/opentelemetry-collector.mk otel-backup-all
# Saves to: tmp/otel-collector-backups/backup-<timestamp>/
```

**Verify backup integrity:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-backup-verify BACKUP_DIR=tmp/otel-collector-backups/backup-<timestamp>
```

### Recovery Operations

**Restore configuration:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-restore-config BACKUP_DIR=tmp/otel-collector-backups/config-<timestamp>
```

**Full restoration workflow:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-restore-all BACKUP_DIR=tmp/otel-collector-backups/backup-<timestamp>
```

For detailed backup/restore procedures, see [docs/opentelemetry-collector-backup-guide.md](../../docs/opentelemetry-collector-backup-guide.md).

---

## Security & RBAC

### RBAC Configuration

This chart creates ClusterRole-based RBAC permissions (required for k8sattributes processor):

```yaml
rbac:
  create: true              # Create RBAC resources
  clusterRole: true         # Create ClusterRole (required for k8sattributes)
```

**Default ClusterRole permissions:**
- Read Pods (k8sattributes processor)
- Read Namespaces (k8sattributes processor)
- Read Nodes (k8sattributes processor)
- Read Deployments, StatefulSets, DaemonSets (k8sattributes processor)
- Read Events, Services, Endpoints (k8s_cluster receiver, optional)

**Disable RBAC:**
```yaml
rbac:
  create: false
```

**Note**: k8sattributes processor requires cluster-wide read access to enrich telemetry with Kubernetes metadata.

### Security Enhancements

**Security Context:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
```

---

## Operations & Maintenance

### Upgrade Operations

**Pre-upgrade health check:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-pre-upgrade-check
```

**Recommended upgrade workflow:**
```bash
# 1. Pre-upgrade check
make -f make/ops/opentelemetry-collector.mk otel-pre-upgrade-check

# 2. Backup (recommended)
make -f make/ops/opentelemetry-collector.mk otel-backup-all

# 3. Upgrade Helm chart
helm upgrade otel-collector scripton-charts/opentelemetry-collector -n monitoring -f values.yaml

# 4. Post-upgrade validation
make -f make/ops/opentelemetry-collector.mk otel-post-upgrade-check

# 5. Rollback if needed
# make -f make/ops/opentelemetry-collector.mk otel-upgrade-rollback
```

**Post-upgrade validation:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-post-upgrade-check
# Validates: version, health, OTLP receivers, pipeline status, error logs
```

**Rollback to previous version:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-upgrade-rollback
# Interactive rollback with revision selection
```

For detailed upgrade procedures and strategies, see [docs/opentelemetry-collector-upgrade-guide.md](../../docs/opentelemetry-collector-upgrade-guide.md).

---

## Monitoring & Diagnostics

### Health Checks

**Check collector health:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-health-check
```

**Check OTLP receivers:**
```bash
# gRPC receiver (port 4317)
kubectl exec -n monitoring deploy/otel-collector -- nc -zv localhost 4317

# HTTP receiver (port 4318)
kubectl exec -n monitoring deploy/otel-collector -- wget -qO- http://localhost:4318
```

### Common Operations

**Port-forward for local testing:**
```bash
# OTLP gRPC
make -f make/ops/opentelemetry-collector.mk otel-port-forward-grpc
# Access at localhost:4317

# OTLP HTTP
make -f make/ops/opentelemetry-collector.mk otel-port-forward-http
# Access at localhost:4318

# Metrics
make -f make/ops/opentelemetry-collector.mk otel-port-forward-metrics
# Access at http://localhost:8888/metrics
```

**Access collector shell:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-shell
```

**View logs:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-logs
# Tail logs: make -f make/ops/opentelemetry-collector.mk otel-logs-all
```

**View configuration:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-config
```

**View pipeline metrics:**
```bash
make -f make/ops/opentelemetry-collector.mk otel-pipeline-metrics
```

**View Makefile commands:**
```bash
make -f make/ops/opentelemetry-collector.mk help
```

---

## Troubleshooting

### Check Collector Status

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Logs
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector -f

# Health check
kubectl exec -n monitoring deploy/otel-collector -- wget -qO- http://localhost:13133
```

### View Configuration

```bash
kubectl get configmap -n monitoring otel-collector -o yaml
```

### Common Issues

1. **No data received**: Check receivers configuration and network connectivity
2. **Memory issues**: Increase memory_limiter limits or add more replicas
3. **Permission errors**: Ensure RBAC is enabled and ClusterRole is created
4. **Export failures**: Verify exporter endpoints and credentials

### Debug Mode

Enable debug exporter to see processed data:

```yaml
config:
  exporters:
    debug:
      verbosity: detailed

  service:
    pipelines:
      traces:
        exporters: [debug, otlp/tempo]
```

## Related Charts

- [prometheus](../prometheus) - Metrics collection
- [loki](../loki) - Log aggregation
- [tempo](../tempo) - Distributed tracing
- [mimir](../mimir) - Long-term metrics storage
- [grafana](../grafana) - Visualization

## Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)

## License

- Chart: BSD 3-Clause License
- OpenTelemetry Collector: Apache License 2.0

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**OpenTelemetry Collector Version**: 0.96.0
