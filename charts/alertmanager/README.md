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

## Backup & Recovery

### Backup Strategy

Alertmanager backup covers **4 components**:

| Component | Priority | Size | Backup Method |
|-----------|----------|------|---------------|
| **Configuration** | Critical | <10 KB | ConfigMap export |
| **Silences** | Important | <1 MB | API export via amtool |
| **Notification Templates** | Important | <100 KB | ConfigMap export |
| **Data Directory** | Secondary | <100 MB | PVC snapshot |

**Recovery Time Objective (RTO)**: < 30 minutes
**Recovery Point Objective (RPO)**: 1 hour

### Quick Backup Commands

```bash
# 1. Backup Configuration (ConfigMap)
kubectl get configmap my-alertmanager-config -n default -o yaml > alertmanager-config-backup.yaml

# 2. Backup Silences (via amtool)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > silences-backup.json

# 3. Backup Notification Templates (if using ConfigMap)
kubectl get configmap my-alertmanager-templates -n default -o yaml > templates-backup.yaml

# 4. Backup Data Directory (PVC snapshot)
kubectl get pvc -n default my-alertmanager-0 -o yaml > pvc-backup.yaml
# Create VolumeSnapshot (requires CSI driver with snapshot support)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: alertmanager-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: my-alertmanager-0
EOF
```

### Backup Automation

**Recommended**: Hourly backups for silences, daily backups for configuration.

```yaml
# CronJob for automated backups
apiVersion: batch/v1
kind: CronJob
metadata:
  name: alertmanager-backup
spec:
  schedule: "0 * * * *"  # Hourly
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Backup configuration
              kubectl get configmap my-alertmanager-config -n default -o yaml > /backup/config-$(date +%Y%m%d-%H%M%S).yaml

              # Backup silences via API
              POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
              kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > /backup/silences-$(date +%Y%m%d-%H%M%S).json

              # Clean up old backups (keep last 24)
              ls -t /backup/config-*.yaml | tail -n +25 | xargs rm -f
              ls -t /backup/silences-*.json | tail -n +25 | xargs rm -f
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: alertmanager-backup-pvc
          restartPolicy: OnFailure
```

### Recovery Procedures

#### 1. Configuration-Only Recovery

Restore alertmanager.yml configuration:

```bash
# Restore from backup
kubectl apply -f alertmanager-config-backup.yaml

# Reload configuration (if --web.enable-lifecycle is set)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget --post-data='' http://localhost:9093/-/reload

# Or restart pods
kubectl rollout restart statefulset/my-alertmanager -n default
```

#### 2. Silences Recovery

Restore silences via API:

```bash
# Get backup file
BACKUP_FILE="silences-backup.json"

# Extract and restore each silence
jq -c '.[]' $BACKUP_FILE | while read silence; do
  # Remove ID and status fields
  silence_data=$(echo $silence | jq 'del(.id, .status)')

  # Create silence via API
  POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n default $POD -- sh -c "wget --post-data='$silence_data' --header='Content-Type: application/json' http://localhost:9093/api/v2/silences"
done
```

#### 3. Full Cluster Recovery

Complete recovery for disaster scenarios:

```bash
# 1. Restore configuration
kubectl apply -f alertmanager-config-backup.yaml

# 2. Restore PVC (if using VolumeSnapshot)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-alertmanager-0
  namespace: default
spec:
  dataSource:
    name: alertmanager-snapshot-20240101-120000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF

# 3. Reinstall Alertmanager
helm upgrade --install my-alertmanager scripton-charts/alertmanager \
  -f values-prod.yaml \
  -n default

# 4. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n default --timeout=300s

# 5. Restore silences
# (Use silences recovery procedure above)

# 6. Verify recovery
kubectl exec -n default my-alertmanager-0 -- wget -qO- http://localhost:9093/api/v2/alerts
```

### Best Practices

1. **Git-based Configuration**: Store alertmanager.yml in Git repository
2. **Hourly Silence Backups**: Capture active silences regularly
3. **Test Recovery**: Quarterly restore testing in non-production
4. **Monitor Backup Jobs**: Alert on backup failures
5. **Off-cluster Storage**: Store backups outside the cluster (S3, MinIO)
6. **Retention Policy**: Keep 24 hourly + 7 daily + 4 weekly backups

**Detailed Guide**: See [docs/alertmanager-backup-guide.md](../../docs/alertmanager-backup-guide.md) for comprehensive backup procedures, automation examples, and disaster recovery workflows.

---

## Security & RBAC

### RBAC Configuration

The chart creates **namespace-scoped RBAC** resources for Alertmanager operations:

```yaml
rbac:
  create: true  # Enable RBAC resources
  annotations: {}
```

**Resources Created:**
- **Role**: Read-only access to ConfigMaps, Secrets, Pods, Services, Endpoints, PVCs
- **RoleBinding**: Binds ServiceAccount to Role

**Permissions Granted:**
- `get`, `list`, `watch` on ConfigMaps (for alertmanager.yml)
- `get`, `list`, `watch` on Secrets (for credentials like SMTP passwords)
- `get`, `list`, `watch` on Pods (for health checks and clustering)
- `get`, `list`, `watch` on Services/Endpoints (for service discovery)
- `get`, `list`, `watch` on PVCs (for storage operations)

### ServiceAccount

```yaml
serviceAccount:
  create: true
  name: ""  # Auto-generated if empty
  annotations: {}
```

### Security Context

**Pod-level security** (runs as non-root user 65534):

```yaml
podSecurityContext:
  runAsUser: 65534      # nobody user
  runAsNonRoot: true
  fsGroup: 65534

securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

### Network Security

**NetworkPolicy Example** (restrict ingress to Prometheus only):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: alertmanager-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from Prometheus
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - protocol: TCP
      port: 9093
  # Allow cluster gossip
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: alertmanager
    ports:
    - protocol: TCP
      port: 9094
    - protocol: UDP
      port: 9094
  egress:
  # Allow DNS
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
  # Allow SMTP
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 587
  # Allow webhook receivers
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 443
```

### Secret Management

**Sensitive configuration** (SMTP passwords, API tokens):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-secrets
type: Opaque
stringData:
  smtp-password: "your-smtp-password"
  slack-webhook-url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  pagerduty-service-key: "your-pagerduty-key"
```

**Reference in configuration:**

```yaml
config:
  global:
    smtp:
      authPassword: "${SMTP_PASSWORD}"  # From secret
    slackApiUrl: "${SLACK_WEBHOOK_URL}"
```

### Best Practices

1. **Least Privilege**: Use read-only RBAC permissions
2. **Secret Management**: Use Kubernetes Secrets or external secret managers (Vault, Sealed Secrets)
3. **Network Policies**: Restrict ingress to Prometheus and egress to receivers only
4. **TLS Encryption**: Enable TLS for Alertmanager web UI and API
5. **Pod Security Standards**: Enforce restricted pod security policy
6. **Audit Logging**: Enable Kubernetes audit logs for RBAC events

---

## Upgrading

### Pre-Upgrade Checklist

Before upgrading Alertmanager, complete these steps:

- [ ] **Review Release Notes**: Check [Alertmanager releases](https://github.com/prometheus/alertmanager/releases) for breaking changes
- [ ] **Backup Configuration**: Export current alertmanager.yml ConfigMap
- [ ] **Backup Silences**: Export active silences via API
- [ ] **Check Prometheus Compatibility**: Ensure Prometheus version is compatible
- [ ] **Test in Non-Production**: Validate upgrade in dev/staging environment
- [ ] **Schedule Maintenance Window**: Plan for brief downtime (if using single replica)

### Quick Upgrade (Patch Versions)

**Example: 0.27.0 → 0.27.1 (patch upgrade)**

```bash
# 1. Backup current configuration
kubectl get configmap my-alertmanager-config -n default -o yaml > alertmanager-config-backup.yaml

# 2. Upgrade via Helm
helm upgrade my-alertmanager scripton-charts/alertmanager \
  --set image.tag=v0.27.1 \
  -n default \
  --wait

# 3. Verify upgrade
kubectl rollout status statefulset/my-alertmanager -n default
kubectl exec -n default my-alertmanager-0 -- alertmanager --version
```

### Upgrade Strategies

#### 1. Rolling Update (HA Deployments)

**Recommended for**: Production clusters with `replicaCount >= 3`

**Downtime**: < 1 minute (brief traffic disruption during pod restarts)

```bash
# 1. Backup configuration and silences
kubectl get configmap my-alertmanager-config -n default -o yaml > config-backup.yaml
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > silences-backup.json

# 2. Upgrade via Helm
helm upgrade my-alertmanager scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  --set replicaCount=3 \
  --set podDisruptionBudget.enabled=true \
  --set podDisruptionBudget.minAvailable=2 \
  -n default \
  --wait

# 3. Monitor rollout
kubectl rollout status statefulset/my-alertmanager -n default

# 4. Verify cluster health
kubectl exec -n default my-alertmanager-0 -- wget -qO- http://localhost:9093/api/v2/status | jq '.cluster.peers'

# 5. Verify silences
kubectl exec -n default my-alertmanager-0 -- wget -qO- http://localhost:9093/api/v2/silences | jq 'length'
```

#### 2. Blue-Green Deployment

**Recommended for**: Major version upgrades or zero-downtime requirements

**Downtime**: None (traffic switch only)

```bash
# 1. Install new version (green)
helm install my-alertmanager-green scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  --set fullnameOverride=alertmanager-green \
  -f values-prod.yaml \
  -n default

# 2. Wait for green deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager-green -n default --timeout=300s

# 3. Restore configuration and silences to green
kubectl get configmap my-alertmanager-config -o yaml | sed 's/my-alertmanager/my-alertmanager-green/g' | kubectl apply -f -
# (Restore silences via API to green cluster)

# 4. Update Prometheus to point to green Alertmanager
# (Update Prometheus alerting.alertmanagers configuration)

# 5. Monitor for issues (15-30 minutes)

# 6. Remove blue deployment
helm uninstall my-alertmanager -n default
```

#### 3. Maintenance Window Upgrade

**Recommended for**: Single-replica deployments or major version upgrades

**Downtime**: 5-15 minutes (full restart)

```bash
# 1. Backup configuration and silences
kubectl get configmap my-alertmanager-config -n default -o yaml > config-backup.yaml
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > silences-backup.json

# 2. Uninstall old version
helm uninstall my-alertmanager -n default

# 3. Wait for complete cleanup
kubectl wait --for=delete pod -l app.kubernetes.io/name=alertmanager -n default --timeout=120s

# 4. Install new version
helm install my-alertmanager scripton-charts/alertmanager \
  --version 0.4.0 \
  --set image.tag=v0.27.0 \
  -f values-prod.yaml \
  -n default

# 5. Wait for new pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n default --timeout=300s

# 6. Verify configuration
kubectl exec -n default my-alertmanager-0 -- wget -qO- http://localhost:9093/api/v2/status

# 7. Restore silences
# (Use silences recovery procedure from Backup & Recovery section)
```

### Version-Specific Notes

#### Alertmanager 0.27.x

**New Features:**
- Native OpenTelemetry support
- Improved clustering performance
- Enhanced API v2 endpoints

**Breaking Changes:** None

**Configuration Changes:** None required

#### Alertmanager 0.26.x

**New Features:**
- Enhanced silence management
- Improved webhook retry logic
- New metrics for notification tracking

**Breaking Changes:** None

**Configuration Changes:**
```yaml
# New optional fields in receivers
receivers:
  - name: example
    webhook_configs:
      - url: "http://example.com/webhook"
        max_alerts: 0  # New: limit alerts per notification (0 = unlimited)
```

#### Alertmanager 0.25.x

**New Features:**
- Discord receiver support
- Telegram receiver support
- msteams receiver improvements

**Breaking Changes:** None

**Configuration Changes:**
```yaml
# New Discord receiver
receivers:
  - name: discord-alerts
    discord_configs:
      - webhook_url: "https://discord.com/api/webhooks/YOUR/WEBHOOK"
```

#### Alertmanager 0.24.x

**New Features:**
- Opsgenie v2 API support
- WeChat Work receiver
- SNS receiver improvements

**Breaking Changes:**
- Opsgenie API v1 deprecated (use v2)

**Configuration Changes:**
```yaml
# Opsgenie v2 API
receivers:
  - name: opsgenie
    opsgenie_configs:
      - api_key: "your-api-key"
        api_url: "https://api.opsgenie.com/"  # New default
```

#### API v1 to v2 Migration

**Alertmanager 0.16.0+** introduced API v2 (stable). API v1 is deprecated.

**Migration Guide:**

```bash
# Old (v1)
curl http://localhost:9093/api/v1/silences

# New (v2)
curl http://localhost:9093/api/v2/silences
```

**Changes:**
- Endpoint paths changed from `/api/v1/*` to `/api/v2/*`
- JSON schema changes (more structured)
- Better error handling and validation

### Post-Upgrade Validation

**Automated validation script:**

```bash
#!/bin/bash
# post-upgrade-validation.sh

NAMESPACE="default"
RELEASE="my-alertmanager"

echo "=== Alertmanager Post-Upgrade Validation ==="

# 1. Check pod status
echo "[1/6] Checking pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n $NAMESPACE --timeout=300s || exit 1

# 2. Check version
echo "[2/6] Checking Alertmanager version..."
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD -- alertmanager --version

# 3. Check API v2 health
echo "[3/6] Checking API v2 health..."
kubectl exec -n $NAMESPACE $POD -- wget -qO- http://localhost:9093/api/v2/status | jq '.versionInfo'

# 4. Check cluster status (HA mode)
echo "[4/6] Checking cluster status..."
REPLICAS=$(kubectl get statefulset -n $NAMESPACE -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].spec.replicas}')
if [ "$REPLICAS" -gt 1 ]; then
  kubectl exec -n $NAMESPACE $POD -- wget -qO- http://localhost:9093/api/v2/status | jq '.cluster.peers | length'
fi

# 5. Check configuration
echo "[5/6] Validating configuration..."
kubectl exec -n $NAMESPACE $POD -- wget -qO- http://localhost:9093/api/v2/status | jq '.config'

# 6. Check silences
echo "[6/6] Checking silences..."
SILENCES=$(kubectl exec -n $NAMESPACE $POD -- wget -qO- http://localhost:9093/api/v2/silences | jq 'length')
echo "Active silences: $SILENCES"

echo "=== Validation Complete ==="
```

**Manual Checks:**
- [ ] All pods are `Running` and `Ready`
- [ ] Alertmanager version matches expected version
- [ ] API v2 endpoints are responding
- [ ] Cluster peers are connected (HA mode)
- [ ] Configuration is valid
- [ ] Silences are preserved

### Rollback Procedures

#### 1. Helm Rollback

**Quick rollback** to previous release:

```bash
# List release history
helm history my-alertmanager -n default

# Rollback to previous revision
helm rollback my-alertmanager -n default

# Rollback to specific revision
helm rollback my-alertmanager 5 -n default

# Verify rollback
kubectl rollout status statefulset/my-alertmanager -n default
```

#### 2. Backup Restore

**Full restore** from backup:

```bash
# 1. Restore configuration
kubectl apply -f alertmanager-config-backup.yaml

# 2. Restart pods
kubectl rollout restart statefulset/my-alertmanager -n default

# 3. Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n default --timeout=300s

# 4. Restore silences
# (Use silences recovery procedure from Backup & Recovery section)
```

#### 3. Emergency Configuration Rollback

**In-place config rollback** (without pod restart):

```bash
# 1. Restore configuration
kubectl apply -f alertmanager-config-backup.yaml

# 2. Reload configuration (requires --web.enable-lifecycle)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- wget --post-data='' http://localhost:9093/-/reload

# 3. Verify configuration
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/status | jq '.config'
```

### Troubleshooting Upgrades

#### Issue: CrashLoopBackOff After Upgrade

**Symptoms:**
```bash
$ kubectl get pods -n default
NAME                 READY   STATUS             RESTARTS   AGE
my-alertmanager-0    0/1     CrashLoopBackOff   5          2m
```

**Solution:**
```bash
# Check logs
kubectl logs -n default my-alertmanager-0

# Common causes:
# 1. Invalid configuration
kubectl exec -n default my-alertmanager-0 -- alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check

# 2. Corrupted data directory
kubectl exec -n default my-alertmanager-0 -- ls -la /alertmanager

# 3. Rollback to previous version
helm rollback my-alertmanager -n default
```

#### Issue: Silences Lost After Upgrade

**Symptoms:** Active silences are missing after upgrade.

**Solution:**
```bash
# Restore silences from backup
BACKUP_FILE="silences-backup.json"
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')

jq -c '.[]' $BACKUP_FILE | while read silence; do
  silence_data=$(echo $silence | jq 'del(.id, .status)')
  kubectl exec -n default $POD -- sh -c "wget --post-data='$silence_data' --header='Content-Type: application/json' http://localhost:9093/api/v2/silences"
done
```

#### Issue: Cluster Peers Not Connecting

**Symptoms:** HA cluster shows only 1 peer instead of 3.

**Solution:**
```bash
# Check StatefulSet status
kubectl get statefulset -n default

# Check headless service
kubectl get svc -n default my-alertmanager-headless

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup my-alertmanager-0.my-alertmanager-headless.default.svc.cluster.local

# Check gossip port (9094)
kubectl exec -n default my-alertmanager-0 -- netstat -tuln | grep 9094

# Restart StatefulSet
kubectl rollout restart statefulset/my-alertmanager -n default
```

### Best Practices

1. **Version Management**:
   - Follow semantic versioning (patch → minor → major)
   - Test minor/major upgrades in non-production first
   - Avoid skipping multiple major versions

2. **Configuration Management**:
   - Store alertmanager.yml in Git repository
   - Use GitOps workflows (ArgoCD, Flux) for automated deployments
   - Validate configuration changes before applying

3. **Rollout Strategy**:
   - Use rolling updates for HA deployments (`replicaCount >= 3`)
   - Enable PodDisruptionBudget (`minAvailable: 2` for 3 replicas)
   - Monitor alerts during upgrade window

4. **Monitoring**:
   - Set up alerts for upgrade failures
   - Monitor pod restart counts
   - Track API latency metrics

**Detailed Guide**: See [docs/alertmanager-upgrade-guide.md](../../docs/alertmanager-upgrade-guide.md) for comprehensive upgrade procedures, version-specific notes, and advanced rollback strategies.

---

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
