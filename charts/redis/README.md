# Redis Helm Chart

[Redis](https://redis.io/) is an open-source, in-memory data structure store used as a database, cache, message broker, and streaming engine.

## Features

- ✅ StatefulSet-based deployment for data persistence
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

## License

Redis is licensed under the [BSD 3-Clause License](https://redis.io/docs/about/license/).

This Helm chart is licensed under BSD-3-Clause.
