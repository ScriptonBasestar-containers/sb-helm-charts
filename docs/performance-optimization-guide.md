# Performance Optimization Guide

**Version**: v1.4.0
**Last Updated**: 2025-12-09
**Scope**: Performance optimization strategies for all enhanced Helm charts

## Table of Contents

1. [Overview](#overview)
2. [Resource Sizing Guidelines](#resource-sizing-guidelines)
3. [Scaling Strategies](#scaling-strategies)
4. [Database Performance](#database-performance)
5. [Storage Performance](#storage-performance)
6. [Network Optimization](#network-optimization)
7. [Caching Strategies](#caching-strategies)
8. [Benchmarking Methodologies](#benchmarking-methodologies)
9. [Monitoring & Profiling](#monitoring--profiling)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive performance optimization strategies for the ScriptonBasestar Helm charts ecosystem, covering resource sizing, scaling strategies, and performance tuning for all 28 enhanced charts.

### Performance Optimization Principles

1. **Measure First**: Always profile and benchmark before optimizing
2. **Identify Bottlenecks**: CPU, memory, disk I/O, network, or application-level
3. **Optimize Iteratively**: Make one change at a time and measure impact
4. **Right-Size Resources**: Avoid both under-provisioning and over-provisioning
5. **Scale Appropriately**: Choose horizontal vs vertical scaling based on workload

### Performance Tiers

| Tier | Performance Target | Use Case |
|------|-------------------|----------|
| **High Performance** | < 100ms p99 latency, > 10k RPS | Production critical services |
| **Standard** | < 500ms p99 latency, > 1k RPS | Production standard services |
| **Development** | < 2s p99 latency, > 100 RPS | Development and testing |

---

## Resource Sizing Guidelines

### Resource Sizing Matrix

#### Tier 1: Critical Infrastructure

**PostgreSQL**

| Workload | vCPU | Memory | Storage IOPS | Connections | Use Case |
|----------|------|--------|--------------|-------------|----------|
| **Small** | 2 | 4 GB | 3000 | 100 | Dev/Test, < 10 GB data |
| **Medium** | 4 | 8 GB | 6000 | 200 | Small production, < 50 GB data |
| **Large** | 8 | 16 GB | 12000 | 500 | Large production, < 200 GB data |
| **XLarge** | 16 | 32 GB | 24000 | 1000 | Enterprise, > 200 GB data |

**Sizing Formula**:
```
Memory = (shared_buffers + work_mem * max_connections + maintenance_work_mem + OS cache)
shared_buffers = 25% of total memory
work_mem = (Memory - shared_buffers) / (max_connections * 3)
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

postgresql:
  max_connections: 200
  shared_buffers: 4GB
  effective_cache_size: 12GB
  maintenance_work_mem: 2GB
  work_mem: 20MB
```

---

**MySQL/MariaDB**

| Workload | vCPU | Memory | Storage IOPS | Connections | Use Case |
|----------|------|--------|--------------|-------------|----------|
| **Small** | 2 | 4 GB | 3000 | 150 | Dev/Test, < 10 GB data |
| **Medium** | 4 | 8 GB | 6000 | 300 | Small production, < 50 GB data |
| **Large** | 8 | 16 GB | 12000 | 500 | Large production, < 200 GB data |
| **XLarge** | 16 | 32 GB | 24000 | 1000 | Enterprise, > 200 GB data |

**Sizing Formula**:
```
Memory = (innodb_buffer_pool_size + key_buffer_size + max_connections * (read_buffer_size + sort_buffer_size) + OS cache)
innodb_buffer_pool_size = 70-80% of total memory
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

mysql:
  max_connections: 500
  innodb_buffer_pool_size: 12G
  innodb_log_file_size: 2G
  query_cache_size: 256M
  tmp_table_size: 256M
```

---

**MongoDB**

| Workload | vCPU | Memory | Storage IOPS | Connections | Use Case |
|----------|------|--------|--------------|-------------|----------|
| **Small** | 2 | 4 GB | 3000 | 1000 | Dev/Test, < 10 GB data |
| **Medium** | 4 | 8 GB | 6000 | 2000 | Small production, < 50 GB data |
| **Large** | 8 | 16 GB | 12000 | 5000 | Large production, < 500 GB data |
| **XLarge** | 16 | 32 GB | 24000 | 10000 | Enterprise, > 500 GB data |

**Sizing Formula**:
```
Memory = (Working Set + Indexes + Connections overhead + OS cache)
Working Set ≈ Frequently accessed data (should fit in memory)
WiredTiger Cache = 50% of (Memory - 1GB)
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

mongodb:
  wiredTigerCacheSizeGB: 7.5  # 50% of (16GB - 1GB)
  maxIncomingConnections: 5000
```

---

**Redis**

| Workload | vCPU | Memory | Use Case |
|----------|------|--------|----------|
| **Small** | 1 | 2 GB | Dev/Test, cache < 1 GB |
| **Medium** | 2 | 4 GB | Small production, cache < 3 GB |
| **Large** | 4 | 8 GB | Large production, cache < 6 GB |
| **XLarge** | 8 | 16 GB | Enterprise, cache < 12 GB |

**Sizing Formula**:
```
Memory = (Dataset size * 1.5) + (Memory overhead for fragmentation)
Redis maxmemory = 75% of total memory (leave 25% for OS and fragmentation)
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 4000m
    memory: 8Gi

redis:
  maxmemory: 6gb
  maxmemory-policy: allkeys-lru
```

---

**Elasticsearch**

| Workload | vCPU | Memory | Storage IOPS | Heap Size | Use Case |
|----------|------|--------|--------------|-----------|----------|
| **Small** | 2 | 4 GB | 3000 | 2 GB | Dev/Test, < 50 GB indices |
| **Medium** | 4 | 8 GB | 6000 | 4 GB | Small production, < 200 GB indices |
| **Large** | 8 | 16 GB | 12000 | 8 GB | Large production, < 1 TB indices |
| **XLarge** | 16 | 32 GB | 24000 | 16 GB | Enterprise, > 1 TB indices |

**Sizing Formula**:
```
Heap Size = min(32GB, 50% of total memory)
File System Cache = 50% of total memory
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

elasticsearch:
  javaOpts: "-Xms8g -Xmx8g"  # Heap size = 50% of memory
```

---

**Kafka**

| Workload | vCPU | Memory | Storage IOPS | Throughput | Use Case |
|----------|------|--------|--------------|------------|----------|
| **Small** | 2 | 4 GB | 3000 | 10 MB/s | Dev/Test, low throughput |
| **Medium** | 4 | 8 GB | 6000 | 50 MB/s | Small production |
| **Large** | 8 | 16 GB | 12000 | 200 MB/s | Large production |
| **XLarge** | 16 | 32 GB | 24000 | 500 MB/s | Enterprise, high throughput |

**Sizing Formula**:
```
Memory = (Page Cache for active segments + Heap + OS)
Page Cache = 70% of memory (for recent log segments)
Heap = 4-6 GB (not more, for GC performance)
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

kafka:
  heap: "-Xms4g -Xmx4g"
  num.network.threads: 8
  num.io.threads: 16
  socket.send.buffer.bytes: 102400
  socket.receive.buffer.bytes: 102400
```

---

**RabbitMQ**

| Workload | vCPU | Memory | Throughput | Use Case |
|----------|------|--------|------------|----------|
| **Small** | 2 | 4 GB | 1k msg/s | Dev/Test |
| **Medium** | 4 | 8 GB | 10k msg/s | Small production |
| **Large** | 8 | 16 GB | 50k msg/s | Large production |
| **XLarge** | 16 | 32 GB | 100k msg/s | Enterprise |

**Sizing Formula**:
```
Memory = (Message backlog size + Connection overhead + VM overhead)
vm_memory_high_watermark = 0.4 (40% of total memory)
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

rabbitmq:
  vm_memory_high_watermark.relative: 0.4
  channel_max: 2048
  heartbeat: 60
```

---

#### Tier 2: Core Services

**Prometheus**

| Workload | vCPU | Memory | Storage | Retention | Samples/s | Use Case |
|----------|------|--------|---------|-----------|-----------|----------|
| **Small** | 2 | 4 GB | 50 GB | 7 days | 10k | Dev/Test, < 100 targets |
| **Medium** | 4 | 8 GB | 200 GB | 15 days | 50k | Small production, < 500 targets |
| **Large** | 8 | 16 GB | 1 TB | 30 days | 200k | Large production, < 2000 targets |
| **XLarge** | 16 | 32 GB | 5 TB | 90 days | 1M | Enterprise, > 2000 targets |

**Sizing Formula**:
```
Memory (GB) = (Samples/s * Retention seconds * 2 bytes) / 1024^3 * 1.5
Storage (GB) = Samples/s * Retention seconds * 1.5 bytes / 1024^3
```

**Example**: 100k samples/s, 30 days retention
- Memory: (100k * 2.6M seconds * 2 bytes) / 1024^3 * 1.5 ≈ 12 GB
- Storage: (100k * 2.6M seconds * 1.5 bytes) / 1024^3 ≈ 365 GB

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

prometheus:
  retention: 30d
  storage.tsdb.max-block-duration: 2h
  storage.tsdb.min-block-duration: 2h
```

---

**Grafana**

| Workload | vCPU | Memory | Storage | Users | Dashboards | Use Case |
|----------|------|--------|---------|-------|------------|----------|
| **Small** | 1 | 2 GB | 10 GB | < 50 | < 100 | Dev/Test |
| **Medium** | 2 | 4 GB | 20 GB | < 200 | < 500 | Small production |
| **Large** | 4 | 8 GB | 50 GB | < 1000 | < 2000 | Large production |
| **XLarge** | 8 | 16 GB | 100 GB | > 1000 | > 2000 | Enterprise |

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 8Gi

grafana:
  GF_DATABASE_MAX_IDLE_CONN: 100
  GF_DATABASE_MAX_OPEN_CONN: 300
  GF_DATAPROXY_TIMEOUT: 30
  GF_DATAPROXY_KEEP_ALIVE_SECONDS: 30
```

---

**Loki**

| Workload | vCPU | Memory | Storage | Retention | Log Rate | Use Case |
|----------|------|--------|---------|-----------|----------|----------|
| **Small** | 2 | 4 GB | 50 GB | 7 days | 10 MB/s | Dev/Test |
| **Medium** | 4 | 8 GB | 200 GB | 15 days | 50 MB/s | Small production |
| **Large** | 8 | 16 GB | 1 TB | 30 days | 200 MB/s | Large production |
| **XLarge** | 16 | 32 GB | 5 TB | 90 days | 500 MB/s | Enterprise |

**Sizing Formula**:
```
Storage (GB) = Log rate (MB/s) * Retention (seconds) * Compression ratio (0.1-0.3) / 1024
Memory (GB) = Active streams * 5 KB + Chunk cache + Index cache
```

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 4000m
    memory: 8Gi
  limits:
    cpu: 8000m
    memory: 16Gi

loki:
  chunk_cache:
    max_size_mb: 4096
  index_cache:
    max_size_mb: 2048
  ingester:
    chunk_target_size: 1572864
    max_chunk_age: 2h
```

---

#### Tier 3: Applications

**Keycloak**

| Workload | vCPU | Memory | Users | Sessions | Use Case |
|----------|------|--------|-------|----------|----------|
| **Small** | 2 | 2 GB | < 1k | < 10k | Dev/Test |
| **Medium** | 4 | 4 GB | < 10k | < 100k | Small production |
| **Large** | 8 | 8 GB | < 100k | < 1M | Large production |
| **XLarge** | 16 | 16 GB | > 100k | > 1M | Enterprise |

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 8000m
    memory: 8Gi

keycloak:
  javaOpts: "-Xms4g -Xmx4g -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
```

---

**Nextcloud**

| Workload | vCPU | Memory | Storage | Users | Files | Use Case |
|----------|------|--------|---------|-------|-------|----------|
| **Small** | 2 | 2 GB | 100 GB | < 50 | < 10k | Personal/Family |
| **Medium** | 4 | 4 GB | 500 GB | < 200 | < 100k | Small team |
| **Large** | 8 | 8 GB | 2 TB | < 1000 | < 1M | Organization |
| **XLarge** | 16 | 16 GB | 10 TB | > 1000 | > 1M | Enterprise |

**Example Configuration (Large)**:
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 8000m
    memory: 8Gi

nextcloud:
  phpMemoryLimit: 2048M
  phpUploadLimit: 16G
  phpMaxExecutionTime: 3600
  opcache.memory_consumption: 512
```

---

### Resource Sizing Calculator

**Script**: `scripts/calculate-resources.sh`

```bash
#!/bin/bash
# Resource sizing calculator for Helm charts
# Usage: ./scripts/calculate-resources.sh <chart> <workload-type> <data-size>

CHART="$1"
WORKLOAD="$2"  # small, medium, large, xlarge
DATA_SIZE="$3"  # in GB

case "${CHART}" in
    postgresql)
        case "${WORKLOAD}" in
            small)
                echo "vCPU: 2, Memory: 4GB, Storage IOPS: 3000"
                echo "shared_buffers: 1GB, max_connections: 100"
                ;;
            medium)
                echo "vCPU: 4, Memory: 8GB, Storage IOPS: 6000"
                echo "shared_buffers: 2GB, max_connections: 200"
                ;;
            large)
                echo "vCPU: 8, Memory: 16GB, Storage IOPS: 12000"
                echo "shared_buffers: 4GB, max_connections: 500"
                ;;
            xlarge)
                echo "vCPU: 16, Memory: 32GB, Storage IOPS: 24000"
                echo "shared_buffers: 8GB, max_connections: 1000"
                ;;
        esac
        ;;

    prometheus)
        # Calculate based on samples/s and retention
        SAMPLES_PER_SEC="${4:-100000}"  # Default 100k samples/s
        RETENTION_DAYS="${5:-30}"        # Default 30 days

        RETENTION_SECONDS=$((RETENTION_DAYS * 86400))
        MEMORY_GB=$(echo "scale=0; (${SAMPLES_PER_SEC} * ${RETENTION_SECONDS} * 2 / 1024 / 1024 / 1024) * 1.5" | bc)
        STORAGE_GB=$(echo "scale=0; ${SAMPLES_PER_SEC} * ${RETENTION_SECONDS} * 1.5 / 1024 / 1024 / 1024" | bc)

        echo "Samples/s: ${SAMPLES_PER_SEC}, Retention: ${RETENTION_DAYS} days"
        echo "Memory: ${MEMORY_GB} GB, Storage: ${STORAGE_GB} GB"
        ;;

    # ... (similar calculations for other charts)
esac
```

---

## Scaling Strategies

### Horizontal vs Vertical Scaling Decision Matrix

| Scaling Type | When to Use | Advantages | Disadvantages | Best For |
|--------------|-------------|------------|---------------|----------|
| **Horizontal (Scale Out)** | Workload is stateless or can be sharded | - No single point of failure<br>- Linear scaling<br>- Better fault tolerance | - More complex<br>- Network overhead<br>- Eventual consistency | - Web servers<br>- API gateways<br>- Stateless services<br>- Prometheus (federation)<br>- Kafka (partitions) |
| **Vertical (Scale Up)** | Workload requires shared state or strong consistency | - Simple to implement<br>- No code changes<br>- Strong consistency | - Limited by hardware<br>- Single point of failure<br>- Downtime for upgrades | - Databases (PostgreSQL, MySQL)<br>- Redis (single instance)<br>- Loki (single-binary mode)<br>- Stateful services |
| **Hybrid** | Mixed workload with stateful and stateless components | - Best of both worlds<br>- Optimize per component | - Complex architecture<br>- Requires careful planning | - Elasticsearch (vertical nodes, horizontal shards)<br>- Kafka (vertical brokers, horizontal partitions)<br>- MongoDB (vertical replica set members, horizontal shards) |

---

### Horizontal Scaling Patterns

#### Pattern 1: Stateless Horizontal Scaling (HPA)

**Use Case**: Grafana, Keycloak, Nextcloud (PHP-FPM), WordPress

**Implementation**:

```yaml
# HorizontalPodAutoscaler based on CPU and memory
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: grafana-hpa
  namespace: monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: grafana
  minReplicas: 2
  maxReplicas: 10
  metrics:
    # CPU-based scaling
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

    # Memory-based scaling
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80

    # Custom metric: Request rate (via Prometheus)
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "1000"

  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # 5 minutes
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60  # 1 minute
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
        - type: Pods
          value: 2
          periodSeconds: 30
      selectPolicy: Max
```

---

#### Pattern 2: Sharded Horizontal Scaling

**Use Case**: Prometheus (federation), Elasticsearch (sharding), Kafka (partitions)

**Prometheus Federation Example**:

```yaml
# Deploy multiple Prometheus instances, each scraping a subset of targets
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus-shard-0
spec:
  serviceName: prometheus-shard-0
  replicas: 1
  template:
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:v2.45.0
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --storage.tsdb.retention.time=7d
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
      volumes:
        - name: config
          configMap:
            name: prometheus-shard-0-config

---
# Prometheus shard 0 config (scrapes targets 0-999)
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-shard-0-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          # Shard by pod name hash (0-999 out of 2000)
          - source_labels: [__meta_kubernetes_pod_name]
            modulus: 2000
            target_label: __tmp_hash
            action: hashmod
          - source_labels: [__tmp_hash]
            regex: "(0|[1-9][0-9]{0,2})"  # 0-999
            action: keep

---
# Global Prometheus federates all shards
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-global-config
data:
  prometheus.yml: |
    scrape_configs:
      - job_name: 'federate'
        scrape_interval: 60s
        honor_labels: true
        metrics_path: '/federate'
        params:
          'match[]':
            - '{job=~".+"}'
        static_configs:
          - targets:
              - 'prometheus-shard-0:9090'
              - 'prometheus-shard-1:9090'
```

---

#### Pattern 3: Read Replicas (Databases)

**Use Case**: PostgreSQL, MySQL, MongoDB read scaling

**PostgreSQL Streaming Replication Example**:

```yaml
# Primary (read-write)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-primary
spec:
  serviceName: postgresql-primary
  replicas: 1
  template:
    spec:
      containers:
        - name: postgresql
          image: postgres:16
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgresql-password
                  key: password
            - name: POSTGRES_INITDB_ARGS
              value: "-c wal_level=replica -c max_wal_senders=10 -c max_replication_slots=10"

---
# Read replica (read-only)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-replica
spec:
  serviceName: postgresql-replica
  replicas: 2  # 2 read replicas for horizontal scaling
  template:
    spec:
      containers:
        - name: postgresql
          image: postgres:16
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgresql-password
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          command:
            - bash
            - -c
            - |
              # Wait for primary to be ready
              until pg_isready -h postgresql-primary-0.postgresql-primary -U postgres; do
                sleep 1
              done

              # Base backup from primary
              pg_basebackup -h postgresql-primary-0.postgresql-primary -D /var/lib/postgresql/data/pgdata -U postgres -v -P -W

              # Configure as replica
              cat > /var/lib/postgresql/data/pgdata/postgresql.auto.conf <<EOF
              primary_conninfo = 'host=postgresql-primary-0.postgresql-primary port=5432 user=postgres password=${POSTGRES_PASSWORD}'
              primary_slot_name = 'replica_slot'
              hot_standby = on
              EOF

              touch /var/lib/postgresql/data/pgdata/standby.signal

              # Start PostgreSQL
              docker-entrypoint.sh postgres

---
# Service for read traffic (load balanced across replicas)
apiVersion: v1
kind: Service
metadata:
  name: postgresql-read
spec:
  selector:
    app: postgresql-replica
  ports:
    - port: 5432
      targetPort: 5432
  sessionAffinity: ClientIP  # Sticky sessions for read consistency
```

**Application Configuration for Read Replicas**:

```python
# Python example using psycopg2
import psycopg2
from psycopg2.pool import SimpleConnectionPool

# Connection pools
write_pool = SimpleConnectionPool(
    1, 20,
    host="postgresql-primary",
    port=5432,
    database="mydb",
    user="postgres",
    password="password"
)

read_pool = SimpleConnectionPool(
    1, 50,  # More connections for reads
    host="postgresql-read",  # Load balanced service
    port=5432,
    database="mydb",
    user="postgres",
    password="password"
)

# Use write pool for writes
def insert_user(name, email):
    conn = write_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO users (name, email) VALUES (%s, %s)", (name, email))
        conn.commit()
    finally:
        write_pool.putconn(conn)

# Use read pool for reads
def get_users():
    conn = read_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM users")
        return cur.fetchall()
    finally:
        read_pool.putconn(conn)
```

---

### Vertical Scaling Patterns

#### Pattern 1: In-Place Vertical Scaling

**Use Case**: Development environments, single-instance databases

**Limitations**:
- Requires pod restart (downtime)
- Limited by node capacity
- No rollback mechanism

**Implementation**:

```bash
# 1. Check current resources
kubectl get pod postgresql-0 -o jsonpath='{.spec.containers[0].resources}'

# 2. Scale up via Helm upgrade
helm upgrade my-pg scripton-charts/postgresql \
  --set resources.requests.cpu=4000m \
  --set resources.requests.memory=8Gi \
  --set resources.limits.cpu=8000m \
  --set resources.limits.memory=16Gi \
  --reuse-values

# 3. Wait for pod restart
kubectl rollout status statefulset/postgresql

# 4. Verify new resources
kubectl get pod postgresql-0 -o jsonpath='{.spec.containers[0].resources}'
```

---

#### Pattern 2: Blue-Green Vertical Scaling (Zero Downtime)

**Use Case**: Production databases requiring zero downtime

**Implementation**:

```bash
# 1. Deploy new StatefulSet with larger resources (Blue-Green)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-new
spec:
  serviceName: postgresql-new
  replicas: 1
  template:
    spec:
      containers:
        - name: postgresql
          image: postgres:16
          resources:
            requests:
              cpu: 4000m
              memory: 8Gi
            limits:
              cpu: 8000m
              memory: 16Gi
EOF

# 2. Restore data to new instance
kubectl exec -i postgresql-new-0 -- psql -U postgres < backup.sql

# 3. Switch service to new instance
kubectl patch service postgresql -p '{"spec":{"selector":{"app":"postgresql-new"}}}'

# 4. Verify traffic switched
kubectl get endpoints postgresql

# 5. Delete old StatefulSet
kubectl delete statefulset postgresql-old
```

---

### Autoscaling Advanced Strategies

#### KEDA (Kubernetes Event-Driven Autoscaling)

**Use Case**: Event-driven workloads (Kafka consumers, RabbitMQ workers)

**Installation**:

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace
```

**Kafka Consumer Autoscaling Example**:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: airflow-worker-scaler
  namespace: airflow
spec:
  scaleTargetRef:
    name: airflow-worker
    kind: Deployment

  minReplicaCount: 2
  maxReplicaCount: 20

  triggers:
    # Scale based on Kafka consumer lag
    - type: kafka
      metadata:
        bootstrapServers: kafka:9092
        consumerGroup: airflow-workers
        topic: airflow-tasks
        lagThreshold: "100"  # Scale up if lag > 100 messages

    # Scale based on pending tasks (custom metric from Airflow)
    - type: prometheus
      metadata:
        serverAddress: http://prometheus:9090
        metricName: airflow_scheduler_tasks_pending
        threshold: "50"
        query: sum(airflow_scheduler_tasks_pending)
```

---

## Database Performance

### PostgreSQL Performance Tuning

#### 1. Query Optimization

**Analyze Query Performance**:

```sql
-- Enable query timing
\timing on

-- Explain query plan
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT u.name, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > NOW() - INTERVAL '30 days'
GROUP BY u.id, u.name
ORDER BY order_count DESC
LIMIT 100;

-- Check slow queries
SELECT
    (total_time / 1000 / 60) as total_minutes,
    (mean_time / 1000) as avg_seconds,
    calls,
    query
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 20;
```

**Optimization Techniques**:

1. **Indexing**:
```sql
-- Create index on frequently queried columns
CREATE INDEX CONCURRENTLY idx_users_created_at ON users(created_at);

-- Partial index for common filters
CREATE INDEX CONCURRENTLY idx_orders_active ON orders(status) WHERE status = 'active';

-- Composite index for multi-column queries
CREATE INDEX CONCURRENTLY idx_orders_user_date ON orders(user_id, created_at DESC);

-- Check index usage
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

2. **Partitioning**:
```sql
-- Partition large tables by date range
CREATE TABLE orders_partitioned (
    id SERIAL,
    user_id INT,
    created_at TIMESTAMP,
    amount DECIMAL
) PARTITION BY RANGE (created_at);

-- Create partitions
CREATE TABLE orders_2025_01 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE orders_2025_02 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- Auto-create partitions with pg_partman extension
CREATE EXTENSION pg_partman;
SELECT partman.create_parent(
    'public.orders_partitioned',
    'created_at',
    'native',
    'monthly'
);
```

3. **Vacuuming and Maintenance**:
```sql
-- Vacuum and analyze (manual)
VACUUM ANALYZE users;

-- Check table bloat
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    n_live_tup,
    n_dead_tup,
    round(100 * n_dead_tup / (n_live_tup + n_dead_tup), 2) as dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;

-- Autovacuum tuning (postgresql.conf)
autovacuum_max_workers = 4
autovacuum_naptime = 30s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
```

#### 2. Connection Pooling

**PgBouncer Deployment**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: pgbouncer
          image: pgbouncer/pgbouncer:1.21.0
          ports:
            - containerPort: 5432
          env:
            - name: DATABASES_HOST
              value: "postgresql-primary"
            - name: DATABASES_PORT
              value: "5432"
            - name: DATABASES_DBNAME
              value: "*"
            - name: PGBOUNCER_POOL_MODE
              value: "transaction"  # session, transaction, or statement
            - name: PGBOUNCER_MAX_CLIENT_CONN
              value: "10000"
            - name: PGBOUNCER_DEFAULT_POOL_SIZE
              value: "25"
            - name: PGBOUNCER_MIN_POOL_SIZE
              value: "10"
            - name: PGBOUNCER_RESERVE_POOL_SIZE
              value: "10"
            - name: PGBOUNCER_MAX_DB_CONNECTIONS
              value: "100"
          volumeMounts:
            - name: config
              mountPath: /etc/pgbouncer
      volumes:
        - name: config
          configMap:
            name: pgbouncer-config

---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer
spec:
  selector:
    app: pgbouncer
  ports:
    - port: 5432
      targetPort: 5432
```

**Pool Mode Selection**:

| Pool Mode | Use Case | Pros | Cons |
|-----------|----------|------|------|
| **Session** | Legacy apps, prepared statements | Full PostgreSQL features | No connection multiplexing |
| **Transaction** | Most applications | Good multiplexing, most features work | Some features incompatible (LISTEN/NOTIFY, cursors) |
| **Statement** | Simple queries, maximum density | Maximum connection multiplexing | Very limited features |

---

### MySQL/MariaDB Performance Tuning

#### 1. InnoDB Optimization

**Configuration Tuning** (my.cnf):

```ini
[mysqld]
# Buffer Pool (70-80% of memory)
innodb_buffer_pool_size = 12G
innodb_buffer_pool_instances = 8

# Log Files (25% of buffer pool)
innodb_log_file_size = 2G
innodb_log_buffer_size = 32M

# I/O Configuration
innodb_flush_log_at_trx_commit = 2  # 1 = full ACID, 2 = faster but less durable
innodb_flush_method = O_DIRECT
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000

# Thread Configuration
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_purge_threads = 4

# Connection Configuration
max_connections = 500
back_log = 500
thread_cache_size = 100

# Query Cache (consider disabling in MySQL 8.0+)
query_cache_type = 0
query_cache_size = 0

# Temporary Tables
tmp_table_size = 256M
max_heap_table_size = 256M

# Slow Query Log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1
log_queries_not_using_indexes = 1
```

#### 2. Query Optimization

**Analyze Slow Queries**:

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;

-- Check query execution plan
EXPLAIN
SELECT u.name, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY u.id, u.name
ORDER BY order_count DESC
LIMIT 100;

-- Analyze slow queries from log
mysqldumpslow -s t -t 20 /var/log/mysql/slow.log
```

**Indexing Strategies**:

```sql
-- Create indexes
ALTER TABLE users ADD INDEX idx_created_at (created_at);
ALTER TABLE orders ADD INDEX idx_user_id_created_at (user_id, created_at);

-- Check index usage
SHOW INDEX FROM users;

-- Optimize tables
OPTIMIZE TABLE users;
OPTIMIZE TABLE orders;
```

---

### MongoDB Performance Tuning

#### 1. Index Optimization

**Create Indexes**:

```javascript
// Connect to MongoDB
db = db.getSiblingDB('mydb');

// Create single-field index
db.users.createIndex({ "email": 1 });

// Create compound index
db.orders.createIndex({ "user_id": 1, "created_at": -1 });

// Create text index for full-text search
db.products.createIndex({ "name": "text", "description": "text" });

// Create geospatial index
db.stores.createIndex({ "location": "2dsphere" });

// Check index usage
db.users.aggregate([
  { $indexStats: {} }
]);

// Explain query
db.users.find({ email: "user@example.com" }).explain("executionStats");
```

**Index Best Practices**:

```javascript
// 1. ESR (Equality, Sort, Range) Rule
db.orders.createIndex({
  "status": 1,        // Equality
  "created_at": -1,   // Sort
  "amount": 1         // Range
});

// 2. Covered Queries (projection matches index)
db.users.find(
  { "email": "user@example.com" },
  { "_id": 0, "email": 1, "name": 1 }
).hint({ "email": 1, "name": 1 });

// 3. Partial Indexes (index only subset)
db.orders.createIndex(
  { "status": 1, "created_at": -1 },
  { partialFilterExpression: { "status": "active" } }
);
```

#### 2. Aggregation Pipeline Optimization

**Optimization Techniques**:

```javascript
// 1. Use $match early to filter documents
db.orders.aggregate([
  { $match: { created_at: { $gte: new Date('2025-01-01') } } },  // Filter first
  { $group: { _id: "$user_id", total: { $sum: "$amount" } } },
  { $sort: { total: -1 } },
  { $limit: 100 }
]);

// 2. Use $project to reduce document size
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $project: { user_id: 1, amount: 1, created_at: 1 } },  // Select only needed fields
  { $group: { _id: "$user_id", total: { $sum: "$amount" } } }
]);

// 3. Use indexes with $lookup
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $lookup: {
      from: "users",
      localField: "user_id",
      foreignField: "_id",
      as: "user"
    } },
  { $unwind: "$user" }
]);

// Create supporting indexes
db.orders.createIndex({ "status": 1, "user_id": 1 });
db.users.createIndex({ "_id": 1 });
```

---

### Redis Performance Tuning

#### 1. Memory Optimization

**Eviction Policies**:

```bash
# Configure eviction policy
redis-cli CONFIG SET maxmemory 4gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Eviction policies:
# - noeviction: Return errors when memory limit reached
# - allkeys-lru: Evict least recently used keys
# - allkeys-lfu: Evict least frequently used keys
# - volatile-lru: Evict LRU keys with expire set
# - volatile-lfu: Evict LFU keys with expire set
# - volatile-ttl: Evict keys with shortest TTL
# - volatile-random: Evict random keys with expire set
# - allkeys-random: Evict random keys
```

**Memory Usage Analysis**:

```bash
# Check memory usage
redis-cli INFO memory

# Sample output:
# used_memory: 4GB
# used_memory_rss: 5GB  # Resident set size (includes fragmentation)
# used_memory_peak: 6GB
# used_memory_overhead: 100MB
# mem_fragmentation_ratio: 1.25  # > 1.5 indicates fragmentation issues

# Check largest keys
redis-cli --bigkeys

# Estimate key memory usage
redis-cli MEMORY USAGE mykey

# Defragment memory (Redis 4.0+)
redis-cli CONFIG SET activedefrag yes
```

#### 2. Persistence Tuning

**RDB vs AOF Trade-offs**:

```bash
# RDB (Point-in-time snapshots)
# - Pros: Compact, fast restore, minimal performance impact
# - Cons: Potential data loss (up to snapshot interval)

redis-cli CONFIG SET save "900 1 300 10 60 10000"  # Save every 15min if 1 change, 5min if 10 changes, etc.
redis-cli CONFIG SET stop-writes-on-bgsave-error yes
redis-cli CONFIG SET rdbcompression yes

# AOF (Append-only file)
# - Pros: Durable (every write logged), less data loss
# - Cons: Larger files, slower restore, higher write overhead

redis-cli CONFIG SET appendonly yes
redis-cli CONFIG SET appendfsync everysec  # always, everysec, or no
redis-cli CONFIG SET no-appendfsync-on-rewrite yes  # Disable fsync during rewrite
redis-cli CONFIG SET auto-aof-rewrite-percentage 100
redis-cli CONFIG SET auto-aof-rewrite-min-size 64mb
```

**Hybrid Approach (RDB + AOF)**:

```bash
# Use RDB for periodic snapshots + AOF for durability
redis-cli CONFIG SET save "900 1"
redis-cli CONFIG SET appendonly yes
redis-cli CONFIG SET appendfsync everysec
```

---

## Storage Performance

### Storage Class Selection

| Storage Type | IOPS | Throughput | Latency | Cost | Use Case |
|--------------|------|------------|---------|------|----------|
| **Local SSD** | 100k+ | 1 GB/s+ | < 1ms | High | Databases (PostgreSQL, MySQL), Elasticsearch, Kafka |
| **Network SSD (Premium)** | 20k | 500 MB/s | 1-5ms | Medium | Prometheus TSDB, Loki, Mimir |
| **Network SSD (Standard)** | 5k | 250 MB/s | 5-10ms | Low | General purpose, logs, backups |
| **Network HDD** | 500 | 100 MB/s | 10-50ms | Very Low | Cold storage, archives |

**Kubernetes StorageClass Examples**:

```yaml
# Local SSD (highest performance)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-ssd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
  - matchLabelExpressions:
      - key: storage-type
        values:
          - local-ssd

---
# Network SSD (Premium)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: premium-ssd
provisioner: pd.csi.storage.gke.io  # GKE example
parameters:
  type: pd-ssd
  replication-type: regional-pd
allowVolumeExpansion: true

---
# Network SSD (Standard)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-ssd
provisioner: ebs.csi.aws.com  # AWS example
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
allowVolumeExpansion: true
```

**Chart Storage Configuration**:

```yaml
# PostgreSQL with local SSD for maximum performance
persistence:
  enabled: true
  storageClass: "local-ssd"
  size: 200Gi

# Prometheus with premium SSD
persistence:
  enabled: true
  storageClass: "premium-ssd"
  size: 1Ti

# Backup storage with standard SSD
backup:
  persistence:
    storageClass: "standard-ssd"
    size: 5Ti
```

---

### I/O Optimization

#### 1. Filesystem Tuning

**XFS for Databases**:

```bash
# Format with XFS (better for large files and parallel I/O)
mkfs.xfs -f -b size=4096 -d agcount=32 /dev/sdb1

# Mount with performance options
mount -o noatime,nodiratime,nobarrier,logbufs=8,logbsize=256k /dev/sdb1 /mnt/data

# /etc/fstab entry
/dev/sdb1 /mnt/data xfs noatime,nodiratime,nobarrier,logbufs=8,logbsize=256k 0 0
```

**ext4 for General Purpose**:

```bash
# Format with ext4
mkfs.ext4 -E stride=32,stripe-width=64 /dev/sdb1

# Mount with performance options
mount -o noatime,nodiratime,data=writeback,barrier=0 /dev/sdb1 /mnt/data
```

#### 2. I/O Scheduler Tuning

**CFQ vs Deadline vs noop**:

```bash
# Check current scheduler
cat /sys/block/sda/queue/scheduler

# Set deadline scheduler (best for SSDs)
echo deadline > /sys/block/sda/queue/scheduler

# Set noop scheduler (best for NVMe/virtualized environments)
echo noop > /sys/block/sda/queue/scheduler

# Persistent across reboots (add to /etc/rc.local or systemd)
cat > /etc/udev/rules.d/60-io-scheduler.rules <<EOF
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
EOF
```

#### 3. Readahead Tuning

```bash
# Check current readahead
blockdev --getra /dev/sda

# Set readahead (KB) - higher for sequential workloads
blockdev --setra 8192 /dev/sda  # 8 MB readahead

# For databases (random I/O), lower readahead
blockdev --setra 256 /dev/sda  # 256 KB readahead
```

---

## Network Optimization

### Network Policies and Bandwidth

**Quality of Service (QoS) with Network Policies**:

```yaml
# Priority traffic for critical databases
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-priority
  namespace: databases
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: backend
      ports:
        - protocol: TCP
          port: 5432
  egress:
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 53  # DNS
```

**Pod Quality of Service Classes**:

```yaml
# Guaranteed QoS (highest priority)
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-critical
spec:
  containers:
    - name: postgresql
      image: postgres:16
      resources:
        requests:
          cpu: "4000m"
          memory: "8Gi"
        limits:
          cpu: "4000m"     # Same as requests = Guaranteed
          memory: "8Gi"    # Same as requests = Guaranteed

---
# Burstable QoS (medium priority)
apiVersion: v1
kind: Pod
metadata:
  name: grafana-burstable
spec:
  containers:
    - name: grafana
      image: grafana/grafana:10.0.0
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2000m"     # Higher than requests = Burstable
          memory: "4Gi"    # Higher than requests = Burstable

---
# BestEffort QoS (lowest priority)
apiVersion: v1
kind: Pod
metadata:
  name: batch-job
spec:
  containers:
    - name: batch
      image: batch-processor:latest
      # No resources defined = BestEffort
```

---

### Service Mesh Performance

**Istio Sidecar Resource Optimization**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-sidecar-injector
  namespace: istio-system
data:
  values: |
    global:
      proxy:
        resources:
          requests:
            cpu: 50m      # Reduced from default 100m
            memory: 64Mi  # Reduced from default 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

        # CPU limit per core
        concurrency: 2

        # Connection pool limits
        settings:
          connectionPool:
            tcp:
              maxConnections: 10000
              connectTimeout: 10s
            http:
              http1MaxPendingRequests: 10000
              http2MaxRequests: 10000
              maxRequestsPerConnection: 0
              maxRetries: 3
```

**Disable Sidecar for Performance-Critical Pods**:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: high-performance-db
  annotations:
    sidecar.istio.io/inject: "false"  # Disable Istio sidecar
spec:
  containers:
    - name: postgresql
      image: postgres:16
```

---

## Caching Strategies

### Multi-Level Caching Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                   Multi-Level Caching Strategy                  │
└────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│   Application    │
│   (In-Memory)    │  L1 Cache: 100-1000ms TTL
│                  │  - Frequent data
│  Local Cache     │  - Session data
│  (Caffeine, etc) │  - Static content
└────────┬─────────┘
         │ Miss
         ▼
┌──────────────────┐
│     Redis        │  L2 Cache: 5-60min TTL
│   (Distributed)  │  - User sessions
│                  │  - API responses
│  Cluster Mode    │  - Computed results
│  (HA + Sharding) │  - Hot data
└────────┬─────────┘
         │ Miss
         ▼
┌──────────────────┐
│   Memcached      │  L3 Cache: 1-24hr TTL
│ (Object Storage) │  - Static assets
│                  │  - Rendered pages
│  Distributed     │  - Large objects
└────────┬─────────┘
         │ Miss
         ▼
┌──────────────────┐
│    Database      │  Source of Truth
│  (PostgreSQL,    │  - Persistent data
│   MongoDB, etc)  │  - Transactional data
└──────────────────┘
```

### Cache-Aside Pattern (Lazy Loading)

**Implementation Example (Python)**:

```python
import redis
import psycopg2
import json
from functools import wraps

# Redis client
redis_client = redis.StrictRedis(host='redis', port=6379, db=0, decode_responses=True)

# PostgreSQL connection
pg_conn = psycopg2.connect(
    host="postgresql",
    database="mydb",
    user="postgres",
    password="password"
)

def cache_aside(ttl=300):
    """
    Cache-aside decorator with TTL

    Args:
        ttl: Time-to-live in seconds (default 5 minutes)
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Generate cache key
            cache_key = f"{func.__name__}:{':'.join(map(str, args))}"

            # Try to get from cache
            cached_value = redis_client.get(cache_key)
            if cached_value:
                return json.loads(cached_value)

            # Cache miss - fetch from database
            result = func(*args, **kwargs)

            # Store in cache with TTL
            redis_client.setex(cache_key, ttl, json.dumps(result))

            return result
        return wrapper
    return decorator

@cache_aside(ttl=600)  # 10 minutes TTL
def get_user(user_id):
    """Get user from database (with caching)"""
    cur = pg_conn.cursor()
    cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
    user = cur.fetchone()
    return {
        "id": user[0],
        "name": user[1],
        "email": user[2]
    }

# Usage
user = get_user(123)  # First call: database query + cache write
user = get_user(123)  # Second call: cache hit (fast!)
```

---

### Write-Through Cache Pattern

**Implementation Example**:

```python
def update_user(user_id, name, email):
    """Update user in database and cache simultaneously"""

    # 1. Update database
    cur = pg_conn.cursor()
    cur.execute(
        "UPDATE users SET name = %s, email = %s WHERE id = %s",
        (name, email, user_id)
    )
    pg_conn.commit()

    # 2. Update cache
    cache_key = f"get_user:{user_id}"
    user_data = {
        "id": user_id,
        "name": name,
        "email": email
    }
    redis_client.setex(cache_key, 600, json.dumps(user_data))

    return user_data
```

---

### Cache Invalidation Strategies

**1. TTL-Based Expiration**:

```python
# Set TTL on cache entry
redis_client.setex("user:123", 300, user_data)  # Expires after 5 minutes
```

**2. Event-Based Invalidation**:

```python
def on_user_updated(user_id):
    """Invalidate cache when user is updated"""
    cache_key = f"get_user:{user_id}"
    redis_client.delete(cache_key)
```

**3. Cache Stampede Prevention (Lock)**:

```python
import time

def get_user_with_lock(user_id):
    """Prevent cache stampede with distributed lock"""
    cache_key = f"get_user:{user_id}"
    lock_key = f"lock:{cache_key}"

    # Try to get from cache
    cached_value = redis_client.get(cache_key)
    if cached_value:
        return json.loads(cached_value)

    # Try to acquire lock
    lock = redis_client.setnx(lock_key, "1")

    if lock:
        # This thread won the race - fetch from database
        try:
            redis_client.expire(lock_key, 10)  # Lock expires after 10s

            # Fetch from database
            user = fetch_user_from_db(user_id)

            # Store in cache
            redis_client.setex(cache_key, 600, json.loads(user))

            return user
        finally:
            # Release lock
            redis_client.delete(lock_key)
    else:
        # Another thread is fetching - wait and retry
        time.sleep(0.1)
        return get_user_with_lock(user_id)  # Retry
```

---

## Benchmarking Methodologies

### Database Benchmarking

#### PostgreSQL: pgbench

**Installation**:

```bash
# pgbench is included with PostgreSQL
apt-get install postgresql-contrib
```

**Benchmark Workflow**:

```bash
# 1. Initialize test database
createdb pgbench_test
pgbench -i -s 100 pgbench_test  # Scale factor 100 = 10M rows

# 2. Run benchmark (simple SELECT)
pgbench -c 10 -j 2 -t 10000 -r pgbench_test
# -c 10: 10 concurrent clients
# -j 2: 2 threads
# -t 10000: 10k transactions per client
# -r: Report latencies

# Sample output:
# transaction type: <builtin: TPC-B (sort of)>
# scaling factor: 100
# query mode: simple
# number of clients: 10
# number of threads: 2
# number of transactions per client: 10000
# number of transactions actually processed: 100000/100000
# latency average = 15.234 ms
# tps = 656.234 (including connections establishing)
# tps = 657.123 (excluding connections establishing)

# 3. Run benchmark (custom script)
cat > custom_bench.sql <<EOF
\set user_id random(1, 10000000)
SELECT * FROM users WHERE id = :user_id;
EOF

pgbench -c 10 -j 2 -t 10000 -f custom_bench.sql pgbench_test

# 4. Long-running benchmark (duration-based)
pgbench -c 50 -j 4 -T 600 -r pgbench_test  # Run for 600 seconds (10 minutes)
```

---

#### MySQL: sysbench

**Installation**:

```bash
apt-get install sysbench
```

**Benchmark Workflow**:

```bash
# 1. Prepare test database
mysql -e "CREATE DATABASE sbtest"

sysbench \
  --db-driver=mysql \
  --mysql-host=mysql \
  --mysql-user=root \
  --mysql-password=password \
  --mysql-db=sbtest \
  --table-size=1000000 \
  --tables=10 \
  /usr/share/sysbench/oltp_read_write.lua prepare

# 2. Run OLTP benchmark
sysbench \
  --db-driver=mysql \
  --mysql-host=mysql \
  --mysql-user=root \
  --mysql-password=password \
  --mysql-db=sbtest \
  --threads=16 \
  --time=300 \
  --report-interval=10 \
  /usr/share/sysbench/oltp_read_write.lua run

# Sample output:
# SQL statistics:
#     queries performed:
#         read:                            1400000
#         write:                           400000
#         other:                           200000
#         total:                           2000000
#     transactions:                        100000 (333.33 per sec.)
#     queries:                             2000000 (6666.67 per sec.)
#     ignored errors:                      0      (0.00 per sec.)
#     reconnects:                          0      (0.00 per sec.)
#
# General statistics:
#     total time:                          300.0012s
#     total number of events:              100000
#
# Latency (ms):
#          min:                                    2.15
#          avg:                                   47.98
#          max:                                  325.45
#          95th percentile:                       84.47

# 3. Cleanup
sysbench \
  --db-driver=mysql \
  --mysql-host=mysql \
  --mysql-user=root \
  --mysql-password=password \
  --mysql-db=sbtest \
  /usr/share/sysbench/oltp_read_write.lua cleanup
```

---

### Application Benchmarking

#### HTTP Load Testing: wrk

**Installation**:

```bash
apt-get install wrk
```

**Benchmark Examples**:

```bash
# 1. Simple GET request
wrk -t 12 -c 400 -d 60s http://grafana:3000/

# -t 12: 12 threads
# -c 400: 400 connections
# -d 60s: Duration 60 seconds

# Sample output:
# Running 1m test @ http://grafana:3000/
#   12 threads and 400 connections
#   Thread Stats   Avg      Stdev     Max   +/- Stdev
#     Latency    45.23ms   12.34ms 250.00ms   87.23%
#     Req/Sec     0.88k   123.45   1.23k    68.92%
#   631245 requests in 1.00m, 2.34GB read
# Requests/sec:  10520.75
# Transfer/sec:     39.85MB

# 2. POST request with Lua script
cat > post_bench.lua <<'EOF'
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.body = '{"username": "user", "password": "pass"}'
EOF

wrk -t 4 -c 100 -d 30s -s post_bench.lua http://keycloak:8080/auth/realms/master/protocol/openid-connect/token

# 3. Variable payload
cat > variable_bench.lua <<'EOF'
request = function()
  user_id = math.random(1, 10000)
  path = "/api/users/" .. user_id
  return wrk.format("GET", path)
end
EOF

wrk -t 8 -c 200 -d 60s -s variable_bench.lua http://api:8080/
```

---

### Kubernetes Resource Benchmarking

#### Cluster Capacity Analysis: cluster-capacity

**Installation**:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/cluster-capacity/releases/download/v0.7.0/cluster-capacity.yaml
```

**Usage**:

```bash
# Simulate scheduling 100 PostgreSQL pods
cluster-capacity --kubeconfig ~/.kube/config \
  --podspec=postgresql-pod.yaml \
  --max-limit=100 \
  --verbose

# Sample output:
# Pod: postgresql-0 can be scheduled on node: node-1
# Pod: postgresql-1 can be scheduled on node: node-2
# Pod: postgresql-2 can be scheduled on node: node-3
# ...
# Pod: postgresql-47 can be scheduled on node: node-1
# Pod: postgresql-48 cannot be scheduled (insufficient CPU on all nodes)
#
# Cluster Capacity: 48 pods
```

---

## Monitoring & Profiling

### Application-Level Profiling

#### PostgreSQL Query Profiling

**Enable pg_stat_statements**:

```sql
-- Enable extension
CREATE EXTENSION pg_stat_statements;

-- Check top queries by total time
SELECT
    (total_time / 1000 / 60) as total_minutes,
    (mean_time / 1000) as avg_seconds,
    calls,
    query
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 20;

-- Check queries with highest I/O
SELECT
    query,
    calls,
    shared_blks_hit,
    shared_blks_read,
    (shared_blks_hit::float / NULLIF(shared_blks_hit + shared_blks_read, 0)) * 100 as cache_hit_ratio
FROM pg_stat_statements
WHERE shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 20;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

---

### Resource Monitoring with Prometheus

**ServiceMonitor for PostgreSQL**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgresql-metrics
  namespace: databases
spec:
  selector:
    matchLabels:
      app: postgresql
  endpoints:
    - port: metrics
      interval: 30s

---
# PostgreSQL Exporter
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql-exporter
spec:
  template:
    spec:
      containers:
        - name: exporter
          image: prometheuscommunity/postgres-exporter:v0.15.0
          env:
            - name: DATA_SOURCE_NAME
              value: "postgresql://postgres:password@postgresql:5432/postgres?sslmode=disable"
          ports:
            - name: metrics
              containerPort: 9187
```

**Grafana Dashboards**:

- PostgreSQL: Dashboard ID 9628
- MySQL: Dashboard ID 7362
- Redis: Dashboard ID 11835
- Elasticsearch: Dashboard ID 14191
- Kafka: Dashboard ID 7589
- Kubernetes Cluster: Dashboard ID 12114

---

## Best Practices

### 1. Measure Before Optimizing

- **Never optimize without profiling first**
- Use APM tools (Prometheus, Grafana, Jaeger) to identify bottlenecks
- Establish performance baselines before making changes
- Measure impact after each optimization

### 2. Right-Size Resources

- **Avoid over-provisioning**: Wastes resources and money
- **Avoid under-provisioning**: Degrades performance and reliability
- Use HPA for dynamic scaling
- Monitor actual resource usage (not just requests/limits)

### 3. Optimize for Your Workload

- **OLTP (Online Transaction Processing)**: Fast queries, high concurrency
  - Small buffer pools, many connections, low latency storage

- **OLAP (Online Analytical Processing)**: Complex queries, large datasets
  - Large buffer pools, fewer connections, high IOPS storage

- **Time-Series**: High write throughput, range queries
  - Partitioning, compression, retention policies

### 4. Use Caching Strategically

- **Cache hot data**: 80/20 rule (20% of data accessed 80% of the time)
- **Set appropriate TTLs**: Balance freshness vs performance
- **Cache at multiple levels**: Application, distributed, CDN
- **Invalidate proactively**: Event-based invalidation when data changes

### 5. Database Best Practices

- **Use connection pooling**: PgBouncer, ProxySQL, MongoDB connection pools
- **Index strategically**: Too few = slow queries, too many = slow writes
- **Partition large tables**: Time-based or hash partitioning
- **Vacuum regularly**: Prevent table bloat (PostgreSQL)
- **Monitor slow queries**: Identify and optimize bottlenecks

### 6. Storage Best Practices

- **Choose appropriate storage class**: Local SSD > Network SSD > HDD
- **Use XFS for databases**: Better than ext4 for large files
- **Tune I/O scheduler**: deadline for SSDs, noop for NVMe
- **Enable compression**: Reduce storage costs (at CPU cost)

### 7. Network Best Practices

- **Use QoS**: Prioritize critical traffic (databases, messaging)
- **Enable HTTP/2**: Multiplexing, header compression
- **Use gRPC for microservices**: Binary protocol, streaming
- **Reduce network hops**: Collocate related services

---

## Troubleshooting

### High CPU Usage

**Diagnosis**:

```bash
# 1. Check pod CPU usage
kubectl top pods -n production

# 2. Check which process is consuming CPU
kubectl exec -it postgresql-0 -- top

# 3. Check database queries
kubectl exec -it postgresql-0 -- psql -U postgres -c \
  "SELECT pid, query, state, query_start FROM pg_stat_activity WHERE state = 'active' ORDER BY query_start;"

# 4. Check kernel CPU usage
kubectl exec -it postgresql-0 -- cat /proc/stat
```

**Solutions**:

- Optimize slow queries (add indexes, rewrite queries)
- Increase CPU limits (vertical scaling)
- Add read replicas (horizontal scaling)
- Enable query caching (Redis, Memcached)

---

### High Memory Usage

**Diagnosis**:

```bash
# 1. Check pod memory usage
kubectl top pods -n production

# 2. Check memory breakdown
kubectl exec -it postgresql-0 -- free -h

# 3. Check for memory leaks
kubectl exec -it postgresql-0 -- ps aux --sort=-rss | head -20

# 4. Check OOM events
kubectl get events -n production | grep OOM
```

**Solutions**:

- Reduce buffer pool size (PostgreSQL shared_buffers, MySQL innodb_buffer_pool_size)
- Increase memory limits
- Enable memory limits enforcement (cgroups)
- Restart pods to clear leaks

---

### Slow Queries

**Diagnosis**:

```sql
-- PostgreSQL: Check slow queries
SELECT
    query,
    calls,
    (total_time / calls) as avg_time_ms,
    min_time,
    max_time
FROM pg_stat_statements
WHERE (total_time / calls) > 1000  -- Queries slower than 1 second
ORDER BY avg_time_ms DESC
LIMIT 20;

-- MySQL: Analyze slow query log
SELECT
    sql_text,
    count_star as executions,
    avg_timer_wait / 1000000000000 as avg_seconds,
    sum_timer_wait / 1000000000000 as total_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE avg_timer_wait > 1000000000000  -- Slower than 1 second
ORDER BY avg_timer_wait DESC
LIMIT 20;
```

**Solutions**:

- Add indexes on frequently queried columns
- Rewrite queries to avoid full table scans
- Use query result caching (Redis)
- Partition large tables
- Increase work_mem (PostgreSQL) or sort_buffer_size (MySQL)

---

### Storage I/O Bottleneck

**Diagnosis**:

```bash
# 1. Check disk I/O
kubectl exec -it postgresql-0 -- iostat -x 5

# Sample output:
# Device   r/s   w/s   rkB/s   wkB/s  await  %util
# sda      120   80    4800    3200   45.2   95.3  # 95% utilization = bottleneck

# 2. Check slow I/O operations
kubectl exec -it postgresql-0 -- iotop -o

# 3. Check storage class performance
kubectl describe pvc postgresql-data
```

**Solutions**:

- Upgrade to faster storage class (local SSD)
- Increase IOPS provisioning
- Optimize database configuration (reduce fsync, increase buffer pool)
- Enable write-ahead logging (WAL) on separate disk
- Use SSD-backed storage

---

**Document Version**: 1.0
**Last Updated**: 2025-12-09
**Maintained By**: SRE Team
**Review Cycle**: Quarterly
