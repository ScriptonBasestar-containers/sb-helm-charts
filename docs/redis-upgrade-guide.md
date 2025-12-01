# Redis Upgrade Guide

This guide provides comprehensive instructions for upgrading Redis instances deployed using the ScriptonBasestar Redis Helm chart.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [Rolling Upgrade (Recommended for Production)](#rolling-upgrade-recommended-for-production)
  - [In-Place Upgrade](#in-place-upgrade)
  - [Blue-Green Deployment](#blue-green-deployment)
  - [Dump and Restore (Clean State)](#dump-and-restore-clean-state)
- [Version-Specific Upgrade Notes](#version-specific-upgrade-notes)
  - [Redis 6.x → 7.x](#redis-6x--7x)
  - [Redis 7.0 → 7.2](#redis-70--72)
  - [Redis 7.2 → 7.4](#redis-72--74)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

Upgrading Redis requires careful planning to ensure data integrity and minimize downtime. This guide covers multiple upgrade strategies suitable for different deployment modes and operational requirements.

### Upgrade Considerations

**Deployment Modes**:
- **Standalone**: Single Redis instance (simplest upgrade path)
- **Replica**: Primary + replicas (rolling upgrade recommended)
- **Sentinel/Cluster**: Not yet implemented in this chart

**Key Risks**:
- Data loss if persistence is not configured correctly
- Downtime during upgrade
- Breaking changes between major versions
- RDB/AOF format compatibility issues
- Replication protocol changes

**RTO/RPO During Upgrades**:
- **Rolling Upgrade**: RTO < 30 seconds, RPO = 0 (no data loss)
- **In-Place Upgrade**: RTO < 2 minutes, RPO = 0 (with proper persistence)
- **Blue-Green**: RTO < 5 minutes, RPO = 0 (with replication sync)
- **Dump/Restore**: RTO < 10 minutes, RPO varies (last snapshot)

---

## Pre-Upgrade Checklist

Before starting any upgrade, complete these essential steps:

### 1. Check Current Redis Version

```bash
# Via kubectl exec
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version

# Via Makefile
make -f make/ops/redis.mk redis-version
```

**Expected output**:
```
redis_version:7.0.15
```

### 2. Review Release Notes

Check the Redis release notes for breaking changes:
- [Redis 7.4 Release Notes](https://raw.githubusercontent.com/redis/redis/7.4/00-RELEASENOTES)
- [Redis 7.2 Release Notes](https://raw.githubusercontent.com/redis/redis/7.2/00-RELEASENOTES)
- [Redis 7.0 Release Notes](https://raw.githubusercontent.com/redis/redis/7.0/00-RELEASENOTES)

**Key areas to check**:
- Removed commands or deprecated features
- Configuration file format changes
- Persistence format changes (RDB/AOF)
- Replication protocol changes
- ACL changes

### 3. Verify Current Configuration

```bash
# Get current Helm values
helm get values redis -n redis > tmp/redis-values-current.yaml

# Check Redis runtime configuration
kubectl exec -n redis redis-0 -- redis-cli CONFIG GET '*' > tmp/redis-config-current.txt
```

### 4. Test in Non-Production Environment

**CRITICAL**: Always test the upgrade in a staging or development environment first.

```bash
# Create a test namespace
kubectl create namespace redis-upgrade-test

# Deploy current version
helm install redis-test charts/redis -n redis-upgrade-test -f tmp/redis-values-current.yaml

# Test upgrade procedure
helm upgrade redis-test charts/redis -n redis-upgrade-test --set image.tag=7.4.1-alpine
```

### 5. Backup All Data

**MANDATORY**: Always create a full backup before upgrading.

```bash
# Full backup (RDB + AOF + Config)
make -f make/ops/redis.mk redis-full-backup

# Verify backup files
ls -lh tmp/redis-backups/
```

**Expected backup files**:
```
redis-rdb-20250101-120000.rdb
redis-aof-20250101-120000.aof
redis-config-20250101-120000.conf
```

### 6. Document Current State

```bash
# Save current deployment state
kubectl get statefulset redis -n redis -o yaml > tmp/redis-statefulset-pre-upgrade.yaml
kubectl get pvc -n redis -o yaml > tmp/redis-pvc-pre-upgrade.yaml

# Save current pod logs
kubectl logs -n redis redis-0 --tail=1000 > tmp/redis-pre-upgrade.log
```

### 7. Schedule Maintenance Window

For production upgrades, schedule a maintenance window:
- **Standalone mode**: 5-15 minutes
- **Replica mode (rolling)**: 30-60 minutes
- **Blue-green deployment**: 1-2 hours (includes validation)

### 8. Notify Stakeholders

Inform all stakeholders about:
- Maintenance window start/end times
- Expected downtime (if any)
- Rollback plan
- Emergency contact information

---

## Upgrade Strategies

Choose the appropriate upgrade strategy based on your deployment mode, downtime tolerance, and operational requirements.

### Rolling Upgrade (Recommended for Production)

**Best for**: Replica mode deployments requiring zero downtime

**Downtime**: None (clients experience brief connection resets)

**Prerequisites**:
- `mode: replica` or `replication.enabled: true`
- At least 1 replica configured
- Persistence enabled (RDB or AOF)

**Procedure**:

#### Step 1: Pre-Upgrade Backup

```bash
# Full backup before starting
make -f make/ops/redis.mk redis-full-backup
```

#### Step 2: Verify Replication Status

```bash
# Check replication lag
kubectl exec -n redis redis-0 -- redis-cli INFO replication

# Expected: master_link_status:up, master_repl_offset and slave_repl_offset should be close
```

#### Step 3: Update Helm Chart

```bash
# Update values.yaml with new image tag
cat > tmp/redis-upgrade-values.yaml <<EOF
image:
  tag: "7.4.1-alpine"

# Keep existing configuration
mode: replica
replication:
  enabled: true
  replicas: 2

persistence:
  enabled: true
  size: 8Gi

redis:
  config: |
    # RDB + AOF for durability
    save 900 1
    save 300 10
    save 60 10000
    appendonly yes
    appendfsync everysec
EOF
```

#### Step 4: Perform Rolling Upgrade

```bash
# Helm upgrade with rolling update strategy
helm upgrade redis charts/redis \
  -n redis \
  -f tmp/redis-upgrade-values.yaml \
  --set-string podAnnotations.upgraded-at="$(date +%Y%m%d-%H%M%S)"

# Watch the rollout
kubectl rollout status statefulset/redis -n redis --timeout=10m
```

**What happens during rolling upgrade**:
1. Kubernetes updates replicas first (redis-2, redis-1)
2. Each replica pod is terminated and recreated with new version
3. Replica reconnects to primary and syncs data
4. Finally, primary (redis-0) is updated
5. Brief failover may occur during primary update

#### Step 5: Verify Each Pod After Update

```bash
# Check version of each pod
for i in 0 1 2; do
  echo "Pod redis-$i:"
  kubectl exec -n redis redis-$i -- redis-cli INFO server | grep redis_version
done
```

**Expected output**:
```
Pod redis-0:
redis_version:7.4.1
Pod redis-1:
redis_version:7.4.1
Pod redis-2:
redis_version:7.4.1
```

#### Step 6: Verify Replication Integrity

```bash
# Check replication status on all pods
for i in 0 1 2; do
  echo "=== Pod redis-$i ==="
  kubectl exec -n redis redis-$i -- redis-cli INFO replication | grep -E "role|connected_slaves|master_link_status"
done
```

**Expected output**:
```
=== Pod redis-0 ===
role:master
connected_slaves:2

=== Pod redis-1 ===
role:slave
master_link_status:up

=== Pod redis-2 ===
role:slave
master_link_status:up
```

#### Step 7: Test Data Integrity

```bash
# Write test data to primary
kubectl exec -n redis redis-0 -- redis-cli SET upgrade-test "$(date)"

# Read from replicas
kubectl exec -n redis redis-1 -- redis-cli GET upgrade-test
kubectl exec -n redis redis-2 -- redis-cli GET upgrade-test
```

---

### In-Place Upgrade

**Best for**: Standalone mode or development environments

**Downtime**: 1-5 minutes (depends on data size and restart time)

**Prerequisites**:
- `mode: standalone`
- Persistence enabled (RDB or AOF)
- Recent backup completed

**Procedure**:

#### Step 1: Pre-Upgrade Backup

```bash
# Create full backup
make -f make/ops/redis.mk redis-full-backup

# Trigger final RDB save
kubectl exec -n redis redis-0 -- redis-cli BGSAVE

# Wait for BGSAVE to complete
kubectl exec -n redis redis-0 -- redis-cli LASTSAVE
```

#### Step 2: Update Helm Values

```bash
# Prepare upgrade values
cat > tmp/redis-upgrade-values.yaml <<EOF
image:
  tag: "7.4.1-alpine"

mode: standalone
replicaCount: 1

persistence:
  enabled: true
  size: 8Gi

redis:
  config: |
    # Ensure persistence is enabled
    save 900 1
    save 300 10
    save 60 10000
    appendonly yes
    appendfsync everysec
EOF
```

#### Step 3: Perform Upgrade

```bash
# Helm upgrade
helm upgrade redis charts/redis \
  -n redis \
  -f tmp/redis-upgrade-values.yaml

# Monitor pod restart
kubectl get pods -n redis -w
```

**Downtime window**: From pod termination until new pod is ready (typically 1-3 minutes)

#### Step 4: Verify Data Persistence

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod/redis-0 -n redis --timeout=5m

# Check Redis version
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version

# Verify data is intact
kubectl exec -n redis redis-0 -- redis-cli DBSIZE
```

#### Step 5: Test Application Connectivity

```bash
# Test basic operations
kubectl exec -n redis redis-0 -- redis-cli PING
kubectl exec -n redis redis-0 -- redis-cli SET test-key "test-value"
kubectl exec -n redis redis-0 -- redis-cli GET test-key
```

---

### Blue-Green Deployment

**Best for**: Production environments requiring absolute zero downtime and easy rollback

**Downtime**: None (requires traffic cutover)

**Prerequisites**:
- Sufficient cluster resources for parallel deployment
- Load balancer or service mesh for traffic switching
- Replication configured for data sync

**Procedure**:

#### Step 1: Deploy "Green" Environment

```bash
# Create new namespace for green deployment
kubectl create namespace redis-green

# Deploy new Redis version in green namespace
helm install redis-green charts/redis \
  -n redis-green \
  -f tmp/redis-upgrade-values.yaml \
  --set image.tag=7.4.1-alpine \
  --set fullnameOverride=redis-green
```

#### Step 2: Configure Replication from Blue to Green

```bash
# Get blue (current) Redis service endpoint
BLUE_HOST=$(kubectl get svc redis -n redis -o jsonpath='{.spec.clusterIP}')
BLUE_PORT=6379

# Configure green Redis as replica of blue
kubectl exec -n redis-green redis-green-0 -- redis-cli REPLICAOF $BLUE_HOST $BLUE_PORT

# Verify replication
kubectl exec -n redis-green redis-green-0 -- redis-cli INFO replication
```

**Expected output**:
```
role:slave
master_host:10.96.1.50
master_port:6379
master_link_status:up
```

#### Step 3: Wait for Full Synchronization

```bash
# Monitor replication lag
while true; do
  kubectl exec -n redis-green redis-green-0 -- redis-cli INFO replication | grep master_repl_offset
  sleep 5
done

# When master_repl_offset stops changing, sync is complete
```

#### Step 4: Promote Green to Primary

```bash
# Stop replication on green
kubectl exec -n redis-green redis-green-0 -- redis-cli REPLICAOF NO ONE

# Verify green is now master
kubectl exec -n redis-green redis-green-0 -- redis-cli INFO replication | grep role
```

**Expected output**:
```
role:master
```

#### Step 5: Switch Application Traffic

**Option A: Update Kubernetes Service Selector**

```bash
# Update service to point to green deployment
kubectl patch service redis -n redis -p '{"spec":{"selector":{"app.kubernetes.io/instance":"redis-green"}}}'
```

**Option B: Update DNS or Ingress**

```bash
# Update ingress/DNS to point to redis-green service
# (Implementation depends on your infrastructure)
```

**Option C: Application Configuration Update**

Update application configuration to use new Redis endpoint:
- Old: `redis.redis.svc.cluster.local:6379`
- New: `redis-green.redis-green.svc.cluster.local:6379`

#### Step 6: Validate Green Environment

```bash
# Test connectivity from application
kubectl exec -n app-namespace app-pod -- redis-cli -h redis-green.redis-green.svc.cluster.local PING

# Verify data integrity
kubectl exec -n redis-green redis-green-0 -- redis-cli DBSIZE
```

#### Step 7: Monitor and Decommission Blue

```bash
# Monitor green environment for 24-48 hours

# If stable, delete blue deployment
helm uninstall redis -n redis
kubectl delete namespace redis
```

---

### Dump and Restore (Clean State)

**Best for**: Major version upgrades with breaking changes, or when you want a clean Redis instance

**Downtime**: 10-30 minutes (depends on data size)

**Prerequisites**:
- RDB or AOF backup available
- Sufficient storage for dump file
- Maintenance window scheduled

**Procedure**:

#### Step 1: Create RDB Dump

```bash
# Trigger BGSAVE on current Redis
kubectl exec -n redis redis-0 -- redis-cli BGSAVE

# Wait for completion (check LASTSAVE timestamp)
kubectl exec -n redis redis-0 -- redis-cli LASTSAVE

# Copy dump.rdb from pod
kubectl cp redis/redis-0:/data/dump.rdb tmp/redis-backups/dump-pre-upgrade.rdb
```

#### Step 2: Export Configuration

```bash
# Save current Redis configuration
kubectl exec -n redis redis-0 -- redis-cli CONFIG GET '*' > tmp/redis-config-export.txt
```

#### Step 3: Uninstall Old Deployment

```bash
# Uninstall Helm release (keep PVC)
helm uninstall redis -n redis

# Optionally delete PVC for clean state
kubectl delete pvc -n redis data-redis-0
```

#### Step 4: Install New Version

```bash
# Deploy new Redis version
helm install redis charts/redis \
  -n redis \
  -f tmp/redis-upgrade-values.yaml \
  --set image.tag=7.4.1-alpine
```

#### Step 5: Restore Data

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod/redis-0 -n redis --timeout=5m

# Stop Redis (to restore dump.rdb)
kubectl exec -n redis redis-0 -- redis-cli SHUTDOWN NOSAVE

# Copy dump file to new pod
kubectl cp tmp/redis-backups/dump-pre-upgrade.rdb redis/redis-0:/data/dump.rdb

# Start Redis (will load dump.rdb automatically)
kubectl delete pod redis-0 -n redis

# Wait for pod restart
kubectl wait --for=condition=ready pod/redis-0 -n redis --timeout=5m
```

#### Step 6: Verify Data Restore

```bash
# Check Redis version
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version

# Verify data size
kubectl exec -n redis redis-0 -- redis-cli DBSIZE

# Test sample keys
kubectl exec -n redis redis-0 -- redis-cli GET test-key
```

---

## Version-Specific Upgrade Notes

### Redis 6.x → 7.x

**Breaking Changes**:

1. **ACL System Changes**:
   - Redis 7.x has stricter ACL defaults
   - `default` user has more restricted permissions
   - **Action**: Review and update ACL rules after upgrade

2. **Replication Protocol**:
   - Enhanced replication protocol (PSYNC2 improvements)
   - **Action**: Upgrade replicas before primary in rolling upgrade

3. **CONFIG Command**:
   - Some config parameters renamed or removed
   - **Action**: Review `redis.config` in values.yaml

4. **Lua Scripting**:
   - Redis Functions introduced (better than EVAL/EVALSHA)
   - **Action**: Consider migrating scripts to Redis Functions

5. **Client-Side Caching**:
   - Protocol changes for client-side caching (RESP3)
   - **Action**: Update client libraries if using caching

**New Features**:
- **Redis Functions**: Persistent, versioned Lua scripts
- **Sharded Pub/Sub**: Channel-based pub/sub for cluster mode
- **Improved ACLs**: More granular permissions
- **Faster RDB loading**: Reduced startup time

**Upgrade Considerations**:

```yaml
# Recommended configuration for Redis 7.x
redis:
  config: |
    # ACL file location (if using ACL config file)
    aclfile /data/users.acl

    # Enable AOF for durability
    appendonly yes
    appendfsync everysec

    # RDB snapshots
    save 900 1
    save 300 10
    save 60 10000

    # Memory management
    maxmemory 512mb
    maxmemory-policy allkeys-lru

    # Replication settings (for replica mode)
    replica-read-only yes
    replica-serve-stale-data yes
```

**Testing after upgrade**:

```bash
# Verify ACL default user
kubectl exec -n redis redis-0 -- redis-cli ACL GETUSER default

# Test Redis Functions (new in 7.x)
kubectl exec -n redis redis-0 -- redis-cli FUNCTION LIST

# Check replication protocol version
kubectl exec -n redis redis-0 -- redis-cli INFO replication | grep master_replid
```

---

### Redis 7.0 → 7.2

**Breaking Changes**:

1. **Command Renaming**:
   - Some internal commands deprecated
   - **Action**: Review custom scripts using deprecated commands

2. **Memory Allocator**:
   - jemalloc updated to newer version
   - **Action**: Monitor memory usage after upgrade

3. **Module API**:
   - Module API version updated
   - **Action**: Update Redis modules to compatible versions

**New Features**:
- **Improved Eviction**: Better LRU/LFU algorithms
- **Cluster Improvements**: Faster failover and resharding
- **Enhanced Monitoring**: More INFO fields

**Upgrade Procedure**:

Use **Rolling Upgrade** for minimal downtime.

```bash
# Update image tag
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.2.7-alpine \
  --reuse-values
```

---

### Redis 7.2 → 7.4

**Breaking Changes**:

1. **Configuration File Format**:
   - Some deprecated config options removed
   - **Action**: Validate `redis.config` against Redis 7.4 docs

2. **Replication Improvements**:
   - Better handling of network partitions
   - **Action**: Test failover scenarios after upgrade

**New Features**:
- **Performance Improvements**: Faster SUNION, SINTER operations
- **Better Memory Efficiency**: Reduced memory overhead for small datasets
- **Enhanced Monitoring**: Additional metrics in INFO command

**Upgrade Procedure**:

Use **Rolling Upgrade** for minimal downtime.

```bash
# Update image tag
helm upgrade redis charts/redis \
  -n redis \
  --set image.tag=7.4.1-alpine \
  --reuse-values
```

**Post-Upgrade Validation**:

```bash
# Verify version
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version

# Check for any warnings in logs
kubectl logs -n redis redis-0 --tail=100

# Test performance (should be slightly better)
kubectl exec -n redis redis-0 -- redis-cli --intrinsic-latency 10
```

---

## Post-Upgrade Validation

After completing the upgrade, perform these validation steps:

### 1. Version Verification

```bash
# Check Redis version on all pods
make -f make/ops/redis.mk redis-version

# Or manually:
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version
```

### 2. Health Check

```bash
# PING test
kubectl exec -n redis redis-0 -- redis-cli PING

# Expected: PONG
```

### 3. Replication Status (Replica Mode)

```bash
# Check replication on primary
kubectl exec -n redis redis-0 -- redis-cli INFO replication

# Verify:
# - role:master
# - connected_slaves:2 (or your replica count)
# - master_repl_offset and slave_repl_offset should be close
```

### 4. Persistence Verification

```bash
# Check last RDB save
kubectl exec -n redis redis-0 -- redis-cli LASTSAVE

# Check AOF status
kubectl exec -n redis redis-0 -- redis-cli INFO persistence | grep aof
```

### 5. Data Integrity Check

```bash
# Write test data
kubectl exec -n redis redis-0 -- redis-cli SET upgrade-validation-key "$(date)"

# Read from primary
kubectl exec -n redis redis-0 -- redis-cli GET upgrade-validation-key

# Read from replicas (if applicable)
kubectl exec -n redis redis-1 -- redis-cli GET upgrade-validation-key
```

### 6. Performance Validation

```bash
# Measure latency
kubectl exec -n redis redis-0 -- redis-cli --latency-history

# Measure operations per second
kubectl exec -n redis redis-0 -- redis-cli --stat
```

### 7. Application Integration Test

```bash
# Test from application pod
kubectl exec -n app-namespace app-pod -- redis-cli -h redis.redis.svc.cluster.local PING

# Monitor application logs for Redis errors
kubectl logs -n app-namespace app-pod --tail=100 | grep -i redis
```

### 8. Log Review

```bash
# Check Redis logs for errors or warnings
kubectl logs -n redis redis-0 --tail=200

# Look for:
# - Warning messages about deprecated features
# - Replication sync errors
# - AOF/RDB loading errors
```

### 9. Resource Usage Check

```bash
# Check CPU/Memory usage
kubectl top pod -n redis

# Compare with pre-upgrade baseline
```

### 10. Backup Validation

```bash
# Create post-upgrade backup
make -f make/ops/redis.mk redis-full-backup

# Verify backup files
ls -lh tmp/redis-backups/
```

---

## Rollback Procedures

If the upgrade fails or causes issues, use these rollback procedures:

### Rollback Strategy 1: Helm Rollback (Fastest)

**Best for**: Issues discovered immediately after upgrade

**Downtime**: < 2 minutes

```bash
# List Helm release history
helm history redis -n redis

# Rollback to previous revision
helm rollback redis -n redis

# Monitor rollback
kubectl rollout status statefulset/redis -n redis --timeout=5m

# Verify version
kubectl exec -n redis redis-0 -- redis-cli INFO server | grep redis_version
```

### Rollback Strategy 2: Restore from Backup (Data Recovery)

**Best for**: Data corruption or loss detected after upgrade

**Downtime**: 5-15 minutes

```bash
# Stop current Redis
kubectl scale statefulset redis -n redis --replicas=0

# Delete PVC (if necessary)
kubectl delete pvc data-redis-0 -n redis

# Reinstall with previous version
helm install redis charts/redis \
  -n redis \
  -f tmp/redis-values-current.yaml \
  --set image.tag=7.0.15-alpine

# Restore from backup
kubectl cp tmp/redis-backups/dump-pre-upgrade.rdb redis/redis-0:/data/dump.rdb

# Restart Redis to load backup
kubectl delete pod redis-0 -n redis

# Verify data
kubectl exec -n redis redis-0 -- redis-cli DBSIZE
```

### Rollback Strategy 3: Blue-Green Failback

**Best for**: Blue-green deployments with issues in green environment

**Downtime**: None

```bash
# Switch traffic back to blue environment
kubectl patch service redis -n redis -p '{"spec":{"selector":{"app.kubernetes.io/instance":"redis"}}}'

# Verify traffic is back on blue
kubectl exec -n app-namespace app-pod -- redis-cli -h redis.redis.svc.cluster.local INFO server | grep redis_version

# Delete green environment
helm uninstall redis-green -n redis-green
kubectl delete namespace redis-green
```

### Rollback Decision Matrix

| Issue | Rollback Strategy | Expected Downtime |
|-------|-------------------|-------------------|
| Pod won't start | Helm rollback | < 2 minutes |
| Performance degradation | Helm rollback | < 2 minutes |
| Data corruption | Restore from backup | 5-15 minutes |
| Application errors | Blue-green failback | None |
| Replication issues | Helm rollback | < 3 minutes |

---

## Troubleshooting

### Issue 1: Pod Stuck in CrashLoopBackOff After Upgrade

**Symptoms**:
```bash
kubectl get pods -n redis
# NAME      READY   STATUS             RESTARTS   AGE
# redis-0   0/1     CrashLoopBackOff   5          10m
```

**Diagnosis**:

```bash
# Check pod logs
kubectl logs -n redis redis-0

# Common errors:
# - "Wrong RDB version"
# - "Bad file format reading the append only file"
# - "Fatal error: can't open config file '/data/redis.conf'"
```

**Solutions**:

**A. RDB Version Mismatch**:

```bash
# Backup existing RDB
kubectl cp redis/redis-0:/data/dump.rdb tmp/redis-backups/dump-corrupted.rdb

# Delete RDB and let Redis create new one
kubectl exec -n redis redis-0 -- rm /data/dump.rdb

# Restart pod
kubectl delete pod redis-0 -n redis
```

**B. AOF Corruption**:

```bash
# Check AOF integrity
kubectl exec -n redis redis-0 -- redis-check-aof /data/appendonly.aof

# Repair AOF
kubectl exec -n redis redis-0 -- redis-check-aof --fix /data/appendonly.aof

# Restart pod
kubectl delete pod redis-0 -n redis
```

**C. Configuration Error**:

```bash
# Test configuration
kubectl exec -n redis redis-0 -- redis-server /etc/redis/redis.conf --test-memory 1

# Review configuration
kubectl get configmap redis-config -n redis -o yaml
```

---

### Issue 2: Replication Broken After Upgrade

**Symptoms**:
```bash
kubectl exec -n redis redis-1 -- redis-cli INFO replication
# master_link_status:down
# master_link_down_since_seconds:120
```

**Diagnosis**:

```bash
# Check primary status
kubectl exec -n redis redis-0 -- redis-cli INFO replication

# Check replica logs
kubectl logs -n redis redis-1 --tail=100
```

**Solutions**:

**A. Replication Protocol Mismatch**:

```bash
# Force replica to re-sync
kubectl exec -n redis redis-1 -- redis-cli REPLICAOF NO ONE
kubectl exec -n redis redis-1 -- redis-cli REPLICAOF redis-0.redis-headless.redis.svc.cluster.local 6379

# Monitor sync progress
kubectl exec -n redis redis-1 -- redis-cli INFO replication | grep master_link_status
```

**B. Network Issues**:

```bash
# Test connectivity from replica to primary
kubectl exec -n redis redis-1 -- redis-cli -h redis-0.redis-headless.redis.svc.cluster.local PING

# Check Redis port accessibility
kubectl exec -n redis redis-1 -- nc -zv redis-0.redis-headless.redis.svc.cluster.local 6379
```

---

### Issue 3: High Memory Usage After Upgrade

**Symptoms**:
```bash
kubectl top pod -n redis
# NAME      CPU   MEMORY
# redis-0   10m   800Mi  # Was 400Mi before upgrade
```

**Diagnosis**:

```bash
# Check memory stats
kubectl exec -n redis redis-0 -- redis-cli INFO memory

# Check for memory leaks
kubectl exec -n redis redis-0 -- redis-cli MEMORY DOCTOR
```

**Solutions**:

**A. Adjust maxmemory Settings**:

```bash
# Update values.yaml
cat >> values.yaml <<EOF
redis:
  config: |
    maxmemory 512mb
    maxmemory-policy allkeys-lru
EOF

# Upgrade Helm release
helm upgrade redis charts/redis -n redis -f values.yaml
```

**B. Enable Memory Optimization**:

```bash
# Runtime adjustment (temporary)
kubectl exec -n redis redis-0 -- redis-cli CONFIG SET activedefrag yes
kubectl exec -n redis redis-0 -- redis-cli CONFIG SET lazyfree-lazy-eviction yes
```

---

### Issue 4: Slow Performance After Upgrade

**Symptoms**:
- Increased latency
- Lower throughput
- Application timeouts

**Diagnosis**:

```bash
# Measure latency
kubectl exec -n redis redis-0 -- redis-cli --latency

# Check slow log
kubectl exec -n redis redis-0 -- redis-cli SLOWLOG GET 10

# Monitor operations
kubectl exec -n redis redis-0 -- redis-cli --stat
```

**Solutions**:

**A. Disable Persistence (Temporary Testing)**:

```bash
# Disable AOF temporarily
kubectl exec -n redis redis-0 -- redis-cli CONFIG SET appendonly no

# Test performance
kubectl exec -n redis redis-0 -- redis-cli --latency
```

**B. Adjust Configuration**:

```bash
# Optimize for performance
redis:
  config: |
    # Faster fsync policy (less durable)
    appendfsync everysec

    # Disable background saves during high load
    stop-writes-on-bgsave-error no

    # Tune TCP settings
    tcp-backlog 511
    tcp-keepalive 300
```

---

### Issue 5: Data Loss After Upgrade

**Symptoms**:
- Missing keys
- DBSIZE shows lower count than expected

**Diagnosis**:

```bash
# Check RDB load status
kubectl logs -n redis redis-0 | grep -i "DB loaded from"

# Check AOF status
kubectl exec -n redis redis-0 -- redis-cli INFO persistence | grep aof

# Verify backup
ls -lh tmp/redis-backups/
```

**Solutions**:

**Immediate Recovery**:

```bash
# Stop Redis
kubectl scale statefulset redis -n redis --replicas=0

# Restore from pre-upgrade backup
kubectl cp tmp/redis-backups/dump-pre-upgrade.rdb redis/redis-0:/data/dump.rdb

# Restart Redis
kubectl scale statefulset redis -n redis --replicas=1

# Verify data
kubectl exec -n redis redis-0 -- redis-cli DBSIZE
```

---

## Best Practices

### 1. Always Test Upgrades in Non-Production First

Create a replica of your production environment and test the upgrade process:

```bash
# Clone production values
helm get values redis -n redis > tmp/redis-prod-values.yaml

# Deploy test instance
helm install redis-test charts/redis -n redis-test -f tmp/redis-prod-values.yaml

# Test upgrade
helm upgrade redis-test charts/redis -n redis-test --set image.tag=7.4.1-alpine
```

### 2. Maintain Multiple Backups

Implement 3-2-1 backup strategy:
- 3 copies of data
- 2 different storage types (PVC + object storage)
- 1 offsite backup

```bash
# Automated backup script
#!/bin/bash
make -f make/ops/redis.mk redis-full-backup

# Upload to S3
aws s3 cp tmp/redis-backups/ s3://my-backups/redis/ --recursive

# Keep last 30 days
find tmp/redis-backups/ -mtime +30 -delete
```

### 3. Monitor Replication Lag During Upgrades

```bash
# Continuous monitoring script
while true; do
  kubectl exec -n redis redis-0 -- redis-cli INFO replication | grep master_repl_offset
  kubectl exec -n redis redis-1 -- redis-cli INFO replication | grep slave_repl_offset
  sleep 2
done
```

### 4. Use Pod Disruption Budgets

Ensure minimum availability during upgrades:

```yaml
# In values.yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1  # For replica mode with 2+ replicas
```

### 5. Gradually Roll Out Upgrades

For large Redis fleets:

```bash
# Week 1: Upgrade dev/test environments
helm upgrade redis-dev charts/redis -n redis-dev --set image.tag=7.4.1-alpine

# Week 2: Upgrade staging
helm upgrade redis-staging charts/redis -n redis-staging --set image.tag=7.4.1-alpine

# Week 3: Upgrade production (off-peak hours)
helm upgrade redis charts/redis -n redis --set image.tag=7.4.1-alpine
```

### 6. Document Upgrade History

Maintain a changelog of all upgrades:

```bash
# Create upgrade log
cat >> UPGRADE_HISTORY.md <<EOF
## $(date +%Y-%m-%d) - Redis 7.0.15 → 7.4.1

- Upgrade method: Rolling upgrade
- Downtime: None
- Issues: None
- Rollback required: No
- Validated by: ops-team
EOF
```

### 7. Configure Health Checks Appropriately

Ensure liveness/readiness probes are configured correctly:

```yaml
# In values.yaml
livenessProbe:
  tcpSocket:
    port: redis
  initialDelaySeconds: 30  # Give Redis time to load RDB/AOF
  periodSeconds: 10
  failureThreshold: 6  # Allow for slower restarts during upgrades

readinessProbe:
  exec:
    command:
      - redis-cli
      - ping
  initialDelaySeconds: 10
  periodSeconds: 10
```

### 8. Use Version-Specific Configurations

Maintain separate configuration files for different Redis versions:

```bash
# values-redis-7.0.yaml
image:
  tag: "7.0.15-alpine"

# values-redis-7.4.yaml
image:
  tag: "7.4.1-alpine"

redis:
  config: |
    # Redis 7.4-specific optimizations
    # ...
```

### 9. Monitor Metrics During and After Upgrade

Key metrics to watch:
- **Latency**: p50, p95, p99 latency
- **Throughput**: ops/sec
- **Memory usage**: used_memory, used_memory_rss
- **Replication lag**: master_repl_offset - slave_repl_offset
- **Connection count**: connected_clients
- **Keyspace hits/misses**: keyspace_hits, keyspace_misses

### 10. Have a Rollback Plan Ready

Before starting upgrade:
- Document current state
- Create recent backup
- Prepare rollback commands
- Test rollback procedure in staging
- Define rollback decision criteria (SLA thresholds)

---

## Summary

This guide provides comprehensive upgrade procedures for Redis deployments. Key takeaways:

✅ **Always backup before upgrading** - Use `make -f make/ops/redis.mk redis-full-backup`

✅ **Test in non-production first** - Validate upgrade in staging environment

✅ **Choose the right upgrade strategy**:
- **Rolling upgrade**: Zero downtime for replica mode
- **In-place upgrade**: Simple for standalone mode
- **Blue-green**: Maximum safety with easy rollback
- **Dump/restore**: Clean state for major version jumps

✅ **Review version-specific breaking changes** - Check Redis release notes

✅ **Validate after upgrade** - Run comprehensive post-upgrade checks

✅ **Have a rollback plan** - Know how to revert if issues arise

For additional support, refer to:
- [Redis Backup Guide](./redis-backup-guide.md)
- [Redis Chart README](../charts/redis/README.md)
- [Redis Official Documentation](https://redis.io/docs/)
- [Redis Release Notes](https://github.com/redis/redis/tree/unstable/00-RELEASENOTES)

---

**Document Version**: 1.0.0
**Last Updated**: 2025-12-01
**Tested Redis Versions**: 7.0.15, 7.2.7, 7.4.1
