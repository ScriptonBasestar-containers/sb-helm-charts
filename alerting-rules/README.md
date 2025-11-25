# Alerting Rules

Pre-configured PrometheusRule templates for the sb-helm-charts observability stack.

## Overview

This directory contains PrometheusRule CRD manifests for Prometheus Operator. These rules can also be used with standalone Prometheus by extracting the rule groups.

## Available Rule Sets

| File | Component | Alerts |
|------|-----------|--------|
| `prometheus-alerts.yaml` | Prometheus | Target down, config reload, TSDB, scraping |
| `kubernetes-alerts.yaml` | Kubernetes | Nodes, pods, deployments, storage, API server |
| `loki-alerts.yaml` | Loki + Promtail | Ingestion, queries, storage, health |
| `tempo-alerts.yaml` | Tempo | Span ingestion, queries, compaction |
| `mimir-alerts.yaml` | Mimir | Ingestion, queries, storage, limits |

## Installation

### With Prometheus Operator

```bash
# Install all rules
kubectl apply -f alerting-rules/ -n monitoring

# Install specific rules
kubectl apply -f alerting-rules/prometheus-alerts.yaml -n monitoring
kubectl apply -f alerting-rules/kubernetes-alerts.yaml -n monitoring
```

### With Helm (using Prometheus chart)

Reference the rules in your Prometheus values:

```yaml
prometheus:
  ruleFiles:
    - /etc/prometheus/rules/*.yml

  extraVolumes:
    - name: alerting-rules
      configMap:
        name: alerting-rules

  extraVolumeMounts:
    - name: alerting-rules
      mountPath: /etc/prometheus/rules
```

Create a ConfigMap from the rule files:

```bash
kubectl create configmap alerting-rules \
  --from-file=alerting-rules/ \
  -n monitoring
```

### With Standalone Prometheus

Extract rule groups from the YAML files and add to your prometheus.yml:

```yaml
rule_files:
  - /etc/prometheus/rules/*.yml
```

## Severity Levels

| Severity | Description | Typical Response |
|----------|-------------|------------------|
| `critical` | Service down, data loss risk | Immediate action required |
| `warning` | Degraded performance, capacity issues | Investigate within hours |
| `info` | Informational, non-urgent | Review during business hours |

## Customization

### Adjusting Thresholds

Edit the `expr` field to change alert thresholds:

```yaml
# Original: Alert when memory usage > 80%
expr: |
  container_memory_usage_bytes{container="prometheus"} /
  container_spec_memory_limit_bytes{container="prometheus"} > 0.8

# Modified: Alert when memory usage > 90%
expr: |
  container_memory_usage_bytes{container="prometheus"} /
  container_spec_memory_limit_bytes{container="prometheus"} > 0.9
```

### Adjusting Alert Duration

Edit the `for` field to change how long a condition must be true:

```yaml
# Original: Alert after 5 minutes
for: 5m

# Modified: Alert after 10 minutes
for: 10m
```

### Adding Labels

Add custom labels for routing:

```yaml
labels:
  severity: warning
  team: platform
  environment: production
```

### Disabling Specific Alerts

Remove or comment out unwanted alerts. Alternatively, use relabeling in Alertmanager:

```yaml
route:
  routes:
    - match:
        alertname: PrometheusScrapesSlow
      receiver: 'null'  # Silence this alert
```

## Alertmanager Configuration

### Example Routing

```yaml
route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'

  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true

    - match:
        severity: warning
      receiver: 'slack'

receivers:
  - name: 'default'
    email_configs:
      - to: 'alerts@example.com'

  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<key>'

  - name: 'slack'
    slack_configs:
      - api_url: '<webhook-url>'
        channel: '#alerts'

  - name: 'null'
```

### Inhibition Rules

Reduce noise by suppressing related alerts:

```yaml
inhibit_rules:
  # If critical, suppress warnings for same alertname
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'namespace']

  # If node is down, suppress all pod alerts on that node
  - source_match:
      alertname: 'KubernetesNodeNotReady'
    target_match_re:
      alertname: 'KubernetesPod.*'
    equal: ['node']
```

## Testing Alerts

### Validate Rules Syntax

```bash
# Using promtool
promtool check rules alerting-rules/*.yaml

# Using kubectl (for PrometheusRule CRD)
kubectl apply --dry-run=client -f alerting-rules/ -n monitoring
```

### Test Alert Expressions

```bash
# Port-forward to Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Test expression in Prometheus UI
# Navigate to http://localhost:9090/graph
# Enter the expression from the rule
```

### Generate Test Alerts

```bash
# Create a test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "Test alert"
    }
  }]'
```

## Runbook Links

Many alerts include `runbook_url` annotations pointing to:

- [Prometheus Operator Runbooks](https://runbooks.prometheus-operator.dev/runbooks/)
- [Kubernetes Runbooks](https://runbooks.prometheus-operator.dev/runbooks/kubernetes/)

Create custom runbooks and update the `runbook_url` annotation:

```yaml
annotations:
  summary: "Custom alert"
  runbook_url: "https://wiki.example.com/runbooks/custom-alert"
```

## Dependencies

### Required Metrics Sources

| Rule Set | Required Components |
|----------|---------------------|
| `prometheus-alerts.yaml` | Prometheus with self-scraping |
| `kubernetes-alerts.yaml` | kube-state-metrics, node-exporter |
| `loki-alerts.yaml` | Loki, Promtail with metrics |
| `tempo-alerts.yaml` | Tempo with metrics |
| `mimir-alerts.yaml` | Mimir with metrics |

### Chart Configuration

Enable ServiceMonitor in chart values:

```yaml
# Prometheus chart
serviceMonitor:
  enabled: true

# Loki chart
monitoring:
  serviceMonitor:
    enabled: true
```

## Best Practices

1. **Start with defaults**: Use these rules as-is initially
2. **Tune gradually**: Adjust thresholds based on your workload
3. **Document changes**: Comment why thresholds were changed
4. **Test in staging**: Validate rule changes before production
5. **Review regularly**: Audit alerts monthly for noise vs. signal

## Additional Resources

- [Prometheus Alerting Overview](https://prometheus.io/docs/alerting/latest/overview/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [PrometheusRule CRD](https://prometheus-operator.dev/docs/user-guides/alerting/)
- [Awesome Prometheus Alerts](https://awesome-prometheus-alerts.grep.to/)
