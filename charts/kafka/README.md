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

## License

This Helm chart is licensed under the BSD-3-Clause License.

Apache Kafka is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Maintainers

- [ScriptonBasestar](https://github.com/scriptonbasestar-container)

---

**Chart Version:** 0.3.0
**Kafka Version:** 3.9.0
**Last Updated:** 2025-11
