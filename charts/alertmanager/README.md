# Alertmanager Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.27.0](https://img.shields.io/badge/AppVersion-0.27.0-informational?style=flat-square)

Prometheus Alertmanager for alert routing and notification with high availability support

## Features

- **High Availability**: Multi-replica support with automatic peer discovery
- **Alert Routing**: Flexible routing tree with grouping and inhibition
- **Multiple Receivers**: Email, Slack, PagerDuty, Webhook, and more
- **Silences**: Temporary alert suppression with TTL
- **Template Support**: Custom notification templates
- **API v2**: RESTful API for alert and silence management
- **ServiceMonitor**: Prometheus Operator integration
- **Operational Tools**: 20+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration (single replica)
helm install my-alertmanager scripton-charts/alertmanager

# Install with HA mode (3 replicas)
helm install my-alertmanager scripton-charts/alertmanager \
  --set replicaCount=3 \
  --set persistence.enabled=true

# Install with production configuration
helm install my-alertmanager scripton-charts/alertmanager \
  -f values-small-prod.yaml
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Prometheus for alert generation
- (Optional) Prometheus Operator for ServiceMonitor

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (HA mode if > 1) | `1` |
| `alertmanager.retention` | Data retention period | `120h` |
| `config.global.resolveTimeout` | Time to wait for resolve | `5m` |
| `config.route.groupBy` | Labels to group alerts | `['alertname', 'cluster', 'service']` |
| `config.route.repeatInterval` | Interval to resend notifications | `12h` |
| `persistence.enabled` | Enable persistent storage | `false` |
| `serviceMonitor.enabled` | Enable ServiceMonitor | `false` |

## Operational Commands

### Basic Operations

```bash
# View logs
make -f make/ops/alertmanager.mk am-logs

# View logs from all pods
make -f make/ops/alertmanager.mk am-logs-all

# Open shell
make -f make/ops/alertmanager.mk am-shell

# Restart
make -f make/ops/alertmanager.mk am-restart
```

### Health & Status

```bash
# Check status
make -f make/ops/alertmanager.mk am-status

# Check version
make -f make/ops/alertmanager.mk am-version

# Check health
make -f make/ops/alertmanager.mk am-health

# Check cluster status (HA mode)
make -f make/ops/alertmanager.mk am-cluster-status
```

### Configuration Management

```bash
# View configuration
make -f make/ops/alertmanager.mk am-config

# Reload configuration
make -f make/ops/alertmanager.mk am-reload

# Validate configuration
make -f make/ops/alertmanager.mk am-validate-config
```

### Alerts Management

```bash
# List all alerts
make -f make/ops/alertmanager.mk am-list-alerts

# List alerts in JSON
make -f make/ops/alertmanager.mk am-list-alerts-json

# Get specific alert
make -f make/ops/alertmanager.mk am-get-alert FINGERPRINT=abc123
```

### Silences Management

```bash
# List all silences
make -f make/ops/alertmanager.mk am-list-silences

# Get specific silence
make -f make/ops/alertmanager.mk am-get-silence ID=abc123

# Delete silence
make -f make/ops/alertmanager.mk am-delete-silence ID=abc123
```

### Port Forward

```bash
# Port forward to localhost:9093
make -f make/ops/alertmanager.mk am-port-forward

# Then visit http://localhost:9093
```

## High Availability Mode

Enable HA by setting `replicaCount > 1`:

```yaml
replicaCount: 3

persistence:
  enabled: true
  size: 5Gi

podDisruptionBudget:
  enabled: true
  minAvailable: 2
```

**How it works:**
- StatefulSet provides stable network identity
- Headless service enables peer discovery
- Gossip protocol (port 9094) synchronizes state
- Each replica has independent storage
- Cluster automatically handles leader election

**Cluster Status:**
```bash
make -f make/ops/alertmanager.mk am-cluster-status
```

## Configuration Examples

### Email Notifications

```yaml
config:
  global:
    smtp:
      from: "alertmanager@example.com"
      smarthost: "smtp.gmail.com:587"
      authUsername: "alertmanager@example.com"
      authPassword: "your-app-password"
      requireTLS: true

  receivers:
    - name: email-team
      emailConfigs:
        - to: "team@example.com"
          headers:
            Subject: "[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}"
```

### Slack Notifications

```yaml
config:
  global:
    slackApiUrl: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

  receivers:
    - name: slack-alerts
      slackConfigs:
        - channel: "#alerts"
          title: "{{ .GroupLabels.alertname }}"
          text: |-
            {{ range .Alerts }}
              *Alert:* {{ .Annotations.summary }}
              *Description:* {{ .Annotations.description }}
              *Severity:* {{ .Labels.severity }}
            {{ end }}
```

### PagerDuty Integration

```yaml
config:
  receivers:
    - name: pagerduty-critical
      pagerdutyConfigs:
        - serviceKey: "your-pagerduty-service-key"
          description: "{{ .GroupLabels.alertname }}"
```

### Webhook Receiver

```yaml
config:
  receivers:
    - name: webhook-receiver
      webhookConfigs:
        - url: "http://example.com/webhook"
          sendResolved: true
          httpConfig:
            basicAuth:
              username: "user"
              password: "pass"
```

## Routing Examples

### Route by Severity

```yaml
config:
  route:
    receiver: default
    routes:
      - match:
          severity: critical
        receiver: pagerduty-critical
        continue: true
      - match:
          severity: warning
        receiver: slack-warnings
```

### Route by Team

```yaml
config:
  route:
    receiver: default
    routes:
      - match:
          team: frontend
        receiver: frontend-team
      - match:
          team: backend
        receiver: backend-team
      - match:
          team: devops
        receiver: devops-team
```

### Inhibition Rules

Suppress warning alerts when critical alert is firing:

```yaml
config:
  inhibitRules:
    - sourceMatch:
        severity: critical
      targetMatch:
        severity: warning
      equal: ['alertname', 'instance']
```

## Integration with Prometheus

### Prometheus Configuration

```yaml
# prometheus.yml
alerting:
  alertmanagers:
    - kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
          action: keep
          regex: alertmanager
        - source_labels: [__meta_kubernetes_pod_container_port_number]
          action: keep
          regex: "9093"
```

### Using ServiceMonitor

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus
```

## Alert Example

Example alert rule in Prometheus:

```yaml
groups:
  - name: example
    rules:
      - alert: HighMemoryUsage
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10
        for: 5m
        labels:
          severity: warning
          team: devops
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 90% (current: {{ $value }}%)"
```

## Production Setup

```yaml
# values-prod.yaml
replicaCount: 3

alertmanager:
  retention: "120h"
  extraArgs:
    - --log.level=info
    - --cluster.reconnect-timeout=5m
    - --web.enable-lifecycle

config:
  global:
    resolveTimeout: "5m"
    smtp:
      from: "alertmanager@example.com"
      smarthost: "smtp.example.com:587"
      authUsername: "alertmanager@example.com"
      authPassword: "your-password"
      requireTLS: true

  route:
    groupBy: ['alertname', 'cluster', 'service']
    groupWait: 10s
    groupInterval: 10s
    repeatInterval: 12h
    receiver: default
    routes:
      - match:
          severity: critical
        receiver: pagerduty-critical
      - match:
          severity: warning
        receiver: slack-warnings

  inhibitRules:
    - sourceMatch:
        severity: critical
      targetMatch:
        severity: warning
      equal: ['alertname', 'cluster', 'service']

  receivers:
    - name: default
      emailConfigs:
        - to: "team@example.com"
    - name: pagerduty-critical
      pagerdutyConfigs:
        - serviceKey: "your-service-key"
    - name: slack-warnings
      slackConfigs:
        - channel: "#warnings"

serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus

podDisruptionBudget:
  enabled: true
  minAvailable: 2

persistence:
  enabled: true
  size: 5Gi

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

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
                  - alertmanager
          topologyKey: kubernetes.io/hostname

priorityClassName: "system-cluster-critical"
```

## Troubleshooting

### Check Alertmanager Status

```bash
make -f make/ops/alertmanager.mk am-status
```

### View Configuration

```bash
make -f make/ops/alertmanager.mk am-config
```

### Check Cluster Health (HA mode)

```bash
make -f make/ops/alertmanager.mk am-cluster-status
```

### Common Issues

**Issue**: Alerts not appearing in Alertmanager

**Solution**:
```bash
# Check Prometheus is sending alerts
kubectl logs -n monitoring prometheus-0 | grep alertmanager

# Check Alertmanager is receiving alerts
make -f make/ops/alertmanager.mk am-list-alerts
```

**Issue**: Notifications not being sent

**Solution**:
```bash
# Check receiver configuration
make -f make/ops/alertmanager.mk am-list-receivers

# Check logs for errors
make -f make/ops/alertmanager.mk am-logs
```

**Issue**: Cluster peers not connecting

**Solution**:
```bash
# Check cluster status
make -f make/ops/alertmanager.mk am-cluster-status

# Check headless service
kubectl get svc -n monitoring alertmanager-headless

# Check StatefulSet DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup alertmanager-0.alertmanager-headless.monitoring.svc.cluster.local
```

## API v2 Documentation

Alertmanager provides a RESTful API for alert and silence management:

### Alerts API

```bash
# List alerts
curl http://localhost:9093/api/v2/alerts

# Get specific alert
curl http://localhost:9093/api/v2/alert/{fingerprint}
```

### Silences API

```bash
# List silences
curl http://localhost:9093/api/v2/silences

# Create silence
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "HighMemoryUsage", "isRegex": false}],
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt": "2024-01-01T12:00:00Z",
    "createdBy": "admin",
    "comment": "Maintenance window"
  }' \
  http://localhost:9093/api/v2/silences

# Delete silence
curl -X DELETE http://localhost:9093/api/v2/silence/{id}
```

### Status API

```bash
# Get cluster status
curl http://localhost:9093/api/v2/status
```

## License

- Chart: BSD 3-Clause License
- Alertmanager: Apache License 2.0

## Additional Resources

- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [API Documentation](https://prometheus.io/docs/alerting/latest/clients/)
- [Notification Templates](https://prometheus.io/docs/alerting/latest/notification_examples/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Alertmanager Version**: 0.27.0
