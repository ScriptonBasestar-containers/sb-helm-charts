# Redis Master-Slave Replication Guide

This guide covers the master-slave replication feature in the Redis Helm chart.

## Overview

The Redis chart supports **master-slave replication** to scale read operations and provide basic data redundancy. When enabled, the chart deploys:

- **1 master pod**: Handles all write operations and replicates data to slaves
- **N replica pods**: Read-only replicas that sync data from the master

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                         │
│                                                              │
│  ┌────────────────┐          ┌─────────────────────────┐   │
│  │  redis-0       │──────────▶│  redis-1, redis-2, ...  │   │
│  │  (Master)      │ Replicate │  (Replicas)             │   │
│  │  Read/Write    │           │  Read-only              │   │
│  └────────────────┘          └─────────────────────────┘   │
│         │                              │                     │
│         │                              │                     │
│  ┌──────▼────────┐            ┌───────▼──────────┐         │
│  │ redis-master  │            │ redis-headless    │         │
│  │ Service       │            │ Service           │         │
│  └───────────────┘            │ (StatefulSet DNS) │         │
│         │                      └───────────────────┘         │
│  ┌──────▼─────────────────────────────────────────┐         │
│  │           redis Service (Master)               │         │
│  │           (Default endpoint for writes)        │         │
│  └────────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### Service Endpoints

Two service endpoints are automatically created for the master:

1. **`redis.{namespace}.svc.cluster.local`**
   - Routes to: Master pod (redis-0)
   - Use for: Write operations, default endpoint
   - Example: `redis.default.svc.cluster.local`

2. **`redis-master.{namespace}.svc.cluster.local`**
   - Routes to: Master pod (redis-0) explicitly
   - Use for: When you need to explicitly target the master
   - Example: `redis-master.default.svc.cluster.local`

### Individual Replica Access

Replicas are accessed via StatefulSet DNS (not load-balanced):

- **`redis-1.redis-headless.{namespace}.svc.cluster.local`** → Replica 1
- **`redis-2.redis-headless.{namespace}.svc.cluster.local`** → Replica 2
- **`redis-N.redis-headless.{namespace}.svc.cluster.local`** → Replica N

Use these for: Read-only operations when you need to target a specific replica

## Configuration

### Enable Replication

Add to your `values.yaml`:

```yaml
replication:
  enabled: true
  replicas: 2  # Number of read-only replicas (in addition to 1 master)
```

This will deploy:
- 1 master (redis-0)
- 2 replicas (redis-1, redis-2)
- Total: 3 pods

### Complete Example

```yaml
# Enable replication
replication:
  enabled: true
  replicas: 2

# Enable password authentication (recommended)
redis:
  password: "secure-password-here"

# Enable persistence for all pods
persistence:
  enabled: true
  storageClass: "fast-ssd"
  size: 10Gi

# Resource limits (per pod)
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Deployment

### Install with Replication

```bash
# Create values file
cat > my-redis-values.yaml <<EOF
replication:
  enabled: true
  replicas: 2

redis:
  password: "my-secure-password"

persistence:
  enabled: true
  size: 10Gi
EOF

# Install chart
helm install my-redis ./charts/redis -f my-redis-values.yaml

# Check pods
kubectl get pods -l app.kubernetes.io/name=redis
```

Expected output:
```
NAME       READY   STATUS    RESTARTS   AGE
redis-0    1/1     Running   0          2m   # Master
redis-1    1/1     Running   0          2m   # Replica
redis-2    1/1     Running   0          2m   # Replica
```

### Upgrade Existing Installation

To enable replication on an existing single-instance Redis:

```bash
# Update values.yaml with replication.enabled=true
helm upgrade my-redis ./charts/redis -f my-redis-values.yaml

# Wait for replica pods to start
kubectl rollout status statefulset redis
```

**Warning**: Upgrading from single instance to replication will:
- Keep redis-0 as master with existing data
- Create new replica pods that will sync from master
- No data loss expected, but test in non-production first

## Usage

### Connecting to Master (Write Operations)

From within the cluster:

```bash
# Using default service (routes to master)
redis-cli -h redis.default.svc.cluster.local -a $REDIS_PASSWORD

# Or explicitly use master service
redis-cli -h redis-master.default.svc.cluster.local -a $REDIS_PASSWORD
```

### Connecting to Replicas (Read Operations)

From within the cluster:

```bash
# Connects to read-only replicas (load balanced)
redis-cli -h redis-1.redis-headless.default.svc.cluster.local -a $REDIS_PASSWORD

# Only read commands work
GET mykey        # ✅ Works
SET mykey val    # ❌ READONLY error
```

### Application Configuration

**Python example** (redis-py):

```python
import redis

# Write pool (master)
master = redis.StrictRedis(
    host='redis-master.default.svc.cluster.local',
    port=6379,
    password='secure-password',
    decode_responses=True
)

# Read pool (replicas)
replicas = redis.StrictRedis(
    host='redis-1.redis-headless.default.svc.cluster.local',
    port=6379,
    password='secure-password',
    decode_responses=True
)

# Write to master
master.set('user:1', 'John Doe')

# Read from replicas (load balanced across multiple replicas)
user = replicas.get('user:1')
```

**Go example** (go-redis):

```go
import "github.com/go-redis/redis/v8"

// Master client (writes)
masterClient := redis.NewClient(&redis.Options{
    Addr:     "redis-master.default.svc.cluster.local:6379",
    Password: "secure-password",
})

// Replica client (reads)
replicaClient := redis.NewClient(&redis.Options{
    Addr:     "redis-1.redis-headless.default.svc.cluster.local:6379",
    Password: "secure-password",
})

// Write to master
masterClient.Set(ctx, "user:1", "John Doe", 0)

// Read from replicas
replicaClient.Get(ctx, "user:1")
```

## Monitoring

### Check Replication Status

```bash
# View replication info for all pods
make -f make/ops/redis.mk redis-replication-info
```

Example output:
```
=== Pod: redis-0 ===
role:master
connected_slaves:2

=== Pod: redis-1 ===
role:slave
master_host:redis-0.redis-headless.default.svc.cluster.local
master_port:6379
master_link_status:up

=== Pod: redis-2 ===
role:slave
master_host:redis-0.redis-headless.default.svc.cluster.local
master_port:6379
master_link_status:up
```

### Check Master Info

```bash
make -f make/ops/redis.mk redis-master-info
```

### Check Replica Lag

```bash
make -f make/ops/redis.mk redis-replica-lag
```

Example output:
```
=== Replica: redis-1 ===
master_link_status:up
master_last_io_seconds_ago:0
master_sync_in_progress:0

=== Replica: redis-2 ===
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
```

### Check Specific Pod Role

```bash
make -f make/ops/redis.mk redis-role POD=redis-0
```

## Manual Failover

⚠️ **This chart does NOT support automatic failover.** If the master fails, you must manually promote a replica.

### Failover Procedure

1. **Identify the failure**:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=redis
   # redis-0 is CrashLoopBackOff or Terminating
   ```

2. **Choose a replica to promote** (e.g., redis-1):
   ```bash
   kubectl exec redis-1 -- redis-cli -a $REDIS_PASSWORD REPLICAOF NO ONE
   ```

3. **Point other replicas to new master**:
   ```bash
   kubectl exec redis-2 -- redis-cli -a $REDIS_PASSWORD \
     REPLICAOF redis-1.redis-headless.default.svc.cluster.local 6379
   ```

4. **Update your application** to point to new master:
   - If using service names, no changes needed (services still route correctly)
   - If using direct pod names, update connection strings

5. **Fix or delete the old master pod**:
   ```bash
   kubectl delete pod redis-0
   # StatefulSet will recreate it
   ```

6. **Add the recovered pod as a replica**:
   ```bash
   kubectl exec redis-0 -- redis-cli -a $REDIS_PASSWORD \
     REPLICAOF redis-1.redis-headless.default.svc.cluster.local 6379
   ```

### Automatic Failover (Recommendation)

For automatic failover with Redis Sentinel, use the [Spotahome Redis Operator](https://github.com/spotahome/redis-operator):

- ✅ Automatic master election
- ✅ Self-healing
- ✅ No manual intervention required
- ✅ Production-ready HA

See [Redis Operator Migration Guide](03-redis-operator-migration.md).

## Future Plans

The following features are **NOT currently supported** but are documented for future consideration:

### Redis Sentinel (Planned)

- Automatic failover
- Master election
- Sentinel quorum
- Status: **Not implemented** - use Redis Operator instead

### Redis Cluster (Planned)

- Horizontal sharding
- Multi-master setup
- Automatic data partitioning
- Status: **Not implemented** - use Redis Cluster Operator

## Troubleshooting

### Replica shows "master_link_status:down"

**Symptoms**:
```bash
make -f make/ops/redis.mk redis-replication-info
# Shows master_link_status:down for replicas
```

**Possible causes**:
1. **Network issue**: Check if replicas can reach master
   ```bash
   kubectl exec redis-1 -- ping redis-0.redis-headless.default.svc.cluster.local
   ```

2. **Password mismatch**: Verify password is correctly set
   ```bash
   kubectl get secret redis -o jsonpath='{.data.redis-password}' | base64 -d
   ```

3. **Master not ready**: Check master pod logs
   ```bash
   kubectl logs redis-0
   ```

### Replication lag too high

**Symptoms**:
```bash
make -f make/ops/redis.mk redis-replica-lag
# Shows master_last_io_seconds_ago:30 or higher
```

**Solutions**:
1. **Increase replica resources**:
   ```yaml
   resources:
     limits:
       cpu: 1000m
       memory: 1Gi
   ```

2. **Reduce write load on master**:
   - Scale horizontally with Redis Cluster
   - Optimize application queries

3. **Check network bandwidth**:
   ```bash
   kubectl exec redis-1 -- redis-cli -a $REDIS_PASSWORD INFO stats | grep sync_
   ```

### Write operations fail

**Symptoms**:
```
Error: READONLY You can't write against a read only replica
```

**Cause**: Application is connecting to replica service instead of master.

**Solution**: Use master endpoint:
```yaml
# Correct (master)
redis_host: redis-master.default.svc.cluster.local

# Incorrect (replicas)
redis_host: redis-1.redis-headless.default.svc.cluster.local
```

### Replica not syncing after pod restart

**Symptoms**: Replica shows empty dataset after restart.

**Solution**: Check replica configuration in pod:
```bash
kubectl exec redis-1 -- redis-cli -a $REDIS_PASSWORD CONFIG GET replicaof
```

Should show:
```
replicaof
redis-0.redis-headless.default.svc.cluster.local 6379
```

If empty, the initContainer may have failed. Check initContainer logs:
```bash
kubectl logs redis-1 -c setup-replication
```

## Best Practices

### 1. Use Password Authentication

Always enable password authentication in production:

```yaml
redis:
  password: "strong-random-password"
```

### 2. Enable Persistence

Each pod should have its own persistent volume:

```yaml
persistence:
  enabled: true
  size: 10Gi
  storageClass: "fast-ssd"
```

### 3. Set Resource Limits

Prevent resource starvation:

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

### 4. Monitor Replication Lag

Set up alerts for replication lag:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true

metrics:
  enabled: true
```

Prometheus alert example:
```yaml
- alert: RedisReplicationLag
  expr: redis_slave_last_io_seconds_ago > 10
  annotations:
    summary: "Redis replica lag is too high"
```

### 5. Use Read Replicas for Scaling

Direct read-heavy operations to replicas:

```yaml
# Application config
REDIS_MASTER_HOST: redis-master.default.svc.cluster.local
REDIS_REPLICA_HOST: redis-1.redis-headless.default.svc.cluster.local
```

### 6. Plan for Failover

Document and test manual failover procedures:
- Keep replica promotion commands ready
- Test failover in staging environment
- Consider upgrading to Redis Operator for automatic failover

## Comparison: Chart vs Operator

| Feature | This Chart (Replication) | Redis Operator |
|---------|-------------------------|----------------|
| Master-Slave Replication | ✅ Manual setup | ✅ Automatic |
| Read Scaling | ✅ Load-balanced replicas | ✅ Load-balanced replicas |
| Automatic Failover | ❌ Manual only | ✅ Sentinel-based |
| Self-Healing | ❌ No | ✅ Yes |
| Multi-Master (Cluster) | ❌ No | ✅ Yes |
| Complexity | 🟢 Low | 🟡 Medium |
| Use Case | Dev/Test, Simple apps | Production HA |

**When to use this chart's replication:**
- Development/testing environments
- Read-heavy workloads with manual failover acceptable
- Resource-constrained environments
- Learning Redis replication concepts

**When to use Redis Operator:**
- Production environments requiring HA
- Automatic failover required
- Multi-datacenter deployments
- Large-scale deployments (100k+ ops/sec)

## References

- [Redis Replication Documentation](https://redis.io/docs/management/replication/)
- [Redis Sentinel Documentation](https://redis.io/docs/management/sentinel/)
- [Redis Cluster Documentation](https://redis.io/docs/management/scaling/)
- [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)
- [Redis Operator Migration Guide](03-redis-operator-migration.md)
