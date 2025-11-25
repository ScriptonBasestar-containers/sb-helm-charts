# Tempo

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/tempo)
[![Chart Version](https://img.shields.io/badge/chart-0.3.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-2.9.0-green.svg)](https://grafana.com/oss/tempo/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

Grafana Tempo distributed tracing backend with S3/MinIO storage support and OpenTelemetry compatibility.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# Install with local storage (development)
helm install tempo sb-charts/tempo

# Install with S3/MinIO storage (production)
helm install tempo sb-charts/tempo \
  --set tempo.storage.type=s3 \
  --set tempo.storage.s3.endpoint=minio.default.svc.cluster.local:9000 \
  --set tempo.storage.s3.bucket=tempo-traces \
  --set tempo.storage.s3.accessKeyId=your-access-key \
  --set tempo.storage.s3.secretAccessKey=your-secret-key
```

## Introduction

This chart bootstraps a Grafana Tempo deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ Distributed tracing with OpenTelemetry support
- ✅ Multiple receiver protocols (OTLP, Jaeger, Zipkin)
- ✅ S3/MinIO backend for scalable storage
- ✅ Local filesystem support for development
- ✅ Horizontal Pod Autoscaling
- ✅ Pod Disruption Budget for HA
- ✅ Network Policy for security
- ✅ Prometheus metrics support
- ✅ Grafana datasource integration

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- **S3/MinIO storage** (recommended for production)
- PersistentVolume provisioner support (for local storage)

### Storage Requirements

**Development:** Local filesystem with PVC (single instance only)
**Production:** S3-compatible storage (MinIO, AWS S3, GCS, etc.) for multi-replica deployment

## Installing the Chart

### Quick Start - Local Storage

For development and testing:

```bash
helm install tempo sb-charts/tempo
```

This uses local filesystem storage with a 10Gi PVC.

### Production Deployment - S3/MinIO Storage

**Step 1: Prepare S3/MinIO Bucket**

```bash
# Install MinIO (if not already available)
helm install minio oci://registry-1.docker.io/bitnamicharts/minio \
  --set auth.rootUser=admin \
  --set auth.rootPassword=SecurePassword \
  --set defaultBuckets=tempo-traces

# Or create bucket in existing MinIO
mc alias set myminio http://minio:9000 admin SecurePassword
mc mb myminio/tempo-traces
```

**Step 2: Create values file**

Create `tempo-values.yaml`:

```yaml
replicaCount: 2

tempo:
  storage:
    type: "s3"
    s3:
      endpoint: "minio.default.svc.cluster.local:9000"
      bucket: "tempo-traces"
      accessKeyId: "your-access-key"
      secretAccessKey: "your-secret-key"
      insecure: false  # Set true for HTTP MinIO

  retention:
    days: 14  # 14 days for production

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

# Production features
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5

podDisruptionBudget:
  enabled: true
  minAvailable: 1

serviceMonitor:
  enabled: true

networkPolicy:
  enabled: true
```

**Step 3: Install Tempo**

```bash
helm install tempo sb-charts/tempo -f tempo-values.yaml
```

### Deployment Scenarios

This chart includes pre-configured values for three deployment scenarios:

#### Home Server / Personal Use

```bash
helm install tempo sb-charts/tempo \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/tempo/values-home-single.yaml
```

**Resources**: 50m-500m CPU, 128Mi-512Mi RAM, 5Gi storage
**Storage**: Local filesystem
**Features**: OTLP receivers only, 7 days retention

#### Startup / Small Team

```bash
helm install tempo sb-charts/tempo \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/tempo/values-startup-single.yaml
```

**Resources**: 100m-1000m CPU, 256Mi-1Gi RAM, 10Gi storage
**Storage**: Local or S3/MinIO
**Features**: OTLP + Jaeger receivers, monitoring enabled

#### Production / High Availability

```bash
helm install tempo sb-charts/tempo \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/tempo/values-prod-master-replica.yaml \
  --set tempo.storage.s3.accessKeyId=your-key \
  --set tempo.storage.s3.secretAccessKey=your-secret \
  --set tempo.storage.s3.endpoint=minio.default.svc.cluster.local:9000
```

**Resources**: 250m-2000m CPU, 512Mi-2Gi RAM
**Storage**: S3/MinIO (required)
**Features**: All receivers, HPA, PDB, full monitoring, 14 days retention

## Configuration

### Storage Configuration

#### Local Filesystem Storage

Suitable for development and single-instance deployments:

```yaml
tempo:
  storage:
    type: "local"
    local:
      path: "/var/tempo/traces"

persistence:
  enabled: true
  size: 10Gi
```

#### S3/MinIO Storage

Required for production and multi-replica deployments:

```yaml
tempo:
  storage:
    type: "s3"
    s3:
      endpoint: "minio.default.svc.cluster.local:9000"
      bucket: "tempo-traces"
      accessKeyId: "your-access-key"
      secretAccessKey: "your-secret-key"
      insecure: false  # Set true for HTTP
```

### Receiver Configuration

Tempo supports multiple trace ingestion protocols:

#### OTLP (OpenTelemetry Protocol)

Most modern applications use OTLP:

```yaml
tempo:
  receivers:
    otlp:
      grpc:
        enabled: true
        port: 4317  # Default OTLP gRPC port
      http:
        enabled: true
        port: 4318  # Default OTLP HTTP port
```

**Client configuration example:**

```go
// Go application
import "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"

exporter, err := otlptracegrpc.New(
    context.Background(),
    otlptracegrpc.WithEndpoint("tempo.default.svc.cluster.local:4317"),
    otlptracegrpc.WithInsecure(),
)
```

#### Jaeger Protocol

For existing Jaeger instrumentation:

```yaml
tempo:
  receivers:
    jaeger:
      grpc:
        enabled: true
        port: 14250
      thriftHttp:
        enabled: true
        port: 14268
```

#### Zipkin Protocol

For Zipkin instrumentation:

```yaml
tempo:
  receivers:
    zipkin:
      enabled: true
      port: 9411
```

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Deployment** | | |
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `grafana/tempo` |
| `image.tag` | Image tag (overrides appVersion) | `""` |
| **Storage** | | |
| `tempo.storage.type` | Storage backend | `local` |
| `tempo.storage.s3.endpoint` | S3 endpoint | `""` |
| `tempo.storage.s3.bucket` | S3 bucket name | `tempo-traces` |
| `tempo.storage.s3.accessKeyId` | S3 access key | `""` |
| `tempo.storage.s3.secretAccessKey` | S3 secret key | `""` |
| `tempo.retention.days` | Trace retention days | `7` |
| **Receivers** | | |
| `tempo.receivers.otlp.grpc.enabled` | Enable OTLP gRPC | `true` |
| `tempo.receivers.otlp.http.enabled` | Enable OTLP HTTP | `true` |
| `tempo.receivers.jaeger.grpc.enabled` | Enable Jaeger gRPC | `false` |
| `tempo.receivers.zipkin.enabled` | Enable Zipkin | `false` |
| **Resources** | | |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `256Mi` |
| **Persistence** | | |
| `persistence.enabled` | Enable PVC (local storage) | `true` |
| `persistence.size` | Storage size | `10Gi` |

See [values.yaml](values.yaml) for all available options.

## Persistence

The chart mounts a Persistent Volume at `/var/tempo` when using local storage. The volume is created using dynamic volume provisioning.

**PVC Configuration:**

```yaml
persistence:
  enabled: true
  storageClass: ""  # Use cluster default
  accessMode: ReadWriteOnce
  size: 10Gi
```

**Storage Requirements:**

- **Home**: 5Gi (7 days retention)
- **Startup**: 10Gi (7 days retention)
- **Production**: Use S3/MinIO (no PVC)

**Note:** For production deployments with multiple replicas, you **must** use S3/MinIO storage. Local filesystem storage only supports single-replica deployments.

## Networking

### Service Configuration

```yaml
service:
  type: ClusterIP
  port: 3200  # HTTP API
  ports:
    otlpGrpc: 4317
    otlpHttp: 4318
    jaegerGrpc: 14250
    jaegerThriftHttp: 14268
    zipkin: 9411
```

### Service Endpoints

| Port | Protocol | Purpose |
|------|----------|---------|
| 3200 | HTTP | Tempo HTTP API and /ready endpoint |
| 4317 | gRPC | OTLP gRPC receiver |
| 4318 | HTTP | OTLP HTTP receiver |
| 14250 | gRPC | Jaeger gRPC receiver (optional) |
| 14268 | HTTP | Jaeger Thrift HTTP (optional) |
| 9411 | HTTP | Zipkin receiver (optional) |

## Integration with Grafana

### Adding Tempo as Datasource

**Manual configuration:**

1. Go to Grafana → Configuration → Data Sources
2. Click "Add data source"
3. Select "Tempo"
4. Configure URL: `http://tempo.default.svc.cluster.local:3200`
5. Save & Test

**Grafana values.yaml:**

```yaml
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Tempo
          type: tempo
          access: proxy
          url: http://tempo.default.svc.cluster.local:3200
          isDefault: false
```

### Querying Traces

**By Trace ID:**
```
Explore → Tempo → Query: <trace-id>
```

**TraceQL Query:**
```
{ span.http.method="GET" && duration > 100ms }
```

**Service Graph:**

Tempo can generate service graphs from trace data. Enable in Grafana:
- Tempo datasource → Settings → Enable "Service Graph"

## Application Instrumentation

### OpenTelemetry (Recommended)

**Go:**
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

exporter, _ := otlptracegrpc.New(
    context.Background(),
    otlptracegrpc.WithEndpoint("tempo.default.svc.cluster.local:4317"),
    otlptracegrpc.WithInsecure(),
)

tp := sdktrace.NewTracerProvider(
    sdktrace.WithBatcher(exporter),
)
otel.SetTracerProvider(tp)
```

**Python:**
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(
    endpoint="tempo.default.svc.cluster.local:4317",
    insecure=True
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)
```

**Node.js:**
```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');

const provider = new NodeTracerProvider();
const exporter = new OTLPTraceExporter({
  url: 'tempo.default.svc.cluster.local:4317'
});
provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

## Security

### Network Policies

Enable network policies to restrict traffic:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
```

**Default policy allows:**
- Ingress: All namespaces on ports 3200, 4317, 4318
- Egress: DNS (53), S3/MinIO (9000, 443)

### Pod Security

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Tempo requires writable filesystem
```

### Credentials Management

S3 credentials are stored in Kubernetes Secret:

```bash
# View secret
kubectl get secret tempo-secret -o yaml

# Update credentials
kubectl create secret generic tempo-secret \
  --from-literal=access-key-id=new-access-key \
  --from-literal=secret-access-key=new-secret-key \
  --dry-run=client -o yaml | kubectl apply -f -
```

## High Availability

### Horizontal Pod Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 75
  targetMemoryUtilizationPercentage: 80
```

**Requirements for HPA:**
- S3/MinIO storage (local storage doesn't support multiple replicas)
- Metrics Server installed in cluster

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

PDB ensures at least 1 replica remains available during voluntary disruptions.

### High Availability Recommendations

For production HA deployment:

1. **S3/MinIO storage**: Required for multi-replica (shared storage)
2. **Multiple replicas**: Set `replicaCount: 2` or enable HPA
3. **Pod anti-affinity**: Spread replicas across nodes (included in prod values)
4. **External HA storage**: Use S3-compatible storage with HA
5. **Monitoring**: Enable ServiceMonitor for visibility

## Monitoring

### Prometheus Metrics

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  labels:
    prometheus: kube-prometheus
```

**Available metrics:**
- `tempo_distributor_spans_received_total` - Total spans received
- `tempo_ingester_blocks_flushed_total` - Blocks flushed to storage
- `tempo_query_frontend_queries_total` - Total queries processed
- `tempo_tempodb_backend_requests_total` - Backend storage requests

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=tempo

# View logs
kubectl logs -l app.kubernetes.io/name=tempo --tail=100

# Describe pod for events
kubectl describe pod <tempo-pod-name>
```

### Storage Issues

**S3/MinIO connection:**

```bash
# Test S3 connectivity from pod
kubectl exec -it <tempo-pod> -- wget -O- http://minio:9000

# Check S3 credentials
kubectl get secret tempo-secret -o yaml
```

**Local storage:**

```bash
# Check PVC binding
kubectl get pvc -l app.kubernetes.io/name=tempo

# Verify storage class
kubectl get storageclass
```

### Traces Not Appearing

**Check receiver endpoints:**

```bash
# Verify service endpoints
kubectl get svc tempo -o yaml

# Test OTLP gRPC endpoint
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v tempo.default.svc.cluster.local:3200/ready
```

**Verify application instrumentation:**

```bash
# Check application is sending traces
kubectl logs <app-pod> | grep -i trace

# Verify Tempo is receiving spans
kubectl logs -l app.kubernetes.io/name=tempo | grep "spans received"
```

### Grafana Integration Issues

```bash
# Test Tempo HTTP API
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://tempo.default.svc.cluster.local:3200/api/search

# Check Grafana datasource configuration
kubectl exec -it <grafana-pod> -- cat /etc/grafana/provisioning/datasources/datasources.yaml
```

### Common Issues

1. **No traces showing up**: Verify application is instrumented and sending to correct endpoint
2. **S3 permission denied**: Check S3 credentials and bucket permissions
3. **PVC not binding**: Check storage class availability
4. **High memory usage**: Increase `resources.limits.memory` or reduce `tempo.retention.days`
5. **Multiple replicas with local storage**: Switch to S3/MinIO storage

## Upgrading

### To v0.3.0

```bash
# Backup important traces (if possible)
# Note: Tempo is designed for recent traces, not long-term storage

# Upgrade chart
helm upgrade tempo sb-charts/tempo \
  --reuse-values \
  --set autoscaling.enabled=true \
  --set podDisruptionBudget.enabled=true

# Verify upgrade
kubectl rollout status deployment/tempo
```

See [CHANGELOG.md](../../CHANGELOG.md) for version-specific upgrade notes.

## Uninstalling the Chart

```bash
# Uninstall release
helm uninstall tempo

# Delete PVC (optional - data will be lost!)
kubectl delete pvc tempo

# Clean up S3 bucket (if no longer needed)
mc rb --force myminio/tempo-traces
```

## Development

### Local Testing

```bash
# Render templates locally
helm template tempo ./charts/tempo -f values.yaml

# Lint chart
helm lint ./charts/tempo

# Dry-run installation
helm install tempo ./charts/tempo --dry-run --debug

# Install in local cluster (kind/minikube)
helm install tempo ./charts/tempo
```

### Testing with OpenTelemetry

```bash
# Install OpenTelemetry Collector demo
kubectl apply -f https://raw.githubusercontent.com/open-telemetry/opentelemetry-operator/main/examples/default-instrumentation/app.yaml

# View traces in Grafana
kubectl port-forward svc/grafana 3000:80
# Visit http://localhost:3000 → Explore → Tempo
```

## Contributing

Contributions are welcome! Please see our [Contributing Guide](../../.github/CONTRIBUTING.md) for details.

## License

This Helm chart is licensed under the BSD 3-Clause License.

**Note**: Grafana Tempo itself is licensed under the AGPL-3.0 License. See the [Tempo project](https://grafana.com/oss/tempo/) for details.

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Chart Catalog**: [docs/CHARTS.md](../../docs/CHARTS.md) - Browse all available charts
- **Tempo Homepage**: https://grafana.com/oss/tempo/
- **Tempo Documentation**: https://grafana.com/docs/tempo/latest/
- **Tempo GitHub**: https://github.com/grafana/tempo
- **OpenTelemetry**: https://opentelemetry.io/
- **Chart Development Guide**: [docs/CHART_DEVELOPMENT_GUIDE.md](../../docs/CHART_DEVELOPMENT_GUIDE.md)

## Related Charts

Consider these complementary charts from this repository:

- **[prometheus](../prometheus)** - Metrics collection and monitoring
- **[loki](../loki)** - Log aggregation and querying
- **[grafana](../grafana)** - Visualization and dashboards
- **[minio](../minio)** - S3-compatible storage backend
- **[alertmanager](../alertmanager)** - Alert routing and notification

**Complete Observability Stack**: Prometheus (metrics) + Loki (logs) + Tempo (traces) + Grafana (visualization)

---

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
