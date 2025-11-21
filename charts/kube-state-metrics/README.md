# Kube State Metrics Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.10.1](https://img.shields.io/badge/AppVersion-2.10.1-informational?style=flat-square)

Kube State Metrics exposes Kubernetes object state as Prometheus metrics

## Features

- **Comprehensive Monitoring**: Exposes state metrics for all Kubernetes resources
- **Prometheus Integration**: Native Prometheus metrics format
- **ServiceMonitor**: Prometheus Operator support
- **Flexible Collection**: Namespace and resource filtering
- **Low Overhead**: Minimal resource usage (read-only access)
- **RBAC Enabled**: ClusterRole with minimal permissions
- **Operational Tools**: 15+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration (all namespaces, all resources)
helm install my-ksm scripton-charts/kube-state-metrics

# Install with namespace filtering
helm install my-ksm scripton-charts/kube-state-metrics \
  --set 'collectors.namespaces={default,kube-system}'

# Install with production configuration
helm install my-ksm scripton-charts/kube-state-metrics \
  -f values-small-prod.yaml
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- (Optional) Prometheus Operator for ServiceMonitor

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `collectors.namespaces` | Limit to specific namespaces | `[]` (all) |
| `collectors.resources` | Limit to specific resources | `[]` (all) |
| `serviceMonitor.enabled` | Enable ServiceMonitor | `false` |
| `rbac.create` | Create RBAC resources | `true` |

### Available Resources

Pods, Nodes, Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs, Services, Endpoints, Ingresses, PersistentVolumes, PersistentVolumeClaims, ConfigMaps, Secrets, Namespaces, ResourceQuotas, LimitRanges, HorizontalPodAutoscalers, PodDisruptionBudgets, NetworkPolicies, StorageClasses, VolumeAttachments, CertificateSigningRequests, and more.

## Operational Commands

### Basic Operations

```bash
# View logs
make -f make/ops/kube-state-metrics.mk ksm-logs

# Open shell
make -f make/ops/kube-state-metrics.mk ksm-shell

# Restart
make -f make/ops/kube-state-metrics.mk ksm-restart
```

### Health & Status

```bash
# Check status
make -f make/ops/kube-state-metrics.mk ksm-status

# Check version
make -f make/ops/kube-state-metrics.mk ksm-version

# Check health
make -f make/ops/kube-state-metrics.mk ksm-health
```

### Metrics Queries

```bash
# Get all metrics
make -f make/ops/kube-state-metrics.mk ksm-metrics

# Get pod metrics
make -f make/ops/kube-state-metrics.mk ksm-pod-metrics

# Get deployment metrics
make -f make/ops/kube-state-metrics.mk ksm-deployment-metrics

# Get node metrics
make -f make/ops/kube-state-metrics.mk ksm-node-metrics

# Get service metrics
make -f make/ops/kube-state-metrics.mk ksm-service-metrics

# Get persistent volume metrics
make -f make/ops/kube-state-metrics.mk ksm-pv-metrics

# Get namespace metrics
make -f make/ops/kube-state-metrics.mk ksm-namespace-metrics
```

### Resource Status

```bash
# Check pod status metrics
make -f make/ops/kube-state-metrics.mk ksm-pod-status

# Check deployment status metrics
make -f make/ops/kube-state-metrics.mk ksm-deployment-status

# Check node status metrics
make -f make/ops/kube-state-metrics.mk ksm-node-status
```

### Port Forward

```bash
# Port forward metrics endpoint
make -f make/ops/kube-state-metrics.mk ksm-port-forward

# Port forward telemetry endpoint
make -f make/ops/kube-state-metrics.mk ksm-port-forward-telemetry

# Then visit http://localhost:8080/metrics
```

## Configuration Examples

### Monitor Specific Namespaces

```yaml
collectors:
  namespaces:
    - default
    - kube-system
    - production
```

### Monitor Specific Resources

```yaml
collectors:
  resources:
    - pods
    - deployments
    - services
    - nodes
    - persistentvolumeclaims
```

### Add Resource Labels to Metrics

```yaml
extraArgs:
  - --metric-labels-allowlist=pods=[*],deployments=[*],statefulsets=[*]
  - --metric-annotations-allowlist=namespaces=[*]
```

## Integration with Prometheus

### Manual Scraping

Add to Prometheus configuration:

```yaml
scrape_configs:
  - job_name: 'kube-state-metrics'
    static_configs:
      - targets: ['kube-state-metrics.default.svc.cluster.local:8080']
```

### Using ServiceMonitor

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus
```

## Example Metrics

### Pod Metrics

```promql
# Total pods by namespace
count(kube_pod_info) by (namespace)

# Pod status
kube_pod_status_phase{phase="Running"}

# Container restarts
rate(kube_pod_container_status_restarts_total[5m])

# Pod resource requests
kube_pod_container_resource_requests{resource="cpu"}
```

### Deployment Metrics

```promql
# Deployment replicas
kube_deployment_status_replicas

# Available replicas
kube_deployment_status_replicas_available

# Unavailable replicas
kube_deployment_status_replicas_unavailable
```

### Node Metrics

```promql
# Node status
kube_node_status_condition{condition="Ready",status="true"}

# Allocatable resources
kube_node_status_allocatable{resource="cpu"}

# Node info
kube_node_info
```

### Persistent Volume Metrics

```promql
# PV capacity
kube_persistentvolume_capacity_bytes

# PVC requests
kube_persistentvolumeclaim_resource_requests_storage_bytes

# PV status
kube_persistentvolume_status_phase{phase="Bound"}
```

## PromQL Query Examples

```promql
# Pods not in Running state
kube_pod_status_phase{phase!="Running"} == 1

# Deployments with insufficient replicas
kube_deployment_status_replicas_available < kube_deployment_spec_replicas

# Nodes not ready
kube_node_status_condition{condition="Ready",status="false"} == 1

# PVCs in pending state
kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1

# Container CPU requests by namespace
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)

# Total storage requests by namespace
sum(kube_persistentvolumeclaim_resource_requests_storage_bytes) by (namespace)
```

## Grafana Dashboards

Recommended Grafana dashboards for kube-state-metrics:

- **Kubernetes Cluster Monitoring** (ID: 7249)
- **Kubernetes Cluster Overview** (ID: 12117)
- **Kubernetes Resource Requests** (ID: 13332)

Import via: Grafana UI → Dashboards → Import → Enter ID

## Production Setup

```yaml
# values-prod.yaml
replicaCount: 1

rbac:
  create: true

serviceAccount:
  create: true

collectors:
  namespaces: []  # All namespaces
  resources: []   # All resources

extraArgs:
  - --metric-labels-allowlist=pods=[*],deployments=[*],statefulsets=[*]
  - --metric-annotations-allowlist=namespaces=[*]

serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

tolerations:
  - effect: NoSchedule
    operator: Exists

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
                  - kube-state-metrics
          topologyKey: kubernetes.io/hostname

priorityClassName: "system-cluster-critical"
```

## Troubleshooting

### Check Metrics Collection

```bash
make -f make/ops/kube-state-metrics.mk ksm-health
make -f make/ops/kube-state-metrics.mk ksm-metrics | head -20
```

### RBAC Issues

```bash
# Check ClusterRole
kubectl get clusterrole kube-state-metrics

# Check ClusterRoleBinding
kubectl get clusterrolebinding kube-state-metrics

# Check ServiceAccount
kubectl get serviceaccount kube-state-metrics -n <namespace>
```

### High Memory Usage

Reduce the number of monitored resources:

```yaml
collectors:
  resources:
    - pods
    - deployments
    - nodes
```

Or limit to specific namespaces:

```yaml
collectors:
  namespaces:
    - production
    - staging
```

### Missing Metrics

Check if resources are enabled:

```bash
# Get available resources
kubectl api-resources
```

Ensure RBAC has permissions for the resource type.

## Sharding (Large Clusters)

For very large clusters (1000+ nodes), use sharding:

```yaml
# Shard 0
replicaCount: 1
extraArgs:
  - --shard=0
  - --total-shards=3

# Shard 1
replicaCount: 1
extraArgs:
  - --shard=1
  - --total-shards=3

# Shard 2
replicaCount: 1
extraArgs:
  - --shard=2
  - --total-shards=3
```

## License

- Chart: BSD 3-Clause License
- Kube State Metrics: Apache License 2.0

## Additional Resources

- [Kube State Metrics Documentation](https://github.com/kubernetes/kube-state-metrics/tree/main/docs)
- [Metrics Reference](https://github.com/kubernetes/kube-state-metrics/tree/main/docs/README.md)
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Kube State Metrics Version**: 2.10.1
