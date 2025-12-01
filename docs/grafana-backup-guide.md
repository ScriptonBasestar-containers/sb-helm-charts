# Grafana Backup and Recovery Guide

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Components](#backup-components)
  - [1. Grafana Configuration Backup](#1-grafana-configuration-backup)
  - [2. SQLite Database Backup](#2-sqlite-database-backup)
  - [3. Dashboards and Datasources Export](#3-dashboards-and-datasources-export)
  - [4. Plugins and Provisioning Backup](#4-plugins-and-provisioning-backup)
  - [5. PVC Snapshot Backup](#5-pvc-snapshot-backup)
- [Recovery Procedures](#recovery-procedures)
  - [Configuration Recovery](#configuration-recovery)
  - [Database Recovery](#database-recovery)
  - [Dashboards and Datasources Recovery](#dashboards-and-datasources-recovery)
  - [Full Disaster Recovery](#full-disaster-recovery)
- [Backup Automation](#backup-automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for backing up and recovering Grafana instances deployed via the Helm chart.

**Backup Philosophy:**
- **Multi-layered approach**: Configuration, database, dashboards, plugins, PVC snapshots
- **Granular recovery**: Restore individual dashboards or complete instance
- **Minimal downtime**: Most backups can be performed without service interruption
- **Version compatibility**: Consider Grafana version when restoring backups

**Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO):**
- **RTO Target**: < 1 hour for complete Grafana instance recovery
- **RPO Target**: 24 hours (daily backups recommended)
- **Dashboard Recovery**: < 15 minutes (via API export/import)
- **Database Recovery**: < 30 minutes (SQLite restore)

---

## Backup Strategy

Grafana backup strategy consists of five complementary components:

### 1. **Grafana Configuration Backup**
- **What**: grafana.ini, ConfigMaps, Secrets
- **Why**: Contains server settings, authentication, security configuration
- **Frequency**: On every configuration change
- **Method**: Kubernetes resource export

### 2. **SQLite Database Backup**
- **What**: grafana.db (users, orgs, preferences, annotations, playlists)
- **Why**: Core Grafana metadata and user data
- **Frequency**: Daily (before major changes)
- **Method**: File copy while Grafana is stopped or SQLite backup command

### 3. **Dashboards and Datasources Export**
- **What**: Dashboard JSON, datasource configurations
- **Why**: Critical visualization and data source definitions
- **Frequency**: Daily or on-demand via API
- **Method**: Grafana HTTP API export

### 4. **Plugins and Provisioning Backup**
- **What**: Installed plugins, provisioning YAML files
- **Why**: Custom functionality and automated configuration
- **Frequency**: On plugin installation or provisioning changes
- **Method**: Directory copy and plugin list export

### 5. **PVC Snapshot Backup**
- **What**: Persistent volume containing all Grafana data
- **Why**: Complete point-in-time recovery capability
- **Frequency**: Weekly
- **Method**: VolumeSnapshot API

**Backup Priority Matrix:**

| Component | Priority | Frequency | Method | Size |
|-----------|----------|-----------|--------|------|
| Dashboards/Datasources | Critical | Daily | API Export | Small (KB-MB) |
| SQLite Database | Critical | Daily | File Copy | Small (MB) |
| Configuration | High | On Change | K8s Export | Tiny (KB) |
| Plugins/Provisioning | Medium | On Change | Directory Copy | Medium (MB) |
| PVC Snapshot | High | Weekly | VolumeSnapshot | Large (GB) |

---

## Backup Components

### 1. Grafana Configuration Backup

Grafana configuration includes ConfigMaps, Secrets, and the grafana.ini file.

#### 1.1 Backup ConfigMaps

Export all Grafana ConfigMaps:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-backup-config

# Manual backup
kubectl get configmap grafana-config -n <namespace> -o yaml > grafana-config-backup-$(date +%Y%m%d-%H%M%S).yaml

# Backup all ConfigMaps with Grafana label
kubectl get configmaps -n <namespace> -l app.kubernetes.io/name=grafana -o yaml > grafana-configmaps-backup-$(date +%Y%m%d-%H%M%S).yaml
```

#### 1.2 Backup Secrets

Export Grafana Secrets (admin password, secret key):

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-backup-secrets

# Manual backup
kubectl get secret grafana-secret -n <namespace> -o yaml > grafana-secret-backup-$(date +%Y%m%d-%H%M%S).yaml

# IMPORTANT: Store secrets backup in secure location (encrypted storage, vault)
# Encrypt secrets backup file
gpg --symmetric --cipher-algo AES256 grafana-secret-backup-$(date +%Y%m%d-%H%M%S).yaml
```

#### 1.3 Backup grafana.ini

If using custom grafana.ini via ConfigMap:

```bash
# Extract grafana.ini from ConfigMap
kubectl get configmap grafana-config -n <namespace> -o jsonpath='{.data.grafana\.ini}' > grafana.ini.backup

# Verify backup
cat grafana.ini.backup
```

#### 1.4 Verify Configuration Backup

```bash
# List all backed up configuration files
ls -lh grafana-*-backup-*.yaml

# Verify ConfigMap structure
kubectl get configmap grafana-config -n <namespace> -o yaml | head -20

# Verify Secrets exist (values will be base64 encoded)
kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data}' | jq
```

---

### 2. SQLite Database Backup

Grafana uses SQLite by default for storing users, organizations, dashboards, datasources, annotations, and playlists.

#### 2.1 Database Location

Default SQLite database location: `/var/lib/grafana/grafana.db`

#### 2.2 Online Backup (Grafana Running)

SQLite supports online backups using the `.backup` command:

```bash
# Using Makefile (recommended - handles locking)
make -f make/ops/grafana.mk grafana-backup-db

# Manual online backup
kubectl exec -n <namespace> deployment/grafana -- sqlite3 /var/lib/grafana/grafana.db ".backup /var/lib/grafana/grafana-backup-$(date +%Y%m%d-%H%M%S).db"

# Copy backup file from pod to local machine
kubectl cp <namespace>/grafana-pod-name:/var/lib/grafana/grafana-backup-YYYYMMDD-HHMMSS.db ./grafana-backup-$(date +%Y%m%d-%H%M%S).db
```

#### 2.3 Offline Backup (Grafana Stopped)

For guaranteed consistency, stop Grafana before backup:

```bash
# Using Makefile (handles scaling down/up)
make -f make/ops/grafana.mk grafana-backup-db-offline

# Manual offline backup
# 1. Scale down Grafana deployment
kubectl scale deployment grafana -n <namespace> --replicas=0

# 2. Wait for pod termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=60s

# 3. Create a temporary pod to access PVC
kubectl run grafana-backup-pod -n <namespace> \
  --image=alpine:3.19 \
  --restart=Never \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "backup",
      "image": "alpine:3.19",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "name": "grafana-data",
        "mountPath": "/var/lib/grafana"
      }]
    }],
    "volumes": [{
      "name": "grafana-data",
      "persistentVolumeClaim": {
        "claimName": "grafana-data"
      }
    }]
  }
}'

# 4. Wait for backup pod
kubectl wait --for=condition=ready pod/grafana-backup-pod -n <namespace> --timeout=60s

# 5. Copy database file
kubectl cp <namespace>/grafana-backup-pod:/var/lib/grafana/grafana.db ./grafana-db-backup-$(date +%Y%m%d-%H%M%S).db

# 6. Cleanup backup pod
kubectl delete pod grafana-backup-pod -n <namespace>

# 7. Scale up Grafana deployment
kubectl scale deployment grafana -n <namespace> --replicas=1
```

#### 2.4 Database Integrity Check

Verify database backup integrity:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-db-integrity-check

# Manual integrity check
sqlite3 grafana-db-backup-YYYYMMDD-HHMMSS.db "PRAGMA integrity_check;"
# Expected output: ok

# Check database size
ls -lh grafana-db-backup-*.db

# Query database for basic info
sqlite3 grafana-db-backup-YYYYMMDD-HHMMSS.db <<EOF
.tables
SELECT COUNT(*) FROM dashboard;
SELECT COUNT(*) FROM data_source;
SELECT COUNT(*) FROM user;
EOF
```

---

### 3. Dashboards and Datasources Export

Grafana's HTTP API allows exporting dashboards and datasources as JSON.

#### 3.1 Prerequisites

Get Grafana admin credentials:

```bash
# Get admin password from secret
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)

# Get Grafana URL
GRAFANA_URL="http://localhost:3000"  # If using port-forward
# OR
GRAFANA_URL="https://grafana.example.com"  # If using ingress

# Setup port-forward if needed
kubectl port-forward -n <namespace> svc/grafana 3000:80 &
```

#### 3.2 Export All Dashboards

Export all dashboards using Grafana API:

```bash
# Using Makefile (exports all dashboards to backups/ directory)
make -f make/ops/grafana.mk grafana-backup-dashboards

# Manual export script
BACKUP_DIR="grafana-dashboards-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Get all dashboard UIDs
DASHBOARD_UIDS=$(curl -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[].uid')

# Export each dashboard
for uid in $DASHBOARD_UIDS; do
  echo "Exporting dashboard: $uid"
  curl -s -u admin:$GRAFANA_PASSWORD \
    "$GRAFANA_URL/api/dashboards/uid/$uid" | jq '.dashboard' > "$BACKUP_DIR/dashboard-$uid.json"
done

echo "Dashboards exported to $BACKUP_DIR/"
ls -lh "$BACKUP_DIR/"
```

#### 3.3 Export Single Dashboard

Export a specific dashboard by UID:

```bash
# Get dashboard UID from Grafana UI or API
DASHBOARD_UID="your-dashboard-uid"

# Export dashboard JSON
curl -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.dashboard' > "dashboard-$DASHBOARD_UID-$(date +%Y%m%d-%H%M%S).json"

# Verify export
jq '.title, .uid, .version' "dashboard-$DASHBOARD_UID-*.json"
```

#### 3.4 Export All Datasources

Export all datasource configurations:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-backup-datasources

# Manual export
BACKUP_DIR="grafana-datasources-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Export all datasources
curl -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/datasources" > "$BACKUP_DIR/datasources.json"

# Export individual datasources
DATASOURCE_IDS=$(curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/datasources" | jq -r '.[].id')

for id in $DATASOURCE_IDS; do
  echo "Exporting datasource ID: $id"
  curl -s -u admin:$GRAFANA_PASSWORD \
    "$GRAFANA_URL/api/datasources/$id" > "$BACKUP_DIR/datasource-$id.json"
done

echo "Datasources exported to $BACKUP_DIR/"
```

#### 3.5 Export Folders

Export dashboard folders structure:

```bash
# Export all folders
curl -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/folders" > grafana-folders-backup-$(date +%Y%m%d-%H%M%S).json

# Verify folders
jq '.[] | {id, uid, title}' grafana-folders-backup-*.json
```

#### 3.6 Export Snapshots

Export dashboard snapshots (if using):

```bash
# List all snapshots
curl -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/dashboard/snapshots" > grafana-snapshots-backup-$(date +%Y%m%d-%H%M%S).json
```

#### 3.7 Verify Dashboard Exports

```bash
# Count exported dashboards
DASHBOARD_COUNT=$(ls -1 grafana-dashboards-backup-*/dashboard-*.json | wc -l)
echo "Exported $DASHBOARD_COUNT dashboards"

# Verify dashboard JSON structure
jq 'keys' grafana-dashboards-backup-*/dashboard-*.json | head -20

# Check for common dashboard properties
jq '.title, .uid, .version, .panels | length' grafana-dashboards-backup-*/dashboard-*.json
```

---

### 4. Plugins and Provisioning Backup

Grafana plugins and provisioning configurations should be backed up for complete recovery.

#### 4.1 Backup Installed Plugins

Export list of installed plugins:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-backup-plugins

# Manual plugin list export
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls > grafana-plugins-list-$(date +%Y%m%d-%H%M%S).txt

# Verify plugins list
cat grafana-plugins-list-*.txt
```

#### 4.2 Backup Plugin Data

Some plugins store data in `/var/lib/grafana/plugins`:

```bash
# Backup plugins directory
kubectl exec -n <namespace> deployment/grafana -- tar czf /tmp/grafana-plugins-backup.tar.gz /var/lib/grafana/plugins

# Copy plugins backup from pod
kubectl cp <namespace>/grafana-pod-name:/tmp/grafana-plugins-backup.tar.gz ./grafana-plugins-backup-$(date +%Y%m%d-%H%M%S).tar.gz

# Cleanup temporary file
kubectl exec -n <namespace> deployment/grafana -- rm /tmp/grafana-plugins-backup.tar.gz
```

#### 4.3 Backup Provisioning Configurations

If using Grafana provisioning for dashboards/datasources:

```bash
# Backup provisioning directory
kubectl exec -n <namespace> deployment/grafana -- tar czf /tmp/grafana-provisioning-backup.tar.gz /etc/grafana/provisioning

# Copy provisioning backup from pod
kubectl cp <namespace>/grafana-pod-name:/tmp/grafana-provisioning-backup.tar.gz ./grafana-provisioning-backup-$(date +%Y%m%d-%H%M%S).tar.gz

# Cleanup
kubectl exec -n <namespace> deployment/grafana -- rm /tmp/grafana-provisioning-backup.tar.gz

# Verify backup
tar tzf grafana-provisioning-backup-*.tar.gz | head -20
```

#### 4.4 Backup Custom Plugins (if installed)

If custom plugins are installed:

```bash
# List custom plugins
kubectl exec -n <namespace> deployment/grafana -- ls -la /var/lib/grafana/plugins/

# Backup specific custom plugin
PLUGIN_NAME="custom-plugin-name"
kubectl exec -n <namespace> deployment/grafana -- tar czf /tmp/$PLUGIN_NAME-backup.tar.gz /var/lib/grafana/plugins/$PLUGIN_NAME

kubectl cp <namespace>/grafana-pod-name:/tmp/$PLUGIN_NAME-backup.tar.gz ./$PLUGIN_NAME-backup-$(date +%Y%m%d-%H%M%S).tar.gz

# Cleanup
kubectl exec -n <namespace> deployment/grafana -- rm /tmp/$PLUGIN_NAME-backup.tar.gz
```

---

### 5. PVC Snapshot Backup

Kubernetes VolumeSnapshot provides point-in-time copies of Grafana persistent volumes.

#### 5.1 Prerequisites

Verify VolumeSnapshot support:

```bash
# Check if VolumeSnapshot CRD exists
kubectl get crd volumesnapshots.snapshot.storage.k8s.io

# Check available VolumeSnapshotClasses
kubectl get volumesnapshotclass

# Verify CSI driver supports snapshots
kubectl get csidrivers
```

#### 5.2 Create VolumeSnapshot

Create a snapshot of Grafana PVC:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-backup-snapshot

# Manual VolumeSnapshot creation
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: grafana-data-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: <namespace>
spec:
  volumeSnapshotClassName: <your-snapshot-class>
  source:
    persistentVolumeClaimName: grafana-data
EOF

# Wait for snapshot to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/grafana-data-snapshot-YYYYMMDD-HHMMSS \
  -n <namespace> --timeout=300s
```

#### 5.3 Verify VolumeSnapshot

Check snapshot status:

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-list-snapshots

# Manual verification
kubectl get volumesnapshot -n <namespace>

# Get snapshot details
kubectl describe volumesnapshot grafana-data-snapshot-YYYYMMDD-HHMMSS -n <namespace>

# Check snapshot size and creation time
kubectl get volumesnapshot grafana-data-snapshot-YYYYMMDD-HHMMSS -n <namespace> -o jsonpath='{.status.restoreSize}, {.status.creationTime}'
```

#### 5.4 List All Snapshots

```bash
# List all Grafana snapshots
kubectl get volumesnapshots -n <namespace> -l app.kubernetes.io/name=grafana

# Get snapshot details in table format
kubectl get volumesnapshots -n <namespace> -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize,\
CREATED:.status.creationTime
```

#### 5.5 Delete Old Snapshots

Cleanup old snapshots to save storage:

```bash
# Delete specific snapshot
kubectl delete volumesnapshot grafana-data-snapshot-YYYYMMDD-HHMMSS -n <namespace>

# Delete snapshots older than 30 days (requires scripting)
THIRTY_DAYS_AGO=$(date -d '30 days ago' +%Y%m%d)

kubectl get volumesnapshots -n <namespace> -o json | \
jq -r ".items[] | select(.metadata.name | startswith(\"grafana-data-snapshot-\")) | select(.metadata.name | split(\"-\")[3] < \"$THIRTY_DAYS_AGO\") | .metadata.name" | \
xargs -I {} kubectl delete volumesnapshot {} -n <namespace>
```

---

## Recovery Procedures

### Configuration Recovery

Restore Grafana ConfigMaps and Secrets from backups.

#### Step 1: Restore ConfigMaps

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-restore-config BACKUP_FILE=grafana-config-backup-YYYYMMDD-HHMMSS.yaml

# Manual restore
kubectl apply -f grafana-config-backup-YYYYMMDD-HHMMSS.yaml

# Verify ConfigMap restoration
kubectl get configmap grafana-config -n <namespace> -o yaml
```

#### Step 2: Restore Secrets

```bash
# Decrypt secrets backup if encrypted
gpg --decrypt grafana-secret-backup-YYYYMMDD-HHMMSS.yaml.gpg > grafana-secret-backup-YYYYMMDD-HHMMSS.yaml

# Using Makefile
make -f make/ops/grafana.mk grafana-restore-secrets BACKUP_FILE=grafana-secret-backup-YYYYMMDD-HHMMSS.yaml

# Manual restore
kubectl apply -f grafana-secret-backup-YYYYMMDD-HHMMSS.yaml

# Verify Secrets restoration (values will be base64 encoded)
kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data}'
```

#### Step 3: Restart Grafana

Restart Grafana to apply restored configuration:

```bash
# Restart Grafana deployment
kubectl rollout restart deployment/grafana -n <namespace>

# Wait for rollout completion
kubectl rollout status deployment/grafana -n <namespace> --timeout=300s

# Verify Grafana is running
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana
```

---

### Database Recovery

Restore Grafana SQLite database from backup.

#### Step 1: Stop Grafana

```bash
# Scale down Grafana deployment
kubectl scale deployment grafana -n <namespace> --replicas=0

# Wait for pod termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=60s
```

#### Step 2: Restore Database File

```bash
# Create temporary pod to access PVC
kubectl run grafana-restore-pod -n <namespace> \
  --image=alpine:3.19 \
  --restart=Never \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "restore",
      "image": "alpine:3.19",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "name": "grafana-data",
        "mountPath": "/var/lib/grafana"
      }]
    }],
    "volumes": [{
      "name": "grafana-data",
      "persistentVolumeClaim": {
        "claimName": "grafana-data"
      }
    }]
  }
}'

# Wait for restore pod
kubectl wait --for=condition=ready pod/grafana-restore-pod -n <namespace> --timeout=60s

# Backup current database (safety)
kubectl exec -n <namespace> grafana-restore-pod -- mv /var/lib/grafana/grafana.db /var/lib/grafana/grafana.db.old

# Copy restored database to pod
kubectl cp ./grafana-db-backup-YYYYMMDD-HHMMSS.db <namespace>/grafana-restore-pod:/var/lib/grafana/grafana.db

# Set correct permissions
kubectl exec -n <namespace> grafana-restore-pod -- chown 472:472 /var/lib/grafana/grafana.db
kubectl exec -n <namespace> grafana-restore-pod -- chmod 640 /var/lib/grafana/grafana.db

# Cleanup restore pod
kubectl delete pod grafana-restore-pod -n <namespace>
```

#### Step 3: Start Grafana

```bash
# Scale up Grafana deployment
kubectl scale deployment grafana -n <namespace> --replicas=1

# Wait for Grafana to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=300s

# Verify Grafana logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana --tail=50
```

#### Step 4: Verify Database Recovery

```bash
# Check Grafana UI is accessible
kubectl port-forward -n <namespace> svc/grafana 3000:80

# Access http://localhost:3000 and verify:
# - Dashboards are visible
# - Datasources are configured
# - Users can log in
# - Annotations are present

# Verify database via API
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)

curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '.[] | {title, uid}'
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '.[] | {name, type}'
```

---

### Dashboards and Datasources Recovery

Restore dashboards and datasources from JSON exports.

#### Step 1: Prepare Grafana API Access

```bash
# Get admin password
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)

# Setup port-forward
kubectl port-forward -n <namespace> svc/grafana 3000:80 &
GRAFANA_URL="http://localhost:3000"
```

#### Step 2: Restore Datasources

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-restore-datasources BACKUP_DIR=grafana-datasources-backup-YYYYMMDD-HHMMSS

# Manual restore - import all datasources
BACKUP_DIR="grafana-datasources-backup-YYYYMMDD-HHMMSS"

for file in "$BACKUP_DIR"/datasource-*.json; do
  echo "Restoring datasource: $file"
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d @"$file" \
    "$GRAFANA_URL/api/datasources"
done

# Verify datasources
curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/datasources" | jq '.[] | {id, name, type}'
```

#### Step 3: Restore Folders (if needed)

```bash
# Restore folders before dashboards
curl -s -u admin:$GRAFANA_PASSWORD \
  grafana-folders-backup-YYYYMMDD-HHMMSS.json | \
jq -c '.[]' | while read folder; do
  FOLDER_TITLE=$(echo $folder | jq -r '.title')
  FOLDER_UID=$(echo $folder | jq -r '.uid')

  echo "Restoring folder: $FOLDER_TITLE"
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d "{\"uid\":\"$FOLDER_UID\",\"title\":\"$FOLDER_TITLE\"}" \
    "$GRAFANA_URL/api/folders"
done
```

#### Step 4: Restore Dashboards

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-restore-dashboards BACKUP_DIR=grafana-dashboards-backup-YYYYMMDD-HHMMSS

# Manual restore - import all dashboards
BACKUP_DIR="grafana-dashboards-backup-YYYYMMDD-HHMMSS"

for file in "$BACKUP_DIR"/dashboard-*.json; do
  DASHBOARD_UID=$(jq -r '.uid' "$file")
  echo "Restoring dashboard: $DASHBOARD_UID"

  # Wrap dashboard JSON in required format
  jq -n --slurpfile dashboard "$file" \
    '{dashboard: $dashboard[0], overwrite: true}' | \
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d @- \
    "$GRAFANA_URL/api/dashboards/db"
done

# Verify dashboards
curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/search?type=dash-db" | jq '.[] | {title, uid, folderTitle}'
```

#### Step 5: Restore Single Dashboard

```bash
# Restore specific dashboard by UID
DASHBOARD_FILE="dashboard-your-dashboard-uid-YYYYMMDD-HHMMSS.json"

jq -n --slurpfile dashboard "$DASHBOARD_FILE" \
  '{dashboard: $dashboard[0], overwrite: true}' | \
curl -X POST -u admin:$GRAFANA_PASSWORD \
  -H "Content-Type: application/json" \
  -d @- \
  "$GRAFANA_URL/api/dashboards/db"

# Verify restoration
DASHBOARD_UID=$(jq -r '.uid' "$DASHBOARD_FILE")
curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.dashboard.title'
```

---

### Full Disaster Recovery

Complete Grafana instance recovery from all backup components.

#### Disaster Recovery Scenario 1: Complete Data Loss (PVC destroyed)

**Prerequisites:**
- Valid VolumeSnapshot available
- All configuration backups available
- Helm chart values available

**Recovery Steps:**

```bash
# Step 1: Restore PVC from VolumeSnapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data-restored
  namespace: <namespace>
spec:
  storageClassName: <your-storage-class>
  dataSource:
    name: grafana-data-snapshot-YYYYMMDD-HHMMSS
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/grafana-data-restored -n <namespace> --timeout=300s

# Step 2: Update Helm release to use restored PVC
helm upgrade grafana charts/grafana \
  --namespace <namespace> \
  --set persistence.existingClaim=grafana-data-restored \
  --reuse-values

# Step 3: Restore ConfigMaps and Secrets
kubectl apply -f grafana-config-backup-YYYYMMDD-HHMMSS.yaml
kubectl apply -f grafana-secret-backup-YYYYMMDD-HHMMSS.yaml

# Step 4: Restart Grafana
kubectl rollout restart deployment/grafana -n <namespace>
kubectl rollout status deployment/grafana -n <namespace> --timeout=300s

# Step 5: Verify recovery
kubectl port-forward -n <namespace> svc/grafana 3000:80
# Access http://localhost:3000 and verify all dashboards/datasources
```

#### Disaster Recovery Scenario 2: Database Corruption

**Recovery Steps:**

```bash
# Step 1: Stop Grafana
kubectl scale deployment grafana -n <namespace> --replicas=0

# Step 2: Restore database (see Database Recovery section)
# ... (follow Database Recovery steps)

# Step 3: Restore dashboards/datasources via API (if needed)
# ... (follow Dashboards and Datasources Recovery steps)

# Step 4: Start Grafana
kubectl scale deployment grafana -n <namespace> --replicas=1

# Step 5: Verify recovery
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=300s
```

#### Disaster Recovery Scenario 3: Accidental Dashboard Deletion

**Recovery Steps:**

```bash
# Option 1: Restore from latest dashboard export
DASHBOARD_UID="deleted-dashboard-uid"
BACKUP_DIR="grafana-dashboards-backup-YYYYMMDD-HHMMSS"

jq -n --slurpfile dashboard "$BACKUP_DIR/dashboard-$DASHBOARD_UID.json" \
  '{dashboard: $dashboard[0], overwrite: true}' | \
curl -X POST -u admin:$GRAFANA_PASSWORD \
  -H "Content-Type: application/json" \
  -d @- \
  "$GRAFANA_URL/api/dashboards/db"

# Option 2: Restore from database backup (if recent)
# ... (follow Database Recovery steps)

# Verify restoration
curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.dashboard.title'
```

---

## Backup Automation

### Scheduled Backup Strategy

Implement automated backups using Kubernetes CronJobs or external schedulers.

#### Daily Dashboard and Datasource Export (CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: grafana-backup-dashboards
  namespace: <namespace>
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: grafana
          containers:
          - name: backup
            image: curlimages/curl:8.5.0
            env:
            - name: GRAFANA_URL
              value: "http://grafana:80"
            - name: GRAFANA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-secret
                  key: admin-password
            command:
            - /bin/sh
            - -c
            - |
              BACKUP_DIR="/backups/grafana-$(date +%Y%m%d-%H%M%S)"
              mkdir -p "$BACKUP_DIR"

              # Export dashboards
              DASHBOARD_UIDS=$(curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[].uid')
              for uid in $DASHBOARD_UIDS; do
                curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/dashboards/uid/$uid" | jq '.dashboard' > "$BACKUP_DIR/dashboard-$uid.json"
              done

              # Export datasources
              curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/datasources" > "$BACKUP_DIR/datasources.json"

              echo "Backup completed: $BACKUP_DIR"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: grafana-backup-storage
```

#### Weekly VolumeSnapshot (CronJob with kubectl)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: grafana-backup-snapshot
  namespace: <namespace>
spec:
  schedule: "0 3 * * 0"  # Weekly on Sunday at 3 AM
  successfulJobsHistoryLimit: 4
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: grafana-backup-sa
          containers:
          - name: snapshot
            image: bitnami/kubectl:1.28
            command:
            - /bin/bash
            - -c
            - |
              SNAPSHOT_NAME="grafana-data-snapshot-$(date +%Y%m%d-%H%M%S)"

              cat <<EOF | kubectl apply -f -
              apiVersion: snapshot.storage.k8s.io/v1
              kind: VolumeSnapshot
              metadata:
                name: $SNAPSHOT_NAME
                namespace: <namespace>
              spec:
                volumeSnapshotClassName: <your-snapshot-class>
                source:
                  persistentVolumeClaimName: grafana-data
              EOF

              # Wait for snapshot readiness
              kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/$SNAPSHOT_NAME -n <namespace> --timeout=600s

              echo "Snapshot created: $SNAPSHOT_NAME"

              # Cleanup old snapshots (keep last 8 weekly snapshots)
              OLD_SNAPSHOTS=$(kubectl get volumesnapshots -n <namespace> --sort-by=.metadata.creationTimestamp -o name | grep grafana-data-snapshot | head -n -8)
              if [ -n "$OLD_SNAPSHOTS" ]; then
                echo "$OLD_SNAPSHOTS" | xargs kubectl delete -n <namespace>
              fi
          restartPolicy: OnFailure
```

**Required ServiceAccount and RBAC for VolumeSnapshot CronJob:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-backup-sa
  namespace: <namespace>
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: grafana-backup-role
  namespace: <namespace>
rules:
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshots"]
    verbs: ["create", "get", "list", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: grafana-backup-rolebinding
  namespace: <namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: grafana-backup-role
subjects:
  - kind: ServiceAccount
    name: grafana-backup-sa
    namespace: <namespace>
```

#### Monthly Database Backup (CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: grafana-backup-database
  namespace: <namespace>
spec:
  schedule: "0 4 1 * *"  # Monthly on 1st at 4 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine:3.19
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache sqlite
              BACKUP_FILE="/backups/grafana-db-$(date +%Y%m%d-%H%M%S).db"
              sqlite3 /var/lib/grafana/grafana.db ".backup $BACKUP_FILE"

              # Verify backup
              sqlite3 $BACKUP_FILE "PRAGMA integrity_check;" | grep -q "ok" && echo "Backup verified: $BACKUP_FILE" || exit 1
            volumeMounts:
            - name: grafana-data
              mountPath: /var/lib/grafana
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: grafana-data
            persistentVolumeClaim:
              claimName: grafana-data
          - name: backup-storage
            persistentVolumeClaim:
              claimName: grafana-backup-storage
```

---

## Best Practices

### 1. Backup Frequency

**Recommended backup schedule:**

| Backup Component | Frequency | Retention | Priority |
|------------------|-----------|-----------|----------|
| Dashboards/Datasources | Daily | 30 days | Critical |
| SQLite Database | Daily | 14 days | Critical |
| Configuration | On Change | Indefinite | High |
| Plugins/Provisioning | On Change | Indefinite | Medium |
| VolumeSnapshot | Weekly | 8 snapshots | High |

### 2. Backup Storage

**Storage best practices:**
- Store backups in different storage tier (S3, NFS, object storage)
- Encrypt sensitive backups (database, secrets)
- Implement 3-2-1 backup rule: 3 copies, 2 media types, 1 offsite
- Use versioned storage for backup retention
- Monitor backup storage capacity

### 3. Backup Validation

**Regularly test backups:**
- Monthly: Restore dashboard from backup to test environment
- Quarterly: Full disaster recovery test with database restore
- Annually: Complete disaster recovery drill with PVC snapshot

```bash
# Automated backup validation script
#!/bin/bash
BACKUP_FILE="grafana-db-backup-latest.db"

# Integrity check
sqlite3 $BACKUP_FILE "PRAGMA integrity_check;" | grep -q "ok" || exit 1

# Content validation
DASHBOARD_COUNT=$(sqlite3 $BACKUP_FILE "SELECT COUNT(*) FROM dashboard;")
DATASOURCE_COUNT=$(sqlite3 $BACKUP_FILE "SELECT COUNT(*) FROM data_source;")

echo "Backup validation passed:"
echo "  Dashboards: $DASHBOARD_COUNT"
echo "  Datasources: $DATASOURCE_COUNT"
```

### 4. Monitoring and Alerting

**Monitor backup jobs:**
- CronJob failures (Kubernetes events)
- Backup storage capacity
- Backup age (alert if backup older than 48 hours)
- VolumeSnapshot status

**Example Prometheus alert:**

```yaml
- alert: GrafanaBackupMissing
  expr: |
    time() - max(kube_job_status_completion_time{job_name=~"grafana-backup-.*"}) > 172800
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Grafana backup missing for 48 hours"
    description: "No successful Grafana backup in the last 48 hours."
```

### 5. Security Considerations

**Backup security best practices:**
- Encrypt database backups containing user data
- Encrypt secrets backups (admin password, secret key)
- Use RBAC to restrict backup access
- Audit backup access logs
- Rotate backup encryption keys periodically

```bash
# Encrypt sensitive backups
gpg --symmetric --cipher-algo AES256 grafana-db-backup-YYYYMMDD-HHMMSS.db
gpg --symmetric --cipher-algo AES256 grafana-secret-backup-YYYYMMDD-HHMMSS.yaml

# Decrypt when needed
gpg --decrypt grafana-db-backup-YYYYMMDD-HHMMSS.db.gpg > grafana-db-backup-YYYYMMDD-HHMMSS.db
```

### 6. Documentation

**Maintain backup documentation:**
- Backup procedures runbook
- Recovery time objectives (RTO) and recovery point objectives (RPO)
- Contact information for backup administrators
- Backup storage locations and credentials
- Disaster recovery plan

---

## Troubleshooting

### Issue 1: Database Backup Fails with "database is locked"

**Symptom:**
```
Error: database is locked
```

**Cause:** SQLite database is being written by Grafana during backup.

**Solution:**

```bash
# Option 1: Use online backup (.backup command)
kubectl exec -n <namespace> deployment/grafana -- sqlite3 /var/lib/grafana/grafana.db ".backup /var/lib/grafana/backup.db"

# Option 2: Stop Grafana before backup (offline backup)
kubectl scale deployment grafana -n <namespace> --replicas=0
# ... perform backup ...
kubectl scale deployment grafana -n <namespace> --replicas=1
```

### Issue 2: Dashboard Import Fails with "UID already exists"

**Symptom:**
```json
{"message":"A dashboard with the same uid already exists","status":"version-mismatch"}
```

**Cause:** Dashboard with same UID already exists in Grafana.

**Solution:**

```bash
# Option 1: Use overwrite flag
jq -n --slurpfile dashboard "$DASHBOARD_FILE" \
  '{dashboard: $dashboard[0], overwrite: true}' | \
curl -X POST -u admin:$GRAFANA_PASSWORD \
  -H "Content-Type: application/json" \
  -d @- \
  "$GRAFANA_URL/api/dashboards/db"

# Option 2: Delete existing dashboard first
DASHBOARD_UID=$(jq -r '.uid' "$DASHBOARD_FILE")
curl -X DELETE -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID"
# Then import
```

### Issue 3: VolumeSnapshot Stuck in "Pending" State

**Symptom:**
```
NAME                              READYTOUSE   SOURCEPVC      AGE
grafana-data-snapshot-20250101    false        grafana-data   10m
```

**Cause:** VolumeSnapshotClass not configured or CSI driver doesn't support snapshots.

**Solution:**

```bash
# Check VolumeSnapshot status
kubectl describe volumesnapshot grafana-data-snapshot-20250101 -n <namespace>

# Check VolumeSnapshotClass
kubectl get volumesnapshotclass

# Check CSI driver capabilities
kubectl get csidrivers -o yaml | grep -A 5 "volumeSnapshotDataSource"

# If CSI driver doesn't support snapshots, use alternative backup method:
# - Database file copy
# - PVC clone
# - Restic backup
```

### Issue 4: Restored Database Shows "Empty" Grafana

**Symptom:** After database restore, Grafana shows no dashboards or datasources.

**Cause:**
- Wrong database file restored
- Database corruption
- Grafana cache not cleared

**Solution:**

```bash
# Step 1: Verify database integrity
sqlite3 grafana.db "PRAGMA integrity_check;"

# Step 2: Check database contents
sqlite3 grafana.db <<EOF
SELECT COUNT(*) FROM dashboard;
SELECT COUNT(*) FROM data_source;
SELECT COUNT(*) FROM user;
EOF

# Step 3: If database is valid, clear Grafana cache
kubectl exec -n <namespace> deployment/grafana -- rm -rf /var/lib/grafana/cache/*

# Step 4: Restart Grafana
kubectl rollout restart deployment/grafana -n <namespace>
```

### Issue 5: Plugin Backup/Restore Fails

**Symptom:** Plugins not working after restore.

**Cause:** Plugin data corruption or version mismatch.

**Solution:**

```bash
# Step 1: Check plugin directory structure
kubectl exec -n <namespace> deployment/grafana -- ls -la /var/lib/grafana/plugins/

# Step 2: Verify plugin versions
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls

# Step 3: Reinstall plugins from plugin list
PLUGIN_LIST=$(cat grafana-plugins-list-YYYYMMDD-HHMMSS.txt)
for plugin in $PLUGIN_LIST; do
  PLUGIN_ID=$(echo $plugin | awk '{print $1}')
  kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins install $PLUGIN_ID
done

# Step 4: Restart Grafana
kubectl rollout restart deployment/grafana -n <namespace>
```

### Issue 6: API Export Times Out for Large Dashboards

**Symptom:**
```
curl: (28) Operation timed out after 30000 milliseconds
```

**Cause:** Large dashboard JSON or slow API response.

**Solution:**

```bash
# Increase curl timeout
curl --max-time 300 -s -u admin:$GRAFANA_PASSWORD \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.dashboard' > dashboard.json

# Export dashboards in batches
DASHBOARD_UIDS=$(curl -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[].uid')
BATCH_SIZE=10
BATCH=()

for uid in $DASHBOARD_UIDS; do
  BATCH+=($uid)
  if [ ${#BATCH[@]} -eq $BATCH_SIZE ]; then
    for batch_uid in "${BATCH[@]}"; do
      curl --max-time 300 -s -u admin:$GRAFANA_PASSWORD "$GRAFANA_URL/api/dashboards/uid/$batch_uid" | jq '.dashboard' > "dashboard-$batch_uid.json" &
    done
    wait
    BATCH=()
  fi
done
```

### Issue 7: Permission Denied When Copying Database

**Symptom:**
```
Error: permission denied while copying file
```

**Cause:** Grafana runs as non-root user (UID 472).

**Solution:**

```bash
# Ensure correct ownership when restoring database
kubectl exec -n <namespace> grafana-restore-pod -- chown 472:472 /var/lib/grafana/grafana.db
kubectl exec -n <namespace> grafana-restore-pod -- chmod 640 /var/lib/grafana/grafana.db

# Verify permissions
kubectl exec -n <namespace> grafana-restore-pod -- ls -l /var/lib/grafana/grafana.db
# Expected: -rw-r----- 1 472 472 ... grafana.db
```

---

## Additional Resources

- [Grafana Administration Documentation](https://grafana.com/docs/grafana/latest/administration/)
- [Grafana HTTP API Reference](https://grafana.com/docs/grafana/latest/developers/http_api/)
- [SQLite Backup Documentation](https://www.sqlite.org/backup.html)
- [Kubernetes VolumeSnapshot Documentation](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Grafana Backup Tool (grafana-backup-tool)](https://github.com/ysde/grafana-backup-tool)

---

**Document Version:** 1.0.0
**Last Updated:** 2025-12-01
**Grafana Chart Version:** 0.3.0
