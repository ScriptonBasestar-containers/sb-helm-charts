# Homeserver Optimization Guide

Best practices and configurations for running Helm charts on home server hardware with limited resources.

## Overview

This guide covers optimization strategies for deploying applications from this repository on home server hardware, including Raspberry Pi, Intel NUC, mini PCs, and older desktop hardware.

**Goals:**
- Minimize resource usage while maintaining functionality
- Optimize for 24/7 operation
- Reduce power consumption
- Maximize storage efficiency
- Ensure reliable operation on consumer hardware

## Table of Contents

- [Hardware Recommendations](#hardware-recommendations)
- [Resource Optimization Strategies](#resource-optimization-strategies)
- [Storage Strategies](#storage-strategies)
- [Kubernetes Configuration](#kubernetes-configuration)
- [Chart-Specific Optimizations](#chart-specific-optimizations)
- [Monitoring on Limited Resources](#monitoring-on-limited-resources)
- [Power Management](#power-management)
- [Cost Analysis](#cost-analysis)

## Hardware Recommendations

### Minimum Requirements

| Workload | CPU | RAM | Storage | Notes |
|----------|-----|-----|---------|-------|
| Single App | 2 cores | 4GB | 64GB SSD | Minimal K3s + one application |
| Light Stack | 4 cores | 8GB | 128GB SSD | 2-3 applications |
| Medium Stack | 4-6 cores | 16GB | 256GB SSD | 5-8 applications |
| Full Stack | 8+ cores | 32GB | 512GB+ SSD | Complete monitoring + apps |

### Recommended Hardware

#### Entry Level: Raspberry Pi 4/5

**Specs:** 4-8GB RAM, ARM64, 15W power
**Suitable for:** 1-3 lightweight applications

```yaml
# Typical resource allocation
applications:
  - nextcloud  # 512Mi RAM
  - redis      # 128Mi RAM
  - postgresql # 256Mi RAM
# Total: ~1GB for apps, rest for K3s overhead
```

**Limitations:**
- Limited RAM (max 8GB)
- SD card reliability (use SSD via USB)
- ARM architecture (some images may not support)

#### Mid Range: Intel NUC / Mini PC

**Specs:** 4-8 cores, 16-32GB RAM, ~35W power
**Suitable for:** 5-10 applications with monitoring

**Recommended Models:**
- Intel NUC 11/12/13 (i5/i7)
- Beelink Mini S / SER series
- Minisforum UM series

```yaml
# Typical resource allocation
applications:
  - nextcloud     # 1Gi RAM
  - keycloak      # 1Gi RAM
  - postgresql    # 512Mi RAM
  - redis         # 256Mi RAM
  - grafana       # 256Mi RAM
  - prometheus    # 512Mi RAM (reduced retention)
  - loki          # 512Mi RAM
# Total: ~4.5GB for apps
```

#### Advanced: Multi-Node Cluster

**Specs:** 2-3 nodes, each 4+ cores, 8-16GB RAM
**Suitable for:** High availability, full monitoring stack

**Options:**
- 3x Raspberry Pi 4/5 (8GB each)
- 2-3x Mini PCs
- Mix of old laptops/desktops

## Resource Optimization Strategies

### 1. Container Resource Limits

Always set resource requests and limits to prevent resource starvation:

```yaml
# Minimal resource configuration
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### 2. Use Light Container Images

Prefer alpine-based or distroless images:

```yaml
# Prefer
image: postgres:16-alpine   # ~80MB
# Over
image: postgres:16          # ~400MB
```

### 3. Reduce Replica Counts

For homeserver, single replicas are often sufficient:

```yaml
# Production vs Homeserver
# Production
replicaCount: 3
# Homeserver
replicaCount: 1
```

### 4. Disable Unnecessary Features

```yaml
# Disable features that consume resources
metrics:
  enabled: false  # Or use low-resource metrics

autoscaling:
  enabled: false

podDisruptionBudget:
  enabled: false  # Single replica anyway
```

### 5. Use Shared Databases

Instead of per-app databases, use shared PostgreSQL/MySQL:

```yaml
# Single PostgreSQL for multiple apps
postgresql:
  initdbScripts:
    init.sql: |
      CREATE DATABASE nextcloud;
      CREATE DATABASE keycloak;
      CREATE DATABASE paperless;
      CREATE USER nextcloud WITH PASSWORD 'pass1';
      CREATE USER keycloak WITH PASSWORD 'pass2';
      CREATE USER paperless WITH PASSWORD 'pass3';
      GRANT ALL ON DATABASE nextcloud TO nextcloud;
      GRANT ALL ON DATABASE keycloak TO keycloak;
      GRANT ALL ON DATABASE paperless TO paperless;
```

## Storage Strategies

### 1. Storage Class Selection

Use appropriate storage for workload type:

```yaml
# Fast storage for databases
storageClass: local-path  # or nfs-fast

# Slow storage for media/backups
storageClass: nfs-slow    # or external HDD
```

### 2. PVC Sizing

Start small and expand as needed:

```yaml
# Homeserver starting points
persistence:
  # Databases
  postgresql: 5Gi    # Start small, monitor usage

  # Applications
  nextcloud: 50Gi    # Depends on photo/file usage
  jellyfin: 10Gi     # Just config, media on NAS

  # Monitoring
  prometheus: 10Gi   # Reduced retention
  loki: 10Gi         # Reduced retention
```

### 3. External Storage Integration

Use NAS/NFS for large datasets:

```yaml
# Mount NFS for media
extraVolumes:
  - name: media
    nfs:
      server: nas.local
      path: /volume1/media

extraVolumeMounts:
  - name: media
    mountPath: /media
    readOnly: true  # For playback only
```

### 4. Retention Policies

Aggressive retention for logs and metrics:

```yaml
# Prometheus - 7 days instead of 15
prometheus:
  retention: 7d
  retentionSize: 5GB

# Loki - 7 days instead of 30
loki:
  retention_period: 168h  # 7 days
```

## Kubernetes Configuration

### K3s Optimization

K3s is recommended for homeservers due to lower resource usage:

```bash
# Install K3s with minimal footprint
curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --disable local-storage \
  --kubelet-arg="max-pods=50"
```

### Disable Unused Components

```bash
# /etc/rancher/k3s/config.yaml
disable:
  - traefik
  - servicelb
  - metrics-server  # If not using HPA

kubelet-arg:
  - "max-pods=50"
  - "eviction-hard=memory.available<100Mi"
  - "system-reserved=cpu=200m,memory=256Mi"
```

### Node Labels for Scheduling

```bash
# Label node for specific workloads
kubectl label node homeserver workload=general
kubectl label node nas-node workload=storage
```

### Priority Classes

```yaml
# High priority for core services
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: homeserver-critical
value: 1000000
globalDefault: false
description: "Critical homeserver services"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: homeserver-normal
value: 100000
globalDefault: true
description: "Normal homeserver services"
```

## Chart-Specific Optimizations

### PostgreSQL (Shared Database)

```yaml
# values-homeserver.yaml
replicaCount: 1

postgresql:
  # Reduced memory settings
  sharedBuffers: "64MB"
  effectiveCacheSize: "256MB"
  workMem: "2MB"
  maintenanceWorkMem: "32MB"
  maxConnections: 50

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

persistence:
  size: 5Gi
```

### Redis (Cache)

```yaml
# values-homeserver.yaml
replicaCount: 1

redis:
  maxmemory: "128mb"
  maxmemoryPolicy: "allkeys-lru"

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi

persistence:
  enabled: false  # Cache only, no persistence needed
```

### Nextcloud

```yaml
# values-homeserver.yaml
replicaCount: 1

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# Use external PostgreSQL/Redis
postgresql:
  external:
    enabled: true
    host: postgresql.default.svc.cluster.local
    database: nextcloud

redis:
  external:
    enabled: true
    host: redis.default.svc.cluster.local

# Optimize PHP
extraEnv:
  - name: PHP_MEMORY_LIMIT
    value: "512M"
  - name: PHP_UPLOAD_LIMIT
    value: "10G"
```

### Jellyfin (Media Server)

```yaml
# values-homeserver.yaml
replicaCount: 1

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# Hardware transcoding (if available)
extraEnv:
  - name: JELLYFIN_PublishedServerUrl
    value: "https://jellyfin.home.local"

# GPU passthrough for transcoding
# securityContext:
#   privileged: true
# extraVolumes:
#   - name: render
#     hostPath:
#       path: /dev/dri/renderD128
```

### Prometheus (Minimal Monitoring)

```yaml
# values-homeserver.yaml
replicaCount: 1

prometheus:
  retention: 7d
  retentionSize: 5GB

  # Reduce scrape frequency
  scrapeInterval: 60s
  evaluationInterval: 60s

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

persistence:
  size: 10Gi
```

### Grafana (Lightweight)

```yaml
# values-homeserver.yaml
replicaCount: 1

resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Disable unnecessary features
grafana:
  plugins: []  # Don't install extra plugins

persistence:
  size: 1Gi
```

## Monitoring on Limited Resources

### Lightweight Monitoring Stack

Instead of full Prometheus + Loki + Tempo:

```yaml
# Option 1: Prometheus only (metrics)
# ~512MB RAM total

# Option 2: Prometheus + Grafana (metrics + visualization)
# ~768MB RAM total

# Option 3: Add Loki for logs if needed
# ~1.5GB RAM total

# Skip Tempo (tracing) on homeserver unless specifically needed
```

### Alternative: VictoriaMetrics

VictoriaMetrics uses less resources than Prometheus:

```bash
# 30-50% less memory usage
# Faster queries
# Compatible with Prometheus queries
```

### Minimal Alerting

Use Uptime Kuma instead of full alerting stack:

```yaml
# Uptime Kuma - lightweight monitoring
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

## Power Management

### Estimate Power Usage

| Component | Idle | Load | Notes |
|-----------|------|------|-------|
| Raspberry Pi 4 | 3W | 7W | Most efficient |
| Intel NUC | 10W | 35W | Good balance |
| Mini PC | 8W | 45W | Varies by model |
| Old Desktop | 40W | 150W+ | Consider replacing |

### Power Optimization

```bash
# CPU frequency scaling
echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable unused USB ports
# Disable WiFi/Bluetooth if using ethernet
```

### UPS Considerations

For 24/7 operation:
- Minimum 500VA UPS for single node
- NUT (Network UPS Tools) for graceful shutdown
- Consider longer runtime for NAS protection

## Cost Analysis

### Monthly Operating Costs (Electricity)

| Setup | Power | Monthly Cost* |
|-------|-------|---------------|
| Raspberry Pi | 5W avg | $0.50 |
| Mini PC | 15W avg | $1.50 |
| NUC | 20W avg | $2.00 |
| Old Desktop | 80W avg | $8.00 |

*Assuming $0.12/kWh

### Total Cost of Ownership (3 Years)

| Setup | Hardware | Electricity | Total |
|-------|----------|-------------|-------|
| Raspberry Pi 4 8GB | $100 | $18 | $118 |
| Mini PC (16GB) | $300 | $54 | $354 |
| Intel NUC (32GB) | $600 | $72 | $672 |
| Cloud VPS equivalent | - | $1,080+ | $1,080+ |

### Cost Savings vs Cloud

Running homeserver vs cloud VPS:
- 4GB VPS: ~$20-40/month = $720-1440/3yr
- Homeserver (Mini PC): ~$354/3yr
- **Savings: $366-1086 over 3 years**

## Quick Start Configurations

### Minimal Stack (RPi 4, 4GB)

```bash
# Deploy only essentials
./scripts/quick-start.sh database default
# PostgreSQL + Redis only
# Total RAM: ~500MB
```

### Personal Cloud (RPi 4/5, 8GB or Mini PC 16GB)

```yaml
# Personal productivity stack
- nextcloud    # 1GB
- vaultwarden  # 128MB
- redis        # 128MB
- postgresql   # 512MB
# Total: ~2GB, leaves room for K3s
```

### Home Media (Mini PC 16GB+)

```yaml
# Media server stack
- jellyfin     # 2GB (with transcoding)
- postgresql   # 512MB
# Mount media from NAS via NFS
# Total: ~3GB
```

### Full Homelab (32GB+ node or cluster)

```yaml
# Complete stack
- nextcloud    # 1GB
- keycloak     # 1GB
- jellyfin     # 2GB
- postgresql   # 1GB
- redis        # 256MB
- prometheus   # 512MB
- grafana      # 256MB
- loki         # 512MB
# Total: ~7GB
```

## Best Practices Summary

### DO

- ✅ Start with minimal resources, scale up as needed
- ✅ Use shared databases for multiple applications
- ✅ Enable persistence only where necessary
- ✅ Use NFS/NAS for large media files
- ✅ Set appropriate retention for logs/metrics
- ✅ Monitor actual resource usage before optimizing
- ✅ Use SSDs for OS and databases
- ✅ Plan for UPS/graceful shutdown

### DON'T

- ❌ Run 3 replicas on a single node
- ❌ Enable every monitoring component
- ❌ Use default production configurations
- ❌ Ignore storage planning
- ❌ Run databases on SD cards
- ❌ Skip resource limits
- ❌ Over-provision "just in case"

## Troubleshooting

### Out of Memory

```bash
# Check memory usage
kubectl top nodes
kubectl top pods --all-namespaces

# Find memory hogs
kubectl get pods --all-namespaces -o custom-columns=\
'NAMESPACE:.metadata.namespace,NAME:.metadata.name,MEM:.spec.containers[*].resources.limits.memory' \
| sort -k3 -h
```

### Slow Performance

```bash
# Check CPU throttling
kubectl top pods --sort-by=cpu

# Check disk I/O
iostat -x 1
```

### Pod Eviction

```bash
# Adjust eviction thresholds
# /etc/rancher/k3s/config.yaml
kubelet-arg:
  - "eviction-hard=memory.available<100Mi,nodefs.available<5%"
  - "eviction-soft=memory.available<200Mi,nodefs.available<10%"
```

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Raspberry Pi Kubernetes](https://ubuntu.com/tutorials/how-to-kubernetes-cluster-on-raspberry-pi)
- [Home Assistant OS vs K3s](https://www.home-assistant.io/installation/)
