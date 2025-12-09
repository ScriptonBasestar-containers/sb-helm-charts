# Promtail Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.6.1](https://img.shields.io/badge/AppVersion-3.6.1-informational?style=flat-square)

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

## Backup & Recovery

Promtail is a **stateless log shipping agent** that does not store logs persistently. Backup focuses on configuration and positions file.

### Backup Strategy

| Component | Priority | Size | Recovery Time |
|-----------|----------|------|---------------|
| **Configuration** | Critical | < 10 KB | < 5 minutes |
| **Positions File** | Important | < 1 MB | < 10 minutes |
| **Kubernetes Manifests** | Critical | < 50 KB | < 15 minutes |

**RTO/RPO Targets:**
- **RTO (Recovery Time)**: < 30 minutes
- **RPO (Recovery Point)**: 0 (stateless, no data loss)

### Quick Backup Commands

```bash
# 1. Backup ConfigMap
kubectl get configmap -n default promtail-config -o yaml > promtail-config-backup.yaml

# 2. Backup Helm values
helm get values my-promtail -n default > promtail-values-backup.yaml

# 3. Backup Kubernetes manifests
helm get manifest my-promtail -n default > promtail-manifest-backup.yaml

# 4. Backup positions file (optional)
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- cat /run/promtail/positions.yaml > positions-backup.yaml
```

### Backup Methods

#### 1. ConfigMap Export (Recommended)

Export Promtail ConfigMap via `kubectl`:

```bash
kubectl get configmap -n default promtail-config -o yaml > promtail-config-backup.yaml
```

**Pros**: Simple, fast, version-controllable
**Cons**: Manual execution

#### 2. Git-Based Configuration Management (Best Practice)

Store `values.yaml` in Git repository:

```bash
# Deploy from Git
helm install my-promtail scripton-charts/promtail \
  -f https://raw.githubusercontent.com/myorg/promtail-config/main/values.yaml
```

**Pros**: Automatic version control, audit trail
**Cons**: Requires Git setup

#### 3. Positions File Backup (Optional)

Copy positions file from each Promtail pod:

```bash
PODS=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[*].metadata.name}')
for POD in $PODS; do
  kubectl exec -n default $POD -- cat /run/promtail/positions.yaml > positions-$POD.yaml
done
```

**Note**: Positions file prevents re-ingesting logs. If lost, Promtail will start reading from current position.

### Recovery Procedures

#### Configuration-Only Recovery

Restore Promtail ConfigMap:

```bash
# Restore ConfigMap
kubectl apply -f promtail-config-backup.yaml

# Restart Promtail pods
kubectl rollout restart daemonset/my-promtail -n default
kubectl rollout status daemonset/my-promtail -n default
```

**RTO**: < 5 minutes

#### Full Cluster Recovery

Reinstall Promtail using backed-up Helm values:

```bash
# Install from backup
helm install my-promtail scripton-charts/promtail \
  -f promtail-values-backup.yaml \
  -n default

# Verify deployment
kubectl get daemonset -n default my-promtail
kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

**RTO**: < 15 minutes

### Automated Backup (CronJob)

Deploy CronJob for daily configuration backups:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: promtail-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: promtail-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              kubectl get configmap -n default promtail-config -o yaml \
                > /backups/promtail/config-$TIMESTAMP.yaml
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: promtail-backup-pvc
```

For complete backup procedures and disaster recovery strategies, see [Promtail Backup Guide](../../docs/promtail-backup-guide.md).

---

## Security & RBAC

Promtail requires cluster-wide permissions to read pod logs from all nodes.

### RBAC Resources

This chart creates the following RBAC resources:

- **ServiceAccount**: Pod identity for Promtail DaemonSet
- **ClusterRole**: Cluster-wide permissions for log collection
- **ClusterRoleBinding**: Links ServiceAccount to ClusterRole

**Permissions Granted:**
- Read access to Nodes, Pods, Services, Endpoints (for service discovery)
- Read pod logs across all namespaces (required for log shipping)

### Configuration

```yaml
rbac:
  # Create RBAC resources
  create: true
  # Annotations to add to the ClusterRole and ClusterRoleBinding
  annotations:
    description: "Promtail log shipping agent"
```

### Security Best Practices

**DO:**
- ✅ Run Promtail as DaemonSet (one pod per node)
- ✅ Use readOnlyRootFilesystem (enabled by default)
- ✅ Enable TLS for Loki communication
- ✅ Limit log collection with pipeline stages
- ✅ Use NetworkPolicy to restrict traffic
- ✅ Rotate credentials regularly

**DON'T:**
- ❌ Grant write permissions to RBAC
- ❌ Disable RBAC in production
- ❌ Run Promtail with privileged: false (it needs to read host logs)
- ❌ Expose Promtail metrics publicly
- ❌ Store sensitive data in logs

### Pod Security Context

Default security context (restrictive):

```yaml
podSecurityContext:
  runAsUser: 0      # Required to read /var/log/pods
  runAsGroup: 0
  fsGroup: 0

securityContext:
  privileged: true  # Required for log access
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

**Note**: Promtail must run as root and with privileged mode to access host log paths (`/var/log/pods`).

### Network Policy

Restrict Promtail network traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: promtail-network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: promtail
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow Loki
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: loki
    ports:
    - protocol: TCP
      port: 3100
```

### TLS/SSL Configuration

Secure communication with Loki:

```yaml
promtail:
  client:
    url: "https://loki.example.com/loki/api/v1/push"
    tls_config:
      ca_file: /etc/promtail/tls/ca.crt
      cert_file: /etc/promtail/tls/client.crt
      key_file: /etc/promtail/tls/client.key
      insecure_skip_verify: false

  # Mount TLS certificates
  extraVolumes:
  - name: tls-certs
    secret:
      secretName: promtail-tls

  extraVolumeMounts:
  - name: tls-certs
    mountPath: /etc/promtail/tls
    readOnly: true
```

### RBAC Verification

Verify RBAC resources are created:

```bash
# Check ServiceAccount
kubectl get serviceaccount -n default my-promtail

# Check ClusterRole
kubectl get clusterrole | grep promtail

# Check ClusterRoleBinding
kubectl get clusterrolebinding | grep promtail

# Verify permissions
kubectl auth can-i get pods --as=system:serviceaccount:default:my-promtail
kubectl auth can-i list nodes --as=system:serviceaccount:default:my-promtail
```

---

## Operations

### Daily Operations

#### Shell Access

Access Promtail pod shell:

```bash
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n default $POD -- /bin/sh
```

#### Port Forwarding

Forward Promtail metrics port:

```bash
kubectl port-forward -n default svc/my-promtail 3101:3101
# Visit http://localhost:3101/metrics
```

#### View Logs

Check Promtail logs:

```bash
# All pods
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=100 -f

# Specific pod
kubectl logs -n default $POD --tail=100 -f

# Previous logs (after crash)
kubectl logs -n default $POD --previous
```

### Monitoring & Health Checks

#### Check DaemonSet Status

```bash
# DaemonSet overview
kubectl get daemonset -n default my-promtail

# Pod status
kubectl get pods -n default -l app.kubernetes.io/name=promtail -o wide

# Node distribution
kubectl get pods -n default -l app.kubernetes.io/name=promtail \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

#### Health Endpoints

Promtail exposes health endpoints on port 3101:

```bash
# Liveness probe
curl http://localhost:3101/ready

# Metrics
curl http://localhost:3101/metrics

# Targets (active scrape configs)
curl http://localhost:3101/service-discovery
```

#### Prometheus Metrics

Key metrics to monitor:

```promql
# Sent log entries
promtail_sent_entries_total

# Dropped log entries (due to errors)
promtail_dropped_entries_total

# Active targets (pods being scraped)
promtail_targets_active

# Bytes sent to Loki
promtail_sent_bytes_total

# Read bytes from files
promtail_read_bytes_total

# Encoding failures
promtail_encoding_failures_total
```

### Configuration Management

#### Update Promtail Configuration

```bash
# Method 1: Update via Helm values
helm upgrade my-promtail scripton-charts/promtail \
  --set promtail.client.url="http://new-loki:3100/loki/api/v1/push" \
  -n default

# Method 2: Update values.yaml
helm upgrade my-promtail scripton-charts/promtail \
  -f values-updated.yaml \
  -n default

# Verify ConfigMap updated
kubectl get configmap -n default promtail-config -o yaml

# Restart pods to pick up new config
kubectl rollout restart daemonset/my-promtail -n default
```

#### Validate Pipeline Stages

Test pipeline stages configuration:

```bash
# Export current config
kubectl get configmap -n default promtail-config -o yaml > config.yaml

# Validate YAML syntax
yamllint config.yaml

# Test with promtail CLI (if available)
# promtail -config.file=config.yaml -dry-run
```

### Maintenance Operations

#### Restart Promtail

```bash
# Rolling restart (no downtime)
kubectl rollout restart daemonset/my-promtail -n default
kubectl rollout status daemonset/my-promtail -n default

# Delete all pods (DaemonSet will recreate)
kubectl delete pods -n default -l app.kubernetes.io/name=promtail
```

#### Scale Resources

```bash
# Update resource limits
helm upgrade my-promtail scripton-charts/promtail \
  --set resources.limits.memory=256Mi \
  --set resources.requests.memory=128Mi \
  -n default
```

#### Clear Positions File

Reset positions file (will re-read logs from current position):

```bash
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')

# Delete positions file
kubectl exec -n default $POD -- rm /run/promtail/positions.yaml

# Restart pod
kubectl delete pod -n default $POD
```

### Troubleshooting

| Issue | Diagnosis Command | Common Cause |
|-------|------------------|--------------|
| **Pods CrashLoopBackOff** | `kubectl logs -n default $POD` | Config syntax error, Loki unreachable |
| **No logs in Loki** | `curl localhost:3101/metrics \| grep sent_entries` | Pipeline stage error, Loki down |
| **High memory usage** | `kubectl top pods -n default -l app.kubernetes.io/name=promtail` | Too many targets, positions file growth |
| **Loki connection errors** | `kubectl logs -n default $POD \| grep -i error` | Incorrect Loki URL, network policy blocking |

**Debug commands:**
```bash
# Check pod events
kubectl describe pod -n default $POD

# Check DaemonSet events
kubectl describe daemonset -n default my-promtail

# Check node resources
kubectl describe node <node-name>

# Test Loki connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://loki.default.svc.cluster.local:3100/loki/api/v1/push
```

### Makefile Targets

Common operational tasks are available via Makefile:

```bash
# Configuration validation
make -f make/ops/promtail.mk pt-validate-config

# Log shipping test
make -f make/ops/promtail.mk pt-test-log-shipping

# Backup configuration
make -f make/ops/promtail.mk pt-backup-config

# Port-forward to metrics
make -f make/ops/promtail.mk pt-port-forward

# Full backup
make -f make/ops/promtail.mk pt-full-backup
```

For complete operational procedures, see `make/ops/promtail.mk` or run:
```bash
make -f make/ops/promtail.mk help
```

---

## Upgrading

Promtail is **stateless** and supports rolling updates with minimal disruption.

### Upgrade Strategy

| Strategy | Downtime | Risk | Use Case |
|----------|----------|------|----------|
| **Rolling Update** | None | Low | Production upgrades |
| **Configuration-Only** | None | Low | Config changes only |
| **Blue-Green** | < 1 min | Very Low | Major version jumps |

### Pre-Upgrade Checklist

1. **Backup current configuration:**
```bash
helm get values my-promtail -n default > promtail-values-backup.yaml
kubectl get configmap -n default promtail-config -o yaml > promtail-config-backup.yaml
```

2. **Check version compatibility:**
   - Verify Promtail version is compatible with Loki version
   - Review [release notes](https://github.com/grafana/loki/releases)

3. **Test in staging:**
```bash
helm upgrade promtail-staging scripton-charts/promtail \
  --version 0.4.0 \
  -n staging
```

### Rolling Update (Recommended)

Upgrade with zero downtime:

```bash
# Upgrade to new version
helm upgrade my-promtail scripton-charts/promtail \
  --version 0.4.0 \
  --set image.tag=3.3.0 \
  -n default \
  --wait

# Monitor rollout
kubectl rollout status daemonset/my-promtail -n default

# Watch pod updates
watch kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

**Expected Timeline:**
- Node 1: 30s - 1min
- Node 2: 30s - 1min
- Node 3: 30s - 1min
- **Total**: 2-5 minutes (depends on node count)

### Configuration-Only Update

Update Promtail configuration without version change:

```bash
# Update values.yaml
vim values.yaml

# Apply configuration update
helm upgrade my-promtail scripton-charts/promtail \
  -f values.yaml \
  -n default

# Restart pods to pick up new config
kubectl rollout restart daemonset/my-promtail -n default
```

### Post-Upgrade Validation

Run post-upgrade checks:

```bash
# Check DaemonSet status
kubectl get daemonset -n default my-promtail

# Verify all pods are running
kubectl get pods -n default -l app.kubernetes.io/name=promtail

# Check Promtail version
kubectl get pods -n default -l app.kubernetes.io/name=promtail \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Verify logs are being sent
kubectl port-forward -n default svc/my-promtail 3101:3101
curl http://localhost:3101/metrics | grep promtail_sent_entries_total
```

### Rollback Procedures

#### Rollback via Helm History

```bash
# Check Helm history
helm history my-promtail -n default

# Rollback to previous revision
helm rollback my-promtail <REVISION> -n default

# Wait for rollback to complete
kubectl rollout status daemonset/my-promtail -n default
```

**RTO**: < 5 minutes

#### Rollback via Backup Restore

```bash
# Uninstall current release
helm uninstall my-promtail -n default

# Restore from backup
helm install my-promtail scripton-charts/promtail \
  --version 0.3.0 \
  -f promtail-values-backup.yaml \
  -n default
```

**RTO**: < 10 minutes

### Version-Specific Notes

#### Promtail 3.3.x
- **New**: OTel logs support
- **Memory**: 20-30% reduction
- **No breaking changes**

#### Promtail 3.0.x (Major Release)
- **Breaking**: Docker scrape config removed
- **Breaking**: Pipeline stage syntax changed (`stages` → `pipeline`)
- **Migration**: Review [Promtail 3.0 Migration Guide](https://grafana.com/docs/loki/latest/send-data/promtail/migration-3.0/)

### Upgrade Best Practices

**DO:**
- ✅ Keep Promtail within 2 minor versions of Loki
- ✅ Test upgrades in dev/staging first
- ✅ Review release notes before upgrading
- ✅ Backup configuration before upgrade
- ✅ Monitor rollout progress

**DON'T:**
- ❌ Use `latest` tag in production
- ❌ Skip testing in staging
- ❌ Ignore version compatibility with Loki
- ❌ Deploy untested configurations

### Makefile Upgrade Targets

```bash
# Pre-upgrade checks
make -f make/ops/promtail.mk pt-pre-upgrade-check

# Post-upgrade validation
make -f make/ops/promtail.mk pt-post-upgrade-check

# Rollback procedures
make -f make/ops/promtail.mk pt-upgrade-rollback
```

For complete upgrade procedures and version-specific notes, see [Promtail Upgrade Guide](../../docs/promtail-upgrade-guide.md).

---

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
**Promtail Version**: 3.6.1
