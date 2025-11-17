# Jellyfin

<!-- Badges -->
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/jellyfin)
[![Chart Version](https://img.shields.io/badge/chart-0.3.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-10.10.3-green.svg)](https://jellyfin.org)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

The Free Software Media System - A Plex alternative that puts you in control.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# Install chart with home server configuration
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml

# Enable Intel QuickSync Video (QSV) hardware transcoding
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=intel-qsv
```

## Introduction

This chart bootstraps a Jellyfin media server deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ **Complete GPU Acceleration Support** (Intel QSV, NVIDIA NVENC, AMD VAAPI)
- ✅ **No External Dependencies** (uses built-in SQLite database)
- ✅ **Flexible Media Library Configuration** (PVC, hostPath, or existing claims)
- ✅ **Optimized for Home Servers** (Raspberry Pi, Intel NUC, Mini PCs)
- ✅ **Production-Ready** with health probes and resource management
- ✅ **Native Configuration** (uses Jellyfin's built-in config files)

### Why Jellyfin over Plex?

- **100% Free & Open Source** - No paid tiers or feature restrictions
- **No Telemetry** - Your data stays on your server
- **Community-Driven** - No vendor lock-in
- **GPU Transcoding** - Free hardware acceleration (Plex charges for this)

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- Persistent storage (PVC or hostPath)

### Optional: GPU Hardware

For hardware-accelerated transcoding:

- **Intel QuickSync Video (QSV)**: Intel CPU with integrated GPU (6th gen+)
  - Most common in home servers (Intel NUC, Mini PCs)
  - Recommended for home use
- **NVIDIA NVENC**: NVIDIA GPU with NVENC support
  - Requires NVIDIA GPU Operator or device plugin
  - Best performance but higher power consumption
- **AMD VAAPI**: AMD GPU with VA-API support
  - Good performance with lower power usage

## Installing the Chart

### Home Server Quick Start (Recommended)

Perfect for Raspberry Pi 4, Intel NUC, or home NAS:

```bash
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml
```

**What you get:**
- 2 CPU cores, 2Gi RAM
- 2Gi config storage, 5Gi transcoding cache
- Ready for Intel QSV hardware acceleration

### With Intel QuickSync Video (QSV)

Enable hardware transcoding on Intel CPUs:

```bash
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=intel-qsv \
  --set nodeSelector."intel\.feature\.node\.kubernetes\.io/gpu"=true
```

### With NVIDIA GPU

```bash
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=nvidia-nvenc \
  --set nodeSelector."nvidia\.com/gpu\.present"=true
```

### With AMD VAAPI

```bash
helm install jellyfin sb-charts/jellyfin \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/jellyfin/values-home-single.yaml \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=amd-vaapi
```

## Configuration

### GPU Hardware Acceleration

Complete guide for enabling GPU transcoding.

#### Intel QuickSync Video (QSV)

**Requirements:**
- Intel CPU with integrated GPU (6th generation or newer)
- `/dev/dri/renderD128` device accessible on node

**Configuration:**

```yaml
# values.yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "intel-qsv"
    intel:
      renderDevice: "/dev/dri/renderD128"

# Node selector (if you have multiple nodes)
nodeSelector:
  intel.feature.node.kubernetes.io/gpu: "true"
```

**What the chart does automatically:**
- ✅ Mounts `/dev/dri` into the container
- ✅ Adds supplementalGroups `44` (video) and `109` (render)
- ✅ Sets proper device permissions

**Verify GPU access:**

```bash
# Check GPU configuration
make -f make/ops/jellyfin.mk jellyfin-check-gpu

# Expected output:
# Hardware acceleration type: intel-qsv
# GPU enabled: Yes
# /dev/dri:
# drwxr-xr-x 2 root root 80 renderD128
```

#### NVIDIA NVENC

**Requirements:**
- NVIDIA GPU with NVENC support
- [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) installed
- Or [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)

**Configuration:**

```yaml
# values.yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "nvidia-nvenc"
    nvidia:
      runtimeClassName: "nvidia"

nodeSelector:
  nvidia.com/gpu.present: "true"
```

**What the chart does automatically:**
- ✅ Adds `nvidia.com/gpu: 1` resource limit
- ✅ Sets `runtimeClassName: nvidia`

**Verify GPU access:**

```bash
make -f make/ops/jellyfin.mk jellyfin-check-gpu

# Should show nvidia-smi output
```

#### AMD VAAPI

**Requirements:**
- AMD GPU with VA-API support
- `/dev/dri` device accessible on node

**Configuration:**

```yaml
# values.yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "amd-vaapi"
```

**What the chart does automatically:**
- ✅ Mounts `/dev/dri` into the container
- ✅ Adds supplementalGroups `44` (video) and `109` (render)

### Media Library Configuration

Jellyfin needs access to your media files. Three options available:

#### Option 1: hostPath (Recommended for Home Servers)

Mount media directly from NAS or local storage:

```yaml
# values.yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      hostPath: "/mnt/nas/media/movies"
      readOnly: true  # Jellyfin only needs read access
    - name: tvshows
      mountPath: /media/tvshows
      hostPath: "/mnt/nas/media/tvshows"
      readOnly: true
    - name: music
      mountPath: /media/music
      hostPath: "/mnt/nas/media/music"
      readOnly: true
```

**Pros:**
- ✅ Direct NAS/SMB/NFS mount access
- ✅ No data duplication
- ✅ Easy to manage media files

**Cons:**
- ⚠️ Requires node affinity (pod must run on node with mount)

#### Option 2: Persistent Volume Claims (PVC)

Use Kubernetes PVCs for media storage:

```yaml
# values.yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      size: 500Gi
      storageClass: "fast-ssd"
    - name: tvshows
      mountPath: /media/tvshows
      size: 1Ti
      storageClass: "slow-hdd"
```

**Pros:**
- ✅ Kubernetes-native storage
- ✅ Portable across nodes

**Cons:**
- ⚠️ Requires storage provisioner
- ⚠️ May need data migration

#### Option 3: Existing Claims

Use pre-created PVCs:

```yaml
# values.yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      existingClaim: "nfs-movies-pvc"
    - name: tvshows
      mountPath: /media/tvshows
      existingClaim: "nfs-tvshows-pvc"
```

### Transcoding Cache

Configure transcoding cache size based on your needs:

```yaml
# values.yaml
jellyfin:
  transcoding:
    cacheSize: 10Gi  # Default
    threads: 0  # 0 = auto-detect CPU cores

# Home server (reduced)
persistence:
  cache:
    size: 5Gi

# Production (large)
persistence:
  cache:
    size: 50Gi
```

**Recommended cache sizes:**
- **Home Server**: 5-10Gi (1-2 concurrent streams)
- **Small Team**: 20-30Gi (3-5 concurrent streams)
- **Production**: 50-100Gi (10+ concurrent streams)

## Deployment Scenarios

### Home Server / Personal Use

Perfect for Raspberry Pi 4, Intel NUC, or small servers:

```bash
helm install jellyfin sb-charts/jellyfin \
  -f charts/jellyfin/values-home-single.yaml
```

**Resources**: 2 CPUs, 2Gi RAM  
**Storage**: 2Gi config, 5Gi cache  
**GPU**: Optional Intel QSV recommended

### Startup / Small Team

Balanced configuration:

```bash
helm install jellyfin sb-charts/jellyfin \
  -f charts/jellyfin/values-startup-single.yaml
```

**Resources**: TBD  
**Storage**: TBD

### Production / High Availability

Note: Jellyfin uses SQLite by default, which doesn't support HA. For production HA:
1. Use external PostgreSQL database
2. Deploy multiple read replicas
3. Use load balancer

See [Jellyfin HA Guide](https://jellyfin.org/docs/general/administration/clustering.html)

## Operational Commands

This chart includes Makefile commands for common operations:

### Access & Debugging

```bash
# Open shell in Jellyfin pod
make -f make/ops/jellyfin.mk jellyfin-shell

# Tail logs
make -f make/ops/jellyfin.mk jellyfin-logs

# Port forward to localhost:8096
make -f make/ops/jellyfin.mk jellyfin-port-forward

# Get access URL
make -f make/ops/jellyfin.mk jellyfin-get-url
```

### GPU & Configuration

```bash
# Check GPU configuration and access
make -f make/ops/jellyfin.mk jellyfin-check-gpu

# Check media directories
make -f make/ops/jellyfin.mk jellyfin-check-media

# Check configuration directory
make -f make/ops/jellyfin.mk jellyfin-check-config

# Check transcoding cache usage
make -f make/ops/jellyfin.mk jellyfin-check-cache
```

### Cache Management

```bash
# Clear transcoding cache (WARNING: destroys cache)
make -f make/ops/jellyfin.mk jellyfin-clear-cache
```

### Backup & Restore

```bash
# Backup configuration to tmp/jellyfin-backups/
make -f make/ops/jellyfin.mk jellyfin-backup-config

# Restore configuration
make -f make/ops/jellyfin.mk jellyfin-restore-config FILE=tmp/jellyfin-backups/backup.tar.gz
```

### Monitoring

```bash
# Show resource usage
make -f make/ops/jellyfin.mk jellyfin-stats

# Describe pod
make -f make/ops/jellyfin.mk jellyfin-describe

# Show pod events
make -f make/ops/jellyfin.mk jellyfin-events
```

For complete list:

```bash
make -f make/ops/jellyfin.mk jellyfin-help
```

## Troubleshooting

### GPU Transcoding Not Working

**Intel QSV:**

1. Verify `/dev/dri` access:
   ```bash
   make -f make/ops/jellyfin.mk jellyfin-shell
   ls -la /dev/dri
   ```

2. Check supplemental groups:
   ```bash
   kubectl describe pod <jellyfin-pod> | grep Groups
   # Should show: 44 109
   ```

3. Enable QSV in Jellyfin UI:
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: Intel QuickSync (QSV)

**NVIDIA:**

1. Verify NVIDIA GPU Operator is installed:
   ```bash
   kubectl get pods -n gpu-operator-resources
   ```

2. Check GPU resource:
   ```bash
   kubectl describe node <node-name> | grep nvidia.com/gpu
   ```

**AMD VAAPI:**

1. Verify `/dev/dri` access (same as Intel QSV)

2. Enable VAAPI in Jellyfin UI:
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: VA-API

### Media Library Not Visible

1. Check media directory mounts:
   ```bash
   make -f make/ops/jellyfin.mk jellyfin-check-media
   ```

2. Verify hostPath exists on node:
   ```bash
   # On the node
   ls -la /mnt/nas/media/
   ```

3. Check pod events for mount errors:
   ```bash
   make -f make/ops/jellyfin.mk jellyfin-events
   ```

### Transcoding Cache Full

Clear the cache:

```bash
make -f make/ops/jellyfin.mk jellyfin-clear-cache
```

Or increase cache size:

```bash
helm upgrade jellyfin sb-charts/jellyfin \
  --reuse-values \
  --set persistence.cache.size=20Gi
```

### High CPU Usage

1. Enable GPU transcoding (see GPU section above)
2. Reduce transcoding quality:
   - Dashboard → Playback → Transcoding
   - Reduce encoder preset (slower = better quality but higher CPU)

## Values Reference

See [values.yaml](values.yaml) for complete configuration options.

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `jellyfin.hardwareAcceleration.enabled` | Enable GPU acceleration | `false` |
| `jellyfin.hardwareAcceleration.type` | GPU type (`intel-qsv`, `nvidia-nvenc`, `amd-vaapi`) | `none` |
| `jellyfin.mediaDirectories` | Media library configuration | `[]` |
| `jellyfin.transcoding.cacheSize` | Transcoding cache size | `10Gi` |
| `persistence.config.size` | Config storage size | `5Gi` |
| `persistence.cache.size` | Cache storage size | `10Gi` |
| `resources.limits.cpu` | CPU limit | `4000m` |
| `resources.limits.memory` | Memory limit | `4Gi` |

## Project Philosophy

This chart follows the **ScriptonBasestar Helm Charts** philosophy:

- ✅ **Configuration files over environment variables**
  - Uses Jellyfin's native SQLite and config files
- ✅ **No subchart complexity**
  - No external database dependencies (uses embedded SQLite)
- ✅ **Simple Docker images**
  - Uses official `jellyfin/jellyfin` image
- ✅ **Hardware optimization**
  - First-class GPU acceleration support for all major vendors

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Jellyfin Documentation**: https://jellyfin.org/docs
- **Jellyfin GitHub**: https://github.com/jellyfin/jellyfin
- **Chart Development Guide**: [docs/CHART_DEVELOPMENT_GUIDE.md](../../docs/CHART_DEVELOPMENT_GUIDE.md)

## License

This Helm chart is licensed under the **BSD-3-Clause** license.

Jellyfin application is licensed under the **GNU GPL v2** license. See [Jellyfin License](https://github.com/jellyfin/jellyfin/blob/master/LICENSE) for details.
