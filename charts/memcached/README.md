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
