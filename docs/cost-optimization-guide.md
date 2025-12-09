# Cost Optimization Guide

**Version**: v1.4.0
**Last Updated**: 2025-12-09
**Scope**: Cost optimization strategies for Kubernetes and Helm chart deployments

## Table of Contents

1. [Overview](#overview)
2. [Resource Usage Tracking](#resource-usage-tracking)
3. [Cost Allocation](#cost-allocation)
4. [Compute Cost Optimization](#compute-cost-optimization)
5. [Storage Cost Optimization](#storage-cost-optimization)
6. [Network Cost Optimization](#network-cost-optimization)
7. [Autoscaling for Cost Efficiency](#autoscaling-for-cost-efficiency)
8. [FinOps Best Practices](#finops-best-practices)
9. [Cost Monitoring & Alerting](#cost-monitoring--alerting)
10. [Optimization Checklists](#optimization-checklists)

---

## Overview

### Purpose

This guide provides comprehensive cost optimization strategies for Kubernetes deployments using ScriptonBasestar Helm charts, covering resource tracking, cost allocation, and FinOps best practices.

### Cost Optimization Pillars

| Pillar | Description | Impact |
|--------|-------------|--------|
| **Right-Sizing** | Match resources to actual workload needs | 20-40% savings |
| **Spot/Preemptible** | Use discounted compute for fault-tolerant workloads | 60-90% savings |
| **Reserved Capacity** | Commit to long-term usage for stable workloads | 30-50% savings |
| **Autoscaling** | Scale resources based on demand | 15-30% savings |
| **Storage Tiering** | Match storage class to data access patterns | 40-70% savings |
| **Idle Resource Cleanup** | Remove unused resources | 10-20% savings |

### Cost Breakdown by Resource Type

Typical Kubernetes cost distribution:

```
┌─────────────────────────────────────────────────────────────┐
│                    Cost Distribution                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Compute (CPU/Memory)  ████████████████████████  55-65%    │
│   Storage (PVCs)        ████████████             20-30%     │
│   Network (Egress)      ████                     5-10%      │
│   Load Balancers        ██                       3-5%       │
│   Other (DNS, etc)      █                        1-3%       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Resource Usage Tracking

### Prometheus Metrics for Cost Tracking

**Key Metrics to Collect**:

```yaml
# Resource usage metrics
container_cpu_usage_seconds_total         # CPU usage
container_memory_working_set_bytes        # Memory usage
container_network_receive_bytes_total     # Network ingress
container_network_transmit_bytes_total    # Network egress
kubelet_volume_stats_used_bytes           # Storage usage

# Resource requests/limits
kube_pod_container_resource_requests      # Requested resources
kube_pod_container_resource_limits        # Resource limits

# Pod lifecycle
kube_pod_status_phase                     # Pod status
kube_pod_container_status_running         # Running containers
```

**ServiceMonitor for kube-state-metrics**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-state-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kube-state-metrics
  endpoints:
    - port: http-metrics
      interval: 30s
      honorLabels: true
```

### Resource Usage Recording Rules

**File**: `prometheus-rules/cost-tracking.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-tracking-rules
  namespace: monitoring
spec:
  groups:
    - name: cost_tracking
      interval: 1m
      rules:
        # CPU usage by namespace (cores)
        - record: namespace:cpu_usage_cores:sum
          expr: |
            sum by (namespace) (
              rate(container_cpu_usage_seconds_total{container!="", pod!=""}[5m])
            )

        # Memory usage by namespace (GB)
        - record: namespace:memory_usage_gb:sum
          expr: |
            sum by (namespace) (
              container_memory_working_set_bytes{container!="", pod!=""}
            ) / 1024 / 1024 / 1024

        # CPU requests by namespace (cores)
        - record: namespace:cpu_requests_cores:sum
          expr: |
            sum by (namespace) (
              kube_pod_container_resource_requests{resource="cpu", unit="core"}
            )

        # Memory requests by namespace (GB)
        - record: namespace:memory_requests_gb:sum
          expr: |
            sum by (namespace) (
              kube_pod_container_resource_requests{resource="memory", unit="byte"}
            ) / 1024 / 1024 / 1024

        # CPU utilization (usage / requests)
        - record: namespace:cpu_utilization:ratio
          expr: |
            namespace:cpu_usage_cores:sum / namespace:cpu_requests_cores:sum

        # Memory utilization (usage / requests)
        - record: namespace:memory_utilization:ratio
          expr: |
            namespace:memory_usage_gb:sum / namespace:memory_requests_gb:sum

        # Storage usage by namespace (GB)
        - record: namespace:storage_usage_gb:sum
          expr: |
            sum by (namespace) (
              kubelet_volume_stats_used_bytes
            ) / 1024 / 1024 / 1024

        # Network egress by namespace (GB/day)
        - record: namespace:network_egress_gb_per_day:sum
          expr: |
            sum by (namespace) (
              rate(container_network_transmit_bytes_total[24h])
            ) * 86400 / 1024 / 1024 / 1024

        # Cost estimate by namespace (hourly rate in USD)
        - record: namespace:estimated_cost_per_hour:sum
          expr: |
            (namespace:cpu_requests_cores:sum * 0.048) +    # $0.048/core/hour
            (namespace:memory_requests_gb:sum * 0.006) +   # $0.006/GB/hour
            (namespace:storage_usage_gb:sum * 0.0001)      # $0.0001/GB/hour
```

### Grafana Dashboard for Cost Tracking

**File**: `grafana-dashboards/cost-tracking.json`

```json
{
  "dashboard": {
    "title": "Kubernetes Cost Tracking",
    "panels": [
      {
        "title": "Monthly Cost Estimate by Namespace",
        "type": "stat",
        "targets": [
          {
            "expr": "sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 720",
            "legendFormat": "{{namespace}}"
          }
        ]
      },
      {
        "title": "Resource Utilization vs Requests",
        "type": "graph",
        "targets": [
          {
            "expr": "namespace:cpu_utilization:ratio",
            "legendFormat": "CPU {{namespace}}"
          },
          {
            "expr": "namespace:memory_utilization:ratio",
            "legendFormat": "Memory {{namespace}}"
          }
        ]
      },
      {
        "title": "Top 10 Expensive Pods",
        "type": "table",
        "targets": [
          {
            "expr": "topk(10, sum by (namespace, pod) (kube_pod_container_resource_requests{resource=\"cpu\"} * 0.048 + kube_pod_container_resource_requests{resource=\"memory\"} / 1024 / 1024 / 1024 * 0.006))",
            "format": "table"
          }
        ]
      },
      {
        "title": "Storage Cost by PVC",
        "type": "piechart",
        "targets": [
          {
            "expr": "sum by (namespace, persistentvolumeclaim) (kubelet_volume_stats_capacity_bytes) / 1024 / 1024 / 1024 * 0.10",
            "legendFormat": "{{namespace}}/{{persistentvolumeclaim}}"
          }
        ]
      }
    ]
  }
}
```

---

## Cost Allocation

### Namespace-Based Cost Allocation

**Strategy**: Allocate costs to namespaces representing teams, projects, or environments.

**Implementation**:

```yaml
# Namespace with cost allocation labels
apiVersion: v1
kind: Namespace
metadata:
  name: team-backend
  labels:
    cost-center: "engineering"
    project: "api-platform"
    environment: "production"
    owner: "backend-team"
```

**Cost Allocation Query**:

```promql
# Monthly cost by cost-center
sum by (cost_center) (
  label_replace(
    namespace:estimated_cost_per_hour:sum * 720,
    "cost_center",
    "$1",
    "namespace",
    ".*"
  )
)
```

### Label-Based Cost Allocation

**Standard Labels for Cost Tracking**:

```yaml
# Pod template with cost allocation labels
metadata:
  labels:
    # Kubernetes recommended labels
    app.kubernetes.io/name: postgresql
    app.kubernetes.io/instance: my-pg
    app.kubernetes.io/component: database

    # Cost allocation labels
    cost-center: "data-platform"
    project: "analytics"
    environment: "production"
    team: "data-engineering"
    budget-code: "BU-DATA-001"
```

**Cost Allocation Report Script**:

```bash
#!/bin/bash
# Generate cost allocation report by labels
# Usage: ./scripts/cost-report.sh [--period monthly|weekly|daily]

PERIOD="${1:-monthly}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus:9090}"

case "${PERIOD}" in
    monthly) HOURS=720 ;;
    weekly) HOURS=168 ;;
    daily) HOURS=24 ;;
esac

echo "Cost Allocation Report - ${PERIOD^}"
echo "================================"
echo ""

# Query cost by namespace
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=sum by (namespace) (namespace:estimated_cost_per_hour:sum) * ${HOURS}" \
  | jq -r '.data.result[] | "\(.metric.namespace): $\(.value[1] | tonumber | floor)"'

echo ""
echo "By Cost Center:"
echo "---------------"

# Query cost by cost-center label
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=sum by (cost_center) (
    kube_namespace_labels{label_cost_center!=\"\"} *
    on(namespace) group_left()
    namespace:estimated_cost_per_hour:sum
  ) * ${HOURS}" \
  | jq -r '.data.result[] | "\(.metric.cost_center): $\(.value[1] | tonumber | floor)"'
```

### Chart-Based Cost Allocation

**Cost per Helm Chart**:

```promql
# Cost by Helm release
sum by (release) (
  label_replace(
    sum by (namespace, pod) (
      kube_pod_container_resource_requests{resource="cpu"} * 0.048 +
      kube_pod_container_resource_requests{resource="memory"} / 1024 / 1024 / 1024 * 0.006
    ),
    "release",
    "$1",
    "pod",
    "(.*)-[a-z0-9]+-[a-z0-9]+"
  )
) * 720  # Monthly
```

**Cost Allocation Matrix**:

| Chart | Tier | Typical Monthly Cost | Cost Drivers |
|-------|------|---------------------|--------------|
| **PostgreSQL** | 1 | $50-500 | CPU, Memory, Storage |
| **MySQL** | 1 | $50-500 | CPU, Memory, Storage |
| **MongoDB** | 1 | $100-800 | CPU, Memory, Storage |
| **Redis** | 1 | $20-200 | Memory |
| **Elasticsearch** | 1 | $200-2000 | CPU, Memory, Storage |
| **Kafka** | 1 | $150-1500 | CPU, Storage, Network |
| **Prometheus** | 2 | $50-500 | CPU, Storage |
| **Grafana** | 2 | $10-100 | CPU, Memory |
| **Loki** | 2 | $100-1000 | Storage |
| **Keycloak** | 2 | $30-300 | CPU, Memory |
| **Nextcloud** | 3 | $50-500 | Storage, CPU |
| **Memcached** | 4 | $10-50 | Memory |

---

## Compute Cost Optimization

### Right-Sizing Resources

**Identify Over-Provisioned Resources**:

```promql
# Pods with CPU utilization < 20% (over-provisioned)
(
  sum by (namespace, pod) (rate(container_cpu_usage_seconds_total[1h]))
  /
  sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})
) < 0.2
and
sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"}) > 0

# Pods with memory utilization < 30% (over-provisioned)
(
  sum by (namespace, pod) (container_memory_working_set_bytes)
  /
  sum by (namespace, pod) (kube_pod_container_resource_requests{resource="memory"})
) < 0.3
and
sum by (namespace, pod) (kube_pod_container_resource_requests{resource="memory"}) > 0
```

**Right-Sizing Recommendations**:

```bash
#!/bin/bash
# Generate right-sizing recommendations
# Usage: ./scripts/right-size-recommendations.sh

PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus:9090}"

echo "Right-Sizing Recommendations"
echo "============================"
echo ""

# Query over-provisioned pods
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=
    topk(20,
      (sum by (namespace, pod) (kube_pod_container_resource_requests{resource=\"cpu\"}) -
       sum by (namespace, pod) (rate(container_cpu_usage_seconds_total[24h])) * 1.3)
    )" \
  | jq -r '.data.result[] | "Pod: \(.metric.namespace)/\(.metric.pod) - Reduce CPU by \(.value[1] | tonumber * 1000 | floor)m"'

echo ""
echo "Potential Monthly Savings:"
echo "--------------------------"

# Calculate potential savings
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=
    sum(
      (sum by (namespace, pod) (kube_pod_container_resource_requests{resource=\"cpu\"}) -
       sum by (namespace, pod) (rate(container_cpu_usage_seconds_total[24h])) * 1.3)
      * 0.048 * 720
    )" \
  | jq -r '"CPU: $\(.data.result[0].value[1] | tonumber | floor)"'
```

### Spot/Preemptible Instances

**Node Affinity for Spot Instances**:

```yaml
# Tolerate spot instance taints
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  template:
    spec:
      # Tolerate spot instance taint
      tolerations:
        - key: "cloud.google.com/gke-spot"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
        - key: "kubernetes.azure.com/scalesetpriority"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"

      # Prefer spot instances
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: "node.kubernetes.io/instance-type"
                    operator: In
                    values:
                      - "spot"
                      - "preemptible"

      # Handle preemption gracefully
      terminationGracePeriodSeconds: 30
```

**Spot Instance Suitability Matrix**:

| Chart | Spot Suitable | Notes |
|-------|---------------|-------|
| **PostgreSQL** | ❌ No | Stateful, data integrity critical |
| **MySQL** | ❌ No | Stateful, data integrity critical |
| **Redis (Standalone)** | ❌ No | Data loss on termination |
| **Redis (Cluster)** | ⚠️ Partial | Only for replicas |
| **Kafka (Broker)** | ⚠️ Partial | Only with replication factor 3+ |
| **Prometheus** | ⚠️ Partial | Needs persistent storage |
| **Grafana** | ✅ Yes | Stateless after SQLite export |
| **Keycloak** | ✅ Yes | Stateless with external DB |
| **Nextcloud** | ⚠️ Partial | Needs graceful shutdown |
| **Airflow (Worker)** | ✅ Yes | Workers are ephemeral |
| **Memcached** | ✅ Yes | Ephemeral cache |
| **Batch Jobs** | ✅ Yes | Designed for interruption |

**Spot Instance Helm Values**:

```yaml
# values-spot.yaml for Grafana
tolerations:
  - key: "cloud.google.com/gke-spot"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"

affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: "cloud.google.com/gke-spot"
              operator: In
              values:
                - "true"

# PodDisruptionBudget for graceful handling
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

### Reserved Capacity Planning

**Identify Stable Workloads for Reserved Instances**:

```promql
# Workloads with consistent resource usage (low variance) - good for reserved capacity
(
  stddev_over_time(sum by (namespace, pod) (rate(container_cpu_usage_seconds_total[1h]))[7d:1h])
  /
  avg_over_time(sum by (namespace, pod) (rate(container_cpu_usage_seconds_total[1h]))[7d:1h])
) < 0.2
```

**Reserved Capacity Recommendations**:

| Usage Pattern | Commitment Type | Discount | Use Case |
|---------------|----------------|----------|----------|
| **Steady (< 20% variance)** | 3-year reserved | 50-60% | Databases, core services |
| **Moderate (20-50% variance)** | 1-year reserved | 30-40% | API servers, monitoring |
| **Variable (> 50% variance)** | On-demand + Spot | 0-70% | Batch jobs, dev/test |

---

## Storage Cost Optimization

### Storage Tiering Strategy

**Storage Tier Definitions**:

| Tier | Storage Class | Cost/GB/Month | IOPS | Use Case |
|------|---------------|---------------|------|----------|
| **Hot** | Premium SSD | $0.17-0.25 | 10k+ | Databases (PostgreSQL, MySQL) |
| **Warm** | Standard SSD | $0.08-0.12 | 3k | Prometheus TSDB, Loki |
| **Cold** | Standard HDD | $0.02-0.04 | 500 | Backups, archives |
| **Archive** | Archive/Glacier | $0.004-0.01 | N/A | Long-term retention |

**Storage Class Definitions**:

```yaml
# Hot tier (Premium SSD)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hot-storage
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: regional-pd
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

---
# Warm tier (Standard SSD)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: warm-storage
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-balanced
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

---
# Cold tier (Standard HDD)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold-storage
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**Chart Storage Tier Recommendations**:

```yaml
# PostgreSQL - Hot tier for data, Cold tier for backups
persistence:
  storageClass: "hot-storage"
  size: 100Gi

backup:
  persistence:
    storageClass: "cold-storage"
    size: 500Gi

---
# Prometheus - Warm tier (high write, sequential read)
persistence:
  storageClass: "warm-storage"
  size: 500Gi

---
# Loki - Warm tier for recent, Cold tier for old chunks
persistence:
  storageClass: "warm-storage"
  size: 200Gi

# Configure chunk storage for S3/MinIO (cheaper)
loki:
  storage_config:
    aws:
      s3: s3://loki-chunks
      s3forcepathstyle: true
    boltdb_shipper:
      shared_store: s3

---
# Backups - Cold tier
backup:
  persistence:
    storageClass: "cold-storage"
    size: 1Ti
```

### Data Lifecycle Management

**Prometheus Data Retention Optimization**:

```yaml
# Prometheus with tiered retention
prometheus:
  # Local retention (hot data)
  retention: 7d
  retentionSize: 50GB

  # Remote write to long-term storage (Mimir/Thanos)
  remoteWrite:
    - url: http://mimir:9009/api/v1/push
      writeRelabelConfigs:
        # Only send metrics needed for long-term analysis
        - sourceLabels: [__name__]
          regex: "(container_.*|kube_.*|node_.*)"
          action: keep
```

**Loki Data Lifecycle**:

```yaml
loki:
  limits_config:
    retention_period: 30d  # Delete logs after 30 days

  # Different retention per tenant (if multi-tenant)
  overrides:
    production:
      retention_period: 90d
    development:
      retention_period: 7d

  # Compaction for storage efficiency
  compactor:
    retention_enabled: true
    retention_delete_delay: 2h
    retention_delete_worker_count: 150
```

**MinIO/S3 Lifecycle Policy**:

```json
{
  "Rules": [
    {
      "ID": "BackupRetention",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "backups/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    },
    {
      "ID": "LogRetention",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "logs/"
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
```

### PVC Cleanup and Optimization

**Identify Unused PVCs**:

```bash
#!/bin/bash
# Find PVCs not bound to any pod
# Usage: ./scripts/find-unused-pvcs.sh

echo "Unused PVCs (not bound to any pod):"
echo "===================================="

# Get all PVCs
for pvc in $(kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
  namespace=$(echo $pvc | cut -d'/' -f1)
  name=$(echo $pvc | cut -d'/' -f2)

  # Check if any pod uses this PVC
  pod_count=$(kubectl get pods -n $namespace -o json | jq -r ".items[].spec.volumes[]?.persistentVolumeClaim.claimName" | grep -c "^${name}$" || true)

  if [ "$pod_count" -eq 0 ]; then
    size=$(kubectl get pvc -n $namespace $name -o jsonpath='{.spec.resources.requests.storage}')
    age=$(kubectl get pvc -n $namespace $name -o jsonpath='{.metadata.creationTimestamp}')
    echo "  $namespace/$name - Size: $size, Created: $age"
  fi
done

echo ""
echo "To delete an unused PVC:"
echo "  kubectl delete pvc <name> -n <namespace>"
```

**PVC Right-Sizing**:

```promql
# PVCs with < 30% usage (over-provisioned)
(
  kubelet_volume_stats_used_bytes
  /
  kubelet_volume_stats_capacity_bytes
) < 0.3
```

---

## Network Cost Optimization

### Egress Cost Reduction

**Key Strategies**:

1. **Keep traffic in-zone**: Use topology-aware routing
2. **Compress data**: Enable gzip/compression for API responses
3. **Cache at edge**: Use CDN for static content
4. **Batch operations**: Reduce API call frequency

**Topology-Aware Routing**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  annotations:
    # Prefer same-zone traffic
    service.kubernetes.io/topology-mode: Auto
spec:
  selector:
    app: postgresql
  topologyKeys:
    - "topology.kubernetes.io/zone"
    - "topology.kubernetes.io/region"
    - "*"
```

**Monitor Egress Traffic**:

```promql
# Egress traffic by namespace (GB/day)
sum by (namespace) (
  rate(container_network_transmit_bytes_total[24h])
) * 86400 / 1024 / 1024 / 1024

# Cross-zone traffic (expensive)
sum by (source_zone, destination_zone) (
  rate(istio_tcp_sent_bytes_total[24h])
) * 86400 / 1024 / 1024 / 1024
```

### Load Balancer Optimization

**Consolidate Load Balancers**:

```yaml
# Use single Ingress controller instead of multiple LoadBalancer services
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: consolidated-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
    - host: prometheus.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prometheus
                port:
                  number: 9090
    - host: keycloak.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak
                port:
                  number: 8080
```

---

## Autoscaling for Cost Efficiency

### Horizontal Pod Autoscaler (HPA)

**Cost-Optimized HPA Configuration**:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-server-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-server
  minReplicas: 2
  maxReplicas: 20
  metrics:
    # Scale on CPU (primary metric)
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70  # Higher target = fewer pods

    # Scale on memory (secondary metric)
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80

  behavior:
    scaleDown:
      # Aggressive scale-down for cost savings
      stabilizationWindowSeconds: 60  # Wait 1 minute before scaling down
      policies:
        - type: Percent
          value: 50  # Scale down 50% at a time
          periodSeconds: 60
        - type: Pods
          value: 2
          periodSeconds: 60
      selectPolicy: Max

    scaleUp:
      # Conservative scale-up to avoid over-provisioning
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 100
          periodSeconds: 60
        - type: Pods
          value: 4
          periodSeconds: 60
      selectPolicy: Min
```

### Vertical Pod Autoscaler (VPA)

**VPA for Right-Sizing**:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: grafana-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: grafana
  updatePolicy:
    updateMode: "Auto"  # Automatically apply recommendations
  resourcePolicy:
    containerPolicies:
      - containerName: grafana
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 2
          memory: 4Gi
        controlledResources: ["cpu", "memory"]
```

### Cluster Autoscaler

**Cost-Optimized Cluster Autoscaler**:

```yaml
# GKE Autopilot is cost-optimized by default
# For GKE Standard or other providers:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
        - name: cluster-autoscaler
          image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.27.0
          command:
            - ./cluster-autoscaler
            - --cloud-provider=gce
            - --nodes=1:10:default-pool
            - --nodes=0:20:spot-pool
            - --scale-down-enabled=true
            - --scale-down-delay-after-add=10m
            - --scale-down-unneeded-time=5m  # Aggressive scale-down
            - --scale-down-utilization-threshold=0.5  # Scale down if < 50% utilized
            - --expander=least-waste  # Choose node that wastes least resources
            - --skip-nodes-with-local-storage=false
            - --balance-similar-node-groups=true
```

### Scheduled Scaling

**Scale Down Dev/Test Environments**:

```yaml
# CronJob to scale down dev environments at night
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-down-dev
  namespace: kube-system
spec:
  schedule: "0 20 * * 1-5"  # 8 PM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: scaler
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Scale down development deployments
                  kubectl scale deployment --all -n development --replicas=0

                  # Scale down staging to minimum
                  kubectl scale deployment --all -n staging --replicas=1
          restartPolicy: OnFailure

---
# CronJob to scale up dev environments in the morning
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-dev
  namespace: kube-system
spec:
  schedule: "0 8 * * 1-5"  # 8 AM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: scaler
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Restore development deployments
                  kubectl scale deployment --all -n development --replicas=2
          restartPolicy: OnFailure
```

---

## FinOps Best Practices

### Cost Governance Framework

**1. Ownership & Accountability**

```yaml
# Enforce cost labels with OPA/Gatekeeper
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-cost-labels
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
  parameters:
    labels:
      - key: "cost-center"
      - key: "owner"
      - key: "environment"
```

**2. Budget Alerts**

```yaml
# Prometheus alert for budget threshold
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
spec:
  groups:
    - name: cost_alerts
      rules:
        - alert: NamespaceCostExceeded
          expr: |
            sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 720 > 1000
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} monthly cost exceeds $1000"
            description: "Estimated monthly cost: ${{ $value | printf \"%.0f\" }}"

        - alert: UnexpectedCostSpike
          expr: |
            (
              sum by (namespace) (namespace:estimated_cost_per_hour:sum)
              -
              sum by (namespace) (namespace:estimated_cost_per_hour:sum offset 1d)
            )
            /
            sum by (namespace) (namespace:estimated_cost_per_hour:sum offset 1d)
            > 0.5
          for: 2h
          labels:
            severity: warning
          annotations:
            summary: "50%+ cost increase in namespace {{ $labels.namespace }}"
```

**3. Regular Cost Reviews**

```bash
#!/bin/bash
# Weekly cost review report
# Usage: ./scripts/weekly-cost-report.sh

echo "Weekly Cost Review - $(date)"
echo "=============================="
echo ""

# Top 10 namespaces by cost
echo "Top 10 Namespaces by Cost:"
echo "--------------------------"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=topk(10, sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 168)" \
  | jq -r '.data.result[] | "\(.metric.namespace): $\(.value[1] | tonumber | floor)"'

echo ""
echo "Week-over-Week Change:"
echo "----------------------"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=
    (sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 168)
    -
    (sum by (namespace) (namespace:estimated_cost_per_hour:sum offset 7d) * 168)" \
  | jq -r '.data.result[] | select(.value[1] | tonumber | fabs > 10) | "\(.metric.namespace): $\(.value[1] | tonumber | floor)"'

echo ""
echo "Optimization Opportunities:"
echo "---------------------------"

# Under-utilized resources
echo "- Under-utilized pods (< 30% CPU):"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=count(namespace:cpu_utilization:ratio < 0.3)" \
  | jq -r '"  \(.data.result[0].value[1]) pods"'

# Over-provisioned storage
echo "- Over-provisioned PVCs (< 30% used):"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode "query=count((kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) < 0.3)" \
  | jq -r '"  \(.data.result[0].value[1]) PVCs"'
```

### FinOps Maturity Model

| Level | Characteristics | Actions |
|-------|-----------------|---------|
| **Crawl** | Basic visibility, reactive | Deploy cost tracking, identify top spenders |
| **Walk** | Proactive optimization, budgets | Implement right-sizing, autoscaling, spot instances |
| **Run** | Automated, continuous optimization | FinOps culture, automated remediation, forecasting |

### Cost Optimization Roadmap

**Month 1: Foundation**
- Deploy kube-state-metrics and cost tracking Prometheus rules
- Create Grafana cost dashboard
- Implement namespace cost labels
- Identify top 10 cost drivers

**Month 2: Quick Wins**
- Right-size over-provisioned pods (target: 20% savings)
- Enable autoscaling for stateless services
- Clean up unused PVCs and resources
- Implement storage tiering

**Month 3: Advanced Optimization**
- Deploy spot instances for suitable workloads
- Implement scheduled scaling for dev/test
- Set up budget alerts
- Create cost allocation reports

**Month 4+: Continuous Improvement**
- Weekly cost reviews
- Quarterly optimization assessments
- Reserved capacity planning
- FinOps process refinement

---

## Cost Monitoring & Alerting

### Alert Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-monitoring-alerts
spec:
  groups:
    - name: cost_monitoring
      rules:
        # Budget alerts
        - alert: NamespaceBudgetWarning
          expr: |
            sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 720 > 800
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} at 80% of $1000 budget"

        - alert: NamespaceBudgetCritical
          expr: |
            sum by (namespace) (namespace:estimated_cost_per_hour:sum) * 720 > 950
          labels:
            severity: critical
          annotations:
            summary: "Namespace {{ $labels.namespace }} at 95% of $1000 budget"

        # Efficiency alerts
        - alert: LowCPUUtilization
          expr: |
            namespace:cpu_utilization:ratio < 0.2
            and
            sum by (namespace) (kube_pod_container_resource_requests{resource="cpu"}) > 1
          for: 24h
          labels:
            severity: info
          annotations:
            summary: "Namespace {{ $labels.namespace }} has < 20% CPU utilization"
            description: "Consider right-sizing or enabling autoscaling"

        - alert: LowMemoryUtilization
          expr: |
            namespace:memory_utilization:ratio < 0.3
            and
            sum by (namespace) (kube_pod_container_resource_requests{resource="memory"}) > 1073741824
          for: 24h
          labels:
            severity: info
          annotations:
            summary: "Namespace {{ $labels.namespace }} has < 30% memory utilization"

        # Anomaly detection
        - alert: CostAnomaly
          expr: |
            (
              sum by (namespace) (namespace:estimated_cost_per_hour:sum)
              -
              avg_over_time(sum by (namespace) (namespace:estimated_cost_per_hour:sum)[7d:1h])
            )
            /
            avg_over_time(sum by (namespace) (namespace:estimated_cost_per_hour:sum)[7d:1h])
            > 0.5
          for: 4h
          labels:
            severity: warning
          annotations:
            summary: "Cost anomaly detected in {{ $labels.namespace }}"
            description: "Current cost is 50%+ above 7-day average"
```

---

## Optimization Checklists

### Quick Wins Checklist

- [ ] **Identify unused resources**
  - [ ] Find and delete unused PVCs
  - [ ] Find and delete orphaned ConfigMaps/Secrets
  - [ ] Identify idle deployments (0 traffic)

- [ ] **Right-size over-provisioned workloads**
  - [ ] Review pods with < 30% CPU utilization
  - [ ] Review pods with < 40% memory utilization
  - [ ] Adjust resource requests to match actual usage + 20% buffer

- [ ] **Enable autoscaling**
  - [ ] HPA for stateless services (API servers, workers)
  - [ ] VPA for variable workloads (batch jobs)
  - [ ] Cluster autoscaler for node pool

- [ ] **Implement spot instances**
  - [ ] Identify spot-tolerant workloads (batch, dev/test)
  - [ ] Configure tolerations and node affinity
  - [ ] Set up PodDisruptionBudgets

### Storage Optimization Checklist

- [ ] **Review storage classes**
  - [ ] Databases on hot tier (SSD)
  - [ ] Metrics/logs on warm tier
  - [ ] Backups on cold tier

- [ ] **Implement data lifecycle**
  - [ ] Set retention policies for Prometheus
  - [ ] Set retention policies for Loki
  - [ ] Configure S3 lifecycle rules for backups

- [ ] **Clean up storage**
  - [ ] Delete unused PVCs
  - [ ] Resize over-provisioned PVCs
  - [ ] Archive old backups to cold storage

### Network Optimization Checklist

- [ ] **Reduce egress costs**
  - [ ] Enable topology-aware routing
  - [ ] Consolidate load balancers with Ingress
  - [ ] Enable compression for API responses

- [ ] **Monitor network usage**
  - [ ] Track egress by namespace
  - [ ] Identify cross-zone traffic
  - [ ] Set up alerts for egress spikes

### Governance Checklist

- [ ] **Implement cost visibility**
  - [ ] Deploy cost tracking Prometheus rules
  - [ ] Create Grafana cost dashboard
  - [ ] Set up weekly cost reports

- [ ] **Enforce cost accountability**
  - [ ] Require cost labels on namespaces
  - [ ] Assign cost center to each team
  - [ ] Set namespace budgets

- [ ] **Establish review process**
  - [ ] Weekly cost review meetings
  - [ ] Monthly optimization assessments
  - [ ] Quarterly capacity planning

---

**Document Version**: 1.0
**Last Updated**: 2025-12-09
**Maintained By**: FinOps Team
**Review Cycle**: Monthly
