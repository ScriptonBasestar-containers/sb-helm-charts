# Jellyfin Upgrade Guide

## Overview

This guide provides comprehensive procedures for upgrading Jellyfin deployments. Jellyfin is a mature media server with stable releases, and this guide covers strategies for safe, reliable upgrades with minimal downtime.

### Upgrade Complexity

Jellyfin upgrades vary in complexity:

- **Patch Upgrades** (e.g., 10.10.1 → 10.10.2): Low risk, bug fixes only
- **Minor Upgrades** (e.g., 10.10.x → 10.11.x): Medium risk, new features, possible plugin compatibility issues
- **Major Upgrades** (e.g., 10.x → 11.x): High risk, breaking changes, FFmpeg updates, database migrations

### Upgrade Strategies

This guide covers three upgrade strategies:

1. **Rolling Upgrade** - Zero downtime, recommended for production (patch/minor versions)
2. **Blue-Green Deployment** - Parallel environments with cutover (major versions)
3. **Maintenance Window** - Full server restart (major versions with breaking changes)

### Critical Pre-Upgrade Steps

**ALWAYS perform these steps before ANY upgrade:**

1. ✅ **Backup all data** (config PVC, media files, configuration)
2. ✅ **Review release notes** for breaking changes
3. ✅ **Check plugin compatibility** (official and community plugins)
4. ✅ **Test upgrade in non-production environment**
5. ✅ **Plan rollback strategy**
6. ✅ **Schedule maintenance window** (if needed)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
3. [Strategy 1: Rolling Upgrade](#strategy-1-rolling-upgrade)
4. [Strategy 2: Blue-Green Deployment](#strategy-2-blue-green-deployment)
5. [Strategy 3: Maintenance Window](#strategy-3-maintenance-window)
6. [Database Migrations](#database-migrations)
7. [Version-Specific Notes](#version-specific-notes)
8. [Post-Upgrade Validation](#post-upgrade-validation)
9. [Rollback Procedures](#rollback-procedures)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Prerequisites

### Required Tools

```bash
# Kubernetes CLI
kubectl version --client

# Helm 3.x
helm version

# SQLite tools (for database verification)
sudo apt-get install sqlite3  # Debian/Ubuntu

# jq (for JSON parsing)
jq --version

# Optional: k9s (for monitoring)
k9s version
```

### Access Requirements

Ensure you have:

1. **Kubernetes Access**: `kubectl` access with appropriate RBAC permissions
2. **Helm Access**: Ability to upgrade Helm releases
3. **Storage Access**: Read access to config PVC for backup
4. **Media Access**: Access to media storage (NAS/NFS/PVC)

### Documentation

Keep these documents handy:

- [Jellyfin Release Notes](https://github.com/jellyfin/jellyfin/releases)
- [Jellyfin Backup Guide](jellyfin-backup-guide.md)
- [Helm Chart Values](../charts/jellyfin/values.yaml)

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

```bash
# Check current version
helm list -n $NAMESPACE | grep jellyfin

# Review Jellyfin release notes
# Visit: https://github.com/jellyfin/jellyfin/releases

# Check for breaking changes
# Look for: "BREAKING CHANGE", "Breaking", "Plugin Compatibility"
```

### 2. Backup All Components

**CRITICAL: Always backup before upgrading**

```bash
# Full backup using Makefile
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Manual backup steps
# 1. Backup config PVC (contains SQLite database)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  tar czf - /config > /backup/jellyfin/pre-upgrade-$(date +%Y%m%d)/config.tar.gz

# 2. Backup configuration
helm get values $RELEASE_NAME -n $NAMESPACE > /backup/jellyfin/pre-upgrade-$(date +%Y%m%d)/values.yaml
```

### 3. Verify Backup Integrity

```bash
# Verify config backup
tar tzf /backup/jellyfin/pre-upgrade-$(date +%Y%m%d)/config.tar.gz | head -20

# Verify SQLite database is in backup
tar tzf /backup/jellyfin/pre-upgrade-$(date +%Y%m%d)/config.tar.gz | grep library.db

# Save backup location
export BACKUP_TIMESTAMP=$(date +%Y%m%d)
export BACKUP_PATH="/backup/jellyfin/pre-upgrade-$BACKUP_TIMESTAMP"
echo "Backup location: $BACKUP_PATH"
```

### 4. Check Current State

```bash
# Check current deployment
kubectl get deployment,pod -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check current image version
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Check library count
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "SELECT COUNT(*) FROM MediaItems;"

# Check plugin status
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  ls -la /config/plugins/
```

### 5. Check Plugin Compatibility

**IMPORTANT:** Jellyfin plugins may break with new versions

```bash
# List installed plugins
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  cat /config/config/plugins.json | jq -r '.[] | "\(.Name) - \(.Version)"'

# Check plugin compatibility in release notes
# Visit: https://github.com/jellyfin/jellyfin/releases
# Search for plugin compatibility notes
```

### 6. Prepare Target Version

```bash
# Set target version
export TARGET_VERSION="10.11.0"  # Adjust to desired version

# Update Helm repository
helm repo update scripton-charts

# Check available chart versions
helm search repo scripton-charts/jellyfin --versions

# Download new chart values (if needed)
helm show values scripton-charts/jellyfin --version 0.3.0 > /tmp/jellyfin-new-values.yaml
```

### 7. Review Configuration Changes

```bash
# Compare old and new values
diff <(helm get values $RELEASE_NAME -n $NAMESPACE) /tmp/jellyfin-new-values.yaml

# Check for deprecated settings
# Review release notes for configuration changes
```

### 8. Makefile Target

```bash
# Run pre-upgrade check
make -f make/ops/jellyfin.mk jellyfin-pre-upgrade-check
```

---

## Strategy 1: Rolling Upgrade

**Best For:** Patch and minor version upgrades
**Downtime:** None (zero-downtime)
**Complexity:** Low
**Risk:** Low to Medium

### Overview

Rolling upgrade updates pods one at a time, ensuring service availability throughout the upgrade process.

**Note:** Jellyfin uses `Recreate` strategy by default due to SQLite database locking. For true rolling upgrades with zero downtime, consider using external PostgreSQL database.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Rolling Upgrade Process                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Initial State:                                                 │
│  ┌────────┐                                                     │
│  │ Pod v1 │  (Single pod - SQLite limitation)                  │
│  └────────┘                                                     │
│       ↓                                                         │
│  Step 1: Terminate Pod, Start New Pod                          │
│  ┌────────┐                                                     │
│  │Terminat│  ← Brief unavailability (5-30 seconds)             │
│  └────────┘                                                     │
│       ↓                                                         │
│  Step 2: New Pod Starting                                      │
│  ┌────────┐                                                     │
│  │ Pod v2 │  ← Service restored                                │
│  └────────┘                                                     │
│                                                                 │
│  Total downtime: 5-30 seconds (pod restart time)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.1 Pre-Upgrade Steps

```bash
# Set variables
export RELEASE_NAME="jellyfin"
export NAMESPACE="default"
export TARGET_VERSION="10.11.0"

# Pre-upgrade backup (REQUIRED)
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Verify backup completed successfully
ls -lh $BACKUP_PATH/
```

### 1.2 Upgrade Execution

```bash
# Option A: Upgrade using Helm (recommended)
helm upgrade $RELEASE_NAME scripton-charts/jellyfin \
  -n $NAMESPACE \
  --set image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout 10m

# Option B: Upgrade with custom values file
helm upgrade $RELEASE_NAME scripton-charts/jellyfin \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set image.tag=$TARGET_VERSION \
  --wait \
  --timeout 10m

# Monitor upgrade progress
kubectl rollout status deployment/${RELEASE_NAME} -n $NAMESPACE
```

### 1.3 Monitor Upgrade

```bash
# Watch pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -w

# Check pod events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep $RELEASE_NAME

# Check logs for errors
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --tail=50
```

### 1.4 Post-Upgrade Validation

```bash
# Verify pod is running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check image version
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 8096:8096 &
curl -I http://localhost:8096

# Verify library count (should match pre-upgrade)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "SELECT COUNT(*) FROM MediaItems;"

# Check plugin status
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  ls -la /config/plugins/

# Login to web UI and verify:
# - Libraries are visible
# - Media playback works
# - Plugins are functional
```

### 1.5 Makefile Targets

```bash
# Rolling upgrade
make -f make/ops/jellyfin.mk jellyfin-rolling-upgrade VERSION=$TARGET_VERSION

# Post-upgrade validation
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check
```

---

## Strategy 2: Blue-Green Deployment

**Best For:** Major version upgrades with significant changes
**Downtime:** 10-30 minutes (cutover)
**Complexity:** Medium
**Risk:** Low (easy rollback)

### Overview

Blue-Green deployment creates a parallel environment with the new version, validates it, then switches traffic.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Blue-Green Deployment Process                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Step 1: Blue (Current) Environment Running                    │
│  ┌──────────────────────────────────────┐                      │
│  │  Blue Environment (v10.10.3)         │                      │
│  │  ┌────────┐                          │  ← Active traffic    │
│  │  │ Pod v1 │                          │                      │
│  │  └────────┘                          │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  Step 2: Deploy Green (New) Environment                        │
│  ┌──────────────────────────────────────┐                      │
│  │  Blue Environment (v10.10.3)         │  ← Active traffic    │
│  │  ┌────────┐                          │                      │
│  │  │ Pod v1 │                          │                      │
│  │  └────────┘                          │                      │
│  └──────────────────────────────────────┘                      │
│  ┌──────────────────────────────────────┐                      │
│  │  Green Environment (v10.11.0)        │  ← Testing only      │
│  │  ┌────────┐                          │                      │
│  │  │ Pod v2 │                          │                      │
│  │  └────────┘                          │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  Step 3: Validate Green, Switch Traffic                        │
│  ┌──────────────────────────────────────┐                      │
│  │  Blue Environment (v10.10.3)         │  ← Standby          │
│  │  ┌────────┐                          │                      │
│  │  │ Pod v1 │                          │                      │
│  │  └────────┘                          │                      │
│  └──────────────────────────────────────┘                      │
│  ┌──────────────────────────────────────┐                      │
│  │  Green Environment (v10.11.0)        │  ← Active traffic    │
│  │  ┌────────┐                          │                      │
│  │  │ Pod v2 │                          │                      │
│  │  └────────┘                          │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 Deploy Green Environment

```bash
# Set variables
export BLUE_RELEASE="jellyfin"
export GREEN_RELEASE="jellyfin-green"
export NAMESPACE="default"
export TARGET_VERSION="10.11.0"

# Pre-upgrade backup (REQUIRED)
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Deploy green environment
helm install $GREEN_RELEASE scripton-charts/jellyfin \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set image.tag=$TARGET_VERSION \
  --set nameOverride="jellyfin-green" \
  --set fullnameOverride="jellyfin-green" \
  --wait \
  --timeout 10m
```

### 2.2 Validate Green Environment

```bash
# Check green pods
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$GREEN_RELEASE

# Port-forward to green service
kubectl port-forward -n $NAMESPACE svc/jellyfin-green 8097:8096 &

# Test green environment
curl -I http://localhost:8097
# Login to http://localhost:8097 and verify functionality

# Verify library count
kubectl exec -n $NAMESPACE ${GREEN_RELEASE}-0 -- \
  sqlite3 /config/data/library.db "SELECT COUNT(*) FROM MediaItems;"

# Check plugin compatibility
kubectl exec -n $NAMESPACE ${GREEN_RELEASE}-0 -- \
  ls -la /config/plugins/
```

### 2.3 Switch Traffic (Cutover)

```bash
# Option A: Update Ingress to point to green service
kubectl patch ingress jellyfin -n $NAMESPACE --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"jellyfin-green"}]'

# Option B: Rename services (requires brief downtime)
kubectl get svc jellyfin -n $NAMESPACE -o yaml > /tmp/jellyfin-blue-svc.yaml
kubectl get svc jellyfin-green -n $NAMESPACE -o yaml > /tmp/jellyfin-green-svc.yaml

# Swap service names
kubectl delete svc jellyfin jellyfin-green -n $NAMESPACE
sed 's/name: jellyfin$/name: jellyfin-old/' /tmp/jellyfin-blue-svc.yaml | kubectl apply -f -
sed 's/name: jellyfin-green$/name: jellyfin/' /tmp/jellyfin-green-svc.yaml | kubectl apply -f -

# Verify traffic is now on green
kubectl get svc -n $NAMESPACE
```

### 2.4 Validate Production Traffic

```bash
# Monitor green environment with production traffic
kubectl logs -n $NAMESPACE ${GREEN_RELEASE}-0 --tail=100

# Check for errors
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep $GREEN_RELEASE

# Monitor for 15-30 minutes before cleanup
```

### 2.5 Cleanup Blue Environment

```bash
# After validating green environment (wait at least 24 hours)
helm uninstall $BLUE_RELEASE -n $NAMESPACE

# Or keep blue as standby for quick rollback
# Delete after extended validation period (1 week)
```

### 2.6 Makefile Targets

```bash
# Blue-green deployment
make -f make/ops/jellyfin.mk jellyfin-blue-green-deploy VERSION=$TARGET_VERSION

# Switch traffic
make -f make/ops/jellyfin.mk jellyfin-blue-green-cutover

# Cleanup blue
make -f make/ops/jellyfin.mk jellyfin-blue-green-cleanup
```

---

## Strategy 3: Maintenance Window

**Best For:** Major version upgrades with breaking changes, FFmpeg updates
**Downtime:** 30 minutes - 2 hours
**Complexity:** Low
**Risk:** Medium to High

### Overview

Maintenance window upgrade stops all services, performs upgrade, then restarts. Simplest but requires downtime.

### 3.1 Schedule Maintenance Window

```bash
# Notify users of maintenance window
# Example: "Jellyfin will be unavailable on 2025-01-27 02:00-04:00 UTC for upgrade"

# Set variables
export RELEASE_NAME="jellyfin"
export NAMESPACE="default"
export TARGET_VERSION="11.0.0"
export MAINTENANCE_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

### 3.2 Pre-Maintenance Backup

```bash
# CRITICAL: Full backup before maintenance
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Verify backup
ls -lh $BACKUP_PATH/
```

### 3.3 Stop Services

```bash
# Scale down to 0 replicas
kubectl scale deployment/${RELEASE_NAME} -n $NAMESPACE --replicas=0

# Verify pod is terminated
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Put up maintenance page (if using Ingress)
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: maintenance-page
  namespace: $NAMESPACE
data:
  index.html: |
    <html>
    <body style="font-family: Arial; text-align: center; padding-top: 100px;">
      <h1>Maintenance in Progress</h1>
      <p>Jellyfin is currently being upgraded. Expected completion: 04:00 UTC</p>
    </body>
    </html>
EOF
```

### 3.4 Perform Database Migrations (If Required)

```bash
# Check for required migrations (review release notes)
# Example: Jellyfin 10.x → 11.x may require database schema updates

# Connect to SQLite database
kubectl run -it --rm sqlite-client --image=alpine:latest --restart=Never -n $NAMESPACE -- \
  sh -c "apk add sqlite && sqlite3 /config/data/library.db"

# Check database schema version
.schema

# Run migration SQL (if needed, follow release notes instructions)

# Exit SQLite
.quit
```

### 3.5 Upgrade Helm Release

```bash
# Upgrade with new version
helm upgrade $RELEASE_NAME scripton-charts/jellyfin \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set image.tag=$TARGET_VERSION \
  --wait \
  --timeout 10m

# Verify deployment
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
```

### 3.6 Restore Services

```bash
# Scale back up (if scaled down)
kubectl scale deployment/${RELEASE_NAME} -n $NAMESPACE --replicas=1

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=600s

# Remove maintenance page
kubectl delete configmap maintenance-page -n $NAMESPACE
```

### 3.7 Post-Maintenance Validation

```bash
# Verify pod running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check logs for errors
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --tail=100

# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 8096:8096 &
curl -I http://localhost:8096

# Verify library count
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "SELECT COUNT(*) FROM MediaItems;"

# Notify users maintenance is complete
```

### 3.8 Makefile Targets

```bash
# Maintenance window upgrade
make -f make/ops/jellyfin.mk jellyfin-maintenance-upgrade VERSION=$TARGET_VERSION

# Post-maintenance check
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check
```

---

## Database Migrations

### 4.1 Understanding Jellyfin Database

Jellyfin uses SQLite database (`library.db`) for media metadata. Most upgrades handle migrations automatically.

```bash
# Check database version
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "PRAGMA user_version;"
```

### 4.2 Automatic Migrations

Most Jellyfin upgrades perform automatic database migrations on first startup:

```bash
# Monitor logs during first startup after upgrade
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --follow

# Look for migration messages:
# [INF] Migrating database from version X to Y
```

### 4.3 Manual Migration (If Required)

Some major version upgrades require manual intervention:

```bash
# Example: Jellyfin 10.x → 11.x migration
# (Check release notes for specific instructions)

# 1. Backup database (REQUIRED)
make -f make/ops/jellyfin.mk jellyfin-backup-config

# 2. Run migration script (if provided)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  /usr/lib/jellyfin/bin/jellyfin migrate

# 3. Verify migration
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "PRAGMA integrity_check;"
```

### 4.4 Migration Troubleshooting

```bash
# Check for database corruption
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "PRAGMA integrity_check;"

# Rollback migration (restore from backup)
make -f make/ops/jellyfin.mk jellyfin-restore-config BACKUP_FILE=/backup/jellyfin/pre-upgrade-20250127/config.tar.gz
```

---

## Version-Specific Notes

### 5.1 Jellyfin v10.10.x → v10.11.x

**Type:** Minor upgrade
**Risk:** Low
**Recommended Strategy:** Rolling Upgrade

**Changes:**
- New playback features
- Performance improvements
- Bug fixes

**Migration Notes:**
- No manual migration required
- Automatic database schema updates
- Plugin compatibility: Check individual plugins

**Upgrade Command:**
```bash
helm upgrade jellyfin scripton-charts/jellyfin \
  --set image.tag=10.11.0 \
  --reuse-values
```

### 5.2 Jellyfin v10.x → v11.x (Hypothetical Major Upgrade)

**Type:** Major upgrade
**Risk:** High
**Recommended Strategy:** Blue-Green Deployment or Maintenance Window

**Potential Changes:**
- Breaking API changes
- FFmpeg version update (may break hardware acceleration)
- Database schema overhaul
- Plugin compatibility breaks
- Configuration format changes

**Migration Notes:**
- ⚠️ Review release notes thoroughly
- ⚠️ Test in staging environment first
- ⚠️ Expect plugin updates required
- ⚠️ Plan for extended downtime (2-4 hours)

**Upgrade Steps:**
```bash
# 1. Full backup
make -f make/ops/jellyfin.mk jellyfin-full-backup

# 2. Review migration guide
# Visit: https://jellyfin.org/docs/general/administration/migration/

# 3. Test in staging environment
# (Deploy to test namespace, validate)

# 4. Schedule maintenance window
# (Notify users, plan 4-hour window)

# 5. Execute upgrade
make -f make/ops/jellyfin.mk jellyfin-maintenance-upgrade VERSION=11.0.0
```

### 5.3 FFmpeg Version Changes

Jellyfin relies heavily on FFmpeg for transcoding. FFmpeg version changes can break hardware acceleration:

```bash
# Check current FFmpeg version
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- ffmpeg -version

# After upgrade, verify transcoding works
# (Test playback in web UI with transcoding enabled)

# If hardware acceleration breaks, check logs
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i vaapi
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i nvenc
```

---

## Post-Upgrade Validation

### 6.1 Automated Validation Script

```bash
#!/bin/bash
# jellyfin-post-upgrade-check.sh

set -euo pipefail

echo "=== Jellyfin Post-Upgrade Validation ==="

# 1. Check pod status
echo "[1/8] Checking pod status..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
if [ $? -ne 0 ]; then
  echo "❌ Failed to get pods"
  exit 1
fi
echo "✅ Pod status check passed"

# 2. Check image version
echo "[2/8] Checking image version..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{.items[0].spec.containers[0].image}'
echo ""
echo "✅ Image version check passed"

# 3. Test web interface
echo "[3/8] Testing web interface..."
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 8096:8096 &
PF_PID=$!
sleep 5
curl -f -I http://localhost:8096 > /dev/null
if [ $? -ne 0 ]; then
  echo "❌ Web interface check failed"
  kill $PF_PID
  exit 1
fi
kill $PF_PID
echo "✅ Web interface check passed"

# 4. Verify library count
echo "[4/8] Verifying library count..."
LIBRARY_COUNT=$(kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "SELECT COUNT(*) FROM MediaItems;" 2>/dev/null || echo "0")
echo "Library count: $LIBRARY_COUNT"
echo "✅ Library count check passed"

# 5. Check database integrity
echo "[5/8] Checking database integrity..."
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  sqlite3 /config/data/library.db "PRAGMA integrity_check;" | grep -q "ok"
if [ $? -ne 0 ]; then
  echo "⚠️  Warning: Database integrity check failed"
else
  echo "✅ Database integrity check passed"
fi

# 6. Check plugins
echo "[6/8] Checking plugins..."
PLUGIN_COUNT=$(kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  ls /config/plugins/*.dll 2>/dev/null | wc -l || echo "0")
echo "Plugin count: $PLUGIN_COUNT"
echo "✅ Plugin check passed"

# 7. Check for errors in logs
echo "[7/8] Checking logs for errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --tail=100 | grep -i error | wc -l)
if [ $ERROR_COUNT -gt 5 ]; then
  echo "⚠️  Warning: $ERROR_COUNT errors found in logs"
else
  echo "✅ Log error check passed ($ERROR_COUNT errors)"
fi

# 8. Summary
echo "[8/8] Post-upgrade validation summary"
echo "======================================"
echo "✅ All critical checks passed"
echo "⚠️  Review warnings above (if any)"
echo "======================================"
```

### 6.2 Manual Validation Checklist

- [ ] Pod is running and ready
- [ ] Image version matches target version
- [ ] Web interface loads successfully
- [ ] User login works
- [ ] Library scan works
- [ ] Media playback works (direct play)
- [ ] Media playback works (transcoding)
- [ ] Hardware acceleration works (if enabled)
- [ ] Plugins are functional
- [ ] Mobile app connectivity works
- [ ] DLNA works (if enabled)
- [ ] No critical errors in logs

### 6.3 Makefile Target

```bash
# Run post-upgrade validation
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check
```

---

## Rollback Procedures

### 7.1 When to Rollback

Consider rollback if:

- ❌ Critical functionality is broken
- ❌ Hardware acceleration fails
- ❌ Plugins are incompatible
- ❌ Database corruption detected
- ❌ Severe performance degradation
- ❌ Media playback fails

### 7.2 Helm Rollback (Simple)

**Use Case:** Upgrade failed or introduced issues, no database migrations

```bash
# List Helm release history
helm history $RELEASE_NAME -n $NAMESPACE

# Rollback to previous revision
helm rollback $RELEASE_NAME -n $NAMESPACE

# Rollback to specific revision
helm rollback $RELEASE_NAME 5 -n $NAMESPACE

# Verify rollback
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
```

### 7.3 Full Rollback (Database + Application)

**Use Case:** Database migrations were applied, need full restoration

```bash
# 1. Stop application
kubectl scale deployment/${RELEASE_NAME} -n $NAMESPACE --replicas=0

# 2. Restore config PVC from pre-upgrade backup
kubectl delete pvc ${RELEASE_NAME}-config -n $NAMESPACE
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-config
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${RELEASE_NAME}-config -n $NAMESPACE --timeout=300s

# Restore config data
cat $BACKUP_PATH/config.tar.gz | \
  kubectl exec -i -n $NAMESPACE jellyfin-restore-helper -- \
  tar xzf - -C /

# 3. Rollback Helm release
helm rollback $RELEASE_NAME -n $NAMESPACE

# 4. Restart application
kubectl scale deployment/${RELEASE_NAME} -n $NAMESPACE --replicas=1

# 5. Verify rollback
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check
```

### 7.4 Blue-Green Rollback

**Use Case:** Blue-Green deployment, need to switch back to blue

```bash
# Switch traffic back to blue service
kubectl patch ingress jellyfin -n $NAMESPACE --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"jellyfin"}]'

# Or rename services back
kubectl delete svc jellyfin jellyfin-green -n $NAMESPACE
kubectl apply -f /tmp/jellyfin-blue-svc.yaml

# Delete green environment
helm uninstall $GREEN_RELEASE -n $NAMESPACE
```

### 7.5 Makefile Target

```bash
# Rollback to previous version
make -f make/ops/jellyfin.mk jellyfin-upgrade-rollback
```

---

## Troubleshooting

### 8.1 Upgrade Failures

#### Issue: Pod stuck in `ImagePullBackOff`

**Cause:** Invalid image tag or registry authentication failure

**Solution:**
```bash
# Check image pull errors
kubectl describe pod ${RELEASE_NAME}-0 -n $NAMESPACE

# Verify image exists
docker pull jellyfin/jellyfin:$TARGET_VERSION

# Check image pull secrets
kubectl get secret -n $NAMESPACE
```

#### Issue: Pod crashes with `CrashLoopBackOff`

**Cause:** Database migration failure, configuration error, FFmpeg issue

**Solution:**
```bash
# Check pod logs
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 --previous

# Check for database errors
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i database

# Check for FFmpeg errors
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i ffmpeg
```

#### Issue: Helm upgrade timeout

**Cause:** Slow database migration, pod startup issues

**Solution:**
```bash
# Increase timeout
helm upgrade $RELEASE_NAME scripton-charts/jellyfin \
  --timeout 30m \
  --wait

# Or upgrade without waiting
helm upgrade $RELEASE_NAME scripton-charts/jellyfin \
  --no-wait
```

### 8.2 Plugin Issues

#### Issue: Plugins don't load after upgrade

**Cause:** Plugin incompatibility with new Jellyfin version

**Solution:**
```bash
# Check plugin compatibility
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  cat /config/config/plugins.json

# Update plugins via web UI
# Settings → Plugins → Catalog → Update

# Or manually update plugins
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- \
  rm -rf /config/plugins/*
# Reinstall plugins via web UI
```

### 8.3 Hardware Acceleration Issues

#### Issue: Hardware acceleration stops working after upgrade

**Cause:** FFmpeg version change, driver incompatibility

**Solution:**
```bash
# Check FFmpeg version
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- ffmpeg -version

# Check device access
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-0 -- ls -la /dev/dri

# Check Intel QSV
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i vaapi

# Check NVIDIA NVENC
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-0 | grep -i nvenc

# Disable hardware acceleration temporarily
# Settings → Playback → Transcoding → Hardware acceleration: None
```

### 8.4 Makefile Targets

```bash
# Troubleshoot upgrade issues
make -f make/ops/jellyfin.mk jellyfin-troubleshoot-upgrade

# Check upgrade logs
make -f make/ops/jellyfin.mk jellyfin-upgrade-logs
```

---

## Best Practices

### 9.1 General Upgrade Best Practices

1. **Always Backup First** - No exceptions. Full backup before any upgrade.
2. **Test in Staging** - Deploy to test environment first, validate thoroughly.
3. **Read Release Notes** - Understand breaking changes and migration requirements.
4. **Check Plugin Compatibility** - Verify plugins work with new version.
5. **Plan Rollback** - Have rollback procedure ready before starting upgrade.
6. **Upgrade During Low-Traffic** - Schedule upgrades during off-peak hours.
7. **Incremental Upgrades** - Avoid skipping multiple major versions.

### 9.2 Backup Before Upgrade

```bash
# Always run full backup before upgrade
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Verify backup completed successfully
ls -lh $BACKUP_PATH/

# Test backup restoration (in test namespace)
make -f make/ops/jellyfin.mk jellyfin-test-restore
```

### 9.3 Staging Environment Testing

```bash
# Deploy to staging namespace
kubectl create namespace jellyfin-staging

# Restore production data to staging
make -f make/ops/jellyfin.mk jellyfin-restore-to-staging \
  BACKUP_PATH=$BACKUP_PATH \
  NAMESPACE=jellyfin-staging

# Upgrade staging environment
helm upgrade jellyfin-staging scripton-charts/jellyfin \
  -n jellyfin-staging \
  --set image.tag=$TARGET_VERSION

# Validate staging for 24-48 hours before production upgrade
```

### 9.4 Communication Plan

1. **Pre-Announcement** (1 week before): Notify users of upcoming maintenance
2. **Reminder** (24 hours before): Send reminder with exact maintenance window
3. **Start Notification**: Notify users when maintenance starts
4. **Completion Notification**: Notify users when upgrade is complete
5. **Issue Reporting**: Provide channel for users to report issues

### 9.5 Rollback Decision Matrix

| Severity | Impact | Action | Timeframe |
|----------|--------|--------|-----------|
| Critical | Playback broken, data loss | Immediate rollback | < 15 minutes |
| High | Hardware acceleration broken | Rollback if no fix within 1 hour | < 1 hour |
| Medium | Plugin issues, minor bugs | Fix forward if possible | 2-4 hours |
| Low | Cosmetic issues, warnings | Fix in next patch release | No rollback |

---

## Summary

### Key Takeaways

1. **Three Upgrade Strategies**: Rolling (minimal downtime), Blue-Green (low-risk), Maintenance Window (simple)
2. **Always Backup First**: Full backup before any upgrade, no exceptions
3. **Test First**: Validate upgrades in staging before production
4. **Check Plugins**: Verify plugin compatibility before upgrading
5. **Plan Rollback**: Have rollback procedure ready and tested

### Quick Reference

```bash
# Pre-upgrade checklist
make -f make/ops/jellyfin.mk jellyfin-pre-upgrade-check

# Full backup
make -f make/ops/jellyfin.mk jellyfin-full-backup

# Rolling upgrade (recommended for minor versions)
make -f make/ops/jellyfin.mk jellyfin-rolling-upgrade VERSION=10.11.0

# Blue-green upgrade (recommended for major versions)
make -f make/ops/jellyfin.mk jellyfin-blue-green-deploy VERSION=11.0.0

# Post-upgrade validation
make -f make/ops/jellyfin.mk jellyfin-post-upgrade-check

# Rollback (if needed)
make -f make/ops/jellyfin.mk jellyfin-upgrade-rollback
```

### Related Documentation

- [Jellyfin Backup Guide](jellyfin-backup-guide.md)
- [Jellyfin README](../charts/jellyfin/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)
- [Jellyfin Official Docs](https://jellyfin.org/docs/)

---

**Last Updated:** 2025-01-27
**Version:** 1.0.0
