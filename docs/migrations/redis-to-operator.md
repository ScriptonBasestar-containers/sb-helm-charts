# Redis Operator Migration Guide

Guide for migrating from the simple Redis Helm chart to production-ready Redis operators with high availability and advanced features.

## Overview

This guide helps you migrate from the basic Redis chart in this repository to a production-ready Redis operator with high availability, automated failover, and clustering support.

**Why migrate to an operator?**
- ✅ Automated high availability (HA) with Sentinel or Cluster mode
- ✅ Automatic failover and recovery
- ✅ Redis Cluster support for horizontal scaling
- ✅ Automated backups (RDB/AOF)
- ✅ Monitoring and metrics
- ✅ Automated configuration management
- ✅ Production-grade reliability

## Table of Contents

- [Operator Comparison](#operator-comparison)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Backup Procedures](#backup-procedures)
- [Migration Process](#migration-process)
- [Verification](#verification)
- [Rollback Plan](#rollback-plan)
- [Post-Migration Tasks](#post-migration-tasks)

## Operator Comparison

### Redis Operator by Spotahome (Recommended)

**Project:** https://github.com/spotahome/redis-operator

**Pros:**
- ✅ Battle-tested and mature
- ✅ Redis Sentinel support (automatic failover)
- ✅ Simple CRD-based configuration
- ✅ Good monitoring integration
- ✅ Active community support
- ✅ Easy to understand and operate

**Cons:**
- ❌ No native Redis Cluster support (Sentinel only)
- ❌ Limited advanced features

**Use Case:** High availability with master-slave replication, automatic failover

### Redis Cluster Operator by OT-Container-Kit

**Project:** https://github.com/OT-CONTAINER-KIT/redis-operator

**Pros:**
- ✅ Supports both Sentinel and Cluster modes
- ✅ Redis Cluster support (horizontal scaling)
- ✅ Modern Kubernetes-native design
- ✅ Comprehensive monitoring (Prometheus)
- ✅ Backup/restore support
- ✅ TLS support

**Cons:**
- ❌ Newer project (less battle-tested)
- ❌ More complex setup for simple use cases

**Use Case:** Enterprises needing Redis Cluster, horizontal scaling, or advanced features

### Redis Enterprise Operator

**Project:** https://github.com/RedisLabs/redis-enterprise-k8s-docs

**Pros:**
- ✅ Commercial support available
- ✅ Redis Enterprise features
- ✅ Multi-tenancy support
- ✅ Active-active geo-distribution
- ✅ Advanced security features

**Cons:**
- ❌ Requires Redis Enterprise license
- ❌ Enterprise-focused (overkill for simple deployments)
- ❌ Heavier resource usage

**Use Case:** Enterprises requiring commercial support and advanced features

**Our Recommendation:**
- **Spotahome Redis Operator**: Most users (simple HA with Sentinel)
- **OT-Container-Kit**: Users needing Redis Cluster or horizontal scaling

## Pre-Migration Checklist

### 1. Assess Current Deployment

```bash
# Check Redis version
kubectl exec -it <redis-pod> -- redis-cli INFO SERVER | grep redis_version

# Check memory usage
kubectl exec -it <redis-pod> -- redis-cli INFO MEMORY | grep used_memory_human

# Check number of keys
kubectl exec -it <redis-pod> -- redis-cli DBSIZE

# Check persistence mode
kubectl exec -it <redis-pod> -- redis-cli CONFIG GET save
kubectl exec -it <redis-pod> -- redis-cli CONFIG GET appendonly
```

### 2. Document Current Configuration

```bash
# Export current values
helm get values <release-name> -n <namespace> > current-redis-values.yaml

# Get all Redis configuration
kubectl exec -it <redis-pod> -- redis-cli CONFIG GET '*' > redis-config.txt

# Note connection strings used by applications
kubectl get cm,secret -n <namespace> | grep -i redis
```

### 3. Plan Downtime Window

**Estimated downtime:**
- Small datasets (< 1GB): 5-15 minutes
- Medium datasets (1-10GB): 15-45 minutes
- Large datasets (> 10GB): 45-120 minutes

**Factors affecting downtime:**
- Dataset size
- Network speed
- Replication/sync time
- Number of databases (DB 0-15)

## Backup Procedures

### Method 1: RDB Snapshot (Recommended)

**Advantages:** Fast, point-in-time backup
**Disadvantages:** May lose recent writes (since last save)

```bash
# Trigger manual save
kubectl exec -it <redis-pod> -- redis-cli BGSAVE

# Wait for save to complete
kubectl exec -it <redis-pod> -- redis-cli LASTSAVE

# Copy RDB file from pod
kubectl exec -it <redis-pod> -- cat /data/dump.rdb > redis-backup.rdb

# Or use kubectl cp
kubectl cp <namespace>/<redis-pod>:/data/dump.rdb ./redis-backup.rdb

# Verify backup
file redis-backup.rdb  # Should show "Redis RDB file"
```

### Method 2: AOF (Append Only File)

**Advantages:** More durable, less data loss
**Disadvantages:** Larger file size, slower

```bash
# Enable AOF if not already enabled
kubectl exec -it <redis-pod> -- redis-cli CONFIG SET appendonly yes

# Wait for rewrite
kubectl exec -it <redis-pod> -- redis-cli BGREWRITEAOF

# Copy AOF file
kubectl cp <namespace>/<redis-pod>:/data/appendonly.aof ./redis-backup.aof
```

### Method 3: DUMP All Keys (For Small Datasets)

```bash
# Export all keys and values
kubectl exec -it <redis-pod> -- redis-cli --rdb redis-dump.rdb

# Or use redis-dump tool
kubectl exec -it <redis-pod> -- sh -c "
  redis-cli --scan | while read key; do
    echo \"SET \\\"$key\\\" $(redis-cli --raw DUMP \"$key\" | base64)\" >> /tmp/redis-commands.txt
  done
"

kubectl cp <namespace>/<redis-pod>:/tmp/redis-commands.txt ./redis-commands.txt
```

### Method 4: PVC Snapshot (Cloud Native)

```bash
# Create VolumeSnapshot (if storage class supports it)
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: redis-snapshot
  namespace: <namespace>
spec:
  volumeSnapshotClassName: <snapshot-class>
  source:
    persistentVolumeClaimName: <redis-pvc-name>
EOF

# Verify snapshot
kubectl get volumesnapshot redis-snapshot -n <namespace>
```

## Migration Process

### Option A: Spotahome Redis Operator Migration (Recommended for HA)

**Step 1: Install Spotahome Redis Operator**

```bash
# Install operator using Helm
helm repo add redis-operator https://spotahome.github.io/redis-operator
helm repo update

helm install redis-operator redis-operator/redis-operator \
  -n redis-operator \
  --create-namespace
```

**Step 2: Create Redis Failover Cluster**

```yaml
# redis-failover.yaml
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: redis-cluster
  namespace: default
spec:
  sentinel:
    replicas: 3  # Sentinel quorum
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  redis:
    replicas: 3  # 1 master + 2 slaves
    image: redis:7.2-alpine
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
    storage:
      persistentVolumeClaim:
        metadata:
          name: redis-data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
    exporter:
      enabled: true  # Prometheus metrics
      image: oliver006/redis_exporter:v1.45.0
    customConfig:
      - "maxmemory 1gb"
      - "maxmemory-policy allkeys-lru"
      - "save 900 1"
      - "save 300 10"
      - "save 60 10000"
```

```bash
kubectl apply -f redis-failover.yaml
```

**Step 3: Wait for Cluster Ready**

```bash
# Watch Redis Failover status
kubectl get redisfailover redis-cluster -n default -w

# Check pods
kubectl get pods -n default -l redisfailovers.databases.spotahome.com/name=redis-cluster

# Check Sentinel status
kubectl exec -it rfr-redis-cluster-0 -n default -- redis-cli -p 26379 SENTINEL master redis-cluster
```

**Step 4: Restore Data**

```bash
# Copy backup to Redis pod
kubectl cp redis-backup.rdb default/rfr-redis-cluster-0:/data/dump.rdb

# Restart Redis to load backup
kubectl delete pod rfr-redis-cluster-0 -n default

# Wait for pod to come back
kubectl wait --for=condition=ready pod/rfr-redis-cluster-0 -n default

# Verify data
kubectl exec -it rfr-redis-cluster-0 -n default -- redis-cli DBSIZE
```

**Step 5: Update Application Connection Strings**

```yaml
# Old connection (simple chart)
redis-master.default.svc.cluster.local:6379

# New connection (Redis Operator with Sentinel)
# Use Sentinel service for automatic failover
rfs-redis-cluster.default.svc.cluster.local:26379  # Sentinel service

# Or connect directly to Redis (will be redirected by Sentinel)
rfr-redis-cluster.default.svc.cluster.local:6379

# Application configuration example (Go)
sentinelAddrs := []string{
    "rfs-redis-cluster.default.svc.cluster.local:26379",
}
client := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:    "redis-cluster",
    SentinelAddrs: sentinelAddrs,
})
```

### Option B: OT-Container-Kit Redis Operator (For Redis Cluster)

**Step 1: Install OT-Container-Kit Redis Operator**

```bash
# Install operator
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update

helm install redis-operator ot-helm/redis-operator \
  -n redis-operator \
  --create-namespace
```

**Step 2: Create Redis Cluster**

```yaml
# redis-cluster.yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: RedisCluster
metadata:
  name: redis-cluster
  namespace: default
spec:
  clusterSize: 3  # 3 master nodes
  clusterVersion: v7
  redisExporter:
    enabled: true
    image: quay.io/opstree/redis-exporter:v1.44.0
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi
```

```bash
kubectl apply -f redis-cluster.yaml
```

**Step 3: Create Redis Sentinel (For HA Master-Slave)**

```yaml
# redis-sentinel.yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: Redis
metadata:
  name: redis-sentinel
  namespace: default
spec:
  kubernetesConfig:
    image: quay.io/opstree/redis:v7.0.5
    imagePullPolicy: IfNotPresent
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
  redisExporter:
    enabled: true
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi
  redisConfig:
    additionalRedisConfig: |
      maxmemory 1gb
      maxmemory-policy allkeys-lru
```

```bash
kubectl apply -f redis-sentinel.yaml
```

**Step 4: Restore Data** (similar process as Option A)

### Data Migration Strategies

**Strategy 1: MIGRATE Command (Zero Downtime)**

For online migration with minimal downtime:

```bash
# Use redis-cli with --cluster-migrate
kubectl exec -it <new-redis-pod> -- redis-cli \
  --cluster import \
  <old-redis-host>:6379 \
  --cluster-from <old-redis-host>:6379 \
  --cluster-replace
```

**Strategy 2: Replication-Based Migration**

Configure old Redis as temporary slave:

```bash
# On new Redis, configure as slave of old Redis temporarily
kubectl exec -it <new-redis-pod> -- redis-cli \
  REPLICAOF <old-redis-host> 6379

# Wait for full sync
kubectl exec -it <new-redis-pod> -- redis-cli INFO replication

# Once synced, promote to master
kubectl exec -it <new-redis-pod> -- redis-cli REPLICAOF NO ONE
```

## Verification

### Connection Test

```bash
# Test Sentinel connection
kubectl run -it --rm redis-test --image=redis:7.2-alpine --restart=Never -- \
  redis-cli -h rfs-redis-cluster.default.svc.cluster.local -p 26379 SENTINEL masters

# Test Redis connection
kubectl run -it --rm redis-test --image=redis:7.2-alpine --restart=Never -- \
  redis-cli -h rfr-redis-cluster.default.svc.cluster.local PING

# Test write
kubectl run -it --rm redis-test --image=redis:7.2-alpine --restart=Never -- \
  redis-cli -h rfr-redis-cluster.default.svc.cluster.local SET migration-test "success"

# Test read
kubectl run -it --rm redis-test --image=redis:7.2-alpine --restart=Never -- \
  redis-cli -h rfr-redis-cluster.default.svc.cluster.local GET migration-test
```

### Data Validation

```bash
# Compare key count
kubectl exec -it <new-redis-pod> -- redis-cli DBSIZE

# Verify sample keys
kubectl exec -it <new-redis-pod> -- redis-cli --scan --pattern '*' | head -10

# Check memory usage
kubectl exec -it <new-redis-pod> -- redis-cli INFO MEMORY | grep used_memory_human
```

### High Availability Test

```bash
# Delete master pod (should trigger automatic failover)
kubectl delete pod rfr-redis-cluster-0 -n default

# Watch Sentinel promote new master
kubectl exec -it rfs-redis-cluster-0 -n default -- \
  redis-cli -p 26379 SENTINEL get-master-addr-by-name redis-cluster

# Verify application continues working
kubectl exec -it <app-pod> -- curl http://localhost:8080/health
```

## Rollback Plan

### If Migration Fails

**Step 1: Reinstall Old Chart**

```bash
# Reinstall from backup values
helm install <redis-release> sb-charts/redis \
  -n <namespace> \
  -f current-redis-values.yaml
```

**Step 2: Restore Data**

```bash
# Wait for pod ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n <namespace>

# Copy backup to pod
kubectl cp redis-backup.rdb <namespace>/<redis-pod>:/data/dump.rdb

# Restart Redis
kubectl delete pod <redis-pod> -n <namespace>

# Verify data
kubectl exec -it <redis-pod> -n <namespace> -- redis-cli DBSIZE
```

**Step 3: Update Applications**

```bash
# Update connection strings back to old service
kubectl set env deployment/<app> \
  REDIS_HOST=redis-master.default.svc.cluster.local
```

## Post-Migration Tasks

### 1. Configure Monitoring

**Prometheus ServiceMonitor:**

```yaml
# Already enabled in operator spec
redisExporter:
  enabled: true
```

**Import Grafana Dashboard:**
- Redis Dashboard: https://grafana.com/grafana/dashboards/11835

### 2. Set Up Alerts

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: redis-alerts
  namespace: default
spec:
  groups:
    - name: redis
      interval: 30s
      rules:
        - alert: RedisDown
          expr: redis_up == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Redis instance is down"

        - alert: RedisHighMemory
          expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Redis memory usage > 90%"
```

### 3. Configure Backups

**Spotahome Operator:**

```bash
# Configure automated backups using CronJob
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: redis-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: redis:7.2-alpine
            command:
            - sh
            - -c
            - |
              redis-cli -h rfr-redis-cluster BGSAVE
              sleep 60
              redis-cli -h rfr-redis-cluster --rdb /backup/dump-\$(date +%Y%m%d).rdb
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: redis-backups
          restartPolicy: OnFailure
EOF
```

### 4. Update Documentation

- Document new connection strings
- Update runbooks with operator-specific commands
- Train team on Sentinel/Cluster operations

### 5. Test Disaster Recovery

```bash
# Simulate total failure
kubectl delete redisfailover redis-cluster -n default

# Restore from backup
kubectl apply -f redis-failover.yaml
# Then restore data as in migration steps
```

## Troubleshooting

### Issue: Sentinel not promoting new master

```bash
# Check Sentinel configuration
kubectl exec -it rfs-redis-cluster-0 -n default -- \
  redis-cli -p 26379 SENTINEL master redis-cluster

# Force failover
kubectl exec -it rfs-redis-cluster-0 -n default -- \
  redis-cli -p 26379 SENTINEL failover redis-cluster

# Check logs
kubectl logs -n default rfs-redis-cluster-0
```

### Issue: Data not replicating

```bash
# Check replication status
kubectl exec -it rfr-redis-cluster-0 -n default -- \
  redis-cli INFO replication

# Check network connectivity
kubectl exec -it rfr-redis-cluster-1 -n default -- \
  redis-cli -h rfr-redis-cluster-0.default.svc.cluster.local PING

# Check replication lag
kubectl exec -it rfr-redis-cluster-0 -n default -- \
  redis-cli INFO replication | grep lag
```

### Issue: Application connection failures

```bash
# Test from application namespace
kubectl run -it --rm debug --image=redis:7.2-alpine --restart=Never -- \
  redis-cli -h rfs-redis-cluster.default.svc.cluster.local -p 26379 SENTINEL masters

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup rfs-redis-cluster.default.svc.cluster.local

# Verify service endpoints
kubectl get endpoints -n default | grep redis
```

## Additional Resources

- [Spotahome Redis Operator Documentation](https://github.com/spotahome/redis-operator/tree/master/docs)
- [OT-Container-Kit Redis Operator](https://ot-redis-operator.netlify.app/)
- [Redis Sentinel Documentation](https://redis.io/docs/manual/sentinel/)
- [Redis Cluster Tutorial](https://redis.io/docs/manual/scaling/)
- [Chart Catalog](../CHARTS.md) - Browse all available charts

---

**Need help?** Open an issue at https://github.com/scriptonbasestar-container/sb-helm-charts/issues

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
