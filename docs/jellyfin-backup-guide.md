# Jellyfin Backup & Recovery Guide

## Overview

This guide provides comprehensive backup and recovery procedures for Jellyfin, a free and open-source media server. Jellyfin stores data across multiple components, and this guide covers strategies for protecting all aspects of your deployment.

### What Gets Backed Up

Jellyfin backup strategy involves four key components:

1. **Config PVC** - Jellyfin configuration, SQLite database, and metadata (most critical)
2. **Media Files** - Movies, TV shows, music (stored separately, often on NAS/external storage)
3. **Transcoding Cache** - Temporary transcoded files (can be rebuilt, lowest priority)
4. **Configuration** - Kubernetes resources, Helm values, and ConfigMaps

### Backup Strategy Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                   Jellyfin Backup Strategy                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ Config PVC       │  │ Media Files      │  │ Transcoding  │ │
│  │ (Database/Meta)  │  │ (Movies/TV/Music)│  │ Cache        │ │
│  │ Priority: HIGH   │  │ Priority: MEDIUM │  │ Priority: LOW│ │
│  └──────────────────┘  └──────────────────┘  └──────────────┘ │
│           │                     │                     │         │
│           ▼                     ▼                     ▼         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Backup Storage (S3/MinIO/NFS/Local)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────┐                                          │
│  │ Configuration    │                                          │
│  │ (Kubernetes)     │                                          │
│  │ Priority: HIGH   │                                          │
│  └──────────────────┘                                          │
│           │                                                     │
│           ▼                                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Backup Storage (S3/MinIO/NFS/Local)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Component | RTO | RPO | Notes |
|-----------|-----|-----|-------|
| Config PVC | < 30 minutes | 24 hours | Fast restore, small data volume |
| Media Files | < 4 hours | 7 days | Large data volume, depends on storage speed |
| Transcoding Cache | < 10 minutes | N/A | Can be skipped, will rebuild automatically |
| Configuration | < 10 minutes | On-change | Git-based versioning recommended |

**Overall RTO:** < 4 hours (primarily limited by media files restore time)
**Overall RPO:** 24 hours (daily config backups, weekly media backups recommended)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Component 1: Config PVC Backup](#component-1-config-pvc-backup)
3. [Component 2: Media Files Backup](#component-2-media-files-backup)
4. [Component 3: Transcoding Cache Backup](#component-3-transcoding-cache-backup)
5. [Component 4: Configuration Backup](#component-4-configuration-backup)
6. [Full Backup Procedures](#full-backup-procedures)
7. [Disaster Recovery Procedures](#disaster-recovery-procedures)
8. [Automated Backup Strategies](#automated-backup-strategies)
9. [Backup Verification](#backup-verification)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

```bash
# Install required CLI tools
# kubectl (Kubernetes CLI)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Optional: Restic for incremental backups
sudo apt-get install restic             # Debian/Ubuntu
brew install restic                     # macOS

# Optional: Rclone for cloud storage sync
sudo apt-get install rclone             # Debian/Ubuntu
brew install rclone                     # macOS
```

### Environment Variables

Create a backup configuration file:

```bash
# backup-config.env
export RELEASE_NAME="jellyfin"
export NAMESPACE="default"
export BACKUP_DIR="/backup/jellyfin"
export S3_BUCKET="jellyfin-backups"
export S3_ENDPOINT="s3.amazonaws.com"
export RETENTION_DAYS=30
```

Load the configuration:

```bash
source backup-config.env
```

### Access Requirements

Ensure you have:

1. **Kubernetes Access**: `kubectl` access to the cluster with appropriate RBAC permissions
2. **Storage Access**: Write permissions to backup destination (S3, NFS, local storage)
3. **Network Access**: Ability to reach Jellyfin pods and storage backends

### Storage Requirements

Estimate backup storage needs:

```bash
# Calculate config PVC size
kubectl get pvc -n $NAMESPACE ${RELEASE_NAME}-config -o jsonpath='{.status.capacity.storage}'

# Calculate media files size (if using PVC)
kubectl get pvc -n $NAMESPACE ${RELEASE_NAME}-media -o jsonpath='{.status.capacity.storage}'

# Estimate total backup size (Config + Media)
# Recommended: 1.5x config size + 1.2x media size
```

Typical storage estimates:
- **Small library** (< 500 movies/TV episodes): 50-200 GB
- **Medium library** (500-2,000 movies/TV episodes): 200 GB - 2 TB
- **Large library** (> 2,000 movies/TV episodes): 2-10 TB

---

## Component 1: Config PVC Backup

The config PVC contains Jellyfin configuration, SQLite database (library.db), metadata, posters, artwork, and user settings. This is the most critical component for recovery.

### 1.1 Direct PVC Backup (Using Helper Pod)

**Pros:** Simple, no special tools required
**Cons:** Slower for large databases

#### Create Backup Helper Pod

```bash
# Create a backup helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jellyfin-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: config
      mountPath: /config
      readOnly: true
  volumes:
  - name: config
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-config
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/jellyfin-backup-helper -n $NAMESPACE --timeout=120s
```

#### Backup Config Data

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/config/$(date +%Y%m%d)

# Backup using tar (with compression)
kubectl exec -n $NAMESPACE jellyfin-backup-helper -- \
  tar czf - /config | \
  cat > $BACKUP_DIR/config/$(date +%Y%m%d)/config.tar.gz

# Generate checksums
cd $BACKUP_DIR/config/$(date +%Y%m%d)
sha256sum config.tar.gz > config.tar.gz.sha256
```

#### Cleanup

```bash
# Delete backup helper pod
kubectl delete pod jellyfin-backup-helper -n $NAMESPACE
```

### 1.2 Restic Backup (Incremental, Recommended)

**Pros:** Incremental, deduplication, encryption, multiple backends
**Cons:** Requires Restic installation

#### Initialize Restic Repository

```bash
# Initialize Restic repository (one-time setup)
export RESTIC_REPOSITORY="s3:${S3_ENDPOINT}/${S3_BUCKET}/jellyfin-config"
export RESTIC_PASSWORD="your-secure-password"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

restic init
```

#### Backup with Restic

```bash
# Create backup helper pod with Restic
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jellyfin-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: restic/restic:latest
    command: ["sleep", "infinity"]
    env:
    - name: RESTIC_REPOSITORY
      value: "s3:${S3_ENDPOINT}/${S3_BUCKET}/jellyfin-config"
    - name: RESTIC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: restic-backup-secret
          key: password
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: s3-credentials
          key: access-key
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: s3-credentials
          key: secret-key
    volumeMounts:
    - name: config
      mountPath: /config
      readOnly: true
  volumes:
  - name: config
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-config
  restartPolicy: Never
EOF

# Run Restic backup
kubectl exec -n $NAMESPACE jellyfin-backup-helper -- \
  restic backup /config --tag daily --host jellyfin-config

# Check snapshots
kubectl exec -n $NAMESPACE jellyfin-backup-helper -- \
  restic snapshots

# Cleanup
kubectl delete pod jellyfin-backup-helper -n $NAMESPACE
```

### 1.3 Volume Snapshot (Fastest, Requires CSI Driver)

**Pros:** Near-instant, storage-level efficiency
**Cons:** Requires CSI snapshot support, vendor-specific

#### Create VolumeSnapshot

```bash
# Check if VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# Create VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: jellyfin-config-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapshot-class  # Adjust to your CSI driver
  source:
    persistentVolumeClaimName: ${RELEASE_NAME}-config
EOF

# Wait for snapshot to be ready
kubectl get volumesnapshot -n $NAMESPACE -w
```

### 1.4 SQLite Database-Specific Backup

**Important:** Jellyfin uses SQLite database files. For consistency, stop Jellyfin before backup or use SQLite backup commands.

```bash
# Backup SQLite database directly (requires sqlite3 in container)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db ".backup '/config/data/library.db.backup'"

# Copy backup file
kubectl cp $NAMESPACE/${RELEASE_NAME}-0:/config/data/library.db.backup \
  $BACKUP_DIR/config/$(date +%Y%m%d)/library.db.backup
```

### 1.5 Makefile Targets

```bash
# Backup config using tar
make -f make/ops/jellyfin.mk jellyfin-backup-config

# Backup config using Restic
make -f make/ops/jellyfin.mk jellyfin-backup-config-restic

# Create volume snapshot
make -f make/ops/jellyfin.mk jellyfin-snapshot-config

# Verify config backup
make -f make/ops/jellyfin.mk jellyfin-verify-config-backup
```

---

## Component 2: Media Files Backup

Media files (movies, TV shows, music) are typically stored on separate storage (NAS, NFS, or dedicated PVCs). Backup strategy depends on your storage setup.

### 2.1 Media on External NAS/NFS

**If media is stored on external NAS/NFS**, backup is typically handled at the storage level (NAS snapshots, RAID, replication).

**Jellyfin-specific considerations:**
- Jellyfin only stores metadata/posters in config PVC
- Original media files remain untouched on NAS
- No Jellyfin-specific backup needed (handled by NAS)

### 2.2 Media on Kubernetes PVC

**If media is stored on Kubernetes PVC**, backup the entire media PVC.

#### Backup Media PVC

```bash
# Create backup helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jellyfin-media-backup-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: backup
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: media
      mountPath: /media
      readOnly: true
  volumes:
  - name: media
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-media  # Adjust to your media PVC name
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/jellyfin-media-backup-helper -n $NAMESPACE --timeout=120s

# Backup media (this will take a LONG time for large libraries)
mkdir -p $BACKUP_DIR/media/$(date +%Y%m%d)
kubectl exec -n $NAMESPACE jellyfin-media-backup-helper -- \
  tar czf - /media | \
  cat > $BACKUP_DIR/media/$(date +%Y%m%d)/media.tar.gz

# Cleanup
kubectl delete pod jellyfin-media-backup-helper -n $NAMESPACE
```

### 2.3 Incremental Media Backup (Recommended for Large Libraries)

```bash
# Use Restic for incremental backups (only changed files)
export RESTIC_REPOSITORY="s3:${S3_ENDPOINT}/${S3_BUCKET}/jellyfin-media"
export RESTIC_PASSWORD="your-secure-password"

# Initialize repository (one-time)
restic init

# Run incremental backup
restic backup /media --tag weekly --host jellyfin-media
```

### 2.4 Media Verification

```bash
# Verify media file integrity
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  find /media -type f -name "*.mp4" -exec md5sum {} \; > media-checksums.txt
```

### 2.5 Makefile Targets

```bash
# Backup media PVC
make -f make/ops/jellyfin.mk jellyfin-backup-media

# Backup media incrementally
make -f make/ops/jellyfin.mk jellyfin-backup-media-restic

# Verify media files
make -f make/ops/jellyfin.mk jellyfin-verify-media
```

**Note:** Media backup is **MEDIUM priority**. If media is already backed up at the NAS level, skip Jellyfin-specific media backups.

---

## Component 3: Transcoding Cache Backup

The transcoding cache contains temporary transcoded files. Backing up this cache is **NOT recommended** as it can be rebuilt automatically.

### 3.1 Skip Transcoding Cache Backup

**Recommendation:** **Do NOT backup transcoding cache**

**Reasons:**
- Large data volume (10-100 GB)
- Temporary files that change frequently
- Jellyfin rebuilds cache automatically on demand
- No user data loss if cache is lost

### 3.2 Clear Transcoding Cache (If Needed)

```bash
# Clear transcoding cache to save storage
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  rm -rf /cache/transcoding-temp/*
```

### 3.3 Makefile Target

```bash
# Clear transcoding cache
make -f make/ops/jellyfin.mk jellyfin-clear-cache
```

---

## Component 4: Configuration Backup

Backing up Kubernetes configuration ensures you can recreate the exact deployment state.

### 4.1 Helm Values Backup

```bash
# Create backup directory
mkdir -p $BACKUP_DIR/k8s-config/$(date +%Y%m%d)

# Export current Helm values
helm get values $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/values.yaml

# Export full Helm release manifest
helm get manifest $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/manifest.yaml

# Export Helm release metadata
helm get all $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/release-full.yaml
```

### 4.2 Kubernetes Resources Backup

```bash
# Export all Jellyfin resources
kubectl get all -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/k8s-resources.yaml

# Export ConfigMaps
kubectl get configmap -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/configmaps.yaml

# Export Secrets (CAUTION: Contains sensitive data)
kubectl get secret -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o yaml > \
  $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/secrets.yaml

# Encrypt secrets backup
gpg --symmetric --cipher-algo AES256 $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/secrets.yaml
rm $BACKUP_DIR/k8s-config/$(date +%Y%m%d)/secrets.yaml  # Remove plaintext
```

### 4.3 Git-Based Configuration Management (Recommended)

```bash
# Initialize Git repository for configuration
cd $BACKUP_DIR/k8s-config
git init
git add values.yaml manifest.yaml
git commit -m "Backup Jellyfin config $(date +%Y%m%d)"
git remote add origin git@github.com:yourorg/jellyfin-config-backup.git
git push origin master
```

### 4.4 Makefile Targets

```bash
# Backup Helm values
make -f make/ops/jellyfin.mk jellyfin-backup-helm-config

# Backup all Kubernetes resources
make -f make/ops/jellyfin.mk jellyfin-backup-k8s-resources
```

---

## Full Backup Procedures

### 6.1 Full Backup Script

Create a comprehensive backup script:

```bash
#!/bin/bash
# jellyfin-full-backup.sh

set -euo pipefail

# Load configuration
source backup-config.env

# Create timestamped backup directory
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$BACKUP_TIMESTAMP"
mkdir -p "$BACKUP_PATH"

echo "Starting full Jellyfin backup: $BACKUP_TIMESTAMP"

# 1. Backup configuration (fastest, do first)
echo "[1/3] Backing up Kubernetes configuration..."
make -f make/ops/jellyfin.mk jellyfin-backup-helm-config

# 2. Backup config PVC (critical)
echo "[2/3] Backing up config PVC..."
make -f make/ops/jellyfin.mk jellyfin-backup-config-restic

# 3. Backup media (if using PVC, otherwise skip)
echo "[3/3] Backing up media files..."
make -f make/ops/jellyfin.mk jellyfin-backup-media-restic || echo "Media backup skipped (external NAS)"

# Generate backup manifest
cat > "$BACKUP_PATH/backup-manifest.txt" <<EOF
Jellyfin Full Backup
====================
Timestamp: $BACKUP_TIMESTAMP
Release: $RELEASE_NAME
Namespace: $NAMESPACE

Components:
- Kubernetes Configuration: ✓
- Config PVC: ✓
- Media Files: ✓ (or external NAS)

Backup Location: $BACKUP_PATH
EOF

echo "Full backup completed: $BACKUP_PATH"
```

### 6.2 Makefile Target

```bash
# Run full backup
make -f make/ops/jellyfin.mk jellyfin-full-backup
```

### 6.3 Backup Retention

```bash
# Delete backups older than retention period
find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# List current backups
ls -lh $BACKUP_DIR/
```

---

## Disaster Recovery Procedures

### 7.1 Full Recovery Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                  Disaster Recovery Workflow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Prepare Kubernetes Environment                              │
│     ├─ Create namespace                                         │
│     ├─ Restore secrets                                          │
│     └─ Verify storage (NAS/NFS mounts)                          │
│                                                                 │
│  2. Restore Configuration                                       │
│     ├─ Apply Helm values                                        │
│     └─ Verify configuration                                     │
│                                                                 │
│  3. Restore Config PVC                                          │
│     ├─ Create PVC                                               │
│     ├─ Restore config data from backup                          │
│     └─ Verify SQLite database integrity                         │
│                                                                 │
│  4. Restore Media Files (if using PVC)                          │
│     ├─ Create media PVC                                         │
│     ├─ Restore media from backup (or remount NAS)               │
│     └─ Verify media files                                       │
│                                                                 │
│  5. Deploy Jellyfin                                             │
│     ├─ Install Helm chart                                       │
│     ├─ Wait for pods to be ready                                │
│     └─ Verify application health                                │
│                                                                 │
│  6. Post-Recovery Validation                                    │
│     ├─ Test web interface                                       │
│     ├─ Verify library scan                                      │
│     ├─ Check user accounts and permissions                      │
│     └─ Test playback functionality                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Step-by-Step Recovery

#### Step 1: Prepare Kubernetes Environment

```bash
# Set recovery variables
export RELEASE_NAME="jellyfin"
export NAMESPACE="default"
export BACKUP_TIMESTAMP="20250115-143000"  # Adjust to your backup
export BACKUP_PATH="$BACKUP_DIR/$BACKUP_TIMESTAMP"

# Create namespace (if needed)
kubectl create namespace $NAMESPACE
```

#### Step 2: Restore Configuration

```bash
# Verify Helm values
cat $BACKUP_PATH/k8s-config/values.yaml

# Create custom values file for recovery
cp $BACKUP_PATH/k8s-config/values.yaml /tmp/jellyfin-recovery-values.yaml
```

#### Step 3: Restore Config PVC

```bash
# Option A: Restore from tar backup
# Create PVC
helm install $RELEASE_NAME scripton-charts/jellyfin -n $NAMESPACE \
  -f /tmp/jellyfin-recovery-values.yaml \
  --set jellyfin.enabled=false  # Install only PVCs

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${RELEASE_NAME}-config -n $NAMESPACE --timeout=300s

# Create restore helper pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jellyfin-restore-helper
  namespace: $NAMESPACE
spec:
  containers:
  - name: restore
    image: alpine:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: config
      mountPath: /config
  volumes:
  - name: config
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-config
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/jellyfin-restore-helper -n $NAMESPACE --timeout=120s

# Restore config data
cat $BACKUP_PATH/config/config.tar.gz | \
  kubectl exec -i -n $NAMESPACE jellyfin-restore-helper -- \
  tar xzf - -C /

# Cleanup
kubectl delete pod jellyfin-restore-helper -n $NAMESPACE

# Option B: Restore from Restic backup
# (Use same helper pod with Restic image, run restic restore)

# Option C: Restore from VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-config
  namespace: $NAMESPACE
spec:
  dataSource:
    name: jellyfin-config-snapshot-20250115-143000
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
```

#### Step 4: Restore Media Files (If Using PVC)

```bash
# If media is on external NAS/NFS, skip this step
# Just ensure NFS/NAS is accessible

# If media is on PVC, restore similarly to config PVC
cat $BACKUP_PATH/media/media.tar.gz | \
  kubectl exec -i -n $NAMESPACE jellyfin-media-restore-helper -- \
  tar xzf - -C /
```

#### Step 5: Deploy Jellyfin

```bash
# Install or upgrade Helm release
helm upgrade --install $RELEASE_NAME scripton-charts/jellyfin \
  -n $NAMESPACE \
  -f /tmp/jellyfin-recovery-values.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=600s

# Check deployment status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
```

#### Step 6: Post-Recovery Validation

```bash
# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 8096:8096 &
curl -I http://localhost:8096

# Verify library scan (login to web UI at http://localhost:8096 and verify):
# - User accounts are present
# - Libraries are visible
# - Media files are detected
# - Playback works

# Check Jellyfin logs
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --tail=50
```

### 7.3 Makefile Targets

```bash
# Full recovery (interactive)
make -f make/ops/jellyfin.mk jellyfin-full-recovery

# Recovery validation
make -f make/ops/jellyfin.mk jellyfin-post-recovery-check
```

---

## Automated Backup Strategies

### 8.1 CronJob-Based Backup

**Note:** As per chart design principles, automated backup CronJobs are **NOT included** in the Helm chart. Use external scheduling tools (Kubernetes CronJob, cron, systemd timers, etc.).

#### Create Backup CronJob

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: jellyfin-daily-backup
  namespace: $NAMESPACE
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: scripton/jellyfin-backup:latest  # Custom image with backup tools
            env:
            - name: BACKUP_DIR
              value: "/backup"
            - name: S3_BUCKET
              value: "jellyfin-backups"
            command:
            - /bin/bash
            - -c
            - |
              /scripts/jellyfin-full-backup.sh
          restartPolicy: OnFailure
EOF
```

### 8.2 Velero Integration

[Velero](https://velero.io/) provides disaster recovery for Kubernetes clusters.

#### Install Velero

```bash
# Install Velero CLI
brew install velero  # macOS
# or download from https://github.com/vmware-tanzu/velero/releases

# Install Velero in cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket jellyfin-velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=true \
  --backup-location-config region=us-east-1
```

#### Create Velero Backup

```bash
# Backup entire namespace
velero backup create jellyfin-backup-$(date +%Y%m%d) \
  --include-namespaces $NAMESPACE \
  --wait

# Backup specific resources
velero backup create jellyfin-backup-$(date +%Y%m%d) \
  --selector app.kubernetes.io/instance=$RELEASE_NAME \
  --include-namespaces $NAMESPACE \
  --wait

# Schedule daily backups
velero schedule create jellyfin-daily \
  --schedule="0 3 * * *" \
  --include-namespaces $NAMESPACE
```

#### Restore with Velero

```bash
# List backups
velero backup get

# Restore from backup
velero restore create --from-backup jellyfin-backup-20250115

# Restore to different namespace
velero restore create --from-backup jellyfin-backup-20250115 \
  --namespace-mappings default:jellyfin-recovery
```

---

## Backup Verification

### 9.1 Backup Integrity Checks

```bash
# Verify config backup checksums
cd $BACKUP_PATH/config
sha256sum -c config.tar.gz.sha256

# Verify Restic backup integrity
restic check
```

### 9.2 Test Restore (Dry Run)

```bash
# Create test namespace
kubectl create namespace jellyfin-test

# Restore to test namespace
# (Follow disaster recovery procedures in test namespace)

# Verify test restoration
kubectl exec -n jellyfin-test ${RELEASE_NAME}-0 -- \
  ls -la /config/data/library.db

# Cleanup test namespace
kubectl delete namespace jellyfin-test
```

### 9.3 Makefile Targets

```bash
# Verify all backup components
make -f make/ops/jellyfin.mk jellyfin-verify-backup

# Test restore in separate namespace
make -f make/ops/jellyfin.mk jellyfin-test-restore
```

---

## Best Practices

### 10.1 Backup Frequency Recommendations

| Component | Recommended Frequency | Reason |
|-----------|----------------------|--------|
| Config PVC | Daily | Critical metadata and database |
| Media Files | Weekly or skip | Large volume, rarely changes (if on NAS, handle at NAS level) |
| Transcoding Cache | Skip | Temporary files, rebuilds automatically |
| Configuration | On-change | Git-based versioning recommended |

### 10.2 3-2-1 Backup Rule

Follow the **3-2-1 backup rule**:
- **3 copies** of data (1 primary + 2 backups)
- **2 different media types** (local disk + cloud storage)
- **1 offsite backup** (different geographic location)

Example implementation:
```
Primary: Kubernetes PVC (local cluster)
Backup 1: NFS/local disk (same datacenter)
Backup 2: S3/cloud storage (different region)
```

### 10.3 Encryption

Always encrypt backups containing user data:

```bash
# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 $BACKUP_PATH/config/config.tar.gz

# Encrypt with OpenSSL
openssl enc -aes-256-cbc -salt -in config.tar.gz -out config.tar.gz.enc

# Restic uses encryption by default
export RESTIC_PASSWORD="your-secure-password"
```

### 10.4 Monitoring and Alerting

Monitor backup job success:

```bash
# Create Prometheus alert rule
groups:
- name: jellyfin-backup
  rules:
  - alert: JellyfinBackupFailed
    expr: time() - jellyfin_last_successful_backup_timestamp > 86400
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "Jellyfin backup failed or hasn't run in 24 hours"
```

---

## Troubleshooting

### 11.1 Common Issues

#### Issue: Backup Job Fails with "No space left on device"

**Cause:** Backup destination storage is full

**Solution:**
```bash
# Check backup destination storage
df -h $BACKUP_DIR

# Clean up old backups
find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# Increase storage allocation or change backup destination
export BACKUP_DIR="/mnt/large-storage/jellyfin-backups"
```

#### Issue: SQLite database corruption after restore

**Cause:** Database was backed up while Jellyfin was running

**Solution:**
```bash
# Always stop Jellyfin before backing up SQLite database
kubectl scale deployment ${RELEASE_NAME} -n $NAMESPACE --replicas=0

# Wait for pod to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=60s

# Run backup
make -f make/ops/jellyfin.mk jellyfin-backup-config

# Restart Jellyfin
kubectl scale deployment ${RELEASE_NAME} -n $NAMESPACE --replicas=1
```

#### Issue: Media files not appearing after restore

**Cause:** NFS/NAS mount not configured, or media PVC not restored

**Solution:**
```bash
# Check media mount
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- ls -la /media

# Verify NFS/NAS is accessible
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- df -h | grep media

# If using PVC, verify PVC is bound
kubectl get pvc -n $NAMESPACE ${RELEASE_NAME}-media
```

#### Issue: Restic backup extremely slow

**Cause:** Large number of small files, slow network

**Solution:**
```bash
# Use tar + Restic for better performance
tar czf - /config | restic backup --stdin --stdin-filename config.tar.gz

# Increase Restic parallelism
restic backup /config -o s3.connections=10

# Use local backup destination first, then sync to S3
restic backup /config --repo /local/backup
rclone sync /local/backup s3:jellyfin-backups/restic
```

### 11.2 Recovery Failures

#### Issue: Jellyfin doesn't start after restore

**Cause:** File permissions mismatch, corrupted database

**Solution:**
```bash
# Check file ownership
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- ls -la /config

# Fix file ownership (if needed)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- chown -R 1000:1000 /config

# Check database integrity
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "PRAGMA integrity_check;"
```

### 11.3 Makefile Targets

```bash
# Troubleshoot backup issues
make -f make/ops/jellyfin.mk jellyfin-troubleshoot-backup

# Check backup storage
make -f make/ops/jellyfin.mk jellyfin-check-backup-storage

# Verify backup integrity
make -f make/ops/jellyfin.mk jellyfin-verify-backup
```

---

## Summary

### Key Takeaways

1. **Backup Strategy**: Focus on Config PVC (highest priority), Media optional (if on external NAS)
2. **RTO/RPO**: < 4 hours recovery time, 24-hour recovery point with daily backups
3. **Tools**: Use Restic for incremental backups, VolumeSnapshot for fastest backups
4. **Automation**: Use external CronJob or systemd timers (not in Helm chart)
5. **Verification**: Always verify backups and test recovery procedures
6. **3-2-1 Rule**: Keep 3 copies on 2 different media with 1 offsite

### Quick Reference

```bash
# Full backup
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Full recovery
make -f make/ops/jellyfin.mk jellyfin-full-recovery

# Verify backup
make -f make/ops/jellyfin.mk jellyfin-verify-backup
```

### Related Documentation

- [Jellyfin Upgrade Guide](jellyfin-upgrade-guide.md)
- [Jellyfin README](../charts/jellyfin/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)

---

**Last Updated:** 2025-01-27
**Version:** 1.0.0
