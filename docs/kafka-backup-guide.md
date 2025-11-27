# Kafka Backup & Recovery Guide

Comprehensive guide for backing up and restoring Kafka message broker including topic metadata, configurations, consumer offsets, and data volumes.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Procedures](#backup-procedures)
- [Recovery Procedures](#recovery-procedures)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Components

Kafka backup consists of five critical components:

1. **Topic Metadata** (topic names, partitions, replication factor, configs)
   - Exported via `kafka-topics --describe`
   - Stored as text files
   - Critical for topic recreation

2. **Broker Configurations** (broker settings, topic-level configs)
   - Exported via `kafka-configs --describe`
   - Broker-level and topic-level configs
   - Required for exact configuration restoration

3. **Data Volumes** (actual message data in log.dirs)
   - Backed up via PVC VolumeSnapshots or disk-level backups
   - Largest component by size
   - Contains actual Kafka log segments

4. **Consumer Group Offsets** (consumer position tracking)
   - Exported via `kafka-consumer-groups --describe`
   - Critical for application state recovery
   - Prevents message reprocessing or data loss

5. **ACLs** (access control lists - if SASL enabled)
   - Exported via `kafka-acls --list`
   - Security and authorization rules
   - Required if using Kafka authentication

### Why All Five?

- **Topic metadata**: Fast recreation of topic structure
- **Broker configs**: Exact configuration restoration
- **Data volumes**: Actual message data and log segments
- **Consumer offsets**: Application state and progress tracking
- **ACLs**: Security and access control preservation
- **Combined**: Maximum data safety and complete disaster recovery capability

---

## Backup Strategy

### Recommended Backup Schedule

| Environment | Metadata | Configs | Data Volumes | Offsets | Retention |
|-------------|----------|---------|--------------|---------|-----------|
| **Production** | Daily (2 AM) | Daily (2 AM) | Daily (2 AM) | Daily (2 AM) | 30 days |
| **Staging** | Weekly | Weekly | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | On-demand | On-demand | 7 days |

### Storage Locations

```
tmp/kafka-backups/
├── topics/                     # Topic metadata
│   ├── 20251127-020000/
│   │   └── topics-metadata.txt
│   └── 20251126-020000/
├── configs/                    # Broker and topic configurations
│   ├── 20251127-020000/
│   │   ├── broker-configs.txt
│   │   └── topic-configs.txt
│   └── 20251126-020000/
└── offsets/                    # Consumer group offsets
    ├── 20251127-020000/
    │   ├── consumer-groups-list.txt
    │   └── offsets-{group}.txt
    └── 20251126-020000/
```

### RTO/RPO Targets

| Component | Recovery Time Objective (RTO) | Recovery Point Objective (RPO) |
|-----------|-------------------------------|--------------------------------|
| Metadata | < 10 minutes | 24 hours (daily backup) |
| Configurations | < 10 minutes | 24 hours (daily backup) |
| Data Volumes | < 4 hours | 24 hours (daily backup) |
| Consumer Offsets | < 20 minutes | 24 hours (daily backup) |
| **Full System** | **< 4 hours** | **24 hours** |

---

## Backup Procedures

### 1. Backup Topic Metadata

**Export all topic metadata:**

```bash
make -f make/ops/kafka.mk kafka-topics-backup
```

**What it does:**
1. Executes `kafka-topics --describe` in Kafka broker pod
2. Exports topic names, partition counts, replication factors, configs
3. Saves to local `tmp/kafka-backups/topics/<timestamp>/`

**Expected output:**
```
Backing up Kafka topic metadata...
Exporting all topics metadata...
✓ Topics backup completed: tmp/kafka-backups/topics/20251127-143022
```

**Manual export (alternative):**
```bash
# Export all topics
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --bootstrap-server localhost:9092 > topics-metadata.txt

# Export specific topic
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --topic my-topic --bootstrap-server localhost:9092
```

### 2. Backup Broker and Topic Configurations

**Export broker and topic-level configurations:**

```bash
make -f make/ops/kafka.mk kafka-configs-backup
```

**What it does:**
1. Exports broker configurations via `kafka-configs --entity-type brokers`
2. Exports topic-level configurations via `kafka-configs --entity-type topics`
3. Saves to `tmp/kafka-backups/configs/<timestamp>/`

**Expected output:**
```
Backing up Kafka broker configurations...
Exporting broker configs...
Exporting topic configs...
✓ Configs backup completed: tmp/kafka-backups/configs/20251127-143022
```

**Manual export (alternative):**
```bash
# Export all broker configs
kubectl exec -it kafka-0 -- \
  kafka-configs.sh --describe --entity-type brokers --all --bootstrap-server localhost:9092

# Export all topic configs
kubectl exec -it kafka-0 -- \
  kafka-configs.sh --describe --entity-type topics --all --bootstrap-server localhost:9092
```

### 3. Backup Consumer Group Offsets

**Export consumer group offsets:**

```bash
make -f make/ops/kafka.mk kafka-consumer-offsets-backup
```

**What it does:**
1. Lists all consumer groups
2. Exports offsets for each consumer group
3. Saves to `tmp/kafka-backups/offsets/<timestamp>/`

**Expected output:**
```
Backing up consumer group offsets...
Exporting consumer groups...
Exporting offsets for group: my-consumer-group
✓ Consumer offsets backup completed: tmp/kafka-backups/offsets/20251127-143022
```

**Manual export (alternative):**
```bash
# List all consumer groups
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

# Describe specific consumer group
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --describe --group my-group --bootstrap-server localhost:9092
```

### 4. Backup Data Volumes

**Create PVC snapshot for data volumes:**

```bash
make -f make/ops/kafka.mk kafka-data-backup
```

**What it does:**
1. Identifies Kafka data PVC (`kafka-data-0`)
2. Creates VolumeSnapshot using CSI driver
3. Returns snapshot name for verification

**Expected output:**
```
Backing up Kafka data volumes (PVC snapshot)...
Note: This requires VolumeSnapshot CRD and CSI driver
Creating snapshot for PVC: kafka-data-0
✓ Snapshot created: kafka-data-snapshot-20251127-143022
  Verify with: kubectl get volumesnapshot -n default kafka-data-snapshot-20251127-143022
```

**Manual snapshot creation:**
```bash
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: kafka-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: kafka-data-0
EOF
```

### 5. Full Backup Workflow

**Recommended complete backup sequence:**

```bash
# Run full backup (automated)
make -f make/ops/kafka.mk kafka-full-backup

# Verify backups
ls -lh tmp/kafka-backups/topics/
ls -lh tmp/kafka-backups/configs/
ls -lh tmp/kafka-backups/offsets/
kubectl get volumesnapshot -n default
```

**Backup verification:**
```bash
# Check topic metadata
cat tmp/kafka-backups/topics/*/topics-metadata.txt | head -20

# Check broker configs
cat tmp/kafka-backups/configs/*/broker-configs.txt

# Check consumer offsets
cat tmp/kafka-backups/offsets/*/consumer-groups-list.txt

# Verify snapshot status
kubectl get volumesnapshot kafka-data-snapshot-* -o yaml
```

---

## Recovery Procedures

### 1. Restore Topic Metadata

**Recreate topics from backup:**

```bash
# Extract topic details from backup
BACKUP_FILE="tmp/kafka-backups/topics/20251127-020000/topics-metadata.txt"

# Parse and recreate topics (manual process)
# Example: Create topic from backup metadata
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --create --topic my-topic \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 2
```

**Note:** Kafka doesn't have bulk topic import. Topics must be recreated individually or via custom scripts.

### 2. Restore Broker and Topic Configurations

**Restore configurations from backup:**

```bash
# Apply broker-level configuration
kubectl exec -it kafka-0 -- \
  kafka-configs.sh --alter --entity-type brokers --entity-name 0 \
  --add-config retention.ms=604800000 \
  --bootstrap-server localhost:9092

# Apply topic-level configuration
kubectl exec -it kafka-0 -- \
  kafka-configs.sh --alter --entity-type topics --entity-name my-topic \
  --add-config retention.ms=259200000 \
  --bootstrap-server localhost:9092
```

### 3. Restore Data Volumes

**Restore from VolumeSnapshot:**

```bash
# Scale down Kafka StatefulSet
kubectl scale statefulset kafka --replicas=0

# Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kafka-data-0-restored
  namespace: default
spec:
  storageClassName: csi-snapclass
  dataSource:
    name: kafka-data-snapshot-20251127-020000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF

# Update StatefulSet volumeClaimTemplates to use restored PVC
# (Requires StatefulSet recreation or PVC name matching)

# Scale up Kafka StatefulSet
kubectl scale statefulset kafka --replicas=3
```

### 4. Restore Consumer Group Offsets

**Reset consumer group offsets from backup:**

```bash
# Option 1: Reset to specific offset (from backup)
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --reset-offsets \
  --group my-group \
  --topic my-topic:0 \
  --to-offset 12345 \
  --bootstrap-server localhost:9092 \
  --execute

# Option 2: Reset to earliest/latest (fallback)
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --reset-offsets \
  --group my-group \
  --all-topics \
  --to-earliest \
  --bootstrap-server localhost:9092 \
  --execute
```

### 5. Full Recovery Workflow

**Complete disaster recovery procedure:**

```bash
# Step 1: Restore data volumes (if needed)
kubectl scale statefulset kafka --replicas=0
# Restore PVC from VolumeSnapshot (see above)

# Step 2: Start Kafka cluster
kubectl scale statefulset kafka --replicas=3
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka --timeout=300s

# Step 3: Recreate topics from metadata backup
# (Parse topics-metadata.txt and create topics)

# Step 4: Apply configurations
# (Apply broker and topic configs from backup)

# Step 5: Reset consumer group offsets
# (Reset offsets from backup)

# Step 6: Verify recovery
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

---

## Best Practices

### 1. Backup Frequency

- **Production**: Daily automated backups + pre-upgrade backups
- **Staging**: Weekly backups
- **Development**: On-demand before major changes

### 2. Retention Policy

| Backup Type | Retention | Reason |
|-------------|-----------|--------|
| Daily | 30 days | Balance storage cost vs recovery needs |
| Weekly | 90 days | Long-term recovery options |
| Monthly | 1 year | Compliance/audit requirements |
| Pre-upgrade | Until next successful upgrade | Rollback safety |

### 3. Backup Verification

**Test restores quarterly:**
```bash
# Restore to test namespace
helm install kafka-test charts/kafka -n kafka-test

# Restore topics and configs
# (Follow recovery procedures above)

# Verify data integrity
kubectl exec -n kafka-test kafka-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092
```

### 4. Security

- **Encrypt backups at rest**: Use encrypted PVCs or encrypted storage backends
- **Encrypt backups in transit**: Use TLS for data transfers
- **Access control**: Restrict backup access to authorized personnel
- **Message data**: May contain sensitive data - treat backups accordingly

### 5. Monitoring

**Monitor backup jobs:**
```bash
# Check backup storage usage
du -sh tmp/kafka-backups/

# Verify recent backups exist
ls -lt tmp/kafka-backups/topics/ | head -5
ls -lt tmp/kafka-backups/configs/ | head -5
ls -lt tmp/kafka-backups/offsets/ | head -5

# Check snapshot status
kubectl get volumesnapshot -n default
```

---

## Troubleshooting

### Backup Failures

**Problem: `kafka-topics --describe` fails**

**Solution:**
```bash
# Verify Kafka service is running
kubectl get pods -l app.kubernetes.io/name=kafka

# Check broker connectivity
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Test topic access
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092
```

**Problem: VolumeSnapshot fails**

**Solution:**
```bash
# Check if VolumeSnapshot CRD exists
kubectl get crd volumesnapshots.snapshot.storage.k8s.io

# Verify snapshot class
kubectl get volumesnapshotclass

# Check CSI driver
kubectl get csidrivers
```

**Problem: Consumer offset export returns empty**

**Solution:**
```bash
# Verify consumer groups exist
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

# Check if consumers are active
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --describe --all-groups --bootstrap-server localhost:9092
```

### Restore Failures

**Problem: Topic creation fails with \"already exists\"**

**Solution:**
```bash
# List existing topics
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

# Delete existing topic (if safe)
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --delete --topic my-topic --bootstrap-server localhost:9092

# Recreate from backup
```

**Problem: Consumer offset reset fails**

**Solution:**
```bash
# Stop consumers first
# Consumers must be inactive to reset offsets

# Verify group is inactive
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --describe --group my-group --bootstrap-server localhost:9092 | grep EMPTY

# Retry offset reset
```

**Problem: Data not accessible after PVC restore**

**Solution:**
```bash
# Verify PVC mount
kubectl exec -it kafka-0 -- ls -la /bitnami/kafka/data

# Check Kafka logs
kubectl logs kafka-0 | tail -50

# Verify broker registration
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

---

## Additional Resources

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka Operations Guide](https://kafka.apache.org/documentation/#operations)
- [Kafka Upgrade Guide](kafka-upgrade-guide.md)
- [Chart README](../charts/kafka/README.md)

---

**Last Updated:** 2025-11-27
