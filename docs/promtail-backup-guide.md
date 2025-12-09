# Promtail Backup and Recovery Guide

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

Promtail is a **stateless log shipping agent** that tails logs from Kubernetes pods and sends them to Loki. Unlike databases or message brokers, Promtail does not store data persistently. However, backing up Promtail configuration and state is essential for:

- **Quick recovery** after failures or cluster migrations
- **Configuration version control** and auditing
- **Log continuity** by preserving positions file
- **Disaster recovery** with minimal log loss

**Key Characteristics:**
- **Stateless**: No persistent data storage
- **Log Shipper**: Reads pod logs and sends to Loki
- **Positions File**: Tracks which logs have been read (in-memory or hostPath)
- **Configuration-driven**: All behavior defined in promtail.yaml

**RTO/RPO Targets:**
- **RTO (Recovery Time Objective)**: < 30 minutes (configuration restore + DaemonSet redeploy)
- **RPO (Recovery Point Objective)**: 0 (no data loss - logs are not stored in Promtail)

**Note:** Since Promtail is stateless, the "backup" primarily consists of configuration and Kubernetes manifests. The positions file is secondary because Promtail can re-scan logs from the beginning (though this may cause duplicate log ingestion).

---

## Backup Strategy

### Components to Backup

Promtail backups consist of 3 main components:

| Component | Priority | Size | Backup Method | Recovery Time |
|-----------|----------|------|---------------|---------------|
| **Configuration** | Critical | < 10 KB | ConfigMap export, values.yaml | < 5 minutes |
| **Positions File** | Important | < 1 MB | kubectl cp (if hostPath) | < 10 minutes |
| **Kubernetes Manifests** | Critical | < 50 KB | Helm values, kubectl export | < 15 minutes |

### Backup Methods

1. **ConfigMap Export** (Recommended)
   - Export Promtail ConfigMap via `kubectl get configmap`
   - Backup Helm values.yaml
   - **Pros**: Simple, fast, version-controllable
   - **Cons**: Requires manual execution

2. **Git-Based Configuration Management** (Best Practice)
   - Store values.yaml in Git repository
   - Use GitOps (ArgoCD, FluxCD) for deployment
   - **Pros**: Automatic version control, auditability
   - **Cons**: Requires Git setup

3. **Helm Values Backup**
   - Export current Helm release values
   - Store in backup location
   - **Pros**: Captures all configurations
   - **Cons**: May include sensitive data

4. **Positions File Snapshot** (Optional)
   - Copy positions file from hostPath
   - Useful for preventing duplicate log ingestion
   - **Pros**: Ensures log continuity
   - **Cons**: Requires node access

---

## Backup Components

### 1. Configuration (Critical)

**What to Backup:**
- Promtail ConfigMap (`promtail-config`)
- Helm values.yaml
- Pipeline stages configuration
- Loki client configuration

**Size:** < 10 KB

**Backup Frequency:** After each configuration change

**Backup Command:**
```bash
# Export ConfigMap
kubectl get configmap -n default promtail-config -o yaml > promtail-config-backup.yaml

# Backup Helm values
helm get values my-promtail -n default > promtail-values-backup.yaml

# Include all values (including defaults)
helm get values my-promtail -n default --all > promtail-values-full-backup.yaml
```

**Why Critical:**
Without configuration, Promtail cannot function. This includes Loki endpoint, pipeline stages, labels, and scrape configs.

---

### 2. Positions File (Important)

**What to Backup:**
- `/run/promtail/positions.yaml` (default location)
- Tracks which log files have been read and at what offset

**Size:** < 1 MB (typically < 100 KB)

**Backup Frequency:** Daily or before major changes

**Backup Command:**
```bash
# Get a Promtail pod
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')

# Copy positions file
kubectl exec -n default $POD -- cat /run/promtail/positions.yaml > positions-backup.yaml

# Alternative: If positions file is on hostPath
# Find the node
NODE=$(kubectl get pod -n default $POD -o jsonpath='{.spec.nodeName}')

# SSH to node and copy
# ssh $NODE "sudo cat /var/lib/promtail/positions.yaml" > positions-backup.yaml
```

**Why Important:**
The positions file prevents re-ingesting logs that have already been sent to Loki. Without it, Promtail will re-read all logs from the beginning, causing duplicates.

**Note:** If positions file is lost, Promtail will automatically create a new one and start reading from the current log position (tail mode) or from the beginning (depending on configuration).

---

### 3. Kubernetes Manifests (Critical)

**What to Backup:**
- DaemonSet manifest
- ServiceAccount, ClusterRole, ClusterRoleBinding
- Service manifest (for metrics endpoint)
- ConfigMap

**Size:** < 50 KB

**Backup Frequency:** After each deployment change

**Backup Command:**
```bash
# Export all Promtail resources
kubectl get daemonset,serviceaccount,clusterrole,clusterrolebinding,service,configmap \
  -n default -l app.kubernetes.io/name=promtail -o yaml > promtail-manifests-backup.yaml

# Alternative: Export Helm release manifest
helm get manifest my-promtail -n default > promtail-helm-manifest-backup.yaml
```

**Why Critical:**
Kubernetes manifests define how Promtail is deployed. Without them, you cannot redeploy Promtail with the same configuration.

---

## Backup Procedures

### Method 1: ConfigMap Export (Recommended for Dev/Test)

**Backup Configuration:**

```bash
#!/bin/bash
# Script: promtail-backup-config.sh
# Description: Backup Promtail configuration

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-promtail}"
BACKUP_DIR="${BACKUP_DIR:-./backups/promtail}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== Promtail Configuration Backup ==="
mkdir -p "$BACKUP_DIR/config-$TIMESTAMP"

# 1. Backup ConfigMap
echo "Backing up ConfigMap..."
kubectl get configmap -n "$NAMESPACE" promtail-config -o yaml \
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
=== Promtail Configuration Backup ===
Backing up ConfigMap...
Backing up Helm values...
Backing up Helm manifest...
Configuration backup saved to: ./backups/promtail/config-20250609-143022/
total 24K
-rw-r--r-- 1 user user 8.5K Jun  9 14:30 configmap.yaml
-rw-r--r-- 1 user user 2.3K Jun  9 14:30 values.yaml
-rw-r--r-- 1 user user 12K  Jun  9 14:30 manifest.yaml
```

---

### Method 2: Git-Based Configuration Management (Best Practice for Production)

**Setup:**

1. **Create Git repository:**
```bash
mkdir promtail-config
cd promtail-config
git init
```

2. **Store Helm values.yaml:**
```bash
cp /path/to/values.yaml .
git add values.yaml
git commit -m "Initial Promtail configuration"
git push origin main
```

3. **Deploy from Git:**
```bash
# Deploy using values from Git
helm install my-promtail scripton-charts/promtail \
  -f https://raw.githubusercontent.com/myorg/promtail-config/main/values.yaml
```

4. **Update configuration:**
```bash
# Edit values.yaml
vim values.yaml

# Commit changes
git add values.yaml
git commit -m "Update Loki endpoint"
git push origin main

# Upgrade deployment
helm upgrade my-promtail scripton-charts/promtail \
  -f https://raw.githubusercontent.com/myorg/promtail-config/main/values.yaml
```

**Pros:**
- Automatic version control
- Audit trail of all changes
- Easy rollback to previous configurations
- GitOps integration (ArgoCD, FluxCD)

---

### Method 3: Positions File Backup (Optional)

**Backup Positions File:**

```bash
#!/bin/bash
# Script: promtail-backup-positions.sh
# Description: Backup Promtail positions file

NAMESPACE="${NAMESPACE:-default}"
BACKUP_DIR="${BACKUP_DIR:-./backups/promtail}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== Promtail Positions File Backup ==="
mkdir -p "$BACKUP_DIR/positions-$TIMESTAMP"

# Get all Promtail pods
PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail -o jsonpath='{.items[*].metadata.name}')

for POD in $PODS; do
  echo "Backing up positions from pod: $POD"

  # Copy positions file
  kubectl exec -n "$NAMESPACE" "$POD" -- cat /run/promtail/positions.yaml \
    > "$BACKUP_DIR/positions-$TIMESTAMP/positions-$POD.yaml" 2>/dev/null || echo "  No positions file found"
done

echo "Positions backup saved to: $BACKUP_DIR/positions-$TIMESTAMP/"
ls -lh "$BACKUP_DIR/positions-$TIMESTAMP/"
```

**Expected Output:**
```
=== Promtail Positions File Backup ===
Backing up positions from pod: promtail-abc123
Backing up positions from pod: promtail-def456
Backing up positions from pod: promtail-ghi789
Positions backup saved to: ./backups/promtail/positions-20250609-143500/
total 12K
-rw-r--r-- 1 user user 3.2K Jun  9 14:35 positions-promtail-abc123.yaml
-rw-r--r-- 1 user user 3.1K Jun  9 14:35 positions-promtail-def456.yaml
-rw-r--r-- 1 user user 3.3K Jun  9 14:35 positions-promtail-ghi789.yaml
```

**Note:** Positions files are node-specific. Each Promtail pod (one per node) maintains its own positions file.

---

### Method 4: Full Backup (All Components)

**Complete Backup Script:**

```bash
#!/bin/bash
# Script: promtail-full-backup.sh
# Description: Full Promtail backup (config + positions + manifests)

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-my-promtail}"
BACKUP_DIR="${BACKUP_DIR:-./backups/promtail}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/full-$TIMESTAMP"

echo "=== Full Promtail Backup ==="
mkdir -p "$BACKUP_PATH"

# 1. Backup ConfigMap
echo "1/4 Backing up ConfigMap..."
kubectl get configmap -n "$NAMESPACE" promtail-config -o yaml \
  > "$BACKUP_PATH/configmap.yaml"

# 2. Backup Helm values
echo "2/4 Backing up Helm values..."
helm get values "$RELEASE_NAME" -n "$NAMESPACE" \
  > "$BACKUP_PATH/values.yaml"

# 3. Backup Kubernetes manifests
echo "3/4 Backing up Kubernetes manifests..."
helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" \
  > "$BACKUP_PATH/manifest.yaml"

# 4. Backup positions file (optional)
echo "4/4 Backing up positions file..."
PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail -o jsonpath='{.items[*].metadata.name}')
mkdir -p "$BACKUP_PATH/positions"

for POD in $PODS; do
  kubectl exec -n "$NAMESPACE" "$POD" -- cat /run/promtail/positions.yaml \
    > "$BACKUP_PATH/positions/positions-$POD.yaml" 2>/dev/null || echo "  No positions file in $POD"
done

# Create backup manifest
cat > "$BACKUP_PATH/BACKUP_MANIFEST.txt" <<EOF
=== Promtail Full Backup ===
Timestamp: $TIMESTAMP
Namespace: $NAMESPACE
Release Name: $RELEASE_NAME
Backup Path: $BACKUP_PATH

Components:
- ConfigMap (configmap.yaml)
- Helm Values (values.yaml)
- Kubernetes Manifests (manifest.yaml)
- Positions Files (positions/*.yaml)

Files:
$(ls -lh "$BACKUP_PATH" | tail -n +2)
$(ls -lh "$BACKUP_PATH/positions" 2>/dev/null | tail -n +2)

RTO: < 30 minutes
RPO: 0 (no data loss)
EOF

echo ""
echo "=== Full Backup Complete ==="
cat "$BACKUP_PATH/BACKUP_MANIFEST.txt"
```

**Expected Output:**
```
=== Full Promtail Backup ===
1/4 Backing up ConfigMap...
2/4 Backing up Helm values...
3/4 Backing up Kubernetes manifests...
4/4 Backing up positions file...
  No positions file in promtail-abc123
  No positions file in promtail-def456

=== Full Backup Complete ===
=== Promtail Full Backup ===
Timestamp: 20250609-144500
Namespace: default
Release Name: my-promtail
Backup Path: ./backups/promtail/full-20250609-144500

Components:
- ConfigMap (configmap.yaml)
- Helm Values (values.yaml)
- Kubernetes Manifests (manifest.yaml)
- Positions Files (positions/*.yaml)

Files:
-rw-r--r-- 1 user user 8.5K Jun  9 14:45 configmap.yaml
-rw-r--r-- 1 user user 2.3K Jun  9 14:45 values.yaml
-rw-r--r-- 1 user user 12K  Jun  9 14:45 manifest.yaml
-rw-r--r-- 1 user user  450 Jun  9 14:45 BACKUP_MANIFEST.txt

RTO: < 30 minutes
RPO: 0 (no data loss)
```

---

## Recovery Procedures

### Scenario 1: Configuration-Only Recovery

**Use Case:** Promtail ConfigMap was accidentally deleted or corrupted

**Recovery Steps:**

1. **Restore ConfigMap:**
```bash
kubectl apply -f backups/promtail/config-20250609-143022/configmap.yaml
```

2. **Verify ConfigMap:**
```bash
kubectl get configmap -n default promtail-config -o yaml
```

3. **Restart Promtail pods to pick up configuration:**
```bash
kubectl rollout restart daemonset/my-promtail -n default
kubectl rollout status daemonset/my-promtail -n default
```

4. **Verify Promtail is sending logs:**
```bash
# Check Promtail logs
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=50

# Verify in Loki (if accessible)
# LogQL query: {app="promtail"}
```

**Expected RTO:** < 5 minutes

---

### Scenario 2: Full Cluster Recovery (Promtail Reinstall)

**Use Case:** Migrating to new cluster or complete Promtail reinstall

**Recovery Steps:**

1. **Restore from Helm values backup:**
```bash
# Install Promtail using backed-up values
helm install my-promtail scripton-charts/promtail \
  -f backups/promtail/full-20250609-144500/values.yaml \
  -n default
```

2. **Verify DaemonSet is running:**
```bash
kubectl get daemonset -n default my-promtail
kubectl get pods -n default -l app.kubernetes.io/name=promtail
```

3. **Check Promtail logs:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=100
```

4. **Verify log ingestion:**
```bash
# Check Promtail metrics endpoint
kubectl port-forward -n default svc/my-promtail 3101:3101

# Visit http://localhost:3101/metrics
# Look for: promtail_sent_entries_total
```

**Expected RTO:** < 15 minutes

**Note:** Promtail will start reading logs from the current position (tail mode) unless positions file is restored.

---

### Scenario 3: Positions File Recovery (Prevent Duplicate Logs)

**Use Case:** Restore positions file to prevent re-ingesting logs

**Recovery Steps:**

1. **Stop Promtail DaemonSet:**
```bash
kubectl scale daemonset/my-promtail -n default --replicas=0
kubectl wait --for=delete pod -n default -l app.kubernetes.io/name=promtail --timeout=60s
```

2. **Restore positions file to hostPath:**
```bash
# If using hostPath for positions file
# SSH to each node and restore positions file

# Example (adjust for your setup):
for NODE in $(kubectl get nodes -o name); do
  echo "Restoring positions to $NODE"
  # Copy positions file to node
  scp backups/promtail/positions-20250609-143500/positions-$NODE.yaml \
    $NODE:/var/lib/promtail/positions.yaml
done
```

3. **Restart Promtail:**
```bash
kubectl scale daemonset/my-promtail -n default --replicas=1
kubectl rollout status daemonset/my-promtail -n default
```

4. **Verify positions file is being used:**
```bash
# Check Promtail logs for "positions file loaded"
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=100 | grep -i position
```

**Expected RTO:** < 30 minutes

**Note:** This procedure is rarely needed. In most cases, it's acceptable to let Promtail start fresh and tail logs from the current position.

---

### Scenario 4: Disaster Recovery (Complete Restoration)

**Use Case:** Complete cluster loss, restore Promtail from backups

**Recovery Steps:**

1. **Verify cluster is ready:**
```bash
kubectl get nodes
kubectl get ns default
```

2. **Install Promtail from backup:**
```bash
# Use full backup
helm install my-promtail scripton-charts/promtail \
  -f backups/promtail/full-20250609-144500/values.yaml \
  -n default --create-namespace
```

3. **Verify installation:**
```bash
kubectl get all -n default -l app.kubernetes.io/name=promtail
```

4. **Check Promtail is running on all nodes:**
```bash
kubectl get pods -n default -l app.kubernetes.io/name=promtail -o wide
```

5. **Verify log shipping:**
```bash
# Check Promtail logs
kubectl logs -n default -l app.kubernetes.io/name=promtail --tail=50

# Verify metrics
kubectl port-forward -n default svc/my-promtail 3101:3101
curl http://localhost:3101/metrics | grep promtail_sent_entries_total
```

**Expected RTO:** < 30 minutes

**RPO:** 0 (Promtail is stateless, no data loss)

---

## Automation

### Automated Configuration Backup (CronJob)

**CronJob Manifest:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: promtail-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: promtail-backup
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
              BACKUP_DIR="/backups/promtail"
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)

              echo "=== Promtail Backup Started ==="
              mkdir -p "$BACKUP_DIR/config-$TIMESTAMP"

              # Backup ConfigMap
              kubectl get configmap -n "$NAMESPACE" promtail-config -o yaml \
                > "$BACKUP_DIR/config-$TIMESTAMP/configmap.yaml"

              echo "Backup saved to: $BACKUP_DIR/config-$TIMESTAMP/"
              ls -lh "$BACKUP_DIR/config-$TIMESTAMP/"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: promtail-backup-pvc
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail-backup
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: promtail-backup
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
  name: promtail-backup
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: promtail-backup
subjects:
- kind: ServiceAccount
  name: promtail-backup
  namespace: default
```

**Deploy CronJob:**
```bash
kubectl apply -f promtail-backup-cronjob.yaml
```

**Verify CronJob:**
```bash
kubectl get cronjob -n default promtail-backup
kubectl get jobs -n default -l job-name=promtail-backup
```

---

### Backup Retention Script

**Cleanup Old Backups:**

```bash
#!/bin/bash
# Script: promtail-backup-cleanup.sh
# Description: Clean up old Promtail backups

BACKUP_DIR="${BACKUP_DIR:-./backups/promtail}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

echo "=== Promtail Backup Cleanup ==="
echo "Backup directory: $BACKUP_DIR"
echo "Retention period: $RETENTION_DAYS days"

# Find and delete backups older than retention period
find "$BACKUP_DIR" -type d -name "config-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
find "$BACKUP_DIR" -type d -name "positions-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
find "$BACKUP_DIR" -type d -name "full-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Cleanup complete"
echo "Remaining backups:"
ls -lh "$BACKUP_DIR"
```

**Add to Cron:**
```bash
# Run daily at 3 AM
0 3 * * * /path/to/promtail-backup-cleanup.sh
```

---

## Testing Backups

### Backup Validation

**Automated Backup Test Script:**

```bash
#!/bin/bash
# Script: promtail-test-backup.sh
# Description: Test Promtail backup restoration

set -e

BACKUP_PATH="${1:-./backups/promtail/full-20250609-144500}"
TEST_NAMESPACE="promtail-test"

echo "=== Promtail Backup Test ==="
echo "Testing backup: $BACKUP_PATH"

# 1. Create test namespace
echo "1/5 Creating test namespace..."
kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Restore ConfigMap
echo "2/5 Restoring ConfigMap..."
kubectl apply -f "$BACKUP_PATH/configmap.yaml" -n "$TEST_NAMESPACE"

# 3. Install Promtail with backed-up values
echo "3/5 Installing Promtail..."
helm install promtail-test scripton-charts/promtail \
  -f "$BACKUP_PATH/values.yaml" \
  -n "$TEST_NAMESPACE" --wait --timeout=5m

# 4. Verify deployment
echo "4/5 Verifying deployment..."
kubectl get daemonset -n "$TEST_NAMESPACE"
kubectl get pods -n "$TEST_NAMESPACE" -l app.kubernetes.io/name=promtail

# 5. Cleanup
echo "5/5 Cleaning up..."
read -p "Delete test namespace? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  helm uninstall promtail-test -n "$TEST_NAMESPACE"
  kubectl delete namespace "$TEST_NAMESPACE"
  echo "Test namespace deleted"
fi

echo ""
echo "=== Backup Test Complete ==="
echo "Backup is valid and can be used for recovery"
```

**Run Test:**
```bash
chmod +x promtail-test-backup.sh
./promtail-test-backup.sh ./backups/promtail/full-20250609-144500
```

---

## Troubleshooting

### Issue 1: Positions File Not Found

**Symptom:**
```
Error: cannot read positions file: /run/promtail/positions.yaml
```

**Cause:** Positions file path is incorrect or positions file is corrupted

**Solution:**
1. Check positions file path in ConfigMap:
```bash
kubectl get configmap -n default promtail-config -o yaml | grep positions
```

2. Verify positions file exists:
```bash
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- ls -l /run/promtail/
```

3. If missing, Promtail will create a new one automatically. Restart the pod:
```bash
kubectl delete pod -n default $POD
```

---

### Issue 2: Duplicate Logs After Recovery

**Symptom:** Loki shows duplicate log entries after Promtail recovery

**Cause:** Positions file was not restored, causing Promtail to re-read logs

**Solution:**
1. Accept duplicates (they will age out based on Loki retention)
2. Use Loki deduplication feature (if enabled)
3. Restore positions file before starting Promtail (see Scenario 3)

**Prevention:** Backup positions file before major changes

---

### Issue 3: ConfigMap Restore Fails

**Symptom:**
```
Error from server (AlreadyExists): configmaps "promtail-config" already exists
```

**Cause:** ConfigMap already exists in namespace

**Solution:**
1. Delete existing ConfigMap:
```bash
kubectl delete configmap -n default promtail-config
```

2. Restore from backup:
```bash
kubectl apply -f backups/promtail/config-20250609-143022/configmap.yaml
```

3. Restart Promtail:
```bash
kubectl rollout restart daemonset/my-promtail -n default
```

---

### Issue 4: Backup Script Permissions Denied

**Symptom:**
```
Error: unable to get configmap: configmaps "promtail-config" is forbidden
```

**Cause:** Service account lacks permissions

**Solution:**
1. Create Role and RoleBinding:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: promtail-backup
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps", "pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: promtail-backup
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: promtail-backup
subjects:
- kind: ServiceAccount
  name: promtail-backup
  namespace: default
```

2. Apply RBAC:
```bash
kubectl apply -f promtail-backup-rbac.yaml
```

---

## Best Practices

### 1. Configuration Management

**DO:**
- ✅ Store Helm values.yaml in Git
- ✅ Use GitOps for deployment (ArgoCD, FluxCD)
- ✅ Backup ConfigMap after each change
- ✅ Test configuration changes in dev/staging first
- ✅ Document all configuration changes

**DON'T:**
- ❌ Manually edit ConfigMap in production
- ❌ Store sensitive data unencrypted
- ❌ Skip backup before major changes
- ❌ Deploy untested configurations to production

---

### 2. Backup Strategy

**DO:**
- ✅ Automate configuration backups (daily CronJob)
- ✅ Test backups regularly (monthly)
- ✅ Store backups in multiple locations (S3, Git, PVC)
- ✅ Implement backup retention policy (30 days)
- ✅ Monitor backup job success

**DON'T:**
- ❌ Rely on positions file backup (Promtail is stateless)
- ❌ Store backups only locally
- ❌ Skip testing backup restoration
- ❌ Keep backups forever (implement retention)

---

### 3. Recovery Planning

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
- ❌ Over-rely on positions file recovery

---

### 4. Monitoring and Alerts

**DO:**
- ✅ Monitor backup job completion
- ✅ Alert on backup failures
- ✅ Track backup storage usage
- ✅ Monitor Promtail log shipping rate
- ✅ Alert on Promtail pod failures

**DON'T:**
- ❌ Ignore backup job failures
- ❌ Skip monitoring backup storage
- ❌ Assume Promtail is always working
- ❌ Forget to rotate backup credentials

---

## Summary

Promtail backup is straightforward due to its stateless nature:

**Critical Components:**
1. **Configuration** (ConfigMap, values.yaml) - Essential for recovery
2. **Kubernetes Manifests** (DaemonSet, RBAC) - Required for redeployment
3. **Positions File** (Optional) - Prevents duplicate log ingestion

**Recommended Backup Strategy:**
- **Configuration**: Daily automated backups via CronJob
- **Git-based**: Store values.yaml in Git (best practice)
- **Positions File**: Optional, backup before major changes

**RTO/RPO:**
- **RTO**: < 30 minutes (configuration restore + redeploy)
- **RPO**: 0 (Promtail is stateless, no data stored)

**Key Takeaway:** Focus on configuration backup and version control. Promtail can be quickly redeployed from backed-up Helm values, and it will resume log shipping immediately.

---

**Related Documentation:**
- [Promtail Upgrade Guide](promtail-upgrade-guide.md)
- [Promtail Chart README](../charts/promtail/README.md)
- [Loki Backup Guide](loki-backup-guide.md) (for log retention)
- [Disaster Recovery Guide](disaster-recovery-guide.md)

**Last Updated:** 2025-12-09
