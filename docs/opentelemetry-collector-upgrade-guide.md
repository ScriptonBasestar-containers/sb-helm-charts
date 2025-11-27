# OpenTelemetry Collector - Comprehensive Upgrade Guide

## Table of Contents

1. [Overview](#overview)
2. [Pre-Upgrade Preparation](#pre-upgrade-preparation)
3. [Upgrade Strategies](#upgrade-strategies)
4. [Version-Specific Notes](#version-specific-notes)
5. [Post-Upgrade Validation](#post-upgrade-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive procedures for upgrading OpenTelemetry Collector deployments in Kubernetes environments. The Collector's stateless design makes upgrades straightforward, but proper procedures ensure zero data loss and minimal downtime.

### Upgrade Complexity

**Low Complexity:**
- Stateless architecture (no data persistence)
- Rolling update support (zero downtime)
- Backward-compatible OTLP protocol
- Configuration hot-reloading (for some changes)

**Considerations:**
- Breaking changes in configuration format
- New/deprecated receivers, processors, exporters
- Performance characteristics may change
- Resource requirements may change

### RTO/RPO During Upgrade

| Upgrade Method | Downtime | Data Loss Risk | Complexity |
|----------------|----------|----------------|------------|
| Rolling Update | None | None (buffering) | Low |
| Blue-Green | 10-30 seconds | None (dual-write) | Medium |
| Maintenance Window | 5-15 minutes | Possible (no buffering) | Low |

---

## Pre-Upgrade Preparation

### Step 1: Review Release Notes

**Check breaking changes:**
```bash
# View OpenTelemetry Collector releases
open https://github.com/open-telemetry/opentelemetry-collector/releases
open https://github.com/open-telemetry/opentelemetry-collector-contrib/releases

# Current version
kubectl get deployment -n monitoring otel-collector -o jsonpath='{.spec.template.spec.containers[0].image}'

# Target version
helm search repo scripton-charts/opentelemetry-collector --versions
```

**Key areas to review:**
- Configuration schema changes
- Deprecated/removed components
- New required permissions
- Performance improvements/regressions
- Security fixes

### Step 2: Backup Current Configuration

**Create full backup:**
```bash
# Using Makefile
make -f make/ops/opentelemetry-collector.mk otel-backup-all

# Manual backup
BACKUP_DIR=tmp/otel-collector-backups/backup-$(date +%Y%m%d-%H%M%S)
mkdir -p $BACKUP_DIR

kubectl get configmap -n monitoring otel-collector-opentelemetry-collector -o yaml > $BACKUP_DIR/configmap.yaml
kubectl get deployment -n monitoring otel-collector-opentelemetry-collector -o yaml > $BACKUP_DIR/deployment.yaml
helm get values otel-collector -n monitoring > $BACKUP_DIR/helm-values.yaml
```

### Step 3: Pre-Upgrade Health Check

**Run pre-upgrade validation:**
```bash
# Using Makefile
make -f make/ops/opentelemetry-collector.mk otel-pre-upgrade-check
```

**Manual health check:**
```bash
# 1. Check pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# 2. Check resource usage
kubectl top pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# 3. Check health endpoint
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $POD_NAME -- wget -qO- http://localhost:13133

# 4. Check OTLP receivers
kubectl exec -n monitoring $POD_NAME -- nc -zv localhost 4317  # gRPC
kubectl exec -n monitoring $POD_NAME -- wget -qO- http://localhost:4318  # HTTP

# 5. Check logs for errors
kubectl logs -n monitoring $POD_NAME --tail=100 | grep -i error

# 6. Check metrics export (if using Prometheus)
kubectl exec -n monitoring $POD_NAME -- wget -qO- http://localhost:8888/metrics | grep -i otelcol
```

### Step 4: Test in Staging

**Deploy target version in staging:**
```bash
# Create staging namespace
kubectl create namespace otel-staging

# Deploy new version
helm install otel-collector-staging scripton-charts/opentelemetry-collector \
  -n otel-staging \
  --version 0.4.0 \
  -f values-staging.yaml

# Send test data
kubectl run test-sender --rm -it --image=curlimages/curl:latest -- sh
# Inside pod:
curl -X POST http://otel-collector-staging.otel-staging.svc:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d '{"resourceSpans":[]}'

# Verify logs
kubectl logs -n otel-staging -l app.kubernetes.io/name=opentelemetry-collector --tail=50
```

### Step 5: Notify Stakeholders

**Upgrade communication template:**
```
Subject: OpenTelemetry Collector Upgrade - [DATE]

Upgrade Details:
- Current Version: 0.96.0
- Target Version: 0.100.0
- Method: Rolling Update (zero downtime)
- Scheduled: [DATE] [TIME]
- Duration: ~15 minutes

Impact:
- No expected downtime
- Brief telemetry buffering during pod restarts
- No configuration changes required

Rollback Plan:
- Helm rollback available within 1 hour
- Configuration backup: tmp/otel-collector-backups/backup-20250127-120000
```

---

## Upgrade Strategies

### Strategy 1: Rolling Update (Recommended)

**When to use:**
- Minor version upgrades (0.96.x → 0.97.x)
- No breaking configuration changes
- Production environment with HA setup

**Advantages:**
- Zero downtime
- Automatic rollback on failure
- Gradual traffic shift

**Prerequisites:**
```yaml
# Ensure multiple replicas for HA
replicaCount: 3

# Pod anti-affinity (optional but recommended)
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

**Upgrade procedure:**

**Step 1: Update Helm chart**
```bash
# Update Helm repository
helm repo update scripton-charts

# Check available versions
helm search repo scripton-charts/opentelemetry-collector --versions

# Upgrade with rolling update
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --version 0.4.0 \
  -f values-prod.yaml \
  --wait \
  --timeout 10m
```

**Step 2: Monitor rollout**
```bash
# Watch rollout status
kubectl rollout status deployment -n monitoring otel-collector-opentelemetry-collector --watch

# Monitor pod creation/termination
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --watch

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp' | grep otel-collector
```

**Step 3: Verify upgrade**
```bash
# Verify new version
kubectl get deployment -n monitoring otel-collector-opentelemetry-collector \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pods are running
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Test health endpoint
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- wget -qO- http://localhost:13133

# Check logs for startup errors
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --tail=50 --all-containers
```

### Strategy 2: Blue-Green Deployment

**When to use:**
- Major version upgrades (0.96.x → 0.100.x)
- Configuration changes required
- High-risk upgrades with easy rollback

**Advantages:**
- Instant rollback capability
- Full testing before cutover
- Minimal risk

**Disadvantages:**
- Requires 2x resources during upgrade
- Brief downtime during cutover (10-30 seconds)
- More complex orchestration

**Upgrade procedure:**

**Step 1: Deploy green environment**
```bash
# Deploy new version alongside existing (blue)
helm install otel-collector-green scripton-charts/opentelemetry-collector \
  -n monitoring \
  --version 0.4.0 \
  -f values-prod.yaml \
  --set fullnameOverride=otel-collector-green
```

**Step 2: Dual-write configuration**
```yaml
# Configure applications to send to both collectors
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.monitoring.svc:4317"  # Blue
  # Add green endpoint (temporary)
  - name: OTEL_EXPORTER_OTLP_ENDPOINT_GREEN
    value: "http://otel-collector-green.monitoring.svc:4317"
```

**Step 3: Validate green environment**
```bash
# Wait for green pods
kubectl wait --for=condition=ready pod -n monitoring -l app.kubernetes.io/name=opentelemetry-collector,release=otel-collector-green --timeout=5m

# Test green collector
kubectl exec -n monitoring deploy/otel-collector-green -- wget -qO- http://localhost:13133

# Verify telemetry flow
kubectl logs -n monitoring -l release=otel-collector-green --tail=100
```

**Step 4: Traffic cutover**
```bash
# Option A: Update Service selector
kubectl patch service otel-collector -n monitoring -p '{"spec":{"selector":{"release":"otel-collector-green"}}}'

# Option B: Swap service names
kubectl delete service otel-collector -n monitoring
kubectl get service otel-collector-green -n monitoring -o yaml | sed 's/otel-collector-green/otel-collector/g' | kubectl apply -f -
```

**Step 5: Decommission blue environment**
```bash
# Wait 1-2 hours to ensure stability
sleep 7200

# Remove old deployment
helm uninstall otel-collector -n monitoring

# Rename green to blue
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set fullnameOverride=otel-collector
```

### Strategy 3: Maintenance Window Upgrade

**When to use:**
- Single-replica deployments
- Breaking configuration changes
- Testing/development environments

**Advantages:**
- Simple procedure
- Clean upgrade path
- No complex orchestration

**Disadvantages:**
- Downtime required (5-15 minutes)
- Telemetry loss during upgrade

**Upgrade procedure:**

**Step 1: Stop data ingestion (optional)**
```bash
# Scale down applications sending telemetry
kubectl scale deployment my-app -n production --replicas=0
```

**Step 2: Upgrade Collector**
```bash
# Upgrade Helm release
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --version 0.4.0 \
  -f values.yaml \
  --wait \
  --timeout 10m
```

**Step 3: Verify and resume**
```bash
# Wait for pods
kubectl wait --for=condition=ready pod -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --timeout=5m

# Test collector
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- wget -qO- http://localhost:13133

# Resume applications
kubectl scale deployment my-app -n production --replicas=3
```

### Strategy 4: DaemonSet Upgrade

**When to use:**
- Agent mode deployments (per-node collectors)
- Node-level telemetry collection

**Advantages:**
- Automatic per-node rollout
- Node-by-node validation

**Upgrade procedure:**

**Step 1: Update DaemonSet**
```bash
# Upgrade via Helm
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --set mode=daemonset \
  --version 0.4.0 \
  -f values-agent.yaml
```

**Step 2: Monitor node-by-node rollout**
```bash
# Watch DaemonSet rollout
kubectl rollout status daemonset -n monitoring otel-collector-opentelemetry-collector --watch

# Check pods per node
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector -o wide

# Verify all nodes have new version
kubectl get daemonset -n monitoring otel-collector-opentelemetry-collector
```

---

## Version-Specific Notes

### Upgrading to 0.100.x

**Breaking changes:**
- `service.telemetry` configuration structure changed
- `zpages` extension removed (use `zpages` in extensions)

**Migration:**
```yaml
# Old configuration (< 0.100.0)
service:
  telemetry:
    logs:
      level: info
    metrics:
      level: detailed

# New configuration (>= 0.100.0)
service:
  telemetry:
    logs:
      level: info
    metrics:
      level: detailed
      address: :8888
```

### Upgrading to 0.96.x

**New features:**
- `connectorprofiles` for advanced pipeline routing
- Improved `k8sattributes` processor performance

**Recommended changes:**
```yaml
# Enable connector profiles
config:
  connectors:
    spanmetrics:
      histogram:
        explicit:
          buckets: [100us, 1ms, 2ms, 6ms, 10ms, 100ms, 250ms]
```

### Upgrading to 0.90.x

**Breaking changes:**
- `batch` processor timeout default changed from 200ms to 5s
- `memory_limiter` now required for production deployments

**Migration:**
```yaml
# Update batch processor
processors:
  batch:
    timeout: 5s  # Explicitly set (was 200ms)
    send_batch_size: 10000

  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
```

---

## Post-Upgrade Validation

### Automated Validation

**Run post-upgrade checks:**
```bash
# Using Makefile
make -f make/ops/opentelemetry-collector.mk otel-post-upgrade-check
```

### Manual Validation

**1. Version verification:**
```bash
# Check deployed version
kubectl get deployment -n monitoring otel-collector-opentelemetry-collector \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Helm release
helm list -n monitoring
helm get values otel-collector -n monitoring
```

**2. Health check:**
```bash
# Health endpoint
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- wget -qO- http://localhost:13133

# Response should be: {}
```

**3. OTLP receivers check:**
```bash
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')

# gRPC receiver (port 4317)
kubectl exec -n monitoring $POD_NAME -- nc -zv localhost 4317

# HTTP receiver (port 4318)
kubectl exec -n monitoring $POD_NAME -- wget -qO- http://localhost:4318
```

**4. Pipeline validation:**
```bash
# Check logs for pipeline start messages
kubectl logs -n monitoring $POD_NAME --tail=100 | grep -i pipeline

# Expected output:
# "Traces" pipeline enabled
# "Metrics" pipeline enabled
# "Logs" pipeline enabled
```

**5. Metrics export validation:**
```bash
# Check collector metrics
kubectl exec -n monitoring $POD_NAME -- wget -qO- http://localhost:8888/metrics | grep otelcol_receiver_accepted

# Expected metrics:
# otelcol_receiver_accepted_spans
# otelcol_receiver_accepted_metric_points
# otelcol_receiver_accepted_log_records
```

**6. Send test telemetry:**
```bash
# Send test span
kubectl run test-trace --rm -it --image=curlimages/curl:latest -- sh
# Inside pod:
curl -X POST http://otel-collector.monitoring.svc:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "test"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId": "0123456789abcdef0123456789abcdef",
          "spanId": "0123456789abcdef",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": "1640000000000000000",
          "endTimeUnixNano": "1640000001000000000"
        }]
      }]
    }]
  }'

# Check logs for processing
kubectl logs -n monitoring $POD_NAME --tail=50 | grep -i test-span
```

**7. Resource usage validation:**
```bash
# Check resource usage
kubectl top pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Compare with pre-upgrade baseline
```

**8. Error log check:**
```bash
# Check for errors in last 30 minutes
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector --since=30m | grep -i error
```

---

## Rollback Procedures

### Rollback Method 1: Helm Rollback

**When to use:**
- Helm-managed deployments
- Quick rollback needed
- Upgrade within last 24 hours

**Rollback procedure:**

**Step 1: Check Helm history**
```bash
helm history otel-collector -n monitoring
```

**Step 2: Identify target revision**
```bash
# Show values for previous revision
helm get values otel-collector -n monitoring --revision 2
```

**Step 3: Rollback**
```bash
# Rollback to previous revision
helm rollback otel-collector -n monitoring

# Or rollback to specific revision
helm rollback otel-collector 2 -n monitoring --wait --timeout 5m
```

**Step 4: Verify rollback**
```bash
# Check version
kubectl get deployment -n monitoring otel-collector-opentelemetry-collector \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Test health
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- wget -qO- http://localhost:13133
```

### Rollback Method 2: Configuration Rollback

**When to use:**
- Configuration issue (not version issue)
- Helm rollback not available

**Rollback procedure:**

**Step 1: Identify backup**
```bash
# List backups
ls -lt tmp/otel-collector-backups/config-*/

# Choose backup
RESTORE_DIR=tmp/otel-collector-backups/config-20250127-120000
```

**Step 2: Restore ConfigMap**
```bash
# Apply backup ConfigMap
kubectl apply -f $RESTORE_DIR/configmap.yaml
```

**Step 3: Restart pods**
```bash
# Restart deployment
kubectl rollout restart deployment -n monitoring otel-collector-opentelemetry-collector

# Wait for rollout
kubectl rollout status deployment -n monitoring otel-collector-opentelemetry-collector --timeout=5m
```

### Rollback Method 3: Full Disaster Recovery

**When to use:**
- Deployment deleted or corrupted
- Major failure requiring full restore

**Rollback procedure:**
```bash
# Use backup restore procedure
make -f make/ops/opentelemetry-collector.mk otel-restore-all BACKUP_DIR=tmp/otel-collector-backups/backup-20250127-120000
```

See [opentelemetry-collector-backup-guide.md](opentelemetry-collector-backup-guide.md) for detailed recovery procedures.

---

## Troubleshooting

### Issue 1: Pods Stuck in Pending

**Symptom:**
```
NAME                                                READY   STATUS    RESTARTS   AGE
otel-collector-opentelemetry-collector-xxx-yyy      0/1     Pending   0          5m
```

**Diagnosis:**
```bash
# Describe pod to see events
kubectl describe pod -n monitoring otel-collector-opentelemetry-collector-xxx-yyy

# Common causes:
# - Insufficient resources
# - PVC not available
# - Node selector mismatch
```

**Solution:**
```bash
# Check resource availability
kubectl describe nodes | grep -A 5 "Allocated resources"

# Adjust resource requests if needed
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=200Mi
```

### Issue 2: CrashLoopBackOff

**Symptom:**
```
NAME                                                READY   STATUS              RESTARTS   AGE
otel-collector-opentelemetry-collector-xxx-yyy      0/1     CrashLoopBackOff    5          10m
```

**Diagnosis:**
```bash
# Check logs
kubectl logs -n monitoring otel-collector-opentelemetry-collector-xxx-yyy --previous

# Common issues:
# - Invalid configuration
# - Missing exporter endpoints
# - Permission errors
```

**Solution:**
```bash
# Validate configuration
kubectl get configmap -n monitoring otel-collector-opentelemetry-collector -o jsonpath='{.data.otel-config\.yaml}' > otel-config.yaml
yamllint otel-config.yaml

# Check for typos in pipeline definitions
grep -A 10 "service:" otel-config.yaml

# Rollback if configuration is invalid
helm rollback otel-collector -n monitoring
```

### Issue 3: High Memory Usage

**Symptom:**
Memory usage exceeds limits, causing OOMKilled

**Diagnosis:**
```bash
# Check memory usage
kubectl top pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Check memory_limiter settings
kubectl get configmap -n monitoring otel-collector-opentelemetry-collector -o jsonpath='{.data.otel-config\.yaml}' | grep -A 5 memory_limiter
```

**Solution:**
```bash
# Increase memory limits
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set resources.limits.memory=4Gi \
  --set resources.requests.memory=2Gi

# Adjust memory_limiter
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set config.processors.memory_limiter.limit_percentage=75
```

### Issue 4: Telemetry Not Received

**Symptom:**
Applications sending telemetry but no data in backend

**Diagnosis:**
```bash
# Check receiver metrics
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- \
  wget -qO- http://localhost:8888/metrics | grep otelcol_receiver_accepted

# Check exporter metrics
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- \
  wget -qO- http://localhost:8888/metrics | grep otelcol_exporter_sent

# Check logs for export errors
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | grep -i "export.*error"
```

**Solution:**
```bash
# Test receiver connectivity from application
kubectl exec -n production my-app-xxx -- nc -zv otel-collector.monitoring.svc 4317

# Test exporter connectivity from collector
kubectl exec -n monitoring deploy/otel-collector-opentelemetry-collector -- nc -zv tempo.monitoring.svc 4317

# Enable debug exporter temporarily
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set config.exporters.debug.verbosity=detailed \
  --set config.service.pipelines.traces.exporters[+]=debug
```

### Issue 5: Permission Denied (RBAC)

**Symptom:**
```
error: failed to list *v1.Pod: pods is forbidden
```

**Diagnosis:**
```bash
# Check RBAC settings
kubectl get clusterrole otel-collector-opentelemetry-collector -o yaml
kubectl get clusterrolebinding otel-collector-opentelemetry-collector -o yaml

# Verify ServiceAccount
kubectl get serviceaccount -n monitoring otel-collector-opentelemetry-collector
```

**Solution:**
```bash
# Ensure RBAC is enabled
helm upgrade otel-collector scripton-charts/opentelemetry-collector \
  -n monitoring \
  --reuse-values \
  --set rbac.create=true \
  --set rbac.clusterRole=true

# Verify permissions
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:otel-collector-opentelemetry-collector
```

---

## Appendix: Upgrade Checklist

### Pre-Upgrade Checklist

- [ ] Review release notes for target version
- [ ] Identify breaking changes
- [ ] Backup current configuration
- [ ] Run pre-upgrade health check
- [ ] Test upgrade in staging environment
- [ ] Notify stakeholders
- [ ] Prepare rollback plan
- [ ] Schedule upgrade window (if needed)

### Upgrade Execution Checklist

- [ ] Verify backup is accessible
- [ ] Update Helm repository
- [ ] Perform upgrade (rolling/blue-green/maintenance)
- [ ] Monitor pod rollout
- [ ] Check for errors in logs
- [ ] Verify new version deployed

### Post-Upgrade Validation Checklist

- [ ] Verify version
- [ ] Health endpoint check
- [ ] OTLP receivers check
- [ ] Pipeline validation
- [ ] Metrics export validation
- [ ] Send test telemetry
- [ ] Resource usage validation
- [ ] Error log check
- [ ] Monitor for 30-60 minutes
- [ ] Document upgrade outcome

### Rollback Checklist (If Needed)

- [ ] Identify issue severity
- [ ] Decide on rollback method
- [ ] Execute rollback procedure
- [ ] Verify rollback success
- [ ] Check logs for errors
- [ ] Test telemetry flow
- [ ] Document rollback reason
- [ ] Plan corrective actions

---

**Document Version**: 1.0
**Last Updated**: 2025-01-27
**Maintained by**: ScriptonBasestar
**Related**: [opentelemetry-collector-backup-guide.md](opentelemetry-collector-backup-guide.md)
