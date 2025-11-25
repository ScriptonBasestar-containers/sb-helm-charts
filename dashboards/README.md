# Grafana Dashboards

Pre-configured Grafana dashboards for the observability stack.

## Available Dashboards

| Dashboard | UID | Description |
|-----------|-----|-------------|
| [prometheus-overview.json](prometheus-overview.json) | `prometheus-overview` | Prometheus server metrics, targets, and query performance |
| [loki-overview.json](loki-overview.json) | `loki-overview` | Loki log aggregation with ingestion rates and query latency |
| [tempo-overview.json](tempo-overview.json) | `tempo-overview` | Tempo distributed tracing with service map |
| [kubernetes-cluster.json](kubernetes-cluster.json) | `kubernetes-cluster` | Kubernetes cluster overview (nodes, pods, resources) |

## Installation

### Method 1: ConfigMap Provisioning (Recommended)

```yaml
# Create ConfigMap with dashboards
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  prometheus-overview.json: |
    <content of prometheus-overview.json>
```

### Method 2: Grafana Dashboard Provisioning

Add to Grafana values:

```yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: 'ScriptonBasestar'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards

  dashboardsConfigMaps:
    default: "grafana-dashboards"
```

### Method 3: Import via UI

1. Open Grafana
2. Navigate to Dashboards > Import
3. Upload JSON file or paste content
4. Select appropriate datasources
5. Click Import

## Prerequisites

### Required Datasources

| Dashboard | Required Datasources |
|-----------|---------------------|
| prometheus-overview | Prometheus |
| loki-overview | Prometheus, Loki |
| tempo-overview | Prometheus, Tempo |
| kubernetes-cluster | Prometheus |

### Required Metrics Sources

- **prometheus-overview**: Prometheus internal metrics (`prometheus_*`)
- **loki-overview**: Loki metrics (`loki_*`) + Promtail
- **tempo-overview**: Tempo metrics (`tempo_*`)
- **kubernetes-cluster**: kube-state-metrics, node-exporter, cAdvisor

## Dashboard Features

### Prometheus Overview
- TSDB series usage and active time series
- Target status (up/down)
- Sample ingestion rate
- Storage usage (blocks, WAL)
- Query duration (p50, p99)
- HTTP request rate by handler
- Scrape targets table

### Loki Overview
- Active streams count
- Ingestion rate (bytes/s, lines/s)
- Query latency (p50, p99)
- Live log stream viewer
- Request rate by route
- Error rate

### Tempo Overview
- Spans received per second
- Ingestion rate (bytes/s)
- Total traces created
- Spans by receiver (OTLP, Jaeger)
- Query latency
- Service map visualization
- Compaction metrics
- Span drop rate

### Kubernetes Cluster
- Cluster stats (nodes, namespaces, pods, deployments)
- CPU usage by node
- Memory usage by node
- Network I/O by node
- Disk usage by node
- Pod status by phase
- Pod restarts
- Top 10 pods by CPU/Memory
- Deployment status table

## Variables

All dashboards include template variables for flexibility:

- `datasource`: Select Prometheus datasource
- `loki_datasource`: Select Loki datasource (Loki dashboard)
- `tempo_datasource`: Select Tempo datasource (Tempo dashboard)
- `namespace`: Filter by Kubernetes namespace (where applicable)
- `search`: Text search (Loki dashboard)

## Customization

Dashboards are designed to be editable. Common customizations:

1. **Change refresh interval**: Edit dashboard settings > refresh
2. **Add panels**: Click "Add" > "Visualization"
3. **Modify queries**: Edit panel > Query tab
4. **Change time range**: Top-right time picker

## Compatibility

- Grafana 10.x+ (schema version 39)
- Prometheus 2.x / 3.x
- Loki 2.9+ / 3.x
- Tempo 2.x

## Related Documentation

- [Dashboard Provisioning Guide](../docs/DASHBOARD_PROVISIONING_GUIDE.md) - Comprehensive provisioning methods
- [GitOps Guide](../docs/GITOPS_GUIDE.md) - ArgoCD/Flux deployment patterns
- [Alerting Rules](../alerting-rules/) - Pre-configured PrometheusRule templates
- [Grafana Chart](../charts/grafana/)
- [Prometheus Chart](../charts/prometheus/)
- [Loki Chart](../charts/loki/)
- [Tempo Chart](../charts/tempo/)
