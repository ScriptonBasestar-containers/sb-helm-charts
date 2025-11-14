# RSSHub Helm Chart

Production-ready RSSHub deployment on Kubernetes for generating RSS feeds from various sources.

## 💡 Alternative: All-in-One Chart

**For quick setup with Redis and Puppeteer included**, consider using [NaturalSelectionLabs RSSHub Chart](https://github.com/NaturalSelectionLabs/helm-charts/tree/main/charts/rsshub):

```bash
helm repo add nsl https://naturalselectionlabs.github.io/helm-charts
helm install rsshub nsl/rsshub
```

**NSL Chart includes:**
- ✅ Built-in Redis caching
- ✅ Built-in Puppeteer (browserless/chrome)
- ✅ Single-chart deployment

**This chart is recommended for:**
- Production environments requiring component isolation
- Custom Redis configuration (Redis Operator)
- Independent scaling of RSSHub, Redis, and Puppeteer
- Integration with existing infrastructure

See [Chart Comparison Guide](../../docs/04-rsshub-chart-comparison.md) for detailed analysis and migration instructions.

## Features

- **RSSHub**: Everything is RSSable - generate RSS feeds for websites
- **Scalable**: HorizontalPodAutoscaler support
- **Production Ready**: Health probes, resource limits, and monitoring
- **Secure**: NetworkPolicy and PodDisruptionBudget support
- **Easy Configuration**: Simple values-based configuration

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Quick Start

### Install the Chart

```bash
helm install rsshub ./charts/rsshub
```

### Access the Service

```bash
# Port-forward to access locally
kubectl port-forward svc/rsshub 1200:1200

# Test the service
curl http://localhost:1200/
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `diygod/rsshub` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.appPort` | Application port | `1200` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `256Mi` |

### Health Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe` | Liveness probe configuration | HTTP GET /healthz on port 1200 |
| `readinessProbe` | Readiness probe configuration | HTTP GET /healthz on port 1200 |
| `startupProbe` | Startup probe configuration | HTTP GET /healthz on port 1200 |

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
- Handles high RSS feed request traffic
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
          port: 1200
  egress:
    # Allow all egress (RSSHub needs to fetch external feeds)
    - {}
```

**Benefits:**
- Zero-trust network security
- Controlled ingress access
- Full egress for feed fetching

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
- Feed request metrics
- Integration with alerting systems

**Requirements:**
- Prometheus Operator installed
- ServiceMonitor CRD available

## Usage Examples

### Access RSS Feeds

```bash
# GitHub trending
curl http://rsshub:1200/github/trending/daily

# Twitter user timeline
curl http://rsshub:1200/twitter/user/DIYgod

# YouTube channel
curl http://rsshub:1200/youtube/user/@LinusTechTips
```

### Configure with Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: rsshub.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: rsshub-tls
      hosts:
        - rsshub.example.com
```

### Environment Variables

RSSHub supports many environment variables for configuration. Add them using `extraEnv`:

```yaml
# In values.yaml
extraEnv:
  - name: CACHE_TYPE
    value: "redis"
  - name: REDIS_URL
    value: "redis://redis:6379/"
  - name: PUPPETEER_WS_ENDPOINT
    value: "ws://browserless:3000"
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=rsshub
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Test Connection

```bash
kubectl port-forward svc/rsshub 1200:1200
curl http://localhost:1200/healthz
```

### Common Issues

**High Memory Usage:**
- Increase `resources.limits.memory`
- Enable Redis caching with `CACHE_TYPE=redis`
- Reduce concurrent feed fetching

**Slow Feed Generation:**
- Check external website availability
- Configure Puppeteer for JavaScript rendering
- Increase CPU resources

## License

This Helm chart is provided as-is under the MIT License.

## Support

- RSSHub Documentation: https://docs.rsshub.app/
- GitHub Issues: https://github.com/DIYgod/RSSHub/issues
- Routes Documentation: https://docs.rsshub.app/routes/
