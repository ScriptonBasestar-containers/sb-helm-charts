# Memcached Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/memcached)

[Memcached](https://memcached.org/) is a high-performance, distributed memory object caching system, generic in nature, but intended for use in speeding up dynamic web applications by alleviating database load.

## ⚠️ Production Consideration

**For production environments requiring advanced management**, consider using [Memcached Operator](https://github.com/ianlewis/memcached-operator):

- ✅ Automated cluster management
- ✅ CRD-based configuration
- ✅ Declarative deployment model
- ✅ Kubernetes-native management

**This chart is recommended for:**
- Development/testing environments
- Simple caching needs
- Single or few-replica deployments
- Minimal operational overhead

## Features

- ✅ Deployment-based for horizontal scaling
- ✅ Simple command-line configuration
- ✅ No database required (pure cache)
- ✅ Liveness and readiness probes
- ✅ Resource limits and requests
- ✅ Security context (non-root user, read-only filesystem)
- ✅ Horizontal Pod Autoscaling (optional)
- ✅ Pod Disruption Budget for HA
- ✅ Network Policy support
- ✅ ServiceMonitor for Prometheus Operator

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install memcached-home charts/memcached \
  -f charts/memcached/values-home-single.yaml
```

**Resource allocation:** 50-250m CPU, 128-256Mi RAM, 128MB cache

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install memcached-startup charts/memcached \
  -f charts/memcached/values-startup-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 256MB cache

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with multiple replicas and auto-scaling:

```bash
helm install memcached-prod charts/memcached \
  -f charts/memcached/values-prod-master-replica.yaml
```

**Features:** 3 replicas, pod anti-affinity, HPA (3-10 pods), PodDisruptionBudget

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 512MB cache per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#memcached).

## Installation

### 1. Basic Installation

```bash
helm install my-memcached ./charts/memcached
```

### 2. Custom Configuration

Create a `my-values.yaml` file:

```yaml
memcached:
  maxMemory: 512
  maxConnections: 2048

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

Install with custom values:

```bash
helm install my-memcached ./charts/memcached -f my-values.yaml
```

### 3. Production Deployment

See `values-example.yaml` for production-ready configuration with:
- Multiple replicas
- Resource limits
- Pod anti-affinity
- Autoscaling enabled
- Network policies

```bash
helm install my-memcached ./charts/memcached -f values-example.yaml
```

## Configuration

### Memcached Settings

The chart configures memcached via command-line arguments:

```yaml
memcached:
  # Maximum memory to use for object storage (in megabytes)
  maxMemory: 256
  # Maximum number of simultaneous connections
  maxConnections: 1024
  # Chunk size growth factor (1.25 is default)
  chunkSizeGrowthFactor: 1.25
  # Minimum space allocated for key+value+flags
  minItemSize: 48
  # Enable or disable CAS (Check and Set) operations
  enableCas: true
  # Verbose logging (0=disabled, 1=enabled, 2=very verbose)
  verbosity: 0
  # Additional command-line arguments
  extraArgs:
    - "-o"
    - "modern"
```

### High Availability

Enable autoscaling and pod disruption budget:

```yaml
replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

podDisruptionBudget:
  enabled: true
  minAvailable: 2

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - memcached
        topologyKey: kubernetes.io/hostname
```

### Network Policy

Restrict network access:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: myapp
      ports:
      - protocol: TCP
        port: 11211
```

### Monitoring

Enable Prometheus metrics collection:

```yaml
serviceMonitor:
  enabled: true
  namespace: monitoring
  interval: 30s
  scrapeTimeout: 10s
  labels:
    prometheus: kube-prometheus
```

## Common Operations

### Using Makefile Commands

The chart includes a Makefile with common operations:

```bash
# Show statistics
make -f Makefile.memcached.mk mc-stats

# Check version
make -f Makefile.memcached.mk mc-version

# View settings
make -f Makefile.memcached.mk mc-settings

# View slab statistics
make -f Makefile.memcached.mk mc-slabs

# View item statistics
make -f Makefile.memcached.mk mc-items

# Port forward to memcached
make -f Makefile.memcached.mk mc-port-forward

# Flush all data (WARNING: clears all cached data)
make -f Makefile.memcached.mk mc-flush
```

### Manual Operations

Connect to memcached manually:

```bash
# Port forward
kubectl port-forward -n default svc/my-memcached 11211:11211

# Test connection
echo "stats" | nc localhost 11211

# Set a key
echo "set mykey 0 3600 5\r\nhello" | nc localhost 11211

# Get a key
echo "get mykey" | nc localhost 11211

# Flush all data
echo "flush_all" | nc localhost 11211
```

## Architecture

### Deployment Strategy

Memcached is deployed as a Deployment (not StatefulSet) because:
- Each memcached instance is independent
- No data persistence required (cache only)
- Easy horizontal scaling
- Client-side hashing handles distribution

### Security

- Runs as non-root user (UID 11211)
- Read-only root filesystem
- All capabilities dropped
- Privilege escalation disabled
- `/tmp` mounted as emptyDir for temporary files

### Resource Management

Default resource allocation:

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Adjust based on your workload. Memory limit should be higher than `maxMemory` setting to account for overhead.

## Troubleshooting

### Check pod status

```bash
kubectl get pods -l app.kubernetes.io/name=memcached
```

### View logs

```bash
kubectl logs -l app.kubernetes.io/name=memcached
```

### Test connection

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inside the pod:
nc -zv my-memcached 11211
echo "stats" | nc my-memcached 11211
```

### Common issues

**Pod fails to start:**
- Check resource limits vs maxMemory setting
- Verify securityContext compatibility with your cluster

**High memory usage:**
- Adjust `maxMemory` setting
- Check slab statistics: `make -f Makefile.memcached.mk mc-slabs`
- Consider item eviction policy

**Connection refused:**
- Verify service exists: `kubectl get svc my-memcached`
- Check network policies
- Verify firewall rules

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of memcached replicas | `1` |
| `image.repository` | Memcached image repository | `memcached` |
| `image.tag` | Memcached image tag | `1.6.32` |
| `memcached.maxMemory` | Maximum memory (MB) | `256` |
| `memcached.maxConnections` | Maximum connections | `1024` |
| `memcached.chunkSizeGrowthFactor` | Chunk growth factor | `1.25` |
| `memcached.minItemSize` | Minimum item size (bytes) | `48` |
| `memcached.enableCas` | Enable CAS operations | `true` |
| `memcached.verbosity` | Logging verbosity (0-3) | `0` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `podDisruptionBudget.enabled` | Enable PDB | `false` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `serviceMonitor.enabled` | Enable ServiceMonitor | `false` |

See `values.yaml` for full parameter list.

---

## Backup & Recovery

### Backup Strategy

Memcached is a **stateless in-memory cache** with **no data persistence**. Backup focuses on configuration and infrastructure, not cache data.

**Backup Components** (2 total):

| Component | Priority | Size | Method |
|-----------|----------|------|--------|
| **Configuration** | Critical | <5 KB | ConfigMap export |
| **Kubernetes Manifests** | Important | <10 KB | Helm values |

**Recovery Objectives**:
- **RTO**: < 15 minutes
- **RPO**: 0 (cache is ephemeral, no data loss)

### Quick Backup Commands

```bash
# 1. Backup Configuration (ConfigMap)
kubectl get configmap -n default my-memcached -o yaml > memcached-config-backup.yaml

# 2. Backup Helm Values
helm get values my-memcached -n default > memcached-values-backup.yaml

# 3. Full Infrastructure Backup
BACKUP_DIR="memcached-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
kubectl get configmap -n default my-memcached -o yaml > $BACKUP_DIR/config.yaml
helm get values my-memcached -n default > $BACKUP_DIR/values.yaml
kubectl get all,pdb,networkpolicy -n default -l app.kubernetes.io/name=memcached -o yaml > $BACKUP_DIR/k8s-resources.yaml
```

### Recovery Procedures

#### Configuration-Only Recovery

Restore configuration after accidental changes:

```bash
# Restore configuration
kubectl apply -f memcached-config-backup.yaml

# Restart pods to apply new configuration
kubectl rollout restart deployment/my-memcached -n default
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=120s

# Verify
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats settings\r\nquit\r" | nc localhost 11211'
```

#### Full Cluster Recreation

Complete recovery for cluster failure:

```bash
# Reinstall Memcached
helm install my-memcached scripton-charts/memcached \
  -f memcached-values-backup.yaml \
  -n default

# Wait for deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=300s

# Test functionality
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211'
```

### Best Practices

1. **Git-Based Configuration**: Store `values.yaml` in Git repository for version control
2. **Daily Configuration Backups**: Backup ConfigMap daily or before every change
3. **Off-Cluster Storage**: Store backups in S3/MinIO or remote Git repository
4. **Quarterly DR Drills**: Practice full cluster recovery procedures
5. **Cache Warming**: Implement cache warming strategy after recovery to reduce initial cache miss rate

**Detailed Guide**: See [docs/memcached-backup-guide.md](../../docs/memcached-backup-guide.md) for comprehensive backup procedures, automation examples, and disaster recovery workflows.

---

## Security & RBAC

### RBAC Configuration

The chart creates **namespace-scoped RBAC** resources for Memcached operations:

```yaml
rbac:
  create: true  # Enable RBAC resources
  annotations: {}
```

**Resources Created**:
- **Role**: Read-only access to ConfigMaps, Secrets, Pods, Services, Endpoints
- **RoleBinding**: Binds ServiceAccount to Role

**Permissions Granted**:
- `get`, `list`, `watch` on ConfigMaps (for configuration)
- `get`, `list`, `watch` on Secrets (for credentials if needed)
- `get`, `list`, `watch` on Pods (for health checks)
- `get`, `list`, `watch` on Services/Endpoints (for service discovery)

### ServiceAccount

```yaml
serviceAccount:
  create: true
  name: ""  # Auto-generated if empty
  annotations: {}
```

### Security Context

**Pod-level security** (runs as non-root user 11211):

```yaml
podSecurityContext:
  fsGroup: 11211
  runAsUser: 11211
  runAsGroup: 11211
  runAsNonRoot: true

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 11211
  allowPrivilegeEscalation: false
```

### Network Security

**NetworkPolicy Example** (restrict ingress to application pods only):

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: my-app  # Only allow from application pods
      ports:
        - protocol: TCP
          port: 11211
```

### Best Practices

1. **Least Privilege**: Use read-only RBAC permissions
2. **Network Policies**: Restrict ingress to application pods only
3. **Pod Security Standards**: Enforce restricted pod security policy
4. **Non-Root User**: Always run as user 11211 (never root)
5. **Read-Only Filesystem**: Prevent unauthorized file modifications

---

## Upgrading

### Pre-Upgrade Checklist

Before upgrading Memcached:

- [ ] **Review Release Notes**: Check [Memcached releases](https://github.com/memcached/memcached/wiki/ReleaseNotes) for breaking changes
- [ ] **Backup Configuration**: Export current ConfigMap and Helm values
- [ ] **Check Client Compatibility**: Ensure application clients support new version
- [ ] **Test in Non-Production**: Validate upgrade in dev/staging environment
- [ ] **Plan for Cache Miss**: Applications must handle cache misses after upgrade

**Note**: Cache data is **ephemeral and will be lost** during upgrade (expected behavior).

### Quick Upgrade (Patch Versions)

**Example: 1.6.38 → 1.6.39 (patch upgrade)**

```bash
# 1. Backup configuration
helm get values my-memcached -n default > memcached-values-backup.yaml

# 2. Upgrade via Helm
helm upgrade my-memcached scripton-charts/memcached \
  --set image.tag=1.6.39-alpine3.22 \
  -n default \
  --wait

# 3. Verify upgrade
kubectl rollout status deployment/my-memcached -n default
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- memcached -V
```

### Upgrade Strategies

#### 1. Rolling Update (Recommended)

**Best For**: Production environments, multi-replica deployments

**Downtime**: None (brief cache misses during pod restarts)

```bash
# Upgrade with PodDisruptionBudget for HA
helm upgrade my-memcached scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  --set replicaCount=3 \
  --set podDisruptionBudget.enabled=true \
  --set podDisruptionBudget.minAvailable=2 \
  -n default \
  --wait

# Monitor rollout
kubectl rollout status deployment/my-memcached -n default

# Verify all pods running new version
kubectl get pods -n default -l app.kubernetes.io/name=memcached -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```

#### 2. Blue-Green Deployment

**Best For**: Zero-downtime requirements, critical cache workloads

**Downtime**: None (traffic switch only)

```bash
# 1. Deploy new version (green)
helm install my-memcached-green scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  --set fullnameOverride=memcached-green \
  -n default

# 2. Wait for green deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached-green -n default --timeout=300s

# 3. Update application to use green service
# (Update application ConfigMap or environment variables)

# 4. Remove blue deployment
helm uninstall my-memcached -n default
```

#### 3. Maintenance Window

**Best For**: Single-replica deployments, non-critical environments

**Downtime**: 2-5 minutes (complete restart)

```bash
# Uninstall old version
helm uninstall my-memcached -n default

# Install new version
helm install my-memcached scripton-charts/memcached \
  --version 0.4.0 \
  --set image.tag=1.6.39-alpine3.22 \
  -f memcached-values-backup.yaml \
  -n default
```

### Version-Specific Notes

#### Memcached 1.6.x

**Current LTS**: Maintained with security updates and bug fixes

**Key Features**:
- TLS support (1.6.10+)
- Improved slab allocator
- Modern memory allocator (`-o modern`)

**Recommended Configuration**:
```yaml
memcached:
  extraArgs:
    - "-o modern"              # Modern memory allocator
    - "-o hashpower=20"        # Larger hash table
    - "-o tail_repair_time=0"  # Disable tail repair for performance
```

#### Memcached 1.5.x → 1.6.x

**Breaking Changes**:
- Default hash table size increased (2^16 → 2^20 buckets)
- Slab allocator improvements (lower memory overhead)

**Migration**: Use rolling update strategy, test in non-production first

### Post-Upgrade Validation

```bash
# Automated validation
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')

# Check version
kubectl exec -n default $POD -- memcached -V

# Test cache operations
kubectl exec -n default $POD -- sh -c 'echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211'

# Check stats
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211' | grep -E "version|uptime|curr_connections"
```

### Rollback Procedures

#### Helm Rollback

```bash
# List release history
helm history my-memcached -n default

# Rollback to previous revision
helm rollback my-memcached -n default

# Verify rollback
kubectl rollout status deployment/my-memcached -n default
```

### Troubleshooting

**Issue**: Pod CrashLoopBackOff after upgrade

**Solution**:
```bash
# Check logs
kubectl logs -n default my-memcached-xxx

# Common causes:
# 1. Invalid command-line arguments (check extraArgs)
# 2. Insufficient memory (increase resources.limits.memory)
# 3. Port conflict (ensure port 11211 is available)
```

**Issue**: High cache miss rate after upgrade

**Expected Behavior**: Cache is empty after pod restart (normal for stateless cache)

**Solution**: Implement cache warming strategy or wait for natural cache population (1-4 hours)

### Best Practices

1. **Version Management**: Stay on latest patch version of 1.6.x series
2. **GitOps Workflow**: Store values.yaml in Git, use ArgoCD/Flux
3. **Rolling Updates**: Use PodDisruptionBudget with `minAvailable: 2` for HA
4. **Monitoring**: Track cache hit rate during and after upgrade
5. **Testing**: Always test upgrades in non-production first
6. **Cache Warming**: Plan for cache repopulation after upgrade

**Detailed Guide**: See [docs/memcached-upgrade-guide.md](../../docs/memcached-upgrade-guide.md) for comprehensive upgrade procedures, version-specific notes, and advanced rollback strategies.

---

## Recent Changes

### Version 0.3.2 (2025-11-17)

**Health Probe Improvements:**
- ✅ Improved readinessProbe to use application-level check (`stats` command)
- ✅ Replaced TCP socket check with memcached stats validation for better health detection
- ✅ Now validates actual memcached functionality instead of just port availability

### Version 0.3.1 (2025-11-17)

**Documentation:**
- ✅ Clarified architecture in `values-prod-master-replica.yaml`
- ✅ Added comprehensive explanation about independent instances (no replication)
- ✅ Added guidance on client-side consistent hashing for distributed cache

For full changelog, see [Chart.yaml](./Chart.yaml) or [docs/05-chart-analysis-2025-11.md](../../docs/05-chart-analysis-2025-11.md).

## Testing

For comprehensive testing scenarios, see [Testing Guide](../../docs/TESTING_GUIDE.md).

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

This Helm chart is licensed under the BSD-3-Clause License. See the chart's `Chart.yaml` for details.

Memcached itself is licensed under the BSD-3-Clause License.

## References

- [Memcached Official Site](https://memcached.org/)
- [Memcached GitHub](https://github.com/memcached/memcached)
- [Memcached Documentation](https://github.com/memcached/memcached/wiki)
- [Docker Hub: memcached](https://hub.docker.com/_/memcached)
