# Grafana Upgrade Guide

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [Strategy 1: Rolling Upgrade (Recommended)](#strategy-1-rolling-upgrade-recommended)
  - [Strategy 2: In-Place Upgrade](#strategy-2-in-place-upgrade)
  - [Strategy 3: Blue-Green Deployment](#strategy-3-blue-green-deployment)
  - [Strategy 4: Database Migration](#strategy-4-database-migration)
- [Version-Specific Upgrade Notes](#version-specific-upgrade-notes)
  - [Grafana 10.x → 11.x](#grafana-10x--11x)
  - [Grafana 9.x → 10.x](#grafana-9x--10x)
  - [Grafana 8.x → 9.x](#grafana-8x--9x)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides comprehensive procedures for upgrading Grafana instances deployed via the Helm chart.

**Upgrade Philosophy:**
- **Minimize downtime**: Rolling upgrades for zero-downtime deployments
- **Version compatibility**: Always test major version upgrades in staging first
- **Plugin compatibility**: Verify plugin compatibility before upgrading
- **Database migration**: Grafana automatically migrates database schema on startup
- **Backup first**: Always backup before upgrading (CRITICAL)

**Upgrade Complexity Matrix:**

| Upgrade Type | Complexity | Downtime | Risk | Recommended Strategy |
|--------------|------------|----------|------|----------------------|
| Patch (10.3.0 → 10.3.1) | Low | None | Low | Rolling Upgrade |
| Minor (10.3.x → 10.4.x) | Medium | None | Low-Medium | Rolling Upgrade |
| Major (10.x → 11.x) | High | Optional | Medium-High | Blue-Green or In-Place |
| Multi-Major (9.x → 11.x) | Very High | Required | High | Database Migration |

**Important Version Compatibility Notes:**
- Grafana database schema is automatically migrated on startup (forward compatible only)
- Plugins may not be compatible across major versions
- Breaking changes in major versions require configuration updates
- Downgrading requires database restore (schema downgrades not supported)

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**CRITICAL:** Always review Grafana release notes before upgrading.

```bash
# Check current Grafana version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# Review release notes for target version
# Visit: https://grafana.com/docs/grafana/latest/whatsnew/
# Check for:
# - Breaking changes
# - Deprecated features
# - Plugin compatibility
# - Database migration notes
# - Configuration changes
```

**Key areas to review:**
- Breaking changes in dashboards, datasources, or alerting
- Authentication/authorization changes
- Plugin API changes
- Database schema migrations
- Configuration file changes (grafana.ini)

### 2. Backup Everything

**MANDATORY:** Create comprehensive backups before any upgrade.

```bash
# Using Makefile (recommended - comprehensive backup)
make -f make/ops/grafana.mk grafana-pre-upgrade-check
make -f make/ops/grafana.mk grafana-full-backup

# Manual backup steps:
# 1. Backup database
make -f make/ops/grafana.mk grafana-backup-db

# 2. Backup dashboards and datasources
make -f make/ops/grafana.mk grafana-backup-dashboards
make -f make/ops/grafana.mk grafana-backup-datasources

# 3. Backup configuration
make -f make/ops/grafana.mk grafana-backup-config
make -f make/ops/grafana.mk grafana-backup-secrets

# 4. Backup plugins
make -f make/ops/grafana.mk grafana-backup-plugins

# 5. Create VolumeSnapshot (if supported)
make -f make/ops/grafana.mk grafana-backup-snapshot

# Verify all backups created
ls -lh grafana-*-backup-*
```

See [Backup Guide](grafana-backup-guide.md) for detailed backup procedures.

### 3. Document Current State

Capture current Grafana configuration and state:

```bash
# Get current Helm values
helm get values grafana -n <namespace> > grafana-values-current.yaml

# Get current Grafana version
CURRENT_VERSION=$(kubectl get deployment grafana -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
echo "Current Grafana version: $CURRENT_VERSION"

# Get current Chart version
CHART_VERSION=$(helm list -n <namespace> -o json | jq -r '.[] | select(.name=="grafana") | .chart')
echo "Current Chart version: $CHART_VERSION"

# List installed plugins
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls > grafana-plugins-current.txt

# Count dashboards and datasources
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl port-forward -n <namespace> svc/grafana 3000:80 &

DASHBOARD_COUNT=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '. | length')
DATASOURCE_COUNT=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '. | length')

echo "Current state:"
echo "  Dashboards: $DASHBOARD_COUNT"
echo "  Datasources: $DATASOURCE_COUNT"
echo "  Plugins: $(wc -l < grafana-plugins-current.txt)"

# Save state summary
cat > grafana-state-pre-upgrade.txt <<EOF
Grafana Upgrade Pre-Check
Date: $(date)
Current Grafana Version: $CURRENT_VERSION
Current Chart Version: $CHART_VERSION
Dashboards: $DASHBOARD_COUNT
Datasources: $DATASOURCE_COUNT
Plugins: $(wc -l < grafana-plugins-current.txt)
EOF
```

### 4. Verify Plugin Compatibility

Check if installed plugins are compatible with target Grafana version:

```bash
# List installed plugins
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls

# For each plugin, check compatibility at:
# https://grafana.com/grafana/plugins/

# Example: Check if plugin supports target Grafana version
PLUGIN_ID="grafana-piechart-panel"
TARGET_VERSION="11.0.0"

# Visit plugin page and verify version compatibility
# https://grafana.com/grafana/plugins/$PLUGIN_ID/

# Update plugins before upgrading Grafana (if needed)
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins update-all
```

**Common plugin compatibility issues:**
- Core plugins: Usually compatible (included in Grafana)
- Community plugins: Check plugin page for version compatibility
- Enterprise plugins: Contact Grafana Labs for compatibility matrix

### 5. Test Upgrade in Staging

**CRITICAL for major version upgrades:** Always test in staging/dev environment first.

```bash
# Deploy Grafana to staging namespace with same configuration
kubectl create namespace grafana-staging

# Copy secrets and configmaps to staging
kubectl get secret grafana-secret -n <namespace> -o yaml | \
  sed 's/namespace: <namespace>/namespace: grafana-staging/' | \
  kubectl apply -f -

kubectl get configmap grafana-config -n <namespace> -o yaml | \
  sed 's/namespace: <namespace>/namespace: grafana-staging/' | \
  kubectl apply -f -

# Deploy staging Grafana with new version
helm install grafana-staging charts/grafana \
  --namespace grafana-staging \
  --set image.tag=<new-version> \
  --values grafana-values-current.yaml

# Test staging environment
# - Verify dashboards load correctly
# - Test datasource connectivity
# - Verify alerting rules
# - Test plugin functionality
# - Check for errors in logs

# Cleanup staging after validation
helm uninstall grafana-staging -n grafana-staging
kubectl delete namespace grafana-staging
```

### 6. Schedule Maintenance Window

For major version upgrades, schedule a maintenance window:

**Recommended maintenance windows:**
- Patch upgrades: No maintenance window needed (rolling upgrade)
- Minor upgrades: Optional 15-30 minute window (rolling upgrade with brief disruption)
- Major upgrades: 1-2 hour maintenance window (potential database migration)

**Communication template:**

```
Subject: Grafana Upgrade Maintenance Window

Dear Team,

We will be upgrading Grafana from version X.Y.Z to A.B.C on [DATE] at [TIME].

Expected Duration: [DURATION]
Expected Impact: [NONE/BRIEF DISRUPTION/FULL DOWNTIME]

During this window:
- [DESCRIBE IMPACT]

Rollback Plan: [DESCRIBE ROLLBACK STRATEGY]

Please contact [CONTACT] if you have any concerns.
```

### 7. Prepare Rollback Plan

Document rollback procedures before upgrade:

```bash
# Rollback plan checklist:
# 1. Have database backup ready
# 2. Have previous Helm values saved
# 3. Know previous Grafana version
# 4. Know previous Chart version
# 5. Document rollback command

# Example rollback command (save this before upgrade):
cat > grafana-rollback-plan.sh <<'EOF'
#!/bin/bash
# Grafana Rollback Plan
# Created: $(date)

NAMESPACE="<namespace>"
PREVIOUS_VERSION="<previous-grafana-version>"
PREVIOUS_CHART_VERSION="<previous-chart-version>"
BACKUP_DATE="<backup-date>"

echo "Rolling back Grafana to version $PREVIOUS_VERSION"

# Option 1: Helm rollback
helm rollback grafana -n $NAMESPACE

# Option 2: Restore from backup
# ... (see Rollback Procedures section)

echo "Rollback completed. Verify Grafana status."
EOF

chmod +x grafana-rollback-plan.sh
```

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Recommended)

**Best for:** Patch and minor version upgrades (e.g., 10.3.0 → 10.3.1, 10.3.x → 10.4.x)

**Characteristics:**
- ✅ Zero downtime
- ✅ Automatic rollback on failure
- ✅ Gradual traffic shift
- ❌ Not suitable for breaking changes
- ❌ Requires health checks configured

**Prerequisites:**
- Helm chart installed
- Health probes configured (liveness, readiness)
- Backup completed

**Procedure:**

#### Step 1: Pre-Upgrade Backup

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-pre-upgrade-check
make -f make/ops/grafana.mk grafana-full-backup

# Verify backups
ls -lh grafana-*-backup-*
```

#### Step 2: Update Helm Chart

```bash
# Update Helm repository
helm repo update

# Check available chart versions
helm search repo scripton-charts/grafana --versions | head -10

# Review chart changes
helm show values scripton-charts/grafana --version <new-chart-version> > grafana-values-new.yaml
diff grafana-values-current.yaml grafana-values-new.yaml
```

#### Step 3: Perform Rolling Upgrade

```bash
# Upgrade using Helm (rolling upgrade)
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --reuse-values \
  --timeout 10m \
  --wait

# Monitor rollout status
kubectl rollout status deployment/grafana -n <namespace> --timeout=600s

# Watch pod replacement
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana -w
```

**Expected behavior:**
1. New pod created with new Grafana version
2. New pod becomes ready (passes health checks)
3. Old pod terminated
4. Traffic automatically shifts to new pod

#### Step 4: Verify Upgrade

```bash
# Using Makefile
make -f make/ops/grafana.mk grafana-post-upgrade-check

# Manual verification
# 1. Check new version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# 2. Verify pod is running
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana

# 3. Check logs for errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana --tail=100 | grep -i error

# 4. Verify dashboards via API
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl port-forward -n <namespace> svc/grafana 3000:80 &

DASHBOARD_COUNT_AFTER=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '. | length')
DATASOURCE_COUNT_AFTER=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '. | length')

echo "Post-upgrade state:"
echo "  Dashboards: $DASHBOARD_COUNT_AFTER (before: $DASHBOARD_COUNT)"
echo "  Datasources: $DATASOURCE_COUNT_AFTER (before: $DATASOURCE_COUNT)"

# 5. Test dashboard functionality
# Access http://localhost:3000 and verify dashboards load correctly
```

#### Step 5: Monitor for Issues

Monitor Grafana for 24-48 hours after upgrade:

```bash
# Monitor Grafana logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana -f

# Check pod restarts
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana \
  -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount

# Monitor resource usage
kubectl top pod -n <namespace> -l app.kubernetes.io/name=grafana

# Check for errors in dashboard queries
# (via Grafana UI - look for query errors)
```

---

### Strategy 2: In-Place Upgrade

**Best for:** Minor and major version upgrades with acceptable brief downtime (e.g., 10.x → 11.x)

**Characteristics:**
- ⚠️ Brief downtime (1-5 minutes)
- ✅ Simple procedure
- ✅ Database automatically migrated
- ❌ Requires downtime window

**Prerequisites:**
- Maintenance window scheduled
- Backup completed
- Database migration tested in staging (for major versions)

**Procedure:**

#### Step 1: Pre-Upgrade Backup

```bash
# Complete backup
make -f make/ops/grafana.mk grafana-full-backup

# Verify backups
ls -lh grafana-*-backup-*
```

#### Step 2: Scale Down Grafana

```bash
# Scale down to 0 replicas
kubectl scale deployment grafana -n <namespace> --replicas=0

# Wait for pod termination
kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=60s

# Verify no pods running
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana
```

#### Step 3: Upgrade Helm Release

```bash
# Upgrade Helm release with new version
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --reuse-values \
  --timeout 10m

# Note: Deployment will remain at 0 replicas
```

#### Step 4: Scale Up Grafana

```bash
# Scale up to 1 replica
kubectl scale deployment grafana -n <namespace> --replicas=1

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=600s

# Monitor database migration logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana -f | grep -i migration
```

**Expected logs during database migration:**

```
logger=migrator t=2025-01-01T00:00:00.000000000Z level=info msg="Starting DB migrations"
logger=migrator t=2025-01-01T00:00:00.000000000Z level=info msg="Executing migration" id="add index user.login"
logger=migrator t=2025-01-01T00:00:00.000000000Z level=info msg="Migration completed"
```

#### Step 5: Verify Upgrade

```bash
# Verify new version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# Check database integrity
make -f make/ops/grafana.mk grafana-db-integrity-check

# Verify dashboards and datasources
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

---

### Strategy 3: Blue-Green Deployment

**Best for:** Major version upgrades with zero downtime and easy rollback (e.g., 10.x → 11.x)

**Characteristics:**
- ✅ Zero downtime
- ✅ Easy rollback (switch back to blue)
- ✅ Full testing before cutover
- ❌ Requires 2x resources temporarily
- ❌ Complex setup (requires PVC clone or shared storage)

**Prerequisites:**
- PVC clone support (VolumeSnapshot) or shared storage
- Load balancer or Ingress for traffic switching
- Backup completed

**Procedure:**

#### Step 1: Clone Grafana PVC

```bash
# Option 1: Using VolumeSnapshot (recommended)
# Create snapshot of current PVC
make -f make/ops/grafana.mk grafana-backup-snapshot

# Create new PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data-green
  namespace: <namespace>
spec:
  storageClassName: <your-storage-class>
  dataSource:
    name: grafana-data-snapshot-<latest>
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/grafana-data-green -n <namespace> --timeout=300s

# Option 2: Using PVC clone (if supported by storage class)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data-green
  namespace: <namespace>
spec:
  storageClassName: <your-storage-class>
  dataSource:
    name: grafana-data
    kind: PersistentVolumeClaim
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
```

#### Step 2: Deploy Green Environment

```bash
# Deploy new Grafana instance (green) with new version
helm install grafana-green charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --set persistence.existingClaim=grafana-data-green \
  --set service.port=81 \
  --set fullnameOverride=grafana-green \
  --values grafana-values-current.yaml

# Wait for green deployment to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana-green -n <namespace> --timeout=600s

# Verify green environment
kubectl exec -n <namespace> deployment/grafana-green -- grafana-cli -v
```

#### Step 3: Test Green Environment

```bash
# Port-forward to green environment
kubectl port-forward -n <namespace> svc/grafana-green 3001:81 &

# Access green environment at http://localhost:3001
# Verify:
# - All dashboards load correctly
# - All datasources work
# - Alerting rules function
# - Plugins are compatible
# - No errors in logs

# Check green environment logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana-green --tail=100
```

#### Step 4: Switch Traffic to Green

**Option A: Using Kubernetes Service selector update**

```bash
# Update main Grafana service to point to green deployment
kubectl patch service grafana -n <namespace> -p '{"spec":{"selector":{"app.kubernetes.io/instance":"grafana-green"}}}'

# Verify service endpoints
kubectl get endpoints grafana -n <namespace>
```

**Option B: Using Ingress weight-based routing (if supported)**

```yaml
# Update Ingress to gradually shift traffic
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "100"  # 100% to green
spec:
  rules:
  - host: grafana.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-green
            port:
              number: 81
```

#### Step 5: Monitor Green Environment

Monitor green environment for 24-48 hours:

```bash
# Monitor logs
kubectl logs -n <namespace> -l app.kubernetes.io/instance=grafana-green -f

# Monitor resource usage
kubectl top pod -n <namespace> -l app.kubernetes.io/instance=grafana-green

# Verify dashboard queries
# (via Grafana UI)
```

#### Step 6: Decommission Blue Environment

After successful cutover (24-48 hours):

```bash
# Uninstall blue environment
helm uninstall grafana -n <namespace>

# Optionally delete blue PVC (ONLY if green is stable)
# kubectl delete pvc grafana-data -n <namespace>

# Rename green to primary
# Update service selector or Ingress to use grafana-green as primary
```

---

### Strategy 4: Database Migration

**Best for:** Multi-major version upgrades or when database corruption/migration issues exist (e.g., 9.x → 11.x)

**Characteristics:**
- ⚠️ Significant downtime (30-60 minutes)
- ✅ Clean database migration
- ✅ Opportunity to fix database issues
- ❌ Complex procedure
- ❌ Requires manual export/import

**Prerequisites:**
- Extended maintenance window (1-2 hours)
- Comprehensive backup of all dashboards and datasources
- New Grafana instance ready

**Procedure:**

#### Step 1: Export All Dashboards and Datasources

```bash
# Export all dashboards
make -f make/ops/grafana.mk grafana-backup-dashboards

# Export all datasources
make -f make/ops/grafana.mk grafana-backup-datasources

# Export folders
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl port-forward -n <namespace> svc/grafana 3000:80 &

curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/folders > grafana-folders-export.json

# Verify exports
DASHBOARD_COUNT=$(ls -1 grafana-dashboards-backup-*/dashboard-*.json | wc -l)
DATASOURCE_COUNT=$(jq '. | length' grafana-datasources-backup-*/datasources.json)

echo "Exported:"
echo "  Dashboards: $DASHBOARD_COUNT"
echo "  Datasources: $DATASOURCE_COUNT"
```

#### Step 2: Deploy New Grafana Instance

```bash
# Scale down old Grafana
kubectl scale deployment grafana -n <namespace> --replicas=0

# Create new PVC for new Grafana instance
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data-new
  namespace: <namespace>
spec:
  storageClassName: <your-storage-class>
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Upgrade Helm release with new version and new PVC
helm upgrade grafana charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --set persistence.existingClaim=grafana-data-new \
  --reuse-values \
  --timeout 10m

# Wait for new Grafana to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=600s
```

#### Step 3: Import Datasources

```bash
# Get new Grafana admin password (may be regenerated)
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)

# Port-forward to new Grafana
kubectl port-forward -n <namespace> svc/grafana 3000:80 &

# Import datasources
BACKUP_DIR="grafana-datasources-backup-<date>"

for file in "$BACKUP_DIR"/datasource-*.json; do
  echo "Importing datasource: $file"
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d @"$file" \
    http://localhost:3000/api/datasources
done

# Verify datasources
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '.[] | {id, name, type}'
```

#### Step 4: Import Folders and Dashboards

```bash
# Import folders first
cat grafana-folders-export.json | jq -c '.[]' | while read folder; do
  FOLDER_TITLE=$(echo $folder | jq -r '.title')
  FOLDER_UID=$(echo $folder | jq -r '.uid')

  echo "Importing folder: $FOLDER_TITLE"
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d "{\"uid\":\"$FOLDER_UID\",\"title\":\"$FOLDER_TITLE\"}" \
    http://localhost:3000/api/folders
done

# Import dashboards
BACKUP_DIR="grafana-dashboards-backup-<date>"

for file in "$BACKUP_DIR"/dashboard-*.json; do
  DASHBOARD_UID=$(jq -r '.uid' "$file")
  echo "Importing dashboard: $DASHBOARD_UID"

  jq -n --slurpfile dashboard "$file" \
    '{dashboard: $dashboard[0], overwrite: true}' | \
  curl -X POST -u admin:$GRAFANA_PASSWORD \
    -H "Content-Type: application/json" \
    -d @- \
    http://localhost:3000/api/dashboards/db
done

# Verify dashboards
DASHBOARD_COUNT_AFTER=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '. | length')
echo "Imported $DASHBOARD_COUNT_AFTER dashboards (expected: $DASHBOARD_COUNT)"
```

#### Step 5: Verify Migration

```bash
# Verify all components
make -f make/ops/grafana.mk grafana-post-upgrade-check

# Test dashboard functionality
# Access http://localhost:3000 and verify:
# - All dashboards render correctly
# - All datasources connect successfully
# - Queries return expected data
# - Alerting rules are active

# Check logs for migration errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana --tail=200 | grep -i error
```

#### Step 6: Cleanup Old PVC (After Verification)

```bash
# ONLY after 24-48 hours of successful operation
# Delete old PVC to free storage
kubectl delete pvc grafana-data -n <namespace>

# Rename new PVC to standard name (optional)
# ... (requires recreating with correct name)
```

---

## Version-Specific Upgrade Notes

### Grafana 10.x → 11.x

**Release Date:** May 2024
**Upgrade Complexity:** High
**Recommended Strategy:** Blue-Green Deployment or Database Migration

#### Breaking Changes

1. **Angular Plugin Support Removed**
   - Grafana 11.x completely removes Angular plugin support
   - **Impact:** Angular-based plugins will not work
   - **Action Required:**
     ```bash
     # List installed Angular plugins
     kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls | grep -i angular

     # Replace Angular plugins with React alternatives:
     # - grafana-piechart-panel → piechart-panel-v2
     # - grafana-worldmap-panel → geomap panel (built-in)
     # - grafana-clock-panel → clock panel (built-in)
     ```

2. **Dashboard Schema Changes**
   - Dashboard JSON schema updated for improved panel types
   - **Impact:** Some dashboard JSON may need minor updates
   - **Action Required:** Test all dashboards in staging before production upgrade

3. **Alerting Changes**
   - Unified alerting becomes mandatory (legacy alerting removed)
   - **Impact:** Legacy alerting rules must be migrated
   - **Action Required:**
     ```bash
     # Verify unified alerting is enabled
     kubectl exec -n <namespace> deployment/grafana -- cat /etc/grafana/grafana.ini | grep -A 5 "\[unified_alerting\]"

     # Should show:
     # [unified_alerting]
     # enabled = true
     ```

4. **Datasource Query Changes**
   - Some datasource query formats updated
   - **Impact:** Prometheus, Loki, and CloudWatch queries may need updates
   - **Action Required:** Test all datasource queries in staging

#### Recommended Upgrade Path

```bash
# 1. Update all plugins to latest React versions
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins update-all

# 2. Backup everything
make -f make/ops/grafana.mk grafana-full-backup

# 3. Test upgrade in staging (CRITICAL)
# ... (see Pre-Upgrade Checklist > Test Upgrade in Staging)

# 4. Perform blue-green upgrade
# ... (see Strategy 3: Blue-Green Deployment)

# 5. Migrate Angular plugins to React alternatives
# ... (install new plugins in green environment)

# 6. Test all dashboards and queries
# ... (verify in green environment before cutover)
```

#### Post-Upgrade Validation

```bash
# Verify no Angular plugins remain
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls | grep -i angular
# Should return empty

# Check unified alerting status
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/alertmanager/grafana/api/v2/status | jq '.cluster.status'

# Verify all dashboards render
# ... (manual verification via UI)
```

---

### Grafana 9.x → 10.x

**Release Date:** June 2023
**Upgrade Complexity:** Medium-High
**Recommended Strategy:** Rolling Upgrade or In-Place Upgrade

#### Breaking Changes

1. **Legacy Alerting Disabled by Default**
   - Unified alerting enabled by default
   - **Impact:** Legacy alerting deprecated
   - **Action Required:**
     ```bash
     # Migrate legacy alerts to unified alerting
     # Via Grafana UI: Alerting > Admin > Upgrade legacy alerts

     # Or enable legacy alerting temporarily (NOT recommended):
     # grafana.ini:
     # [alerting]
     # enabled = true
     # [unified_alerting]
     # enabled = false
     ```

2. **Dashboard UID Required**
   - All dashboards must have unique UID
   - **Impact:** Dashboards without UID will get auto-generated UID
   - **Action Required:** Verify all dashboards have UID before upgrade

3. **SQL Datasource Changes**
   - MySQL, PostgreSQL, MSSQL datasource query format updated
   - **Impact:** Some SQL queries may need adjustments
   - **Action Required:** Test all SQL datasource queries in staging

#### Recommended Upgrade Path

```bash
# 1. Backup everything
make -f make/ops/grafana.mk grafana-full-backup

# 2. Migrate legacy alerts (if using legacy alerting)
# Via Grafana UI: Alerting > Admin > Upgrade legacy alerts

# 3. Verify all dashboards have UID
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '.[] | select(.uid == null or .uid == "")'
# Should return empty array

# 4. Perform rolling upgrade
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=10.4.0 \
  --reuse-values

# 5. Verify upgrade
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

---

### Grafana 8.x → 9.x

**Release Date:** June 2022
**Upgrade Complexity:** Medium
**Recommended Strategy:** Rolling Upgrade

#### Breaking Changes

1. **Unified Alerting Introduced**
   - New alerting system introduced (legacy alerting still available)
   - **Impact:** New alerting features available
   - **Action Required:** Plan migration to unified alerting

2. **Dashboard Permissions Changes**
   - Improved dashboard folder permissions
   - **Impact:** Minor permission model changes
   - **Action Required:** Verify folder permissions after upgrade

3. **Plugin Signature Enforcement**
   - Unsigned plugins blocked by default
   - **Impact:** Unsigned custom plugins will not load
   - **Action Required:**
     ```bash
     # Allow unsigned plugins (NOT recommended for production):
     # grafana.ini:
     # [plugins]
     # allow_loading_unsigned_plugins = plugin-id1,plugin-id2

     # Better: Sign custom plugins or use signed alternatives
     ```

#### Recommended Upgrade Path

```bash
# 1. Backup everything
make -f make/ops/grafana.mk grafana-full-backup

# 2. Verify plugin signatures
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls
# Check for unsigned plugins

# 3. Perform rolling upgrade
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=9.5.0 \
  --reuse-values

# 4. Verify upgrade
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Using Makefile (comprehensive validation)
make -f make/ops/grafana.mk grafana-post-upgrade-check

# Manual validation checklist:
# 1. Verify Grafana version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# 2. Check pod status
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana

# 3. Verify logs for errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana --tail=100 | grep -i error

# 4. Check database integrity
make -f make/ops/grafana.mk grafana-db-integrity-check

# 5. Verify dashboards count
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl port-forward -n <namespace> svc/grafana 3000:80 &

DASHBOARD_COUNT=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '. | length')
echo "Dashboard count: $DASHBOARD_COUNT (expected: <pre-upgrade-count>)"

# 6. Verify datasources count
DATASOURCE_COUNT=$(curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '. | length')
echo "Datasource count: $DATASOURCE_COUNT (expected: <pre-upgrade-count>)"

# 7. Test datasource connectivity
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq -r '.[].id' | while read ds_id; do
  echo "Testing datasource ID: $ds_id"
  curl -s -u admin:$GRAFANA_PASSWORD "http://localhost:3000/api/datasources/proxy/$ds_id/api/v1/query?query=up" | jq '.status'
done
```

### Manual Validation

**Dashboard Functionality:**
1. Access Grafana UI
2. Open 5-10 representative dashboards
3. Verify:
   - Dashboards load without errors
   - All panels render correctly
   - Queries return expected data
   - Time range selection works
   - Refresh works correctly
   - Variables/templating works

**Datasource Connectivity:**
1. Navigate to Configuration > Datasources
2. Test each datasource using "Save & Test" button
3. Verify all datasources show "Data source is working"

**Alerting Functionality:**
1. Navigate to Alerting > Alert Rules
2. Verify all alert rules are present
3. Check alert rule status (OK, Pending, Alerting)
4. Test notification channels

**Plugin Functionality:**
1. Navigate to Configuration > Plugins
2. Verify all plugins are loaded
3. Test plugin-specific functionality (if using custom plugins)

**User Access:**
1. Test login with non-admin user
2. Verify user permissions
3. Test team/organization access (if using)

---

## Rollback Procedures

### Rollback Strategy 1: Helm Rollback (Quick)

**Best for:** Rolling upgrades that completed but have issues

```bash
# Check Helm release history
helm history grafana -n <namespace>

# Rollback to previous revision
helm rollback grafana -n <namespace>

# Or rollback to specific revision
helm rollback grafana <revision-number> -n <namespace>

# Verify rollback
kubectl rollout status deployment/grafana -n <namespace>
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# Verify dashboards and datasources
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

**Limitations:**
- Only rolls back Helm configuration, not database schema
- Database schema downgrades not supported by Grafana
- If database migration occurred, may require database restore

---

### Rollback Strategy 2: Database Restore (Complete)

**Best for:** Major version upgrades with database migration issues

```bash
# Step 1: Stop Grafana
kubectl scale deployment grafana -n <namespace> --replicas=0

# Step 2: Restore database from backup
# ... (see Backup Guide > Database Recovery)

# Step 3: Rollback Helm release to previous version
helm rollback grafana -n <namespace>

# Step 4: Start Grafana
kubectl scale deployment grafana -n <namespace> --replicas=1
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=600s

# Step 5: Verify rollback
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

---

### Rollback Strategy 3: Blue-Green Switchback

**Best for:** Blue-green deployments with issues in green environment

```bash
# Step 1: Switch traffic back to blue environment
kubectl patch service grafana -n <namespace> -p '{"spec":{"selector":{"app.kubernetes.io/instance":"grafana"}}}'

# Step 2: Verify blue environment is serving traffic
kubectl get endpoints grafana -n <namespace>

# Step 3: Decommission green environment
helm uninstall grafana-green -n <namespace>
kubectl delete pvc grafana-data-green -n <namespace>

# Step 4: Verify blue environment
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

---

## Troubleshooting

### Issue 1: Grafana Pod CrashLoopBackOff After Upgrade

**Symptom:**
```
NAME                      READY   STATUS             RESTARTS   AGE
grafana-5d7f8c9b8-abc12   0/1     CrashLoopBackOff   5          5m
```

**Cause:** Database migration failure or configuration error

**Solution:**

```bash
# Check pod logs for error details
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana --tail=200

# Common errors:
# Error 1: Database migration failed
# Solution: Restore database from backup and retry upgrade

# Error 2: Configuration error
# Solution: Verify ConfigMap and Secrets
kubectl get configmap grafana-config -n <namespace> -o yaml
kubectl get secret grafana-secret -n <namespace> -o yaml

# Error 3: Permission denied
# Solution: Verify PVC ownership
kubectl exec -n <namespace> deployment/grafana -- ls -la /var/lib/grafana/
# Should be owned by UID 472 (grafana user)
```

### Issue 2: Dashboards Missing After Upgrade

**Symptom:** Grafana UI shows no dashboards after upgrade

**Cause:** Database migration issue or PVC mounted incorrectly

**Solution:**

```bash
# Check database contents
kubectl exec -n <namespace> deployment/grafana -- sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM dashboard;"

# If count is 0, database is empty - restore from backup
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD-HHMMSS.db

# If count is correct, check PVC mount
kubectl get pvc -n <namespace>
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=grafana | grep -A 5 "Volumes:"
```

### Issue 3: Plugin Compatibility Errors

**Symptom:**
```
logger=plugin.loader t=2025-01-01T00:00:00Z level=error msg="Failed to load plugin" error="plugin is built with Grafana version X, but you are running version Y"
```

**Cause:** Plugin not compatible with new Grafana version

**Solution:**

```bash
# Update plugin to compatible version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins update <plugin-id>

# Or remove incompatible plugin
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins remove <plugin-id>

# Restart Grafana
kubectl rollout restart deployment/grafana -n <namespace>

# Find compatible plugin alternatives
# Visit: https://grafana.com/grafana/plugins/
```

### Issue 4: Database Migration Stuck

**Symptom:** Grafana pod stuck in "Running" state but not ready, logs show migration in progress for >10 minutes

**Cause:** Large database or complex migration

**Solution:**

```bash
# Check migration progress
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana -f | grep -i migration

# If stuck for >30 minutes, migration may have failed
# Option 1: Wait (some migrations can take 1+ hour for large databases)

# Option 2: Rollback and restore database
kubectl scale deployment grafana -n <namespace> --replicas=0
# Restore database from backup
# Rollback Helm release
helm rollback grafana -n <namespace>
```

### Issue 5: Datasource Queries Failing After Upgrade

**Symptom:** Dashboards load but panels show "Query error" or "No data"

**Cause:** Datasource query format changed in new Grafana version

**Solution:**

```bash
# Test datasource connectivity
GRAFANA_PASSWORD=$(kubectl get secret grafana-secret -n <namespace> -o jsonpath='{.data.admin-password}' | base64 -d)
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/datasources | jq '.[] | {id, name, type}'

# Test individual datasource
DS_ID=1  # Replace with datasource ID
curl -s -u admin:$GRAFANA_PASSWORD "http://localhost:3000/api/datasources/$DS_ID/health" | jq

# Review Grafana release notes for query format changes
# Update dashboard queries to new format

# For Prometheus queries, check:
# - PromQL syntax changes
# - Query resolution settings
# - Time range handling
```

### Issue 6: High Memory Usage After Upgrade

**Symptom:** Grafana pod using significantly more memory after upgrade

**Cause:** New Grafana version has higher resource requirements or memory leak

**Solution:**

```bash
# Monitor memory usage
kubectl top pod -n <namespace> -l app.kubernetes.io/name=grafana

# Check Grafana metrics
curl -s http://localhost:3000/metrics | grep grafana_build_info
curl -s http://localhost:3000/metrics | grep go_memstats

# Increase memory limits if needed
helm upgrade grafana charts/grafana \
  --namespace <namespace> \
  --set resources.limits.memory=2Gi \
  --set resources.requests.memory=512Mi \
  --reuse-values

# If memory leak suspected, check Grafana issue tracker:
# https://github.com/grafana/grafana/issues
```

### Issue 7: Alerting Rules Not Working After Upgrade

**Symptom:** Alert rules show "No Data" or not triggering

**Cause:** Unified alerting configuration issue or datasource query changes

**Solution:**

```bash
# Check unified alerting status
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/alertmanager/grafana/api/v2/status | jq

# Verify alert rules
curl -s -u admin:$GRAFANA_PASSWORD http://localhost:3000/api/v1/provisioning/alert-rules | jq

# Check alert evaluation logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana | grep -i alert

# Test alert rule query manually
# Navigate to Alerting > Alert Rules > Edit rule > Test
```

---

## Additional Resources

- [Grafana Upgrade Documentation](https://grafana.com/docs/grafana/latest/upgrade-guide/)
- [Grafana Release Notes](https://grafana.com/docs/grafana/latest/whatsnew/)
- [Grafana Breaking Changes](https://grafana.com/docs/grafana/latest/breaking-changes/)
- [Helm Upgrade Documentation](https://helm.sh/docs/helm/helm_upgrade/)
- [Grafana Community Forum](https://community.grafana.com/)

---

**Document Version:** 1.0.0
**Last Updated:** 2025-12-01
**Grafana Chart Version:** 0.3.0
