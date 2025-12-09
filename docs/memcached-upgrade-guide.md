# Memcached Upgrade Guide

## Overview

This guide provides comprehensive upgrade procedures for Memcached deployments on Kubernetes using the scripton-charts Helm chart.

**Important**: Memcached is a **stateless in-memory cache** with **zero-downtime upgrades** supported via rolling updates. Cache data is ephemeral and lost during pod restarts (expected behavior).

### Version Compatibility

| Memcached Version | Release Date | Chart Version | Notes |
|-------------------|--------------|---------------|-------|
| **1.6.39** | 2025-01 | 0.4.0+ | Latest stable, Alpine 3.22 |
| **1.6.38** | 2024-12 | 0.3.0 | Stable |
| **1.6.37** | 2024-11 | 0.3.0 | Stable |
| **1.6.x** | 2019+ | 0.3.0+ | Current LTS series |
| **1.5.x** | 2017-2019 | 0.2.0 | Legacy (EOL) |

**Kubernetes Compatibility**:
- Memcached 1.6.x: Kubernetes 1.19+
- Chart 0.4.0: Kubernetes 1.25+, Helm 3.12+

---

## Pre-Upgrade Checklist

Before upgrading Memcached, complete these steps:

- [ ] **Review Release Notes**: Check [Memcached releases](https://github.com/memcached/memcached/wiki/ReleaseNotes) for breaking changes
- [ ] **Backup Configuration**: Export current ConfigMap and Helm values
- [ ] **Check Client Compatibility**: Ensure application clients support new Memcached version
- [ ] **Verify Resource Availability**: Confirm cluster has resources for rolling update (CPU/memory)
- [ ] **Test in Non-Production**: Validate upgrade in dev/staging environment
- [ ] **Review Cache Usage**: Check current cache hit rate and eviction rate (will reset after upgrade)
- [ ] **Plan for Cache Miss**: Applications must handle cache misses gracefully after upgrade
- [ ] **Schedule Maintenance (Optional)**: For risk-averse environments, consider low-traffic window

**Note**: Since Memcached is stateless, **data loss is expected and acceptable** during upgrades. Applications must regenerate cache entries on first access.

---

## Upgrade Strategies

### Strategy 1: Rolling Update (Recommended)

**Best For**: Production environments, multi-replica deployments

**Downtime**: None (brief cache misses during pod restarts)

**Requirements**:
- `replicaCount >= 2` (for minimal disruption)
- `podDisruptionBudget.enabled: true` with `minAvailable: 1`

**Procedure**:

```bash
# 1. Backup current configuration
kubectl get configmap -n default my-memcached -o yaml > memcached-config-backup.yaml
helm get values my-memcached -n default > memcached-values-backup.yaml

# 2. Update Helm chart and image version
helm upgrade my-memcached scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  --set replicaCount=3 \
  --set podDisruptionBudget.enabled=true \
  --set podDisruptionBudget.minAvailable=2 \
  -n default \
  --wait

# 3. Monitor rolling update
kubectl rollout status deployment/my-memcached -n default

# 4. Verify all pods are running new version
kubectl get pods -n default -l app.kubernetes.io/name=memcached -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase

# 5. Test cache functionality
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211'

# 6. Monitor cache hit rate (expect initial low rate)
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211' | grep -E "get_hits|get_misses"
```

**Expected Behavior**:
- Pods restart one-by-one (controlled by `maxUnavailable: 0`, `maxSurge: 1`)
- Cache entries are lost on pod restart (expected)
- Applications experience cache misses during warmup period
- Service remains available throughout upgrade

**RTO**: < 5 minutes (time for all pods to restart)

---

### Strategy 2: Blue-Green Deployment

**Best For**: Zero-downtime requirements, critical cache workloads

**Downtime**: None (traffic switch only)

**Requirements**:
- Sufficient cluster resources for parallel deployment
- Client applications support multiple Memcached endpoints

**Procedure**:

```bash
# 1. Deploy new version (green) alongside existing (blue)
helm install my-memcached-green scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  --set fullnameOverride=memcached-green \
  --set replicaCount=3 \
  -n default

# 2. Wait for green deployment to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached-green -n default --timeout=300s

# 3. Test green deployment
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached-green -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211'

# 4. Update application configuration to point to green service
# Example: Update application ConfigMap
kubectl patch configmap app-config -n default --type merge -p '{"data":{"MEMCACHED_HOST":"memcached-green.default.svc.cluster.local"}}'

# 5. Restart application pods to pick up new config
kubectl rollout restart deployment/my-app -n default

# 6. Monitor for issues (15-30 minutes)
# Check application logs, error rates, cache hit rate

# 7. Remove blue deployment (if satisfied)
helm uninstall my-memcached -n default

# 8. Rename green to original name (optional)
# This step requires brief downtime - skip if unnecessary
```

**Expected Behavior**:
- Both blue and green clusters run in parallel
- Applications switch to green cluster after restart
- Zero downtime for cache service
- Cache warming happens on green cluster while blue is still serving

**RTO**: < 1 minute (application restart time)

---

### Strategy 3: Maintenance Window Upgrade

**Best For**: Single-replica deployments, non-critical environments

**Downtime**: 2-5 minutes (complete restart)

**Requirements**:
- Scheduled maintenance window
- Applications tolerate temporary cache unavailability

**Procedure**:

```bash
# 1. Backup configuration
kubectl get configmap -n default my-memcached -o yaml > memcached-config-backup.yaml
helm get values my-memcached -n default > memcached-values-backup.yaml

# 2. Uninstall old version
helm uninstall my-memcached -n default

# 3. Wait for complete cleanup
kubectl wait --for=delete pod -l app.kubernetes.io/name=memcached -n default --timeout=120s

# 4. Install new version
helm install my-memcached scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  -f memcached-values-backup.yaml \
  -n default

# 5. Wait for new pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=300s

# 6. Verify deployment
kubectl get pods,svc -n default -l app.kubernetes.io/name=memcached

# 7. Test cache functionality
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211'
```

**Expected Behavior**:
- Complete downtime during deployment
- Fresh cache (all data lost)
- Applications experience cache misses after upgrade

**RTO**: < 5 minutes

---

## Version-Specific Notes

### Memcached 1.6.x Series

**Current LTS**: Maintained with security updates and bug fixes

**Key Features**:
- TLS support (1.6.10+)
- Improved slab allocator
- Better connection management
- Modern memory allocator (`-o modern`)

**Breaking Changes**: None between 1.6.x patch versions

**Configuration Recommendations**:
```yaml
memcached:
  extraArgs:
    - "-o modern"              # Modern memory allocator
    - "-o hashpower=20"        # Larger hash table (2^20 buckets)
    - "-o tail_repair_time=0"  # Disable tail repair for performance
```

---

### Memcached 1.6.10+ (TLS Support)

**New Feature**: TLS encryption for client connections

**Configuration**:
```yaml
memcached:
  extraArgs:
    - "-Z"  # Enable TLS
    - "--tls-cert=/path/to/cert.pem"
    - "--tls-key=/path/to/key.pem"
```

**Client Impact**: Clients must be updated to support TLS connections

**Migration Strategy**:
1. Deploy new Memcached with TLS enabled
2. Update clients to use TLS connections
3. Remove old non-TLS deployment

---

### Memcached 1.5.x → 1.6.x Migration

**Breaking Changes**:
- **Default hash table size**: Increased from 2^16 to 2^20 buckets
  - **Impact**: Slightly higher memory usage (~1 MB)
  - **Fix**: Adjust `-o hashpower` if necessary

- **Slab allocator improvements**: More efficient memory usage
  - **Impact**: Lower memory overhead per item
  - **Fix**: May need to adjust `maxMemory` setting

- **Connection handling**: Improved concurrency
  - **Impact**: Better performance under high connection load
  - **Fix**: None required

**Configuration Changes**:
```yaml
# Old (1.5.x)
memcached:
  maxMemory: 256
  extraArgs: []

# New (1.6.x) - recommended
memcached:
  maxMemory: 256  # May reduce slightly due to slab improvements
  extraArgs:
    - "-o modern"              # Enable modern allocator
    - "-o hashpower=20"        # Explicit hash table size
```

**Upgrade Steps**:
1. Test in non-production with application workload
2. Monitor memory usage (expect slight decrease)
3. Adjust `maxMemory` if necessary
4. Use rolling update strategy for zero-downtime

---

### Memcached 1.4.x → 1.6.x Migration (Legacy)

**⚠️ Not Recommended**: Direct upgrade not supported by this chart

**Migration Path**:
1. Upgrade to 1.5.x first (using legacy chart)
2. Then upgrade to 1.6.x

**Alternative**: Deploy fresh 1.6.x cluster and retire 1.4.x cluster

---

### Protocol Changes

**Binary Protocol Stability**:
- Memcached protocol is **stable** across all 1.x versions
- No client-side changes required for version upgrades
- Binary protocol introduced in 1.3.x, unchanged since then

**ASCII Protocol**:
- Fully compatible across all versions
- No breaking changes

**Recommendation**: No client library updates required for protocol compatibility

---

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# post-upgrade-validation.sh

NAMESPACE="default"
RELEASE="my-memcached"

echo "=== Memcached Post-Upgrade Validation ==="

# 1. Check pod status
echo "[1/7] Checking pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n $NAMESPACE --timeout=300s || exit 1
echo "  ✓ All pods are ready"

# 2. Check version
echo "[2/7] Checking Memcached version..."
POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
VERSION=$(kubectl exec -n $NAMESPACE $POD -- memcached -V 2>&1 | head -1)
echo "  Version: $VERSION"

# 3. Test basic cache operations
echo "[3/7] Testing cache operations..."
RESULT=$(kubectl exec -n $NAMESPACE $POD -- sh -c 'echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211')
if echo "$RESULT" | grep -q "VALUE test"; then
  echo "  ✓ Cache set/get operations working"
else
  echo "  ✗ Cache operations failed"
  exit 1
fi

# 4. Check stats
echo "[4/7] Checking cache stats..."
STATS=$(kubectl exec -n $NAMESPACE $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211')
UPTIME=$(echo "$STATS" | grep "STAT uptime" | awk '{print $3}')
CONNECTIONS=$(echo "$STATS" | grep "STAT curr_connections" | awk '{print $3}')
echo "  Uptime: $UPTIME seconds"
echo "  Current connections: $CONNECTIONS"

# 5. Verify configuration
echo "[5/7] Verifying configuration..."
MAX_MEMORY=$(echo "$STATS" | grep "STAT limit_maxbytes" | awk '{print $3}')
MAX_CONNECTIONS=$(echo "$STATS" | grep "STAT max_connections" | awk '{print $3}')
echo "  Max memory: $((MAX_MEMORY / 1024 / 1024)) MB"
echo "  Max connections: $MAX_CONNECTIONS"

# 6. Check service endpoint
echo "[6/7] Checking service endpoint..."
kubectl get svc -n $NAMESPACE $RELEASE || exit 1
echo "  ✓ Service is available"

# 7. Test from within cluster
echo "[7/7] Testing connectivity from within cluster..."
kubectl run -it --rm memcached-test --image=busybox --restart=Never -n $NAMESPACE -- sh -c "echo -e 'stats\r\nquit\r' | nc $RELEASE.$ NAMESPACE.svc.cluster.local 11211" 2>&1 | grep -q "STAT version"
if [ $? -eq 0 ]; then
  echo "  ✓ Cluster connectivity working"
else
  echo "  ⚠ Cluster connectivity test inconclusive"
fi

echo ""
echo "=== Validation Complete ==="
```

**Run Validation**:

```bash
chmod +x post-upgrade-validation.sh
./post-upgrade-validation.sh
```

---

### Manual Validation Checklist

- [ ] All pods are `Running` and `Ready`
- [ ] Memcached version matches expected version
- [ ] Cache set/get operations work correctly
- [ ] Service endpoints are accessible
- [ ] Configuration (memory, connections) is correct
- [ ] Applications can connect to cache
- [ ] Cache hit rate is recovering (monitor for 1 hour)
- [ ] No error logs in Memcached pods
- [ ] Resource usage (CPU/memory) is within expected limits

---

## Rollback Procedures

### Method 1: Helm Rollback (Quick)

**Use Case**: Recently upgraded, issue discovered immediately

**Procedure**:

```bash
# 1. List release history
helm history my-memcached -n default

# 2. Rollback to previous revision
helm rollback my-memcached -n default

# 3. Wait for rollout to complete
kubectl rollout status deployment/my-memcached -n default

# 4. Verify rollback
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- memcached -V
```

**RTO**: < 5 minutes

---

### Method 2: Configuration Rollback

**Use Case**: Configuration change caused issues, not version upgrade

**Procedure**:

```bash
# 1. Restore previous configuration
kubectl apply -f memcached-config-backup.yaml

# 2. Restart pods to apply config
kubectl rollout restart deployment/my-memcached -n default

# 3. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=300s

# 4. Verify configuration
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats settings\r\nquit\r" | nc localhost 11211'
```

**RTO**: < 5 minutes

---

### Method 3: Blue-Green Rollback

**Use Case**: Blue deployment still exists, want to revert from green

**Procedure**:

```bash
# 1. Revert application to blue service
kubectl patch configmap app-config -n default --type merge -p '{"data":{"MEMCACHED_HOST":"memcached.default.svc.cluster.local"}}'

# 2. Restart applications
kubectl rollout restart deployment/my-app -n default

# 3. Remove green deployment
helm uninstall my-memcached-green -n default

# 4. Verify applications are using blue cluster
kubectl logs -n default deployment/my-app | grep -i memcached
```

**RTO**: < 2 minutes (application restart)

---

## Troubleshooting

### Issue 1: Pod CrashLoopBackOff After Upgrade

**Symptoms**:
```bash
$ kubectl get pods -n default
NAME                           READY   STATUS             RESTARTS   AGE
my-memcached-7c9f4d8b-x1y2z    0/1     CrashLoopBackOff   5          2m
```

**Diagnosis**:
```bash
# Check pod logs
kubectl logs -n default my-memcached-7c9f4d8b-x1y2z

# Check pod events
kubectl describe pod -n default my-memcached-7c9f4d8b-x1y2z
```

**Common Causes**:

1. **Invalid command-line arguments**:
   ```
   # Error: unknown option: -o modernn
   ```
   **Fix**: Correct typo in `extraArgs`:
   ```yaml
   memcached:
     extraArgs:
       - "-o modern"  # Fixed typo
   ```

2. **Insufficient memory**:
   ```
   # Error: failed to allocate memory
   ```
   **Fix**: Increase pod memory limits:
   ```yaml
   resources:
     limits:
       memory: 1Gi  # Increased from 512Mi
   ```

3. **Port already in use**:
   ```
   # Error: failed to listen on TCP port 11211
   ```
   **Fix**: Check for port conflicts, ensure no other service uses port 11211

---

### Issue 2: High Cache Miss Rate After Upgrade

**Symptoms**: Applications report significantly increased latency, cache hit rate near 0%

**Diagnosis**:
```bash
# Check cache hit/miss stats
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211' | grep -E "get_hits|get_misses"
```

**Expected Behavior**:
- **This is normal** after Memcached restart
- Cache is empty, all keys must be regenerated
- Hit rate will recover over time (1-4 hours depending on workload)

**Solutions**:

1. **Implement cache warming** (proactive):
   ```bash
   # Trigger cache warming endpoint in application
   curl -X POST http://my-app/api/cache/warm
   ```

2. **Gradual traffic ramp-up** (reactive):
   ```bash
   # Scale down application replicas temporarily to reduce load
   kubectl scale deployment/my-app --replicas=2 -n default

   # Wait for cache to warm up (30 minutes)
   # Then scale back up
   kubectl scale deployment/my-app --replicas=10 -n default
   ```

3. **Monitor and wait**:
   - Cache hit rate should recover naturally as applications access data
   - Typical recovery time: 1-4 hours for full warmup

---

### Issue 3: Client Connection Errors

**Symptoms**: Applications cannot connect to Memcached after upgrade

**Diagnosis**:
```bash
# Test connectivity from application pod
APP_POD=$(kubectl get pods -n default -l app=my-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $APP_POD -- sh -c 'echo -e "stats\r\nquit\r" | nc memcached.default.svc.cluster.local 11211'

# Check service endpoints
kubectl get endpoints -n default my-memcached

# Check pod status
kubectl get pods -n default -l app.kubernetes.io/name=memcached -o wide
```

**Common Causes**:

1. **Service selector mismatch**:
   ```bash
   # Verify service selector matches pod labels
   kubectl get svc -n default my-memcached -o yaml | grep -A3 selector
   kubectl get pods -n default -l app.kubernetes.io/name=memcached --show-labels
   ```

2. **NetworkPolicy blocking traffic**:
   ```bash
   # Check NetworkPolicy rules
   kubectl get networkpolicy -n default

   # Temporarily disable to test
   kubectl delete networkpolicy -n default my-memcached-netpol
   ```

3. **DNS resolution issues**:
   ```bash
   # Test DNS from application pod
   kubectl exec -n default $APP_POD -- nslookup memcached.default.svc.cluster.local
   ```

---

### Issue 4: Memory Limit Exceeded

**Symptoms**: Pods being OOMKilled, frequent restarts

**Diagnosis**:
```bash
# Check pod resource usage
kubectl top pods -n default -l app.kubernetes.io/name=memcached

# Check OOMKill events
kubectl get events -n default | grep -i oom

# Check Memcached memory usage
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211' | grep -E "bytes|limit_maxbytes"
```

**Solution**:

```bash
# Increase memory limits
helm upgrade my-memcached scripton-charts/memcached \
  --set memcached.maxMemory=512 \
  --set resources.limits.memory=768Mi \
  --set resources.requests.memory=512Mi \
  -n default \
  --reuse-values

# Wait for rolling update
kubectl rollout status deployment/my-memcached -n default
```

**Rule of Thumb**: Set pod memory limit = (memcached.maxMemory × 1.2) + 100 MB
- Example: `maxMemory=512 MB` → pod limit = `(512 × 1.2) + 100 = 714 MB` (round up to 768 MB)

---

## Best Practices

### 1. Version Management

**Upgrade Path**:
- ✅ Upgrade patch versions frequently (1.6.37 → 1.6.38 → 1.6.39)
- ✅ Test minor versions in non-production first (1.5.x → 1.6.x)
- ❌ Never skip multiple minor versions (1.4.x → 1.6.x not supported)

**Recommendation**: Stay on latest patch version of 1.6.x series for security updates.

---

### 2. Configuration Management

**GitOps Workflow**:
- ✅ Store `values.yaml` in Git repository
- ✅ Use ArgoCD or Flux for automated deployments
- ✅ Review configuration changes via Pull Requests
- ✅ Tag releases for easy rollback

**Example**:
```bash
git tag v0.4.0-memcached-1.6.39
git push --tags
```

---

### 3. Rollout Strategy

**For Production**:
- ✅ Use rolling updates with PodDisruptionBudget
- ✅ Set `replicaCount >= 3` for HA
- ✅ Set `podDisruptionBudget.minAvailable: 2`
- ✅ Monitor cache hit rate during upgrade

**Configuration**:
```yaml
replicaCount: 3

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0  # Zero downtime
    maxSurge: 1        # One extra pod during rollout

podDisruptionBudget:
  enabled: true
  minAvailable: 2  # Ensure majority availability
```

---

### 4. Monitoring

**Key Metrics**:
- **Cache hit rate**: `get_hits / (get_hits + get_misses)`
- **Eviction rate**: `evictions` (should be low)
- **Connection count**: `curr_connections` vs `max_connections`
- **Memory usage**: `bytes` vs `limit_maxbytes`

**Example Prometheus Queries**:
```promql
# Cache hit rate
rate(memcached_commands_total{command="get",status="hit"}[5m]) / rate(memcached_commands_total{command="get"}[5m])

# Eviction rate
rate(memcached_items_evicted_total[5m])

# Memory usage percentage
memcached_current_bytes / memcached_limit_bytes * 100
```

**Alerts**:
```yaml
- alert: MemcachedHighEvictionRate
  expr: rate(memcached_items_evicted_total[5m]) > 100
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Memcached eviction rate is high"
    description: "{{ $value }} evictions/sec - consider increasing memory"

- alert: MemcachedLowCacheHitRate
  expr: rate(memcached_commands_total{status="hit"}[30m]) / rate(memcached_commands_total{command="get"}[30m]) < 0.5
  for: 30m
  labels:
    severity: warning
  annotations:
    summary: "Memcached cache hit rate is low"
    description: "Hit rate: {{ $value | humanizePercentage }}"
```

---

### 5. Testing

**Pre-Upgrade Testing**:
1. Deploy to dev/staging environment
2. Run load tests with production-like traffic
3. Monitor cache hit rate and performance
4. Verify client library compatibility
5. Test rollback procedures

**Load Testing Example**:
```bash
# Using memtier_benchmark
kubectl run memtier --image=redislabs/memtier_benchmark --rm -it -- \
  --server=memcached.default.svc.cluster.local \
  --port=11211 \
  --protocol=memcache_text \
  --clients=50 \
  --threads=4 \
  --ratio=1:10 \
  --data-size=1024 \
  --requests=10000

# Monitor during test
kubectl top pods -n default -l app.kubernetes.io/name=memcached
```

---

### 6. Cache Warming Strategy

**Post-Upgrade**:
Implement cache warming to reduce initial cache miss rate:

**Option 1: Application-Level Warming**:
```python
# Example Python cache warming endpoint
@app.route('/api/cache/warm', methods=['POST'])
def warm_cache():
    # Preload frequently accessed keys
    for user_id in get_active_users():
        cache.set(f'user:{user_id}', get_user_data(user_id))

    for product_id in get_popular_products():
        cache.set(f'product:{product_id}', get_product_data(product_id))

    return {'status': 'success', 'warmed_keys': count}
```

**Option 2: Traffic Replay**:
```bash
# Replay production traffic from logs to warm cache
cat access.log | grep "GET /api" | xargs -P10 -I{} curl {}
```

---

### 7. Capacity Planning

**Memory Sizing**:
```
Total Memory Required = (Average Item Size × Number of Items × 1.2) + 100 MB

Example:
- Average item size: 2 KB
- Expected items: 100,000
- Total: (2 KB × 100,000 × 1.2) + 100 MB = 340 MB

Recommended maxMemory: 384 MB (round up to next power of 2)
Pod memory limit: 512 MB (340 MB × 1.2 + overhead)
```

---

## Summary

### Upgrade Checklist

- [ ] Review release notes for breaking changes
- [ ] Backup configuration (ConfigMap, Helm values)
- [ ] Test upgrade in non-production environment
- [ ] Verify client library compatibility
- [ ] Choose upgrade strategy (Rolling/Blue-Green/Maintenance)
- [ ] Execute upgrade during low-traffic window (optional)
- [ ] Monitor pod rollout status
- [ ] Validate cache functionality post-upgrade
- [ ] Monitor cache hit rate recovery (1-4 hours)
- [ ] Implement cache warming if necessary

### Key Takeaways

1. **Memcached upgrades are low-risk**: Stateless architecture, stable protocol
2. **Zero-downtime possible**: Rolling updates with PodDisruptionBudget
3. **Cache data is lost**: Expected behavior, applications must handle cache misses
4. **Protocol is stable**: No client library updates required
5. **Test before production**: Validate in non-production environment
6. **Monitor hit rate**: Cache warming reduces initial miss rate
7. **Rollback is fast**: Helm rollback in < 5 minutes

### Additional Resources

- [Memcached Documentation](https://memcached.org/)
- [Memcached Release Notes](https://github.com/memcached/memcached/wiki/ReleaseNotes)
- [Memcached Performance Tuning](https://github.com/memcached/memcached/wiki/Performance)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-09
**Tested With**: Memcached 1.6.39, Kubernetes 1.28+, Helm 3.12+
