# Full Monitoring Stack - Example Deployment

Complete observability stack with metrics, logs, and visualization.

## Stack Components

### Metrics Collection & Storage

- **Prometheus** - Time-series database and metrics collection
- **Alertmanager** - Alert routing and notification
- **Pushgateway** - Batch job metrics collection
- **Node Exporter** - Hardware and OS metrics (DaemonSet on all nodes)
- **Kube State Metrics** - Kubernetes object state metrics
- **Blackbox Exporter** - Endpoint probing (HTTP/HTTPS/TCP/DNS/ICMP)

### Logging

- **Loki** - Log aggregation and storage
- **Promtail** - Log collection agent (DaemonSet on all nodes)

### Visualization

- **Grafana** - Metrics and logs visualization with dashboards

## Architecture

```

┌─────────────────────────────────────────────────────────────────┐
│                         Grafana (UI)                            │
│                    http://grafana.local                         │
└───────────────┬──────────────────────┬──────────────────────────┘
                │                      │
                ▼                      ▼
        ┌──────────────┐       ┌──────────────┐
        │  Prometheus  │       │     Loki     │
        │   (Metrics)  │       │    (Logs)    │
        └──────┬───────┘       └──────┬───────┘
               │                      │
        ┌──────┴───────┬──────────────┴────────┐
        ▼              ▼              ▼         ▼
  ┌──────────┐  ┌──────────┐  ┌───────────┐ ┌─────────┐
  │   Node   │  │   Kube   │  │ Blackbox  │ │Promtail │
  │ Exporter │  │  State   │  │  Exporter │ │(DaemonSet)
  │(DaemonSet)│  │ Metrics  │  │           │ └─────────┘
  └──────────┘  └──────────┘  └───────────┘
        │
  ┌─────┴─────┐
  │Pushgateway│
  │(Batch Jobs)
  └───────────┘
        │
  ┌─────┴──────┐
  │Alertmanager│
  │  (Alerts)  │
  └────────────┘

```

## Prerequisites

### 1. Kubernetes Cluster

- Kubernetes 1.19+
- Sufficient resources (see Resource Requirements below)

### 2. Storage

- StorageClass with dynamic provisioning
- Or pre-created PersistentVolumes

### 3. Helm

```bash
helm repo add scripton-charts <https://scriptonbasestar-container.github.io/sb-helm-charts>
helm repo update

```

### 4. (Optional) Ingress Controller

- nginx-ingress or similar
- cert-manager for TLS

## Installation

### Step 1: Create Namespace

```bash
kubectl create namespace monitoring

```

### Step 2: Install Components

Install in this order for proper dependencies:

#### 2.1 Storage & Data Collection

```bash
# Prometheus (metrics storage)
helm install prometheus scripton-charts/prometheus \
  -f values-prometheus.yaml \
  -n monitoring

# Loki (log storage)
helm install loki scripton-charts/loki \
  -f values-loki.yaml \
  -n monitoring

```

#### 2.2 Metrics Exporters

```bash
# Node Exporter (hardware metrics)
helm install node-exporter scripton-charts/node-exporter \
  -f values-node-exporter.yaml \
  -n monitoring

# Kube State Metrics (K8s object metrics)
helm install kube-state-metrics scripton-charts/kube-state-metrics \
  -f values-kube-state-metrics.yaml \
  -n monitoring

# Blackbox Exporter (endpoint probing)
helm install blackbox-exporter scripton-charts/blackbox-exporter \
  -f values-blackbox-exporter.yaml \
  -n monitoring

```

#### 2.3 Log Collection

```bash
# Promtail (log collection)
helm install promtail scripton-charts/promtail \
  -f values-promtail.yaml \
  -n monitoring

```

#### 2.4 Alerting

```bash
# Alertmanager (alert routing)
helm install alertmanager scripton-charts/alertmanager \
  -f values-alertmanager.yaml \
  -n monitoring

# Pushgateway (batch job metrics)
helm install pushgateway scripton-charts/pushgateway \
  -f values-pushgateway.yaml \
  -n monitoring

```

#### 2.5 Visualization

```bash
# Grafana (dashboards)
helm install grafana scripton-charts/grafana \
  -f values-grafana.yaml \
  -n monitoring

```

### Step 3: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Expected output:
# prometheus-0                      1/1     Running
# loki-0                            1/1     Running
# alertmanager-0                    1/1     Running
# grafana-...                       1/1     Running
# node-exporter-...                 1/1     Running  (on each node)
# kube-state-metrics-...            1/1     Running
# blackbox-exporter-...             1/1     Running
# promtail-...                      1/1     Running  (on each node)
# pushgateway-...                   1/1     Running

```

## Access

### Grafana UI

```bash
# Get Grafana admin password
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open browser
open http://localhost:3000
# Login: admin / <password-from-above>

```

### Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
open http://localhost:9090

```

### Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
open http://localhost:9093

```

## Configuration

### Grafana Dashboards

Pre-configured dashboards are automatically provisioned:

- Kubernetes Cluster Monitoring
- Node Metrics
- Pod Metrics
- Prometheus Stats
- Loki Logs

### Prometheus Targets

Prometheus automatically discovers:

- All nodes (via node-exporter)
- All pods (via kube-state-metrics)
- Kubernetes API server
- All services with `prometheus.io/scrape: "true"` annotation

### Alert Rules

Default alert rules included:

- Node down
- High CPU/Memory usage
- Pod crash looping
- PersistentVolume full
- Kubernetes API errors

## Customization

### Add Custom Metrics Scraping

Edit `values-prometheus.yaml`:

```yaml
prometheus:
  additionalScrapeConfigs:
    - job_name: 'my-app'

      static_configs:
        - targets: ['my-app.default.svc.cluster.local:8080']

```

### Add Alert Receivers

Edit `values-alertmanager.yaml`:

```yaml
config:
  receivers:
    - name: 'slack'

      slack_configs:
        - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

          channel: '#alerts'

```

### Add Grafana Datasources

Edit `values-grafana.yaml`:

```yaml
grafana:
  datasources:
    - name: External Prometheus

      type: prometheus
      url: http://external-prometheus:9090

```

## Resource Requirements

### Minimum (Development)

- 3 CPU cores
- 8 GB RAM
- 50 GB storage

### Recommended (Production)

- 8 CPU cores
- 16 GB RAM
- 200 GB storage

### Per Component (Production)

| Component | CPU (req/limit) | Memory (req/limit) | Storage |
|-----------|-----------------|-------------------|---------|
| Prometheus | 500m/2000m | 1Gi/4Gi | 50Gi |
| Loki | 500m/2000m | 1Gi/2Gi | 50Gi |
| Grafana | 200m/500m | 256Mi/1Gi | 5Gi |
| Alertmanager | 100m/500m | 128Mi/512Mi | 5Gi |
| Node Exporter | 100m/500m (per node) | 128Mi/256Mi | - |

| Kube State Metrics | 100m/500m | 128Mi/512Mi | - |
| Blackbox Exporter | 100m/500m | 128Mi/512Mi | - |

| Promtail | 100m/500m (per node) | 128Mi/256Mi | - |
| Pushgateway | 100m/500m | 128Mi/512Mi | 2Gi |

## Troubleshooting

### Prometheus not scraping targets

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus config
kubectl exec -n monitoring prometheus-0 -- cat /etc/prometheus/prometheus.yml

# Check targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

```

### Loki not receiving logs

```bash
# Check Promtail is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail

# Test Loki endpoint
kubectl exec -n monitoring loki-0 -- wget -O- http://localhost:3100/ready

```

### Grafana datasource not working

```bash
# Check Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Verify datasource config
kubectl get cm -n monitoring grafana-datasources -o yaml

```

## Uninstallation

```bash
# Remove all components
helm uninstall -n monitoring prometheus loki grafana alertmanager \
  node-exporter kube-state-metrics blackbox-exporter promtail pushgateway

# (Optional) Delete namespace
kubectl delete namespace monitoring

```

## Next Steps

1. **Add More Dashboards**: Import from <https://grafana.com/grafana/dashboards/>
2. **Configure Alerting**: Set up Slack/PagerDuty/Email notifications
3. **Enable Persistence**: Configure S3/MinIO for long-term storage
4. **Scale Up**: Increase replicas and resources for production
5. **Add Authentication**: Enable OAuth/LDAP for Grafana
6. **Enable TLS**: Use Ingress with cert-manager
7. **Backup**: Set up automated backups for Prometheus/Loki data

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
