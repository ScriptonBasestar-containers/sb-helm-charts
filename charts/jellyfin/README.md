# Jellyfin Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/jellyfin)

[Jellyfin](https://jellyfin.org/) is a Free Software Media System that puts you in control of managing and streaming your media. It is an alternative to the proprietary Plex, to provide media from a dedicated server to end-user devices via multiple apps.

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install my-jellyfin scripton-charts/jellyfin
```

## Introduction

This chart bootstraps a Jellyfin deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- 🎬 Complete media server solution (movies, TV shows, music, photos)
- 🚀 Hardware acceleration support (Intel QSV, NVIDIA NVENC, AMD VA-API)
- 📦 Simple deployment (no external database required - uses SQLite)
- 🏠 Optimized for home servers and production deployments
- 🔒 Production-ready with persistence, ingress, and monitoring support

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install jellyfin-home charts/jellyfin \
  -f charts/jellyfin/values-home-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 20Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install jellyfin-startup charts/jellyfin \
  -f charts/jellyfin/values-startup-single.yaml
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 50Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High-performance deployment with hardware transcoding and enhanced storage:

```bash
helm install jellyfin-prod charts/jellyfin \
  -f charts/jellyfin/values-prod-master-replica.yaml
```

**Features:** Hardware transcoding (GPU passthrough), PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 100Gi storage

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#jellyfin).


- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure (for persistence)
- (Optional) GPU device plugin for hardware acceleration:
  - Intel: [Intel Device Plugin](https://github.com/intel/intel-device-plugins-for-kubernetes)
  - NVIDIA: [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html)

## Versioning

| Chart Version | App Version | Kubernetes | Helm | Notes |
|---------------|-------------|------------|------|-------|
| 0.1.0         | 10.10.3     | 1.19+      | 3.0+ | Initial release with GPU support |

## Installing the Chart

### Basic Installation

To install the chart with the release name `my-jellyfin`:

```bash
helm install my-jellyfin scripton-charts/jellyfin
```

### Home Server Installation (Intel QuickSync)

For home servers with Intel integrated graphics:

```bash
helm install my-jellyfin scripton-charts/jellyfin \
  -f values-homeserver.yaml
```

### Production Installation (NVIDIA GPU)

For production deployments with NVIDIA GPU:

```bash
helm install my-jellyfin scripton-charts/jellyfin \
  -f values-example.yaml \
  --set jellyfin.network.publishedServerUrl=https://jellyfin.example.com \
  --set ingress.hosts[0].host=jellyfin.example.com
```

## Uninstalling the Chart

To uninstall/delete the `my-jellyfin` deployment:

```bash
helm delete my-jellyfin
```

## Configuration

### Basic Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Jellyfin replicas | `1` |
| `image.repository` | Jellyfin image repository | `jellyfin/jellyfin` |
| `image.tag` | Jellyfin image tag | `10.10.3` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### Jellyfin Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `jellyfin.mediaDirectories` | Media library directories | `[]` |
| `jellyfin.hardwareAcceleration.enabled` | Enable GPU hardware acceleration | `false` |
| `jellyfin.hardwareAcceleration.type` | GPU type (`intel-qsv`, `nvidia-nvenc`, `amd-vaapi`) | `none` |
| `jellyfin.hardwareAcceleration.intel.renderDevice` | Intel GPU render device path | `/dev/dri/renderD128` |
| `jellyfin.hardwareAcceleration.nvidia.runtimeClassName` | NVIDIA runtime class | `nvidia` |
| `jellyfin.transcoding.cacheSize` | Transcoding cache size | `10Gi` |
| `jellyfin.transcoding.threads` | Software transcoding threads (0=auto) | `0` |
| `jellyfin.network.publishedServerUrl` | Published server URL for remote access | `""` |
| `jellyfin.network.enableDlna` | Enable DLNA discovery | `false` |

### Persistence Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.config.enabled` | Enable config persistence | `true` |
| `persistence.config.size` | Config PVC size | `5Gi` |
| `persistence.config.storageClass` | Config storage class | `""` |
| `persistence.config.existingClaim` | Use existing PVC for config | `""` |
| `persistence.cache.enabled` | Enable cache persistence | `true` |
| `persistence.cache.size` | Cache PVC size | `10Gi` |
| `persistence.cache.storageClass` | Cache storage class | `""` |
| `persistence.cache.existingClaim` | Use existing PVC for cache | `""` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.ports` | Service ports | See `values.yaml` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts | `[]` |
| `ingress.tls` | Ingress TLS configuration | `[]` |

### Resource Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `4000m` |
| `resources.limits.memory` | Memory limit | `4Gi` |
| `resources.requests.cpu` | CPU request | `1000m` |
| `resources.requests.memory` | Memory request | `2Gi` |

## Hardware Acceleration

Jellyfin supports multiple hardware acceleration methods for efficient video transcoding.

### Intel QuickSync (QSV)

**Requirements:**
- Intel CPU with integrated graphics (6th gen+)
- `/dev/dri` device access
- `video` (GID 44) and `render` (GID 109) group membership

**Configuration:**

```yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "intel-qsv"
    intel:
      renderDevice: "/dev/dri/renderD128"

podSecurityContext:
  supplementalGroups:
    - 44   # video
    - 109  # render
```

**Verify GPU access:**

```bash
make jellyfin-check-gpu
```

### NVIDIA NVENC

**Requirements:**
- NVIDIA GPU (Maxwell architecture or newer)
- NVIDIA GPU Operator installed
- NVIDIA driver 522.25+ (for Jellyfin 10.10+)

**Configuration:**

```yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "nvidia-nvenc"
    nvidia:
      runtimeClassName: "nvidia"

nodeSelector:
  nvidia.com/gpu.present: "true"

resources:
  limits:
    nvidia.com/gpu: 1
```

**Verify GPU access:**

```bash
make jellyfin-check-gpu
```

### AMD VA-API

**Requirements:**
- AMD GPU with VA-API support
- `/dev/dri` device access

**Configuration:**

```yaml
jellyfin:
  hardwareAcceleration:
    enabled: true
    type: "amd-vaapi"
```

## Media Libraries

Configure media directories using PVCs or hostPath mounts:

### Using PersistentVolumeClaims

```yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      size: 100Gi
      storageClass: "fast-ssd"
    - name: tvshows
      mountPath: /media/tvshows
      size: 200Gi
      storageClass: "standard-hdd"
```

### Using Existing PVCs

```yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      existingClaim: "my-movies-pvc"
    - name: tvshows
      mountPath: /media/tvshows
      existingClaim: "my-tvshows-pvc"
```

### Using hostPath (Home Servers)

```yaml
jellyfin:
  mediaDirectories:
    - name: media
      mountPath: /media
      hostPath: /mnt/nas/media
      readOnly: false
```

## Operational Commands

This chart includes a comprehensive set of operational commands via Makefile.

### Access & Debugging

```bash
# Port forward to localhost
make jellyfin-port-forward

# Get access URL
make jellyfin-get-url

# View logs
make jellyfin-logs

# Open shell
make jellyfin-shell

# Restart deployment
make jellyfin-restart
```

### GPU & Configuration Checks

```bash
# Check GPU configuration and access
make jellyfin-check-gpu

# Check media directories
make jellyfin-check-media

# Check configuration directory
make jellyfin-check-config

# Check transcoding cache usage
make jellyfin-check-cache
```

### Cache Management

```bash
# Clear transcoding cache
make jellyfin-clear-cache
```

### Backup & Restore

```bash
# Backup configuration
make jellyfin-backup-config

# Restore configuration
make jellyfin-restore-config FILE=tmp/jellyfin-backups/backup.tar.gz
```

### Monitoring

```bash
# Show resource usage
make jellyfin-stats

# Describe pod
make jellyfin-describe

# Show pod events
make jellyfin-events
```

## Examples

### Example 1: Home Server with Intel QuickSync

```bash
helm install jellyfin scripton-charts/jellyfin \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=intel-qsv \
  --set jellyfin.mediaDirectories[0].name=media \
  --set jellyfin.mediaDirectories[0].mountPath=/media \
  --set jellyfin.mediaDirectories[0].hostPath=/mnt/media
```

### Example 2: Production with NVIDIA GPU and Ingress

```bash
helm install jellyfin scripton-charts/jellyfin \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=nvidia-nvenc \
  --set jellyfin.network.publishedServerUrl=https://jellyfin.example.com \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=jellyfin.example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --set ingress.tls[0].secretName=jellyfin-tls \
  --set ingress.tls[0].hosts[0]=jellyfin.example.com
```

### Example 3: Multiple Media Libraries

```yaml
# custom-values.yaml
jellyfin:
  mediaDirectories:
    - name: movies
      mountPath: /media/movies
      existingClaim: "movies-pvc"
    - name: tvshows
      mountPath: /media/tvshows
      existingClaim: "tvshows-pvc"
    - name: music
      mountPath: /media/music
      existingClaim: "music-pvc"
    - name: photos
      mountPath: /media/photos
      existingClaim: "photos-pvc"
  hardwareAcceleration:
    enabled: true
    type: "intel-qsv"
```

```bash
helm install jellyfin scripton-charts/jellyfin -f custom-values.yaml
```

## Initial Setup

After installation, complete the setup wizard:

1. **Access Jellyfin Web UI:**
   ```bash
   kubectl port-forward svc/jellyfin 8096:8096
   ```
   Open http://localhost:8096

2. **Create Admin Account:**
   - Set username and password
   - Complete language and timezone settings

3. **Add Media Libraries:**
   - Navigate to: Admin Dashboard > Libraries
   - Add libraries pointing to mounted paths (e.g., `/media/movies`)
   - Configure metadata providers

4. **Configure Hardware Acceleration:**
   - Navigate to: Admin Dashboard > Playback > Transcoding
   - Select hardware acceleration type:
     - Intel QSV: "Intel QuickSync (QSV)" or "Video Acceleration API (VA-API)"
     - NVIDIA: "NVIDIA NVENC"
     - AMD: "Video Acceleration API (VA-API)"
   - Enable hardware decoding and encoding

5. **Configure Remote Access (Optional):**
   - Set published server URL in chart values
   - Configure reverse proxy with WebSocket support
   - Enable HTTPS for secure streaming

## Troubleshooting

### GPU Not Detected

**Intel QSV:**
```bash
# Check device access
kubectl exec -it deployment/jellyfin -- ls -la /dev/dri

# Check supplemental groups
kubectl describe pod -l app.kubernetes.io/name=jellyfin | grep "Supplemental Groups"
```

**NVIDIA:**
```bash
# Check GPU availability
kubectl exec -it deployment/jellyfin -- nvidia-smi

# Check runtime class
kubectl get pod -l app.kubernetes.io/name=jellyfin -o yaml | grep runtimeClassName
```

### Transcoding Performance

1. **Check transcoding cache:**
   ```bash
   make jellyfin-check-cache
   ```

2. **Verify GPU is being used:**
   - Navigate to: Admin Dashboard > Playback > Activity
   - During playback, check if "(HW)" appears next to codec

3. **Monitor resource usage:**
   ```bash
   make jellyfin-stats
   ```

### Media Libraries Not Scanning

```bash
# Check media directory access
make jellyfin-check-media

# Check pod logs
make jellyfin-logs
```

## Migration from Other Charts

### From brianmcarey/jellyfin-helm

This chart differs from `brianmcarey/jellyfin-helm` in:
- **Persistence enabled by default** (production-ready)
- **Better GPU configuration** (Intel QSV, NVIDIA NVENC, AMD VA-API)
- **Operational commands** (Makefile targets)
- **Multiple media directory support**
- **Production features** (Ingress, NetworkPolicy, PodDisruptionBudget)

**Migration steps:**
1. Backup existing configuration: `make jellyfin-backup-config`
2. Export existing PVCs
3. Install this chart with existing PVCs
4. Restore configuration if needed

## Project Philosophy

This chart follows [ScriptonBasestar Helm Charts](https://github.com/scriptonbasestar-container/sb-helm-charts) principles:

- ✅ Configuration files over environment variables
- ✅ No external database dependencies (uses SQLite)
- ✅ Simple deployment structure
- ✅ Hardware acceleration support
- ✅ Production-ready defaults

## License

- **Chart License:** BSD-3-Clause
- **Jellyfin License:** GPL-2.0

## Links

- **Jellyfin Official:** https://jellyfin.org/
- **Jellyfin Documentation:** https://jellyfin.org/docs/
- **Docker Hub:** https://hub.docker.com/r/jellyfin/jellyfin
- **GitHub Repository:** https://github.com/jellyfin/jellyfin
- **Chart Repository:** https://github.com/scriptonbasestar-container/sb-helm-charts

## Support

For issues and feature requests, please open an issue at:
https://github.com/scriptonbasestar-container/sb-helm-charts/issues
