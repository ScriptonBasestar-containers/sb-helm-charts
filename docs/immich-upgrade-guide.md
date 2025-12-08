# Immich Upgrade Guide

## Overview

This guide provides comprehensive procedures for upgrading Immich deployments. Immich is under active development with frequent releases, and this guide covers strategies for safe, reliable upgrades with minimal downtime.

### Upgrade Complexity

Immich upgrades vary in complexity:

- **Patch Upgrades** (e.g., 1.119.0 → 1.119.1): Low risk, bug fixes only
- **Minor Upgrades** (e.g., 1.119.0 → 1.120.0): Medium risk, new features, possible database migrations
- **Major Upgrades** (e.g., 1.x → 2.x): High risk, breaking changes, significant database migrations

### Upgrade Strategies

This guide covers three upgrade strategies:

1. **Rolling Upgrade** - Zero downtime, recommended for production (patch/minor versions)
2. **Blue-Green Deployment** - Parallel environments with cutover (major versions)
3. **Maintenance Window** - Full cluster restart (major versions with significant changes)

### Critical Pre-Upgrade Steps

**ALWAYS perform these steps before ANY upgrade:**

1. ✅ **Backup all data** (database, library PVC, configuration)
2. ✅ **Review release notes** for breaking changes
3. ✅ **Test upgrade in non-production environment**
4. ✅ **Plan rollback strategy**
5. ✅ **Schedule maintenance window** (if needed)

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

# PostgreSQL client (for database migrations)
psql --version

# jq (for JSON parsing)
jq --version

# Optional: k9s (for monitoring)
k9s version
```

### Access Requirements

Ensure you have:

1. **Kubernetes Access**: `kubectl` access with appropriate RBAC permissions
2. **Helm Access**: Ability to upgrade Helm releases
3. **Database Access**: PostgreSQL credentials with migration privileges
4. **Backup Access**: Ability to create and restore backups

### Documentation

Keep these documents handy:

- [Immich Release Notes](https://github.com/immich-app/immich/releases)
- [Immich Backup Guide](immich-backup-guide.md)
- [Helm Chart Values](../charts/immich/values.yaml)

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

```bash
# Check current version
helm list -n $NAMESPACE | grep immich

# Review Immich release notes
# Visit: https://github.com/immich-app/immich/releases

# Check for breaking changes
# Look for: "BREAKING CHANGE", "Migration Required", "Action Required"
```

### 2. Backup All Components

**CRITICAL: Always backup before upgrading**

```bash
# Full backup using Makefile
make -f make/ops/immich.mk immich-full-backup

# Manual backup steps
# 1. Backup PostgreSQL database
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB \
  -Fc -f - > /backup/immich/pre-upgrade-$(date +%Y%m%d)/immich-db.dump

# 2. Backup library PVC
make -f make/ops/immich.mk immich-backup-library-restic

# 3. Backup configuration
helm get values $RELEASE_NAME -n $NAMESPACE > /backup/immich/pre-upgrade-$(date +%Y%m%d)/values.yaml
```

### 3. Verify Backup Integrity

```bash
# Verify database backup
pg_restore --list /backup/immich/pre-upgrade-$(date +%Y%m%d)/immich-db.dump | head -20

# Verify library backup
restic snapshots

# Save backup location
export BACKUP_TIMESTAMP=$(date +%Y%m%d)
export BACKUP_PATH="/backup/immich/pre-upgrade-$BACKUP_TIMESTAMP"
echo "Backup location: $BACKUP_PATH"
```

### 4. Check Current State

```bash
# Check current deployment
kubectl get deployment,statefulset,pod -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check current image versions
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Check database connectivity
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();"

# Check current photo count
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM assets;"
```

### 5. Prepare Target Version

```bash
# Set target version
export TARGET_VERSION="v1.120.0"  # Adjust to desired version

# Update Helm repository
helm repo update scripton-charts

# Check available chart versions
helm search repo scripton-charts/immich --versions

# Download new chart values (if needed)
helm show values scripton-charts/immich --version 0.3.0 > /tmp/immich-new-values.yaml
```

### 6. Review Configuration Changes

```bash
# Compare old and new values
diff <(helm get values $RELEASE_NAME -n $NAMESPACE) /tmp/immich-new-values.yaml

# Check for deprecated settings
# Review release notes for configuration changes
```

### 7. Makefile Target

```bash
# Run pre-upgrade check
make -f make/ops/immich.mk immich-pre-upgrade-check
```

---

## Strategy 1: Rolling Upgrade

**Best For:** Patch and minor version upgrades
**Downtime:** None (zero-downtime)
**Complexity:** Low
**Risk:** Low to Medium

### Overview

Rolling upgrade updates pods one at a time, ensuring service availability throughout the upgrade process.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Rolling Upgrade Process                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Initial State:                                                 │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │ Pod v1 │  │ Pod v1 │  │ Pod v1 │                           │
│  └────────┘  └────────┘  └────────┘                           │
│       ↓                                                         │
│  Step 1: Terminate Pod 1, Start Pod v2                         │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │ Pod v2 │  │ Pod v1 │  │ Pod v1 │  ← Service still available│
│  └────────┘  └────────┘  └────────┘                           │
│       ↓                                                         │
│  Step 2: Terminate Pod 2, Start Pod v2                         │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │ Pod v2 │  │ Pod v2 │  │ Pod v1 │  ← Service still available│
│  └────────┘  └────────┘  └────────┘                           │
│       ↓                                                         │
│  Step 3: Terminate Pod 3, Start Pod v2                         │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │ Pod v2 │  │ Pod v2 │  │ Pod v2 │  ← Upgrade complete       │
│  └────────┘  └────────┘  └────────┘                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.1 Pre-Upgrade Steps

```bash
# Set variables
export RELEASE_NAME="immich"
export NAMESPACE="default"
export TARGET_VERSION="v1.120.0"

# Pre-upgrade backup (REQUIRED)
make -f make/ops/immich.mk immich-full-backup

# Verify backup completed successfully
ls -lh $BACKUP_PATH/
```

### 1.2 Upgrade Execution

```bash
# Option A: Upgrade using Helm (recommended)
helm upgrade $RELEASE_NAME scripton-charts/immich \
  -n $NAMESPACE \
  --set immich.server.image.tag=$TARGET_VERSION \
  --set immich.machineLearning.image.tag=$TARGET_VERSION \
  --reuse-values \
  --wait \
  --timeout 10m

# Option B: Upgrade with custom values file
helm upgrade $RELEASE_NAME scripton-charts/immich \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set immich.server.image.tag=$TARGET_VERSION \
  --set immich.machineLearning.image.tag=$TARGET_VERSION \
  --wait \
  --timeout 10m

# Monitor upgrade progress
kubectl rollout status deployment/${RELEASE_NAME}-server -n $NAMESPACE
kubectl rollout status statefulset/${RELEASE_NAME}-machine-learning -n $NAMESPACE
```

### 1.3 Monitor Upgrade

```bash
# Watch pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -w

# Check pod events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep $RELEASE_NAME

# Check logs for errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --tail=50 --all-containers
```

### 1.4 Post-Upgrade Validation

```bash
# Verify all pods are running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check image versions
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Test database migrations (if any)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt"

# Verify photo count (should match pre-upgrade)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM assets;"

# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 2283:2283 &
curl -I http://localhost:2283
# Login to web UI and verify functionality
```

### 1.5 Makefile Targets

```bash
# Rolling upgrade
make -f make/ops/immich.mk immich-rolling-upgrade VERSION=$TARGET_VERSION

# Post-upgrade validation
make -f make/ops/immich.mk immich-post-upgrade-check
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
│  │  Blue Environment (v1.119.0)         │                      │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │                      │
│  │  │ Pod v1 │  │ Pod v1 │  │ Pod v1 │ │  ← Active traffic    │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  Step 2: Deploy Green (New) Environment                        │
│  ┌──────────────────────────────────────┐                      │
│  │  Blue Environment (v1.119.0)         │                      │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │  ← Active traffic    │
│  │  │ Pod v1 │  │ Pod v1 │  │ Pod v1 │ │                      │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│  ┌──────────────────────────────────────┐                      │
│  │  Green Environment (v1.120.0)        │                      │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │  ← Testing only      │
│  │  │ Pod v2 │  │ Pod v2 │  │ Pod v2 │ │                      │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  Step 3: Validate Green, Switch Traffic                        │
│  ┌──────────────────────────────────────┐                      │
│  │  Blue Environment (v1.119.0)         │  ← Standby          │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │                      │
│  │  │ Pod v1 │  │ Pod v1 │  │ Pod v1 │ │                      │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│  ┌──────────────────────────────────────┐                      │
│  │  Green Environment (v1.120.0)        │  ← Active traffic    │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │                      │
│  │  │ Pod v2 │  │ Pod v2 │  │ Pod v2 │ │                      │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  Step 4: Cleanup Blue Environment (after validation)           │
│  ┌──────────────────────────────────────┐                      │
│  │  Green Environment (v1.120.0)        │  ← Active traffic    │
│  │  ┌────────┐  ┌────────┐  ┌────────┐ │                      │
│  │  │ Pod v2 │  │ Pod v2 │  │ Pod v2 │ │                      │
│  │  └────────┘  └────────┘  └────────┘ │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 Deploy Green Environment

```bash
# Set variables
export BLUE_RELEASE="immich"
export GREEN_RELEASE="immich-green"
export NAMESPACE="default"
export TARGET_VERSION="v2.0.0"

# Pre-upgrade backup (REQUIRED)
make -f make/ops/immich.mk immich-full-backup

# Deploy green environment
helm install $GREEN_RELEASE scripton-charts/immich \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set immich.server.image.tag=$TARGET_VERSION \
  --set immich.machineLearning.image.tag=$TARGET_VERSION \
  --set nameOverride="immich-green" \
  --set fullnameOverride="immich-green" \
  --wait \
  --timeout 10m
```

### 2.2 Validate Green Environment

```bash
# Check green pods
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$GREEN_RELEASE

# Port-forward to green service
kubectl port-forward -n $NAMESPACE svc/immich-green 2284:2283 &

# Test green environment
curl -I http://localhost:2284
# Login to http://localhost:2284 and verify functionality

# Check database migrations (green should have new schema)
kubectl exec -n $NAMESPACE ${GREEN_RELEASE}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt"

# Verify photo count
kubectl exec -n $NAMESPACE ${GREEN_RELEASE}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM assets;"
```

### 2.3 Switch Traffic (Cutover)

```bash
# Option A: Update Ingress to point to green service
kubectl patch ingress immich -n $NAMESPACE --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"immich-green"}]'

# Option B: Rename services (requires brief downtime)
kubectl get svc immich -n $NAMESPACE -o yaml > /tmp/immich-blue-svc.yaml
kubectl get svc immich-green -n $NAMESPACE -o yaml > /tmp/immich-green-svc.yaml

# Swap service names
kubectl delete svc immich immich-green -n $NAMESPACE
sed 's/name: immich$/name: immich-old/' /tmp/immich-blue-svc.yaml | kubectl apply -f -
sed 's/name: immich-green$/name: immich/' /tmp/immich-green-svc.yaml | kubectl apply -f -

# Verify traffic is now on green
kubectl get svc -n $NAMESPACE
```

### 2.4 Validate Production Traffic

```bash
# Monitor green environment with production traffic
kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$GREEN_RELEASE --tail=100 --all-containers

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
make -f make/ops/immich.mk immich-blue-green-deploy VERSION=$TARGET_VERSION

# Switch traffic
make -f make/ops/immich.mk immich-blue-green-cutover

# Cleanup blue
make -f make/ops/immich.mk immich-blue-green-cleanup
```

---

## Strategy 3: Maintenance Window

**Best For:** Major version upgrades with breaking changes, database schema migrations
**Downtime:** 30 minutes - 2 hours
**Complexity:** Low
**Risk:** Medium to High

### Overview

Maintenance window upgrade stops all services, performs upgrade, then restarts. Simplest but requires downtime.

### 3.1 Schedule Maintenance Window

```bash
# Notify users of maintenance window
# Example: "Immich will be unavailable on 2025-01-27 02:00-04:00 UTC for upgrade"

# Set variables
export RELEASE_NAME="immich"
export NAMESPACE="default"
export TARGET_VERSION="v2.0.0"
export MAINTENANCE_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

### 3.2 Pre-Maintenance Backup

```bash
# CRITICAL: Full backup before maintenance
make -f make/ops/immich.mk immich-full-backup

# Verify backup
ls -lh $BACKUP_PATH/
```

### 3.3 Stop Services

```bash
# Scale down to 0 replicas
kubectl scale deployment/${RELEASE_NAME}-server -n $NAMESPACE --replicas=0
kubectl scale statefulset/${RELEASE_NAME}-machine-learning -n $NAMESPACE --replicas=0

# Verify all pods are terminated
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
      <p>Immich is currently being upgraded. Expected completion: 04:00 UTC</p>
    </body>
    </html>
EOF
```

### 3.4 Perform Database Migrations (If Required)

```bash
# Check for required migrations (review release notes)
# Example: Immich v2.0.0 requires manual migration

# Connect to database
kubectl run -it --rm psql-client --image=postgres:16 --restart=Never -n $NAMESPACE -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB

# Run migration SQL (example)
-- Check current schema version
SELECT * FROM migrations;

-- Run migration (if needed)
-- Follow instructions from Immich release notes

# Exit psql
\q
```

### 3.5 Upgrade Helm Release

```bash
# Upgrade with new version
helm upgrade $RELEASE_NAME scripton-charts/immich \
  -n $NAMESPACE \
  -f values-production.yaml \
  --set immich.server.image.tag=$TARGET_VERSION \
  --set immich.machineLearning.image.tag=$TARGET_VERSION \
  --wait \
  --timeout 10m

# Verify deployment
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
```

### 3.6 Restore Services

```bash
# Scale back up (if scaled down)
kubectl scale deployment/${RELEASE_NAME}-server -n $NAMESPACE --replicas=2
kubectl scale statefulset/${RELEASE_NAME}-machine-learning -n $NAMESPACE --replicas=1

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE --timeout=600s

# Remove maintenance page
kubectl delete configmap maintenance-page -n $NAMESPACE
```

### 3.7 Post-Maintenance Validation

```bash
# Verify all pods running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# Check logs for errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --tail=100 --all-containers

# Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 2283:2283 &
curl -I http://localhost:2283

# Verify photo count
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT COUNT(*) FROM assets;"

# Notify users maintenance is complete
```

### 3.8 Makefile Targets

```bash
# Maintenance window upgrade
make -f make/ops/immich.mk immich-maintenance-upgrade VERSION=$TARGET_VERSION

# Post-maintenance check
make -f make/ops/immich.mk immich-post-upgrade-check
```

---

## Database Migrations

### 4.1 Understanding Immich Migrations

Immich uses automatic database migrations via TypeORM. Most upgrades handle migrations automatically, but some require manual intervention.

```bash
# Check migration status
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT * FROM migrations ORDER BY timestamp DESC LIMIT 10;"
```

### 4.2 Manual Migration (If Required)

Some major version upgrades require manual migration steps:

```bash
# Example: Immich v1.x → v2.x migration
# (Check release notes for specific instructions)

# 1. Backup database (REQUIRED)
make -f make/ops/immich.mk immich-backup-db

# 2. Run migration script (if provided)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  /app/scripts/migrate-v1-to-v2.sh

# 3. Verify migration
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "\dt"
```

### 4.3 Migration Troubleshooting

```bash
# Check for failed migrations
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-server-0 | grep -i migration

# Rollback migration (if supported)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  npm run migration:revert

# Manual rollback (restore from backup)
make -f make/ops/immich.mk immich-restore-db BACKUP_FILE=/backup/immich/pre-upgrade-20250127/immich-db.dump
```

---

## Version-Specific Notes

### 5.1 Immich v1.119.x → v1.120.x

**Type:** Minor upgrade
**Risk:** Low
**Recommended Strategy:** Rolling Upgrade

**Changes:**
- New face recognition models
- Performance improvements
- Bug fixes

**Migration Notes:**
- No manual migration required
- Automatic database schema updates
- ML models will download automatically

**Upgrade Command:**
```bash
helm upgrade immich scripton-charts/immich \
  --set immich.server.image.tag=v1.120.0 \
  --set immich.machineLearning.image.tag=v1.120.0 \
  --reuse-values
```

### 5.2 Immich v1.x → v2.x (Hypothetical Major Upgrade)

**Type:** Major upgrade
**Risk:** High
**Recommended Strategy:** Blue-Green Deployment or Maintenance Window

**Potential Changes:**
- Breaking API changes
- Database schema overhaul
- Configuration format changes
- New required dependencies

**Migration Notes:**
- ⚠️ Review release notes thoroughly
- ⚠️ Test in staging environment first
- ⚠️ Expect manual migration steps
- ⚠️ Plan for extended downtime (2-4 hours)

**Upgrade Steps:**
```bash
# 1. Full backup
make -f make/ops/immich.mk immich-full-backup

# 2. Review migration guide
# Visit: https://github.com/immich-app/immich/blob/main/docs/MIGRATION_V2.md

# 3. Test in staging environment
# (Deploy to test namespace, validate)

# 4. Schedule maintenance window
# (Notify users, plan 4-hour window)

# 5. Execute upgrade
make -f make/ops/immich.mk immich-maintenance-upgrade VERSION=v2.0.0
```

### 5.3 PostgreSQL Version Upgrades

If upgrading PostgreSQL (e.g., 15 → 16):

```bash
# 1. Backup database
make -f make/ops/immich.mk immich-backup-db

# 2. Dump database from old version
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -Fc > immich-pg15.dump

# 3. Upgrade PostgreSQL server (external)
# (Follow PostgreSQL upgrade guide)

# 4. Restore database to new version
pg_restore -h $POSTGRES_HOST_NEW -U $POSTGRES_USER -d $POSTGRES_DB immich-pg15.dump

# 5. Update Immich connection settings
helm upgrade immich scripton-charts/immich \
  --set postgresql.external.host=$POSTGRES_HOST_NEW
```

---

## Post-Upgrade Validation

### 6.1 Automated Validation Script

```bash
#!/bin/bash
# immich-post-upgrade-check.sh

set -euo pipefail

echo "=== Immich Post-Upgrade Validation ==="

# 1. Check pod status
echo "[1/8] Checking pod status..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
if [ $? -ne 0 ]; then
  echo "❌ Failed to get pods"
  exit 1
fi
echo "✅ Pod status check passed"

# 2. Check image versions
echo "[2/8] Checking image versions..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
echo "✅ Image version check passed"

# 3. Check database connectivity
echo "[3/8] Checking database connectivity..."
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" > /dev/null
if [ $? -ne 0 ]; then
  echo "❌ Database connectivity failed"
  exit 1
fi
echo "✅ Database connectivity check passed"

# 4. Verify photo count
echo "[4/8] Verifying photo count..."
PHOTO_COUNT=$(kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM assets;")
echo "Photo count: $PHOTO_COUNT"
echo "✅ Photo count check passed"

# 5. Test web interface
echo "[5/8] Testing web interface..."
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME} 2283:2283 &
PF_PID=$!
sleep 5
curl -f -I http://localhost:2283 > /dev/null
if [ $? -ne 0 ]; then
  echo "❌ Web interface check failed"
  kill $PF_PID
  exit 1
fi
kill $PF_PID
echo "✅ Web interface check passed"

# 6. Check for errors in logs
echo "[6/8] Checking logs for errors..."
ERROR_COUNT=$(kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --tail=100 --all-containers | grep -i error | wc -l)
if [ $ERROR_COUNT -gt 5 ]; then
  echo "⚠️  Warning: $ERROR_COUNT errors found in logs"
else
  echo "✅ Log error check passed ($ERROR_COUNT errors)"
fi

# 7. Check ML service
echo "[7/8] Checking ML service..."
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-machine-learning-0 -- ls /cache > /dev/null
if [ $? -ne 0 ]; then
  echo "⚠️  Warning: ML cache check failed"
else
  echo "✅ ML service check passed"
fi

# 8. Summary
echo "[8/8] Post-upgrade validation summary"
echo "======================================"
echo "✅ All critical checks passed"
echo "⚠️  Review warnings above (if any)"
echo "======================================"
```

### 6.2 Manual Validation Checklist

- [ ] All pods are running and ready
- [ ] Image versions match target version
- [ ] Database connectivity works
- [ ] Photo count matches pre-upgrade count
- [ ] Web interface loads successfully
- [ ] User login works
- [ ] Photo/video viewing works
- [ ] Album access works
- [ ] Sharing functionality works
- [ ] Upload functionality works
- [ ] ML features work (face recognition, search)
- [ ] Mobile app connectivity works
- [ ] No critical errors in logs

### 6.3 Makefile Target

```bash
# Run post-upgrade validation
make -f make/ops/immich.mk immich-post-upgrade-check
```

---

## Rollback Procedures

### 7.1 When to Rollback

Consider rollback if:

- ❌ Critical functionality is broken
- ❌ Data loss detected
- ❌ Severe performance degradation
- ❌ Database corruption
- ❌ Security vulnerabilities introduced

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
kubectl scale deployment/${RELEASE_NAME}-server -n $NAMESPACE --replicas=0
kubectl scale statefulset/${RELEASE_NAME}-machine-learning -n $NAMESPACE --replicas=0

# 2. Restore database from pre-upgrade backup
cat $BACKUP_PATH/postgresql/immich-db.dump | \
  kubectl exec -i -n $NAMESPACE postgres-0 -- \
  psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB;"
cat $BACKUP_PATH/postgresql/immich-db.dump | \
  kubectl exec -i -n $NAMESPACE postgres-0 -- \
  psql -U postgres -c "CREATE DATABASE $POSTGRES_DB;"
cat $BACKUP_PATH/postgresql/immich-db.dump | \
  kubectl exec -i -n $NAMESPACE postgres-0 -- \
  pg_restore -U $POSTGRES_USER -d $POSTGRES_DB -v

# 3. Rollback Helm release
helm rollback $RELEASE_NAME -n $NAMESPACE

# 4. Restore application
kubectl scale deployment/${RELEASE_NAME}-server -n $NAMESPACE --replicas=2
kubectl scale statefulset/${RELEASE_NAME}-machine-learning -n $NAMESPACE --replicas=1

# 5. Verify rollback
make -f make/ops/immich.mk immich-post-upgrade-check
```

### 7.4 Blue-Green Rollback

**Use Case:** Blue-Green deployment, need to switch back to blue

```bash
# Switch traffic back to blue service
kubectl patch ingress immich -n $NAMESPACE --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"immich"}]'

# Or rename services back
kubectl get svc immich-green -n $NAMESPACE -o yaml > /tmp/immich-green-svc.yaml
kubectl get svc immich -n $NAMESPACE -o yaml > /tmp/immich-blue-svc.yaml

kubectl delete svc immich immich-green -n $NAMESPACE
sed 's/name: immich$/name: immich-green/' /tmp/immich-blue-svc.yaml | kubectl apply -f -
sed 's/name: immich-green$/name: immich/' /tmp/immich-blue-svc.yaml | kubectl apply -f -

# Delete green environment
helm uninstall $GREEN_RELEASE -n $NAMESPACE
```

### 7.5 Makefile Target

```bash
# Rollback to previous version
make -f make/ops/immich.mk immich-upgrade-rollback
```

---

## Troubleshooting

### 8.1 Upgrade Failures

#### Issue: Pods stuck in `ImagePullBackOff`

**Cause:** Invalid image tag or registry authentication failure

**Solution:**
```bash
# Check image pull errors
kubectl describe pod ${RELEASE_NAME}-server-0 -n $NAMESPACE

# Verify image exists
docker pull ghcr.io/immich-app/immich-server:$TARGET_VERSION

# Check image pull secrets
kubectl get secret -n $NAMESPACE
kubectl describe secret <image-pull-secret> -n $NAMESPACE
```

#### Issue: Pods crash with `CrashLoopBackOff`

**Cause:** Database migration failure, configuration error

**Solution:**
```bash
# Check pod logs
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-server-0 --previous

# Check database connectivity
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"

# Check for migration errors
kubectl logs -n $NAMESPACE ${RELEASE_NAME}-server-0 | grep -i migration
```

#### Issue: Helm upgrade timeout

**Cause:** Slow database migration, pod startup issues

**Solution:**
```bash
# Increase timeout
helm upgrade $RELEASE_NAME scripton-charts/immich \
  --timeout 30m \
  --wait

# Or upgrade without waiting
helm upgrade $RELEASE_NAME scripton-charts/immich \
  --no-wait
```

### 8.2 Database Migration Issues

#### Issue: Migration fails with "duplicate key value violates unique constraint"

**Cause:** Data inconsistency, migration script bug

**Solution:**
```bash
# Rollback database to pre-upgrade state
make -f make/ops/immich.mk immich-restore-db BACKUP_FILE=$BACKUP_PATH/postgresql/immich-db.dump

# Report issue to Immich GitHub
# https://github.com/immich-app/immich/issues
```

#### Issue: Migration hangs indefinitely

**Cause:** Large database, slow storage

**Solution:**
```bash
# Check migration progress
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c \
  "SELECT * FROM pg_stat_activity WHERE state != 'idle';"

# If truly hung, kill migration and rollback
kubectl delete pod ${RELEASE_NAME}-server-0 -n $NAMESPACE
helm rollback $RELEASE_NAME -n $NAMESPACE
```

### 8.3 Performance Issues Post-Upgrade

#### Issue: Web interface extremely slow after upgrade

**Cause:** Missing indexes after migration, inefficient queries

**Solution:**
```bash
# Check database query performance
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c \
  "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Rebuild indexes (if needed)
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "REINDEX DATABASE $POSTGRES_DB;"

# Vacuum database
kubectl exec -n $NAMESPACE ${RELEASE_NAME}-server-0 -- \
  psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "VACUUM ANALYZE;"
```

### 8.4 Makefile Targets

```bash
# Troubleshoot upgrade issues
make -f make/ops/immich.mk immich-troubleshoot-upgrade

# Check upgrade logs
make -f make/ops/immich.mk immich-upgrade-logs
```

---

## Best Practices

### 9.1 General Upgrade Best Practices

1. **Always Backup First** - No exceptions. Full backup before any upgrade.
2. **Test in Staging** - Deploy to test environment first, validate thoroughly.
3. **Read Release Notes** - Understand breaking changes and migration requirements.
4. **Plan Rollback** - Have rollback procedure ready before starting upgrade.
5. **Monitor Closely** - Watch logs, metrics, and user feedback during upgrade.
6. **Upgrade During Low-Traffic** - Schedule upgrades during off-peak hours.
7. **Incremental Upgrades** - Avoid skipping multiple major versions.

### 9.2 Backup Before Upgrade

```bash
# Always run full backup before upgrade
make -f make/ops/immich.mk immich-full-backup

# Verify backup completed successfully
ls -lh $BACKUP_PATH/

# Test backup restoration (in test namespace)
make -f make/ops/immich.mk immich-test-restore
```

### 9.3 Staging Environment Testing

```bash
# Deploy to staging namespace
kubectl create namespace immich-staging

# Restore production data to staging
make -f make/ops/immich.mk immich-restore-to-staging \
  BACKUP_PATH=$BACKUP_PATH \
  NAMESPACE=immich-staging

# Upgrade staging environment
helm upgrade immich-staging scripton-charts/immich \
  -n immich-staging \
  --set immich.server.image.tag=$TARGET_VERSION \
  --set immich.machineLearning.image.tag=$TARGET_VERSION

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
| Critical | Data loss, security breach | Immediate rollback | < 15 minutes |
| High | Major functionality broken | Rollback if no fix within 1 hour | < 1 hour |
| Medium | Minor functionality broken | Fix forward if possible | 2-4 hours |
| Low | Cosmetic issues, warnings | Fix in next patch release | No rollback |

---

## Summary

### Key Takeaways

1. **Three Upgrade Strategies**: Rolling (zero-downtime), Blue-Green (low-risk), Maintenance Window (simple)
2. **Always Backup First**: Full backup before any upgrade, no exceptions
3. **Test First**: Validate upgrades in staging before production
4. **Monitor Closely**: Watch logs, metrics, and user feedback during and after upgrade
5. **Plan Rollback**: Have rollback procedure ready and tested

### Quick Reference

```bash
# Pre-upgrade checklist
make -f make/ops/immich.mk immich-pre-upgrade-check

# Full backup
make -f make/ops/immich.mk immich-full-backup

# Rolling upgrade (recommended for minor versions)
make -f make/ops/immich.mk immich-rolling-upgrade VERSION=v1.120.0

# Blue-green upgrade (recommended for major versions)
make -f make/ops/immich.mk immich-blue-green-deploy VERSION=v2.0.0

# Post-upgrade validation
make -f make/ops/immich.mk immich-post-upgrade-check

# Rollback (if needed)
make -f make/ops/immich.mk immich-upgrade-rollback
```

### Related Documentation

- [Immich Backup Guide](immich-backup-guide.md)
- [Immich README](../charts/immich/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)
- [Immich Official Docs](https://immich.app/docs)

---

**Last Updated:** 2025-01-27
**Version:** 1.0.0
