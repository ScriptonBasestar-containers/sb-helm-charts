# RabbitMQ Operator Migration Guide

Guide for migrating from the simple RabbitMQ Helm chart to the production-ready RabbitMQ Cluster Operator.

## Overview

This guide helps you migrate from the basic RabbitMQ chart in this repository to the production-ready RabbitMQ Cluster Operator with high availability, automated operations, and advanced features.

**Why migrate to the operator?**
- ✅ Automated high availability clustering
- ✅ Automatic peer discovery
- ✅ Rolling upgrades
- ✅ Automatic recovery from failures
- ✅ Prometheus metrics built-in
- ✅ TLS encryption
- ✅ Production-grade reliability
- ✅ Official VMware/Broadcom support

## Table of Contents

- [Operator Overview](#operator-overview)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Backup Procedures](#backup-procedures)
- [Migration Process](#migration-process)
- [Verification](#verification)
- [Rollback Plan](#rollback-plan)
- [Post-Migration Tasks](#post-migration-tasks)

## Operator Overview

### RabbitMQ Cluster Operator

**Project:** https://github.com/rabbitmq/cluster-operator

**Features:**
- ✅ Official RabbitMQ operator from VMware/Broadcom
- ✅ Automated cluster formation
- ✅ Quorum queues for HA
- ✅ Stream queues support
- ✅ Shovel and Federation plugins
- ✅ Prometheus metrics
- ✅ TLS/mTLS support
- ✅ LDAP authentication
- ✅ OAuth 2.0 support
- ✅ Rolling upgrades
- ✅ Automatic recovery

**Related Operators:**
- **RabbitMQ Messaging Topology Operator:** Manages users, vhosts, queues, exchanges via CRDs
- **RabbitMQ Standby Replication Operator:** Cross-datacenter replication

**Use Case:** Any production RabbitMQ deployment requiring HA and automated management.

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check current RabbitMQ version
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl version

# Check cluster status
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl cluster_status

# List all vhosts
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_vhosts

# List all users
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_users

# List all queues
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_queues -p / name messages

# List all exchanges
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_exchanges -p /

# List all bindings
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_bindings -p /

# Check enabled plugins
kubectl exec -it <rabbitmq-pod> -- rabbitmq-plugins list -e
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-rabbitmq-values.yaml

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i rabbit

# Export definitions (users, vhosts, queues, exchanges, bindings, policies)
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl export_definitions /tmp/definitions.json
kubectl cp <namespace>/<rabbitmq-pod>:/tmp/definitions.json ./rabbitmq-definitions.json
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small deployments (< 100 queues): 10-20 minutes
- Medium deployments (100-1000 queues): 20-45 minutes
- Large deployments (> 1000 queues): 45-90 minutes

**Factors affecting downtime:**
- Number of queues and messages
- Definition complexity
- Network speed

**Note:** Message migration is not automatic. Plan for message drainage or loss of in-flight messages.

## Backup Procedures

### Method 1: Definition Export (Recommended)

**Advantages:** Captures all metadata (users, vhosts, queues, exchanges, policies)
**Disadvantages:** Does not include messages

```bash
# Export all definitions
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl export_definitions /tmp/definitions.json

# Copy to local machine
kubectl cp <namespace>/<rabbitmq-pod>:/tmp/definitions.json ./rabbitmq-definitions.json

# Verify the export
cat rabbitmq-definitions.json | jq '.users | length'
cat rabbitmq-definitions.json | jq '.queues | length'
```

### Method 2: Message Backup via Shovel

**Advantages:** Can backup messages
**Disadvantages:** Complex setup, requires destination queue

```bash
# Enable shovel plugin if not already enabled
kubectl exec -it <rabbitmq-pod> -- rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management

# Configure shovel to backup queue (via management UI or API)
# This should be done before migration planning
```

### Method 3: Message Drainage

**Advantages:** No message loss
**Disadvantages:** Requires application coordination

```bash
# Stop producers first
# Wait for consumers to process all messages
kubectl exec -it <rabbitmq-pod> -- rabbitmqctl list_queues name messages

# Verify all queues are empty (or acceptable message count)
```

## Migration Process

### Step 1: Install the Operator

```bash
# Install via kubectl
kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"

# Or install via Helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install rabbitmq-cluster-operator bitnami/rabbitmq-cluster-operator \
  --namespace rabbitmq-system \
  --create-namespace

# Verify operator is running
kubectl get pods -n rabbitmq-system
```

### Step 2: Prepare RabbitmqCluster Definition

```yaml
# rabbitmq-cluster.yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq-cluster
  namespace: <target-namespace>
spec:
  # Number of replicas (odd number recommended for quorum)
  replicas: 3

  # RabbitMQ image
  image: rabbitmq:3.13.1-management

  # Persistence
  persistence:
    storageClassName: ""  # Use default storage class
    storage: 10Gi

  # Resources
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2
      memory: 2Gi

  # RabbitMQ configuration
  rabbitmq:
    additionalConfig: |
      cluster_partition_handling = pause_minority
      vm_memory_high_watermark_paging_ratio = 0.99
      disk_free_limit.relative = 1.0
      collect_statistics_interval = 10000

    # Additional plugins
    additionalPlugins:
      - rabbitmq_management
      - rabbitmq_prometheus
      - rabbitmq_peer_discovery_k8s
      - rabbitmq_shovel
      - rabbitmq_shovel_management

  # Service configuration
  service:
    type: ClusterIP
    annotations: {}

  # TLS (optional)
  tls:
    secretName: ""  # TLS secret name if using TLS

  # Override configuration
  override:
    statefulSet:
      spec:
        template:
          spec:
            containers: []
            topologySpreadConstraints:
              - maxSkew: 1
                topologyKey: topology.kubernetes.io/zone
                whenUnsatisfiable: ScheduleAnyway
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: rabbitmq-cluster
```

### Step 3: Deploy the Cluster

```bash
kubectl apply -f rabbitmq-cluster.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready rabbitmqcluster/rabbitmq-cluster \
  -n <target-namespace> --timeout=600s

# Check status
kubectl get rabbitmqcluster -n <target-namespace>
kubectl describe rabbitmqcluster rabbitmq-cluster -n <target-namespace>
```

### Step 4: Get Credentials

```bash
# Get default user credentials
kubectl get secret rabbitmq-cluster-default-user \
  -n <target-namespace> \
  -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret rabbitmq-cluster-default-user \
  -n <target-namespace> \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Get service endpoint
kubectl get svc rabbitmq-cluster -n <target-namespace>
```

### Step 5: Import Definitions

```bash
# Port-forward to management UI
kubectl port-forward -n <target-namespace> svc/rabbitmq-cluster 15672:15672

# Import via management API
curl -u <username>:<password> \
  -X POST \
  -H "Content-Type: application/json" \
  -d @rabbitmq-definitions.json \
  http://localhost:15672/api/definitions

# Or use rabbitmqctl from within a pod
kubectl cp rabbitmq-definitions.json \
  <target-namespace>/rabbitmq-cluster-server-0:/tmp/definitions.json

kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl import_definitions /tmp/definitions.json
```

### Step 6: (Optional) Install Messaging Topology Operator

For declarative management of users, vhosts, queues, exchanges:

```bash
# Install the operator
kubectl apply -f "https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml"

# Create users, vhosts, queues declaratively
cat <<EOF | kubectl apply -f -
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: myapp-user
  namespace: <target-namespace>
spec:
  rabbitmqClusterReference:
    name: rabbitmq-cluster
  tags:
    - management
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rabbitmq.com/v1beta1
kind: Vhost
metadata:
  name: myapp-vhost
  namespace: <target-namespace>
spec:
  name: myapp
  rabbitmqClusterReference:
    name: rabbitmq-cluster
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: myapp-queue
  namespace: <target-namespace>
spec:
  name: my-queue
  vhost: myapp
  type: quorum  # or classic
  durable: true
  rabbitmqClusterReference:
    name: rabbitmq-cluster
EOF
```

## Verification

### 1. Check Cluster Status

```bash
# Check RabbitmqCluster resource
kubectl get rabbitmqcluster -n <target-namespace>

# Check cluster status via rabbitmqctl
kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl cluster_status

# Check all pods are running
kubectl get pods -l app.kubernetes.io/name=rabbitmq-cluster -n <target-namespace>
```

### 2. Verify Definitions

```bash
# List vhosts
kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl list_vhosts

# List users
kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl list_users

# List queues
kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl list_queues -p / name type messages

# List exchanges
kubectl exec -it rabbitmq-cluster-server-0 -n <target-namespace> -- \
  rabbitmqctl list_exchanges -p /
```

### 3. Test Connectivity

```bash
# Port-forward to AMQP
kubectl port-forward -n <target-namespace> svc/rabbitmq-cluster 5672:5672

# Test with Python (pika)
python3 << 'EOF'
import pika

credentials = pika.PlainCredentials('default_user', 'password')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', 5672, '/', credentials)
)
channel = connection.channel()
channel.queue_declare(queue='test_queue')
channel.basic_publish(exchange='', routing_key='test_queue', body='Hello!')
print("Message sent successfully")
connection.close()
EOF
```

### 4. Verify Management UI

```bash
# Port-forward
kubectl port-forward -n <target-namespace> svc/rabbitmq-cluster 15672:15672

# Open http://localhost:15672
# Login with credentials from secret
```

## Rollback Plan

### 1. Keep Original Deployment Running

```bash
# Scale down original (but don't delete)
kubectl scale deployment <rabbitmq-deployment> --replicas=0 -n <namespace>
# or for StatefulSet
kubectl scale statefulset <rabbitmq-statefulset> --replicas=0 -n <namespace>
```

### 2. Rollback Procedure

If issues occur:

```bash
# Scale up original RabbitMQ
kubectl scale deployment <rabbitmq-deployment> --replicas=1 -n <namespace>

# Update application connection strings
kubectl set env deployment/<app> RABBITMQ_HOST=<original-rabbitmq-service>

# Delete operator cluster (if needed)
kubectl delete rabbitmqcluster rabbitmq-cluster -n <target-namespace>
```

### 3. Post-Rollback Verification

```bash
# Verify original RabbitMQ is running
kubectl get pods -l app.kubernetes.io/name=rabbitmq -n <namespace>

# Test connectivity
kubectl exec -it <app-pod> -- nc -zv <original-rabbitmq-service> 5672
```

## Post-Migration Tasks

### 1. Update Application Configurations

```yaml
# New connection configuration
RABBITMQ_HOST: rabbitmq-cluster.<namespace>.svc.cluster.local
RABBITMQ_PORT: "5672"
RABBITMQ_USER: default_user
RABBITMQ_PASS: <from-secret>
RABBITMQ_VHOST: /

# Connection string format
RABBITMQ_URI: amqp://default_user:<password>@rabbitmq-cluster.<namespace>.svc.cluster.local:5672/
```

### 2. Configure Monitoring

```bash
# Create ServiceMonitor for Prometheus
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq-cluster
  namespace: <target-namespace>
spec:
  endpoints:
  - port: prometheus
    interval: 15s
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq-cluster
EOF

# Or use PodMonitor
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: rabbitmq-cluster
  namespace: <target-namespace>
spec:
  podMetricsEndpoints:
  - port: prometheus
    interval: 15s
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq-cluster
EOF
```

### 3. Configure Alerts

```yaml
# Prometheus alerting rules
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: rabbitmq-alerts
  namespace: <target-namespace>
spec:
  groups:
    - name: rabbitmq
      rules:
        - alert: RabbitMQNodeDown
          expr: rabbitmq_build_info == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "RabbitMQ node is down"

        - alert: RabbitMQHighMemory
          expr: rabbitmq_process_resident_memory_bytes / rabbitmq_resident_memory_limit_bytes > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "RabbitMQ memory usage is high"

        - alert: RabbitMQQueueBacklog
          expr: rabbitmq_queue_messages > 10000
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "RabbitMQ queue has high message backlog"
```

### 4. Enable TLS (Recommended for Production)

```bash
# Create TLS secret
kubectl create secret tls rabbitmq-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n <target-namespace>

# Update cluster to use TLS
kubectl patch rabbitmqcluster rabbitmq-cluster -n <target-namespace> \
  --type=merge \
  -p '{"spec":{"tls":{"secretName":"rabbitmq-tls"}}}'
```

### 5. Clean Up Original Deployment

After verification period (1-2 weeks):

```bash
# Delete original RabbitMQ
helm uninstall <rabbitmq-release> -n <namespace>

# Delete PVCs
kubectl delete pvc -l app.kubernetes.io/name=rabbitmq -n <namespace>
```

## Troubleshooting

### Common Issues

1. **Cluster not forming:**
   ```bash
   # Check operator logs
   kubectl logs -n rabbitmq-system deploy/rabbitmq-cluster-operator

   # Check pod logs
   kubectl logs rabbitmq-cluster-server-0 -n <target-namespace>
   ```

2. **Definition import failures:**
   ```bash
   # Check for invalid definitions
   kubectl exec -it rabbitmq-cluster-server-0 -- \
     rabbitmqctl import_definitions /tmp/definitions.json --skip-if-unchanged
   ```

3. **Memory issues:**
   ```bash
   # Check memory status
   kubectl exec -it rabbitmq-cluster-server-0 -- \
     rabbitmqctl status | grep -A 5 "Memory"

   # Adjust memory limits in cluster spec
   ```

4. **Disk space issues:**
   ```bash
   # Check disk status
   kubectl exec -it rabbitmq-cluster-server-0 -- \
     rabbitmqctl status | grep -A 5 "Disk"
   ```

## References

- [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)
- [RabbitMQ Messaging Topology Operator](https://github.com/rabbitmq/messaging-topology-operator)
- [RabbitMQ Clustering Guide](https://www.rabbitmq.com/clustering.html)
- [RabbitMQ Quorum Queues](https://www.rabbitmq.com/quorum-queues.html)
- [RabbitMQ Production Checklist](https://www.rabbitmq.com/production-checklist.html)
