# Apache Kafka Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)
![AppVersion: 3.9.0](https://img.shields.io/badge/AppVersion-3.9.0-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Apache Kafka streaming platform with KRaft mode (no Zookeeper) and management UI.

## Features

- ✅ **Kafka 3.9.0** - Latest stable 3.x version (LTS)
- ✅ **KRaft Mode** - No Zookeeper dependency
- ✅ **Kafka UI** - Web-based management interface
- ✅ **Production-Ready** - StatefulSet with persistent storage
- ✅ **SASL Authentication** - Optional authentication support
- ✅ **Easy Operations** - 20+ Makefile commands
- ✅ **HA Support** - Multi-broker clustering
- ✅ **Monitoring Ready** - Health probes and metrics

## Quick Start

```bash
# Add the Helm repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default values (development)
helm install my-kafka scripton-charts/kafka

# Access Kafka UI
kubectl port-forward svc/my-kafka-ui 8080:8080
# Open http://localhost:8080
```

## KRaft Mode

This chart uses Kafka's KRaft mode (Kafka Raft metadata mode) instead of Zookeeper:

**Benefits:**
- Simpler architecture - no external coordination service
- Faster metadata operations
- Reduced operational complexity
- Better scalability

**Combined Mode:**
- Each broker acts as both broker and controller
- Suitable for small to medium deployments
- Simplified configuration

## Installation

### Development

```bash
helm install my-kafka scripton-charts/kafka \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/kafka/values-dev.yaml
```

### Production (3-broker cluster)

```bash
helm install my-kafka scripton-charts/kafka \
  -n production \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/kafka/values-small-prod.yaml \
  --set kafka.sasl.password='<STRONG_PASSWORD>' \
  --set persistence.storageClass='fast-ssd'
```

## Configuration

### Topic Defaults

```yaml
kafka:
  numPartitions: 3
  defaultReplicationFactor: 3
  minInsyncReplicas: 2
  autoCreateTopicsEnable: false  # Disable for production
```

### SASL Authentication

```yaml
kafka:
  sasl:
    enabled: true
    mechanisms: "PLAIN"
    username: "admin"
    password: "<strong-password>"
```

### Kafka UI

```yaml
kafkaUI:
  enabled: true
  ingress:
    enabled: true
    className: "nginx"
    hosts:
      - host: kafka-ui.example.com
        paths:
          - path: /
            pathType: Prefix
```

## Operations

### Topic Management

```bash
# List topics
make -f make/ops/kafka.mk kafka-topics-list

# Create topic
make -f make/ops/kafka.mk kafka-topic-create TOPIC=my-topic PARTITIONS=3 REPLICATION=2

# Describe topic
make -f make/ops/kafka.mk kafka-topic-describe TOPIC=my-topic

# Delete topic
make -f make/ops/kafka.mk kafka-topic-delete TOPIC=my-topic
```

### Producer/Consumer Testing

```bash
# Produce messages (interactive)
make -f make/ops/kafka.mk kafka-produce TOPIC=my-topic

# Consume messages
make -f make/ops/kafka.mk kafka-consume TOPIC=my-topic
```

### Consumer Groups

```bash
# List consumer groups
make -f make/ops/kafka.mk kafka-consumer-groups-list

# Describe consumer group
make -f make/ops/kafka.mk kafka-consumer-group-describe GROUP=my-group
```

### Broker Information

```bash
# List brokers
make -f make/ops/kafka.mk kafka-broker-list

# Get cluster ID
make -f make/ops/kafka.mk kafka-cluster-id

# View logs
make -f make/ops/kafka.mk kafka-logs
```

## Values Profiles

### values-dev.yaml
- Single broker
- Auto-create topics enabled
- 1-day retention
- 5Gi storage
- No authentication

### values-small-prod.yaml
- 3 brokers for HA
- Auto-create topics disabled
- 7-day retention
- 50Gi SSD storage
- SASL authentication
- Anti-affinity rules

## Troubleshooting

### Broker not starting

Check cluster ID and controller voters:

```bash
kubectl logs kafka-0
# Look for KRaft configuration errors
```

### Topics not replicating

Check replication factor matches broker count:

```bash
make -f make/ops/kafka.mk kafka-topic-describe TOPIC=my-topic
```

### Cannot produce/consume

Check SASL configuration:

```bash
# Verify authentication
kubectl exec kafka-0 -- kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

## Production Recommendations

### 1. Use Operators for Large Deployments

For production clusters >3 brokers, consider [Strimzi Kafka Operator](https://strimzi.io/):
- Automatic rolling updates
- TLS encryption
- Advanced monitoring
- Multi-cluster support

### 2. Broker Count

- **Development**: 1 broker
- **Small Production**: 3 brokers  
- **Large Production**: 5+ brokers (use operator)

### 3. Storage

```yaml
persistence:
  storageClass: "fast-ssd"  # Use SSD for better performance
  size: 100Gi  # Size based on retention requirements
```

### 4. Resource Planning

**Memory:**
- Heap: 50% of container memory limit
- Page cache: Remaining 50%

**Example for 4Gi memory:**
```yaml
resources:
  limits:
    memory: 4Gi
kafka:
  extraEnv:
    - name: KAFKA_HEAP_OPTS
      value: "-Xmx2G -Xms2G"
```

### 5. Retention Planning

Calculate storage needs:
```
Storage = Messages/day × Message size × Retention days × Replication factor
```

### 6. Monitoring

Enable JMX exporter for Prometheus:

```yaml
kafka:
  extraEnv:
    - name: KAFKA_JMX_OPTS
      value: "-javaagent:/opt/jmx-exporter/jmx-exporter.jar=7071:/etc/jmx-exporter/config.yml"
```

---

## Backup & Recovery

Kafka supports comprehensive backup and recovery procedures for production deployments.

### Backup Strategy

Kafka backup consists of five critical components:

1. **Topic Metadata** (topic names, partitions, replication factor, configs)
2. **Broker Configurations** (broker settings, topic-level configs)
3. **Data Volumes** (actual message data in log.dirs)
4. **Consumer Group Offsets** (consumer position tracking)
5. **ACLs** (access control lists - if SASL enabled)

### Backup Commands

```bash
# 1. Backup topic metadata
make -f make/ops/kafka.mk kafka-topics-backup

# 2. Backup broker and topic configurations
make -f make/ops/kafka.mk kafka-configs-backup

# 3. Backup consumer group offsets
make -f make/ops/kafka.mk kafka-consumer-offsets-backup

# 4. Backup data volumes (create PVC snapshot)
make -f make/ops/kafka.mk kafka-data-backup

# 5. Full backup (automated workflow)
make -f make/ops/kafka.mk kafka-full-backup

# 6. Verify backups
ls -lh tmp/kafka-backups/topics/
ls -lh tmp/kafka-backups/configs/
ls -lh tmp/kafka-backups/offsets/
kubectl get volumesnapshot -n default
```

**Backup storage locations:**
```
tmp/kafka-backups/
├── topics/                     # Topic metadata
│   └── YYYYMMDD-HHMMSS/
│       └── topics-metadata.txt
├── configs/                    # Broker and topic configurations
│   └── YYYYMMDD-HHMMSS/
│       ├── broker-configs.txt
│       └── topic-configs.txt
└── offsets/                    # Consumer group offsets
    └── YYYYMMDD-HHMMSS/
        ├── consumer-groups-list.txt
        └── offsets-{group}.txt
```

### Recovery Commands

```bash
# 1. Restore data volumes from VolumeSnapshot
kubectl scale statefulset kafka --replicas=0
# Restore PVC from snapshot (follow VolumeSnapshot procedures)
kubectl scale statefulset kafka --replicas=3

# 2. Recreate topics from metadata backup
# (Parse topics-metadata.txt and create topics individually)

# 3. Apply configurations
# (Apply broker and topic configs from backup)

# 4. Reset consumer group offsets
kubectl exec -it kafka-0 -- \
  kafka-consumer-groups.sh --reset-offsets --group my-group \
  --topic my-topic:0 --to-offset 12345 --bootstrap-server localhost:9092 --execute

# 5. Verify recovery
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

### Best Practices

- **Production**: Daily automated backups + pre-upgrade backups
- **Retention**: 30 days (daily), 90 days (weekly), 1 year (monthly)
- **Verification**: Test restores quarterly
- **Security**: Encrypt backups at rest and in transit

**📖 Complete guide**: See [docs/kafka-backup-guide.md](../../docs/kafka-backup-guide.md) for detailed backup/recovery procedures.

---

## Upgrading

Kafka supports multiple upgrade strategies with zero-downtime rolling updates.

### Pre-Upgrade Checklist

```bash
# 1. Run pre-upgrade health check
make -f make/ops/kafka.mk kafka-pre-upgrade-check

# 2. Backup everything
make -f make/ops/kafka.mk kafka-full-backup

# 3. Review changelog
# - Check Kafka release notes: https://kafka.apache.org/downloads
# - Review chart CHANGELOG.md

# 4. Test in staging
helm upgrade kafka-staging charts/kafka -n staging -f values-staging.yaml
```

### Upgrade Procedures

**Method 1: Rolling Upgrade (Recommended for patch/minor versions)**
```bash
# Zero-downtime upgrade with controlled broker shutdown
helm upgrade kafka charts/kafka -f values.yaml --wait --timeout=10m

# Monitor rolling update
kubectl get pods -l app.kubernetes.io/name=kafka -w

# Verify ISR status after each broker restart
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

# Verify deployment
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**Method 2: Blue-Green Upgrade (For major versions with zero downtime)**
```bash
# Deploy new "green" Kafka cluster
helm install kafka-green charts/kafka -f values.yaml \
  --set image.tag=3.6-debian-12 --set fullnameOverride=kafka-green

# Set up MirrorMaker 2.0 for topic replication (blue → green)
# (Deploy MirrorMaker 2.0 connector)

# Validate data consistency
kubectl exec -it kafka-green-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

# Update producer/consumer configs to new cluster (gradual cutover)

# Decommission old cluster after validation (24-48 hours)
helm uninstall kafka
```

**Method 3: Maintenance Window Upgrade (For major versions)**
```bash
# Scale down StatefulSet
kubectl scale statefulset kafka --replicas=0

# Backup data
make -f make/ops/kafka.mk kafka-full-backup

# Upgrade chart
helm upgrade kafka charts/kafka -f values.yaml --set image.tag=3.6-debian-12

# Scale up StatefulSet
kubectl scale statefulset kafka --replicas=3

# Wait for cluster formation
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka --timeout=300s

# Verify cluster health
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

### Post-Upgrade Validation

```bash
# Automated validation
make -f make/ops/kafka.mk kafka-post-upgrade-check

# Manual checks
kubectl get pods -l app.kubernetes.io/name=kafka
kubectl exec -it kafka-0 -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | head -1
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092

# Check under-replicated partitions (should be empty)
kubectl exec -it kafka-0 -- \
  kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

# Test produce/consume
kubectl exec -it kafka-0 -- \
  kafka-console-producer.sh --topic test-upgrade --bootstrap-server localhost:9092
kubectl exec -it kafka-0 -- \
  kafka-console-consumer.sh --topic test-upgrade --from-beginning --bootstrap-server localhost:9092
```

### Rollback Procedures

**Option 1: Helm Rollback (Fast)**
```bash
make -f make/ops/kafka.mk kafka-upgrade-rollback  # Display rollback plan
helm rollback kafka
make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**Option 2: PVC Restore (Complete - includes data)**
```bash
kubectl scale statefulset kafka --replicas=0

# Restore PVC from VolumeSnapshot
kubectl apply -f <pvc-from-snapshot.yaml>

helm rollback kafka

kubectl scale statefulset kafka --replicas=3

make -f make/ops/kafka.mk kafka-post-upgrade-check
```

**📖 Complete guide**: See [docs/kafka-upgrade-guide.md](../../docs/kafka-upgrade-guide.md) for detailed upgrade procedures and version-specific notes.

---

## License

This Helm chart is licensed under the BSD-3-Clause License.

Apache Kafka is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Maintainers

- [ScriptonBasestar](https://github.com/scriptonbasestar-container)

---

**Chart Version:** 0.3.0
**Kafka Version:** 3.9.0
**Last Updated:** 2025-11
