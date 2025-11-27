# Kafka Upgrade Guide

Comprehensive guide for upgrading Kafka message broker deployments with zero-downtime strategies and rollback procedures.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Preparation](#pre-upgrade-preparation)
- [Upgrade Procedures](#upgrade-procedures)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Version-Specific Notes](#version-specific-notes)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Upgrade Types

| Upgrade Type | Example | Risk Level | Downtime | Rollback Complexity |
|--------------|---------|------------|----------|---------------------|
| **Patch** | 3.6.1 → 3.6.2 | Low | None | Easy |
| **Minor** | 3.5.x → 3.6.x | Medium | None | Moderate |
| **Major** | 2.x.x → 3.x.x | High | 15-30 min | Complex |
| **Chart** | v0.2.0 → v0.3.0 | Low-Medium | None | Easy |

### Compatibility Matrix

| Kafka Version | Chart Version | KRaft Mode | ZooKeeper | Kubernetes |
|---------------|---------------|------------|-----------|------------|
| 3.6.x | 0.3.x | ✅ Yes | ❌ No | 1.24+ |
| 3.5.x | 0.2.x | ✅ Yes | ⚠️ Deprecated | 1.21+ |
| 3.4.x | 0.1.x | ⚠️ Experimental | ✅ Yes | 1.21+ |

**Note:** This chart uses KRaft mode (no ZooKeeper). ZooKeeper mode is deprecated and not supported.

---

## Pre-Upgrade Preparation

### 1. Health Check

**Verify current deployment health:**

```bash
# Run pre-upgrade health check
make -f make/ops/kafka.mk kafka-pre-upgrade-check
```

**What it checks:**
- Pod status (all Running)
- Broker connectivity
- Cluster metadata (KRaft mode)
- Under-replicated partitions (ISR health)

**Manual health check:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=kafka

# Check broker cluster
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Check topics and partitions
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --bootstrap-server localhost:9092

# Check under-replicated partitions
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092
```

### 2. Backup Before Upgrade

**⚠️ CRITICAL: Always backup before upgrading**

```bash
# 1. Backup topic metadata
make -f make/ops/kafka.mk kafka-topics-backup

# 2. Backup broker and topic configurations
make -f make/ops/kafka.mk kafka-configs-backup

# 3. Backup consumer group offsets
make -f make/ops/kafka.mk kafka-consumer-offsets-backup

# 4. Backup data volumes (create PVC snapshot)
make -f make/ops/kafka.mk kafka-data-backup

# 5. Verify backups
ls -lh tmp/kafka-backups/topics/
ls -lh tmp/kafka-backups/configs/
ls -lh tmp/kafka-backups/offsets/
kubectl get volumesnapshot -n default
```

**Tag backups:**
```bash
# Create timestamped backup directory
BACKUP_TAG="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
mkdir -p "tmp/kafka-backups/${BACKUP_TAG}"

# Copy backups to tagged directory
cp -r tmp/kafka-backups/topics/* "tmp/kafka-backups/${BACKUP_TAG}/"
cp -r tmp/kafka-backups/configs/* "tmp/kafka-backups/${BACKUP_TAG}/"
cp -r tmp/kafka-backups/offsets/* "tmp/kafka-backups/${BACKUP_TAG}/"
```

### 3. Review Changelog

**Check for breaking changes:**

- [Kafka Release Notes](https://kafka.apache.org/downloads)
- [Chart CHANGELOG.md](../CHANGELOG.md)

**Common breaking changes:**
- Inter-broker protocol version changes
- Log format version changes
- Configuration parameter deprecations
- KRaft metadata version changes

### 4. Test in Staging

**Deploy to staging environment first:**

```bash
# Deploy to staging namespace
helm upgrade kafka-staging charts/kafka \
  -n staging \
  -f values-staging.yaml \
  --set image.tag=3.6-debian-12

# Validate staging deployment
kubectl get pods -n staging
make -f make/ops/kafka.mk kafka-post-upgrade-check NAMESPACE=staging
```

### 5. Plan Maintenance Window

**Recommended windows:**
- **Patch upgrades**: No window needed (rolling update)
- **Minor upgrades**: No window needed (rolling update with inter-broker protocol compatibility)
- **Major upgrades**: 30-60 minute window (or blue-green deployment)

**Note:** Rolling upgrades require inter-broker protocol version compatibility. Always check release notes.

---

## Upgrade Procedures

### Method 1: Rolling Upgrade (Recommended)

**Zero-downtime upgrade for patch/minor versions:**

```bash
# Step 1: Update Helm repository
helm repo update

# Step 2: Upgrade chart (rolling update)
helm upgrade kafka charts/kafka \
  -f values.yaml \
  --wait \
  --timeout=10m

# Step 3: Monitor rolling update
kubectl get pods -l app.kubernetes.io/name=kafka -w

# Step 4: Verify ISR status after each broker restart
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

# Step 5: Verify deployment
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**Rolling update behavior:**
- StatefulSet updates brokers one by one (controlled shutdown)
- Each broker gracefully transfers leadership before shutdown
- Kafka controller waits for ISR synchronization
- Brief interruption per broker (< 30 seconds)
- Total upgrade time: 3-5 minutes for 3-broker cluster

### Method 2: Blue-Green Upgrade

**For major version upgrades with zero downtime:**

```bash
# Step 1: Deploy new "green" Kafka cluster
helm install kafka-green charts/kafka \
  -f values.yaml \
  --set image.tag=3.6-debian-12 \
  --set fullnameOverride=kafka-green

# Step 2: Set up MirrorMaker 2.0 for topic replication
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mirrormaker2
spec:
  containers:
  - name: mirrormaker2
    image: bitnami/kafka:3.6
    command:
    - connect-mirror-maker.sh
    - /config/mm2.properties
EOF

# Step 3: Validate data consistency
kubectl exec -it kafka-green-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

kubectl exec -it kafka-green-0 -- \
  kafka-consumer-groups.sh --describe --all-groups --bootstrap-server localhost:9092

# Step 4: Update producer/consumer configs to new cluster
# (Application configuration change - gradual cutover)

# Step 5: Monitor both clusters during transition period
kubectl logs -f kafka-0
kubectl logs -f kafka-green-0

# Step 6: Decommission old cluster after validation (24-48 hours)
helm uninstall kafka  # Old blue deployment
```

### Method 3: Maintenance Window Upgrade

**For major version upgrades with planned downtime:**

```bash
# Step 1: Notify stakeholders - maintenance window starting

# Step 2: Scale down StatefulSet
kubectl scale statefulset kafka --replicas=0

# Step 3: Backup data (if not already done)
make -f make/ops/kafka.mk kafka-full-backup

# Step 4: Upgrade chart with new image and configs
helm upgrade kafka charts/kafka \
  -f values.yaml \
  --set image.tag=3.6-debian-12

# Step 5: Update inter-broker protocol version (if needed)
# Edit values.yaml: kafka.interBrokerProtocolVersion

# Step 6: Scale up StatefulSet
kubectl scale statefulset kafka --replicas=3

# Step 7: Wait for cluster formation
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka --timeout=300s

# Step 8: Verify cluster health and ISR status
make -f make/ops/kafka.mk kafka-post-upgrade-check

# Step 9: Test topic produce/consume
kubectl exec -it kafka-0 -- \
  kafka-console-producer.sh --topic test --bootstrap-server localhost:9092
kubectl exec -it kafka-0 -- \
  kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server localhost:9092
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Run post-upgrade check
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**What it checks:**
- All pods running and ready
- StatefulSet available
- Kafka version
- Broker cluster connectivity
- Topic accessibility
- Under-replicated partitions

### Manual Validation Checklist

**1. Component Status:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=kafka

# Expected: All pods Running/Ready
# kafka-0           1/1     Running   0          5m
# kafka-1           1/1     Running   0          5m
# kafka-2           1/1     Running   0          5m
```

**2. Kafka Version:**
```bash
# Check version via broker API
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | head -1

# Expected: broker ID, host, port with new version
```

**3. Broker Cluster:**
```bash
# Verify all brokers online
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | grep -o '^[0-9].*:9092'

# Expected: All broker IDs listed (0, 1, 2)
```

**4. Topic Access:**
```bash
# List all topics
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

# Describe topics
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --bootstrap-server localhost:9092
```

**5. Under-Replicated Partitions:**
```bash
# Check ISR health
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

# Expected: No output (all partitions in-sync)
```

**6. Consumer Groups:**
```bash
# List consumer groups
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

# Describe consumer group state
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --describe --group my-group --bootstrap-server localhost:9092
```

**7. Kafka UI Access:**
```bash
# Port-forward Kafka UI
make -f make/ops/kafka.mk kafka-ui-port-forward

# Access http://localhost:8080
# Verify topics, brokers, consumer groups visible
```

**8. Test Produce/Consume:**
```bash
# Test message production
kubectl exec -it kafka-0 -- \
  kafka-console-producer.sh --topic test-upgrade --bootstrap-server localhost:9092
# Type messages and Ctrl+C

# Test message consumption
kubectl exec -it kafka-0 -- \
  kafka-console-consumer.sh --topic test-upgrade --from-beginning --bootstrap-server localhost:9092
```

---

## Rollback Procedures

### When to Rollback

- Broker cluster formation fails
- Under-replicated partitions after upgrade
- Data loss or corruption detected
- Performance degradation
- Critical functionality broken

### Method 1: Helm Rollback (Fast)

**Rollback to previous chart release:**

```bash
# Display rollback plan
make -f make/ops/kafka.mk kafka-upgrade-rollback

# Execute Helm rollback
helm rollback kafka

# Verify rollback
kubectl get pods -l app.kubernetes.io/name=kafka
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**Note:** Helm rollback reverts chart but NOT Kafka data. May require data restore for major versions.

### Method 2: PVC Restore (Complete)

**Restore data volumes to pre-upgrade state:**

```bash
# Step 1: Scale down StatefulSet
kubectl scale statefulset kafka --replicas=0

# Step 2: Restore PVC from VolumeSnapshot
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

# Step 3: Helm rollback to previous chart
helm rollback kafka

# Step 4: Scale up StatefulSet
kubectl scale statefulset kafka --replicas=3

# Step 5: Verify rollback
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

### Method 3: Full Disaster Recovery

**Complete restore from backups:**

```bash
# Step 1: Uninstall broken deployment
helm uninstall kafka

# Step 2: Reinstall previous chart version
helm install kafka charts/kafka \
  -f values.yaml \
  --version 0.2.0  # Previous working version

# Step 3: Restore PVC from snapshot (if needed)
# (Follow PVC restore procedures above)

# Step 4: Recreate topics from metadata backup
# (Parse topics-metadata.txt and recreate topics)

# Step 5: Restore consumer group offsets
# (Reset offsets from backup)

# Step 6: Verify full recovery
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

---

## Version-Specific Notes

### Kafka 3.6.x

**Key Features:**
- KRaft mode production-ready
- Improved metadata management
- Enhanced security features

**Breaking Changes:**
- None (backward compatible with 3.5.x)

**Migration Notes:**
- Rolling upgrade supported from 3.5.x
- No configuration changes required

### Kafka 3.5.x → 3.6.x

**Upgrade Path:**
```bash
helm upgrade kafka charts/kafka --set image.tag=3.6-debian-12
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**Post-upgrade:**
- Verify broker cluster formation
- Check under-replicated partitions
- Test topic produce/consume

### Kafka 3.4.x → 3.5.x

**Breaking Changes:**
- ZooKeeper mode deprecated (use KRaft)
- Some configuration parameters renamed

**Migration:**
```bash
# Update values.yaml for KRaft mode
# Migrate from ZooKeeper (if applicable)

helm upgrade kafka charts/kafka
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

### Kafka 2.x → 3.x

**⚠️ MAJOR UPGRADE - Requires careful planning**

**Breaking changes:**
- Complete ZooKeeper removal (KRaft only)
- Inter-broker protocol version changes
- Log format version changes
- Configuration parameter changes

**Migration Path:**
1. Read [Kafka 3.0 Migration Guide](https://kafka.apache.org/documentation/#upgrade_3_0_0)
2. Migrate from ZooKeeper to KRaft mode
3. Test extensively in staging
4. Plan 1-2 hour maintenance window
5. Backup extensively before upgrade

---

## Best Practices

### 1. Always Test in Staging

**Never upgrade production directly:**
```bash
# Deploy staging environment
helm install kafka-staging charts/kafka -n staging -f values-staging.yaml

# Test upgrade in staging
helm upgrade kafka-staging charts/kafka --set image.tag=3.6-debian-12

# Validate for 24-48 hours before production upgrade
```

### 2. Incremental Upgrades

**Prefer small, frequent upgrades:**
- Patch upgrades: Every 1-2 months
- Minor upgrades: Every 3-6 months
- Major upgrades: Plan carefully (6-12 months)

**Avoid skipping versions:**
- ❌ Bad: 3.4.0 → 3.6.0 (skip 3.5.x)
- ✅ Good: 3.4.0 → 3.5.3 → 3.6.2

### 3. Monitor After Upgrade

**Post-upgrade monitoring (24-48 hours):**
```bash
# Watch pod status
kubectl get pods -l app.kubernetes.io/name=kafka -w

# Monitor logs
kubectl logs -f kafka-0
kubectl logs -f kafka-1
kubectl logs -f kafka-2

# Check resource usage
kubectl top pods -l app.kubernetes.io/name=kafka

# Monitor under-replicated partitions
watch 'kubectl exec kafka-0 -- kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092'
```

### 4. Document Upgrade

**Maintain upgrade log:**
```markdown
## Kafka Upgrade Log

### 2025-11-27: 3.5.3 → 3.6.2
- **Performed by:** DevOps Team
- **Downtime:** None (rolling update)
- **Issues:** None
- **Rollback:** Not required
- **Notes:** All partitions remained in-sync during upgrade
```

---

## Troubleshooting

### Under-Replicated Partitions After Upgrade

**Problem: Partitions not in-sync after upgrade**

**Solution:**
```bash
# Check ISR status
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

# Wait for ISR synchronization (may take 5-10 minutes)
# Monitor logs for replication progress
kubectl logs -f kafka-0 | grep -i replication
```

### Broker Not Joining Cluster

**Problem: Broker fails to join cluster after upgrade**

**Solution:**
```bash
# Check broker logs
kubectl logs kafka-0 | tail -50

# Verify KRaft cluster ID matches
kubectl exec -it kafka-0 -- \
  cat /bitnami/kafka/data/__cluster_metadata-0/meta.properties

# Restart broker if needed
kubectl delete pod kafka-0
```

### Consumer Group Lag Increasing

**Problem: Consumer groups falling behind after upgrade**

**Solution:**
```bash
# Check consumer group lag
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --describe --group my-group --bootstrap-server localhost:9092

# Restart consumers if lagging
# Increase consumer parallelism if needed
```

### Performance Degradation

**Problem: Kafka slower after upgrade**

**Solution:**
```bash
# Check resource usage
kubectl top pods -l app.kubernetes.io/name=kafka

# Increase resources if needed
helm upgrade kafka charts/kafka \
  --set resources.limits.cpu=4000m \
  --set resources.limits.memory=8Gi

# Check disk I/O
kubectl exec -it kafka-0 -- iostat -x 5
```

---

## Additional Resources

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka Upgrade Guide](https://kafka.apache.org/documentation/#upgrade)
- [Kafka Backup & Recovery Guide](kafka-backup-guide.md)
- [Chart README](../charts/kafka/README.md)

---

**Last Updated:** 2025-11-27
