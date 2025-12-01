# Redis Backup & Recovery Guide

This comprehensive guide covers backup and recovery procedures for the Redis Helm chart deployment in Kubernetes.

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Disaster Recovery](#disaster-recovery)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Philosophy

Redis backup strategy in Kubernetes focuses on:
- **RDB snapshots** for point-in-time backups
- **AOF (Append Only File)** for durability and minimal data loss
- **Replication** for high availability
- **PVC snapshots** for disaster recovery
- **Configuration backups** for infrastructure-as-code

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) | Method |
|----------|---------------------|---------------------|--------|
| **RDB restore** | < 10 minutes | 15 minutes - 1 hour | RDB snapshot |
| **AOF restore** | < 30 minutes | 1 second | AOF replay |
| **Replica failover** | < 1 minute | Near-zero | Replica promotion |
| **Disaster recovery** | < 2 hours | 24 hours | PVC snapshot restore |

### Backup Types Comparison

| Type | Speed | Size | Use Case | Data Loss Risk |
|------|-------|------|----------|----------------|
| **RDB Snapshot** | Fast (async) | Small (compressed) | Periodic backups | 1-15 minutes |
| **AOF** | Slower (sync) | Larger (append log) | Durability, PITR | 1 second (everysec) |
| **Replication** | Real-time | N/A (live replica) | HA, read scaling | Near-zero |
| **PVC Snapshot** | Very fast | Full volume size | Disaster recovery | Depends on last RDB/AOF |

---

## Backup Strategy

### Multi-Layered Approach

The Redis chart supports a **4-component backup strategy**:

```
┌─────────────────────────────────────────────────────────────┐
│                    Redis Backup Strategy                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Configuration Backups (ConfigMap + Secret)               │
│     ├─ Frequency: Daily / Before changes                    │
│     ├─ Retention: 90 days                                   │
│     └─ Size: < 100 KB                                       │
│                                                              │
│  2. RDB Snapshots (dump.rdb)                                 │
│     ├─ Frequency: Hourly / Daily                            │
│     ├─ Retention: 7-30 days                                 │
│     └─ Size: Depends on dataset (1 MB - 10 GB+)             │
│                                                              │
│  3. AOF (Append Only File)                                   │
│     ├─ Frequency: Continuous (every second)                 │
│     ├─ Retention: Until rewrite                             │
│     └─ Size: Larger than RDB, compressed via rewrite        │
│                                                              │
│  4. Replication (Hot Standby)                                │
│     ├─ Frequency: Real-time                                 │
│     ├─ Retention: N/A (live replica)                        │
│     └─ RPO: Near-zero                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Recommended Configuration

**Development environments:**
```yaml
redis:
  config: |
    # RDB snapshots only (default)
    save 900 1
    save 300 10
    save 60 10000
    appendonly no
```

**Production environments:**
```yaml
redis:
  config: |
    # RDB snapshots
    save 900 1
    save 300 10
    save 60 10000

    # AOF enabled for durability
    appendonly yes
    appendfilename "appendonly.aof"
    appendfsync everysec

    # Replication (when mode: replica)
    replica-serve-stale-data yes
    replica-read-only yes

replication:
  enabled: true
  replicas: 2
```

---

## Backup Components

### 1. Configuration Backups

**What**: ConfigMap (redis.conf) and Secret (password)

**Why**:
- Restore Redis configuration after cluster recreation
- Track configuration changes over time
- Enable infrastructure-as-code workflows

**Backup frequency**: Daily (automated) / Before changes (manual)

**Retention**: 90 days

**Backup command**:
```bash
make -f make/ops/redis.mk redis-backup-config
```

**What's backed up**:
- ConfigMap: `redis-config` (redis.conf)
- Secret: `redis-secret` (password)
- Kubernetes manifests (StatefulSet, Service)

**Recovery time**: < 5 minutes

---

### 2. RDB Snapshots

**What**: Redis Database (RDB) - point-in-time binary snapshot

**Why**:
- Fast, compact backups (compressed binary format)
- Low overhead (background process)
- Easy to transfer and restore
- Default Redis persistence method

**How RDB works**:
```
[Dataset in Memory]
        ↓
   [BGSAVE fork()]
        ↓
   [Child process writes dump.rdb]
        ↓
   [Atomic rename: temp.rdb → dump.rdb]
```

**Configuration** (`redis.conf`):
```ini
# Save snapshots based on time + changes
save 900 1      # After 900 sec (15 min) if at least 1 key changed
save 300 10     # After 300 sec (5 min) if at least 10 keys changed
save 60 10000   # After 60 sec if at least 10000 keys changed

# RDB settings
stop-writes-on-bgsave-error yes  # Stop writes if save fails
rdbcompression yes               # Compress RDB files
rdbchecksum yes                  # Checksum for corruption detection
dbfilename dump.rdb              # RDB filename
dir /data                        # RDB directory
```

**Backup methods**:

#### Automatic snapshots (configured via save directives)
Redis automatically saves RDB files based on configuration.

#### Manual BGSAVE
```bash
# Trigger background save
kubectl exec -it redis-0 -- redis-cli BGSAVE

# Check save status
kubectl exec -it redis-0 -- redis-cli LASTSAVE
```

#### Manual SAVE (blocking - use with caution)
```bash
# Synchronous save (blocks all clients)
kubectl exec -it redis-0 -- redis-cli SAVE
```

**Backup frequency**:
- Automatic: Based on `save` directives (every 15 min if 1 key changed)
- Manual: On-demand via Makefile

**Retention**: 7-30 days

**Commands**:
```bash
# Trigger RDB snapshot
make -f make/ops/redis.mk redis-backup-rdb

# Copy RDB file from pod
make -f make/ops/redis.mk redis-backup-rdb-download

# Verify RDB file
make -f make/ops/redis.mk redis-backup-verify FILE=dump.rdb
```

**Recovery time**: 1-10 minutes (depends on dataset size)

**Pros**:
- Fast backups (background process)
- Compact file size (compressed)
- Low performance impact
- Easy to transfer

**Cons**:
- Data loss risk (up to 15 minutes with default config)
- Requires free memory (fork() doubles memory temporarily)
- Not suitable for real-time durability

---

### 3. AOF (Append Only File)

**What**: Append Only File - log of all write operations

**Why**:
- **Better durability** than RDB (1 second data loss max)
- **Point-in-Time Recovery** capability
- **Automatic recovery** on restart
- Suitable for critical data that requires minimal loss

**How AOF works**:
```
[Write Command: SET key value]
        ↓
   [Append to AOF buffer]
        ↓
   [Fsync to disk] (every second / always / no)
        ↓
   [appendonly.aof grows]
        ↓
   [AOF Rewrite] (compact AOF when too large)
```

**Configuration** (`redis.conf`):
```ini
# Enable AOF
appendonly yes
appendfilename "appendonly.aof"

# Fsync policy (durability vs performance trade-off)
appendfsync everysec  # Sync every second (recommended)
# appendfsync always  # Sync every write (slowest, safest)
# appendfsync no      # Let OS decide (fastest, riskiest)

# AOF rewrite settings
no-appendfsync-on-rewrite no      # Don't fsync during rewrite
auto-aof-rewrite-percentage 100   # Rewrite when 100% larger
auto-aof-rewrite-min-size 64mb    # Min size before rewrite
```

**Fsync policies comparison**:

| Policy | Data Loss Risk | Performance | Use Case |
|--------|----------------|-------------|----------|
| **always** | None (disk failure only) | Slowest | Critical financial data |
| **everysec** | 1 second | Good (recommended) | Production (balanced) |
| **no** | Up to 30 seconds | Fastest | Dev/test, cache-only |

**AOF Rewrite**:

AOF files grow continuously. Redis automatically rewrites them to compact size.

```bash
# Manual AOF rewrite (background)
kubectl exec -it redis-0 -- redis-cli BGREWRITEAOF

# Check rewrite status
kubectl exec -it redis-0 -- redis-cli INFO persistence | grep aof_rewrite
```

**Backup frequency**: Continuous (every second with `appendfsync everysec`)

**Commands**:
```bash
# Backup AOF file
make -f make/ops/redis.mk redis-backup-aof

# Trigger AOF rewrite (compact)
make -f make/ops/redis.mk redis-aof-rewrite

# Verify AOF file
make -f make/ops/redis.mk redis-backup-verify FILE=appendonly.aof
```

**Recovery time**: 1-30 minutes (depends on AOF size and replay speed)

**Pros**:
- Minimal data loss (1 second)
- More durable than RDB
- Automatic recovery on restart
- Human-readable format (Redis commands)

**Cons**:
- Larger file size than RDB
- Slower recovery (must replay all commands)
- Higher disk I/O overhead

---

### 4. Replication (Hot Standby)

**What**: Real-time Redis replication for high availability

**Why**:
- **Near-zero RPO**: Continuous data replication
- **Fast failover**: < 1 minute RTO
- **Read scaling**: Offload reads to replicas
- **No backup window**: Always available

**Replication architecture**:

```
┌──────────────┐     Async      ┌──────────────┐
│  redis-0     │ ───────────→  │  redis-1     │
│  (Primary)   │                │  (Replica)   │
│  Read/Write  │                │  Read Only   │
└──────────────┘                └──────────────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │  redis-2     │
                                 │  (Replica)   │
                                 │  Read Only   │
                                 └──────────────┘
```

**Configuration**:

**Primary** (`values.yaml`):
```yaml
mode: replica  # Enable replication mode
replication:
  enabled: true
  replicas: 2  # Number of replicas
```

**Replica configuration** (auto-configured by chart):
```ini
# redis.conf on replicas
replicaof redis-0.redis-headless 6379
replica-serve-stale-data yes
replica-read-only yes
```

**Replication workflow**:

1. **Initial sync**:
   - Replica connects to primary
   - Primary creates RDB snapshot
   - Primary sends RDB to replica
   - Replica loads RDB
   - Primary sends buffered commands

2. **Continuous replication**:
   - Primary sends write commands to replicas
   - Replicas apply commands asynchronously

**Commands**:
```bash
# Check replication status
make -f make/ops/redis.mk redis-replication-status

# Check replication lag
make -f make/ops/redis.mk redis-replication-lag

# Promote replica to primary
make -f make/ops/redis.mk redis-promote-replica POD=redis-1
```

**Failover procedure**:

1. Detect primary failure (monitoring, health checks)
2. Select replica to promote (choose replica with least lag)
3. Promote replica:
   ```bash
   kubectl exec -it redis-1 -- redis-cli REPLICAOF NO ONE
   ```
4. Update application connection string to new primary
5. Reconfigure other replicas to replicate from new primary

**Recovery time**: < 1 minute (manual) / < 30 seconds (automated with Sentinel/Cluster)

**Note**: This chart supports **manual failover**. For automatic failover, consider:
- **Redis Sentinel** (not implemented in this chart)
- **Redis Cluster** (not implemented in this chart)
- **Redis Operator** (recommended for production HA)

---

## Backup Procedures

### Daily Backup Routine

**Automated backup strategy**:

```yaml
# CronJob for daily RDB backups
apiVersion: batch/v1
kind: CronJob
metadata:
  name: redis-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: redis-backup
            image: redis:7-alpine
            command:
            - /bin/sh
            - -c
            - |
              # Trigger RDB snapshot
              redis-cli -h redis-0.redis-headless BGSAVE

              # Wait for save to complete
              while [ "$(redis-cli -h redis-0.redis-headless LASTSAVE)" = "$LAST_SAVE" ]; do
                sleep 5
              done

              # Copy RDB file
              kubectl cp redis-0:/data/dump.rdb /backup/redis-dump-$(date +%Y%m%d).rdb

              # Upload to S3 (optional)
              aws s3 cp /backup/redis-dump-$(date +%Y%m%d).rdb s3://redis-backups/

              # Cleanup old backups
              find /backup -name "redis-dump-*.rdb" -mtime +30 -delete
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: redis-backup-pvc
          restartPolicy: OnFailure
```

### Manual Backup Procedures

#### 1. RDB Snapshot Backup

```bash
# Using Makefile
make -f make/ops/redis.mk redis-backup-rdb

# Manual execution
kubectl exec -it redis-0 -- redis-cli BGSAVE

# Wait for completion
kubectl exec -it redis-0 -- redis-cli LASTSAVE

# Copy RDB file from pod
kubectl cp redis-0:/data/dump.rdb tmp/redis-backups/dump-$(date +%Y%m%d).rdb
```

**Output**: `tmp/redis-backups/dump-20250115.rdb`

#### 2. AOF Backup

```bash
# Using Makefile
make -f make/ops/redis.mk redis-backup-aof

# Manual execution
kubectl cp redis-0:/data/appendonly.aof tmp/redis-backups/appendonly-$(date +%Y%m%d).aof
```

#### 3. Configuration Backup

```bash
# Using Makefile
make -f make/ops/redis.mk redis-backup-config

# Manual execution
kubectl get configmap redis-config -o yaml > redis-config-$(date +%Y%m%d).yaml
kubectl get secret redis-secret -o yaml > redis-secret-$(date +%Y%m%d).yaml
```

#### 4. Full Backup (RDB + AOF + Config)

```bash
# Complete backup
make -f make/ops/redis.mk redis-backup-all
```

### Pre-Upgrade Backup

**Always backup before upgrades**:

```bash
# Step 1: Trigger final RDB snapshot
make -f make/ops/redis.mk redis-backup-rdb

# Step 2: Backup AOF (if enabled)
make -f make/ops/redis.mk redis-backup-aof

# Step 3: Backup configuration
make -f make/ops/redis.mk redis-backup-config

# Step 4: PVC snapshot (optional but recommended)
make -f make/ops/redis.mk redis-backup-pvc-snapshot

# Step 5: Verify backups
ls -lh tmp/redis-backups/
```

### Backup Verification

**Always verify backups**:

```bash
# Check RDB file integrity
redis-check-rdb tmp/redis-backups/dump.rdb

# Check AOF file integrity
redis-check-aof tmp/redis-backups/appendonly.aof

# Using Makefile
make -f make/ops/redis.mk redis-backup-verify FILE=tmp/redis-backups/dump.rdb
```

---

## Recovery Procedures

### Recovery Decision Tree

```
What needs to be restored?
  ├─ Complete data loss → Full restore (RDB or AOF)
  ├─ Partial data corruption → Point-in-time recovery (AOF)
  ├─ Configuration lost → Config restore
  └─ Primary failed → Replica promotion
```

### 1. Restore from RDB Snapshot

**Scenario**: Complete data loss, need to restore from RDB backup

**Steps**:

```bash
# Step 1: Stop Redis (to prevent writes during restore)
kubectl scale statefulset redis --replicas=0

# Step 2: Copy RDB file to pod
kubectl cp tmp/redis-backups/dump-20250115.rdb redis-0:/data/dump.rdb

# Step 3: Start Redis
kubectl scale statefulset redis --replicas=1

# Step 4: Wait for pod ready
kubectl wait --for=condition=ready pod/redis-0 --timeout=300s

# Step 5: Verify data
kubectl exec -it redis-0 -- redis-cli DBSIZE
kubectl exec -it redis-0 -- redis-cli KEYS '*' | head -10
```

**Recovery time**: 5-10 minutes

**Data loss**: Up to last RDB snapshot interval (15 min - 1 hour)

### 2. Restore from AOF

**Scenario**: Need minimal data loss, restore from AOF backup

**Steps**:

```bash
# Step 1: Stop Redis
kubectl scale statefulset redis --replicas=0

# Step 2: Copy AOF file to pod
kubectl cp tmp/redis-backups/appendonly-20250115.aof redis-0:/data/appendonly.aof

# Step 3: Enable AOF in configuration (if not already enabled)
# Update values.yaml: appendonly yes

# Step 4: Start Redis
kubectl scale statefulset redis --replicas=1

# Step 5: Monitor AOF loading
kubectl logs -f redis-0
# Look for: "DB loaded from append only file"

# Step 6: Verify data
kubectl exec -it redis-0 -- redis-cli DBSIZE
```

**Recovery time**: 10-30 minutes (AOF replay)

**Data loss**: 1 second (with `appendfsync everysec`)

### 3. Point-in-Time Recovery (AOF)

**Scenario**: Accidental data deletion, need to restore to specific point in time

**Steps**:

```bash
# Step 1: Stop Redis
kubectl scale statefulset redis --replicas=0

# Step 2: Copy AOF file locally
kubectl cp redis-0:/data/appendonly.aof tmp/appendonly-original.aof

# Step 3: Find problematic command in AOF
grep -n "DEL critical-key" tmp/appendonly-original.aof
# Output: 1234567:*2... (command at line 1234567)

# Step 4: Truncate AOF at that point (before bad command)
head -n 1234566 tmp/appendonly-original.aof > tmp/appendonly-recovery.aof

# Step 5: Copy truncated AOF to pod
kubectl cp tmp/appendonly-recovery.aof redis-0:/data/appendonly.aof

# Step 6: Start Redis
kubectl scale statefulset redis --replicas=1

# Step 7: Verify data restored correctly
kubectl exec -it redis-0 -- redis-cli EXISTS critical-key
```

**Recovery time**: 15-45 minutes

**Data loss**: Only data after the recovery point

### 4. Replica Promotion (Failover)

**Scenario**: Primary failed, promote replica to primary

**Steps**:

```bash
# Step 1: Verify primary is down
kubectl get pods -l app.kubernetes.io/name=redis

# Step 2: Choose replica to promote (check lag)
make -f make/ops/redis.mk redis-replication-lag

# Step 3: Promote replica
make -f make/ops/redis.mk redis-promote-replica POD=redis-1

# Or manually:
kubectl exec -it redis-1 -- redis-cli REPLICAOF NO ONE

# Step 4: Update application connection string
# Point applications to redis-1 instead of redis-0

# Step 5: Reconfigure other replicas
kubectl exec -it redis-2 -- redis-cli REPLICAOF redis-1.redis-headless 6379

# Step 6: Verify new topology
make -f make/ops/redis.mk redis-replication-status
```

**Recovery time**: < 1 minute

**Data loss**: Near-zero (depends on replication lag)

### 5. Configuration Restore

**Scenario**: Lost ConfigMap or Secret

**Steps**:

```bash
# Restore ConfigMap
kubectl apply -f redis-config-20250115.yaml

# Restore Secret
kubectl apply -f redis-secret-20250115.yaml

# Restart Redis to apply new configuration
kubectl rollout restart statefulset/redis
kubectl rollout status statefulset/redis
```

**Recovery time**: 5-10 minutes

---

## Disaster Recovery

### Complete Cluster Loss

**Scenario**: Entire Kubernetes cluster lost

**Recovery procedure**:

#### 1. Rebuild Kubernetes cluster

```bash
# (Cluster-specific steps - out of scope)
```

#### 2. Restore Redis configuration

```bash
# Restore from Git or backup location
kubectl apply -f redis-config-20250115.yaml
kubectl apply -f redis-secret-20250115.yaml
```

#### 3. Deploy Redis chart

```bash
helm install redis sb-charts/redis \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  -f values.yaml
```

#### 4. Wait for Redis pod ready

```bash
kubectl wait --for=condition=ready pod/redis-0 --timeout=300s
```

#### 5. Restore data

**Option A: From RDB backup**:
```bash
kubectl scale statefulset redis --replicas=0
kubectl cp tmp/redis-backups/dump-latest.rdb redis-0:/data/dump.rdb
kubectl scale statefulset redis --replicas=1
```

**Option B: From AOF backup**:
```bash
kubectl scale statefulset redis --replicas=0
kubectl cp tmp/redis-backups/appendonly-latest.aof redis-0:/data/appendonly.aof
kubectl scale statefulset redis --replicas=1
```

#### 6. Verify data integrity

```bash
kubectl exec -it redis-0 -- redis-cli DBSIZE
kubectl exec -it redis-0 -- redis-cli INFO stats
kubectl exec -it redis-0 -- redis-cli KEYS '*' | head -20
```

#### 7. Rebuild replication (if applicable)

```bash
helm upgrade redis sb-charts/redis --set replication.replicas=2
```

**Total recovery time**: 1-3 hours

---

## Best Practices

### Backup Best Practices

1. **3-2-1 Rule**:
   - 3 copies of data (primary + 2 backups)
   - 2 different storage types (RDB + AOF or RDB + replica)
   - 1 offsite copy (S3/GCS/Azure)

2. **Use both RDB and AOF**:
   - RDB for fast, periodic backups
   - AOF for durability between RDB snapshots

3. **Enable replication**:
   - At least 1 replica for production
   - Enables fast failover and read scaling

4. **Automate backups**:
   - Daily RDB snapshots (CronJob)
   - Continuous AOF (built-in)
   - Weekly PVC snapshots

5. **Test restores regularly**:
   - Monthly: RDB restore test
   - Quarterly: Full disaster recovery drill
   - Document recovery procedures

6. **Monitor backup status**:
   - Last successful BGSAVE time
   - AOF rewrite status
   - Replication lag
   - Backup storage capacity

### Performance Optimization

1. **RDB optimization**:
   - Use `BGSAVE` instead of `SAVE` (non-blocking)
   - Ensure sufficient memory for fork() (2x dataset size temporarily)
   - Schedule backups during low-traffic periods

2. **AOF optimization**:
   - Use `appendfsync everysec` (balanced)
   - Enable AOF rewrite: `auto-aof-rewrite-percentage 100`
   - Monitor AOF size and rewrite frequency

3. **Replication optimization**:
   - Use replica-read-only for read scaling
   - Monitor replication lag
   - Configure `repl-backlog-size` appropriately

### Retention Strategy

| Backup Type | Frequency | Retention | Storage Location |
|-------------|-----------|-----------|------------------|
| **RDB snapshots** | Daily | 30 days | S3 (Standard) |
| **AOF** | Continuous | Until rewrite | Local PVC |
| **Configuration** | Daily | 90 days | Git + S3 |
| **PVC snapshot** | Weekly | 4 weeks | CSI Snapshots |

---

## Troubleshooting

### Common Issues

#### 1. BGSAVE fails: "Cannot allocate memory"

**Cause**: Insufficient memory for fork()

**Solution**:
```bash
# Check memory usage
kubectl top pod redis-0

# Increase memory limits
kubectl patch statefulset redis -p '{"spec":{"template":{"spec":{"containers":[{"name":"redis","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# Or enable transparent huge pages (host-level)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

#### 2. AOF rewrite fails: "Background AOF rewrite terminated by signal"

**Cause**: Disk full or insufficient disk I/O

**Solution**:
```bash
# Check disk usage
kubectl exec -it redis-0 -- df -h /data

# Increase PVC size
kubectl patch pvc data-redis-0 -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

#### 3. Replication broken: "Master link status: down"

**Cause**: Network connectivity or primary crash

**Solution**:
```bash
# Check replica status
kubectl exec -it redis-1 -- redis-cli INFO replication

# Reconnect to primary
kubectl exec -it redis-1 -- redis-cli REPLICAOF redis-0.redis-headless 6379

# Verify connection
kubectl exec -it redis-1 -- redis-cli INFO replication | grep master_link_status
```

#### 4. Cannot restore: "Short read or OOM loading DB"

**Cause**: Corrupted RDB file or insufficient memory

**Solution**:
```bash
# Verify RDB file
redis-check-rdb tmp/redis-backups/dump.rdb

# If corrupted, try AOF restore instead
# Or restore from older RDB backup
```

#### 5. AOF file corrupted

**Cause**: Partial write or disk failure

**Solution**:
```bash
# Check AOF file
redis-check-aof tmp/redis-backups/appendonly.aof

# Fix AOF file (truncates at first error)
redis-check-aof --fix tmp/redis-backups/appendonly.aof

# Restore fixed AOF
kubectl cp tmp/redis-backups/appendonly.aof redis-0:/data/appendonly.aof
```

---

## Appendix

### Backup Checklist

**Daily tasks**:
- [ ] Verify automated RDB backups completed
- [ ] Check AOF file size (shouldn't grow unbounded)
- [ ] Monitor replication lag (should be < 1 second)

**Weekly tasks**:
- [ ] Test RDB restore
- [ ] Verify AOF integrity
- [ ] Create PVC snapshot
- [ ] Review backup retention

**Monthly tasks**:
- [ ] Full disaster recovery drill
- [ ] Update backup retention policy
- [ ] Verify offsite backups accessible

### Reference Commands

```bash
# Backup commands
make -f make/ops/redis.mk redis-backup-rdb
make -f make/ops/redis.mk redis-backup-aof
make -f make/ops/redis.mk redis-backup-config
make -f make/ops/redis.mk redis-backup-all

# Restore commands
make -f make/ops/redis.mk redis-restore-rdb FILE=dump.rdb
make -f make/ops/redis.mk redis-restore-aof FILE=appendonly.aof

# Replication commands
make -f make/ops/redis.mk redis-replication-status
make -f make/ops/redis.mk redis-promote-replica POD=redis-1

# Verification commands
make -f make/ops/redis.mk redis-backup-verify FILE=dump.rdb
redis-check-rdb dump.rdb
redis-check-aof appendonly.aof
```

### External Resources

- [Redis Persistence Documentation](https://redis.io/docs/manual/persistence/)
- [Redis Replication Documentation](https://redis.io/docs/manual/replication/)
- [Redis Admin Guide](https://redis.io/docs/manual/admin/)
- [Kubernetes VolumeSnapshot Documentation](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

---

**Document version**: 1.0
**Last updated**: 2025-01-15
**Author**: ScriptonBasestar Helm Charts Team
