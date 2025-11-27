# Observability Stack Integration Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Component Installation](#component-installation)
5. [Integration Configuration](#integration-configuration)
6. [Grafana Configuration](#grafana-configuration)
7. [Application Instrumentation](#application-instrumentation)
8. [Monitoring & Alerting](#monitoring--alerting)
9. [Production Deployment](#production-deployment)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive procedures for deploying and integrating a complete observability stack using the ScriptonBasestar Helm charts. The stack combines metrics, logs, and traces into a unified platform for monitoring, debugging, and analyzing applications in Kubernetes.

### Observability Pillars

The complete stack implements the three pillars of observability:

1. **Metrics** - Quantitative measurements (CPU, memory, request rates, error rates)
   - **Prometheus**: Short-term metrics collection and querying
   - **Mimir**: Long-term metrics storage and high availability

2. **Logs** - Text-based event records (application logs, access logs, error logs)
   - **Promtail**: Log collection agent
   - **Loki**: Log aggregation and indexing

3. **Traces** - Distributed request flow tracking (spans, traces, dependencies)
   - **OpenTelemetry Collector**: Telemetry data collection and processing
   - **Tempo**: Distributed tracing backend

4. **Visualization** - Unified dashboard and exploration
   - **Grafana**: Metrics, logs, and traces visualization

### Stack Components

| Component | Role | Storage | HA Support |
|-----------|------|---------|------------|
| **Prometheus** | Metrics scraping & short-term storage | Local (15d default) | Yes (federation) |
| **Mimir** | Long-term metrics storage | S3/MinIO | Yes (distributed) |
| **Loki** | Log aggregation & indexing | S3/MinIO | Yes (distributed) |
| **Tempo** | Distributed tracing backend | S3/MinIO | Yes (distributed) |
| **Promtail** | Log collection agent | N/A (agent) | N/A |
| **OpenTelemetry Collector** | Telemetry collection gateway | N/A (stateless) | Yes (horizontal) |
| **Grafana** | Visualization & dashboards | PostgreSQL | Yes (clustering) |

---

## Architecture

### Reference Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Applications                              │
│  (Instrumented with Prometheus, OpenTelemetry, Logging)         │
└──────────────┬──────────────┬──────────────┬────────────────────┘
               │              │              │
               │ Metrics      │ Traces       │ Logs
               │ (pull)       │ (push)       │ (push)
               ▼              ▼              ▼
         ┌──────────┐   ┌──────────┐   ┌──────────┐
         │Prometheus│   │   OTel   │   │ Promtail │
         │          │   │Collector │   │ (DaemonSet)
         │(StatefulSet)│  (Deployment)  └─────┬────┘
         └─────┬────┘   └─────┬────┘          │
               │              │               │
               │ remote_write │ OTLP          │ push
               ▼              ▼               ▼
         ┌──────────┐   ┌──────────┐   ┌──────────┐
         │  Mimir   │   │  Tempo   │   │   Loki   │
         │          │   │          │   │          │
         │(StatefulSet)│(StatefulSet) │(StatefulSet)
         └─────┬────┘   └─────┬────┘   └─────┬────┘
               │              │               │
               │ S3/MinIO     │ S3/MinIO      │ S3/MinIO
               ▼              ▼               ▼
         ┌────────────────────────────────────────┐
         │           Object Storage                │
         │         (MinIO or S3)                   │
         └────────────────────────────────────────┘
                           ▲
                           │ Query
                           │
                    ┌──────┴─────┐
                    │  Grafana   │
                    │            │
                    │ (Deployment)│
                    └────────────┘
                           │
                    ┌──────┴─────┐
                    │  Users     │
                    │ (Browser)  │
                    └────────────┘
```

### Data Flow

**Metrics Flow:**
1. Applications expose `/metrics` endpoint (Prometheus format)
2. Prometheus scrapes metrics from applications (pull model)
3. Prometheus stores metrics locally (15 days default)
4. Prometheus remote_writes metrics to Mimir for long-term storage
5. Grafana queries both Prometheus (recent data) and Mimir (historical data)

**Logs Flow:**
1. Applications write logs to stdout/stderr
2. Promtail (DaemonSet) collects logs from all pods on each node
3. Promtail pushes logs to Loki
4. Loki indexes logs and stores them in object storage (S3/MinIO)
5. Grafana queries Loki for log exploration and alerting

**Traces Flow:**
1. Applications emit traces using OpenTelemetry SDK
2. Applications send traces to OpenTelemetry Collector (OTLP protocol)
3. OpenTelemetry Collector processes and forwards traces to Tempo
4. Tempo stores traces in object storage (S3/MinIO)
5. Grafana queries Tempo for trace visualization and analysis

### Network Ports

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Prometheus | 9090 | HTTP | Metrics query API, UI |
| Mimir | 8080 | HTTP | Remote write, query API |
| Loki | 3100 | HTTP | Log push, query API |
| Tempo | 4317 | gRPC | OTLP trace ingestion |
| Tempo | 3200 | HTTP | Query API, UI |
| OpenTelemetry Collector | 4317 | gRPC | OTLP receiver |
| OpenTelemetry Collector | 4318 | HTTP | OTLP HTTP receiver |
| OpenTelemetry Collector | 8888 | HTTP | Metrics endpoint |
| Promtail | 3101 | HTTP | Metrics endpoint |
| Grafana | 3000 | HTTP | UI, API |

---

## Prerequisites

### Kubernetes Cluster

- Kubernetes 1.24+
- kubectl configured with cluster access
- Storage class for PersistentVolumeClaims
- Minimum 16GB memory, 8 CPU cores (for full stack)

### Helm

```bash
# Install Helm 3.8+
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Add ScriptonBasestar Helm repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update
```

### Object Storage (S3-compatible)

For production deployments, S3-compatible object storage is required for Mimir, Loki, and Tempo.

**Option 1: MinIO (Recommended for on-premises)**
```bash
# Install MinIO using sb-charts
helm install minio sb-charts/minio -n storage --create-namespace \
  --set persistence.enabled=true \
  --set persistence.size=100Gi \
  --set auth.rootUser=admin \
  --set auth.rootPassword=minio123
```

**Option 2: AWS S3**
- Create S3 buckets: `mimir-blocks`, `loki-data`, `tempo-traces`
- Create IAM user with read/write permissions
- Note access key ID and secret access key

**Option 3: Other S3-compatible storage**
- Google Cloud Storage (GCS)
- Azure Blob Storage
- Ceph RGW
- DigitalOcean Spaces

### Namespace

```bash
# Create monitoring namespace
kubectl create namespace monitoring
```

---

## Component Installation

### 1. Install MinIO (Object Storage)

**File: `values-minio.yaml`**
```yaml
# MinIO for object storage backend
persistence:
  enabled: true
  storageClass: ""
  size: 100Gi

auth:
  rootUser: admin
  rootPassword: minio123

replicas: 1

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

service:
  type: ClusterIP
  port: 9000

ingress:
  enabled: false
```

**Install:**
```bash
helm install minio sb-charts/minio -n storage --create-namespace -f values-minio.yaml
```

**Create buckets:**
```bash
# Port-forward to MinIO
kubectl port-forward -n storage svc/minio 9000:9000 &

# Install MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Configure mc
mc alias set myminio http://localhost:9000 admin minio123

# Create buckets
mc mb myminio/mimir-blocks
mc mb myminio/loki-data
mc mb myminio/tempo-traces

# Verify buckets
mc ls myminio
```

### 2. Install Prometheus

**File: `values-prometheus.yaml`**
```yaml
# Prometheus for metrics scraping and short-term storage
server:
  persistentVolume:
    enabled: true
    size: 50Gi
  retention: "15d"

  # Remote write to Mimir for long-term storage
  remoteWrite:
    - url: http://mimir.monitoring.svc.cluster.local:8080/api/v1/push
      queueConfig:
        capacity: 10000
        maxShards: 20
        minShards: 1
        maxSamplesPerSend: 5000
        batchSendDeadline: 5s

  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi

  # Service discovery configuration
  # Scrape Kubernetes pods with prometheus.io annotations
  extraScrapeConfigs: |
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__

alertmanager:
  enabled: false

pushgateway:
  enabled: false

serviceMonitor:
  enabled: false
```

**Install:**
```bash
helm install prometheus sb-charts/prometheus -n monitoring -f values-prometheus.yaml
```

### 3. Install Mimir

**File: `values-mimir.yaml`**
```yaml
# Mimir for long-term metrics storage
replicaCount: 1

mimir:
  target: "all"  # Monolithic mode

  storage:
    backend: "s3"
    s3:
      endpoint: "minio.storage.svc.cluster.local:9000"
      bucket: "mimir-blocks"
      region: "us-east-1"
      accessKeyId: "admin"
      secretAccessKey: "minio123"
      insecure: true

  blocks:
    retentionPeriod: "90d"  # 90 days retention

  limits:
    ingestionRate: 50000
    ingestionBurstSize: 500000
    maxGlobalSeriesPerUser: 500000

persistence:
  enabled: true
  size: 50Gi

resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi

serviceMonitor:
  enabled: true
```

**Install:**
```bash
helm install mimir sb-charts/mimir -n monitoring -f values-mimir.yaml
```

### 4. Install Loki

**File: `values-loki.yaml`**
```yaml
# Loki for log aggregation
loki:
  auth_enabled: false

  storage:
    type: s3
    s3:
      endpoint: minio.storage.svc.cluster.local:9000
      bucketnames: loki-data
      access_key_id: admin
      secret_access_key: minio123
      s3ForcePathStyle: true
      insecure: true

  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: index_
          period: 24h

  limits_config:
    retention_period: 90d
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20

persistence:
  enabled: true
  size: 30Gi

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi

serviceMonitor:
  enabled: true
```

**Install:**
```bash
helm install loki sb-charts/loki -n monitoring -f values-loki.yaml
```

### 5. Install Promtail

**File: `values-promtail.yaml`**
```yaml
# Promtail for log collection (DaemonSet)
config:
  lokiAddress: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push

  snippets:
    pipelineStages:
      - docker: {}
      - cri: {}

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# DaemonSet to run on all nodes
daemonset:
  enabled: true

serviceMonitor:
  enabled: true
```

**Install:**
```bash
helm install promtail sb-charts/promtail -n monitoring -f values-promtail.yaml
```

### 6. Install Tempo

**File: `values-tempo.yaml`**
```yaml
# Tempo for distributed tracing
tempo:
  storage:
    trace:
      backend: s3
      s3:
        endpoint: minio.storage.svc.cluster.local:9000
        bucket: tempo-traces
        access_key: admin
        secret_key: minio123
        insecure: true

  retention: 720h  # 30 days

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

persistence:
  enabled: true
  size: 30Gi

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi

serviceMonitor:
  enabled: true
```

**Install:**
```bash
helm install tempo sb-charts/tempo -n monitoring -f values-tempo.yaml
```

### 7. Install OpenTelemetry Collector

**File: `values-otel-collector.yaml`**
```yaml
# OpenTelemetry Collector for telemetry collection
mode: deployment
replicaCount: 2

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
      auth_type: serviceAccount
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.pod.name
          - k8s.node.name

  exporters:
    # Send traces to Tempo
    otlp/tempo:
      endpoint: tempo.monitoring.svc.cluster.local:4317
      tls:
        insecure: true

    # Send metrics to Mimir (via Prometheus remote write)
    prometheusremotewrite:
      endpoint: http://mimir.monitoring.svc.cluster.local:8080/api/v1/push

    # Send logs to Loki
    loki:
      endpoint: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push

  service:
    extensions:
      - health_check
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
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

rbac:
  create: true
  clusterRole: true

serviceMonitor:
  enabled: true

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

**Install:**
```bash
helm install otel-collector sb-charts/opentelemetry-collector -n monitoring -f values-otel-collector.yaml
```

### 8. Install Grafana

**File: `values-grafana.yaml`**
```yaml
# Grafana for visualization
admin:
  user: admin
  password: grafana123

# PostgreSQL for Grafana persistence
postgresql:
  enabled: false
  external:
    enabled: true
    host: postgresql.default.svc.cluster.local
    port: 5432
    database: grafana
    username: grafana
    password: grafana123

persistence:
  enabled: true
  size: 10Gi

# Pre-configure datasources
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      # Prometheus datasource (short-term metrics)
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server.monitoring.svc.cluster.local:9090
        access: proxy
        isDefault: true
        jsonData:
          timeInterval: 30s
          httpMethod: POST

      # Mimir datasource (long-term metrics)
      - name: Mimir
        type: prometheus
        url: http://mimir.monitoring.svc.cluster.local:8080/prometheus
        access: proxy
        jsonData:
          timeInterval: 1m
          httpMethod: POST

      # Loki datasource (logs)
      - name: Loki
        type: loki
        url: http://loki.monitoring.svc.cluster.local:3100
        access: proxy
        jsonData:
          maxLines: 1000
          derivedFields:
            - datasourceUid: tempo
              matcherRegex: '"trace_id":"(\w+)"'
              name: TraceID
              url: '$${__value.raw}'

      # Tempo datasource (traces)
      - name: Tempo
        type: tempo
        url: http://tempo.monitoring.svc.cluster.local:3200
        access: proxy
        jsonData:
          tracesToLogs:
            datasourceUid: loki
            mapTagNamesEnabled: true
            tags: ['pod', 'namespace']
          tracesToMetrics:
            datasourceUid: prometheus
          serviceMap:
            datasourceUid: prometheus
          search:
            hide: false
          nodeGraph:
            enabled: true

# Dashboard providers
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - grafana.example.com
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com
```

**Install:**
```bash
helm install grafana sb-charts/grafana -n monitoring -f values-grafana.yaml
```

---

## Integration Configuration

### 1. Verify Component Status

```bash
# Check all pods
kubectl get pods -n monitoring

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# prometheus-server-0                     1/1     Running   0          5m
# mimir-0                                 1/1     Running   0          5m
# loki-0                                  1/1     Running   0          5m
# tempo-0                                 1/1     Running   0          5m
# promtail-xxxxx                          1/1     Running   0          5m  (DaemonSet)
# otel-collector-xxxxxxxxxx-xxxxx         1/1     Running   0          5m
# grafana-xxxxxxxxxx-xxxxx                1/1     Running   0          5m

# Check services
kubectl get svc -n monitoring
```

### 2. Test Prometheus Remote Write to Mimir

```bash
# Check Prometheus remote write status
kubectl logs -n monitoring prometheus-server-0 | grep "remote_write"

# Verify Mimir is receiving metrics
kubectl exec -n monitoring mimir-0 -- wget -qO- http://localhost:8080/metrics | grep "cortex_ingester_ingested_samples_total"
```

### 3. Test Promtail to Loki

```bash
# Check Promtail logs
kubectl logs -n monitoring -l app=promtail --tail=50

# Verify Loki is receiving logs
kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/loki/api/v1/label' | jq
```

### 4. Test OpenTelemetry Collector to Tempo

```bash
# Check OTel Collector logs
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --tail=50

# Verify Tempo is ready
kubectl exec -n monitoring tempo-0 -- wget -qO- http://localhost:3200/ready
```

---

## Grafana Configuration

### 1. Access Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser: http://localhost:3000
# Login: admin / grafana123
```

### 2. Verify Datasources

1. Navigate to **Configuration → Data Sources**
2. Verify all datasources are green (Prometheus, Mimir, Loki, Tempo)
3. Test each datasource connection

### 3. Import Dashboards

**Kubernetes Cluster Monitoring:**
```bash
# Import dashboard ID: 315 (Kubernetes cluster monitoring)
# Or use Grafana UI: Dashboards → Import → 315
```

**Loki Logs Dashboard:**
```bash
# Import dashboard ID: 13639 (Loki Dashboard)
```

**Tempo Traces Dashboard:**
```bash
# Import custom dashboard or use Explore view
```

### 4. Create Explore Queries

**Metrics Query (Prometheus/Mimir):**
```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# Memory usage by namespace
sum(container_memory_working_set_bytes) by (namespace)

# Request rate
rate(http_requests_total[5m])
```

**Logs Query (Loki):**
```logql
# All logs from namespace
{namespace="default"}

# Error logs
{namespace="default"} |= "error"

# Logs with trace ID
{namespace="default"} | json | trace_id != ""
```

**Traces Query (Tempo):**
- Use **Explore** view
- Select **Tempo** datasource
- Search by service name, operation, duration, etc.
- Click on trace ID to view waterfall diagram

---

## Application Instrumentation

### 1. Metrics (Prometheus)

**Add Prometheus annotations to pods:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  containers:
    - name: app
      image: my-app:latest
      ports:
        - containerPort: 8080
          name: metrics
```

**Expose `/metrics` endpoint in application:**

Python (Flask):
```python
from prometheus_client import Counter, Histogram, generate_latest
from flask import Flask, Response

app = Flask(__name__)

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency')

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype='text/plain')
```

Go:
```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "net/http"
)

func main() {
    http.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":8080", nil)
}
```

### 2. Logs (Loki via Promtail)

Promtail automatically collects logs from all pods. Ensure applications log to stdout/stderr:

**Structured logging (JSON format recommended):**
```json
{
  "timestamp": "2025-01-27T12:00:00Z",
  "level": "info",
  "message": "Request processed",
  "trace_id": "0123456789abcdef",
  "duration_ms": 45
}
```

**Add trace ID to logs for correlation:**
```python
import logging
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def log_with_trace(message, trace_id):
    log_entry = {
        "message": message,
        "trace_id": trace_id,
        "level": "info"
    }
    logger.info(json.dumps(log_entry))
```

### 3. Traces (OpenTelemetry)

**Install OpenTelemetry SDK:**

Python:
```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp
```

**Configure application:**
```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Configure tracer
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Configure OTLP exporter
otlp_exporter = OTLPSpanExporter(
    endpoint="otel-collector.monitoring.svc.cluster.local:4317",
    insecure=True
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Instrument code
@app.route('/api/users')
def get_users():
    with tracer.start_as_current_span("get_users") as span:
        span.set_attribute("user.count", len(users))
        return jsonify(users)
```

**Environment variables for auto-instrumentation:**
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.monitoring.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "my-app"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=production"
```

---

## Monitoring & Alerting

### 1. Prometheus Alerting Rules

**Create alert rules ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alerts
  namespace: monitoring
data:
  alerts.yml: |
    groups:
      - name: kubernetes_alerts
        interval: 30s
        rules:
          - alert: HighPodMemory
            expr: sum(container_memory_working_set_bytes) by (pod) > 1e9
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Pod {{ $labels.pod }} high memory usage"
              description: "Pod {{ $labels.pod }} is using more than 1GB memory"

          - alert: HighErrorRate
            expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "High error rate detected"
              description: "Error rate is {{ $value }} per second"
```

### 2. Grafana Alerting

**Create alert in Grafana:**
1. Navigate to **Alerting → Alert rules**
2. Click **New alert rule**
3. Configure:
   - Query: `rate(http_requests_total{status="500"}[5m]) > 0.1`
   - Condition: `WHEN last() OF query(A) IS ABOVE 0.1`
   - Evaluation: Every 1m for 5m
   - Notification: Configure contact points (email, Slack, PagerDuty)

### 3. Log-based Alerts

**Create Loki alert:**
```yaml
# Alert on error logs
- alert: HighErrorLogRate
  expr: |
    sum(rate({namespace="production"} |= "error" [5m])) > 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error log rate in production"
    description: "More than 10 error logs per second"
```

---

## Production Deployment

### 1. High Availability

**Prometheus:**
```yaml
# Use federation for HA
server:
  replicaCount: 2
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - prometheus
          topologyKey: kubernetes.io/hostname
```

**Mimir:**
```yaml
# Increase replicas for distributed mode
replicaCount: 3
mimir:
  ingester:
    ring:
      replicationFactor: 3
```

**Loki:**
```yaml
# Distributed Loki setup
loki:
  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: s3
        schema: v13
  ingester:
    replicas: 3
  distributor:
    replicas: 3
  querier:
    replicas: 3
```

**Tempo:**
```yaml
# Increase replicas
replicaCount: 3
```

**OpenTelemetry Collector:**
```yaml
# Already HA with 2 replicas
replicaCount: 3
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

### 2. Resource Sizing

**Recommended minimum resources for production:**

| Component | CPU (requests) | Memory (requests) | CPU (limits) | Memory (limits) | Storage |
|-----------|----------------|-------------------|--------------|-----------------|---------|
| Prometheus | 1000m | 4Gi | 2000m | 8Gi | 100Gi |
| Mimir | 1000m | 4Gi | 2000m | 8Gi | 100Gi |
| Loki | 500m | 2Gi | 1000m | 4Gi | 50Gi |
| Tempo | 500m | 2Gi | 1000m | 4Gi | 50Gi |
| Promtail | 100m | 128Mi | 200m | 256Mi | N/A |
| OTel Collector | 500m | 1Gi | 2000m | 4Gi | N/A |
| Grafana | 500m | 1Gi | 1000m | 2Gi | 20Gi |

### 3. Security

**Enable authentication:**
```yaml
# Grafana basic auth (already configured)
admin:
  user: admin
  password: <strong-password>

# Use Secrets for credentials
apiVersion: v1
kind: Secret
metadata:
  name: observability-credentials
  namespace: monitoring
type: Opaque
stringData:
  minio-access-key: admin
  minio-secret-key: <strong-password>
  grafana-admin-password: <strong-password>
```

**Enable TLS:**
```yaml
# Ingress with TLS
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com
```

**Network Policies:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: grafana
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 3000
```

### 4. Backup Strategy

**Backup Grafana dashboards:**
```bash
# Export all dashboards
kubectl exec -n monitoring grafana-xxxxx -- grafana-cli admin export-dashboards /tmp/dashboards

# Backup to S3
aws s3 cp /tmp/dashboards s3://my-backup-bucket/grafana-dashboards/ --recursive
```

**Backup Prometheus data:**
```bash
# Create snapshot
kubectl exec -n monitoring prometheus-server-0 -- promtool tsdb snapshot /prometheus

# Copy snapshot
kubectl cp monitoring/prometheus-server-0:/prometheus/snapshots /tmp/prometheus-snapshot
```

**Backup Grafana database:**
```bash
# Backup PostgreSQL database
kubectl exec -n default postgresql-0 -- pg_dump -U grafana grafana > grafana-db-backup.sql
```

---

## Troubleshooting

### Common Issues

#### 1. Prometheus not scraping metrics

**Check:**
```bash
# Verify service discovery
kubectl exec -n monitoring prometheus-server-0 -- wget -qO- http://localhost:9090/api/v1/targets | jq

# Check pod annotations
kubectl get pod my-app -o yaml | grep prometheus.io
```

#### 2. Mimir not receiving remote_write

**Check:**
```bash
# Verify Prometheus remote_write config
kubectl logs -n monitoring prometheus-server-0 | grep "remote_write"

# Check Mimir logs
kubectl logs -n monitoring mimir-0 | grep "write"

# Verify network connectivity
kubectl exec -n monitoring prometheus-server-0 -- wget -qO- http://mimir:8080/ready
```

#### 3. Loki not receiving logs

**Check:**
```bash
# Verify Promtail is running
kubectl get pods -n monitoring -l app=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app=promtail --tail=50

# Test Loki API
kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/ready'
```

#### 4. Tempo not receiving traces

**Check:**
```bash
# Verify OTel Collector is forwarding traces
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | grep "tempo"

# Check Tempo logs
kubectl logs -n monitoring tempo-0 | grep "otlp"

# Test Tempo API
kubectl exec -n monitoring tempo-0 -- wget -qO- http://localhost:3200/ready
```

#### 5. Grafana datasource connection issues

**Check:**
```bash
# Test datasource from Grafana pod
kubectl exec -n monitoring grafana-xxxxx -- curl http://prometheus-server:9090/api/v1/query?query=up
kubectl exec -n monitoring grafana-xxxxx -- curl http://mimir:8080/prometheus/api/v1/query?query=up
kubectl exec -n monitoring grafana-xxxxx -- curl http://loki:3100/loki/api/v1/labels
kubectl exec -n monitoring grafana-xxxxx -- curl http://tempo:3200/ready
```

### Performance Tuning

**Prometheus:**
```yaml
# Increase scrape interval for high cardinality
server:
  global:
    scrape_interval: 60s  # Reduce from 30s
    evaluation_interval: 60s
```

**Mimir:**
```yaml
# Increase limits
mimir:
  limits:
    ingestionRate: 100000
    maxGlobalSeriesPerUser: 1000000
```

**Loki:**
```yaml
# Increase log ingestion limits
loki:
  limits_config:
    ingestion_rate_mb: 20
    ingestion_burst_size_mb: 40
```

**Tempo:**
```yaml
# Increase trace retention
tempo:
  retention: 1440h  # 60 days
```

---

## Appendix: Quick Reference

### Component URLs

| Component | Service | Port | URL |
|-----------|---------|------|-----|
| Prometheus | prometheus-server | 9090 | http://prometheus-server.monitoring.svc:9090 |
| Mimir | mimir | 8080 | http://mimir.monitoring.svc:8080 |
| Loki | loki | 3100 | http://loki.monitoring.svc:3100 |
| Tempo | tempo | 3200 | http://tempo.monitoring.svc:3200 |
| OTel Collector | otel-collector | 4317/4318 | http://otel-collector.monitoring.svc:4317 |
| Grafana | grafana | 3000 | http://grafana.monitoring.svc:3000 |

### Useful Commands

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# View Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f

# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# View Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:9090
# Open: http://localhost:9090/targets

# Query Mimir directly
kubectl exec -n monitoring mimir-0 -- wget -qO- 'http://localhost:8080/prometheus/api/v1/query?query=up'

# Query Loki directly
kubectl exec -n monitoring loki-0 -- wget -qO- 'http://localhost:3100/loki/api/v1/label'

# Test Tempo
kubectl exec -n monitoring tempo-0 -- wget -qO- http://localhost:3200/ready

# Check OTel Collector metrics
kubectl exec -n monitoring deploy/otel-collector -- wget -qO- http://localhost:8888/metrics
```

---

**Document Version**: 1.0
**Last Updated**: 2025-01-27
**Maintained by**: ScriptonBasestar
**Related**: [Multi-Tenancy Guide](multi-tenancy-guide.md)
