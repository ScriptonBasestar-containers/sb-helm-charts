# Redis Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/redis)

[Redis](https://redis.io/) is an open-source, in-memory data structure store used as a database, cache, message broker, and streaming engine.

## ⚠️ Production Consideration

**For production environments requiring high availability**, consider using [Spotahome Redis Operator](https://github.com/spotahome/redis-operator) instead:

- ✅ Automatic failover with Sentinel
- ✅ Master-Replica replication
- ✅ Self-healing capabilities
- ✅ CRD-based management

See [Redis Operator Migration Guide](../../docs/03-redis-operator-migration.md) for detailed comparison and migration instructions.

**This chart is recommended for:**
- Development/testing environments
- Simple cache servers
- Single-application deployments
- Resource-constrained environments

## Features

- ✅ StatefulSet-based deployment for data persistence
- ✅ **Master-Slave replication** (1 master + N read-only replicas)
- ✅ Customizable redis.conf configuration file
- ✅ Password authentication support
- ✅ Persistent volume for data storage
- ✅ Prometheus metrics exporter (optional sidecar)
- ✅ ServiceMonitor for Prometheus Operator
- ✅ Liveness, readiness, and startup probes
- ✅ Resource limits and requests
- ✅ Security context (non-root user)
- ✅ Horizontal Pod Autoscaling (optional, not recommended for stateful)
- ✅ Pod Disruption Budget for HA

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PersistentVolume provisioner support in the underlying infrastructure

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install redis-home charts/redis \
  -f charts/redis/values-home-single.yaml \
  --set redis.password=your-secure-password
```

**Resource allocation:** 50-250m CPU, 128-512Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install redis-startup charts/redis \
  -f charts/redis/values-startup-single.yaml \
  --set redis.password=your-secure-password
```

**Resource allocation:** 100-500m CPU, 256Mi-1Gi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with master-replica replication and monitoring:

```bash
helm install redis-prod charts/redis \
  -f charts/redis/values-prod-master-replica.yaml \
  --set redis.password=your-secure-password
```

**Features:** 3 replicas (1 master + 2 read replicas), pod anti-affinity, PodDisruptionBudget, ServiceMonitor

**Resource allocation:** 250m-2000m CPU, 512Mi-2Gi RAM, 20Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#redis).

## Installation

### 1. Basic Installation

```bash
helm install my-redis ./charts/redis
```

### 2. With Password Authentication

Create a `my-values.yaml` file:

```yaml
redis:
  password: "your-secure-password"

persistence:
  enabled: true
  size: 8Gi
```

Install with custom values:

```bash
helm install my-redis ./charts/redis -f my-values.yaml
```

### 2b. Reusing an Existing Secret

If you already manage the Redis password through your own Secret, create it first (the key defaults to `redis-password`):

```bash
kubectl create secret generic redis-auth --from-literal=redis-password='super-secure'
```

Then reference it from the chart:

```yaml
redis:
  existingSecret: redis-auth
  # secretKeyName: custom-key  # Optional, defaults to redis-password
```

The chart will skip creating a Secret and will mount the referenced one instead.

### 3. Production Deployment

See `values-example.yaml` for production-ready configuration with:
- Password authentication
- Persistence enabled
- Resource limits
- Monitoring enabled

```bash
helm install my-redis ./charts/redis -f values-example.yaml
```

## Configuration

### Redis Configuration

The chart allows full customization of `redis.conf`:

```yaml
redis:
  password: "secure-password"
  config: |
    maxmemory 512mb
    maxmemory-policy allkeys-lru
    appendonly yes
    save 900 1
    save 300 10
```

### Persistence

Configure persistent storage:

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"
  size: 20Gi
  accessMode: ReadWriteOnce
```

### Monitoring

Enable Prometheus metrics:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s

metrics:
  enabled: true
```

### Master-Slave Replication

Enable read-only replicas for scaling read operations:

```yaml
replication:
  enabled: true
  replicas: 2  # Number of read-only replicas (in addition to 1 master)
```

**This creates:**
- 1 master pod (read/write)
- N replica pods (read-only)
- Service endpoints:
  - `redis.{namespace}.svc.cluster.local` → Master (for writes)
  - `redis-master.{namespace}.svc.cluster.local` → Master explicitly
- Individual replica access via StatefulSet DNS:
  - `redis-1.redis-headless.{namespace}.svc.cluster.local` → Replica 1
  - `redis-2.redis-headless.{namespace}.svc.cluster.local` → Replica 2

**Use cases:**
- Scale read operations across multiple replicas
- Reduce load on master for read-heavy workloads
- Basic data redundancy (manual failover only)
- Choose specific replica for read operations

**Important notes:**
- ⚠️ **Manual failover only** - no automatic master promotion
- ⚠️ For automatic failover, use [Redis Operator](../../docs/03-redis-operator-migration.md) with Sentinel
- ✅ Each replica has its own persistent volume
- ✅ Password authentication is synced via `masterauth`

**Monitoring replication:**

```bash
# Check replication status
make -f make/ops/redis.mk redis-replication-info

# Check master status
make -f make/ops/redis.mk redis-master-info

# Check replica lag
make -f make/ops/redis.mk redis-replica-lag

# Check specific pod role
make -f make/ops/redis.mk redis-role POD=redis-0
```

### High Availability

Protect Redis during cluster maintenance and enable security isolation:

```yaml
# Pod Disruption Budget - prevents data loss during maintenance
podDisruptionBudget:
  enabled: true
  minAvailable: 1  # For StatefulSet, ensure at least 1 pod is always available

# Network Policy - restricts network access
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      - podSelector:
          matchLabels:
            app: backend  # Only allow access from backend pods
      ports:
        - protocol: TCP
          port: 6379
```

**Pod Disruption Budget Benefits:**
- Prevents all Redis pods from being drained simultaneously
- Ensures data availability during node maintenance
- Critical for StatefulSet deployments

**Network Policy Benefits:**
- Restricts Redis access to authorized clients only
- Provides network-level security isolation
- Complements authentication for defense-in-depth

## Common Use Cases

### 1. Cache Server

```yaml
redis:
  config: |
    maxmemory 2gb
    maxmemory-policy allkeys-lru
    appendonly no
    save ""

resources:
  limits:
    cpu: 1000m
    memory: 2.5Gi
  requests:
    cpu: 500m
    memory: 2Gi
```

### 2. Persistent Database

```yaml
redis:
  config: |
    appendonly yes
    appendfsync everysec
    save 900 1
    save 300 10
    save 60 10000

persistence:
  enabled: true
  size: 20Gi
```

### 3. Session Store

```yaml
redis:
  password: "session-secret"
  config: |
    maxmemory 1gb
    maxmemory-policy volatile-lru
    timeout 300
```

## Accessing Redis

### From Within the Cluster

```bash
# With password
kubectl run redis-client --rm -it --restart='Never' \
  --image redis:7.4.1-alpine -- \
  redis-cli -h my-redis -a your-password

# Without password
kubectl run redis-client --rm -it --restart='Never' \
  --image redis:7.4.1-alpine -- \
  redis-cli -h my-redis
```

### Port Forward

```bash
kubectl port-forward svc/my-redis 6379:6379
redis-cli -h 127.0.0.1 -p 6379
```

## Monitoring

### Redis Metrics

When metrics are enabled, Prometheus metrics are exposed at:

```
http://<pod-ip>:9121/metrics
```

Key metrics include:
- `redis_connected_clients` - Number of connected clients
- `redis_used_memory_bytes` - Memory used by Redis
- `redis_commands_processed_total` - Total commands processed
- `redis_keyspace_hits_total` / `redis_keyspace_misses_total` - Cache hit/miss rate

### Redis CLI Monitoring

```bash
# Monitor commands in real-time
kubectl exec -it my-redis-0 -- redis-cli monitor

# Get server info
kubectl exec -it my-redis-0 -- redis-cli info

# Check memory usage
kubectl exec -it my-redis-0 -- redis-cli info memory
```

## Backup and Restore

### Manual Backup

```bash
# Trigger RDB snapshot
kubectl exec my-redis-0 -- redis-cli BGSAVE

# Copy dump.rdb from pod
kubectl cp my-redis-0:/data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb
```

### Restore from Backup

```bash
# Copy backup to pod
kubectl cp ./redis-backup.rdb my-redis-0:/data/dump.rdb

# Restart Redis
kubectl delete pod my-redis-0
```

## Security Considerations

1. **Always use password authentication** in production:
   ```yaml
   redis:
     password: "strong-random-password"
   ```

2. **Network isolation**: Use NetworkPolicy to restrict access
   ```yaml
   networkPolicy:
     enabled: true
   ```

3. **Disable dangerous commands** (optional):
   ```yaml
   redis:
     config: |
       rename-command FLUSHDB ""
       rename-command FLUSHALL ""
       rename-command CONFIG ""
   ```

4. **TLS/SSL**: For production, consider using [Redis with TLS](https://redis.io/docs/manual/security/encryption/)

## Performance Tuning

### Kernel Parameters

For production deployments, configure host kernel parameters:

```yaml
initContainers:
  - name: sysctl
    image: busybox
    command:
      - sh
      - -c
      - |
        sysctl -w vm.overcommit_memory=1
        sysctl -w net.core.somaxconn=65535
    securityContext:
      privileged: true
```

### Resource Allocation

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 4Gi

redis:
  config: |
    maxmemory 3gb
    maxmemory-policy allkeys-lru
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod my-redis-0

# Check logs
kubectl logs my-redis-0

# Check configuration
kubectl exec my-redis-0 -- redis-cli CONFIG GET "*"
```

### High Memory Usage

```bash
# Check memory info
kubectl exec my-redis-0 -- redis-cli INFO memory

# Check largest keys
kubectl exec my-redis-0 -- redis-cli --bigkeys
```

### Connection Issues

```bash
# Test connectivity
kubectl exec my-redis-0 -- redis-cli PING

# Check client connections
kubectl exec my-redis-0 -- redis-cli CLIENT LIST
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `redis.password` | string | `""` | Redis password (empty = no auth) |
| `redis.config` | string | See values.yaml | Redis configuration file content |
| `persistence.enabled` | bool | `true` | Enable persistent storage |
| `persistence.size` | string | `"8Gi"` | Size of persistent volume |
| `replicaCount` | int | `1` | Number of Redis replicas |
| `metrics.enabled` | bool | `false` | Enable Prometheus metrics exporter |
| `resources.limits.memory` | string | `"512Mi"` | Memory limit |

For full configuration options, see [values.yaml](./values.yaml).

## Recent Changes

### Version 0.3.1 (2025-11-17)

**Security Fixes:**
- ✅ Fixed password exposure in readiness probe (now uses `REDISCLI_AUTH` environment variable)
- ✅ Fixed password exposure in metrics exporter command-line arguments

**Bug Fixes:**
- ✅ Fixed `persistence.existingClaim` support - now properly mounts existing PVCs

**Documentation:**
- ✅ Added clear warnings to `values-prod-sentinel.yaml` and `values-prod-cluster.yaml` (modes not implemented)
- ✅ Provided alternative solutions: Redis Operator, Bitnami charts

For full changelog, see [Chart.yaml](./Chart.yaml) or [docs/05-chart-analysis-2025-11.md](../../docs/05-chart-analysis-2025-11.md).

## Testing

For comprehensive testing scenarios, see [Testing Guide](../../docs/TESTING_GUIDE.md).

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

Redis is licensed under the [BSD 3-Clause License](https://redis.io/docs/about/license/).

This Helm chart is licensed under BSD-3-Clause.
