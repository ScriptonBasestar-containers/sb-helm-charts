# RabbitMQ Upgrade Guide

**Chart Version**: v0.4.0
**RabbitMQ Version**: 3.13+
**Last Updated**: 2025-12-09

## Table of Contents

1. [Overview](#overview)
2. [Supported Upgrade Paths](#supported-upgrade-paths)
3. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
4. [Upgrade Strategies](#upgrade-strategies)
5. [Version-Specific Notes](#version-specific-notes)
6. [Post-Upgrade Validation](#post-upgrade-validation)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

This guide provides comprehensive upgrade procedures for RabbitMQ deployments using the ScriptonBasestar Helm chart.

### Upgrade Strategies Summary

| Strategy | Downtime | Complexity | Use Case |
|----------|----------|------------|----------|
| **In-Place Upgrade** | 5-15 minutes | Low | Single-node, development |
| **Blue-Green Deployment** | < 1 minute | Medium | Production, zero-risk |
| **Cluster Rolling Upgrade** | None | High | Multi-node cluster (future) |
| **Backup & Restore** | 1-2 hours | Low | Major version jumps |

### Version Compatibility

| From Version | To Version | Strategy | Notes |
|--------------|------------|----------|-------|
| 3.12.x | 3.13.x | In-Place or Blue-Green | Feature parity maintained |
| 3.11.x | 3.12.x | In-Place or Blue-Green | Quorum queues improvements |
| 3.10.x | 3.11.x | In-Place or Blue-Green | Stream support added |
| 3.9.x | 3.13.x | Backup & Restore | Skip 2+ versions not recommended |

---

## Supported Upgrade Paths

### Direct Upgrade Paths (In-Place)

**RabbitMQ 3.12.x → 3.13.x**
- ✅ Direct upgrade supported
- ✅ Feature parity maintained
- ⚠️ Test plugins compatibility
- **Recommended**: Blue-Green deployment

**RabbitMQ 3.11.x → 3.12.x**
- ✅ Direct upgrade supported
- ✅ Quorum queues performance improvements
- ✅ Khepri metadata store (experimental in 3.13)
- **Recommended**: In-Place or Blue-Green

**RabbitMQ 3.10.x → 3.11.x**
- ✅ Direct upgrade supported
- ✅ Stream support added
- ⚠️ Test stream plugin if used
- **Recommended**: Blue-Green deployment

### Multi-Step Upgrade Paths

**RabbitMQ 3.9.x → 3.13.x**
- ❌ Direct upgrade NOT recommended
- ✅ Upgrade path: 3.9 → 3.10 → 3.11 → 3.12 → 3.13
- **Recommended**: Backup & Restore (export definitions, fresh install)

**RabbitMQ 3.8.x → 3.13.x**
- ❌ Direct upgrade NOT supported
- ✅ Upgrade path: 3.8 → 3.9 → 3.10 → 3.11 → 3.12 → 3.13
- **Recommended**: Backup & Restore

### Erlang Version Requirements

| RabbitMQ Version | Minimum Erlang | Recommended Erlang |
|------------------|----------------|-------------------|
| 3.13.x | 25.0 | 26.0+ |
| 3.12.x | 25.0 | 25.3+ |
| 3.11.x | 25.0 | 25.2+ |
| 3.10.x | 24.0 | 25.0+ |

**⚠️ Important**: The official RabbitMQ Docker image includes compatible Erlang version, no manual Erlang upgrade needed.

---

## Pre-Upgrade Checklist

### 1. Requirements Check

```bash
# Get current RabbitMQ version
kubectl exec -n default $POD -- rabbitmqctl version

# Check Erlang version
kubectl exec -n default $POD -- rabbitmqctl eval 'erlang:system_info(otp_release).'

# Verify cluster health
kubectl exec -n default $POD -- rabbitmqctl cluster_status
kubectl exec -n default $POD -- rabbitmqctl node_health_check

# Check all alarms cleared
kubectl exec -n default $POD -- rabbitmqctl alarm_status
```

**Expected output**: All nodes running, no alarms, status = ok

### 2. Backup All Components

**⚠️ CRITICAL**: Always backup before upgrading!

```bash
# Run full backup (via Makefile)
make -f make/ops/rabbitmq.mk rmq-full-backup

# Or manual backup
BACKUP_DIR="./backups/rabbitmq/pre-upgrade-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# 1. Backup definitions
kubectl exec -n default $POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json
kubectl cp default/$POD:/tmp/definitions.json $BACKUP_DIR/definitions.json

# 2. Backup configuration
kubectl get configmap my-rabbitmq -o yaml > $BACKUP_DIR/configmap.yaml
kubectl get secret my-rabbitmq -o yaml > $BACKUP_DIR/secret.yaml

# 3. Backup Helm values
helm get values my-rabbitmq > $BACKUP_DIR/helm-values.yaml

# 4. Create PVC snapshot (if supported)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rabbitmq-pre-upgrade-$(date +%Y%m%d-%H%M%S)
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: my-rabbitmq
EOF
```

### 3. Check Current State

```bash
# List all vhosts
kubectl exec -n default $POD -- rabbitmqctl list_vhosts

# List all queues and messages
kubectl exec -n default $POD -- rabbitmqctl list_queues name messages

# List all users
kubectl exec -n default $POD -- rabbitmqctl list_users

# List all enabled plugins
kubectl exec -n default $POD -- rabbitmq-plugins list -E

# Check connections
kubectl exec -n default $POD -- rabbitmqctl list_connections

# Check resource usage
kubectl exec -n default $POD -- rabbitmqctl status | grep -A 10 "Memory"
kubectl exec -n default $POD -- rabbitmqctl status | grep -A 5 "Disk"
```

### 4. Resource Availability

```bash
# Check node resources
kubectl top node

# Check namespace quota
kubectl describe quota -n default

# Verify storage capacity
kubectl describe pvc my-rabbitmq | grep "Capacity"

# Check for sufficient disk space
kubectl exec -n default $POD -- df -h /var/lib/rabbitmq
```

### 5. Application Preparation

- [ ] Notify application owners about maintenance window
- [ ] Configure application retry logic (connections will drop)
- [ ] Prepare monitoring dashboards (track queue depth, connections)
- [ ] Schedule upgrade during low-traffic period
- [ ] Have rollback plan ready

**Checklist**:
```
[ ] Current version documented
[ ] Target version verified
[ ] Erlang compatibility confirmed
[ ] Full backup completed and verified
[ ] Cluster health checked (all nodes healthy)
[ ] All alarms cleared
[ ] Queue depths recorded (baseline)
[ ] Resource availability verified
[ ] Applications configured for upgrade
[ ] Rollback procedure documented
```

---

## Upgrade Strategies

### Strategy 1: In-Place Upgrade (Single-Node)

**Best For**: Development, staging, single-node deployments
**Downtime**: 5-15 minutes
**Risk**: Medium (data preserved, brief outage)

#### Procedure

```bash
# 1. Pre-upgrade backup
make -f make/ops/rabbitmq.mk rmq-full-backup

# 2. Record current version
kubectl exec -n default $POD -- rabbitmqctl version > pre-upgrade-version.txt

# 3. Upgrade via Helm
helm upgrade my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management \
  --reuse-values

# 4. Wait for pod restart
kubectl rollout status deployment my-rabbitmq -n default

# 5. Verify upgrade
kubectl exec -n default $POD -- rabbitmqctl version
kubectl exec -n default $POD -- rabbitmqctl node_health_check

# 6. Verify data integrity
kubectl exec -n default $POD -- rabbitmqctl list_queues
kubectl exec -n default $POD -- rabbitmqctl list_users
```

**Expected Timeline**:
- Helm upgrade: 30 seconds
- Pod termination: 30 seconds
- Pod startup: 2-5 minutes
- Health checks: 1 minute
- **Total**: 5-10 minutes

### Strategy 2: Blue-Green Deployment

**Best For**: Production, zero-downtime requirement, risk mitigation
**Downtime**: < 1 minute (traffic switch only)
**Risk**: Low (instant rollback, parallel validation)

#### Procedure

```bash
# 1. Backup current deployment
make -f make/ops/rabbitmq.mk rmq-full-backup

# 2. Deploy "green" environment (new version)
helm install my-rabbitmq-green scripton-charts/rabbitmq \
  --namespace default \
  --set image.tag=3.13.1-management \
  --set fullnameOverride=rabbitmq-green \
  --set service.clusterIP=""  # Get new IP

# 3. Wait for green deployment
kubectl rollout status deployment rabbitmq-green -n default

# 4. Import definitions to green
kubectl cp ./backups/rabbitmq/latest/definitions.json \
  default/$GREEN_POD:/tmp/definitions.json

kubectl exec -n default $GREEN_POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json

# 5. Verify green deployment
kubectl exec -n default $GREEN_POD -- rabbitmqctl version
kubectl exec -n default $GREEN_POD -- rabbitmqctl list_queues
kubectl exec -n default $GREEN_POD -- rabbitmqctl list_users

# 6. Test green deployment
# - Connect test application to green service
# - Send test messages
# - Verify message routing
# - Check management UI

# 7. Switch traffic (update service or DNS)
kubectl patch service my-rabbitmq -n default \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"rabbitmq-green"}}}'

# 8. Monitor for 15-30 minutes
kubectl logs -f deployment/rabbitmq-green -n default
watch kubectl get pods -n default -l app.kubernetes.io/name=rabbitmq

# 9. Decommission blue deployment (after validation)
helm uninstall my-rabbitmq -n default
# Keep PVC for 7 days in case of rollback
```

**Traffic Switch Options**:

**Option A: Service Selector Patch** (recommended)
```bash
kubectl patch service my-rabbitmq -n default \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"rabbitmq-green"}}}'
```

**Option B: DNS Update** (if using external DNS)
```bash
# Update DNS record to point to green service IP
kubectl get svc rabbitmq-green -n default -o jsonpath='{.spec.clusterIP}'
```

**Option C: Ingress Update**
```bash
kubectl patch ingress rabbitmq -n default \
  -p '{"spec":{"rules":[{"host":"rabbitmq.example.com","http":{"paths":[{"path":"/","backend":{"service":{"name":"rabbitmq-green","port":{"number":15672}}}}]}}]}}'
```

### Strategy 3: Cluster Rolling Upgrade (Multi-Node)

**Best For**: Multi-node RabbitMQ cluster (future feature)
**Downtime**: None (requires clustering support)
**Risk**: Low (gradual upgrade, automatic failover)

**⚠️ Note**: This chart currently supports single-node deployments only. For production clustering, see:
- [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)
- [Bitnami RabbitMQ Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq)

**Future Procedure** (when clustering is supported):

```bash
# 1. Verify cluster health
kubectl exec -n default rabbitmq-0 -- rabbitmqctl cluster_status

# 2. Upgrade replicas one by one
for i in {2..0}; do
  echo "Upgrading rabbitmq-$i..."

  # Update StatefulSet partition
  kubectl patch statefulset rabbitmq -n default \
    -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":'$i'}}}}'

  # Wait for pod restart
  kubectl wait --for=condition=ready pod/rabbitmq-$i -n default --timeout=300s

  # Verify cluster health
  kubectl exec -n default rabbitmq-$i -- rabbitmqctl cluster_status

  # Wait 5 minutes before next node
  sleep 300
done

# 3. Final verification
kubectl exec -n default rabbitmq-0 -- rabbitmqctl cluster_status
```

### Strategy 4: Backup & Restore (Major Version Jumps)

**Best For**: Skipping multiple versions (3.9 → 3.13)
**Downtime**: 1-2 hours (depends on data size)
**Risk**: Medium (data export/import, thorough testing required)

#### Procedure

```bash
# 1. Export all definitions from old version
OLD_POD=$(kubectl get pods -n default -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n default $OLD_POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json

kubectl cp default/$OLD_POD:/tmp/definitions.json \
  ./backups/rabbitmq/definitions-v$(kubectl exec -n default $OLD_POD -- rabbitmqctl version).json

# 2. Drain queues (optional: export messages)
# If queue contents are critical, use shovel/consumer to backup messages
# See backup guide for message export procedures

# 3. Uninstall old version
helm uninstall my-rabbitmq -n default

# 4. Delete old PVC (after confirming backup)
kubectl delete pvc my-rabbitmq -n default

# 5. Install new version
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management \
  --set rabbitmq.admin.password='your-password'

# 6. Wait for deployment
kubectl rollout status deployment my-rabbitmq -n default

# 7. Import definitions
NEW_POD=$(kubectl get pods -n default -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')

kubectl cp ./backups/rabbitmq/definitions-v*.json \
  default/$NEW_POD:/tmp/definitions.json

kubectl exec -n default $NEW_POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json

# 8. Verify
kubectl exec -n default $NEW_POD -- rabbitmqctl version
kubectl exec -n default $NEW_POD -- rabbitmqctl list_vhosts
kubectl exec -n default $NEW_POD -- rabbitmqctl list_queues
kubectl exec -n default $NEW_POD -- rabbitmqctl list_users

# 9. Restore messages (if backed up)
# Use shovel or custom consumer to republish messages
```

---

## Version-Specific Notes

### RabbitMQ 3.13.x (Latest)

**Released**: November 2023

**Key Features**:
- Khepri metadata store (experimental, opt-in)
- Improved Quorum queues performance
- Enhanced stream plugin
- OAuth 2.0 enhancements
- Better observability (metrics, tracing)

**Breaking Changes**:
- ❌ None (backward compatible with 3.12.x)

**Plugin Changes**:
- ✅ `rabbitmq_stream` plugin improvements
- ✅ `rabbitmq_prometheus` additional metrics

**Upgrade Notes**:
```bash
# No special upgrade steps required from 3.12.x
# Test plugins thoroughly after upgrade

# Verify stream plugin (if used)
kubectl exec -n default $POD -- rabbitmq-plugins list | grep stream

# Check new metrics
kubectl exec -n default $POD -- curl http://localhost:15692/metrics | grep rabbitmq_stream
```

### RabbitMQ 3.12.x

**Released**: June 2023

**Key Features**:
- Quorum queues scalability improvements
- Classic queue v2 (CQv2) - optional new implementation
- Enhanced management plugin

**Breaking Changes**:
- ⚠️ Deprecated features removed (none affecting core functionality)

**Plugin Changes**:
- ✅ `rabbitmq_management` performance improvements
- ✅ `rabbitmq_prometheus` new metrics

**Upgrade Notes**:
```bash
# From 3.11.x: Direct upgrade supported

# Enable CQv2 (optional, for new queues)
kubectl exec -n default $POD -- rabbitmqctl eval \
  'application:set_env(rabbit, classic_queue_default_version, 2).'
```

### RabbitMQ 3.11.x

**Released**: September 2022

**Key Features**:
- Stream support (pub/sub with replay)
- Super Streams (partitioned streams)
- Improved memory management

**Breaking Changes**:
- ⚠️ `rabbitmq_federation` configuration format changes (minor)

**Plugin Changes**:
- ✅ `rabbitmq_stream` plugin (new)
- ✅ `rabbitmq_stream_management` plugin (new)

**Upgrade Notes**:
```bash
# From 3.10.x: Direct upgrade supported

# Enable stream plugin (if needed)
kubectl exec -n default $POD -- rabbitmq-plugins enable rabbitmq_stream

# Verify stream support
kubectl exec -n default $POD -- rabbitmqctl eval \
  'rabbit_stream:status().'
```

### RabbitMQ 3.10.x

**Released**: May 2022

**Key Features**:
- Improved Quorum queues (non-mirrored queues)
- Better memory management
- Enhanced metrics

**Breaking Changes**:
- ⚠️ Classic mirrored queues deprecated (use Quorum queues instead)

**Upgrade Notes**:
```bash
# From 3.9.x: Direct upgrade supported

# Migrate classic mirrored queues to Quorum queues (recommended)
kubectl exec -n default $POD -- rabbitmqctl list_queues name policy | \
  grep "ha-"  # Find mirrored queues

# Create Quorum queue equivalent
kubectl exec -n default $POD -- rabbitmqctl eval \
  'rabbit_amqqueue:declare({resource, <<"/">>, queue, <<"my-quorum-queue">>}, quorum, true, false, [], none, "guest").'
```

---

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# post-upgrade-check.sh

set -e

NAMESPACE="default"
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')

echo "=== RabbitMQ Post-Upgrade Validation ==="

# 1. Version check
echo "1. Checking RabbitMQ version..."
NEW_VERSION=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl version)
echo "   Version: $NEW_VERSION"

# 2. Node health
echo "2. Checking node health..."
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl node_health_check
echo "   ✓ Node healthy"

# 3. Cluster status (single-node should show 1 node)
echo "3. Checking cluster status..."
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl cluster_status

# 4. Alarm status
echo "4. Checking alarms..."
ALARMS=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl alarm_status)
if [[ "$ALARMS" == "[]" ]]; then
  echo "   ✓ No alarms"
else
  echo "   ⚠ Alarms present: $ALARMS"
fi

# 5. List vhosts
echo "5. Checking virtual hosts..."
VHOSTS=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_vhosts --quiet | wc -l)
echo "   Virtual hosts: $VHOSTS"

# 6. List queues
echo "6. Checking queues..."
QUEUES=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues --quiet | wc -l)
echo "   Queues: $QUEUES"

# 7. List users
echo "7. Checking users..."
USERS=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_users --quiet | wc -l)
echo "   Users: $USERS"

# 8. List enabled plugins
echo "8. Checking enabled plugins..."
kubectl exec -n $NAMESPACE $POD -- rabbitmq-plugins list -E

# 9. Management UI accessibility
echo "9. Checking Management UI..."
kubectl exec -n $NAMESPACE $POD -- curl -s http://localhost:15672/ | grep -q "RabbitMQ Management"
echo "   ✓ Management UI accessible"

# 10. Prometheus metrics
echo "10. Checking Prometheus metrics..."
METRICS=$(kubectl exec -n $NAMESPACE $POD -- curl -s http://localhost:15692/metrics | wc -l)
echo "   Metrics exported: $METRICS lines"

# 11. Erlang version
echo "11. Checking Erlang version..."
ERLANG=$(kubectl exec -n $NAMESPACE $POD -- rabbitmqctl eval 'erlang:system_info(otp_release).' | tr -d "'")
echo "   Erlang/OTP: $ERLANG"

echo ""
echo "=== Validation Complete ==="
```

### Manual Validation Checklist

```
[ ] RabbitMQ version matches target version
[ ] Node health check passes
[ ] Cluster status shows all nodes (1 for single-node)
[ ] No alarms present
[ ] All vhosts present (compare with pre-upgrade count)
[ ] All queues present (compare with pre-upgrade count)
[ ] All users present
[ ] Management UI accessible
[ ] Prometheus metrics exporting
[ ] Application connectivity verified (send/receive test messages)
[ ] Queue depths match baseline (no message loss)
[ ] Plugins enabled as expected
[ ] Performance metrics normal (CPU, memory, disk)
```

### Connectivity Test

```bash
# Test AMQP connection
kubectl run rabbitmq-test --rm -it --restart=Never \
  --image=python:3.11-slim \
  -- bash -c "
    pip install pika && python3 <<EOF
import pika

connection = pika.BlockingConnection(
    pika.ConnectionParameters('my-rabbitmq', 5672)
)
channel = connection.channel()
channel.queue_declare(queue='test-queue')
channel.basic_publish(exchange='', routing_key='test-queue', body='test message')
print('✓ Message published successfully')
connection.close()
EOF
"
```

---

## Rollback Procedures

### Rollback Option 1: Helm Rollback (In-Place Upgrade)

**Use Case**: Upgrade completed but issues found within hours
**RTO**: 10-15 minutes

```bash
# 1. Check rollback history
helm history my-rabbitmq -n default

# 2. Rollback to previous revision
helm rollback my-rabbitmq -n default

# 3. Wait for rollback
kubectl rollout status deployment my-rabbitmq -n default

# 4. Verify rollback
kubectl exec -n default $POD -- rabbitmqctl version
kubectl exec -n default $POD -- rabbitmqctl node_health_check

# 5. Restore definitions (if data lost)
kubectl cp ./backups/rabbitmq/latest/definitions.json \
  default/$POD:/tmp/definitions.json

kubectl exec -n default $POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json
```

### Rollback Option 2: Restore from Backup (Full Disaster Recovery)

**Use Case**: Data corruption, severe issues, backup required
**RTO**: 1-2 hours

```bash
# 1. Uninstall broken deployment
helm uninstall my-rabbitmq -n default

# 2. Delete corrupted PVC
kubectl delete pvc my-rabbitmq -n default

# 3. Restore from VolumeSnapshot (if available)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-rabbitmq
  namespace: default
spec:
  storageClassName: csi-snapclass
  dataSource:
    name: rabbitmq-pre-upgrade-20251209-120000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# 4. Reinstall RabbitMQ with old version
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.12.14-management \
  -f ./backups/rabbitmq/latest/helm-values.yaml

# 5. Verify restoration
kubectl exec -n default $POD -- rabbitmqctl version
kubectl exec -n default $POD -- rabbitmqctl list_queues
```

### Rollback Option 3: Blue-Green Rollback (Instant)

**Use Case**: Blue-Green deployment, green environment has issues
**RTO**: < 1 minute

```bash
# 1. Switch traffic back to blue
kubectl patch service my-rabbitmq -n default \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"my-rabbitmq"}}}'

# 2. Verify blue deployment serving traffic
kubectl get svc my-rabbitmq -n default -o wide

# 3. Decommission green deployment
helm uninstall my-rabbitmq-green -n default

# 4. Cleanup green PVC (after confirming rollback)
kubectl delete pvc rabbitmq-green -n default
```

---

## Troubleshooting

### Issue 1: Pod Fails to Start After Upgrade

**Symptoms**:
```
Error: CrashLoopBackOff
Pod logs: "init terminating in do_boot"
```

**Cause**: Mnesia database incompatibility, version mismatch

**Solution**:
```bash
# Option 1: Clear Mnesia database (DESTRUCTIVE - data loss)
kubectl exec -n default $POD -- rabbitmqctl stop_app
kubectl exec -n default $POD -- rabbitmqctl reset
kubectl exec -n default $POD -- rabbitmqctl start_app

# Import definitions to restore topology
kubectl cp ./backups/rabbitmq/latest/definitions.json \
  default/$POD:/tmp/definitions.json
kubectl exec -n default $POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json

# Option 2: Restore from PVC snapshot (preferred)
# See Rollback Option 2
```

### Issue 2: Plugin Compatibility Issues

**Symptoms**:
```
Plugin 'rabbitmq_my_plugin' is not compatible with RabbitMQ 3.13.x
```

**Cause**: Third-party plugin incompatible with new version

**Solution**:
```bash
# 1. Disable problematic plugin
kubectl exec -n default $POD -- rabbitmq-plugins disable rabbitmq_my_plugin

# 2. Check for plugin updates
# Visit https://www.rabbitmq.com/community-plugins.html

# 3. Update ConfigMap to remove plugin
kubectl edit configmap my-rabbitmq -n default
# Remove plugin from enabled_plugins list

# 4. Restart RabbitMQ
kubectl rollout restart deployment my-rabbitmq -n default
```

### Issue 3: Performance Degradation After Upgrade

**Symptoms**: Slower message processing, higher CPU/memory usage

**Cause**: Configuration changes, new features enabled by default

**Solution**:
```bash
# 1. Check resource usage
kubectl exec -n default $POD -- rabbitmqctl status | grep -A 20 "Memory"

# 2. Disable unnecessary features
# If CQv2 causing issues, revert to CQv1
kubectl exec -n default $POD -- rabbitmqctl eval \
  'application:set_env(rabbit, classic_queue_default_version, 1).'

# 3. Adjust memory threshold
kubectl exec -n default $POD -- rabbitmqctl eval \
  'application:set_env(rabbit, vm_memory_high_watermark, 0.6).'

# 4. Review and optimize queues
kubectl exec -n default $POD -- rabbitmqctl list_queues name messages consumers memory

# 5. Consider scaling resources
helm upgrade my-rabbitmq scripton-charts/rabbitmq \
  --set resources.limits.memory=2Gi \
  --set resources.limits.cpu=2000m \
  --reuse-values
```

### Issue 4: Connections Dropped During Upgrade

**Symptoms**: Application logs show connection errors

**Cause**: Expected during in-place upgrade (RabbitMQ restart)

**Solution**:
```bash
# Application-side: Configure retry logic
# Example (Python pika):

import pika
from pika.exceptions import AMQPConnectionError
import time

def connect_with_retry(max_retries=5, delay=5):
    for attempt in range(max_retries):
        try:
            connection = pika.BlockingConnection(
                pika.ConnectionParameters('my-rabbitmq', 5672)
            )
            return connection
        except AMQPConnectionError as e:
            if attempt < max_retries - 1:
                time.sleep(delay)
            else:
                raise

# For zero-downtime, use Blue-Green deployment strategy
```

---

## Best Practices

### 1. Plan Upgrades During Maintenance Windows

```bash
# Schedule during low-traffic period
# Example: 2 AM - 4 AM on Sunday

# Notify stakeholders 48 hours in advance
# Prepare rollback plan
# Have team on standby
```

### 2. Test Upgrades in Non-Production First

```bash
# Deploy staging environment
helm install rabbitmq-staging scripton-charts/rabbitmq \
  --namespace staging \
  --set image.tag=3.12.14-management

# Import production definitions
kubectl cp ./backups/rabbitmq/prod/definitions.json \
  staging/$POD:/tmp/definitions.json

# Test upgrade in staging
helm upgrade rabbitmq-staging scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management \
  --reuse-values

# Validate thoroughly before production upgrade
```

### 3. Always Backup Before Upgrading

```bash
# Automated pre-upgrade backup
cat <<'EOF' > pre-upgrade-backup.sh
#!/bin/bash
set -e

NAMESPACE="default"
RELEASE_NAME="my-rabbitmq"
BACKUP_DIR="./backups/rabbitmq/pre-upgrade-$(date +%Y%m%d-%H%M%S)"

mkdir -p $BACKUP_DIR

# Backup all components
make -f make/ops/rabbitmq.mk rmq-full-backup BACKUP_DIR=$BACKUP_DIR

# Create VolumeSnapshot
kubectl create -f - <<YAML
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $RELEASE_NAME-pre-upgrade-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: $RELEASE_NAME
YAML

echo "Pre-upgrade backup completed: $BACKUP_DIR"
EOF

chmod +x pre-upgrade-backup.sh
./pre-upgrade-backup.sh
```

### 4. Monitor During and After Upgrade

```bash
# Real-time monitoring during upgrade
watch -n 5 kubectl get pods -n default -l app.kubernetes.io/name=rabbitmq

# Check logs continuously
kubectl logs -f deployment/my-rabbitmq -n default

# Monitor metrics
kubectl port-forward svc/my-rabbitmq 15692:15692
watch curl -s http://localhost:15692/metrics | grep rabbitmq_queue_messages
```

### 5. Validate Thoroughly

```bash
# Run post-upgrade validation
./post-upgrade-check.sh

# Test application connectivity
kubectl run test-producer --rm -it --restart=Never --image=python:3.11-slim -- bash

# Monitor for 24 hours after upgrade
# Check for errors, performance issues, data inconsistencies
```

### 6. Document Everything

```markdown
# Upgrade Log Template

## Upgrade Details
- Date: 2025-12-09
- Engineer: John Doe
- From Version: 3.12.14
- To Version: 3.13.1
- Strategy: Blue-Green Deployment

## Pre-Upgrade State
- Queue count: 15
- Message count: 1,245
- User count: 5
- Vhost count: 2

## Timeline
- 02:00 - Pre-upgrade backup completed
- 02:15 - Green deployment started
- 02:20 - Definitions imported
- 02:30 - Traffic switched to green
- 02:35 - Validation completed
- 03:00 - Blue decommissioned

## Post-Upgrade State
- Queue count: 15 (verified)
- Message count: 1,245 (verified)
- User count: 5 (verified)
- Vhost count: 2 (verified)

## Issues Encountered
- None

## Rollback Plan
- Keep blue deployment for 7 days
- Keep PVC snapshot for 30 days
```

### 7. Use Blue-Green for Production

```bash
# Recommended production upgrade flow:
1. Deploy green environment (new version)
2. Import definitions to green
3. Test green thoroughly (15-30 minutes)
4. Switch traffic to green
5. Monitor for 24 hours
6. Decommission blue after validation
```

### 8. Keep Erlang Version Compatible

```bash
# Always use official RabbitMQ Docker images
# Erlang version is bundled and compatible

# Verify Erlang version after upgrade
kubectl exec -n default $POD -- rabbitmqctl eval \
  'io:format("Erlang/OTP ~s~n", [erlang:system_info(otp_release)]).'
```

---

## Summary

This guide provides comprehensive upgrade procedures for RabbitMQ deployments:

- **4 upgrade strategies**: In-Place (5-15 min), Blue-Green (<1 min), Cluster Rolling (future), Backup & Restore (1-2 hours)
- **Version compatibility**: Direct upgrade paths for 3.10.x → 3.13.x
- **Pre-upgrade checklist**: Requirements, backups, current state, resources, application prep
- **Version-specific notes**: 3.13.x (Khepri), 3.12.x (CQv2), 3.11.x (Streams), 3.10.x (Quorum queues)
- **Post-upgrade validation**: Automated script + manual checklist
- **3 rollback procedures**: Helm rollback, Backup restore, Blue-Green instant switch
- **Troubleshooting**: 4 common issues and solutions
- **Best practices**: 8 production-ready guidelines

**Recommended Production Setup**:
1. **Test in staging** first
2. **Full backup** before upgrade (definitions + PVC snapshot)
3. **Blue-Green deployment** for zero downtime
4. **Validate thoroughly** (automated + manual)
5. **Monitor for 24 hours** after upgrade
6. **Document** upgrade process and issues

For backup procedures, see the [RabbitMQ Backup Guide](rabbitmq-backup-guide.md).
For operational procedures, see the main [RabbitMQ README](../charts/rabbitmq/README.md).
