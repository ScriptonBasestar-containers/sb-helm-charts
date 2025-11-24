# Observability Stack Guide

Complete guide for deploying and integrating Prometheus (metrics), Loki (logs), and Tempo (traces) for comprehensive observability.

## Overview

This guide demonstrates how to deploy a complete observability stack using three pillars:

- **Metrics** (Prometheus) - What is happening
- **Logs** (Loki) - Why it is happening
- **Traces** (Tempo) - How it is happening

Together, these provide complete visibility into your applications and infrastructure.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Integration and Correlation](#integration-and-correlation)
- [Application Instrumentation](#application-instrumentation)
- [Grafana Configuration](#grafana-configuration)
- [Query Examples](#query-examples)
- [Troubleshooting](#troubleshooting)
- [Production Considerations](#production-considerations)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Grafana (Visualization)                      │
│                  Dashboards, Alerts, Explore                     │
└──────────┬──────────────┬──────────────┬─────────────────────────┘
           │              │              │
           ▼              ▼              ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Prometheus │  │    Loki    │  │   Tempo    │
    │  (Metrics) │  │   (Logs)   │  │  (Traces)  │
    └──────┬─────┘  └──────┬─────┘  └──────┬─────┘
           │                │                │
    ┌──────┴─────────┐      │         ┌──────┴──────┐
    │   Exporters    │      │         │  OTLP/Jaeger│
    │ - Node         │      │         │  Receivers  │
    │ - KubeState    │      │         └──────┬──────┘
    │ - Blackbox     │      │                │
    └────────────────┘      │                │
                      ┌─────┴─────┐    ┌─────┴─────┐
                      │ Promtail  │    │   Apps    │
                      │(DaemonSet)│    │(Instrumented)
                      └───────────┘    └───────────┘
                            │                │
                      ┌─────┴─────┐    ┌─────┴─────┐
                      │   Pods    │    │   Pods    │
                      │  (Logs)   │    │  (Traces) │
                      └───────────┘    └───────────┘
```

### Data Flow

**Metrics Flow:**
```
Application/Node → Exporters → Prometheus → Grafana
```

**Logs Flow:**
```
Application/Container → Promtail → Loki → Grafana
```

**Traces Flow:**
```
Application (OTLP/Jaeger) → Tempo → Grafana
```

## Prerequisites

### Infrastructure

- Kubernetes 1.24+
- Helm 3.8+
- Storage Class with dynamic provisioning
- 8GB+ RAM available for monitoring stack
- (Optional) Ingress controller for external access

### Storage Requirements

| Component | Storage Type | Size (Dev) | Size (Prod) | Notes |
|-----------|--------------|------------|-------------|-------|
| Prometheus | PVC | 10Gi | 50Gi+ | Time-series metrics |
| Loki | PVC or S3 | 10Gi | S3/MinIO | Log aggregation |
| Tempo | PVC or S3 | 10Gi | S3/MinIO | Trace storage |
| Grafana | PVC | 5Gi | 10Gi | Dashboards config |

**Production Recommendation:** Use S3/MinIO for Loki and Tempo for scalability.

## Quick Start

### 1. Add Helm Repository

```bash
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update
```

### 2. Create Namespace

```bash
kubectl create namespace monitoring
```

### 3. Install Stack (Development)

```bash
# Install Prometheus
helm install prometheus sb-charts/prometheus \
  -n monitoring \
  --set persistence.size=10Gi

# Install Loki
helm install loki sb-charts/loki \
  -n monitoring \
  --set persistence.size=10Gi

# Install Tempo
helm install tempo sb-charts/tempo \
  -n monitoring \
  --set persistence.size=10Gi

# Install Promtail (log collector)
helm install promtail sb-charts/promtail \
  -n monitoring \
  --set loki.serviceName=loki

# Install Grafana with datasources
helm install grafana sb-charts/grafana \
  -n monitoring \
  --set persistence.size=5Gi
```

### 4. Access Grafana

```bash
# Get Grafana password
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port forward
kubectl port-forward -n monitoring svc/grafana 3000:80

# Visit: http://localhost:3000
# Login: admin / <password-from-above>
```

## Detailed Installation

### Production Deployment with S3/MinIO

**Step 1: Deploy MinIO for Object Storage**

```bash
helm install minio oci://registry-1.docker.io/bitnamicharts/minio \
  -n monitoring \
  --set auth.rootUser=admin \
  --set auth.rootPassword=SecureMinioPassword \
  --set defaultBuckets="loki-chunks,tempo-traces" \
  --set persistence.size=50Gi
```

**Step 2: Deploy Prometheus**

```bash
helm install prometheus sb-charts/prometheus \
  -n monitoring \
  -f - <<EOF
persistence:
  enabled: true
  size: 50Gi

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

retention: "30d"

serviceMonitor:
  enabled: true
EOF
```

**Step 3: Deploy Loki with S3**

```bash
helm install loki sb-charts/loki \
  -n monitoring \
  -f - <<EOF
loki:
  storage:
    type: "s3"
    s3:
      endpoint: "minio.monitoring.svc.cluster.local:9000"
      bucketNames: "loki-chunks"
      accessKeyId: "admin"
      secretAccessKey: "SecureMinioPassword"
      s3ForcePathStyle: true

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi

persistence:
  enabled: false  # Using S3
EOF
```

**Step 4: Deploy Tempo with S3**

```bash
helm install tempo sb-charts/tempo \
  -n monitoring \
  -f - <<EOF
tempo:
  storage:
    type: "s3"
    s3:
      endpoint: "minio.monitoring.svc.cluster.local:9000"
      bucket: "tempo-traces"
      accessKeyId: "admin"
      secretAccessKey: "SecureMinioPassword"
      insecure: true  # For MinIO

  retention:
    days: 14

  receivers:
    otlp:
      grpc:
        enabled: true
      http:
        enabled: true
    jaeger:
      grpc:
        enabled: true

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5

persistence:
  enabled: false  # Using S3
EOF
```

**Step 5: Deploy Promtail**

```bash
helm install promtail sb-charts/promtail \
  -n monitoring \
  --set loki.serviceName=loki.monitoring.svc.cluster.local
```

**Step 6: Deploy Grafana with All Datasources**

```bash
helm install grafana sb-charts/grafana \
  -n monitoring \
  -f - <<EOF
persistence:
  enabled: true
  size: 10Gi

grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          access: proxy
          url: http://prometheus.monitoring.svc.cluster.local:9090
          isDefault: true
          jsonData:
            timeInterval: "30s"
        - name: Loki
          type: loki
          access: proxy
          url: http://loki.monitoring.svc.cluster.local:3100
          jsonData:
            maxLines: 1000
        - name: Tempo
          type: tempo
          access: proxy
          url: http://tempo.monitoring.svc.cluster.local:3200
          jsonData:
            tracesToLogs:
              datasourceUid: 'Loki'
              tags: ['job', 'instance', 'pod', 'namespace']
            tracesToMetrics:
              datasourceUid: 'Prometheus'
            serviceMap:
              datasourceUid: 'Prometheus'
            nodeGraph:
              enabled: true

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

ingress:
  enabled: true
  className: nginx
  hosts:
    - grafana.example.com
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com
EOF
```

## Integration and Correlation

### Traces to Logs Correlation

Grafana can automatically jump from traces to related logs using configured tags.

**Tempo datasource configuration:**

```yaml
jsonData:
  tracesToLogs:
    datasourceUid: 'Loki'
    tags: ['job', 'instance', 'pod', 'namespace']
    mappedTags: [{ key: 'service.name', value: 'service' }]
    mapTagNamesEnabled: true
    spanStartTimeShift: '-1m'
    spanEndTimeShift: '1m'
```

**Application logging with trace context:**

```go
// Go example
import (
    "go.uber.org/zap"
    "go.opentelemetry.io/otel/trace"
)

span := trace.SpanFromContext(ctx)
logger.Info("Processing request",
    zap.String("traceID", span.SpanContext().TraceID().String()),
    zap.String("spanID", span.SpanContext().SpanID().String()),
)
```

### Traces to Metrics Correlation

Link traces to related metrics for performance analysis.

**Tempo datasource configuration:**

```yaml
jsonData:
  tracesToMetrics:
    datasourceUid: 'Prometheus'
    tags: [{ key: 'service.name', value: 'service' }]
    queries:
      - name: 'Request Rate'
        query: 'rate(http_requests_total{service="$service"}[5m])'
      - name: 'Error Rate'
        query: 'rate(http_requests_total{service="$service",status=~"5.."}[5m])'
```

### Logs to Traces Correlation

Extract trace IDs from logs for correlation.

**Loki datasource configuration:**

```yaml
jsonData:
  derivedFields:
    - datasourceUid: 'Tempo'
      matcherRegex: '"traceID":"(\w+)"'
      name: 'TraceID'
      url: '$${__value.raw}'
```

## Application Instrumentation

### OpenTelemetry Instrumentation (Recommended)

**Go Application:**

```go
package main

import (
    "context"
    "log"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/propagation"
    "go.opentelemetry.io/otel/sdk/resource"
    "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
    "google.golang.org/grpc"
)

func initTracer() (*trace.TracerProvider, error) {
    ctx := context.Background()

    // Create OTLP exporter
    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint("tempo.monitoring.svc.cluster.local:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, err
    }

    // Create resource
    res, err := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceNameKey.String("my-service"),
            semconv.ServiceVersionKey.String("1.0.0"),
        ),
    )
    if err != nil {
        return nil, err
    }

    // Create tracer provider
    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(res),
    )

    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.TraceContext{})

    return tp, nil
}

func main() {
    tp, err := initTracer()
    if err != nil {
        log.Fatal(err)
    }
    defer tp.Shutdown(context.Background())

    // Your application code here
}
```

**Python Application:**

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

def init_tracer():
    resource = Resource.create({
        "service.name": "my-service",
        "service.version": "1.0.0",
    })

    provider = TracerProvider(resource=resource)

    otlp_exporter = OTLPSpanExporter(
        endpoint="tempo.monitoring.svc.cluster.local:4317",
        insecure=True,
    )

    provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
    trace.set_tracer_provider(provider)

if __name__ == "__main__":
    init_tracer()
    # Your application code here
```

**Node.js Application:**

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');

function initTracer() {
  const resource = Resource.default().merge(
    new Resource({
      [SemanticResourceAttributes.SERVICE_NAME]: 'my-service',
      [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    })
  );

  const provider = new NodeTracerProvider({ resource });

  const exporter = new OTLPTraceExporter({
    url: 'tempo.monitoring.svc.cluster.local:4317',
  });

  provider.addSpanProcessor(new BatchSpanProcessor(exporter));
  provider.register();
}

initTracer();
```

## Grafana Configuration

### Creating Correlated Dashboards

**Example dashboard with all three pillars:**

```json
{
  "dashboard": {
    "title": "Service Overview",
    "panels": [
      {
        "title": "Request Rate (Metrics)",
        "type": "graph",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Recent Logs",
        "type": "logs",
        "datasource": "Loki",
        "targets": [
          {
            "expr": "{job=\"my-service\"}"
          }
        ]
      },
      {
        "title": "Trace Service Graph",
        "type": "nodeGraph",
        "datasource": "Tempo"
      }
    ]
  }
}
```

### Setting Up Alerts

**Alert for high error rate (Prometheus):**

```yaml
groups:
  - name: service_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Service {{ $labels.service }} has error rate {{ $value }}"
```

## Query Examples

### Metrics (PromQL)

```promql
# Request rate by service
rate(http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate percentage
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100
```

### Logs (LogQL)

```logql
# All logs from a service
{job="my-service"}

# Error logs
{job="my-service"} |= "error"

# Logs with specific trace ID
{job="my-service"} |= "traceID" |= "abc123"

# Rate of errors
rate({job="my-service"} |= "error" [5m])
```

### Traces (TraceQL)

```traceql
# Slow traces
{ duration > 1s }

# Traces with errors
{ status = error }

# Traces for specific service
{ service.name = "my-service" }

# Complex query
{ service.name = "my-service" && span.http.method = "POST" && duration > 100ms }
```

## Troubleshooting

### Common Issues

**1. Traces not appearing in Tempo**

```bash
# Check Tempo is receiving spans
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo | grep "spans received"

# Verify application can reach Tempo
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v tempo.monitoring.svc.cluster.local:3200/ready
```

**2. Logs not showing in Loki**

```bash
# Check Promtail is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail

# Test Loki API
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://loki.monitoring.svc.cluster.local:3100/ready
```

**3. Metrics not collecting**

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check scrape configs
kubectl get configmap -n monitoring prometheus-config -o yaml
```

## Production Considerations

### High Availability

**Prometheus:**
- Use Thanos or Cortex for HA and long-term storage
- Multiple replicas with federation

**Loki:**
- Use S3/MinIO storage with multiple replicas
- Consider microservices mode for scale

**Tempo:**
- S3/MinIO storage required for multi-replica
- Enable HPA for auto-scaling

### Resource Planning

| Component | CPU (Request/Limit) | Memory (Request/Limit) | Storage |
|-----------|---------------------|------------------------|---------|
| Prometheus | 500m/2000m | 1Gi/4Gi | 50Gi+ |
| Loki | 250m/1000m | 512Mi/2Gi | S3/MinIO |
| Tempo | 250m/2000m | 512Mi/2Gi | S3/MinIO |
| Grafana | 250m/1000m | 512Mi/1Gi | 10Gi |
| Promtail | 100m/200m | 128Mi/256Mi | - |

### Security

**1. Enable Authentication:**

```yaml
# Grafana
grafana:
  auth:
    ldap:
      enabled: true
```

**2. Enable TLS:**

```yaml
# Ingress with TLS
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: monitoring-tls
      hosts:
        - grafana.example.com
```

**3. Network Policies:**

```yaml
# Enable for all components
networkPolicy:
  enabled: true
```

### Backup and Restore

**Prometheus:**
```bash
# Snapshot
curl -X POST http://prometheus:9090/api/v1/admin/tsdb/snapshot

# Backup PVC
kubectl exec -n monitoring prometheus-0 -- tar czf /backup/prometheus.tar.gz /prometheus
```

**Grafana:**
```bash
# Export dashboards
kubectl exec -n monitoring grafana-0 -- grafana-cli admin export

# Backup PVC
kubectl exec -n monitoring grafana-0 -- tar czf /backup/grafana.tar.gz /var/lib/grafana
```

## Related Charts

- [prometheus](../charts/prometheus) - Metrics collection and monitoring
- [loki](../charts/loki) - Log aggregation and querying
- [tempo](../charts/tempo) - Distributed tracing
- [grafana](../charts/grafana) - Visualization and dashboards
- [promtail](../charts/promtail) - Log collection agent
- [alertmanager](../charts/alertmanager) - Alert routing
- [minio](../charts/minio) - S3-compatible object storage

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Dashboard Examples](https://grafana.com/grafana/dashboards/)
- [Example Deployment](../examples/full-monitoring-stack/) - Pre-configured stack

---

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
