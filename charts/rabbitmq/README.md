# RabbitMQ Helm Chart

A production-ready Helm chart for deploying [RabbitMQ](https://www.rabbitmq.com/) message broker on Kubernetes with management UI and Prometheus metrics support.

## ⚠️ Production Consideration

**For production environments requiring clustering and high availability**, consider using [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator):

- ✅ Native RabbitMQ clustering support
- ✅ Automatic node recovery
- ✅ CRD-based management
- ✅ Official operator from RabbitMQ team

**This chart is recommended for:**
- Development/testing environments
- Single-node deployments
- Simple message queuing needs
- Configuration-first approach preference

## Overview

RabbitMQ is a widely-used open-source message broker that implements the Advanced Message Queuing Protocol (AMQP). This chart provides a simple, configuration-first approach to deploying RabbitMQ on Kubernetes.

### Features

- ✅ **Configuration-First Design**: Native `rabbitmq.conf` and `enabled_plugins` mounted as ConfigMaps
- ✅ **Management UI**: Built-in web interface for monitoring and management (port 15672)
- ✅ **Prometheus Metrics**: Export metrics via `rabbitmq_prometheus` plugin (port 15692)
- ✅ **Persistent Storage**: PVC support for `/var/lib/rabbitmq` data directory
- ✅ **Security Hardened**: Non-root user, minimal capabilities, configurable secrets
- ✅ **Production-Ready**: Health probes, resource limits, ServiceMonitor support
- ✅ **Simple by Default**: Single-node deployment (clustering deferred to future release)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume provisioner (if persistence is enabled)

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install rabbitmq-home charts/rabbitmq \
  -f charts/rabbitmq/values-home-single.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install rabbitmq-startup charts/rabbitmq \
  -f charts/rabbitmq/values-startup-single.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with multiple replicas and monitoring:

```bash
helm install rabbitmq-prod charts/rabbitmq \
  -f charts/rabbitmq/values-prod-master-replica.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Features:** 3 replicas, pod anti-affinity, HPA, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 20Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#rabbitmq).

## ⚠️ Important: Password Requirement

**The RabbitMQ admin password is mandatory** for both installation and template validation:

```bash
# ❌ This will FAIL (no password provided)
helm template my-rabbitmq ./charts/rabbitmq

# ✅ This will SUCCEED
helm template my-rabbitmq ./charts/rabbitmq \
  --set rabbitmq.admin.password='test-password'

# ✅ Or use existing secret
helm template my-rabbitmq ./charts/rabbitmq \
  --set rabbitmq.admin.existingSecret.enabled=true \
  --set rabbitmq.admin.existingSecret.secretName='my-secret'
```

This is a **security feature by design** - the chart refuses to generate templates without proper credentials configuration.

## Installation

### Add Repository

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

### Install Chart

```bash
# Basic installation with required password
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set rabbitmq.admin.password='your-strong-password'

# Install with custom values file
helm install my-rabbitmq scripton-charts/rabbitmq -f values.yaml
```

### Verify Installation

```bash
# Check deployment status
kubectl get pods -l app.kubernetes.io/name=rabbitmq

# Get admin credentials
kubectl get secret my-rabbitmq -o jsonpath="{.data.username}" | base64 --decode
kubectl get secret my-rabbitmq -o jsonpath="{.data.password}" | base64 --decode

# Access Management UI (port-forward)
kubectl port-forward svc/my-rabbitmq 15672:15672
# Open browser: http://localhost:15672
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of RabbitMQ replicas | `1` |
| `image.repository` | RabbitMQ image repository | `rabbitmq` |
| `image.tag` | RabbitMQ image tag | `3.13.1-management` |
| `rabbitmq.admin.username` | Admin username | `guest` |
| `rabbitmq.admin.password` | Admin password (required) | `""` |
| `rabbitmq.conf` | Native rabbitmq.conf content | See values.yaml |
| `rabbitmq.plugins` | Enabled plugins list | `[rabbitmq_management,...]` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | PVC size | `10Gi` |
| `service.type` | Service type | `ClusterIP` |
| `monitoring.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` |
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget | `false` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |

For all available parameters, see [values.yaml](values.yaml).

### Example Configurations

#### Minimal Production Deployment

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "CHANGE_ME_STRONG_PASSWORD"

persistence:
  enabled: true
  size: 50Gi

resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

#### With Prometheus Monitoring

```yaml
rabbitmq:
  admin:
    password: "your-password"

monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus
```

#### Custom Configuration

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "secure-password"

  conf: |
    listeners.tcp.default = 5672
    management.tcp.port = 15672
    vm_memory_high_watermark.relative = 0.7
    disk_free_limit.absolute = 5GB
    consumer_timeout = 3600000
    heartbeat = 60

  plugins: |
    [rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel].
```

#### High Availability with Autoscaling

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "secure-password"

# Enable autoscaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75

# Ensure minimum availability during maintenance
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Restrict network access
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      ports:
        - protocol: TCP
          port: 5672

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

## Usage

### Accessing RabbitMQ

#### Management UI

```bash
# Port-forward to local machine
kubectl port-forward svc/my-rabbitmq 15672:15672

# Access UI in browser
open http://localhost:15672
```

#### AMQP Connection

**From within the cluster:**
```
Host: my-rabbitmq.default.svc.cluster.local
Port: 5672
Connection string: amqp://USERNAME:PASSWORD@my-rabbitmq.default.svc.cluster.local:5672/
```

**From outside the cluster (port-forward):**
```bash
kubectl port-forward svc/my-rabbitmq 5672:5672

# Connection string
amqp://USERNAME:PASSWORD@localhost:5672/
```

### Common Operations

#### Check Cluster Status

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl cluster_status
```

#### List Queues

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_queues
```

#### List Exchanges

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_exchanges
```

#### Create User and Permissions

```bash
# Create user
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_user myuser mypassword

# Set permissions
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_permissions -p / myuser ".*" ".*" ".*"

# Set user tags (e.g., administrator)
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_user_tags myuser administrator
```

#### Create Virtual Host

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_vhost /my-vhost
```

#### Check Node Health

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-diagnostics ping
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-diagnostics check_running
```

### Makefile Commands

If you're using the chart from the repository:

```bash
# Lint chart
make -f Makefile.rabbitmq.mk lint

# Generate templates
make -f Makefile.rabbitmq.mk template

# Install chart
make -f Makefile.rabbitmq.mk install

# Check RabbitMQ status
make -f Makefile.rabbitmq.mk rmq-status

# List queues
make -f Makefile.rabbitmq.mk rmq-list-queues

# Open shell in pod
make -f Makefile.rabbitmq.mk rmq-shell

# Tail logs
make -f Makefile.rabbitmq.mk rmq-logs
```

## Persistence

RabbitMQ requires persistent storage for queue data and node metadata. By default, a 10Gi PVC is created and mounted at `/var/lib/rabbitmq`.

### Using Existing PVC

```yaml
persistence:
  enabled: true
  existingClaim: "my-existing-pvc"
```

### Disable Persistence (Not Recommended for Production)

```yaml
persistence:
  enabled: false
```

⚠️ **Warning**: Disabling persistence will cause data loss when the pod is terminated.

## Security

### Credentials Management

**Option 1: Set password in values.yaml (default)**
```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "your-password"
```

**Option 2: Use existing secret**
```yaml
rabbitmq:
  admin:
    existingSecret:
      enabled: true
      secretName: "my-rabbitmq-secret"
      usernameKey: "username"
      passwordKey: "password"
```

Create the secret:
```bash
kubectl create secret generic my-rabbitmq-secret \
  --from-literal=username=admin \
  --from-literal=password='your-strong-password'
```

### Security Context

The chart runs RabbitMQ as non-root user (UID 999) with minimal capabilities:

```yaml
securityContext:
  runAsUser: 999
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

## Monitoring

### Prometheus Metrics

RabbitMQ exposes metrics via the `rabbitmq_prometheus` plugin on port 15692.

#### Enable ServiceMonitor (Prometheus Operator)

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus
```

#### Manual Scraping

If not using Prometheus Operator, configure scrape target:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['my-rabbitmq.default.svc.cluster.local:15692']
```

### Metrics Endpoint

```bash
# Port-forward metrics port
kubectl port-forward svc/my-rabbitmq 15692:15692

# Fetch metrics
curl http://localhost:15692/metrics
```

## Upgrading

### Upgrade Chart

```bash
helm upgrade my-rabbitmq scripton-charts/rabbitmq -f values.yaml
```

### Rollback

```bash
helm rollback my-rabbitmq
```

## Uninstallation

```bash
# Uninstall chart
helm uninstall my-rabbitmq

# Optional: Delete PVC (data will be lost)
kubectl delete pvc my-rabbitmq
```

## Troubleshooting

### Pod Not Starting

Check pod events and logs:
```bash
kubectl describe pod -l app.kubernetes.io/name=rabbitmq
kubectl logs -l app.kubernetes.io/name=rabbitmq
```

### Permission Denied Errors

Ensure PVC permissions match `fsGroup: 999`:
```yaml
podSecurityContext:
  fsGroup: 999
```

### Memory Issues

Adjust memory limits and RabbitMQ memory threshold:
```yaml
resources:
  limits:
    memory: 2Gi

rabbitmq:
  conf: |
    vm_memory_high_watermark.relative = 0.6
```

### Connection Refused

Verify service and endpoints:
```bash
kubectl get svc my-rabbitmq
kubectl get endpoints my-rabbitmq
```

## Limitations

- **Single-node only**: Clustering is not yet supported in this release
- **No TLS/SSL**: AMQP+SSL configuration must be added manually via `extraEnv`
- **No federation/shovel**: Advanced plugins can be enabled via `rabbitmq.plugins`

## Roadmap

- [ ] StatefulSet support for multi-node clustering
- [ ] Built-in TLS/SSL configuration
- [ ] Federation and shovel plugin configuration
- [ ] LoadDefinitions support for auto-configuration
- [ ] HorizontalPodAutoscaler examples

## License

This Helm chart is licensed under the **BSD-3-Clause License**.

RabbitMQ itself is licensed under the **Mozilla Public License 2.0 (MPL 2.0)**. See [RabbitMQ License](https://www.rabbitmq.com/mpl.html) for details.

## Contributing

Contributions are welcome! Please submit issues and pull requests to the [GitHub repository](https://github.com/scriptonbasestar-container/sb-helm-charts).

## Resources

- [RabbitMQ Official Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Configuration Reference](https://www.rabbitmq.com/configure.html)
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)
- [RabbitMQ Prometheus Plugin](https://www.rabbitmq.com/prometheus.html)
- [AMQP 0-9-1 Reference](https://www.rabbitmq.com/amqp-0-9-1-reference.html)
