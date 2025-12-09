# Alertmanager Backup and Recovery Guide

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Automation](#automation)
7. [Testing Backups](#testing-backups)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

Alertmanager handles alerts sent by Prometheus and routes them to receivers (email, Slack, PagerDuty, etc.). Backing up Alertmanager is essential for:

- **Configuration preservation** (routing rules, receivers, inhibition rules)
- **Silence management** (active silences for maintenance windows)
- **Notification templates** (custom alert formatting)
- **Disaster recovery** (minimal downtime)

**Key Characteristics:**
- **Semi-stateful**: Configuration is static, but silences are runtime state
- **Alert Router**: Routes alerts to notification receivers
- **Clustering**: High availability with Gossip protocol
- **Data Directory**: Stores silences, notifications, and state

**RTO/RPO Targets:**
- **RTO (Recovery Time Objective)**: < 30 minutes (config restore + redeploy)
- **RPO (Recovery Point Objective)**: 1 hour (for silences)

---

## Backup Strategy

### Components to Backup

Alertmanager backups consist of 4 main components:

| Component | Priority | Size | Backup Method | Recovery Time |
|-----------|----------|------|---------------|---------------|
| **Configuration** | Critical | < 10 KB | ConfigMap export, values.yaml | < 5 minutes |
| **Silences** | Important | < 1 MB | API export via amtool | < 10 minutes |
| **Notification Templates** | Important | < 100 KB | ConfigMap export | < 5 minutes |
| **Data Directory** | Secondary | < 100 MB | PVC snapshot | < 15 minutes |

### Backup Methods

1. **ConfigMap Export** (Recommended)
   - Export Alertmanager ConfigMap via `kubectl`
   - Backup Helm values.yaml
   - **Pros**: Simple, fast, version-controllable
   - **Cons**: Requires manual execution

2. **API-Based Silence Export** (Recommended)
   - Export silences via Alertmanager API using `amtool`
   - **Pros**: Captures runtime state
   - **Cons**: Requires amtool installation

3. **PVC Snapshot** (Optional)
   - Snapshot Alertmanager data volume
   - **Pros**: Complete state backup
   - **Cons**: Requires storage provider support

4. **Git-Based Configuration Management** (Best Practice)
   - Store alertmanager.yml in Git repository
   - Use GitOps (ArgoCD, FluxCD) for deployment
   - **Pros**: Automatic version control, auditability
   - **Cons**: Requires Git setup

---

## Backup Components

### 1. Configuration (Critical)

**What to Backup:**
- Alertmanager ConfigMap (`alertmanager-config`)
- Helm values.yaml
- Routing rules (route)
- Receivers (email, Slack, PagerDuty, etc.)
- Inhibition rules

**Size:** < 10 KB

**Backup Frequency:** After each configuration change

**Backup Command:**
```bash
# Export ConfigMap
kubectl get configmap -n default alertmanager-config -o yaml > alertmanager-config-backup.yaml

# Backup Helm values
helm get values my-alertmanager -n default > alertmanager-values-backup.yaml

# Include all values (including defaults)
helm get values my-alertmanager -n default --all > alertmanager-values-full-backup.yaml
```

**Why Critical:**
Without configuration, Alertmanager cannot route alerts. This includes receivers, routing rules, inhibition rules, and notification templates.

---

### 2. Silences (Important)

**What to Backup:**
- Active silences (maintenance windows, temporary mutes)
- Silence metadata (creator, comment, start/end time)

**Size:** < 1 MB (typically < 100 KB)

**Backup Frequency:** Hourly or before major changes

**Backup Command:**

Using `amtool`:
```bash
# Install amtool (if not available)
# wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/amtool-0.27.0.linux-amd64.tar.gz
# tar xzf amtool-0.27.0.linux-amd64.tar.gz

# Port-forward to Alertmanager
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

# Export silences
amtool --alertmanager.url=http://localhost:9093 silence query -o json > silences-backup.json

# Kill port-forward
kill %1
```

Using API directly:
```bash
# Get Alertmanager pod
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')

# Export silences via API
kubectl exec -n default $POD -- wget -qO- http://localhost:9093/api/v2/silences > silences-backup.json
```

**Why Important:**
Silences prevent alert notifications during maintenance windows. Losing silences may cause alert storms during planned maintenance.

---

### 3. Notification Templates (Important)

**What to Backup:**
- Custom notification templates (*.tmpl files)
- Template ConfigMap

**Size:** < 100 KB

**Backup Frequency:** After each template change

**Backup Command:**
```bash
# If templates are in ConfigMap
kubectl get configmap -n default alertmanager-templates -o yaml > alertmanager-templates-backup.yaml

# If templates are mounted from PVC
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- tar czf /tmp/templates.tar.gz /etc/alertmanager/templates/
kubectl cp default/$POD:/tmp/templates.tar.gz ./templates-backup.tar.gz
```

**Why Important:**
Custom templates define how alerts are formatted for different receivers. Without templates, alerts will use default formatting.

---

### 4. Data Directory (Secondary)

**What to Backup:**
- Silences database (`silences`)
- Notification log (`nflog`)
- Alertmanager state

**Size:** < 100 MB (typically < 10 MB)

**Backup Frequency:** Daily or before major changes

**Backup Command:**

Via PVC Snapshot (if supported):
```bash
# Create VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: alertmanager-snapshot-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: my-alertmanager-data
EOF
```

Via filesystem copy:
```bash
# Copy data directory
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- tar czf /tmp/data.tar.gz /alertmanager/
kubectl cp default/$POD:/tmp/data.tar.gz ./alertmanager-data-backup.tar.gz
```

**Why Secondary:**
Data directory contains runtime state that can be reconstructed from configuration and API exports. However, backup provides fastest recovery path.

---

## Backup Procedures

### Method 1: Configuration-Only Backup (Recommended for Dev/Test)

**Backup Configuration:**

```bash
#!/bin/bash
# Script: alertmanager-backup-config.sh
# Description: Backup Alertmanager configuration

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-alertmanager}"
BACKUP_DIR="${BACKUP_DIR:-./backups/alertmanager}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== Alertmanager Configuration Backup ==="
mkdir -p "$BACKUP_DIR/config-$TIMESTAMP"

# 1. Backup ConfigMap
echo "Backing up ConfigMap..."
kubectl get configmap -n "$NAMESPACE" "$RELEASE_NAME-config" -o yaml \
  > "$BACKUP_DIR/config-$TIMESTAMP/configmap.yaml"

# 2. Backup Helm values
echo "Backing up Helm values..."
helm get values "$RELEASE_NAME" -n "$NAMESPACE" \
  > "$BACKUP_DIR/config-$TIMESTAMP/values.yaml"

# 3. Backup Helm manifest
echo "Backing up Helm manifest..."
helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" \
  > "$BACKUP_DIR/config-$TIMESTAMP/manifest.yaml"

echo "Configuration backup saved to: $BACKUP_DIR/config-$TIMESTAMP/"
ls -lh "$BACKUP_DIR/config-$TIMESTAMP/"
```

**Expected Output:**
```
=== Alertmanager Configuration Backup ===
Backing up ConfigMap...
Backing up Helm values...
Backing up Helm manifest...
Configuration backup saved to: ./backups/alertmanager/config-20250609-143022/
total 16K
-rw-r--r-- 1 user user 5.2K Jun  9 14:30 configmap.yaml
-rw-r--r-- 1 user user 1.8K Jun  9 14:30 values.yaml
-rw-r--r-- 1 user user 8.1K Jun  9 14:30 manifest.yaml
```

---

### Method 2: Silences Backup (Runtime State)

**Backup Silences:**

```bash
#!/bin/bash
# Script: alertmanager-backup-silences.sh
# Description: Backup Alertmanager silences

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-alertmanager}"
BACKUP_DIR="${BACKUP_DIR:-./backups/alertmanager}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== Alertmanager Silences Backup ==="
mkdir -p "$BACKUP_DIR/silences-$TIMESTAMP"

# Get Alertmanager pod
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')

# Export silences via API
echo "Exporting silences from pod: $POD"
kubectl exec -n "$NAMESPACE" "$POD" -- wget -qO- http://localhost:9093/api/v2/silences \
  > "$BACKUP_DIR/silences-$TIMESTAMP/silences.json"

# Count silences
SILENCE_COUNT=$(cat "$BACKUP_DIR/silences-$TIMESTAMP/silences.json" | jq '. | length')
echo "Backed up $SILENCE_COUNT silences"

echo "Silences backup saved to: $BACKUP_DIR/silences-$TIMESTAMP/"
ls -lh "$BACKUP_DIR/silences-$TIMESTAMP/"
```

**Expected Output:**
```
=== Alertmanager Silences Backup ===
Exporting silences from pod: alertmanager-0
Backed up 5 silences
Silences backup saved to: ./backups/alertmanager/silences-20250609-143500/
total 4K
-rw-r--r-- 1 user user 2.3K Jun  9 14:35 silences.json
```

---

### Method 3: Full Backup (All Components)

**Complete Backup Script:**

```bash
#!/bin/bash
# Script: alertmanager-full-backup.sh
# Description: Full Alertmanager backup (config + silences + data)

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-alertmanager}"
BACKUP_DIR="${BACKUP_DIR:-./backups/alertmanager}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/full-$TIMESTAMP"

echo "=== Full Alertmanager Backup ==="
mkdir -p "$BACKUP_PATH"

# 1. Backup ConfigMap
echo "1/4 Backing up ConfigMap..."
kubectl get configmap -n "$NAMESPACE" "$RELEASE_NAME-config" -o yaml \
  > "$BACKUP_PATH/configmap.yaml"

# 2. Backup Helm values
echo "2/4 Backing up Helm values..."
helm get values "$RELEASE_NAME" -n "$NAMESPACE" \
  > "$BACKUP_PATH/values.yaml"

# 3. Backup silences
echo "3/4 Backing up silences..."
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n "$NAMESPACE" "$POD" -- wget -qO- http://localhost:9093/api/v2/silences \
  > "$BACKUP_PATH/silences.json" 2>/dev/null || echo "  No silences found"

# 4. Backup data directory (optional)
echo "4/4 Backing up data directory..."
kubectl exec -n "$NAMESPACE" "$POD" -- tar czf /tmp/data.tar.gz /alertmanager/ 2>/dev/null && \
  kubectl cp "$NAMESPACE/$POD:/tmp/data.tar.gz" "$BACKUP_PATH/data.tar.gz" 2>/dev/null || \
  echo "  Data directory backup skipped (no persistence enabled)"

# Create backup manifest
cat > "$BACKUP_PATH/BACKUP_MANIFEST.txt" <<EOF
=== Alertmanager Full Backup ===
Timestamp: $TIMESTAMP
Namespace: $NAMESPACE
Release Name: $RELEASE_NAME
Backup Path: $BACKUP_PATH

Components:
- ConfigMap (configmap.yaml)
- Helm Values (values.yaml)
- Silences (silences.json)
- Data Directory (data.tar.gz) - Optional

Files:
$(ls -lh "$BACKUP_PATH" | tail -n +2)

RTO: < 30 minutes
RPO: 1 hour
EOF

echo ""
echo "=== Full Backup Complete ==="
cat "$BACKUP_PATH/BACKUP_MANIFEST.txt"
```

**Expected Output:**
```
=== Full Alertmanager Backup ===
1/4 Backing up ConfigMap...
2/4 Backing up Helm values...
3/4 Backing up silences...
4/4 Backing up data directory...

=== Full Backup Complete ===
=== Alertmanager Full Backup ===
Timestamp: 20250609-144500
Namespace: default
Release Name: my-alertmanager
Backup Path: ./backups/alertmanager/full-20250609-144500

Components:
- ConfigMap (configmap.yaml)
- Helm Values (values.yaml)
- Silences (silences.json)
- Data Directory (data.tar.gz) - Optional

Files:
-rw-r--r-- 1 user user 5.2K Jun  9 14:45 configmap.yaml
-rw-r--r-- 1 user user 1.8K Jun  9 14:45 values.yaml
-rw-r--r-- 1 user user 2.3K Jun  9 14:45 silences.json
-rw-r--r-- 1 user user  12K Jun  9 14:45 data.tar.gz
-rw-r--r-- 1 user user  510 Jun  9 14:45 BACKUP_MANIFEST.txt

RTO: < 30 minutes
RPO: 1 hour
```

---

## Recovery Procedures

### Scenario 1: Configuration-Only Recovery

**Use Case:** Alertmanager ConfigMap was accidentally deleted or misconfigured

**Recovery Steps:**

1. **Restore ConfigMap:**
```bash
kubectl apply -f backups/alertmanager/config-20250609-143022/configmap.yaml
```

2. **Verify ConfigMap:**
```bash
kubectl get configmap -n default my-alertmanager-config -o yaml
```

3. **Restart Alertmanager pods:**
```bash
kubectl rollout restart statefulset/my-alertmanager -n default
kubectl rollout status statefulset/my-alertmanager -n default
```

4. **Verify Alertmanager is working:**
```bash
# Check pod status
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager

# Check Alertmanager status
kubectl port-forward -n default svc/my-alertmanager 9093:9093
curl http://localhost:9093/-/healthy
```

**Expected RTO:** < 5 minutes

---

### Scenario 2: Silences Recovery

**Use Case:** Silences were lost after pod restart or upgrade

**Recovery Steps:**

1. **Restore silences via API:**
```bash
# Port-forward to Alertmanager
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

# Import silences (one by one)
cat backups/alertmanager/silences-20250609-143500/silences.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done

# Kill port-forward
kill %1
```

2. **Verify silences:**
```bash
# List silences
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &
curl http://localhost:9093/api/v2/silences | jq '.'
kill %1
```

**Expected RTO:** < 10 minutes

**Note:** Silences have expiration times. Only active silences will be restored.

---

### Scenario 3: Full Cluster Recovery (Alertmanager Reinstall)

**Use Case:** Complete Alertmanager reinstallation after cluster migration

**Recovery Steps:**

1. **Restore from Helm values backup:**
```bash
# Install Alertmanager using backed-up values
helm install my-alertmanager scripton-charts/alertmanager \
  -f backups/alertmanager/full-20250609-144500/values.yaml \
  -n default
```

2. **Verify StatefulSet is running:**
```bash
kubectl get statefulset -n default my-alertmanager
kubectl get pods -n default -l app.kubernetes.io/name=alertmanager
```

3. **Restore silences:**
```bash
# Wait for Alertmanager to be ready
kubectl wait --for=condition=ready pod -n default -l app.kubernetes.io/name=alertmanager --timeout=300s

# Restore silences
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &
cat backups/alertmanager/full-20250609-144500/silences.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done
kill %1
```

4. **Verify Alertmanager:**
```bash
# Check health
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &
curl http://localhost:9093/-/healthy
curl http://localhost:9093/api/v2/status | jq '.cluster.status'
kill %1
```

**Expected RTO:** < 30 minutes

---

### Scenario 4: Disaster Recovery (Complete Restoration)

**Use Case:** Complete cluster loss, restore Alertmanager from backups

**Recovery Steps:**

1. **Verify cluster is ready:**
```bash
kubectl get nodes
kubectl get ns default
```

2. **Install Alertmanager from backup:**
```bash
# Use full backup
helm install my-alertmanager scripton-charts/alertmanager \
  -f backups/alertmanager/full-20250609-144500/values.yaml \
  -n default --create-namespace
```

3. **Verify installation:**
```bash
kubectl get all -n default -l app.kubernetes.io/name=alertmanager
```

4. **Restore silences:**
```bash
# Wait for Alertmanager to be ready
kubectl wait --for=condition=ready pod -n default -l app.kubernetes.io/name=alertmanager --timeout=300s

# Port-forward
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

# Import silences
cat backups/alertmanager/full-20250609-144500/silences.json | jq -c '.[]' | while read silence; do
  curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d "$silence"
done

kill %1
```

5. **Verify alert routing:**
```bash
# Send test alert
kubectl run -it --rm test-alert --image=curlimages/curl --restart=Never -- \
  curl -X POST http://my-alertmanager.default.svc.cluster.local:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
```

**Expected RTO:** < 30 minutes

**RPO:** 1 hour (based on silence backup frequency)

---

## Automation

### Automated Backup (CronJob)

**CronJob Manifest:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: alertmanager-backup
  namespace: default
spec:
  schedule: "0 */1 * * *"  # Every hour
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: alertmanager-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              #!/bin/sh
              set -e

              NAMESPACE="default"
              RELEASE_NAME="my-alertmanager"
              BACKUP_DIR="/backups/alertmanager"
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)

              echo "=== Alertmanager Backup Started ==="
              mkdir -p "$BACKUP_DIR/backup-$TIMESTAMP"

              # Backup ConfigMap
              kubectl get configmap -n "$NAMESPACE" "$RELEASE_NAME-config" -o yaml \
                > "$BACKUP_DIR/backup-$TIMESTAMP/configmap.yaml"

              # Backup silences
              POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')
              kubectl exec -n "$NAMESPACE" "$POD" -- wget -qO- http://localhost:9093/api/v2/silences \
                > "$BACKUP_DIR/backup-$TIMESTAMP/silences.json" 2>/dev/null || echo "No silences"

              echo "Backup saved to: $BACKUP_DIR/backup-$TIMESTAMP/"
              ls -lh "$BACKUP_DIR/backup-$TIMESTAMP/"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: alertmanager-backup-pvc
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: alertmanager-backup
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: alertmanager-backup
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alertmanager-backup
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: alertmanager-backup
subjects:
- kind: ServiceAccount
  name: alertmanager-backup
  namespace: default
```

**Deploy CronJob:**
```bash
kubectl apply -f alertmanager-backup-cronjob.yaml
```

**Verify CronJob:**
```bash
kubectl get cronjob -n default alertmanager-backup
kubectl get jobs -n default -l job-name=alertmanager-backup
```

---

### Backup Retention Script

**Cleanup Old Backups:**

```bash
#!/bin/bash
# Script: alertmanager-backup-cleanup.sh
# Description: Clean up old Alertmanager backups

BACKUP_DIR="${BACKUP_DIR:-./backups/alertmanager}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

echo "=== Alertmanager Backup Cleanup ==="
echo "Backup directory: $BACKUP_DIR"
echo "Retention period: $RETENTION_DAYS days"

# Find and delete backups older than retention period
find "$BACKUP_DIR" -type d -name "config-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
find "$BACKUP_DIR" -type d -name "silences-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
find "$BACKUP_DIR" -type d -name "full-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Cleanup complete"
echo "Remaining backups:"
ls -lh "$BACKUP_DIR"
```

**Add to Cron:**
```bash
# Run daily at 3 AM
0 3 * * * /path/to/alertmanager-backup-cleanup.sh
```

---

## Testing Backups

### Backup Validation

**Automated Backup Test Script:**

```bash
#!/bin/bash
# Script: alertmanager-test-backup.sh
# Description: Test Alertmanager backup restoration

set -e

BACKUP_PATH="${1:-./backups/alertmanager/full-20250609-144500}"
TEST_NAMESPACE="alertmanager-test"

echo "=== Alertmanager Backup Test ==="
echo "Testing backup: $BACKUP_PATH"

# 1. Create test namespace
echo "1/5 Creating test namespace..."
kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Restore ConfigMap
echo "2/5 Restoring ConfigMap..."
kubectl apply -f "$BACKUP_PATH/configmap.yaml" -n "$TEST_NAMESPACE"

# 3. Install Alertmanager with backed-up values
echo "3/5 Installing Alertmanager..."
helm install alertmanager-test scripton-charts/alertmanager \
  -f "$BACKUP_PATH/values.yaml" \
  -n "$TEST_NAMESPACE" --wait --timeout=5m

# 4. Verify deployment
echo "4/5 Verifying deployment..."
kubectl get statefulset -n "$TEST_NAMESPACE"
kubectl get pods -n "$TEST_NAMESPACE" -l app.kubernetes.io/name=alertmanager

# 5. Cleanup
echo "5/5 Cleaning up..."
read -p "Delete test namespace? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  helm uninstall alertmanager-test -n "$TEST_NAMESPACE"
  kubectl delete namespace "$TEST_NAMESPACE"
  echo "Test namespace deleted"
fi

echo ""
echo "=== Backup Test Complete ==="
echo "Backup is valid and can be used for recovery"
```

**Run Test:**
```bash
chmod +x alertmanager-test-backup.sh
./alertmanager-test-backup.sh ./backups/alertmanager/full-20250609-144500
```

---

## Troubleshooting

### Issue 1: Silences Not Restored

**Symptom:** Silences are not visible after restoration

**Cause:** Silences may have expired or API import failed

**Solution:**

1. Check silence expiration:
```bash
cat backups/alertmanager/silences-20250609-143500/silences.json | jq '.[] | {id, endsAt}'
```

2. Manually re-create expired silences:
```bash
# Create new silence
kubectl port-forward -n default svc/my-alertmanager 9093:9093 &

curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "alertname",
        "value": "HighMemoryUsage",
        "isRegex": false
      }
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "admin",
    "comment": "Maintenance window"
  }'

kill %1
```

---

### Issue 2: ConfigMap Restore Fails

**Symptom:**
```
Error from server (AlreadyExists): configmaps "my-alertmanager-config" already exists
```

**Cause:** ConfigMap already exists in namespace

**Solution:**

1. Delete existing ConfigMap:
```bash
kubectl delete configmap -n default my-alertmanager-config
```

2. Restore from backup:
```bash
kubectl apply -f backups/alertmanager/config-20250609-143022/configmap.yaml
```

3. Restart Alertmanager:
```bash
kubectl rollout restart statefulset/my-alertmanager -n default
```

---

### Issue 3: Backup Script Permissions Denied

**Symptom:**
```
Error: unable to get configmap: configmaps "my-alertmanager-config" is forbidden
```

**Cause:** Service account lacks permissions

**Solution:**

Ensure RBAC is configured (see Automation section for CronJob RBAC).

---

### Issue 4: Data Directory Backup Fails

**Symptom:**
```
tar: /alertmanager/: Cannot stat: No such file or directory
```

**Cause:** Persistence is not enabled or path is incorrect

**Solution:**

1. Check if persistence is enabled:
```bash
helm get values my-alertmanager -n default | grep -A5 persistence
```

2. If persistence is disabled, skip data directory backup:
```bash
# Data directory backup is optional when persistence is disabled
# Silences will be lost on pod restart, but can be restored from API backup
```

---

## Best Practices

### 1. Configuration Management

**DO:**
- ✅ Store alertmanager.yml in Git
- ✅ Use GitOps for deployment (ArgoCD, FluxCD)
- ✅ Backup ConfigMap after each change
- ✅ Test routing rules in dev/staging first
- ✅ Document receiver configurations

**DON'T:**
- ❌ Manually edit ConfigMap in production
- ❌ Store credentials unencrypted
- ❌ Skip backup before major changes
- ❌ Deploy untested configurations to production

---

### 2. Silence Management

**DO:**
- ✅ Backup silences hourly (automated CronJob)
- ✅ Document silence reasons in comments
- ✅ Set appropriate expiration times
- ✅ Review active silences regularly
- ✅ Use silence matchers carefully

**DON'T:**
- ❌ Create permanent silences (use inhibition rules instead)
- ❌ Silence critical alerts without reason
- ❌ Forget to expire silences after maintenance
- ❌ Use overly broad matchers

---

### 3. Backup Strategy

**DO:**
- ✅ Automate configuration backups (hourly CronJob)
- ✅ Test backups regularly (monthly)
- ✅ Store backups in multiple locations (S3, Git, PVC)
- ✅ Implement backup retention policy (30 days)
- ✅ Monitor backup job success

**DON'T:**
- ❌ Skip silence backups (important for maintenance windows)
- ❌ Store backups only locally
- ❌ Skip testing backup restoration
- ❌ Keep backups forever (implement retention)

---

### 4. Recovery Planning

**DO:**
- ✅ Document recovery procedures
- ✅ Practice disaster recovery regularly
- ✅ Measure actual RTO/RPO during tests
- ✅ Automate recovery where possible
- ✅ Maintain runbooks for common scenarios

**DON'T:**
- ❌ Assume backups work without testing
- ❌ Wait for disaster to test recovery
- ❌ Ignore failed backup jobs
- ❌ Over-rely on data directory backups

---

## Summary

Alertmanager backup focuses on configuration and runtime state:

**Critical Components:**
1. **Configuration** (ConfigMap, values.yaml) - Essential for routing
2. **Silences** (runtime state) - Important for maintenance windows
3. **Notification Templates** (optional) - Custom alert formatting

**Recommended Backup Strategy:**
- **Configuration**: Hourly automated backups via CronJob
- **Silences**: Hourly API exports (to capture maintenance windows)
- **Git-based**: Store alertmanager.yml in Git (best practice)

**RTO/RPO:**
- **RTO**: < 30 minutes (config restore + redeploy)
- **RPO**: 1 hour (for silences, based on backup frequency)

**Key Takeaway:** Focus on configuration and silence backup. Alertmanager can be quickly redeployed from backed-up Helm values, and silences can be restored via API.

---

**Related Documentation:**
- [Alertmanager Upgrade Guide](alertmanager-upgrade-guide.md)
- [Alertmanager Chart README](../charts/alertmanager/README.md)
- [Prometheus Backup Guide](prometheus-backup-guide.md) (for alert rules)
- [Disaster Recovery Guide](disaster-recovery-guide.md)

**Last Updated:** 2025-12-09
