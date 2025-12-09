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

## Backup & Recovery

Comprehensive backup and recovery procedures for Jellyfin deployments.

### Backup Components

Jellyfin backup strategy covers 4 components:

| Component | Priority | Size | Backup Method |
|-----------|----------|------|---------------|
| **Config PVC** | 🔴 Critical | 100MB-1GB | tar, Restic, VolumeSnapshot |
| **Media Files** | 🔴 Critical | Variable (TB+) | NAS/External Backup |
| **Transcoding Cache** | ⚪ Skip | 5-50GB | Not backed up (rebuildable) |
| **Configuration** | 🟡 Important | <1MB | ConfigMap export |

### Quick Backup Commands

```bash
# Full backup (config + database + settings)
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Config-only backup (fastest)
make -f make/ops/jellyfin.mk jellyfin-backup-config

# Database-only backup (SQLite)
make -f make/ops/jellyfin.mk jellyfin-backup-database

# Check backup status
make -f make/ops/jellyfin.mk jellyfin-backup-status
```

**Output**: Backups saved to `tmp/jellyfin-backups/backup-YYYYMMDD-HHMMSS.tar.gz`

### Recovery Workflow

Complete disaster recovery in 4 steps:

```bash
# 1. Install fresh Jellyfin chart
helm install jellyfin sb-charts/jellyfin -f values.yaml

# 2. Restore configuration
make -f make/ops/jellyfin.mk jellyfin-restore-config \
  FILE=tmp/jellyfin-backups/backup-20250109-143022.tar.gz

# 3. Restore database (if separate backup)
make -f make/ops/jellyfin.mk jellyfin-restore-database \
  FILE=tmp/jellyfin-backups/library-db-20250109-143022.sql

# 4. Restart pod to apply changes
kubectl rollout restart deployment/jellyfin
```

**Validation**:
```bash
# Verify libraries restored
make -f make/ops/jellyfin.mk jellyfin-check-libraries

# Check plugin compatibility
make -f make/ops/jellyfin.mk jellyfin-check-plugins
```

### Backup Strategies

**1. Automated Daily Backups (Recommended)**

Create a CronJob for automated backups:

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: jellyfin-backup
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: jellyfin
          containers:
          - name: backup
            image: alpine:3.18
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache tar gzip
              cd /config
              tar czf /backup/config-$(date +%Y%m%d-%H%M%S).tar.gz .
              # Keep only last 7 days
              find /backup -name "config-*.tar.gz" -mtime +7 -delete
            volumeMounts:
            - name: config
              mountPath: /config
            - name: backup
              mountPath: /backup
          volumes:
          - name: config
            persistentVolumeClaim:
              claimName: jellyfin-config
          - name: backup
            persistentVolumeClaim:
              claimName: jellyfin-backups
          restartPolicy: OnFailure
```

**2. Restic Incremental Backups**

Efficient incremental backups with deduplication:

```bash
# Initialize Restic repository
export RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-backups/jellyfin
export RESTIC_PASSWORD=<secure-password>
restic init

# Backup config PVC
kubectl exec -it jellyfin-0 -- tar czf - /config | \
  restic backup --stdin --stdin-filename jellyfin-config.tar.gz

# Verify backup
restic snapshots

# Restore specific snapshot
restic restore latest --target /restore/
```

**3. Volume Snapshots (Fastest)**

Use Kubernetes VolumeSnapshot API for instant backups:

```yaml
# volumesnapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: jellyfin-config-snapshot
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: jellyfin-config
```

### Backup Best Practices

**DO:**
- ✅ Backup config PVC daily (contains SQLite database + metadata)
- ✅ Backup before upgrades
- ✅ Test restore procedures quarterly
- ✅ Store backups offsite (S3, NAS, etc.)
- ✅ Verify backup integrity with checksums

**DON'T:**
- ❌ Backup transcoding cache (temporary data, rebuildable)
- ❌ Rely on media file backups if on external NAS (separate concern)
- ❌ Store backups on same PVC

### Recovery Time Objectives (RTO/RPO)

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|----------|---------------------|---------------------|
| **Config Restore** | < 30 minutes | 24 hours |
| **Database Restore** | < 1 hour | 24 hours |
| **Full Disaster Recovery** | < 4 hours | 24 hours |
| **Media Library Rescan** | Variable (depends on library size) | N/A |

**For comprehensive backup procedures**, see [Jellyfin Backup Guide](../../docs/jellyfin-backup-guide.md).

---

## Security & RBAC

Role-Based Access Control (RBAC) and security features for Jellyfin deployments.

### RBAC Resources

This chart creates namespace-scoped RBAC resources:

**Resources Created:**
- `Role`: Defines permissions for Jellyfin operations
- `RoleBinding`: Binds Role to ServiceAccount
- `ServiceAccount`: Pod identity for RBAC

**Permissions Granted** (read-only):
```yaml
- configmaps: [get, list, watch]       # Configuration
- secrets: [get, list, watch]          # Credentials
- pods: [get, list, watch]             # Health checks
- services: [get, list, watch]         # Service discovery
- endpoints: [get, list, watch]        # Service discovery
- persistentvolumeclaims: [get, list, watch]  # Storage operations
```

### RBAC Configuration

**Enable/Disable RBAC:**

```yaml
# values.yaml
rbac:
  create: true  # Enable RBAC (default)
  annotations:
    description: "Jellyfin RBAC for config and media access"
```

**Disable RBAC** (not recommended):

```bash
helm install jellyfin sb-charts/jellyfin --set rbac.create=false
```

### Security Context

**Pod-level security:**

```yaml
# values.yaml
podSecurityContext:
  fsGroup: 1000          # Jellyfin user group
  runAsUser: 1000        # Jellyfin user
  runAsNonRoot: true
  supplementalGroups:    # Auto-added for GPU access
    - 44   # video group (Intel QSV, AMD VAAPI)
    - 109  # render group (Intel QSV, AMD VAAPI)
```

**Container-level security:**

```yaml
# values.yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Jellyfin needs write access to /tmp
```

### Network Policies

Restrict network access to Jellyfin:

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: jellyfin-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: jellyfin
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow HTTP traffic from ingress controller
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
      ports:
      - protocol: TCP
        port: 8096
    # Allow service discovery port
    - from:
      - namespaceSelector:
          matchLabels:
            name: default
      ports:
      - protocol: UDP
        port: 7359
  egress:
    # Allow DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53
    # Allow external metadata providers
    - to:
      - podSelector: {}
      ports:
      - protocol: TCP
        port: 443
```

### Security Best Practices

**DO:**
- ✅ Enable RBAC (default)
- ✅ Use non-root user (fsGroup: 1000)
- ✅ Apply NetworkPolicy to restrict traffic
- ✅ Enable TLS/SSL on ingress
- ✅ Use secrets for sensitive data
- ✅ Regularly update plugins and Jellyfin version

**DON'T:**
- ❌ Run as root user
- ❌ Disable RBAC in production
- ❌ Expose port 8096 directly (use ingress with TLS)
- ❌ Store credentials in ConfigMaps (use Secrets)

### RBAC Verification

**Verify RBAC resources:**

```bash
# Check Role
kubectl get role jellyfin-role -o yaml

# Check RoleBinding
kubectl get rolebinding jellyfin-rolebinding -o yaml

# Check ServiceAccount
kubectl get serviceaccount jellyfin -o yaml
```

**Test RBAC permissions:**

```bash
# Test read access to ConfigMaps
kubectl auth can-i get configmaps --as=system:serviceaccount:default:jellyfin
# Expected: yes

# Test write access to ConfigMaps (should fail)
kubectl auth can-i create configmaps --as=system:serviceaccount:default:jellyfin
# Expected: no
```

---

## Operations

Daily operations, monitoring, and maintenance for Jellyfin deployments.

### Daily Operations

**Access Jellyfin:**

```bash
# Get web UI URL
make -f make/ops/jellyfin.mk jellyfin-get-url

# Port forward to localhost:8096
make -f make/ops/jellyfin.mk jellyfin-port-forward
# Open http://localhost:8096
```

**Shell Access:**

```bash
# Interactive shell
make -f make/ops/jellyfin.mk jellyfin-shell

# Execute one-off command
kubectl exec -it deployment/jellyfin -- ls -la /config
```

**Log Management:**

```bash
# Tail logs (follow)
make -f make/ops/jellyfin.mk jellyfin-logs

# View last 100 lines
kubectl logs deployment/jellyfin --tail=100

# Search logs for errors
kubectl logs deployment/jellyfin | grep -i error
```

### Monitoring & Health Checks

**Resource Usage:**

```bash
# Show CPU/memory usage
make -f make/ops/jellyfin.mk jellyfin-stats

# Describe pod
make -f make/ops/jellyfin.mk jellyfin-describe

# Show events
make -f make/ops/jellyfin.mk jellyfin-events
```

**Health Endpoints:**

```bash
# Check liveness (port 8096)
kubectl exec deployment/jellyfin -- wget -qO- http://localhost:8096/health

# Check readiness
kubectl exec deployment/jellyfin -- wget -qO- http://localhost:8096/health
```

**Storage Usage:**

```bash
# Check config directory size
make -f make/ops/jellyfin.mk jellyfin-check-config

# Check transcoding cache usage
make -f make/ops/jellyfin.mk jellyfin-check-cache

# Check media directories
make -f make/ops/jellyfin.mk jellyfin-check-media
```

### Database Operations

Jellyfin uses SQLite for metadata storage.

**Database Backup:**

```bash
# Backup library.db (SQLite database)
make -f make/ops/jellyfin.mk jellyfin-backup-database

# Output: tmp/jellyfin-backups/library-db-YYYYMMDD-HHMMSS.sql
```

**Database Maintenance:**

```bash
# Vacuum database (reclaim space)
make -f make/ops/jellyfin.mk jellyfin-db-vacuum

# Check database integrity
make -f make/ops/jellyfin.mk jellyfin-db-check

# Analyze database (optimize query performance)
make -f make/ops/jellyfin.mk jellyfin-db-analyze
```

**Database Statistics:**

```bash
# Show database size and table counts
make -f make/ops/jellyfin.mk jellyfin-db-stats
```

### Plugin Management

**List Installed Plugins:**

```bash
# Show all installed plugins
make -f make/ops/jellyfin.mk jellyfin-list-plugins

# Check plugin versions
make -f make/ops/jellyfin.mk jellyfin-check-plugins
```

**Plugin Compatibility:**

```bash
# Before upgrading Jellyfin, check plugin compatibility
make -f make/ops/jellyfin.mk jellyfin-plugin-compatibility TARGET_VERSION=10.11.0
```

**Plugin Updates:**

Plugins are typically updated through the Jellyfin web UI:
1. Dashboard → Plugins
2. Catalog → Select plugin → Install
3. Restart Jellyfin

### Transcoding Operations

**Check GPU Status:**

```bash
# Verify GPU access and hardware acceleration
make -f make/ops/jellyfin.mk jellyfin-check-gpu
```

**Cache Management:**

```bash
# Check cache usage
make -f make/ops/jellyfin.mk jellyfin-check-cache

# Clear transcoding cache (WARNING: destroys in-progress transcodes)
make -f make/ops/jellyfin.mk jellyfin-clear-cache
```

**Transcoding Performance:**

```bash
# Monitor active transcodes
make -f make/ops/jellyfin.mk jellyfin-active-transcodes

# Check transcoding logs
kubectl logs deployment/jellyfin | grep -i "transcode"
```

### Performance Tuning

**Resource Adjustments:**

```bash
# Increase CPU/memory limits
helm upgrade jellyfin sb-charts/jellyfin \
  --reuse-values \
  --set resources.limits.cpu=8000m \
  --set resources.limits.memory=8Gi
```

**Cache Size Optimization:**

```bash
# Increase transcoding cache for more concurrent streams
helm upgrade jellyfin sb-charts/jellyfin \
  --reuse-values \
  --set persistence.cache.size=50Gi
```

**Enable GPU Acceleration** (if not already enabled):

```bash
# Intel QSV
helm upgrade jellyfin sb-charts/jellyfin \
  --reuse-values \
  --set jellyfin.hardwareAcceleration.enabled=true \
  --set jellyfin.hardwareAcceleration.type=intel-qsv
```

### Troubleshooting Common Issues

**Pod Not Starting:**

```bash
# Check pod events
make -f make/ops/jellyfin.mk jellyfin-events

# Check pod status
kubectl describe pod -l app.kubernetes.io/name=jellyfin

# Check logs
make -f make/ops/jellyfin.mk jellyfin-logs
```

**Media Library Not Scanning:**

```bash
# Check media directory mounts
make -f make/ops/jellyfin.mk jellyfin-check-media

# Trigger manual library scan (via web UI)
# Dashboard → Libraries → Scan All Libraries
```

**High CPU Usage:**

1. Enable GPU hardware acceleration (see Configuration section)
2. Reduce concurrent transcodes (Dashboard → Playback → Streaming)
3. Lower transcoding quality preset

**Database Corruption:**

```bash
# Check database integrity
make -f make/ops/jellyfin.mk jellyfin-db-check

# If corrupted, restore from backup
make -f make/ops/jellyfin.mk jellyfin-restore-database \
  FILE=tmp/jellyfin-backups/library-db-20250109-143022.sql
```

### Maintenance Windows

**Planned Maintenance:**

```bash
# 1. Backup before maintenance
make -f make/ops/jellyfin.mk jellyfin-full-backup

# 2. Scale down to 0 replicas
kubectl scale deployment jellyfin --replicas=0

# 3. Perform maintenance (upgrade, migrate, etc.)

# 4. Scale up
kubectl scale deployment jellyfin --replicas=1

# 5. Verify health
make -f make/ops/jellyfin.mk jellyfin-stats
```

---

## Upgrading

Comprehensive procedures for upgrading Jellyfin deployments.

### Pre-Upgrade Checklist

**CRITICAL: Complete these steps before upgrading:**

1. **Backup Everything:**
   ```bash
   make -f make/ops/jellyfin.mk jellyfin-full-backup
   ```

2. **Check Plugin Compatibility:**
   ```bash
   make -f make/ops/jellyfin.mk jellyfin-plugin-compatibility TARGET_VERSION=10.11.0
   ```

3. **Review Release Notes:**
   - [Jellyfin Releases](https://github.com/jellyfin/jellyfin/releases)
   - Check for breaking changes
   - Note FFmpeg version changes

4. **Verify Current State:**
   ```bash
   # Check current version
   kubectl get deployment jellyfin -o jsonpath='{.spec.template.spec.containers[0].image}'

   # Check pod health
   make -f make/ops/jellyfin.mk jellyfin-stats
   ```

5. **Check Storage Space:**
   ```bash
   # Ensure enough space for database migration
   make -f make/ops/jellyfin.mk jellyfin-check-config
   make -f make/ops/jellyfin.mk jellyfin-check-cache
   ```

6. **Test in Staging:**
   - Deploy same version to staging environment
   - Restore production backup to staging
   - Perform test upgrade
   - Validate functionality

7. **Plan Maintenance Window:**
   - **Minimal downtime**: Use Rolling Upgrade (3-5 minutes)
   - **Zero downtime**: Use Blue-Green Deployment (30-60 minutes setup)
   - **Full restart**: Use Maintenance Window (10-20 minutes)

8. **Notify Users:**
   - Announce upgrade window
   - Warn about brief service interruption

### Upgrade Strategies

This chart supports 3 upgrade strategies:

#### Strategy 1: Rolling Upgrade (Recommended)

**Minimal downtime (3-5 minutes)** - Recommended for production.

```bash
# 1. Backup first
make -f make/ops/jellyfin.mk jellyfin-full-backup

# 2. Update chart
helm upgrade jellyfin sb-charts/jellyfin \
  --reuse-values \
  --set image.tag=10.11.0

# 3. Monitor rollout
kubectl rollout status deployment/jellyfin

# 4. Verify health
make -f make/ops/jellyfin.mk jellyfin-stats
make -f make/ops/jellyfin.mk jellyfin-get-url
```

**Limitations:**
- ⚠️ Brief interruption during pod restart (SQLite locking)
- ⚠️ Active transcodes will be interrupted

#### Strategy 2: Blue-Green Deployment

**Low-risk with instant rollback capability.**

```bash
# 1. Deploy new version alongside old (green)
helm install jellyfin-green sb-charts/jellyfin \
  -f values.yaml \
  --set image.tag=10.11.0 \
  --set nameOverride=jellyfin-green

# 2. Share same PVCs
helm upgrade jellyfin-green sb-charts/jellyfin \
  --reuse-values \
  --set persistence.config.existingClaim=jellyfin-config \
  --set persistence.cache.existingClaim=jellyfin-cache

# 3. Validate new version
make -f make/ops/jellyfin.mk jellyfin-port-forward RELEASE=jellyfin-green
# Test at http://localhost:8096

# 4. Switch ingress to green
kubectl patch ingress jellyfin -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"jellyfin-green"}}}]}}]}}'

# 5. Verify traffic switched
make -f make/ops/jellyfin.mk jellyfin-get-url

# 6. Keep old version for 24h, then delete
helm uninstall jellyfin  # Delete old blue version
```

**Rollback (if issues):**
```bash
# Switch ingress back to blue
kubectl patch ingress jellyfin -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"jellyfin"}}}]}}]}}'
```

#### Strategy 3: Maintenance Window

**Simple upgrade with full downtime (10-20 minutes).**

```bash
# 1. Backup
make -f make/ops/jellyfin.mk jellyfin-full-backup

# 2. Uninstall old version
helm uninstall jellyfin

# 3. Install new version
helm install jellyfin sb-charts/jellyfin \
  -f values.yaml \
  --set image.tag=10.11.0

# 4. Verify
make -f make/ops/jellyfin.mk jellyfin-stats
```

**Use when:**
- ✅ Major version upgrade (10.x → 11.x)
- ✅ Database schema changes required
- ✅ Downtime is acceptable

### Post-Upgrade Validation

**Run these checks after every upgrade:**

```bash
# 1. Check pod status
kubectl get pods -l app.kubernetes.io/name=jellyfin

# 2. Verify version
kubectl exec deployment/jellyfin -- /jellyfin/jellyfin --version

# 3. Check logs for errors
make -f make/ops/jellyfin.mk jellyfin-logs | grep -i error

# 4. Test web UI
make -f make/ops/jellyfin.mk jellyfin-get-url

# 5. Verify libraries loaded
# Dashboard → Libraries → Check all libraries visible

# 6. Test playback
# Play a video file to ensure transcoding works

# 7. Verify GPU acceleration (if enabled)
make -f make/ops/jellyfin.mk jellyfin-check-gpu

# 8. Check plugin compatibility
make -f make/ops/jellyfin.mk jellyfin-check-plugins
```

**Automated validation script:**

```bash
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check
```

### Rollback Procedures

#### Rollback via Helm

```bash
# 1. List release history
helm history jellyfin

# 2. Rollback to previous revision
helm rollback jellyfin

# 3. Verify rollback
kubectl rollout status deployment/jellyfin
make -f make/ops/jellyfin.mk jellyfin-stats
```

#### Full Rollback (if Helm fails)

```bash
# 1. Uninstall current version
helm uninstall jellyfin

# 2. Reinstall old version
helm install jellyfin sb-charts/jellyfin \
  -f values-backup.yaml \
  --set image.tag=10.10.3  # Previous version

# 3. Restore from backup (if database corrupted)
make -f make/ops/jellyfin.mk jellyfin-restore-config \
  FILE=tmp/jellyfin-backups/backup-20250109-120000.tar.gz

# 4. Restart pod
kubectl rollout restart deployment/jellyfin
```

#### Blue-Green Rollback

```bash
# Switch ingress back to old version
kubectl patch ingress jellyfin -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"jellyfin"}}}]}}]}}'
```

### Version-Specific Upgrade Notes

#### 10.10.x → 10.11.x (Minor Version)

**Changes:**
- FFmpeg 7.x support
- New plugin API version
- Improved hardware acceleration

**Steps:**
1. Check plugin compatibility (some plugins may need updates)
2. Use Rolling Upgrade strategy
3. Verify hardware acceleration still works

#### 10.x → 11.x (Major Version)

**Breaking Changes:**
- Database schema changes
- Plugin API v3 (incompatible with v2 plugins)
- FFmpeg 8.x required

**Steps:**
1. **MANDATORY**: Full backup before upgrade
2. Update all plugins to v3-compatible versions
3. Use Maintenance Window strategy (expect 20-30 min downtime)
4. Database migration automatic on first start
5. Test all features thoroughly

### Upgrade Best Practices

**DO:**
- ✅ Always backup before upgrading
- ✅ Test upgrades in staging first
- ✅ Review release notes for breaking changes
- ✅ Check plugin compatibility
- ✅ Verify hardware acceleration after upgrade
- ✅ Keep old backups for 30 days
- ✅ Upgrade during low-usage periods

**DON'T:**
- ❌ Skip backups
- ❌ Upgrade multiple major versions at once
- ❌ Ignore plugin compatibility warnings
- ❌ Forget to test GPU acceleration after upgrade
- ❌ Delete old backups immediately

### Automated Upgrade Testing

**Create a test script:**

```bash
#!/bin/bash
# test-upgrade.sh

# 1. Deploy staging environment
helm install jellyfin-staging sb-charts/jellyfin -f values-staging.yaml

# 2. Restore production backup
make -f make/ops/jellyfin.mk jellyfin-restore-config \
  FILE=tmp/jellyfin-backups/prod-backup.tar.gz \
  RELEASE=jellyfin-staging

# 3. Upgrade to new version
helm upgrade jellyfin-staging sb-charts/jellyfin \
  --reuse-values \
  --set image.tag=10.11.0

# 4. Run validation tests
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check RELEASE=jellyfin-staging

# 5. Cleanup staging
helm uninstall jellyfin-staging
```

**For comprehensive upgrade procedures and version-specific notes**, see [Jellyfin Upgrade Guide](../../docs/jellyfin-upgrade-guide.md).

---

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

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

This Helm chart is licensed under the **BSD-3-Clause** license.

Jellyfin application is licensed under the **GNU GPL v2** license. See [Jellyfin License](https://github.com/jellyfin/jellyfin/blob/master/LICENSE) for details.
