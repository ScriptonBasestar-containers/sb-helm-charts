# Devpi Helm Chart

Production-ready Devpi PyPI server deployment on Kubernetes for Python package management and caching.

## Features

- **Devpi Server**: Private PyPI server with package caching
- **Persistent Storage**: Volume for package data
- **Scalable**: HorizontalPodAutoscaler support
- **Production Ready**: Health probes, resource limits, and monitoring
- **Secure**: NetworkPolicy and PodDisruptionBudget support

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install devpi-home charts/devpi \
  -f charts/devpi/values-home-single.yaml
```

**Resource allocation:** 50-250m CPU, 128-256Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install devpi-startup charts/devpi \
  -f charts/devpi/values-startup-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with PostgreSQL and monitoring:

```bash
helm install devpi-prod charts/devpi \
  -f charts/devpi/values-prod-master-replica.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Features:** PostgreSQL backend, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 20Gi storage

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#devpi).


- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume support (for package persistence)

## Quick Start

### Install the Chart

```bash
helm install devpi ./charts/devpi
```

### Access the Service

```bash
# Port-forward to access locally
kubectl port-forward svc/devpi 3141:3141

# Test the service
curl http://localhost:3141/
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `ghcr.io/scriptonbasestar-containers/devpi/pypi` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `Always` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `3141` |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.storageClass` | Storage class | `""` (default) |
| `persistence.accessMode` | Access mode | `ReadWriteOnce` |
| `persistence.size` | Volume size | `8Gi` |

### Health Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe` | Liveness probe configuration | HTTP GET / on port 3141 |
| `readinessProbe` | Readiness probe configuration | HTTP GET / on port 3141 |
| `startupProbe` | Startup probe configuration | HTTP GET / on port 3141 |

### Resources

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Production Features

### HorizontalPodAutoscaler

Automatically scale pods based on CPU usage:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

**Benefits:**
- Handles high package download traffic
- Scales down during low usage
- Ensures consistent performance

### PodDisruptionBudget

Ensures minimum availability during cluster maintenance:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

**Benefits:**
- Prevents service outage during node maintenance
- Controls pod eviction rate
- Improves reliability

### NetworkPolicy

Restricts network access for enhanced security:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: default
      ports:
        - protocol: TCP
          port: 3141
```

**Benefits:**
- Zero-trust network security
- Prevents unauthorized access
- Compliance with security best practices

**Requirements:**
- CNI plugin with NetworkPolicy support (Calico, Cilium, etc.)

### ServiceMonitor

Enable Prometheus metrics collection:

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    path: /
    interval: 30s
    scrapeTimeout: 10s
```

**Benefits:**
- Real-time performance visibility
- Package download metrics
- Integration with alerting systems

**Requirements:**
- Prometheus Operator installed
- ServiceMonitor CRD available

## Usage Examples

### Configure pip to use Devpi

```bash
# Set devpi as default index
pip config set global.index-url http://devpi:3141/root/pypi/+simple/

# Or use environment variable
export PIP_INDEX_URL=http://devpi:3141/root/pypi/+simple/
```

### Upload packages to Devpi

```bash
# Install devpi-client
pip install devpi-client

# Login to devpi
devpi use http://devpi:3141
devpi login root --password=<password>

# Upload package
devpi upload
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=devpi
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Test Connection

```bash
kubectl port-forward svc/devpi 3141:3141
curl http://localhost:3141/
```

### Access Devpi Web Interface

```bash
kubectl port-forward svc/devpi 3141:3141
# Open browser: http://localhost:3141/
```

## License

This Helm chart is provided as-is under the MIT License.

## Support

- Devpi Documentation: https://devpi.net/
- GitHub Issues: https://github.com/devpi/devpi/issues
