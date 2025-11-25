# Kafka to Strimzi Operator Migration Guide

Guide for migrating from the simple Kafka Helm chart to the production-ready Strimzi Kafka Operator.

## Overview

This guide helps you migrate from the basic Kafka chart in this repository to the production-ready Strimzi Kafka Operator with high availability, automated operations, and advanced features.

**Why migrate to Strimzi?**
- ✅ CNCF Sandbox project
- ✅ Native Kubernetes integration
- ✅ Declarative topic and user management
- ✅ Automated rolling updates
- ✅ Built-in Kafka Connect
- ✅ Kafka MirrorMaker 2 for replication
- ✅ Prometheus metrics
- ✅ TLS encryption and authentication
- ✅ Production-grade reliability

## Table of Contents

- [Operator Overview](#operator-overview)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Backup Procedures](#backup-procedures)
- [Migration Process](#migration-process)
- [Verification](#verification)
- [Rollback Plan](#rollback-plan)
- [Post-Migration Tasks](#post-migration-tasks)

## Operator Overview

### Strimzi Kafka Operator

**Project:** https://strimzi.io/

**Features:**
- ✅ CNCF Sandbox project
- ✅ KRaft mode (no ZooKeeper) support
- ✅ CRD-based topic and user management
- ✅ Kafka Connect cluster management
- ✅ Kafka MirrorMaker 2 for cross-cluster replication
- ✅ Kafka Bridge (HTTP access to Kafka)
- ✅ Cruise Control integration
- ✅ Automated certificate management
- ✅ OAuth 2.0 authentication
- ✅ Schema Registry integration

**Components:**
- **Kafka CRD:** Kafka cluster management
- **KafkaTopic CRD:** Topic management
- **KafkaUser CRD:** User and ACL management
- **KafkaConnect CRD:** Kafka Connect cluster
- **KafkaMirrorMaker2 CRD:** Cross-cluster replication
- **KafkaBridge CRD:** HTTP bridge to Kafka

**Use Case:** Any production Kafka deployment requiring HA and Kubernetes-native management.

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check current Kafka version
kubectl exec -it <kafka-pod> -- kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092 | head -5

# List all topics
kubectl exec -it <kafka-pod> -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

# Describe topics (partitions, replicas, configs)
kubectl exec -it <kafka-pod> -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe

# Check consumer groups
kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --list

# Describe consumer group offsets
kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group <group-name>

# Check cluster status (KRaft mode)
kubectl exec -it <kafka-pod> -- kafka-metadata.sh \
  --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log \
  --command "print"
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-kafka-values.yaml

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i kafka

# Export topic configurations
kubectl exec -it <kafka-pod> -- kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe > kafka-topics.txt

# Export consumer group offsets
for group in $(kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list); do
  kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --describe --group $group > "offsets-$group.txt"
done
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small clusters (< 10 topics): 15-30 minutes
- Medium clusters (10-100 topics): 30-60 minutes
- Large clusters (> 100 topics): 60-120 minutes

**Factors affecting downtime:**
- Number of topics and partitions
- Data volume (if migrating data)
- Number of consumer groups
- Network speed

**Note:** Message migration requires additional tooling (MirrorMaker 2) and may require extended maintenance window.

## Backup Procedures

### Method 1: Topic Configuration Export

**Advantages:** Quick, captures all topic metadata
**Disadvantages:** Does not include messages

```bash
# Export all topic configurations
kubectl exec -it <kafka-pod> -- bash -c '
  for topic in $(kafka-topics.sh --bootstrap-server localhost:9092 --list); do
    echo "=== $topic ===" >> /tmp/topics-config.txt
    kafka-configs.sh --bootstrap-server localhost:9092 \
      --entity-type topics --entity-name $topic --describe >> /tmp/topics-config.txt
  done
'

# Copy to local
kubectl cp <namespace>/<kafka-pod>:/tmp/topics-config.txt ./topics-config.txt
```

### Method 2: Consumer Offset Export

```bash
# Export all consumer group offsets
kubectl exec -it <kafka-pod> -- bash -c '
  for group in $(kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list); do
    echo "=== $group ===" >> /tmp/offsets.txt
    kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
      --describe --group $group >> /tmp/offsets.txt
  done
'

kubectl cp <namespace>/<kafka-pod>:/tmp/offsets.txt ./consumer-offsets.txt
```

### Method 3: Data Migration with MirrorMaker 2

For migrating messages, use Kafka MirrorMaker 2:

```yaml
# mm2-config.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaMirrorMaker2
metadata:
  name: migration-mm2
spec:
  version: 3.6.1
  replicas: 1
  connectCluster: "target"
  clusters:
    - alias: "source"
      bootstrapServers: <old-kafka>:9092
    - alias: "target"
      bootstrapServers: <new-kafka>:9092
  mirrors:
    - sourceCluster: "source"
      targetCluster: "target"
      sourceConnector:
        config:
          replication.factor: 3
          offset-syncs.topic.replication.factor: 3
          sync.topic.acls.enabled: "false"
      topicsPattern: ".*"
      groupsPattern: ".*"
```

## Migration Process

### Step 1: Install Strimzi Operator

```bash
# Create namespace
kubectl create namespace kafka

# Install Strimzi via Helm
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --set watchNamespaces="{kafka}"

# Or install via kubectl
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

# Verify operator is running
kubectl get pods -n kafka -l name=strimzi-cluster-operator
```

### Step 2: Prepare Kafka Cluster Definition (KRaft Mode)

```yaml
# kafka-cluster.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-cluster
  namespace: kafka
spec:
  kafka:
    version: 3.6.1
    replicas: 3

    # KRaft mode (no ZooKeeper)
    metadataVersion: 3.6-IV2

    # Listeners
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
      - name: external
        port: 9094
        type: nodeport
        tls: false

    # Storage
    storage:
      type: jbod
      volumes:
        - id: 0
          type: persistent-claim
          size: 100Gi
          deleteClaim: false

    # Configuration
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
      inter.broker.protocol.version: "3.6"
      log.retention.hours: 168
      log.segment.bytes: 1073741824
      log.retention.check.interval.ms: 300000
      num.partitions: 3

    # Resources
    resources:
      requests:
        memory: 2Gi
        cpu: "500m"
      limits:
        memory: 4Gi
        cpu: "2"

    # Metrics
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml

  # KRaft Controller
  kafkaNodePools:
    - name: controller
      replicas: 3
      roles:
        - controller
      storage:
        type: jbod
        volumes:
          - id: 0
            type: persistent-claim
            size: 10Gi
            deleteClaim: false

    - name: broker
      replicas: 3
      roles:
        - broker
      storage:
        type: jbod
        volumes:
          - id: 0
            type: persistent-claim
            size: 100Gi
            deleteClaim: false

  # Entity Operator (for Topic and User CRDs)
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

### Step 3: Create Metrics ConfigMap

```yaml
# kafka-metrics-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-metrics
  namespace: kafka
data:
  kafka-metrics-config.yml: |
    lowercaseOutputName: true
    rules:
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
        clientId: "$3"
        topic: "$4"
        partition: "$5"
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), brokerHost=(.+), brokerPort=(.+)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
        clientId: "$3"
        broker: "$4:$5"
    - pattern: kafka.server<type=(.+), name=(.+)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        quantile: "0.$4"
```

### Step 4: Deploy the Cluster

```bash
# Apply metrics config
kubectl apply -f kafka-metrics-config.yaml

# Deploy Kafka cluster
kubectl apply -f kafka-cluster.yaml

# Wait for cluster to be ready
kubectl wait kafka/kafka-cluster --for=condition=Ready --timeout=600s -n kafka

# Check status
kubectl get kafka -n kafka
kubectl describe kafka kafka-cluster -n kafka
```

### Step 5: Create Topics via CRDs

```yaml
# kafka-topics.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: my-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
    min.insync.replicas: 2
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: events-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 6
  replicas: 3
  config:
    retention.ms: 2592000000
    cleanup.policy: delete
```

### Step 6: Create Users via CRDs

```yaml
# kafka-users.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: my-app-user
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: my-topic
          patternType: literal
        operations:
          - Read
          - Write
          - Describe
      - resource:
          type: group
          name: my-app-group
          patternType: literal
        operations:
          - Read
```

### Step 7: Migrate Data (If Required)

Using MirrorMaker 2:

```bash
# Apply MirrorMaker 2 configuration
kubectl apply -f mm2-config.yaml

# Monitor replication progress
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group mirrormaker2-cluster

# Wait for replication to catch up
# Check lag is 0 across all partitions
```

## Verification

### 1. Check Cluster Status

```bash
# Check Kafka resource
kubectl get kafka -n kafka
kubectl describe kafka kafka-cluster -n kafka

# Check all pods
kubectl get pods -n kafka

# Check cluster via kafka command
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  kafka-metadata.sh --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log \
  --command "print"
```

### 2. Verify Topics

```bash
# List topics
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check KafkaTopic CRDs
kubectl get kafkatopics -n kafka

# Describe specific topic
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic my-topic
```

### 3. Test Produce/Consume

```bash
# Produce test message
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  bash -c "echo 'test message' | kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic my-topic"

# Consume test message
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
  kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic my-topic \
    --from-beginning \
    --max-messages 1
```

### 4. Test Application Connectivity

```bash
# Get bootstrap servers
kubectl get kafka kafka-cluster -n kafka \
  -o jsonpath='{.status.listeners[?(@.name=="plain")].bootstrapServers}'

# Test from application pod
kubectl exec -it <app-pod> -- \
  kafka-console-producer.sh \
    --bootstrap-server kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092 \
    --topic test
```

## Rollback Plan

### 1. Keep Original Deployment Running

```bash
# Scale down original Kafka (but don't delete)
kubectl scale statefulset <kafka-statefulset> --replicas=0 -n <namespace>
```

### 2. Rollback Procedure

If issues occur:

```bash
# Scale up original Kafka
kubectl scale statefulset <kafka-statefulset> --replicas=3 -n <namespace>

# Update application bootstrap servers
kubectl set env deployment/<app> \
  KAFKA_BOOTSTRAP_SERVERS=<original-kafka-service>:9092

# Delete Strimzi cluster (if needed)
kubectl delete kafka kafka-cluster -n kafka
```

### 3. Post-Rollback Verification

```bash
# Verify original Kafka is running
kubectl get pods -l app.kubernetes.io/name=kafka -n <namespace>

# Test connectivity
kubectl exec -it <app-pod> -- \
  kafka-topics.sh --bootstrap-server <original-service>:9092 --list
```

## Post-Migration Tasks

### 1. Update Application Configurations

```yaml
# New connection configuration
KAFKA_BOOTSTRAP_SERVERS: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092

# For TLS
KAFKA_BOOTSTRAP_SERVERS: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9093
KAFKA_SECURITY_PROTOCOL: SSL

# For SCRAM authentication
KAFKA_SECURITY_PROTOCOL: SASL_PLAINTEXT
KAFKA_SASL_MECHANISM: SCRAM-SHA-512
KAFKA_SASL_USERNAME: my-app-user
KAFKA_SASL_PASSWORD: <from-secret>
```

### 2. Configure Monitoring

```bash
# Create PodMonitor for Prometheus
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-cluster
  namespace: kafka
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/cluster: kafka-cluster
      strimzi.io/kind: Kafka
  podMetricsEndpoints:
  - port: tcp-prometheus
    path: /metrics
EOF

# Import Strimzi Grafana dashboards
# Available at: https://github.com/strimzi/strimzi-kafka-operator/tree/main/examples/metrics/grafana-dashboards
```

### 3. Configure Alerts

```yaml
# Prometheus alerting rules
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kafka-alerts
  namespace: kafka
spec:
  groups:
    - name: kafka
      rules:
        - alert: KafkaBrokerDown
          expr: count(kafka_server_replicamanager_leadercount) < 3
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Kafka broker is down"

        - alert: KafkaUnderReplicatedPartitions
          expr: kafka_server_replicamanager_underreplicatedpartitions > 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Kafka has under-replicated partitions"

        - alert: KafkaConsumerLag
          expr: kafka_consumergroup_lag > 10000
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Kafka consumer group has high lag"
```

### 4. Set Up Cruise Control (Optional)

```yaml
# Add Cruise Control to Kafka cluster
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-cluster
spec:
  # ... existing spec ...
  cruiseControl:
    config:
      default.goals: >
        com.linkedin.kafka.cruisecontrol.analyzer.goals.RackAwareGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.ReplicaCapacityGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.DiskCapacityGoal,
        com.linkedin.kafka.cruisecontrol.analyzer.goals.NetworkInboundCapacityGoal
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: cruise-control-metrics
          key: metrics-config.yml
```

### 5. Clean Up Original Deployment

After verification period (1-2 weeks):

```bash
# Delete original Kafka
helm uninstall <kafka-release> -n <namespace>

# Delete PVCs
kubectl delete pvc -l app.kubernetes.io/name=kafka -n <namespace>
```

## Troubleshooting

### Common Issues

1. **Cluster not forming (KRaft):**
   ```bash
   # Check controller logs
   kubectl logs kafka-cluster-controller-0 -n kafka

   # Check broker logs
   kubectl logs kafka-cluster-broker-0 -n kafka
   ```

2. **Topic creation failures:**
   ```bash
   # Check entity operator logs
   kubectl logs kafka-cluster-entity-operator-xxx -c topic-operator -n kafka

   # Check KafkaTopic status
   kubectl describe kafkatopic my-topic -n kafka
   ```

3. **Authentication issues:**
   ```bash
   # Check user secret
   kubectl get secret my-app-user -n kafka -o yaml

   # Check user operator logs
   kubectl logs kafka-cluster-entity-operator-xxx -c user-operator -n kafka
   ```

4. **Performance issues:**
   ```bash
   # Check JMX metrics
   kubectl exec -it kafka-cluster-kafka-0 -n kafka -- \
     kafka-run-class.sh kafka.tools.JmxTool \
       --object-name kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec \
       --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi
   ```

## References

- [Strimzi Documentation](https://strimzi.io/docs/operators/latest/overview)
- [Strimzi GitHub](https://github.com/strimzi/strimzi-kafka-operator)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Strimzi Examples](https://github.com/strimzi/strimzi-kafka-operator/tree/main/examples)
