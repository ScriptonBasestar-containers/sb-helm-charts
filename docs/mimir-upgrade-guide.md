# Grafana Mimir Upgrade Guide

This guide provides comprehensive upgrade procedures for Grafana Mimir deployed via the `sb-helm-charts/mimir` chart.

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

Grafana Mimir supports **three upgrade strategies**, each with different trade-offs:

| Strategy | Downtime | Complexity | Use Case |
|----------|----------|-----------|----------|
| **Rolling Upgrade** | None (zero-downtime) | Medium | Minor version upgrades (2.14 → 2.15) |
| **Blue-Green Deployment** | 10-30 minutes | High | Major version upgrades (2.x → 3.x) |
| **Maintenance Window** | 30-60 minutes | Low | Small deployments or testing environments |

**Choosing the right strategy:**

- **Rolling upgrade**: Recommended for production monolithic deployments
- **Blue-Green**: Best for major version migrations with rollback capability
- **Maintenance window**: Simplest for dev/test or small production deployments

**Version upgrade paths:**
- **Patch upgrades** (2.15.0 → 2.15.1): Rolling upgrade
- **Minor upgrades** (2.14.x → 2.15.x): Rolling upgrade (test first)
- **Major upgrades** (2.x → 3.x): Blue-green deployment recommended

---

## Pre-Upgrade Checklist

### 1. Run Pre-Upgrade Health Check

```bash
make -f make/ops/mimir.mk mimir-pre-upgrade-check
```

**Checks performed:**
- Mimir health status (all components ready)
- Ring consistency (ingester, compactor, store-gateway rings)
- Query performance baseline
- Storage backend connectivity (S3/filesystem)
- Available disk space (> 20% free for filesystem mode)
- Current Mimir version

**Expected output:**
```
=== Mimir Pre-Upgrade Health Check ===
1. Health status: healthy
2. Ingester ring: 1/1 instances ACTIVE
3. Compactor ring: 1/1 instances ACTIVE
4. Store-gateway ring: 1/1 instances ACTIVE
5. Current version: 2.14.1
6. Storage backend: S3 (s3://mimir-blocks)
7. Disk space: 75% available
✓ Mimir ready for upgrade
```

---

### 2. Review Breaking Changes

**Always check Mimir release notes for breaking changes:**

```bash
# Check current version
kubectl exec mimir-0 -- /bin/mimir --version

# Review release notes
# https://github.com/grafana/mimir/releases/tag/mimir-2.15.0
```

**Common breaking changes:**
- Configuration schema changes (mimir.yaml)
- Flag renames or deprecations
- Block format changes (rare, but critical)
- API endpoint changes
- Ring protocol changes (affects clustering)

---

### 3. Create Full Backup

**Critical:** Always backup before upgrades.

```bash
# 1. Backup all components
make -f make/ops/mimir.mk mimir-backup-all

# 2. Verify backup integrity
make -f make/ops/mimir.mk mimir-backup-verify DIR=./tmp/mimir-backups/pre-upgrade-$(date +%Y%m%d)

# 3. Optional: Create PVC snapshot (disaster recovery)
make -f make/ops/mimir.mk mimir-create-pvc-snapshot SNAPSHOT_NAME=pre-upgrade-$(date +%Y%m%d)

# 4. Tag current S3 bucket state (if using S3 backend)
aws s3api put-object-tagging \
  --bucket mimir-blocks \
  --tagging 'TagSet=[{Key=pre-upgrade,Value='$(date +%Y%m%d)'}]'
```

**Backup verification:**
```bash
# Verify all backup components exist
ls -lh ./tmp/mimir-backups/pre-upgrade-$(date +%Y%m%d)/
# Expected:
# - mimir-config.yaml
# - blocks-backup.tar.gz (if filesystem mode)
# - backup-manifest.json
```

---

### 4. Review Current Configuration

```bash
# Export current configuration
kubectl get configmap mimir-config -o yaml > mimir-config-current.yaml

# Compare with new version's configuration schema
# Check for deprecated settings
kubectl exec mimir-0 -- /bin/mimir -config.file=/etc/mimir/mimir.yaml -validate-config
```

---

### 5. Test in Non-Production First

**Always test upgrades in staging environment:**

```bash
# 1. Clone production configuration to staging
kubectl get configmap mimir-config -o yaml | \
  sed 's/namespace: production/namespace: staging/' | \
  kubectl apply -n staging -f -

# 2. Upgrade staging
helm upgrade mimir sb-charts/mimir \
  -n staging \
  --set image.tag=2.15.0

# 3. Run validation tests
make -f make/ops/mimir.mk mimir-post-upgrade-check NAMESPACE=staging

# 4. Monitor for 24-48 hours before production upgrade
```

---

## Upgrade Methods

### Method 1: Rolling Upgrade (Zero Downtime)

**Best for:** Minor version upgrades in monolithic mode
**Downtime:** None
**Complexity:** Medium

**Procedure:**

```bash
# Step 1: Pre-upgrade backup
make -f make/ops/mimir.mk mimir-backup-all

# Step 2: Pre-upgrade health check
make -f make/ops/mimir.mk mimir-pre-upgrade-check

# Step 3: Update chart values with new version
helm upgrade mimir sb-charts/mimir \
  -f values-production.yaml \
  --set image.tag=2.15.0 \
  --set podDisruptionBudget.enabled=true

# Step 4: Monitor rollout
kubectl rollout status statefulset mimir

# Step 5: Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mimir --timeout=300s

# Step 6: Verify rings are healthy
make -f make/ops/mimir.mk mimir-ring-status

# Step 7: Run post-upgrade validation
make -f make/ops/mimir.mk mimir-post-upgrade-check

# Step 8: Test query functionality
make -f make/ops/mimir.mk mimir-query-test
```

**Rolling upgrade workflow:**

1. StatefulSet controller updates pods one-by-one (starting from highest ordinal)
2. Each pod:
   - Stops gracefully (allows in-flight queries to complete)
   - Starts with new version
   - Rejoins rings (ingester, compactor, store-gateway)
   - Waits for readiness probe
3. Next pod upgrades only after previous pod is healthy
4. Total time: ~5-10 minutes per pod

**Monitoring during upgrade:**

```bash
# Watch pod status
watch kubectl get pods -l app.kubernetes.io/name=mimir

# Monitor Mimir logs
kubectl logs -f mimir-0 --tail=100

# Check ring membership
make -f make/ops/mimir.mk mimir-ring-status

# Monitor query latency
make -f make/ops/mimir.mk mimir-metrics-query QUERY='histogram_quantile(0.99, rate(cortex_request_duration_seconds_bucket[5m]))'
```

---

### Method 2: Blue-Green Deployment (Safe Major Upgrades)

**Best for:** Major version upgrades, high-risk changes
**Downtime:** 10-30 minutes (during cutover)
**Complexity:** High

**Procedure:**

```bash
# Step 1: Backup current deployment
make -f make/ops/mimir.mk mimir-backup-all

# Step 2: Deploy new version alongside current (blue-green)
helm install mimir-green sb-charts/mimir \
  -f values-production.yaml \
  --set image.tag=2.15.0 \
  --set nameOverride=mimir-green \
  --set service.port=9000  # Different port to avoid conflict

# Step 3: Configure new deployment to read from same storage
# Use same S3 bucket or PVC (read-only initially)
kubectl patch statefulset mimir-green --type merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"mimir","env":[{"name":"READ_ONLY","value":"true"}]}]}}}}'

# Step 4: Wait for new deployment to warm up
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mimir-green --timeout=600s

# Step 5: Validate new deployment
make -f make/ops/mimir.mk mimir-query-test RELEASE=mimir-green

# Step 6: Cutover: Update ingress/load balancer to point to new deployment
kubectl patch ingress mimir-ingress --type merge \
  -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"mimir-green"}}}]}}]}}'

# Step 7: Monitor new deployment (15-30 minutes)
make -f make/ops/mimir.mk mimir-post-upgrade-check RELEASE=mimir-green

# Step 8: If successful, remove old deployment
helm uninstall mimir

# Step 9: Rename green to primary
helm upgrade mimir-green sb-charts/mimir --set nameOverride=mimir
```

**Rollback (if issues detected):**
```bash
# Revert ingress to old deployment
kubectl patch ingress mimir-ingress --type merge \
  -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"mimir"}}}]}}]}}'

# Remove failed green deployment
helm uninstall mimir-green
```

---

### Method 3: Maintenance Window Upgrade (Simplest)

**Best for:** Dev/test environments, small deployments
**Downtime:** 30-60 minutes
**Complexity:** Low

**Procedure:**

```bash
# Step 1: Announce maintenance window
echo "Mimir upgrade maintenance: $(date) - $(date -d '+1 hour')"

# Step 2: Stop all write traffic (optional)
kubectl scale deployment <prometheus> --replicas=0  # Stop Prometheus remote-write

# Step 3: Backup
make -f make/ops/mimir.mk mimir-backup-all

# Step 4: Scale down Mimir
kubectl scale statefulset mimir --replicas=0

# Step 5: Wait for pods to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=mimir --timeout=300s

# Step 6: Upgrade chart
helm upgrade mimir sb-charts/mimir \
  -f values-production.yaml \
  --set image.tag=2.15.0

# Step 7: Scale up Mimir
kubectl scale statefulset mimir --replicas=1

# Step 8: Wait for readiness
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mimir --timeout=600s

# Step 9: Validate
make -f make/ops/mimir.mk mimir-post-upgrade-check

# Step 10: Resume write traffic
kubectl scale deployment <prometheus> --replicas=1
```

---

## Version-Specific Upgrade Notes

### Upgrading from 2.14.x to 2.15.x

**Release date:** December 2024
**Type:** Minor version (rolling upgrade supported)

**Breaking changes:**
- None reported for 2.14 → 2.15 upgrade

**Configuration changes:**
- New flags for query performance optimization:
  ```yaml
  limits:
    query_sharding_total_shards: 128  # New default
  ```

**Recommended procedure:**
```bash
# 1. Backup
make -f make/ops/mimir.mk mimir-backup-all

# 2. Pre-upgrade check
make -f make/ops/mimir.mk mimir-pre-upgrade-check

# 3. Rolling upgrade
helm upgrade mimir sb-charts/mimir \
  --set image.tag=2.15.0 \
  --reuse-values

# 4. Validate
make -f make/ops/mimir.mk mimir-post-upgrade-check
```

---

### Upgrading from 2.13.x to 2.14.x

**Release date:** November 2024
**Type:** Minor version (rolling upgrade supported)

**Breaking changes:**
- Deprecated `blocks_storage.backend` config (use `common.storage.backend`)

**Migration steps:**
```bash
# 1. Update configuration before upgrade
kubectl edit configmap mimir-config
# Change:
#   blocks_storage:
#     backend: s3
# To:
#   common:
#     storage:
#       backend: s3

# 2. Validate configuration
kubectl exec mimir-0 -- /bin/mimir -config.file=/etc/mimir/mimir.yaml -validate-config

# 3. Proceed with rolling upgrade
helm upgrade mimir sb-charts/mimir --set image.tag=2.14.1
```

---

### Upgrading from 2.12.x to 2.13.x

**Release date:** October 2024
**Type:** Minor version

**Breaking changes:**
- None

**New features:**
- Improved query performance with query sharding
- Enhanced multi-tenancy support

**Recommended procedure:**
```bash
# Standard rolling upgrade
helm upgrade mimir sb-charts/mimir --set image.tag=2.13.2 --reuse-values
```

---

### Major Version Upgrades (2.x → 3.x)

**Note:** Mimir 3.x not yet released (as of 2.15.0)

**When Mimir 3.0 releases, expect:**
- Blue-green deployment recommended
- Potential block format changes
- Configuration schema updates
- Extended testing period required

**Planned procedure (future):**
```bash
# 1. Test in staging for 2-4 weeks
helm upgrade mimir-staging sb-charts/mimir --set image.tag=3.0.0

# 2. Use blue-green deployment for production
# (Follow Method 2: Blue-Green Deployment above)

# 3. Extended validation period (1-2 weeks)
# 4. Remove old deployment only after complete validation
```

---

## Post-Upgrade Validation

### 1. Health Check

```bash
make -f make/ops/mimir.mk mimir-post-upgrade-check
```

**Checks performed:**
- All pods running and ready
- All rings healthy (ingester, compactor, store-gateway)
- Query endpoint responding
- Ingestion endpoint accepting data
- No error logs in past 5 minutes

**Expected output:**
```
=== Mimir Post-Upgrade Validation ===
1. Pod status: 1/1 running (mimir-0)
2. Version: 2.15.0 ✓
3. Ingester ring: 1/1 ACTIVE ✓
4. Compactor ring: 1/1 ACTIVE ✓
5. Store-gateway ring: 1/1 ACTIVE ✓
6. Query test: SUCCESS (200 OK) ✓
7. Error logs: 0 errors in last 5 minutes ✓
✓ Post-upgrade validation PASSED
```

---

### 2. Functional Validation

**Test query functionality:**

```bash
# Query recent metrics (last 5 minutes)
make -f make/ops/mimir.mk mimir-query-test QUERY='up{job="mimir"}[5m]'

# Query historical metrics (last 7 days)
make -f make/ops/mimir.mk mimir-query-test QUERY='up{job="mimir"}[7d]'

# Test aggregations
make -f make/ops/mimir.mk mimir-query-test QUERY='rate(http_requests_total[5m])'
```

**Test ingestion:**

```bash
# Verify Prometheus remote-write is working
kubectl logs -l app=prometheus --tail=50 | grep remote_write

# Check ingester metrics
make -f make/ops/mimir.mk mimir-metrics-query \
  QUERY='cortex_ingester_ingested_samples_total'
```

---

### 3. Performance Validation

**Compare pre/post-upgrade performance:**

```bash
# Query latency (p99)
make -f make/ops/mimir.mk mimir-metrics-query \
  QUERY='histogram_quantile(0.99, rate(cortex_request_duration_seconds_bucket{route="api_v1_query"}[5m]))'

# Ingestion rate
make -f make/ops/mimir.mk mimir-metrics-query \
  QUERY='sum(rate(cortex_ingester_ingested_samples_total[1m]))'

# Active series count
make -f make/ops/mimir.mk mimir-metrics-query \
  QUERY='sum(cortex_ingester_memory_series)'
```

**Performance regression checklist:**
- [ ] Query latency p99 < 1 second (or same as pre-upgrade)
- [ ] Ingestion rate matches expected workload
- [ ] No increase in error rates
- [ ] Memory usage stable (no memory leaks)
- [ ] CPU usage within expected range

---

### 4. Data Integrity Validation

**Verify no data loss:**

```bash
# Query historical data across upgrade window
make -f make/ops/mimir.mk mimir-query-test \
  QUERY='count_over_time(up{job="mimir"}[2h])'

# Check for gaps in time series
make -f make/ops/mimir.mk mimir-validate-data-continuity \
  START_TIME="$(date -d '-1 hour' -Iseconds)" \
  END_TIME="$(date -Iseconds)"
```

**Expected:** No gaps in time series data during upgrade

---

### 5. Multi-Tenancy Validation (if enabled)

**Verify all tenants operational:**

```bash
# List all tenants
kubectl exec mimir-0 -- curl -s http://localhost:8080/prometheus/api/v1/label/__tenant_id__/values

# Query each tenant
for tenant in $(kubectl exec mimir-0 -- curl -s http://localhost:8080/prometheus/api/v1/label/__tenant_id__/values | jq -r '.data[]'); do
  echo "Testing tenant: $tenant"
  kubectl exec mimir-0 -- curl -H "X-Scope-OrgID: $tenant" \
    'http://localhost:8080/prometheus/api/v1/query?query=up'
done
```

---

## Rollback Procedures

### Rollback Method 1: Helm Rollback (Quick)

**Use when:** Upgrade completed but issues detected immediately
**Time:** 5-10 minutes

```bash
# Step 1: List Helm revisions
helm history mimir

# Output:
# REVISION  UPDATED       STATUS      CHART         APP VERSION  DESCRIPTION
# 1         2024-11-20    superseded  mimir-0.3.0   2.14.1       Install complete
# 2         2024-11-27    deployed    mimir-0.3.0   2.15.0       Upgrade complete

# Step 2: Rollback to previous revision
helm rollback mimir 1

# Step 3: Wait for rollback completion
kubectl rollout status statefulset mimir

# Step 4: Verify rollback
make -f make/ops/mimir.mk mimir-version
# Expected: 2.14.1

# Step 5: Validate functionality
make -f make/ops/mimir.mk mimir-post-upgrade-check
```

---

### Rollback Method 2: Restore from Backup (Complete)

**Use when:** Data corruption or complete failure
**Time:** 30-60 minutes

```bash
# Step 1: Stop Mimir
kubectl scale statefulset mimir --replicas=0

# Step 2: Restore configuration
make -f make/ops/mimir.mk mimir-restore-config \
  DIR=./tmp/mimir-backups/pre-upgrade-20241127

# Step 3: Restore block storage (if filesystem mode)
make -f make/ops/mimir.mk mimir-restore-blocks \
  FILE=./tmp/mimir-backups/pre-upgrade-20241127/blocks-backup.tar.gz

# Step 4: Restore from PVC snapshot (if available)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-mimir-0
spec:
  dataSource:
    name: pre-upgrade-20241127
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: [ReadWriteOnce]
  storageClassName: gp3
  resources:
    requests:
      storage: 100Gi
EOF

# Step 5: Reinstall previous chart version
helm upgrade mimir sb-charts/mimir \
  -f values-production.yaml \
  --set image.tag=2.14.1

# Step 6: Scale up
kubectl scale statefulset mimir --replicas=1

# Step 7: Validate restoration
make -f make/ops/mimir.mk mimir-post-upgrade-check
make -f make/ops/mimir.mk mimir-query-test QUERY='up{job="mimir"}[1h]'
```

---

### Rollback Method 3: Blue-Green Cutback

**Use when:** Blue-green deployment and new version has issues
**Time:** 5 minutes

```bash
# Revert ingress to old deployment
kubectl patch ingress mimir-ingress --type merge \
  -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"mimir"}}}]}}]}}'

# Remove failed green deployment
helm uninstall mimir-green

# Verify old deployment operational
make -f make/ops/mimir.mk mimir-health-check
```

---

## Troubleshooting

### Issue: Upgrade Stuck (Pods Not Starting)

**Symptoms:**
- Pods in CrashLoopBackOff or ImagePullBackOff
- StatefulSet rollout stuck
- Pods repeatedly restarting

**Causes:**
- Image pull failure (invalid tag or registry issues)
- Configuration incompatibility
- Resource constraints (OOMKilled)
- PVC mount issues

**Solutions:**

```bash
# 1. Check pod events
kubectl describe pod mimir-0

# 2. Check pod logs for errors
kubectl logs mimir-0 --previous

# 3. Verify image exists
kubectl get pod mimir-0 -o jsonpath='{.spec.containers[0].image}'
docker pull $(kubectl get pod mimir-0 -o jsonpath='{.spec.containers[0].image}')

# 4. Check configuration validity
kubectl exec mimir-0 -- /bin/mimir -config.file=/etc/mimir/mimir.yaml -validate-config

# 5. If OOMKilled, increase memory limits
helm upgrade mimir sb-charts/mimir \
  --set resources.limits.memory=4Gi \
  --reuse-values

# 6. If persistent failure, rollback
helm rollback mimir
```

---

### Issue: Ring Not Converging After Upgrade

**Symptoms:**
- Ingester/compactor ring shows UNHEALTHY instances
- Queries fail with "no ingesters available"
- Logs show "failed to join ring" errors

**Causes:**
- Network connectivity issues
- Ring protocol incompatibility (version mismatch)
- Etcd/memberlist issues (if using external coordinator)

**Solutions:**

```bash
# 1. Check ring status
make -f make/ops/mimir.mk mimir-ring-status

# 2. Verify all pods are same version
kubectl get pods -l app.kubernetes.io/name=mimir \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# 3. Force ring refresh
kubectl exec mimir-0 -- curl -X POST http://localhost:8080/ingester/ring/forget?id=<instance-id>

# 4. Restart pods sequentially
kubectl delete pod mimir-0 --wait
kubectl wait --for=condition=ready pod/mimir-0
```

---

### Issue: Query Performance Degraded After Upgrade

**Symptoms:**
- Queries slower than before upgrade
- Query timeout errors
- High CPU usage on mimir pods

**Causes:**
- Cache cleared during upgrade (expected, temporary)
- New query planner behavior
- Configuration changes affecting performance
- Increased series cardinality

**Solutions:**

```bash
# 1. Wait for cache to warm up (15-30 minutes)
watch kubectl top pod mimir-0

# 2. Check query statistics
make -f make/ops/mimir.mk mimir-metrics-query \
  QUERY='cortex_query_frontend_queue_length'

# 3. Review query sharding configuration
kubectl exec mimir-0 -- grep query_sharding /etc/mimir/mimir.yaml

# 4. Increase query parallelism (if needed)
helm upgrade mimir sb-charts/mimir \
  --set 'mimir.config.limits.max_query_parallelism=16' \
  --reuse-values

# 5. Monitor for 1-2 hours; if no improvement, consider rollback
```

---

### Issue: Data Loss or Gaps After Upgrade

**Symptoms:**
- Queries return incomplete data
- Missing metrics for upgrade window
- "no data" errors for specific time ranges

**Causes:**
- Ingestion paused during upgrade (expected for maintenance window)
- WAL replay failure (data loss)
- Block compaction issues
- Clock skew

**Solutions:**

```bash
# 1. Check for data gaps
make -f make/ops/mimir.mk mimir-validate-data-continuity \
  START_TIME="$(date -d '-2 hours' -Iseconds)" \
  END_TIME="$(date -Iseconds)"

# 2. Verify ingester WAL
kubectl exec mimir-0 -- ls -lh /data/ingester/wal/

# 3. Check compactor status
make -f make/ops/mimir.mk mimir-compactor-status

# 4. If WAL replay failed, restore from backup
helm rollback mimir
make -f make/ops/mimir.mk mimir-restore-all \
  DIR=./tmp/mimir-backups/pre-upgrade-$(date +%Y%m%d)

# 5. Investigate block storage
kubectl exec mimir-0 -- ls -lR /data/blocks/ | grep -v "^total" | wc -l
```

---

### Issue: S3 Connectivity Issues After Upgrade

**Symptoms:**
- Logs show "failed to list blocks" errors
- Store-gateway unable to query historical data
- S3 timeout errors

**Causes:**
- S3 credentials expired or changed
- Network policy blocking S3 access
- S3 bucket permissions changed
- Mimir S3 configuration incorrect

**Solutions:**

```bash
# 1. Verify S3 credentials
kubectl get secret mimir-s3-credentials -o jsonpath='{.data.access-key-id}' | base64 -d

# 2. Test S3 connectivity from pod
kubectl exec mimir-0 -- curl -I https://s3.amazonaws.com

# 3. Test S3 bucket access
kubectl exec mimir-0 -- aws s3 ls s3://mimir-blocks/

# 4. Check Mimir S3 configuration
kubectl exec mimir-0 -- grep -A 10 "s3:" /etc/mimir/mimir.yaml

# 5. Verify network policies allow S3
kubectl get networkpolicy -n <namespace>

# 6. Update S3 credentials if expired
kubectl create secret generic mimir-s3-credentials \
  --from-literal=access-key-id=<new-key> \
  --from-literal=secret-access-key=<new-secret> \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart statefulset mimir
```

---

## Related Documentation

- [Mimir Backup Guide](mimir-backup-guide.md) - Backup and recovery procedures
- [Mimir README](../charts/mimir/README.md) - Chart documentation
- [Makefile Commands](MAKEFILE_COMMANDS.md) - All operational commands
- [Production Checklist](PRODUCTION_CHECKLIST.md) - Production readiness validation

---

**Last Updated:** 2025-11-27
**Chart Version:** 0.3.0
**Mimir Version:** 2.15.0
