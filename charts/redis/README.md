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
- ✅ `mode` selector (`standalone`/`replica`) with validation; Sentinel/Cluster explicitly blocked until implemented
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

## Modes

- `mode: standalone` (default): Single instance, uses `replicaCount`.
- `mode: replica`: 1 primary + N replicas, uses `replication.replicas` (manual failover). `replication.replicas: 0` is allowed (master only) but keeps replica-ready services/config in place.
- `mode: sentinel` / `mode: cluster`: **Not implemented yet**. The chart now fails fast if selected; use Redis Operator or Bitnami charts instead.
- Backward compatibility: `replication.enabled=true` still works and maps to `mode: replica`, but `mode` is the preferred switch going forward.

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
mode: replica

replication:
  replicas: 2  # Number of read-only replicas (in addition to 1 master). Use 0 for master-only with replica wiring.
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
- Backward compatibility: `replication.enabled=true` is still accepted; when set, the chart treats it as `mode: replica`.

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

## Backup & Recovery

This chart provides comprehensive backup and recovery procedures for Redis data, configuration, and disaster recovery.

### Backup Strategy

The chart implements a **4-component backup strategy**:

1. **Configuration Backup**: Redis configuration and Kubernetes manifests
2. **RDB Snapshots**: Point-in-time binary snapshots
3. **AOF Persistence**: Append-only file for durability
4. **Replication**: Hot standby via primary-replica architecture

**RTO/RPO Targets**:
- Recovery Time Objective (RTO): < 1 hour
- Recovery Point Objective (RPO): 24 hours (daily backups)

### Quick Backup Commands

```bash
# Full backup (RDB + AOF + Config)
make -f make/ops/redis.mk redis-full-backup

# RDB snapshot only
make -f make/ops/redis.mk redis-backup-rdb

# AOF backup only
make -f make/ops/redis.mk redis-backup-aof

# Configuration backup
make -f make/ops/redis.mk redis-backup-config
```

### Quick Recovery Commands

```bash
# Restore from RDB backup
make -f make/ops/redis.mk redis-restore-rdb BACKUP_FILE=tmp/redis-backups/redis-rdb-20250101-120000.rdb

# Restore from AOF backup
make -f make/ops/redis.mk redis-restore-aof BACKUP_FILE=tmp/redis-backups/redis-aof-20250101-120000.aof

# Restore configuration
make -f make/ops/redis.mk redis-restore-config BACKUP_FILE=tmp/redis-backups/redis-config-20250101-120000.conf
```

### Disaster Recovery

```bash
# Complete cluster loss - restore from backups
make -f make/ops/redis.mk redis-disaster-recovery BACKUP_DIR=tmp/redis-backups/20250101-120000

# Replica promotion (manual failover)
make -f make/ops/redis.mk redis-promote-replica POD=redis-1
```

### Advanced Backup Features

**Automated Backups** (via CronJob):
```yaml
# Not implemented in this chart - use external backup solutions
# Examples: Velero, Kasten K10, or custom CronJob with Makefile targets
```

**PVC Snapshots** (for disaster recovery):
```bash
# Create VolumeSnapshot
make -f make/ops/redis.mk redis-create-pvc-snapshot

# Restore from VolumeSnapshot
make -f make/ops/redis.mk redis-restore-from-pvc-snapshot SNAPSHOT_NAME=redis-snapshot-20250101
```

**Best Practices**:
- Enable **both RDB and AOF** for maximum durability
- Schedule daily RDB backups (automated via external tools)
- Enable replication for hot standby
- Store backups offsite (S3, MinIO, NFS)
- Test recovery procedures regularly (quarterly recommended)
- Implement 3-2-1 backup rule (3 copies, 2 storage types, 1 offsite)

**For detailed backup procedures, disaster recovery scenarios, and troubleshooting**, see the comprehensive [Redis Backup Guide](../../docs/redis-backup-guide.md).

## Security & RBAC

This chart implements comprehensive security features including RBAC, network policies, and authentication.

### RBAC Configuration

The chart creates namespace-scoped RBAC resources for Redis pods:

```yaml
# Enable RBAC (default: true)
rbac:
  create: true
  annotations: {}
```

**RBAC Resources Created**:
- **Role**: Namespace-scoped permissions for Redis operations
- **RoleBinding**: Binds the Role to the Redis ServiceAccount
- **ServiceAccount**: Identity for Redis pods

**Permissions Granted**:
- `get`, `list`, `watch` on ConfigMaps (configuration access)
- `get`, `list`, `watch` on Secrets (credentials access)
- `get`, `list`, `watch` on Pods (health checks, operations)
- `get`, `list`, `watch` on Endpoints (service discovery)
- `get`, `list`, `watch` on PersistentVolumeClaims (storage operations)

**RBAC Best Practices**:
- Keep `rbac.create: true` in production (least-privilege principle)
- Use separate ServiceAccounts for different Redis instances
- Audit RBAC permissions regularly
- Never grant cluster-wide permissions to Redis

### Authentication & Authorization

**Password Authentication**:
```yaml
# Method 1: Inline password (development only)
redis:
  password: "your-secure-password"

# Method 2: Existing Secret (recommended for production)
redis:
  existingSecret: "redis-auth"
  secretKeyName: "redis-password"  # Default key name
```

**Create Secret for Production**:
```bash
# Generate strong random password
REDIS_PASSWORD=$(openssl rand -base64 32)

# Create Kubernetes Secret
kubectl create secret generic redis-auth \
  --from-literal=redis-password="${REDIS_PASSWORD}" \
  -n redis
```

**Redis ACL** (Advanced):
```yaml
redis:
  config: |
    # Enable ACL file
    aclfile /data/users.acl

    # Default user restrictions
    user default on >your-password ~* &* +@all
```

### Network Security

**Network Policy** (recommended for production):
```yaml
networkPolicy:
  enabled: true
  ingress:
    # Allow only from specific namespaces/pods
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      - podSelector:
          matchLabels:
            app: backend
      ports:
        - protocol: TCP
          port: 6379
```

**TLS/SSL Encryption**:
```yaml
# Not natively supported by this chart
# Use external solutions: Istio, Linkerd, or stunnel sidecar
```

**For TLS setup**, see [Redis TLS Documentation](https://redis.io/docs/manual/security/encryption/)

### Command Security

**Disable Dangerous Commands**:
```yaml
redis:
  config: |
    # Rename dangerous commands (makes them unusable)
    rename-command FLUSHDB ""
    rename-command FLUSHALL ""
    rename-command CONFIG ""
    rename-command KEYS ""
    rename-command SHUTDOWN ""
```

**Alternative: Rename Instead of Disable**:
```yaml
redis:
  config: |
    # Rename to hard-to-guess names
    rename-command FLUSHDB "FLUSHDB_MY_SECRET_2024"
    rename-command CONFIG "CONFIG_ADMIN_ONLY"
```

### Security Checklist

**Production Security Requirements**:
- ✅ Enable RBAC (`rbac.create: true`)
- ✅ Use strong password authentication (32+ character random password)
- ✅ Store passwords in Kubernetes Secrets (not inline in values.yaml)
- ✅ Enable NetworkPolicy to restrict access
- ✅ Disable/rename dangerous commands
- ✅ Run as non-root user (default: uid 999)
- ✅ Enable read-only root filesystem (where applicable)
- ✅ Set resource limits to prevent DoS
- ✅ Use Pod Security Standards (restricted profile)
- ✅ Enable audit logging (via Kubernetes audit logs)

**Security Best Practices**:
- Rotate passwords regularly (quarterly recommended)
- Use separate Redis instances for different security zones
- Monitor for unauthorized access attempts
- Enable persistence for audit trail
- Implement network segmentation
- Use Redis ACLs for fine-grained access control (Redis 6+)
- Consider TLS for data in transit

### Pod Security Context

**Default Security Context**:
```yaml
# Pod-level security
podSecurityContext:
  fsGroup: 999  # redis group

# Container-level security
securityContext:
  runAsUser: 999      # redis user
  runAsGroup: 999
  runAsNonRoot: true
  readOnlyRootFilesystem: false  # Redis needs writable /data
  capabilities:
    drop:
      - ALL
```

**Tighten Security Further**:
```yaml
securityContext:
  runAsUser: 999
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### Compliance & Auditing

**Audit Logging**:
- Kubernetes audit logs capture all Redis pod API interactions
- Enable `--audit-log-path` on kube-apiserver
- Monitor ConfigMap/Secret access patterns

**Compliance Standards**:
- **PCI-DSS**: Requires encryption at rest/transit, access controls, audit logging
- **HIPAA**: Requires encryption, access controls, audit trails
- **SOC 2**: Requires access controls, monitoring, incident response

**For advanced security configurations and compliance**, refer to:
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Redis Security Documentation](https://redis.io/docs/manual/security/)

---

## Operations

This chart includes comprehensive operational tooling via Makefile targets.

### Common Operations

```bash
# Health checks
make -f make/ops/redis.mk redis-health      # Overall health check
make -f make/ops/redis.mk redis-ping        # Simple PING test
make -f make/ops/redis.mk redis-version     # Check Redis version

# Information gathering
make -f make/ops/redis.mk redis-info        # Full INFO output
make -f make/ops/redis.mk redis-config      # Current configuration
make -f make/ops/redis.mk redis-stats       # Live statistics

# Replication monitoring (replica mode)
make -f make/ops/redis.mk redis-replication-info  # Replication status
make -f make/ops/redis.mk redis-master-info       # Master info
make -f make/ops/redis.mk redis-replica-lag       # Replica lag check
```

### Backup Operations

```bash
# Full backups
make -f make/ops/redis.mk redis-full-backup      # RDB + AOF + Config
make -f make/ops/redis.mk redis-backup-rdb       # RDB snapshot only
make -f make/ops/redis.mk redis-backup-aof       # AOF backup only
make -f make/ops/redis.mk redis-backup-config    # Configuration only

# Advanced backups
make -f make/ops/redis.mk redis-create-pvc-snapshot    # VolumeSnapshot
make -f make/ops/redis.mk redis-backup-all-namespaces  # Multi-namespace backup
```

### Recovery Operations

```bash
# Restore from backups
make -f make/ops/redis.mk redis-restore-rdb BACKUP_FILE=tmp/redis-backups/redis-rdb-20250101.rdb
make -f make/ops/redis.mk redis-restore-aof BACKUP_FILE=tmp/redis-backups/redis-aof-20250101.aof
make -f make/ops/redis.mk redis-restore-config BACKUP_FILE=tmp/redis-backups/redis-config-20250101.conf

# Disaster recovery
make -f make/ops/redis.mk redis-disaster-recovery BACKUP_DIR=tmp/redis-backups/20250101-120000
make -f make/ops/redis.mk redis-restore-from-pvc-snapshot SNAPSHOT_NAME=redis-snapshot-20250101
```

### Replication Operations (Replica Mode)

```bash
# Failover operations
make -f make/ops/redis.mk redis-promote-replica POD=redis-1  # Manual failover
make -f make/ops/redis.mk redis-force-failover               # Emergency failover

# Replication management
make -f make/ops/redis.mk redis-resync-replica POD=redis-1   # Force re-sync
make -f make/ops/redis.mk redis-role POD=redis-0             # Check pod role
```

### Maintenance Operations

```bash
# Data management
make -f make/ops/redis.mk redis-dbsize       # Database size
make -f make/ops/redis.mk redis-keys         # List all keys (use with caution)
make -f make/ops/redis.mk redis-flushdb      # Flush current database (DANGEROUS)
make -f make/ops/redis.mk redis-flushall     # Flush all databases (DANGEROUS)

# Performance analysis
make -f make/ops/redis.mk redis-slowlog      # Slow query log
make -f make/ops/redis.mk redis-latency      # Latency monitoring
make -f make/ops/redis.mk redis-memory-stats # Memory analysis

# Persistence management
make -f make/ops/redis.mk redis-save         # Trigger RDB save
make -f make/ops/redis.mk redis-bgsave       # Background RDB save
make -f make/ops/redis.mk redis-lastsave     # Last RDB save timestamp
```

### Debugging Operations

```bash
# Shell access
make -f make/ops/redis.mk redis-shell        # Interactive Redis CLI
make -f make/ops/redis.mk redis-bash         # Bash shell in pod

# Logs and monitoring
make -f make/ops/redis.mk redis-logs         # View pod logs
make -f make/ops/redis.mk redis-describe     # Describe pod
make -f make/ops/redis.mk redis-events       # View events
make -f make/ops/redis.mk redis-top          # Resource usage

# Port forwarding
make -f make/ops/redis.mk redis-port-forward # Forward port 6379 to localhost
```

### Upgrade Operations

```bash
# Pre-upgrade checks
make -f make/ops/redis.mk redis-pre-upgrade-check     # Validate upgrade readiness
make -f make/ops/redis.mk redis-check-replication     # Verify replication status

# Post-upgrade validation
make -f make/ops/redis.mk redis-post-upgrade-check    # Comprehensive validation
make -f make/ops/redis.mk redis-validate-upgrade      # Quick validation

# Rollback
make -f make/ops/redis.mk redis-upgrade-rollback      # Rollback via Helm
```

### Custom Parameters

Most Makefile targets support custom parameters:

```bash
# Custom namespace
make -f make/ops/redis.mk redis-health NAMESPACE=redis-prod

# Custom pod name
make -f make/ops/redis.mk redis-shell POD=redis-2

# Custom backup location
make -f make/ops/redis.mk redis-backup-rdb BACKUP_DIR=/mnt/backups

# Custom release name
make -f make/ops/redis.mk redis-info RELEASE=my-redis
```

**For a complete list of available Makefile targets**, run:
```bash
make -f make/ops/redis.mk help
```

---

## Upgrading

This chart supports multiple upgrade strategies depending on your deployment mode and downtime tolerance.

### Pre-Upgrade Checklist

Before upgrading Redis, complete these essential steps:

1. **Check current version**:
   ```bash
   make -f make/ops/redis.mk redis-version
   ```

2. **Review release notes**:
   - [Redis 7.4 Release Notes](https://raw.githubusercontent.com/redis/redis/7.4/00-RELEASENOTES)
   - [Redis 7.2 Release Notes](https://raw.githubusercontent.com/redis/redis/7.2/00-RELEASENOTES)

3. **Create full backup** (MANDATORY):
   ```bash
   make -f make/ops/redis.mk redis-full-backup
   ```

4. **Verify current configuration**:
   ```bash
   helm get values redis -n redis > tmp/redis-values-current.yaml
   ```

5. **Test in non-production** (CRITICAL):
   ```bash
   # Deploy test instance
   helm install redis-test charts/redis -n redis-test -f tmp/redis-values-current.yaml

   # Test upgrade
   helm upgrade redis-test charts/redis -n redis-test --set image.tag=7.4.1-alpine
   ```

### Upgrade Strategies

#### 1. Rolling Upgrade (Recommended for Production)

**Best for**: Replica mode with zero downtime requirement

**Downtime**: None (brief connection resets)

```bash
# Perform pre-upgrade backup
make -f make/ops/redis.mk redis-full-backup

# Verify replication status
make -f make/ops/redis.mk redis-replication-info

# Upgrade via Helm
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.4.1-alpine \
  --reuse-values

# Monitor rollout
kubectl rollout status statefulset/redis -n redis --timeout=10m

# Post-upgrade validation
make -f make/ops/redis.mk redis-post-upgrade-check
```

**What happens**:
1. Replicas are updated first (redis-2, redis-1)
2. Each replica reconnects to primary and syncs
3. Finally, primary (redis-0) is updated
4. Brief failover may occur during primary update

#### 2. In-Place Upgrade

**Best for**: Standalone mode or development environments

**Downtime**: 1-5 minutes

```bash
# Backup before upgrade
make -f make/ops/redis.mk redis-full-backup

# Trigger final RDB save
kubectl exec -n redis redis-0 -- redis-cli BGSAVE

# Upgrade
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.4.1-alpine \
  --reuse-values

# Monitor pod restart
kubectl get pods -n redis -w
```

#### 3. Blue-Green Deployment

**Best for**: Maximum safety with easy rollback

**Downtime**: None (requires traffic cutover)

```bash
# Deploy "green" environment with new version
kubectl create namespace redis-green
helm install redis-green charts/redis \
  -n redis-green \
  -f tmp/redis-values-current.yaml \
  --set image.tag=7.4.1-alpine

# Configure green as replica of blue
kubectl exec -n redis-green redis-green-0 -- \
  redis-cli REPLICAOF redis.redis.svc.cluster.local 6379

# Wait for full sync, then promote green
kubectl exec -n redis-green redis-green-0 -- redis-cli REPLICAOF NO ONE

# Switch traffic to green
kubectl patch service redis -n redis \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"redis-green"}}}'
```

### Version-Specific Notes

#### Redis 6.x → 7.x (Major Upgrade)

**Breaking Changes**:
- ACL system changes (stricter defaults)
- Replication protocol enhancements
- Some config parameters renamed

**Recommended Approach**: Blue-green deployment

```bash
# Review ACL configuration after upgrade
kubectl exec -n redis redis-0 -- redis-cli ACL GETUSER default

# Update configuration if needed
redis:
  config: |
    # Redis 7.x ACL configuration
    aclfile /data/users.acl
```

#### Redis 7.0 → 7.2

**Breaking Changes**: Minor (mostly internal optimizations)

**Recommended Approach**: Rolling upgrade

```bash
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.2.7-alpine \
  --reuse-values
```

#### Redis 7.2 → 7.4

**Breaking Changes**: Minimal

**Recommended Approach**: Rolling upgrade

```bash
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.4.1-alpine \
  --reuse-values
```

### Post-Upgrade Validation

Run comprehensive post-upgrade checks:

```bash
# Automated validation
make -f make/ops/redis.mk redis-post-upgrade-check

# Manual checks
make -f make/ops/redis.mk redis-version          # Verify version
make -f make/ops/redis.mk redis-health           # Health check
make -f make/ops/redis.mk redis-replication-info # Replication status
make -f make/ops/redis.mk redis-dbsize           # Data integrity
```

### Rollback Procedures

If upgrade fails or causes issues:

**Helm Rollback** (fastest):
```bash
# List release history
helm history redis -n redis

# Rollback to previous revision
helm rollback redis -n redis

# Verify rollback
make -f make/ops/redis.mk redis-version
```

**Restore from Backup** (data recovery):
```bash
# Stop current Redis
kubectl scale statefulset redis -n redis --replicas=0

# Restore from backup
make -f make/ops/redis.mk redis-restore-rdb \
  BACKUP_FILE=tmp/redis-backups/dump-pre-upgrade.rdb

# Restart Redis
kubectl scale statefulset redis -n redis --replicas=1
```

**Blue-Green Failback**:
```bash
# Switch traffic back to blue
kubectl patch service redis -n redis \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"redis"}}}'
```

### Upgrade Best Practices

1. ✅ **Always backup before upgrading**
2. ✅ **Test in non-production first**
3. ✅ **Review version-specific breaking changes**
4. ✅ **Use rolling upgrades for replica mode**
5. ✅ **Monitor replication lag during upgrades**
6. ✅ **Have a rollback plan ready**
7. ✅ **Validate thoroughly after upgrade**
8. ✅ **Schedule upgrades during low-traffic periods**

**For detailed upgrade procedures, version-specific notes, and troubleshooting**, see the comprehensive [Redis Upgrade Guide](../../docs/redis-upgrade-guide.md)

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
| `mode` | string | `"standalone"` | Deployment mode (`standalone` or `replica`; Sentinel/Cluster not implemented) |
| `redis.password` | string | `""` | Redis password (empty = no auth) |
| `redis.config` | string | See values.yaml | Redis configuration file content |
| `persistence.enabled` | bool | `true` | Enable persistent storage |
| `persistence.size` | string | `"8Gi"` | Size of persistent volume |
| `replication.replicas` | int | `2` | Number of read-only replicas when `mode=replica` (1 master is added automatically; 0 = master-only with replica wiring) |
| `replicaCount` | int | `1` | Pod count when `mode=standalone` |
| `metrics.enabled` | bool | `false` | Enable Prometheus metrics exporter |
| `resources.limits.memory` | string | `"512Mi"` | Memory limit |

For full configuration options, see [values.yaml](./values.yaml).

## Recent Changes

### Version 0.3.3 (2025-11-17)

- ✅ Added `mode` selector (`standalone`/`replica`) with validation and backward compatibility
- ✅ Allowed `replication.replicas: 0` when `mode=replica` (master-only while keeping replica wiring)
- ⚠️ Chart now fails fast when `mode=sentinel` or `mode=cluster` is selected (still not implemented)

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
