# RabbitMQ Backup & Recovery Guide

**Chart Version**: v0.4.0
**RabbitMQ Version**: 3.13+
**Last Updated**: 2025-12-09

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Methods](#backup-methods)
5. [Recovery Procedures](#recovery-procedures)
6. [Automation](#automation)
7. [Testing Backups](#testing-backups)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

This guide provides comprehensive backup and recovery procedures for RabbitMQ deployments using the ScriptonBasestar Helm chart.

### What Gets Backed Up

| Component | Priority | Size | Backup Frequency |
|-----------|----------|------|------------------|
| **Definitions** (exchanges, queues, bindings, vhosts, users, policies) | Critical | <10 MB | Every 6 hours |
| **Messages** (queue contents) | Important | Variable (GB-TB) | Daily or continuous |
| **Configuration** (rabbitmq.conf, enabled_plugins) | Important | <1 MB | On change |
| **Mnesia Database** (/var/lib/rabbitmq/mnesia) | Critical | 100 MB - 10 GB | Daily |

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|----------|---------------------|---------------------|
| **Definitions restore** | < 15 minutes | 6 hours |
| **Messages restore** | < 2 hours | 24 hours |
| **Configuration restore** | < 10 minutes | 24 hours |
| **Full disaster recovery** | < 1 hour | 24 hours |
| **Mnesia database restore** | < 30 minutes | 24 hours |

---

## Backup Strategy

### Recommended Approach

**4-Component Backup Strategy:**

1. **Definitions Export** (rabbitmqadmin) - **PRIMARY METHOD**
   - Exchanges, queues, bindings, vhosts, users, policies, parameters
   - JSON format, portable across RabbitMQ versions
   - Quick to backup and restore

2. **Message Backup** (shovel plugin or external consumer)
   - Queue contents (messages)
   - Optional: Use persistent queues with durable messages
   - Alternative: Use federation/shovel to replicate to backup cluster

3. **Configuration Backup** (ConfigMaps)
   - rabbitmq.conf, enabled_plugins
   - Kubernetes ConfigMaps and Secrets
   - Chart values.yaml

4. **Mnesia Database Backup** (PVC snapshot)
   - Complete RabbitMQ state (definitions + messages)
   - Fastest recovery method
   - Requires consistent snapshot (quiescent state)

### Backup Decision Matrix

| Scenario | Definitions | Messages | Configuration | Mnesia DB |
|----------|-------------|----------|---------------|-----------|
| **Development** | ✅ Daily | ❌ | ✅ On change | ❌ |
| **Staging** | ✅ Every 6h | ✅ Daily | ✅ On change | ✅ Daily |
| **Production** | ✅ Every 6h | ✅ Continuous | ✅ On change | ✅ Daily |
| **DR Testing** | ✅ | ✅ | ✅ | ✅ |

---

## Backup Components

### 1. Definitions Backup (Critical Priority)

**What**: Exchanges, queues, bindings, vhosts, users, policies, parameters

**Tools**: `rabbitmqadmin` (Management Plugin)

**Format**: JSON

**Size**: Typically <10 MB

**Procedure**:

```bash
# Set variables
NAMESPACE="default"
RELEASE_NAME="my-rabbitmq"
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="./backups/rabbitmq/$(date +%Y%m%d-%H%M%S)"

# Create backup directory
mkdir -p $BACKUP_DIR

# Export definitions via Management API
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json

# Copy from pod
kubectl cp -n $NAMESPACE $POD:/tmp/definitions.json \
  $BACKUP_DIR/definitions.json

# Cleanup
kubectl exec -n $NAMESPACE $POD -- rm /tmp/definitions.json

echo "Definitions backup saved to: $BACKUP_DIR/definitions.json"
```

**Alternative using rabbitmqadmin**:

```bash
# Install rabbitmqadmin on pod (if not present)
kubectl exec -n $NAMESPACE $POD -- \
  curl -o /usr/local/bin/rabbitmqadmin \
  http://localhost:15672/cli/rabbitmqadmin

kubectl exec -n $NAMESPACE $POD -- chmod +x /usr/local/bin/rabbitmqadmin

# Export definitions
kubectl exec -n $NAMESPACE $POD -- \
  rabbitmqadmin export /tmp/definitions.json

# Copy from pod
kubectl cp -n $NAMESPACE $POD:/tmp/definitions.json \
  $BACKUP_DIR/definitions.json
```

**What's Included**:
- Users and permissions
- Virtual hosts
- Exchanges (types: direct, fanout, topic, headers)
- Queues (durable, transient, auto-delete)
- Bindings (exchange-to-queue, exchange-to-exchange)
- Policies (HA, TTL, max-length, federation)
- Parameters (federation, shovel)

### 2. Messages Backup (Important Priority)

**What**: Queue contents (messages)

**Challenge**: RabbitMQ is designed for transient messaging, not long-term storage

**Options**:

#### Option A: Persistent Queues (Recommended for Production)

Configure durable queues with persistent messages:

```bash
# Declare durable queue
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl eval \
  'rabbit_amqqueue:declare({resource, <<"/">>, queue, <<"my-queue">>}, true, false, [], none, "guest").'

# Verify queue durability
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues name durable
```

With durable queues + persistent messages, messages survive restarts and are included in Mnesia database backups.

#### Option B: Shovel Plugin (Message Migration)

Use shovel to copy messages to another RabbitMQ instance:

```bash
# Enable shovel plugin
kubectl exec -n $NAMESPACE $POD -- rabbitmq-plugins enable rabbitmq_shovel

# Configure shovel via Management API
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  -X PUT http://localhost:15672/api/parameters/shovel/%2f/my-shovel \
  -H "Content-Type: application/json" \
  -d '{
    "value": {
      "src-uri": "amqp://localhost",
      "src-queue": "source-queue",
      "dest-uri": "amqp://backup-rabbitmq:5672",
      "dest-queue": "backup-queue"
    }
  }'
```

#### Option C: External Consumer Backup

Write custom consumer to dump messages:

```python
#!/usr/bin/env python3
import pika
import json

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

messages = []
for method_frame, properties, body in channel.consume('my-queue', auto_ack=False):
    messages.append({
        'body': body.decode(),
        'properties': {
            'content_type': properties.content_type,
            'delivery_mode': properties.delivery_mode,
            'headers': properties.headers
        }
    })
    channel.basic_ack(method_frame.delivery_tag)
    if method_frame.delivery_tag >= 1000:  # Limit
        break

with open('messages_backup.json', 'w') as f:
    json.dump(messages, f, indent=2)

connection.close()
```

#### Option D: Federation (Continuous Replication)

Configure upstream to backup cluster:

```bash
# Enable federation plugin
kubectl exec -n $NAMESPACE $POD -- rabbitmq-plugins enable rabbitmq_federation

# Configure upstream
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  -X PUT http://localhost:15672/api/parameters/federation-upstream/%2f/backup-upstream \
  -H "Content-Type: application/json" \
  -d '{
    "value": {
      "uri": "amqp://backup-rabbitmq:5672",
      "ack-mode": "on-confirm"
    }
  }'

# Configure policy for federation
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  -X PUT http://localhost:15672/api/policies/%2f/federate-all \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "^federated\\.",
    "definition": {
      "federation-upstream": "backup-upstream"
    },
    "apply-to": "exchanges"
  }'
```

### 3. Configuration Backup (Important Priority)

**What**: rabbitmq.conf, enabled_plugins, Kubernetes resources

**Procedure**:

```bash
# Backup ConfigMaps
kubectl get configmap -n $NAMESPACE $RELEASE_NAME -o yaml > \
  $BACKUP_DIR/configmap.yaml

# Backup Secrets (admin credentials)
kubectl get secret -n $NAMESPACE $RELEASE_NAME -o yaml > \
  $BACKUP_DIR/secret.yaml

# Backup PVC definition
kubectl get pvc -n $NAMESPACE $RELEASE_NAME -o yaml > \
  $BACKUP_DIR/pvc.yaml

# Backup Helm values
helm get values -n $NAMESPACE $RELEASE_NAME > \
  $BACKUP_DIR/helm-values.yaml

# Backup chart version
helm list -n $NAMESPACE -o json | jq '.[] | select(.name=="'$RELEASE_NAME'")' > \
  $BACKUP_DIR/chart-info.json
```

**Configuration files** (from ConfigMap):
```bash
# Extract rabbitmq.conf
kubectl get configmap -n $NAMESPACE $RELEASE_NAME \
  -o jsonpath='{.data.rabbitmq\.conf}' > $BACKUP_DIR/rabbitmq.conf

# Extract enabled_plugins
kubectl get configmap -n $NAMESPACE $RELEASE_NAME \
  -o jsonpath='{.data.enabled_plugins}' > $BACKUP_DIR/enabled_plugins
```

### 4. Mnesia Database Backup (Critical Priority)

**What**: Complete RabbitMQ internal database (definitions + messages + metadata)

**Location**: `/var/lib/rabbitmq/mnesia`

**Methods**:

#### Option A: PVC Snapshot (Fastest, Recommended)

```bash
# Create VolumeSnapshot (requires CSI driver with snapshot support)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rabbitmq-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: $RELEASE_NAME
EOF

# List snapshots
kubectl get volumesnapshot -n $NAMESPACE

# Verify snapshot
kubectl describe volumesnapshot -n $NAMESPACE rabbitmq-snapshot-YYYYMMDD-HHMMSS
```

#### Option B: Filesystem Copy (Hot Backup)

```bash
# Stop RabbitMQ (quiescent state)
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl stop_app

# Copy Mnesia database
kubectl exec -n $NAMESPACE $POD -- tar czf /tmp/mnesia-backup.tar.gz \
  -C /var/lib/rabbitmq mnesia

# Copy from pod
kubectl cp -n $NAMESPACE $POD:/tmp/mnesia-backup.tar.gz \
  $BACKUP_DIR/mnesia-backup.tar.gz

# Start RabbitMQ
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl start_app

echo "Mnesia backup saved to: $BACKUP_DIR/mnesia-backup.tar.gz"
```

**⚠️ Warning**: Stopping the app causes service interruption.

#### Option C: Restic Backup (PVC-based)

```bash
# Install restic (one-time setup)
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: restic-backup
  namespace: $NAMESPACE
spec:
  containers:
  - name: restic
    image: restic/restic:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
    env:
    - name: RESTIC_REPOSITORY
      value: "s3:https://s3.amazonaws.com/my-backup-bucket/rabbitmq"
    - name: RESTIC_PASSWORD
      value: "your-restic-password"
    - name: AWS_ACCESS_KEY_ID
      value: "your-access-key"
    - name: AWS_SECRET_ACCESS_KEY
      value: "your-secret-key"
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: $RELEASE_NAME
EOF

# Initialize restic repo (first time only)
kubectl exec -n $NAMESPACE restic-backup -- restic init

# Create backup
kubectl exec -n $NAMESPACE restic-backup -- restic backup /data

# List snapshots
kubectl exec -n $NAMESPACE restic-backup -- restic snapshots

# Cleanup
kubectl delete pod -n $NAMESPACE restic-backup
```

---

## Backup Methods

### Method 1: Definitions Export (Recommended for Quick Recovery)

**Pros**: Fast, portable, version-independent, human-readable JSON
**Cons**: Doesn't include messages
**Use Case**: Development, quick topology recovery

**Procedure**: See [Definitions Backup](#1-definitions-backup-critical-priority)

### Method 2: PVC Snapshot (Recommended for Production)

**Pros**: Fastest backup/restore, includes everything (definitions + messages)
**Cons**: Requires CSI driver with snapshot support, storage-specific
**Use Case**: Production, disaster recovery

**Procedure**: See [Mnesia Database Backup - Option A](#option-a-pvc-snapshot-fastest-recommended)

### Method 3: Mnesia Database Copy

**Pros**: Complete backup, works without CSI snapshots
**Cons**: Requires stopping RabbitMQ (downtime), slower than snapshots
**Use Case**: Development, testing, migration

**Procedure**: See [Mnesia Database Backup - Option B](#option-b-filesystem-copy-hot-backup)

### Method 4: Federation/Shovel (Continuous Replication)

**Pros**: Near-zero RPO, no service interruption
**Cons**: Requires second RabbitMQ cluster, complex setup
**Use Case**: High availability, zero data loss requirements

**Procedure**: See [Messages Backup - Option D](#option-d-federation-continuous-replication)

### Method 5: Restic (Incremental Backups to S3/MinIO)

**Pros**: Incremental backups, encryption, deduplication, S3 storage
**Cons**: Requires external storage (S3/MinIO), slower than snapshots
**Use Case**: Long-term backups, off-cluster storage

**Procedure**: See [Mnesia Database Backup - Option C](#option-c-restic-backup-pvc-based)

---

## Recovery Procedures

### 1. Restore Definitions Only

**Scenario**: Accidental deletion of queues/exchanges, topology corruption

**Procedure**:

```bash
# Upload definitions file to pod
kubectl cp $BACKUP_DIR/definitions.json \
  $NAMESPACE/$POD:/tmp/definitions.json

# Import definitions via Management API
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json

# Verify
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_vhosts
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_exchanges
```

**Alternative using rabbitmqadmin**:

```bash
kubectl cp $BACKUP_DIR/definitions.json \
  $NAMESPACE/$POD:/tmp/definitions.json

kubectl exec -n $NAMESPACE $POD -- \
  rabbitmqadmin import /tmp/definitions.json
```

**RTO**: < 15 minutes
**RPO**: Based on backup frequency (typically 6 hours)

### 2. Restore Messages (from external backup)

**Scenario**: Message loss, queue corruption

**Procedure** (using Python consumer):

```python
#!/usr/bin/env python3
import pika
import json

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

with open('messages_backup.json') as f:
    messages = json.load(f)

for msg in messages:
    channel.basic_publish(
        exchange='',
        routing_key='my-queue',
        body=msg['body'],
        properties=pika.BasicProperties(
            content_type=msg['properties'].get('content_type'),
            delivery_mode=msg['properties'].get('delivery_mode', 1),
            headers=msg['properties'].get('headers')
        )
    )

connection.close()
```

**RTO**: Variable (depends on message count)
**RPO**: Based on backup frequency (typically 24 hours)

### 3. Restore Configuration

**Scenario**: Lost ConfigMaps, incorrect configuration

**Procedure**:

```bash
# Restore ConfigMap
kubectl apply -f $BACKUP_DIR/configmap.yaml

# Restart RabbitMQ to apply configuration
kubectl rollout restart deployment -n $NAMESPACE $RELEASE_NAME

# Verify configuration
kubectl exec -n $NAMESPACE $POD -- cat /etc/rabbitmq/rabbitmq.conf
kubectl exec -n $NAMESPACE $POD -- cat /etc/rabbitmq/enabled_plugins
```

**RTO**: < 10 minutes
**RPO**: Based on configuration change tracking

### 4. Full Disaster Recovery (from PVC Snapshot)

**Scenario**: Complete cluster loss, data corruption, disaster

**Prerequisites**:
- VolumeSnapshot exists
- CSI driver supports snapshot restore
- Helm chart values backup available

**Procedure**:

```bash
# Step 1: Create PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rabbitmq-restored
  namespace: $NAMESPACE
spec:
  storageClassName: csi-snapclass
  dataSource:
    name: rabbitmq-snapshot-20251209-120000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Step 2: Restore Helm release with restored PVC
helm install $RELEASE_NAME scripton-charts/rabbitmq \
  -n $NAMESPACE \
  -f $BACKUP_DIR/helm-values.yaml \
  --set persistence.existingClaim=rabbitmq-restored

# Step 3: Verify RabbitMQ started
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=rabbitmq

# Step 4: Verify data
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_users
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl cluster_status

# Step 5: Verify messages (check queue depth)
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues name messages
```

**RTO**: < 1 hour (depends on PVC provisioning time)
**RPO**: Based on snapshot frequency (typically 24 hours)

### 5. Full Disaster Recovery (from Mnesia Backup)

**Scenario**: No VolumeSnapshots available, legacy backup

**Procedure**:

```bash
# Step 1: Deploy fresh RabbitMQ instance
helm install $RELEASE_NAME scripton-charts/rabbitmq \
  -n $NAMESPACE \
  -f $BACKUP_DIR/helm-values.yaml

# Step 2: Stop RabbitMQ application
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl stop_app

# Step 3: Clear existing Mnesia database
kubectl exec -n $NAMESPACE $POD -- rm -rf /var/lib/rabbitmq/mnesia/*

# Step 4: Upload backup
kubectl cp $BACKUP_DIR/mnesia-backup.tar.gz \
  $NAMESPACE/$POD:/tmp/mnesia-backup.tar.gz

# Step 5: Extract backup
kubectl exec -n $NAMESPACE $POD -- tar xzf /tmp/mnesia-backup.tar.gz \
  -C /var/lib/rabbitmq

# Step 6: Fix permissions
kubectl exec -n $NAMESPACE $POD -- chown -R 999:999 /var/lib/rabbitmq/mnesia

# Step 7: Start RabbitMQ
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl start_app

# Step 8: Verify
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl cluster_status
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues
```

**RTO**: < 1 hour
**RPO**: 24 hours

---

## Automation

### CronJob for Definitions Backup

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rabbitmq-definitions-backup
  namespace: default
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: rabbitmq-backup-sa
          containers:
          - name: backup
            image: curlimages/curl:latest
            command:
            - /bin/sh
            - -c
            - |
              set -e
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)
              BACKUP_DIR="/backups/definitions/$TIMESTAMP"
              mkdir -p $BACKUP_DIR

              # Export definitions
              curl -u ${RABBITMQ_USER}:${RABBITMQ_PASS} \
                http://rabbitmq:15672/api/definitions \
                -o $BACKUP_DIR/definitions.json

              echo "Backup completed: $BACKUP_DIR/definitions.json"
            env:
            - name: RABBITMQ_USER
              valueFrom:
                secretKeyRef:
                  name: rabbitmq
                  key: username
            - name: RABBITMQ_PASS
              valueFrom:
                secretKeyRef:
                  name: rabbitmq
                  key: password
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: rabbitmq-backups
          restartPolicy: OnFailure
```

### Backup Retention Script

```bash
#!/bin/bash
# cleanup-old-backups.sh
# Retains last 30 days of backups

BACKUP_ROOT="/backups/rabbitmq"
RETENTION_DAYS=30

find $BACKUP_ROOT -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Cleaned up backups older than $RETENTION_DAYS days"
```

### Upload to S3/MinIO

```bash
#!/bin/bash
# upload-to-s3.sh

BACKUP_DIR="/backups/rabbitmq/$(date +%Y%m%d-%H%M%S)"
S3_BUCKET="s3://my-backup-bucket/rabbitmq"

# Upload to S3
aws s3 sync $BACKUP_DIR $S3_BUCKET/$(basename $BACKUP_DIR) \
  --storage-class STANDARD_IA \
  --server-side-encryption AES256

echo "Backup uploaded to: $S3_BUCKET/$(basename $BACKUP_DIR)"
```

---

## Testing Backups

### Backup Validation Checklist

- [ ] Definitions backup file is valid JSON
- [ ] Definitions include all expected vhosts, exchanges, queues
- [ ] ConfigMap backup contains rabbitmq.conf and enabled_plugins
- [ ] Secret backup contains admin credentials
- [ ] PVC snapshot completed successfully
- [ ] Backup files are uploaded to remote storage (S3/MinIO)
- [ ] Backup retention policy is enforced
- [ ] Recovery procedure documented and tested quarterly

### Automated Backup Test Script

```bash
#!/bin/bash
# test-rabbitmq-backup.sh

set -e

NAMESPACE="default"
RELEASE_NAME="my-rabbitmq"
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')
BACKUP_DIR="./test-backup-$(date +%Y%m%d-%H%M%S)"

echo "=== RabbitMQ Backup Test ==="

# 1. Create test backup directory
mkdir -p $BACKUP_DIR
echo "✓ Created backup directory: $BACKUP_DIR"

# 2. Export definitions
kubectl exec -n $NAMESPACE $POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json
kubectl cp -n $NAMESPACE $POD:/tmp/definitions.json \
  $BACKUP_DIR/definitions.json
echo "✓ Exported definitions"

# 3. Validate JSON
if ! jq empty $BACKUP_DIR/definitions.json 2>/dev/null; then
  echo "✗ Invalid JSON in definitions backup"
  exit 1
fi
echo "✓ Validated definitions JSON"

# 4. Check required keys
REQUIRED_KEYS=("users" "vhosts" "permissions" "queues" "exchanges" "bindings")
for key in "${REQUIRED_KEYS[@]}"; do
  if ! jq -e ".$key" $BACKUP_DIR/definitions.json >/dev/null; then
    echo "✗ Missing required key: $key"
    exit 1
  fi
done
echo "✓ All required definition keys present"

# 5. Backup ConfigMaps
kubectl get configmap -n $NAMESPACE $RELEASE_NAME -o yaml > \
  $BACKUP_DIR/configmap.yaml
echo "✓ Backed up ConfigMap"

# 6. Backup Secrets
kubectl get secret -n $NAMESPACE $RELEASE_NAME -o yaml > \
  $BACKUP_DIR/secret.yaml
echo "✓ Backed up Secret"

# 7. Summary
echo ""
echo "=== Backup Test Summary ==="
echo "Backup location: $BACKUP_DIR"
echo "Definitions size: $(du -h $BACKUP_DIR/definitions.json | cut -f1)"
echo "ConfigMap size: $(du -h $BACKUP_DIR/configmap.yaml | cut -f1)"
echo "Secret size: $(du -h $BACKUP_DIR/secret.yaml | cut -f1)"
echo ""
echo "Queue count: $(jq '.queues | length' $BACKUP_DIR/definitions.json)"
echo "Exchange count: $(jq '.exchanges | length' $BACKUP_DIR/definitions.json)"
echo "User count: $(jq '.users | length' $BACKUP_DIR/definitions.json)"
echo "Vhost count: $(jq '.vhosts | length' $BACKUP_DIR/definitions.json)"
echo ""
echo "✓ All backup tests passed!"
```

---

## Troubleshooting

### Issue 1: Definitions Export Fails with 401 Unauthorized

**Symptoms**:
```
HTTP/1.1 401 Unauthorized
```

**Cause**: Incorrect admin credentials

**Solution**:
```bash
# Get correct credentials
kubectl get secret -n $NAMESPACE $RELEASE_NAME \
  -o jsonpath='{.data.username}' | base64 -d

kubectl get secret -n $NAMESPACE $RELEASE_NAME \
  -o jsonpath='{.data.password}' | base64 -d

# Use correct credentials in curl
kubectl exec -n $NAMESPACE $POD -- curl -u <username>:<password> \
  http://localhost:15672/api/definitions
```

### Issue 2: Mnesia Restore Fails with "Inconsistent Database"

**Symptoms**:
```
{error,{inconsistent_database,context,[{rabbitmq_management,{bad_return_value,{error,{load_error,{rabbitmq_management,...}}}}]}}
```

**Cause**: Mnesia database version mismatch, RabbitMQ version mismatch

**Solution**:
```bash
# Option 1: Use definitions export instead of Mnesia restore
# (Definitions are version-independent)

# Option 2: Match RabbitMQ versions exactly
# Check backup version
grep "version" $BACKUP_DIR/definitions.json

# Deploy matching version
helm install $RELEASE_NAME scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management  # Match backup version
```

### Issue 3: Messages Lost After Restore

**Symptoms**: Queues exist but are empty after restore

**Cause**: Non-durable queues or non-persistent messages

**Solution**:
```bash
# Ensure queues are durable
kubectl exec -n $NAMESPACE $POD -- rabbitmqctl list_queues name durable

# Configure durable queues and persistent messages
# In application code:
channel.queue_declare(queue='my-queue', durable=True)
channel.basic_publish(
    exchange='',
    routing_key='my-queue',
    body='message',
    properties=pika.BasicProperties(delivery_mode=2)  # Persistent
)
```

### Issue 4: PVC Snapshot Not Found

**Symptoms**:
```
VolumeSnapshot "rabbitmq-snapshot-..." not found
```

**Cause**: Snapshot deleted by retention policy, incorrect namespace

**Solution**:
```bash
# List all snapshots in namespace
kubectl get volumesnapshot -n $NAMESPACE

# Check snapshot status
kubectl describe volumesnapshot -n $NAMESPACE <snapshot-name>

# Verify VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# Create new snapshot if needed
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rabbitmq-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: $RELEASE_NAME
EOF
```

---

## Best Practices

### 1. Follow 3-2-1 Backup Rule

- **3** copies of data (original + 2 backups)
- **2** different storage media (PVC + S3)
- **1** off-site backup (S3/MinIO in different region)

**Example**:
```bash
# Local: PVC snapshot (on-cluster)
# Remote 1: S3 Standard (same region)
# Remote 2: S3 Glacier (different region)

# Upload definitions to S3
aws s3 cp $BACKUP_DIR/definitions.json \
  s3://my-backup-bucket/rabbitmq/definitions-$(date +%Y%m%d).json

# Replicate to second region
aws s3 sync s3://my-backup-bucket/rabbitmq \
  s3://my-backup-bucket-dr/rabbitmq \
  --source-region us-east-1 \
  --region eu-west-1
```

### 2. Test Restores Quarterly

Schedule quarterly disaster recovery drills:

```bash
# Q1, Q2, Q3, Q4: Full restore test
# - Deploy to separate namespace
# - Restore from latest backup
# - Verify data integrity
# - Measure RTO/RPO
# - Document lessons learned
```

### 3. Encrypt Backups

**At rest**:
```bash
# S3 server-side encryption
aws s3 cp $BACKUP_DIR/definitions.json \
  s3://my-backup-bucket/rabbitmq/ \
  --server-side-encryption AES256
```

**In transit**:
```bash
# GPG encryption before upload
gpg --encrypt --recipient backup@example.com \
  $BACKUP_DIR/definitions.json

aws s3 cp $BACKUP_DIR/definitions.json.gpg \
  s3://my-backup-bucket/rabbitmq/
```

### 4. Monitor Backup Health

**Prometheus metrics**:
```yaml
# rabbitmq_backup_last_success_timestamp_seconds
# rabbitmq_backup_duration_seconds
# rabbitmq_backup_size_bytes
```

**Alerts**:
```yaml
groups:
  - name: rabbitmq_backup
    rules:
      - alert: RabbitMQBackupFailed
        expr: time() - rabbitmq_backup_last_success_timestamp_seconds > 86400
        for: 1h
        annotations:
          summary: "RabbitMQ backup has not succeeded in 24 hours"
```

### 5. Document Recovery Procedures

Maintain runbook with:
- Step-by-step recovery procedures
- Contact information (on-call, management)
- Decision tree (which backup method to use)
- RTO/RPO commitments
- Escalation procedures

### 6. Automate Backup Validation

```bash
# Automated validation script
#!/bin/bash
BACKUP_DIR="/backups/rabbitmq/latest"

# Validate JSON
jq empty $BACKUP_DIR/definitions.json

# Check file size (should be >1KB)
SIZE=$(stat -f%z $BACKUP_DIR/definitions.json)
if [ $SIZE -lt 1024 ]; then
  echo "ERROR: Backup file too small"
  exit 1
fi

# Check timestamp (should be <24 hours old)
AGE=$(($(date +%s) - $(stat -f%m $BACKUP_DIR/definitions.json)))
if [ $AGE -gt 86400 ]; then
  echo "ERROR: Backup is stale"
  exit 1
fi

echo "Backup validation passed"
```

### 7. Use Persistent Queues for Critical Messages

```yaml
# Application configuration
rabbitmq:
  queues:
    - name: critical-queue
      durable: true          # Survives broker restart
      auto_delete: false
      arguments:
        x-max-length: 10000
```

**Publish persistent messages**:
```python
channel.basic_publish(
    exchange='',
    routing_key='critical-queue',
    body='important message',
    properties=pika.BasicProperties(
        delivery_mode=2  # Persistent (written to disk)
    )
)
```

---

## Summary

This guide provides comprehensive backup and recovery procedures for RabbitMQ deployments:

- **4 backup components**: Definitions, Messages, Configuration, Mnesia database
- **5 backup methods**: Definitions export, PVC snapshot, Mnesia copy, Federation/Shovel, Restic
- **5 recovery procedures**: Definitions restore, Message restore, Configuration restore, Full DR (snapshot), Full DR (Mnesia)
- **Automation examples**: CronJob, retention script, S3 upload
- **RTO/RPO targets**: < 1 hour / 24 hours (full DR)

**Recommended Production Setup**:
1. **Definitions backup** every 6 hours (automated CronJob)
2. **PVC snapshot** daily (VolumeSnapshot)
3. **Configuration backup** on every change (GitOps)
4. **Messages backup** via persistent queues + federation (continuous)
5. **Off-site backup** to S3/MinIO (3-2-1 rule)
6. **Quarterly DR drill** (full restore test)

For operational procedures, see the main [RabbitMQ README](../charts/rabbitmq/README.md).
