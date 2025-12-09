# MinIO Upgrade Guide

This guide provides comprehensive upgrade procedures for MinIO object storage deployments.

## Table of Contents

1. [Upgrade Strategy Overview](#upgrade-strategy-overview)
2. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
3. [Upgrade Strategies](#upgrade-strategies)
4. [Version-Specific Notes](#version-specific-notes)
5. [Post-Upgrade Validation](#post-upgrade-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Upgrade Strategy Overview

MinIO supports multiple upgrade strategies depending on your deployment mode and availability requirements.

### Upgrade Strategies Summary

| Strategy | Downtime | Risk | Complexity | Best For |
|----------|----------|------|------------|----------|
| Rolling Upgrade | None (HA) | Low | Low | Distributed mode (4+ nodes) |
| In-Place Upgrade | 5-15 min | Medium | Low | Standalone mode |
| Blue-Green Deployment | < 1 min | Very Low | High | Critical production workloads |
| Canary Upgrade | None | Very Low | High | Large-scale deployments |

### Deployment Mode Considerations

**Standalone Mode (1 node):**
- Requires downtime for upgrade
- Use in-place or blue-green strategy
- RTO: 5-15 minutes

**Distributed Mode (4+ nodes):**
- Supports zero-downtime rolling upgrades
- Automatic quorum management
- RTO: 0 minutes (with proper planning)

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**Critical items to check:**
- Breaking changes in new version
- Deprecated features
- New feature requirements
- Known issues and workarounds

**Resources:**
- [MinIO Release Notes](https://github.com/minio/minio/releases)
- [MinIO Changelog](https://github.com/minio/minio/blob/master/CHANGELOG.md)
- [Breaking Changes Document](https://min.io/docs/minio/linux/operations/upgrade.html)

```bash
# Check current version
mc admin info minio-primary | grep "Version"

# Check target version compatibility
helm show chart sb-charts/minio | grep appVersion
```

### 2. Backup Everything

**Complete backup checklist:**

```bash
# 1. Backup bucket data
mc mirror minio-primary s3://backup-bucket/pre-upgrade-$(date +%Y%m%d)

# 2. Backup configuration
mc admin config export minio-primary > backup/config-pre-upgrade.json
kubectl get configmap minio-config -n default -o yaml > backup/minio-config-pre-upgrade.yaml
kubectl get secret minio-secret -n default -o yaml > backup/minio-secret-pre-upgrade.yaml

# 3. Backup IAM policies
mc admin user list minio-primary --json > backup/users-pre-upgrade.json
mc admin policy list minio-primary --json > backup/policies-pre-upgrade.json

# 4. Backup bucket metadata
for bucket in $(mc ls minio-primary | awk '{print $5}'); do
  mc admin policy info minio-primary $bucket > backup/${bucket}-policy-pre-upgrade.json
  mc version info minio-primary/$bucket > backup/${bucket}-version-pre-upgrade.json
  mc ilm export minio-primary/$bucket > backup/${bucket}-lifecycle-pre-upgrade.json
done

# 5. Backup Kubernetes resources
kubectl get statefulset minio -n default -o yaml > backup/minio-statefulset-pre-upgrade.yaml
kubectl get pvc -n default -l app.kubernetes.io/name=minio -o yaml > backup/minio-pvcs-pre-upgrade.yaml
```

### 3. Verify Cluster Health

**Health check commands:**

```bash
# 1. Check cluster status
mc admin info minio-primary

# 2. Verify all nodes are online
mc admin cluster info minio-primary

# 3. Check for heal operations
mc admin heal status minio-primary

# 4. Verify replication status (if configured)
mc admin replicate status minio-primary

# 5. Check disk usage
mc admin prometheus metrics minio-primary | grep minio_cluster_disk

# 6. Verify pod health in Kubernetes
kubectl get pods -n default -l app.kubernetes.io/name=minio
kubectl describe pods -n default -l app.kubernetes.io/name=minio | grep -A 5 "Conditions:"
```

### 4. Check Storage Capacity

**Ensure sufficient storage:**

```bash
# Check total storage usage
mc admin info minio-primary | grep "Total Size"

# Check per-node storage
mc admin prometheus metrics minio-primary | grep minio_node_disk_used_bytes

# Verify PVC capacity
kubectl get pvc -n default -l app.kubernetes.io/name=minio -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.resources.requests.storage,USED:.status.capacity.storage
```

**Recommended free space:** At least 20% free capacity for upgrade operations.

### 5. Test in Staging Environment

**Staging upgrade workflow:**

```bash
# 1. Deploy staging MinIO (same version as production)
helm install minio-staging sb-charts/minio -f values-staging.yaml -n staging

# 2. Copy sample data from production
mc mirror --limit 1000 minio-primary/test-bucket minio-staging/test-bucket

# 3. Perform upgrade in staging
helm upgrade minio-staging sb-charts/minio --set image.tag=RELEASE.2024-12-01T01-31-13Z -n staging

# 4. Validate functionality
./validate-minio.sh minio-staging

# 5. Document any issues or special steps
```

### 6. Schedule Maintenance Window (Standalone Mode)

**For standalone deployments:**
- Notify users of scheduled downtime
- Plan for 30-60 minute window
- Schedule during off-peak hours
- Coordinate with dependent services

### 7. Prepare Rollback Plan

**Rollback readiness checklist:**
- [ ] Previous Helm revision documented
- [ ] Backup verification completed
- [ ] Rollback procedure tested in staging
- [ ] Rollback time window identified
- [ ] Team availability confirmed

### 8. Review Current Configuration

**Document current settings:**

```bash
# Export current Helm values
helm get values minio -n default > current-values.yaml

# Review MinIO server configuration
mc admin config export minio-primary > current-server-config.json

# Document replica count and mode
kubectl get statefulset minio -n default -o jsonpath='{.spec.replicas}'
```

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Distributed Mode)

**Best for:** Production HA deployments (4+ nodes), zero downtime required

**Requirements:**
- Distributed mode with 4+ nodes
- Quorum always maintained (n/2 + 1 nodes)
- Same MinIO version across all nodes during upgrade

**Downtime:** None (with proper execution)

**Procedure:**

```bash
# 1. Verify distributed mode and replica count
kubectl get statefulset minio -n default -o jsonpath='{.spec.replicas}'
# Must be >= 4

# 2. Set update strategy to RollingUpdate
helm upgrade minio sb-charts/minio \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  --set updateStrategy.type=RollingUpdate \
  --set updateStrategy.rollingUpdate.partition=0 \
  -n default

# 3. Monitor rolling update progress
kubectl rollout status statefulset minio -n default

# 4. Watch pod updates (in separate terminal)
watch kubectl get pods -n default -l app.kubernetes.io/name=minio

# 5. Monitor cluster health during upgrade
watch mc admin info minio-primary

# 6. Verify each pod before proceeding
for i in {0..3}; do
  kubectl wait --for=condition=ready pod minio-$i -n default --timeout=5m
  mc admin info minio-primary
  sleep 10
done
```

**Expected behavior:**
- Pods restart one at a time (ordered: 3, 2, 1, 0)
- Quorum maintained throughout upgrade
- No service interruption
- Total upgrade time: 10-20 minutes (4 nodes)

**Monitoring during upgrade:**

```bash
# Check cluster quorum
mc admin cluster info minio-primary

# Monitor heal operations (automatic rebalancing)
mc admin heal status minio-primary

# Check for errors
kubectl logs -f statefulset/minio -n default --all-containers
```

### Strategy 2: In-Place Upgrade (Standalone Mode)

**Best for:** Single-node deployments, development environments

**Requirements:**
- Standalone mode (1 node)
- Acceptable downtime (5-15 minutes)
- Recent backup completed

**Downtime:** 5-15 minutes (includes restart and health checks)

**Procedure:**

```bash
# 1. Pre-upgrade backup (CRITICAL)
make -f make/ops/minio.mk minio-full-backup

# 2. Scale down to 0 (graceful shutdown)
kubectl scale statefulset minio --replicas=0 -n default

# 3. Wait for pod termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=minio -n default --timeout=2m

# 4. Upgrade with new image version
helm upgrade minio sb-charts/minio \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  -n default

# 5. Scale up to 1
kubectl scale statefulset minio --replicas=1 -n default

# 6. Wait for pod to be ready
kubectl wait --for=condition=ready pod minio-0 -n default --timeout=5m

# 7. Verify service health
mc admin info minio-primary
mc ls minio-primary

# 8. Test basic operations
echo "test" > test-upgrade.txt
mc cp test-upgrade.txt minio-primary/test-bucket/
mc cp minio-primary/test-bucket/test-upgrade.txt test-download.txt
diff test-upgrade.txt test-download.txt
```

**Recovery on failure:**

```bash
# If upgrade fails, rollback immediately
helm rollback minio -n default
kubectl scale statefulset minio --replicas=1 -n default
kubectl wait --for=condition=ready pod minio-0 -n default --timeout=5m
```

### Strategy 3: Blue-Green Deployment

**Best for:** Critical production workloads, minimal risk tolerance, compliance requirements

**Requirements:**
- Sufficient resources for parallel cluster
- DNS or load balancer switching capability
- Ability to sync data between clusters

**Downtime:** < 1 minute (DNS/LB cutover only)

**Procedure:**

```bash
# 1. Deploy green environment (new version)
helm install minio-green sb-charts/minio \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  -f values-prod-distributed.yaml \
  -n default

# 2. Wait for green cluster to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=minio-green -n default --timeout=10m

# 3. Configure mc alias for green cluster
mc alias set minio-green http://minio-green:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# 4. Replicate data from blue to green
mc admin replicate add minio-primary minio-green

# Wait for replication to complete
mc admin replicate status minio-primary

# 5. Verify green cluster functionality
mc admin info minio-green
mc ls minio-green
./validate-minio.sh minio-green

# 6. Switch traffic to green (update ingress/service)
kubectl patch ingress minio-ingress -n default --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "minio-green"}]'

# 7. Monitor green cluster
watch mc admin info minio-green

# 8. Keep blue cluster running for 24-48 hours (rollback capability)

# 9. After validation period, remove blue cluster
helm uninstall minio -n default
```

**Rollback procedure:**

```bash
# Immediate rollback (switch ingress back to blue)
kubectl patch ingress minio-ingress -n default --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "minio"}]'
```

### Strategy 4: Canary Upgrade

**Best for:** Large-scale distributed deployments, gradual rollout, risk mitigation

**Requirements:**
- Distributed mode with 6+ nodes
- Ability to partition traffic
- Advanced monitoring and observability

**Downtime:** None

**Procedure:**

```bash
# 1. Upgrade 1 node (canary)
helm upgrade minio sb-charts/minio \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  --set updateStrategy.rollingUpdate.partition=3 \
  -n default

# This will upgrade only pod minio-3 (highest ordinal)

# 2. Monitor canary node for 1-4 hours
kubectl logs -f minio-3 -n default
mc admin prometheus metrics minio-primary | grep minio_3

# 3. Check for errors or anomalies
kubectl describe pod minio-3 -n default
mc admin cluster info minio-primary

# 4. If canary is healthy, proceed with rolling upgrade
helm upgrade minio sb-charts/minio \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  --set updateStrategy.rollingUpdate.partition=0 \
  -n default

# 5. Monitor full rollout
kubectl rollout status statefulset minio -n default
```

**Canary rollback:**

```bash
# Rollback canary node only
kubectl delete pod minio-3 -n default
# StatefulSet will recreate with old version due to partition setting
```

---

## Version-Specific Notes

### MinIO RELEASE.2023.x → RELEASE.2024.x

**Major changes:**
- New storage backend optimizations
- Enhanced site replication features
- Updated IAM policy engine
- Improved object lock support

**Breaking changes:**
- None (backward compatible)

**Upgrade notes:**
- No special procedures required
- Standard rolling upgrade supported
- Test IAM policies after upgrade

**Downtime:** None (distributed) / 5-10 min (standalone)

### MinIO RELEASE.2022.x → RELEASE.2024.x

**Major changes:**
- Multiple release cycles (recommend incremental upgrade)
- Significant performance improvements
- New compression algorithms
- Enhanced metrics and monitoring

**Breaking changes:**
- Deprecated legacy replication API
- Changed default bucket versioning behavior
- Updated TLS configuration format

**Upgrade notes:**
1. Upgrade to intermediate version first (RELEASE.2023.x)
2. Verify compatibility with existing clients
3. Update mc client to latest version
4. Review and update replication configurations

**Downtime:** None (distributed) / 15-20 min (standalone)

### Distributed Mode: Adding Nodes (Horizontal Scaling)

**Important:** Cannot add nodes to existing distributed cluster. Must redeploy.

**Workaround for scaling:**

```bash
# 1. Deploy new larger cluster (e.g., 4 → 8 nodes)
helm install minio-new sb-charts/minio \
  --set replicaCount=8 \
  --set minio.mode=distributed \
  --set image.tag=RELEASE.2024-12-01T01-31-13Z \
  -n default

# 2. Configure site replication
mc admin replicate add minio-primary minio-new

# 3. Wait for full replication
mc admin replicate status minio-primary

# 4. Switch traffic to new cluster
# (use blue-green strategy)

# 5. Decommission old cluster
helm uninstall minio -n default
helm upgrade minio-new minio -n default
```

### Erasure Coding Configuration Changes

**Changing parity cannot be done in-place:**

Current: 4 nodes, 2 parity (EC:2)
Target: 4 nodes, 1 parity (EC:1)

**Procedure:**
- Deploy new cluster with desired EC settings
- Replicate data to new cluster
- Switch traffic (blue-green deployment)

---

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# validate-minio-upgrade.sh

ALIAS="minio-primary"
FAILED=0

echo "=== MinIO Post-Upgrade Validation ==="

# 1. Check cluster status
echo "1. Checking cluster status..."
if mc admin info $ALIAS > /dev/null 2>&1; then
  echo "   ✅ Cluster is online"
else
  echo "   ❌ Cluster is offline"
  FAILED=1
fi

# 2. Verify version
echo "2. Verifying version..."
VERSION=$(mc admin info $ALIAS | grep "Version" | awk '{print $2}')
echo "   Current version: $VERSION"

# 3. Check node count
echo "3. Checking node count..."
NODE_COUNT=$(mc admin cluster info $ALIAS | grep "Servers:" | awk '{print $2}')
echo "   Nodes: $NODE_COUNT"

# 4. Verify all nodes online
echo "4. Verifying all nodes online..."
ONLINE_NODES=$(mc admin cluster info $ALIAS | grep "Online" | wc -l)
if [ "$ONLINE_NODES" -eq "$NODE_COUNT" ]; then
  echo "   ✅ All nodes online ($ONLINE_NODES/$NODE_COUNT)"
else
  echo "   ❌ Some nodes offline ($ONLINE_NODES/$NODE_COUNT)"
  FAILED=1
fi

# 5. Check heal status
echo "5. Checking heal status..."
if mc admin heal status $ALIAS | grep -q "No active heal operations"; then
  echo "   ✅ No heal operations running"
else
  echo "   ⚠️  Heal operations in progress"
fi

# 6. Verify bucket access
echo "6. Verifying bucket access..."
if mc ls $ALIAS > /dev/null 2>&1; then
  echo "   ✅ Buckets accessible"
else
  echo "   ❌ Cannot list buckets"
  FAILED=1
fi

# 7. Test write operation
echo "7. Testing write operation..."
echo "test-$(date +%s)" > /tmp/test-upgrade.txt
if mc cp /tmp/test-upgrade.txt $ALIAS/test-bucket/upgrade-test.txt > /dev/null 2>&1; then
  echo "   ✅ Write operation successful"
  mc rm $ALIAS/test-bucket/upgrade-test.txt
else
  echo "   ❌ Write operation failed"
  FAILED=1
fi

# 8. Test read operation
echo "8. Testing read operation..."
if mc cp $ALIAS/test-bucket/sample-file.txt /tmp/sample-download.txt > /dev/null 2>&1; then
  echo "   ✅ Read operation successful"
else
  echo "   ⚠️  Read operation failed (may be normal if file doesn't exist)"
fi

# 9. Verify IAM
echo "9. Verifying IAM..."
if mc admin user list $ALIAS > /dev/null 2>&1; then
  echo "   ✅ IAM accessible"
else
  echo "   ❌ IAM not accessible"
  FAILED=1
fi

# 10. Check metrics endpoint
echo "10. Checking metrics endpoint..."
if mc admin prometheus metrics $ALIAS > /dev/null 2>&1; then
  echo "   ✅ Metrics endpoint available"
else
  echo "   ⚠️  Metrics endpoint unavailable"
fi

echo ""
if [ $FAILED -eq 0 ]; then
  echo "✅ All validation checks passed!"
  exit 0
else
  echo "❌ Some validation checks failed!"
  exit 1
fi
```

### Manual Validation Checklist

- [ ] **Cluster status:** All nodes online and healthy
- [ ] **Version verification:** Correct version deployed
- [ ] **Bucket listing:** Can list all buckets
- [ ] **Object read:** Can read existing objects
- [ ] **Object write:** Can write new objects
- [ ] **Object delete:** Can delete objects
- [ ] **IAM access:** Users and policies functional
- [ ] **Versioning:** Bucket versioning working
- [ ] **Lifecycle:** Lifecycle rules executing
- [ ] **Replication:** Site replication functioning (if configured)
- [ ] **Metrics:** Prometheus metrics available
- [ ] **Logs:** No critical errors in logs

---

## Rollback Procedures

### Rollback Method 1: Helm Rollback (Quick)

**When to use:** Upgrade deployed successfully but issues discovered

**Procedure:**

```bash
# 1. Check Helm history
helm history minio -n default

# 2. Rollback to previous revision
helm rollback minio -n default

# 3. Wait for rollout
kubectl rollout status statefulset minio -n default

# 4. Verify rollback
mc admin info minio-primary
kubectl get pods -n default -l app.kubernetes.io/name=minio
```

**Recovery time:** 5-10 minutes (distributed) / 3-5 minutes (standalone)

### Rollback Method 2: Full Restore from Backup

**When to use:** Data corruption, Helm rollback failed

**Procedure:**

```bash
# 1. Stop MinIO completely
kubectl scale statefulset minio --replicas=0 -n default

# 2. Restore Kubernetes resources
kubectl apply -f backup/minio-statefulset-pre-upgrade.yaml
kubectl apply -f backup/minio-config-pre-upgrade.yaml
kubectl apply -f backup/minio-secret-pre-upgrade.yaml

# 3. Restore bucket data (if needed)
# Start MinIO first
kubectl scale statefulset minio --replicas=4 -n default
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n default --timeout=5m

# Restore from backup
mc mirror s3://backup-bucket/pre-upgrade-20250109 minio-primary

# 4. Restore IAM
cat backup/users-pre-upgrade.json | while read user; do
  mc admin user add minio-primary $(echo $user | jq -r '.accessKey') $(echo $user | jq -r '.secretKey')
done

# 5. Restore bucket metadata
for bucket in $(mc ls minio-primary | awk '{print $5}'); do
  mc admin policy set minio-primary $bucket < backup/${bucket}-policy-pre-upgrade.json
  mc ilm import minio-primary/$bucket < backup/${bucket}-lifecycle-pre-upgrade.json
done

# 6. Verify restoration
./validate-minio.sh
```

**Recovery time:** 1-4 hours (depends on data size)

### Rollback Method 3: Blue-Green Rollback

**When to use:** Blue-green deployment, green cluster has issues

**Procedure:**

```bash
# 1. Switch traffic back to blue cluster
kubectl patch ingress minio-ingress -n default --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "minio"}]'

# 2. Verify blue cluster health
mc admin info minio-primary

# 3. Remove green cluster
helm uninstall minio-green -n default

# 4. Clean up green PVCs (optional)
kubectl delete pvc -n default -l app.kubernetes.io/instance=minio-green
```

**Recovery time:** < 1 minute

---

## Troubleshooting

### Issue 1: Pod Stuck in Pending/Init

**Symptoms:**
- Pod remains in Pending state
- PVC binding issues
- Resource constraints

**Diagnosis:**

```bash
# Check pod status
kubectl describe pod minio-0 -n default

# Check PVC status
kubectl get pvc -n default -l app.kubernetes.io/name=minio

# Check node resources
kubectl top nodes
```

**Solutions:**
- Verify PVC provisioner is working
- Check storage class configuration
- Ensure sufficient node resources
- Review pod scheduling constraints

### Issue 2: Quorum Lost During Rolling Upgrade

**Symptoms:**
- Cluster becomes unavailable
- Write operations fail
- "Quorum lost" errors in logs

**Diagnosis:**

```bash
# Check cluster status
mc admin cluster info minio-primary

# Check pod readiness
kubectl get pods -n default -l app.kubernetes.io/name=minio

# Review logs for quorum errors
kubectl logs -n default -l app.kubernetes.io/name=minio --tail=100 | grep -i quorum
```

**Solutions:**
- Pause upgrade immediately
- Ensure at least n/2 + 1 nodes are ready
- Increase pod readiness probe timeout
- Roll back if quorum cannot be restored

### Issue 3: Version Mismatch Errors

**Symptoms:**
- Nodes reject connections
- "Version mismatch" in logs
- Cluster health degraded

**Diagnosis:**

```bash
# Check version on each pod
for i in {0..3}; do
  echo "Pod minio-$i:"
  kubectl exec -n default minio-$i -- minio --version
done
```

**Solutions:**
- Complete rolling upgrade (don't pause mid-upgrade)
- Ensure updateStrategy.partition is set correctly
- Roll back to consistent version

### Issue 4: Post-Upgrade Performance Degradation

**Symptoms:**
- Slow read/write operations
- High CPU/memory usage
- Increased heal operations

**Diagnosis:**

```bash
# Check heal status
mc admin heal status minio-primary

# Monitor metrics
mc admin prometheus metrics minio-primary | grep -E "minio_cluster|minio_heal"

# Check resource usage
kubectl top pods -n default -l app.kubernetes.io/name=minio
```

**Solutions:**
- Wait for heal operations to complete
- Increase resource limits
- Review erasure coding configuration
- Check network performance

---

## Best Practices

### DO ✅

- ✅ **Test upgrades in staging first**
- ✅ **Backup everything before upgrading**
- ✅ **Read release notes thoroughly**
- ✅ **Use rolling upgrades for distributed mode**
- ✅ **Monitor cluster health during upgrade**
- ✅ **Validate functionality post-upgrade**
- ✅ **Keep backup for 48-72 hours post-upgrade**
- ✅ **Update mc client to match server version**
- ✅ **Schedule during low-traffic periods**
- ✅ **Have rollback plan ready**

### DON'T ❌

- ❌ **Don't skip backups** - always backup before upgrading
- ❌ **Don't upgrade during peak hours** - schedule maintenance windows
- ❌ **Don't ignore release notes** - breaking changes happen
- ❌ **Don't mix versions** in distributed mode (temporary during rolling upgrade is OK)
- ❌ **Don't skip staging tests** - catch issues early
- ❌ **Don't delete old backups immediately** - keep for recovery
- ❌ **Don't upgrade multiple major versions** at once - use incremental upgrades
- ❌ **Don't ignore heal operations** - let them complete before declaring success
- ❌ **Don't panic on temporary errors** - some errors during upgrade are normal
- ❌ **Don't skip post-upgrade validation** - verify everything works

### Upgrade Cadence Recommendations

**Patch releases (RELEASE.2024-12-01 → RELEASE.2024-12-15):**
- Frequency: Monthly
- Risk: Low
- Testing: Basic smoke tests

**Minor releases (RELEASE.2024-Q1 → RELEASE.2024-Q2):**
- Frequency: Quarterly
- Risk: Medium
- Testing: Full regression testing

**Major releases (Major version changes):**
- Frequency: Annually
- Risk: High
- Testing: Comprehensive testing in staging

---

**See Also:**
- [MinIO Backup Guide](minio-backup-guide.md)
- MinIO README - Operations section
- MinIO values.yaml - Upgrade configuration

**Last Updated:** 2025-12-09
