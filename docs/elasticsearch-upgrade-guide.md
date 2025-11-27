# Elasticsearch Upgrade Guide

This guide provides comprehensive upgrade procedures for Elasticsearch deployed via the `sb-helm-charts/elasticsearch` chart.

---

## Table of Contents

1. [Upgrade Strategy Overview](#upgrade-strategy-overview)
2. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
3. [Upgrade Methods](#upgrade-methods)
4. [Version-Specific Upgrade Notes](#version-specific-upgrade-notes)
5. [Post-Upgrade Validation](#post-upgrade-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)

---

## Upgrade Strategy Overview

Elasticsearch supports **three upgrade strategies**, each with different trade-offs:

| Strategy | Downtime | Complexity | Use Case |
|----------|----------|-----------|----------|
| **Rolling Upgrade** | None (zero-downtime) | Medium | Minor version upgrades (8.10 → 8.11) |
| **Full Cluster Restart** | 30-60 minutes | Low | Major version upgrades (7.x → 8.x) |
| **Snapshot & Restore** | 1-2 hours | High | Multi-version jumps (7.10 → 8.11) |

**Choosing the right strategy:**

- **Rolling upgrade**: Recommended for production (zero downtime)
- **Full restart**: Simpler for small clusters or major versions
- **Snapshot restore**: Required for version jumps > 1 major version

---

## Pre-Upgrade Checklist

### 1. Run Pre-Upgrade Health Check

```bash
make -f make/ops/elasticsearch.mk es-pre-upgrade-check
```

**Checks performed:**
- Cluster health (must be GREEN or YELLOW)
- All shards allocated (no UNASSIGNED shards)
- Elasticsearch version
- Available disk space (> 20% free)
- Index template compatibility

**Expected output:**
```
=== Elasticsearch Pre-Upgrade Health Check ===
1. Cluster health: GREEN
2. Shards: 15 active, 0 unassigned
3. Current version: 8.10.4
4. Disk space: 68% available
✓ Cluster ready for upgrade
```

---

### 2. Create Full Backup

**Critical:** Always backup before upgrades.

```bash
# 1. Backup cluster settings
make -f make/ops/elasticsearch.mk es-cluster-settings-backup

# 2. Create snapshot
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=pre_upgrade_$(date +%Y%m%d)

# 3. Verify snapshot
make -f make/ops/elasticsearch.mk es-verify-snapshot SNAPSHOT_NAME=pre_upgrade_$(date +%Y%m%d)

# 4. Optional: Create PVC snapshot (disaster recovery)
make -f make/ops/elasticsearch.mk es-data-backup
```

---

### 3. Review Breaking Changes

**Elasticsearch upgrade documentation:**
- [Elasticsearch 8.x Breaking Changes](https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-8.0.html)
- [Elasticsearch 7.x → 8.x Migration Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/migrating-8.0.html)

**Common breaking changes:**
- Index mapping changes (field types, analyzers)
- REST API deprecations
- Query DSL changes
- Aggregation behavior changes

---

### 4. Test Upgrade in Staging

**Deploy staging cluster:**

```bash
# Deploy Elasticsearch to staging namespace
helm install elasticsearch-staging scripton-charts/elasticsearch \
  -f values.yaml \
  --set image.tag=8.10.4 \
  --namespace staging

# Restore production snapshot to staging
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=production_latest

# Test upgrade in staging
helm upgrade elasticsearch-staging scripton-charts/elasticsearch \
  --set image.tag=8.11.0 \
  --namespace staging

# Run validation tests
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

---

## Upgrade Methods

### Method 1: Rolling Upgrade (Zero Downtime)

**Best for:** Minor version upgrades (8.10 → 8.11), production environments

**Advantages:**
- No downtime
- Gradual rollout (detect issues early)
- Easy rollback (Helm rollback)

**Disadvantages:**
- Slower than full restart
- Requires shard reallocation (network traffic)
- Not supported for major version jumps

**Procedure:**

```bash
# 1. Run pre-upgrade checks
make -f make/ops/elasticsearch.mk es-pre-upgrade-check

# 2. Disable shard allocation (prevent rebalancing during upgrade)
make -f make/ops/elasticsearch.mk es-disable-shard-allocation

# 3. Upgrade StatefulSet with new image
helm upgrade elasticsearch scripton-charts/elasticsearch \
  --set image.tag=8.11.0 \
  --reuse-values

# 4. Monitor pod rollout (one pod at a time)
kubectl rollout status statefulset/elasticsearch --timeout=20m

# 5. Wait for each pod to join cluster
# StatefulSet updates pods in reverse order (elasticsearch-2, elasticsearch-1, elasticsearch-0)
# Wait for each pod to be Ready before next pod updates

# 6. Re-enable shard allocation
make -f make/ops/elasticsearch.mk es-enable-shard-allocation

# 7. Monitor shard reallocation
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/shards?v&h=index,shard,prirep,state,node"

# 8. Run post-upgrade validation
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**How it works:**

1. **Disable shard allocation**: Prevents Elasticsearch from moving shards during upgrade (reduces network traffic)
2. **StatefulSet rolling update**: Kubernetes updates pods one at a time (reverse order)
3. **Node upgrade**: Each pod downloads new image, restarts with new version
4. **Cluster join**: New node joins cluster, syncs with master
5. **Shard recovery**: After all nodes upgraded, re-enable shard allocation
6. **Rebalancing**: Elasticsearch redistributes shards across nodes

**Timeline:**
- Pod update: 2-5 minutes per pod
- Cluster sync: 1-3 minutes per pod
- Shard reallocation: 5-30 minutes (depends on data size)
- **Total:** 30-60 minutes for 3-node cluster

---

### Method 2: Full Cluster Restart

**Best for:** Major version upgrades (7.x → 8.x), small clusters, maintenance windows

**Advantages:**
- Simple procedure (stop all, upgrade, start all)
- Faster than rolling upgrade (no shard reallocation during upgrade)
- Supports major version jumps

**Disadvantages:**
- Downtime (30-60 minutes)
- All-or-nothing (harder to rollback mid-upgrade)

**Procedure:**

```bash
# 1. Run pre-upgrade checks
make -f make/ops/elasticsearch.mk es-pre-upgrade-check

# 2. Create pre-upgrade backup
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=pre_upgrade_full_restart

# 3. Disable shard allocation (prevent rebalancing)
make -f make/ops/elasticsearch.mk es-disable-shard-allocation

# 4. Stop all Elasticsearch pods (scale to 0)
kubectl scale statefulset/elasticsearch --replicas=0

# 5. Wait for all pods to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=elasticsearch --timeout=5m

# 6. Upgrade StatefulSet with new image and configs
helm upgrade elasticsearch scripton-charts/elasticsearch \
  --set image.tag=8.0.0 \
  --set elasticsearch.config.node.name='${HOSTNAME}' \
  --reuse-values

# 7. Scale back to desired replicas
kubectl scale statefulset/elasticsearch --replicas=3

# 8. Wait for cluster to form (all pods join)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elasticsearch --timeout=10m

# 9. Re-enable shard allocation
make -f make/ops/elasticsearch.mk es-enable-shard-allocation

# 10. Monitor shard recovery
watch "kubectl exec -it elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/recovery?v&h=index,shard,type,stage,source_node,target_node,files_percent'"

# 11. Run post-upgrade validation
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**Timeline:**
- Pod termination: 2-5 minutes
- Helm upgrade: 1-2 minutes
- Cluster formation: 3-5 minutes
- Shard recovery: 10-40 minutes (depends on data size)
- **Total:** 30-60 minutes

---

### Method 3: Snapshot & Restore (Blue-Green)

**Best for:** Multi-version jumps (7.10 → 8.11), production with strict SLAs, testing new configs

**Advantages:**
- Safest method (old cluster remains untouched)
- Supports any version jump
- Easy rollback (switch back to old cluster)
- Test new configs before cutover

**Disadvantages:**
- Longest downtime (1-2 hours)
- Requires double resources temporarily
- More complex procedure

**Procedure:**

```bash
# === Phase 1: Prepare Old Cluster ===

# 1. Create final snapshot from old cluster (7.x)
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=migration_to_8x_$(date +%Y%m%d)

# 2. Verify snapshot
make -f make/ops/elasticsearch.mk es-verify-snapshot SNAPSHOT_NAME=migration_to_8x_$(date +%Y%m%d)

# === Phase 2: Deploy New Cluster ===

# 3. Deploy new Elasticsearch cluster (8.x) in separate namespace
helm install elasticsearch-new scripton-charts/elasticsearch \
  -f values-8x.yaml \
  --set image.tag=8.11.0 \
  --namespace elasticsearch-new

# 4. Wait for new cluster to be healthy
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elasticsearch --namespace elasticsearch-new --timeout=10m

# === Phase 3: Restore Data to New Cluster ===

# 5. Register same snapshot repository on new cluster
# (Ensure new cluster has access to same snapshot storage)
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl -X PUT "http://localhost:9200/_snapshot/backup_repo?pretty" \
  -H 'Content-Type: application/json' -d '{
    "type": "fs",
    "settings": {
      "location": "/usr/share/elasticsearch/snapshots"
    }
  }'

# 6. Restore snapshot to new cluster
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl -X POST "http://localhost:9200/_snapshot/backup_repo/migration_to_8x_$(date +%Y%m%d)/_restore?pretty" \
  -H 'Content-Type: application/json' -d '{
    "indices": "*",
    "include_global_state": true
  }'

# 7. Monitor restore progress
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl "http://localhost:9200/_cat/recovery?v"

# === Phase 4: Validate New Cluster ===

# 8. Run validation tests
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl "http://localhost:9200/_cat/indices?v"
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl "http://localhost:9200/_cluster/health?pretty"

# 9. Test application queries (read-only)
# Update application config to point to new cluster endpoint (read-only mode)

# === Phase 5: Cutover ===

# 10. Schedule maintenance window
# 11. Stop writes to old cluster (set application to read-only or maintenance mode)

# 12. Create final incremental snapshot from old cluster
make -f make/ops/elasticsearch.mk es-create-snapshot SNAPSHOT_NAME=final_incremental_$(date +%Y%m%d_%H%M%S)

# 13. Restore final snapshot to new cluster (only changed indices)
kubectl exec -it elasticsearch-new-0 --namespace elasticsearch-new -- curl -X POST "http://localhost:9200/_snapshot/backup_repo/final_incremental_$(date +%Y%m%d_%H%M%S)/_restore?pretty"

# 14. Update application configs to use new cluster (read/write)

# 15. Monitor new cluster for 24-48 hours

# === Phase 6: Decommission Old Cluster ===

# 16. After validation period, uninstall old cluster
helm uninstall elasticsearch --namespace default
```

**Timeline:**
- New cluster deployment: 5-10 minutes
- Snapshot restore: 30-120 minutes (depends on data size)
- Validation: 15-30 minutes
- Cutover: 10-20 minutes
- **Total:** 1-3 hours (excluding monitoring period)

---

## Version-Specific Upgrade Notes

### Elasticsearch 7.x → 8.x (Major Upgrade)

**Critical breaking changes:**

1. **Security enabled by default:**
```yaml
# values.yaml - Configure security settings
elasticsearch:
  password: "changeme"  # REQUIRED in 8.x (was optional in 7.x)
```

2. **Mapping types removed:**
```bash
# 7.x mapping (deprecated)
PUT /my-index/_mapping/_doc { ... }

# 8.x mapping (types removed)
PUT /my-index/_mapping { ... }
```

3. **REST API changes:**
- `_type` field removed from all APIs
- Cluster state API response format changed
- Search API deprecations

**Recommended upgrade path:**

1. **Upgrade to latest 7.x first** (7.17.x):
```bash
helm upgrade elasticsearch scripton-charts/elasticsearch --set image.tag=7.17.15
```

2. **Run deprecation info API:**
```bash
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_migration/deprecations?pretty"
```

3. **Fix all deprecation warnings** before upgrading to 8.x

4. **Use snapshot & restore method** for 7.x → 8.x upgrade

---

### Elasticsearch 8.10 → 8.11 (Minor Upgrade)

**Changes:**

- Performance improvements (shard allocation, search)
- New aggregations and query types
- Bug fixes

**Recommended method:** Rolling upgrade (zero downtime)

**Procedure:**

```bash
helm upgrade elasticsearch scripton-charts/elasticsearch --set image.tag=8.11.0
```

---

### Elasticsearch 8.11 → 8.12 (Minor Upgrade)

**Changes:**

- Security enhancements
- Query DSL improvements
- Vector search optimizations

**Recommended method:** Rolling upgrade

---

## Post-Upgrade Validation

### Run Post-Upgrade Health Check

```bash
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**Checks performed:**

1. **Cluster health:** GREEN or YELLOW
2. **All nodes joined:** Expected node count
3. **Shard allocation:** All shards active
4. **No unassigned shards:** 0 unassigned
5. **Index accessibility:** All indices readable
6. **Elasticsearch version:** Upgraded version confirmed
7. **Plugin compatibility:** All plugins loaded

**Expected output:**
```
=== Elasticsearch Post-Upgrade Validation ===
1. Cluster health: GREEN
2. Nodes joined: 3/3
3. Shards: 15 active, 0 relocating, 0 initializing, 0 unassigned
4. Indices: 5 indices accessible
5. Elasticsearch version: 8.11.0
6. Plugins: [analysis-icu, repository-s3]
✓ Upgrade validation passed
```

---

### Validate Index Accessibility

```bash
# Check all indices
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/indices?v"

# Test search query
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/my-index/_search?pretty" \
  -H 'Content-Type: application/json' -d '{
    "query": { "match_all": {} },
    "size": 10
  }'

# Verify document count
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/my-index/_count?pretty"
```

---

### Monitor Cluster Performance

```bash
# Check shard allocation status
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/allocation?v"

# Monitor JVM heap usage
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/nodes?v&h=name,heap.percent,ram.percent,cpu,load_1m"

# Check for errors in logs
kubectl logs elasticsearch-0 --tail=100 | grep -i error
```

---

## Rollback Procedures

### Helm Rollback (Chart-Only)

**Use case:** Rollback chart configuration changes (NOT Elasticsearch version)

**Limitations:** Cannot rollback Elasticsearch version (data format may be incompatible)

```bash
# List recent releases
helm history elasticsearch

# Rollback to previous release
helm rollback elasticsearch

# Rollback to specific revision
helm rollback elasticsearch 3
```

**⚠️ Warning:** Helm rollback only reverts chart configuration. If Elasticsearch data format changed, rollback will fail.

---

### Snapshot Restore Rollback

**Use case:** Rollback Elasticsearch version and data

**Procedure:**

```bash
# 1. Uninstall current deployment
helm uninstall elasticsearch

# 2. Delete PVCs (removes upgraded data)
kubectl delete pvc -l app.kubernetes.io/name=elasticsearch

# 3. Deploy previous Elasticsearch version
helm install elasticsearch scripton-charts/elasticsearch \
  -f values.yaml \
  --set image.tag=8.10.4

# 4. Register snapshot repository
make -f make/ops/elasticsearch.mk es-create-snapshot-repo

# 5. Restore pre-upgrade snapshot
make -f make/ops/elasticsearch.mk es-restore-snapshot SNAPSHOT_NAME=pre_upgrade_20231127

# 6. Validate cluster
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**Timeline:** 30-90 minutes (depends on data size)

---

### PVC Restore Rollback

**Use case:** Fastest rollback for disaster scenarios

**Procedure:**

```bash
# 1. Uninstall current deployment
helm uninstall elasticsearch

# 2. Restore PVCs from VolumeSnapshot (created before upgrade)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: elasticsearch-data-0
spec:
  dataSource:
    name: es-snapshot-pre-upgrade-20231127
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
EOF

# 3. Deploy previous Elasticsearch version
helm install elasticsearch scripton-charts/elasticsearch \
  -f values.yaml \
  --set image.tag=8.10.4

# 4. Validate cluster
make -f make/ops/elasticsearch.mk es-post-upgrade-check
```

**Timeline:** 15-30 minutes

---

## Troubleshooting

### Upgrade Stuck - Pods CrashLooping

**Symptom:** Pods fail to start after upgrade.

**Common causes:**

1. **Incompatible data format:**
```bash
# Check pod logs
kubectl logs elasticsearch-0 | grep -i "incompatible"

# Solution: Rollback to previous version
helm rollback elasticsearch
```

2. **Insufficient resources (JVM heap):**
```bash
# Check OOMKilled events
kubectl describe pod elasticsearch-0 | grep -i oom

# Solution: Increase memory limits
helm upgrade elasticsearch scripton-charts/elasticsearch \
  --set resources.limits.memory=4Gi \
  --set elasticsearch.javaOpts="-Xms2g -Xmx2g"
```

3. **Configuration errors:**
```bash
# Check Elasticsearch logs
kubectl logs elasticsearch-0 --tail=50

# Solution: Fix configuration via values.yaml
```

---

### Shards Not Reallocating After Upgrade

**Symptom:** Shards stuck in `UNASSIGNED` state.

**Diagnosis:**

```bash
# Check shard allocation status
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason"

# Check cluster allocation explain
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cluster/allocation/explain?pretty"
```

**Solutions:**

1. **Re-enable shard allocation (if disabled):**
```bash
make -f make/ops/elasticsearch.mk es-enable-shard-allocation
```

2. **Retry failed shards:**
```bash
kubectl exec -it elasticsearch-0 -- curl -X POST "http://localhost:9200/_cluster/reroute?retry_failed=true&pretty"
```

3. **Adjust shard allocation settings:**
```bash
kubectl exec -it elasticsearch-0 -- curl -X PUT "http://localhost:9200/_cluster/settings?pretty" \
  -H 'Content-Type: application/json' -d '{
    "transient": {
      "cluster.routing.allocation.disk.watermark.low": "90%",
      "cluster.routing.allocation.disk.watermark.high": "95%"
    }
  }'
```

---

### Cluster Split-Brain After Upgrade

**Symptom:** Multiple clusters formed (split-brain scenario).

**Diagnosis:**

```bash
# Check cluster state on each node
for pod in elasticsearch-0 elasticsearch-1 elasticsearch-2; do
  echo "=== $pod ==="
  kubectl exec -it $pod -- curl "http://localhost:9200/_cat/nodes?v"
done
```

**Solution:**

```bash
# 1. Stop all Elasticsearch pods
kubectl scale statefulset/elasticsearch --replicas=0

# 2. Wait for termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=elasticsearch --timeout=5m

# 3. Ensure cluster.initial_master_nodes is set correctly
helm upgrade elasticsearch scripton-charts/elasticsearch \
  --set elasticsearch.config.cluster.initial_master_nodes='["elasticsearch-0","elasticsearch-1","elasticsearch-2"]'

# 4. Start cluster
kubectl scale statefulset/elasticsearch --replicas=3

# 5. Verify single cluster formed
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/nodes?v"
```

---

### Slow Shard Recovery After Upgrade

**Symptom:** Shard recovery taking hours.

**Diagnosis:**

```bash
# Monitor recovery progress
kubectl exec -it elasticsearch-0 -- curl "http://localhost:9200/_cat/recovery?v&h=index,shard,time,type,stage,source_node,target_node,files_percent"
```

**Solutions:**

1. **Increase recovery rate limits:**
```bash
kubectl exec -it elasticsearch-0 -- curl -X PUT "http://localhost:9200/_cluster/settings?pretty" \
  -H 'Content-Type: application/json' -d '{
    "transient": {
      "indices.recovery.max_bytes_per_sec": "500mb"
    }
  }'
```

2. **Increase concurrent recoveries:**
```bash
kubectl exec -it elasticsearch-0 -- curl -X PUT "http://localhost:9200/_cluster/settings?pretty" \
  -H 'Content-Type: application/json' -d '{
    "transient": {
      "cluster.routing.allocation.node_concurrent_recoveries": 4
    }
  }'
```

---

**Last Updated:** 2025-11-27
**Chart Version:** v0.3.0
**Elasticsearch Version:** 8.11.x
