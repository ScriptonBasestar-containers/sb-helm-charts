# WordPress Helm Chart - Comprehensive Backup & Recovery Guide

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Testing & Validation](#testing--validation)
7. [Automation](#automation)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

### Purpose

This guide provides comprehensive backup and recovery procedures for WordPress deployments using the Helm chart. WordPress requires backing up multiple components to ensure complete disaster recovery capability.

### Backup Philosophy

**Defense in Depth**: Multiple backup layers for complete protection
- **Layer 1**: WordPress content directory (uploads, plugins, themes)
- **Layer 2**: MySQL database (posts, pages, settings, users)
- **Layer 3**: Kubernetes configuration (ConfigMaps, Secrets, Helm values)
- **Layer 4**: PVC snapshots (disaster recovery)

**Recovery Objectives**:
- **RTO (Recovery Time Objective)**: < 2 hours (complete WordPress instance recovery)
- **RPO (Recovery Point Objective)**: 24 hours (daily backups), 1 hour (hourly for critical deployments)

### Prerequisites

- `kubectl` configured with access to the WordPress namespace
- `helm` CLI installed
- `mysql` client for database operations
- Access to backup storage location (S3, MinIO, NFS, local)
- Sufficient disk space for backup files

---

## Backup Strategy

### 4-Layer Backup Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    WordPress Backup Layers                       │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: WordPress Content (Uploads, Plugins, Themes)           │
│          - Full backup: tar archive                             │
│          - Incremental: rsync                                   │
│          - Size: Small to large (GB to TB)                      │
│          - Priority: Critical                                   │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: MySQL Database (Posts, Pages, Settings, Users)         │
│          - Full backup: mysqldump                               │
│          - Size: Small to medium (MB to GB)                     │
│          - Priority: Critical                                   │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: Kubernetes Configuration (ConfigMaps, Secrets, Helm)   │
│          - Full backup: kubectl export                          │
│          - Size: Very small (KB)                                │
│          - Priority: High                                       │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4: PVC Snapshots (Disaster Recovery)                      │
│          - Snapshot: VolumeSnapshot API                         │
│          - Size: Same as content directory                      │
│          - Priority: Medium                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Backup Frequency Recommendations

| Component | Recommended Frequency | Retention | Priority |
|-----------|----------------------|-----------|----------|
| **WordPress Content** | Hourly or Daily | 7 daily, 4 weekly, 12 monthly | Critical |
| **MySQL Database** | Daily (hourly for critical) | 7 daily, 4 weekly, 12 monthly | Critical |
| **Configuration** | On every change | Last 10 versions | High |
| **PVC Snapshots** | Weekly | 4 weekly, 3 monthly | Medium |

### Backup Tools & Methods

| Component | Tool | Method | Speed | Storage Efficiency |
|-----------|------|--------|-------|-------------------|
| WordPress Content (Full) | tar | `tar czf` | Medium | High (compressed) |
| WordPress Content (Incremental) | rsync | `rsync -av --delete` | Fast | Very High |
| MySQL Database | mysqldump | `mysqldump --single-transaction` | Fast | Medium |
| Configuration | kubectl | `kubectl get -o yaml` | Very Fast | N/A |
| PVC Snapshots | VolumeSnapshot | Kubernetes API | Fast | CSI-dependent |

---

## Backup Components

### Component 1: WordPress Content Directory

**What's Included**:
- `/var/www/html/wp-content/uploads/` - Media files, images, documents
- `/var/www/html/wp-content/plugins/` - Installed WordPress plugins
- `/var/www/html/wp-content/themes/` - WordPress themes
- `/var/www/html/wp-content/languages/` - Language files
- `/var/www/html/wp-content/upgrade/` - Temporary update files
- `/var/www/html/wp-config.php` - WordPress configuration (contains database credentials)

**Size**: Variable (typically 1GB - 100GB+, depending on media uploads)

**Backup Methods**:
1. **Full Backup (tar)**: Complete archive of all files
2. **Incremental Backup (rsync)**: Only changed files since last backup

**Recovery Time**: 10-30 minutes (depending on size)

---

### Component 2: MySQL Database

**What's Included**:
- WordPress posts and pages (`wp_posts`)
- Comments and metadata (`wp_comments`, `wp_commentmeta`)
- User accounts and roles (`wp_users`, `wp_usermeta`)
- WordPress settings and options (`wp_options`)
- Plugin and theme data (various plugin-specific tables)
- Taxonomy terms and relationships (`wp_terms`, `wp_term_taxonomy`, `wp_term_relationships`)

**Size**: Variable (typically 10MB - 10GB, depending on content volume)

**Backup Method**: `mysqldump` with `--single-transaction` (ensures consistency without locking)

**Recovery Time**: 5-15 minutes

---

### Component 3: Kubernetes Configuration

**What's Included**:
- **ConfigMaps**: WordPress environment variables
- **Secrets**: Database credentials, SMTP passwords, WordPress salts
- **Helm values**: Chart configuration
- **Kubernetes manifests**: Deployment, Service, Ingress, PVC definitions

**Size**: Very small (< 100KB)

**Recovery Time**: 5-10 minutes

---

### Component 4: PVC Snapshots

**What's Included**:
- Point-in-time snapshot of the entire WordPress content PVC
- Faster disaster recovery compared to file-level restore

**Size**: Same as WordPress content directory (but storage-efficient with copy-on-write)

**Recovery Time**: 5-10 minutes (snapshot restore)

**Note**: Requires CSI driver support for VolumeSnapshot API

---

## Backup Procedures

### Pre-Backup Checklist

Before performing backups, verify:

```bash
# 1. Verify WordPress pod is running
make -f make/ops/wordpress.mk wp-status

# 2. Check WordPress version
make -f make/ops/wordpress.mk wp-version

# 3. Verify database connectivity
make -f make/ops/wordpress.mk wp-db-check

# 4. Check disk space for backups
make -f make/ops/wordpress.mk wp-disk-usage
```

---

### Procedure 1: Full WordPress Content Backup (tar)

**Purpose**: Complete backup of all WordPress files (uploads, plugins, themes, config)

**Frequency**: Daily (or hourly for critical deployments)

**Storage Required**: ~Same as content directory size (compressed)

**Steps**:

```bash
# 1. Perform full content backup
make -f make/ops/wordpress.mk wp-backup-content-full

# This creates: backups/wordpress-content-full-YYYYMMDD-HHMMSS.tar.gz
```

**What Happens**:
1. Pod name is detected automatically
2. `tar` creates compressed archive of `/var/www/html/wp-content/` and `wp-config.php`
3. Archive is copied from pod to local `backups/` directory
4. Backup file is timestamped: `wordpress-content-full-20250108-143022.tar.gz`

**Manual Procedure** (if Makefile unavailable):

```bash
# 1. Get WordPress pod name
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

# 2. Create backup directory
mkdir -p backups

# 3. Create tar archive inside pod
kubectl exec -n wordpress $WP_POD -- tar czf /tmp/wordpress-content-backup.tar.gz \
  -C /var/www/html wp-content wp-config.php

# 4. Copy backup to local machine
kubectl cp wordpress/$WP_POD:/tmp/wordpress-content-backup.tar.gz \
  backups/wordpress-content-full-$(date +%Y%m%d-%H%M%S).tar.gz

# 5. Clean up temporary file in pod
kubectl exec -n wordpress $WP_POD -- rm /tmp/wordpress-content-backup.tar.gz
```

**Verification**:

```bash
# Check backup file exists and has reasonable size
ls -lh backups/wordpress-content-full-*.tar.gz

# Verify archive integrity
tar tzf backups/wordpress-content-full-20250108-143022.tar.gz | head -20
```

---

### Procedure 2: Incremental WordPress Content Backup (rsync)

**Purpose**: Efficient backup of only changed files since last backup

**Frequency**: Hourly (for critical deployments)

**Storage Required**: Much smaller than full backup (only changed files)

**Steps**:

```bash
# 1. Perform incremental content backup
make -f make/ops/wordpress.mk wp-backup-content-incremental

# This creates: backups/wordpress-content-incremental-YYYYMMDD-HHMMSS/
```

**What Happens**:
1. Pod name is detected automatically
2. `rsync` synchronizes `/var/www/html/wp-content/` to local directory
3. Only new/modified files are transferred
4. Directory is timestamped: `wordpress-content-incremental-20250108-150000/`

**Manual Procedure**:

```bash
# 1. Get WordPress pod name
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

# 2. Create backup directory
mkdir -p backups/wordpress-content-incremental-$(date +%Y%m%d-%H%M%S)

# 3. Use kubectl cp to copy content (rsync not available in standard WordPress image)
kubectl cp wordpress/$WP_POD:/var/www/html/wp-content \
  backups/wordpress-content-incremental-$(date +%Y%m%d-%H%M%S)/

# 4. Also backup wp-config.php
kubectl cp wordpress/$WP_POD:/var/www/html/wp-config.php \
  backups/wordpress-content-incremental-$(date +%Y%m%d-%H%M%S)/
```

---

### Procedure 3: MySQL Database Backup (mysqldump)

**Purpose**: Complete backup of WordPress database (posts, pages, settings, users)

**Frequency**: Daily (hourly for critical deployments)

**Storage Required**: Small to medium (10MB - 10GB)

**Steps**:

```bash
# 1. Perform MySQL database backup
make -f make/ops/wordpress.mk wp-backup-mysql

# This creates: backups/wordpress-mysql-YYYYMMDD-HHMMSS.sql.gz
```

**What Happens**:
1. Database credentials are extracted from WordPress Secret
2. `mysqldump` is executed with `--single-transaction` (no table locking)
3. SQL dump is compressed and timestamped
4. Backup file: `wordpress-mysql-20250108-143022.sql.gz`

**Manual Procedure**:

```bash
# 1. Get database credentials from Secret
export MYSQL_HOST=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_HOST}' | base64 -d)
export MYSQL_DATABASE=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_NAME}' | base64 -d)
export MYSQL_USER=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_USER}' | base64 -d)
export MYSQL_PASSWORD=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_PASSWORD}' | base64 -d)

# 2. Create backup directory
mkdir -p backups

# 3. Run mysqldump from WordPress pod (has mysql client)
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n wordpress $WP_POD -- mysqldump \
  --host=$MYSQL_HOST \
  --user=$MYSQL_USER \
  --password=$MYSQL_PASSWORD \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  $MYSQL_DATABASE | gzip > backups/wordpress-mysql-$(date +%Y%m%d-%H%M%S).sql.gz
```

**Backup Options Explained**:
- `--single-transaction`: Ensures consistent snapshot without locking tables (InnoDB)
- `--routines`: Includes stored procedures and functions
- `--triggers`: Includes table triggers
- `--events`: Includes scheduled events

**Verification**:

```bash
# Check backup file exists and has reasonable size
ls -lh backups/wordpress-mysql-*.sql.gz

# Verify SQL dump integrity
zcat backups/wordpress-mysql-20250108-143022.sql.gz | head -50

# Check for specific table exports
zcat backups/wordpress-mysql-20250108-143022.sql.gz | grep "CREATE TABLE"
```

---

### Procedure 4: Kubernetes Configuration Backup

**Purpose**: Backup Kubernetes resources for disaster recovery

**Frequency**: On every configuration change

**Storage Required**: Very small (< 100KB)

**Steps**:

```bash
# 1. Perform configuration backup
make -f make/ops/wordpress.mk wp-backup-config

# This creates: backups/wordpress-config-YYYYMMDD-HHMMSS.tar.gz
```

**What Happens**:
1. Exports all WordPress Kubernetes resources (ConfigMaps, Secrets, Deployment, Service, Ingress, PVC)
2. Exports Helm release values
3. Archives everything into timestamped tar.gz file

**Manual Procedure**:

```bash
# 1. Create backup directory
mkdir -p backups/wordpress-config-$(date +%Y%m%d-%H%M%S)
cd backups/wordpress-config-$(date +%Y%m%d-%H%M%S)

# 2. Export ConfigMaps
kubectl get configmap -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > configmaps.yaml

# 3. Export Secrets
kubectl get secret -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > secrets.yaml

# 4. Export Deployment
kubectl get deployment -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > deployment.yaml

# 5. Export Service
kubectl get service -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > service.yaml

# 6. Export Ingress
kubectl get ingress -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > ingress.yaml

# 7. Export PVC
kubectl get pvc -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > pvc.yaml

# 8. Export ServiceAccount
kubectl get serviceaccount -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > serviceaccount.yaml

# 9. Export RBAC resources
kubectl get role -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > role.yaml
kubectl get rolebinding -n wordpress -l app.kubernetes.io/name=wordpress -o yaml > rolebinding.yaml

# 10. Export Helm values
helm get values wordpress -n wordpress > helm-values.yaml

# 11. Archive configuration
cd ..
tar czf wordpress-config-$(date +%Y%m%d-%H%M%S).tar.gz wordpress-config-$(date +%Y%m%d-%H%M%S)/
rm -rf wordpress-config-$(date +%Y%m%d-%H%M%S)/
```

---

### Procedure 5: PVC Snapshot (VolumeSnapshot API)

**Purpose**: Point-in-time snapshot of WordPress content PVC for disaster recovery

**Frequency**: Weekly

**Storage Required**: Same as content directory (storage-efficient with CSI driver)

**Prerequisites**:
- CSI driver installed with snapshot support
- VolumeSnapshotClass configured

**Steps**:

```bash
# 1. Create PVC snapshot
make -f make/ops/wordpress.mk wp-snapshot-content

# This creates: wordpress-content-snapshot-YYYYMMDD-HHMMSS
```

**Manual Procedure**:

```bash
# 1. Create VolumeSnapshot manifest
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: wordpress-content-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: wordpress
spec:
  volumeSnapshotClassName: csi-snapclass  # Adjust to your VolumeSnapshotClass
  source:
    persistentVolumeClaimName: wordpress-content  # Adjust to your PVC name
EOF

# 2. Verify snapshot creation
kubectl get volumesnapshot -n wordpress

# 3. Check snapshot readyToUse status
kubectl get volumesnapshot wordpress-content-snapshot-20250108-143022 -n wordpress -o jsonpath='{.status.readyToUse}'
```

**List All Snapshots**:

```bash
# List all WordPress content snapshots
make -f make/ops/wordpress.mk wp-list-snapshots

# Manual command:
kubectl get volumesnapshot -n wordpress -l app.kubernetes.io/name=wordpress
```

---

### Procedure 6: Full Backup (All Components)

**Purpose**: Complete backup of all WordPress components in one operation

**Frequency**: Daily (before major changes or upgrades)

**Storage Required**: Sum of all component sizes

**Steps**:

```bash
# 1. Perform full backup (all components)
make -f make/ops/wordpress.mk wp-full-backup

# This creates:
# - backups/wordpress-content-full-YYYYMMDD-HHMMSS.tar.gz
# - backups/wordpress-mysql-YYYYMMDD-HHMMSS.sql.gz
# - backups/wordpress-config-YYYYMMDD-HHMMSS.tar.gz
```

**What Happens**:
1. Executes all backup procedures sequentially:
   - WordPress content backup (tar)
   - MySQL database backup (mysqldump)
   - Kubernetes configuration backup
2. All backups are timestamped with the same timestamp
3. Summary report is generated

**Manual Procedure**:

```bash
# Run all backup procedures with same timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# 1. WordPress content backup
make -f make/ops/wordpress.mk wp-backup-content-full

# 2. MySQL database backup
make -f make/ops/wordpress.mk wp-backup-mysql

# 3. Configuration backup
make -f make/ops/wordpress.mk wp-backup-config

echo "Full backup completed: $TIMESTAMP"
ls -lh backups/*$TIMESTAMP*
```

---

## Recovery Procedures

### Recovery Planning

**Recovery Scenarios**:

| Scenario | Components to Restore | RTO | Procedure |
|----------|----------------------|-----|-----------|
| **Lost Media Files** | WordPress content only | < 30 min | Restore content from tar/rsync |
| **Database Corruption** | MySQL database only | < 15 min | Restore database from mysqldump |
| **Full Instance Loss** | All components | < 2 hours | Full recovery procedure |
| **Accidental Plugin Delete** | WordPress content only | < 30 min | Restore content from tar/rsync |
| **Accidental Post Delete** | MySQL database only | < 15 min | Restore database from mysqldump |

---

### Recovery 1: Restore WordPress Content

**Purpose**: Restore WordPress files (uploads, plugins, themes) from backup

**When to Use**:
- Lost media files
- Corrupted plugins or themes
- Accidental file deletion
- Rollback after failed plugin/theme update

**Steps**:

```bash
# 1. Restore WordPress content from tar backup
make -f make/ops/wordpress.mk wp-restore-content BACKUP_FILE=backups/wordpress-content-full-20250108-143022.tar.gz
```

**Manual Procedure**:

```bash
# 1. Verify backup file exists
ls -lh backups/wordpress-content-full-20250108-143022.tar.gz

# 2. Get WordPress pod name
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

# 3. Copy backup to pod
kubectl cp backups/wordpress-content-full-20250108-143022.tar.gz \
  wordpress/$WP_POD:/tmp/wordpress-content-backup.tar.gz

# 4. Extract backup in pod (overwrites existing files)
kubectl exec -n wordpress $WP_POD -- tar xzf /tmp/wordpress-content-backup.tar.gz \
  -C /var/www/html

# 5. Fix file permissions
kubectl exec -n wordpress $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
kubectl exec -n wordpress $WP_POD -- chown www-data:www-data /var/www/html/wp-config.php

# 6. Clean up temporary file
kubectl exec -n wordpress $WP_POD -- rm /tmp/wordpress-content-backup.tar.gz

# 7. Restart WordPress pod to reload
kubectl rollout restart deployment/wordpress -n wordpress
```

**Verification**:

```bash
# 1. Check WordPress pod is running
kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress

# 2. Verify files were restored
kubectl exec -n wordpress $WP_POD -- ls -lh /var/www/html/wp-content/uploads/

# 3. Login to WordPress admin and verify media library
make -f make/ops/wordpress.mk wp-port-forward
# Open browser: http://localhost:8080/wp-admin
```

---

### Recovery 2: Restore MySQL Database

**Purpose**: Restore WordPress database from mysqldump backup

**When to Use**:
- Database corruption
- Accidental post/page deletion
- Rollback after failed database migration
- Lost user accounts or settings

**Steps**:

```bash
# 1. Restore MySQL database from backup
make -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=backups/wordpress-mysql-20250108-143022.sql.gz
```

**Manual Procedure**:

```bash
# 1. Verify backup file exists
ls -lh backups/wordpress-mysql-20250108-143022.sql.gz

# 2. Get database credentials
export MYSQL_HOST=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_HOST}' | base64 -d)
export MYSQL_DATABASE=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_NAME}' | base64 -d)
export MYSQL_USER=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_USER}' | base64 -d)
export MYSQL_PASSWORD=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_PASSWORD}' | base64 -d)

# 3. Get WordPress pod name (has mysql client)
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

# 4. Copy backup to pod
kubectl cp backups/wordpress-mysql-20250108-143022.sql.gz \
  wordpress/$WP_POD:/tmp/wordpress-mysql-backup.sql.gz

# 5. Restore database
kubectl exec -n wordpress $WP_POD -- bash -c \
  "zcat /tmp/wordpress-mysql-backup.sql.gz | mysql --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE"

# 6. Clean up temporary file
kubectl exec -n wordpress $WP_POD -- rm /tmp/wordpress-mysql-backup.sql.gz

# 7. Restart WordPress pod
kubectl rollout restart deployment/wordpress -n wordpress
```

**Verification**:

```bash
# 1. Check database connectivity
make -f make/ops/wordpress.mk wp-db-check

# 2. Verify table count
make -f make/ops/wordpress.mk wp-db-table-count

# 3. Login to WordPress admin and verify content
make -f make/ops/wordpress.mk wp-port-forward
# Open browser: http://localhost:8080/wp-admin
```

---

### Recovery 3: Restore Kubernetes Configuration

**Purpose**: Restore Kubernetes resources from backup

**When to Use**:
- Namespace accidentally deleted
- ConfigMaps or Secrets lost
- Need to recreate WordPress in different cluster

**Steps**:

```bash
# 1. Restore configuration from backup
make -f make/ops/wordpress.mk wp-restore-config BACKUP_FILE=backups/wordpress-config-20250108-143022.tar.gz
```

**Manual Procedure**:

```bash
# 1. Extract configuration backup
mkdir -p /tmp/wordpress-config-restore
tar xzf backups/wordpress-config-20250108-143022.tar.gz -C /tmp/wordpress-config-restore

# 2. Apply Kubernetes resources
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/configmaps.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/secrets.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/serviceaccount.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/role.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/rolebinding.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/pvc.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/deployment.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/service.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/ingress.yaml

# 3. Verify resources
kubectl get all -n wordpress

# 4. Clean up
rm -rf /tmp/wordpress-config-restore
```

---

### Recovery 4: Restore from PVC Snapshot

**Purpose**: Fast disaster recovery using VolumeSnapshot

**When to Use**:
- Complete content PVC loss
- Fastest recovery option
- Rollback after failed storage migration

**Steps**:

```bash
# 1. Restore from PVC snapshot
make -f make/ops/wordpress.mk wp-restore-from-snapshot SNAPSHOT_NAME=wordpress-content-snapshot-20250108-143022
```

**Manual Procedure**:

```bash
# 1. Scale down WordPress deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 2. Delete existing PVC (WARNING: This will delete current data!)
kubectl delete pvc wordpress-content -n wordpress

# 3. Create new PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-content
  namespace: wordpress
spec:
  storageClassName: standard  # Adjust to your storage class
  dataSource:
    name: wordpress-content-snapshot-20250108-143022
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi  # Must be >= original PVC size
EOF

# 4. Wait for PVC to be bound
kubectl get pvc wordpress-content -n wordpress -w

# 5. Scale up WordPress deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 6. Verify WordPress pod is running
kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -w
```

---

### Recovery 5: Full Disaster Recovery

**Purpose**: Complete WordPress instance recovery from backups

**When to Use**:
- Complete cluster failure
- Namespace accidentally deleted
- Migrating WordPress to new cluster

**RTO**: < 2 hours

**Prerequisites**:
- All backup files available
- New Kubernetes cluster (or existing cluster with namespace recreated)
- Helm installed and configured

**Steps**:

```bash
# 1. Perform full recovery
make -f make/ops/wordpress.mk wp-full-recovery \
  CONTENT_BACKUP=backups/wordpress-content-full-20250108-143022.tar.gz \
  MYSQL_BACKUP=backups/wordpress-mysql-20250108-143022.sql.gz \
  CONFIG_BACKUP=backups/wordpress-config-20250108-143022.tar.gz
```

**Manual Procedure**:

```bash
# ==========================
# Phase 1: Restore Configuration (10 minutes)
# ==========================

# 1. Create namespace
kubectl create namespace wordpress

# 2. Restore Kubernetes configuration
mkdir -p /tmp/wordpress-config-restore
tar xzf backups/wordpress-config-20250108-143022.tar.gz -C /tmp/wordpress-config-restore

# 3. Apply resources (order matters)
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/secrets.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/configmaps.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/serviceaccount.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/role.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/rolebinding.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/pvc.yaml

# Wait for PVC to be bound
kubectl get pvc -n wordpress -w

# 4. Apply workload resources
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/deployment.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/service.yaml
kubectl apply -f /tmp/wordpress-config-restore/wordpress-config-*/ingress.yaml

# ==========================
# Phase 2: Restore WordPress Content (30 minutes)
# ==========================

# 5. Wait for WordPress pod to be running
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 6. Get WordPress pod name
export WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')

# 7. Copy content backup to pod
kubectl cp backups/wordpress-content-full-20250108-143022.tar.gz \
  wordpress/$WP_POD:/tmp/wordpress-content-backup.tar.gz

# 8. Extract content backup
kubectl exec -n wordpress $WP_POD -- tar xzf /tmp/wordpress-content-backup.tar.gz \
  -C /var/www/html

# 9. Fix permissions
kubectl exec -n wordpress $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
kubectl exec -n wordpress $WP_POD -- chown www-data:www-data /var/www/html/wp-config.php

# ==========================
# Phase 3: Restore MySQL Database (15 minutes)
# ==========================

# 10. Copy database backup to pod
kubectl cp backups/wordpress-mysql-20250108-143022.sql.gz \
  wordpress/$WP_POD:/tmp/wordpress-mysql-backup.sql.gz

# 11. Get database credentials
export MYSQL_HOST=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_HOST}' | base64 -d)
export MYSQL_DATABASE=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_NAME}' | base64 -d)
export MYSQL_USER=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_USER}' | base64 -d)
export MYSQL_PASSWORD=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_PASSWORD}' | base64 -d)

# 12. Restore database
kubectl exec -n wordpress $WP_POD -- bash -c \
  "zcat /tmp/wordpress-mysql-backup.sql.gz | mysql --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE"

# ==========================
# Phase 4: Cleanup & Verification (5 minutes)
# ==========================

# 13. Clean up temporary files
kubectl exec -n wordpress $WP_POD -- rm /tmp/wordpress-content-backup.tar.gz
kubectl exec -n wordpress $WP_POD -- rm /tmp/wordpress-mysql-backup.sql.gz
rm -rf /tmp/wordpress-config-restore

# 14. Restart WordPress pod
kubectl rollout restart deployment/wordpress -n wordpress

# 15. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# ==========================
# Phase 5: Post-Recovery Validation
# ==========================

# 16. Verify WordPress version
make -f make/ops/wordpress.mk wp-version

# 17. Verify database connectivity
make -f make/ops/wordpress.mk wp-db-check

# 18. Verify database table count
make -f make/ops/wordpress.mk wp-db-table-count

# 19. Check disk usage
make -f make/ops/wordpress.mk wp-disk-usage

# 20. Login to WordPress admin
make -f make/ops/wordpress.mk wp-port-forward
# Open browser: http://localhost:8080/wp-admin

echo "Full disaster recovery completed successfully!"
```

---

## Testing & Validation

### Backup Testing Checklist

**Monthly Backup Testing**:

```bash
# 1. Verify backup files exist and are not corrupted
ls -lh backups/

# 2. Test content backup integrity
tar tzf backups/wordpress-content-full-latest.tar.gz | head -20

# 3. Test MySQL backup integrity
zcat backups/wordpress-mysql-latest.sql.gz | head -50

# 4. Test configuration backup integrity
tar tzf backups/wordpress-config-latest.tar.gz

# 5. Verify backup sizes are reasonable
du -sh backups/*
```

**Quarterly Restore Testing**:

```bash
# 1. Create test namespace
kubectl create namespace wordpress-restore-test

# 2. Perform full recovery in test namespace
# (Modify recovery procedure to use wordpress-restore-test namespace)

# 3. Verify WordPress functionality
# - Login to admin panel
# - View posts and pages
# - Upload media file
# - Install plugin
# - Change theme

# 4. Compare with production
# - Database table count should match
# - File count should match
# - User accounts should match

# 5. Clean up test namespace
kubectl delete namespace wordpress-restore-test
```

---

## Automation

### Automated Backup Script

Create `scripts/wordpress-backup.sh`:

```bash
#!/bin/bash
# WordPress Automated Backup Script
# Usage: ./scripts/wordpress-backup.sh

set -e

# Configuration
NAMESPACE="wordpress"
BACKUP_DIR="backups"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "Starting WordPress backup: $TIMESTAMP"

# 1. WordPress content backup
echo "Backing up WordPress content..."
make -f make/ops/wordpress.mk wp-backup-content-full

# 2. MySQL database backup
echo "Backing up MySQL database..."
make -f make/ops/wordpress.mk wp-backup-mysql

# 3. Configuration backup
echo "Backing up Kubernetes configuration..."
make -f make/ops/wordpress.mk wp-backup-config

# 4. Cleanup old backups (older than RETENTION_DAYS)
echo "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "wordpress-*" -type f -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully: $TIMESTAMP"
ls -lh "$BACKUP_DIR"/*$TIMESTAMP*
```

### Cron Schedule (Daily Backups)

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/scripts/wordpress-backup.sh >> /var/log/wordpress-backup.log 2>&1
```

### Kubernetes CronJob (Alternative)

**Note**: This example creates a CronJob inside the cluster.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: wordpress-backup
  namespace: wordpress
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: wordpress
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # WordPress content backup
              WP_POD=$(kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')
              kubectl exec -n wordpress $WP_POD -- tar czf /tmp/wordpress-content-backup.tar.gz -C /var/www/html wp-content wp-config.php
              kubectl cp wordpress/$WP_POD:/tmp/wordpress-content-backup.tar.gz /backups/wordpress-content-$(date +%Y%m%d-%H%M%S).tar.gz

              # MySQL database backup
              MYSQL_HOST=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_HOST}' | base64 -d)
              MYSQL_DATABASE=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_NAME}' | base64 -d)
              MYSQL_USER=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_USER}' | base64 -d)
              MYSQL_PASSWORD=$(kubectl get secret wordpress-secret -n wordpress -o jsonpath='{.data.WORDPRESS_DB_PASSWORD}' | base64 -d)

              kubectl exec -n wordpress $WP_POD -- mysqldump \
                --host=$MYSQL_HOST \
                --user=$MYSQL_USER \
                --password=$MYSQL_PASSWORD \
                --single-transaction \
                $MYSQL_DATABASE | gzip > /backups/wordpress-mysql-$(date +%Y%m%d-%H%M%S).sql.gz
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: wordpress-backup-pvc
```

---

## Troubleshooting

### Issue 1: Backup Fails - Disk Space

**Symptoms**:
```
tar: Error writing to archive: No space left on device
```

**Diagnosis**:

```bash
# Check disk usage on WordPress pod
make -f make/ops/wordpress.mk wp-disk-usage

# Check disk usage on local machine
df -h
du -sh backups/
```

**Solution**:

```bash
# Option 1: Clean up old backups
find backups/ -name "wordpress-*" -type f -mtime +30 -delete

# Option 2: Increase PVC size (if backing up to PVC)
kubectl patch pvc wordpress-backup-pvc -n wordpress -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Option 3: Use external backup storage (S3, MinIO, NFS)
```

---

### Issue 2: MySQL Restore Fails - Character Encoding

**Symptoms**:
```
ERROR 1366 (HY000) at line 1234: Incorrect string value
```

**Diagnosis**:

```bash
# Check database character set
kubectl exec -n wordpress $WP_POD -- mysql --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e "SHOW VARIABLES LIKE 'character_set%';"
```

**Solution**:

```bash
# Add character set options to mysqldump and restore
mysqldump --default-character-set=utf8mb4 ...
mysql --default-character-set=utf8mb4 ...
```

---

### Issue 3: Content Restore Fails - Permission Denied

**Symptoms**:
```
tar: wp-content/uploads: Cannot open: Permission denied
```

**Diagnosis**:

```bash
# Check file ownership in pod
kubectl exec -n wordpress $WP_POD -- ls -lh /var/www/html/wp-content/
```

**Solution**:

```bash
# Fix ownership after restore
kubectl exec -n wordpress $WP_POD -- chown -R www-data:www-data /var/www/html/wp-content
kubectl exec -n wordpress $WP_POD -- chown www-data:www-data /var/www/html/wp-config.php
kubectl exec -n wordpress $WP_POD -- chmod 755 /var/www/html/wp-content
kubectl exec -n wordpress $WP_POD -- chmod 644 /var/www/html/wp-config.php
```

---

### Issue 4: Snapshot Creation Fails - CSI Driver Not Installed

**Symptoms**:
```
error: unable to recognize "snapshot.yaml": no matches for kind "VolumeSnapshot" in version "snapshot.storage.k8s.io/v1"
```

**Diagnosis**:

```bash
# Check if VolumeSnapshot CRD exists
kubectl get crd volumesnapshots.snapshot.storage.k8s.io

# Check if CSI driver supports snapshots
kubectl get volumesnapshotclass
```

**Solution**:

```bash
# Install snapshot CRDs (if missing)
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml

# Install snapshot controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

---

## Best Practices

### 1. Backup Storage

**Best Practices**:
- ✅ Store backups in **different availability zone** than WordPress
- ✅ Use **S3-compatible storage** (AWS S3, MinIO, Ceph) for offsite backups
- ✅ Implement **3-2-1 backup rule**: 3 copies, 2 different media, 1 offsite
- ✅ Encrypt backups containing sensitive data (wp-config.php contains database credentials)
- ❌ Don't store backups only on the same PVC as WordPress

**Example: Upload to S3 after backup**:

```bash
# After backup, upload to S3
aws s3 cp backups/wordpress-content-full-20250108-143022.tar.gz \
  s3://my-backup-bucket/wordpress/content/ --storage-class GLACIER

aws s3 cp backups/wordpress-mysql-20250108-143022.sql.gz \
  s3://my-backup-bucket/wordpress/mysql/ --storage-class GLACIER
```

---

### 2. Testing

**Best Practices**:
- ✅ **Test restore procedures quarterly** in isolated namespace
- ✅ Verify backup integrity after each backup
- ✅ Document recovery time for each procedure
- ✅ Simulate disaster recovery scenarios
- ❌ Don't assume backups are valid without testing

---

### 3. Retention Policy

**Recommended Retention**:

| Backup Type | Retention Policy | Storage Cost | Recovery Likelihood |
|-------------|------------------|--------------|---------------------|
| **Daily** | 7 days | Medium | High |
| **Weekly** | 4 weeks | Low | Medium |
| **Monthly** | 12 months | Very Low (Glacier) | Low |
| **Yearly** | 7 years | Very Low (Deep Archive) | Very Low |

---

### 4. Security

**Best Practices**:
- ✅ Encrypt database backups (contain user passwords, even if hashed)
- ✅ Encrypt configuration backups (contain database credentials in wp-config.php)
- ✅ Use RBAC to restrict backup access
- ✅ Rotate backup encryption keys annually
- ❌ Don't commit backups to Git repositories

**Example: Encrypt backup with GPG**:

```bash
# Encrypt backup
gpg --symmetric --cipher-algo AES256 backups/wordpress-mysql-20250108-143022.sql.gz

# Decrypt for restore
gpg --decrypt backups/wordpress-mysql-20250108-143022.sql.gz.gpg > wordpress-mysql-20250108-143022.sql.gz
```

---

### 5. Monitoring

**Best Practices**:
- ✅ Monitor backup success/failure (alerting)
- ✅ Track backup size trends (detect anomalies)
- ✅ Alert on backup age (if last backup > 25 hours, alert)
- ✅ Monitor backup storage space

**Example: Prometheus Alert**:

```yaml
- alert: WordPressBackupTooOld
  expr: time() - wordpress_last_backup_timestamp > 86400
  for: 1h
  annotations:
    summary: "WordPress backup is too old"
    description: "Last backup was more than 24 hours ago"
```

---

### 6. Documentation

**Best Practices**:
- ✅ Document backup locations and credentials
- ✅ Maintain runbook for disaster recovery
- ✅ Document RTO/RPO for each component
- ✅ Keep backup encryption keys in secure vault (not Git)

---

## Summary

### Quick Reference

| Task | Command | RTO |
|------|---------|-----|
| **Full Backup** | `make -f make/ops/wordpress.mk wp-full-backup` | N/A |
| **Content Backup** | `make -f make/ops/wordpress.mk wp-backup-content-full` | N/A |
| **MySQL Backup** | `make -f make/ops/wordpress.mk wp-backup-mysql` | N/A |
| **Config Backup** | `make -f make/ops/wordpress.mk wp-backup-config` | N/A |
| **Snapshot** | `make -f make/ops/wordpress.mk wp-snapshot-content` | N/A |
| **Restore Content** | `make -f make/ops/wordpress.mk wp-restore-content BACKUP_FILE=...` | < 30 min |
| **Restore MySQL** | `make -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=...` | < 15 min |
| **Restore Config** | `make -f make/ops/wordpress.mk wp-restore-config BACKUP_FILE=...` | < 10 min |
| **Full Recovery** | `make -f make/ops/wordpress.mk wp-full-recovery CONTENT_BACKUP=... MYSQL_BACKUP=... CONFIG_BACKUP=...` | < 2 hours |

### Backup Components Summary

| Component | Size | Backup Method | Recovery Time | Priority |
|-----------|------|---------------|---------------|----------|
| **WordPress Content** | 1GB - 100GB+ | tar / rsync | 10-30 min | Critical |
| **MySQL Database** | 10MB - 10GB | mysqldump | 5-15 min | Critical |
| **Configuration** | < 100KB | kubectl export | 5-10 min | High |
| **PVC Snapshots** | Same as content | VolumeSnapshot | 5-10 min | Medium |

### Recovery Objectives

- **RTO (Recovery Time Objective)**: < 2 hours (complete instance recovery)
- **RPO (Recovery Point Objective)**: 24 hours (daily backups), 1 hour (hourly for critical)

---

**Related Documentation**:
- [WordPress Upgrade Guide](wordpress-upgrade-guide.md)
- [WordPress Chart README](../charts/wordpress/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)

**Last Updated**: 2025-12-08
