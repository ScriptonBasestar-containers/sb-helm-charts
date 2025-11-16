# Browserless Chrome Helm Chart

Production-ready Browserless Chrome deployment on Kubernetes for headless browser automation and web scraping.

## Features

- **Browserless Chrome**: Headless Chrome with Puppeteer support
- **Scalable**: HorizontalPodAutoscaler support
- **Production Ready**: Health probes, resource limits, and monitoring
- **Secure**: NetworkPolicy and PodDisruptionBudget support
- **Easy Configuration**: Simple values-based configuration

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install browserless-home charts/browserless-chrome \
  -f charts/browserless-chrome/values-home-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, no persistence

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install browserless-startup charts/browserless-chrome \
  -f charts/browserless-chrome/values-startup-single.yaml
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, no persistence

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with auto-scaling and enhanced reliability:

```bash
helm install browserless-prod charts/browserless-chrome \
  -f charts/browserless-chrome/values-prod-master-replica.yaml
```

**Features:** 3 replicas, HPA (3-10 pods), PodDisruptionBudget, NetworkPolicy

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM per pod, no persistence

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#browserless-chrome).


- Kubernetes 1.19+
- Helm 3.0+

## Quick Start

### Install the Chart

```bash
helm install browserless-chrome ./charts/browserless-chrome
```

### Access the Service

```bash
# Port-forward to access locally
kubectl port-forward svc/browserless-chrome 3000:3000

# Test the service
curl http://localhost:3000/
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `ghcr.io/browserless/chrome` |
| `image.tag` | Container image tag | `1.61.1-puppeteer-21.4.1` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `3000` |

### Environment Variables

| Parameter | Description | Default |
|-----------|-------------|---------|
| `envs.CONCURRENT` | Max concurrent sessions | `10` |
| `envs.TOKEN` | API authentication token | `change_it_random_string` |

### Health Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe` | Liveness probe configuration | HTTP GET / on port 3000 |
| `readinessProbe` | Readiness probe configuration | HTTP GET / on port 3000 |
| `startupProbe` | Startup probe configuration | HTTP GET / on port 3000 |

### Resources

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

## Production Features

### HorizontalPodAutoscaler

Automatically scale pods based on CPU and memory usage:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

**Benefits:**
- Handles traffic spikes automatically
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
- Prevents complete service outage during maintenance
- Controls pod eviction rate
- Improves service reliability

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
          port: 3000
```

**Benefits:**
- Zero-trust network security
- Prevents lateral movement
- Compliance with security best practices

**Requirements:**
- CNI plugin with NetworkPolicy support (Calico, Cilium, etc.)

### ServiceMonitor

Enable Prometheus metrics collection:

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

**Benefits:**
- Real-time performance visibility
- Historical data for capacity planning
- Integration with alerting systems

**Requirements:**
- Prometheus Operator installed
- ServiceMonitor CRD available

## Usage Examples

### Basic Puppeteer Usage

```javascript
const puppeteer = require('puppeteer');

const browser = await puppeteer.connect({
  browserWSEndpoint: 'ws://browserless-chrome:3000?token=change_it_random_string',
});

const page = await browser.newPage();
await page.goto('https://example.com');
const title = await page.title();
console.log(title);

await browser.close();
```

### With Authentication Token

Set a secure token in values.yaml:

```yaml
envs:
  TOKEN: your-secure-random-token-here
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=browserless-chrome
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Test Connection

```bash
kubectl port-forward svc/browserless-chrome 3000:3000
curl http://localhost:3000/
```

## License

This Helm chart is provided as-is under the MIT License.

## Support

- Browserless Documentation: https://docs.browserless.io/
- GitHub Issues: https://github.com/browserless/chrome/issues
