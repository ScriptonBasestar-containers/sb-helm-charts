# Paperless-ngx Upgrade Guide

This guide provides comprehensive upgrade procedures for Paperless-ngx deployed via the ScriptonBasestar Helm chart.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Strategies](#upgrade-strategies)
  - [1. Rolling Upgrade (Recommended)](#1-rolling-upgrade-recommended)
  - [2. Maintenance Mode Upgrade](#2-maintenance-mode-upgrade)
  - [3. Blue-Green Deployment](#3-blue-green-deployment)
  - [4. Database Migration Upgrade](#4-database-migration-upgrade)
- [Version-Specific Notes](#version-specific-notes)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Overview

Paperless-ngx follows semantic versioning with regular releases. Upgrade procedures depend on:

- **Version change magnitude** (patch vs. minor vs. major)
- **Database schema changes** (requires migration)
- **Configuration changes** (environment variables, settings)
- **Downtime tolerance** (zero-downtime vs. maintenance window)

This guide covers all upgrade scenarios with production-ready procedures using Makefile targets.

---

## Pre-Upgrade Checklist

### 1. Review Release Notes

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-check-latest-version
```

**Manual Procedure:**
```bash
# 1. Check current version
kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 2. Check latest version
helm search repo scripton-charts/paperless-ngx --versions | head -5

# 3. Review release notes
# Visit: https://github.com/paperless-ngx/paperless-ngx/releases
```

### 2. Backup Current State

**⚠️ CRITICAL: Always backup before upgrading!**

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-full-backup
```

**Manual Procedure:**
```bash
# 1. Set backup timestamp
export BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 2. Backup all documents
make -f make/ops/paperless-ngx.mk paperless-backup-documents

# 3. Backup database
make -f make/ops/paperless-ngx.mk paperless-backup-database

# 4. Backup configuration
make -f make/ops/paperless-ngx.mk paperless-backup-helm-values

# 5. Create PVC snapshots
make -f make/ops/paperless-ngx.mk paperless-create-pvc-snapshots

# 6. Verify all backups exist
ls -lh $BACKUP_DIR/$BACKUP_TIMESTAMP/
```

**Expected Files:**
```
consume.tar.gz
data.tar.gz
media.tar.gz
export.tar.gz
paperless-db.dump
helm-values.yaml
volumesnapshots.yaml
```

### 3. Check Cluster Resources

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-pre-upgrade-check
```

**Manual Procedure:**
```bash
# 1. Check pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# 2. Check PVC status and capacity
kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# 3. Check node resources
kubectl top nodes

# 4. Check current resource usage
kubectl top pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# 5. Verify database connectivity
export POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c 'SELECT version();'"

# 6. Verify Redis connectivity
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "redis-cli -h $REDIS_HOST -p $REDIS_PORT -a '$REDIS_PASSWORD' PING"
```

**Expected Output:**
```
NAME                                   READY   STATUS    RESTARTS   AGE
paperless-ngx-xxxx                     1/1     Running   0          5d

NAME                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES
paperless-ngx-consume          Bound    pvc-xxx                                    10Gi       RWO
paperless-ngx-data             Bound    pvc-yyy                                    10Gi       RWO
paperless-ngx-media            Bound    pvc-zzz                                    50Gi       RWO
paperless-ngx-export           Bound    pvc-www                                    10Gi       RWO

PostgreSQL 17.2
PONG
```

### 4. Review Configuration Changes

```bash
# 1. Get current Helm values
helm get values -n $NAMESPACE $RELEASE_NAME > current-values.yaml

# 2. Get new chart default values
helm show values scripton-charts/paperless-ngx > new-default-values.yaml

# 3. Compare configuration
diff current-values.yaml new-default-values.yaml
```

### 5. Notify Users (if applicable)

```bash
# Schedule maintenance window if zero-downtime upgrade is not possible
# - Send notification to users
# - Update status page
# - Schedule upgrade during low-traffic period
```

---

## Upgrade Strategies

### 1. Rolling Upgrade (Recommended)

**Use Case:** Patch and minor version upgrades with no breaking changes

**Downtime:** None (zero-downtime upgrade)

**Pros:**
- No service interruption
- Automatic rollback on failure
- Simple procedure

**Cons:**
- Not suitable for major version changes with breaking changes
- Database migrations run during traffic (potential performance impact)

#### Procedure

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-upgrade-rolling VERSION=2.15.0
```

**Manual Procedure:**
```bash
# Step 1: Pre-upgrade backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Update chart repository
helm repo update scripton-charts

# Step 3: Review changes (dry-run)
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set image.tag=2.15.0 \
  --reuse-values \
  --dry-run --debug

# Step 4: Perform rolling upgrade
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set image.tag=2.15.0 \
  --reuse-values \
  --wait --timeout 10m

# Step 5: Monitor rollout
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx

# Step 6: Verify new version
kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Step 7: Post-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

**Expected Output:**
```
Release "paperless-ngx" has been upgraded. Happy Helming!
deployment "paperless-ngx" successfully rolled out
ghcr.io/paperless-ngx/paperless-ngx:2.15.0
```

**Database Migration Handling:**
Paperless-ngx automatically applies database migrations on startup via Django migrations. Monitor logs:

```bash
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=100 -f
```

Expected migration output:
```
Operations to perform:
  Apply all migrations: admin, auth, contenttypes, documents, paperless_mail, sessions
Running migrations:
  Applying documents.0043_auto_20241201_1234... OK
  Applying documents.0044_auto_20241205_5678... OK
```

---

### 2. Maintenance Mode Upgrade

**Use Case:** Major version upgrades with breaking changes or significant database schema changes

**Downtime:** 10-30 minutes (depends on database migration time)

**Pros:**
- Safe for major version changes
- Database migrations run without traffic
- Clear maintenance window

**Cons:**
- Service unavailable during upgrade
- Requires user notification

#### Procedure

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-upgrade-maintenance VERSION=3.0.0
```

**Manual Procedure:**
```bash
# Step 1: Pre-upgrade backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Create maintenance notice
cat > /tmp/maintenance.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Maintenance</title></head>
<body>
  <h1>Paperless-ngx is currently under maintenance</h1>
  <p>We are upgrading to version 3.0.0. Expected completion: 30 minutes.</p>
</body>
</html>
EOF

# Step 3: Scale down to 0 replicas (enter maintenance mode)
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=0

# Step 4: Verify all pods are terminated
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# Step 5: Backup database one final time (while app is down)
make -f make/ops/paperless-ngx.mk paperless-backup-database

# Step 6: Update Helm release
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set image.tag=3.0.0 \
  --reuse-values \
  --wait --timeout 15m

# Step 7: Wait for pod to be ready (migrations will run automatically)
kubectl wait pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx \
  --for=condition=Ready --timeout=900s

# Step 8: Monitor migration logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=200 -f

# Step 9: Verify application health
kubectl exec -n $NAMESPACE $(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}') -- \
  python manage.py check

# Step 10: Post-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check

# Step 11: Test web interface
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-paperless-ngx 8000:8000
# Access http://localhost:8000 and verify functionality

# Step 12: Remove maintenance notice (if using Ingress with maintenance page)
# This step depends on your specific Ingress setup
```

**Total Downtime:** 10-30 minutes (depends on migration complexity)

---

### 3. Blue-Green Deployment

**Use Case:** Zero-downtime upgrades for major versions with ability to quickly rollback

**Downtime:** None (instant cutover)

**Pros:**
- Zero downtime
- Instant rollback (switch back to "blue" environment)
- Full testing before cutover

**Cons:**
- Requires 2x resources temporarily
- Database sharing requires careful planning
- More complex procedure

#### Procedure

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-upgrade-blue-green VERSION=3.0.0
```

**Manual Procedure:**
```bash
# Step 1: Pre-upgrade backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Deploy "green" environment (new version)
export GREEN_RELEASE="${RELEASE_NAME}-green"

# Step 3: Create separate PVCs for green environment (to avoid data conflicts)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${GREEN_RELEASE}-consume
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${GREEN_RELEASE}-data
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${GREEN_RELEASE}-media
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${GREEN_RELEASE}-export
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Step 4: Copy data from blue to green PVCs
# This requires a temporary pod with both PVCs mounted
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: data-copy-pod
  namespace: $NAMESPACE
spec:
  containers:
  - name: copier
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: blue-consume
      mountPath: /blue/consume
    - name: blue-data
      mountPath: /blue/data
    - name: blue-media
      mountPath: /blue/media
    - name: blue-export
      mountPath: /blue/export
    - name: green-consume
      mountPath: /green/consume
    - name: green-data
      mountPath: /green/data
    - name: green-media
      mountPath: /green/media
    - name: green-export
      mountPath: /green/export
  volumes:
  - name: blue-consume
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-consume
  - name: blue-data
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-data
  - name: blue-media
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-media
  - name: blue-export
    persistentVolumeClaim:
      claimName: ${RELEASE_NAME}-export
  - name: green-consume
    persistentVolumeClaim:
      claimName: ${GREEN_RELEASE}-consume
  - name: green-data
    persistentVolumeClaim:
      claimName: ${GREEN_RELEASE}-data
  - name: green-media
    persistentVolumeClaim:
      claimName: ${GREEN_RELEASE}-media
  - name: green-export
    persistentVolumeClaim:
      claimName: ${GREEN_RELEASE}-export
EOF

# Step 5: Wait for pod to be ready
kubectl wait pod -n $NAMESPACE data-copy-pod --for=condition=Ready --timeout=120s

# Step 6: Copy data (this will take time depending on data size)
kubectl exec -n $NAMESPACE data-copy-pod -- sh -c "cp -a /blue/consume/. /green/consume/"
kubectl exec -n $NAMESPACE data-copy-pod -- sh -c "cp -a /blue/data/. /green/data/"
kubectl exec -n $NAMESPACE data-copy-pod -- sh -c "cp -a /blue/media/. /green/media/"
kubectl exec -n $NAMESPACE data-copy-pod -- sh -c "cp -a /blue/export/. /green/export/"

# Step 7: Delete data-copy-pod
kubectl delete pod -n $NAMESPACE data-copy-pod

# Step 8: Deploy green environment with new version
helm install $GREEN_RELEASE scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set image.tag=3.0.0 \
  --set persistence.consume.existingClaim=${GREEN_RELEASE}-consume \
  --set persistence.data.existingClaim=${GREEN_RELEASE}-data \
  --set persistence.media.existingClaim=${GREEN_RELEASE}-media \
  --set persistence.export.existingClaim=${GREEN_RELEASE}-export \
  --set service.port=8001 \
  --set ingress.enabled=false \
  --reuse-values \
  --wait --timeout 15m

# Step 9: Wait for green deployment to be ready
kubectl wait deployment -n $NAMESPACE ${GREEN_RELEASE}-paperless-ngx \
  --for=condition=Available --timeout=900s

# Step 10: Test green environment
kubectl port-forward -n $NAMESPACE svc/${GREEN_RELEASE}-paperless-ngx 8001:8001
# Access http://localhost:8001 and verify functionality

# Step 11: Run smoke tests on green environment
make -f make/ops/paperless-ngx.mk paperless-smoke-test RELEASE=$GREEN_RELEASE

# Step 12: Cutover to green (update Ingress or Service selector)
# Option A: Update Ingress to point to green service
kubectl patch ingress -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -p \
  '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"'${GREEN_RELEASE}'-paperless-ngx","port":{"number":8000}}}}]}}]}}'

# Option B: Update Service selector to point to green deployment
kubectl patch service -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"'${GREEN_RELEASE}'"}}}'

# Step 13: Monitor traffic and errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=${GREEN_RELEASE} --tail=100 -f

# Step 14: If everything is OK, scale down blue deployment
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=0

# Step 15: Keep blue environment for 24-48 hours, then clean up
# After confirming green is stable:
helm uninstall -n $NAMESPACE $RELEASE_NAME
kubectl delete pvc -n $NAMESPACE ${RELEASE_NAME}-consume ${RELEASE_NAME}-data ${RELEASE_NAME}-media ${RELEASE_NAME}-export
```

**Rollback (if issues occur):**
```bash
# Instant rollback: Switch back to blue
kubectl patch service -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"'${RELEASE_NAME}'"}}}'

kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=1
kubectl scale deployment -n $NAMESPACE ${GREEN_RELEASE}-paperless-ngx --replicas=0
```

---

### 4. Database Migration Upgrade

**Use Case:** PostgreSQL version upgrades (e.g., PostgreSQL 13 → 17)

**Downtime:** 30-60 minutes (depends on database size)

**Pros:**
- Controlled database migration
- Data validation before cutover

**Cons:**
- Significant downtime
- Complex procedure

#### Procedure

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-upgrade-database-migration
```

**Manual Procedure:**
```bash
# Step 1: Full backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Scale down Paperless-ngx
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=0

# Step 3: Backup PostgreSQL database
make -f make/ops/paperless-ngx.mk paperless-backup-database

# Step 4: Deploy new PostgreSQL instance (e.g., PostgreSQL 17)
# This step depends on how you manage PostgreSQL (Helm chart, operator, external)
# Example using Bitnami PostgreSQL chart:
helm install postgresql-new bitnami/postgresql \
  --version 17.0.0 \
  -n $NAMESPACE \
  --set auth.username=paperless \
  --set auth.password=<strong-password> \
  --set auth.database=paperless

# Step 5: Wait for new PostgreSQL to be ready
kubectl wait pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql-new \
  --for=condition=Ready --timeout=300s

# Step 6: Restore database to new PostgreSQL instance
export NEW_POSTGRES_HOST="postgresql-new.default.svc.cluster.local"
export NEW_POSTGRES_PORT=5432
export NEW_POSTGRES_USER="paperless"
export NEW_POSTGRES_PASSWORD="<strong-password>"
export NEW_POSTGRES_DB="paperless"

cat $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump | \
  kubectl exec -i -n $NAMESPACE $(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql-new -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U $NEW_POSTGRES_USER -d $NEW_POSTGRES_DB

# Step 7: Verify data in new database
kubectl exec -n $NAMESPACE $(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql-new -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U $NEW_POSTGRES_USER -d $NEW_POSTGRES_DB -c 'SELECT COUNT(*) FROM documents_document;'

# Step 8: Update Paperless-ngx to use new database
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set postgresql.external.host=$NEW_POSTGRES_HOST \
  --set postgresql.external.port=$NEW_POSTGRES_PORT \
  --set postgresql.external.username=$NEW_POSTGRES_USER \
  --set postgresql.external.password=$NEW_POSTGRES_PASSWORD \
  --set postgresql.external.database=$NEW_POSTGRES_DB \
  --reuse-values \
  --wait --timeout 10m

# Step 9: Verify Paperless-ngx connectivity to new database
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=100

# Step 10: Post-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check

# Step 11: After confirming everything works, decommission old PostgreSQL
# Keep old database for 7 days before deletion (safety net)
helm uninstall -n $NAMESPACE postgresql-old
```

---

## Version-Specific Notes

### Upgrading to Paperless-ngx 2.15.x

**Breaking Changes:**
- None

**New Features:**
- Improved OCR performance
- New document tags UI
- Enhanced search capabilities

**Migration Notes:**
```bash
# No special migration required
# Standard rolling upgrade procedure applies
make -f make/ops/paperless-ngx.mk paperless-upgrade-rolling VERSION=2.15.0
```

---

### Upgrading to Paperless-ngx 3.0.x (Future Major Release)

**Breaking Changes:**
- PostgreSQL 16+ required (upgrade from PostgreSQL 13-15)
- Redis 7+ required (upgrade from Redis 6)
- Environment variable changes (see release notes)
- New document storage format (automatic migration)

**Migration Notes:**
```bash
# 1. Use Maintenance Mode upgrade strategy
make -f make/ops/paperless-ngx.mk paperless-upgrade-maintenance VERSION=3.0.0

# 2. Monitor migration logs carefully
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=500 -f

# 3. Expect longer migration time (document format conversion)
# Allow 30-60 minutes for migration on large document sets
```

---

### Upgrading PostgreSQL (External Database)

**PostgreSQL 13 → 17 Upgrade:**
```bash
# Use Database Migration Upgrade strategy
make -f make/ops/paperless-ngx.mk paperless-upgrade-database-migration

# Or use pg_upgrade for in-place upgrade (advanced)
# Refer to PostgreSQL documentation: https://www.postgresql.org/docs/current/pgupgrade.html
```

---

## Post-Upgrade Validation

### Automated Validation

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

**Manual Procedure:**
```bash
# 1. Verify pod is running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# 2. Verify image version
kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 3. Check pod logs for errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=100

# 4. Verify database connectivity
export POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD -- python manage.py check

# 5. Verify document count
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"

# 6. Test web interface health endpoint
kubectl exec -n $NAMESPACE $POD -- curl -f http://localhost:8000/api/ || echo "Health check failed"

# 7. Test document search
kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-paperless-ngx 8000:8000
# Access http://localhost:8000 and test search functionality

# 8. Verify OCR functionality (upload a test document)
# This requires manual testing via web interface

# 9. Check PVC usage
kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

# 10. Verify Redis connectivity
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "redis-cli -h $REDIS_HOST -p $REDIS_PORT -a '$REDIS_PASSWORD' PING"
```

**Expected Output:**
```
✓ Pod running (1/1 Ready)
✓ Image version matches target
✓ No errors in logs
✓ Database connectivity OK
✓ Document count matches pre-upgrade count
✓ Health endpoint returns 200 OK
✓ Search functionality working
✓ OCR processing functional
✓ PVCs healthy
✓ Redis connectivity OK
```

### Smoke Tests

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-smoke-test
```

**Manual Tests:**
```bash
# 1. Upload test document
# Via web interface: Upload a PDF document

# 2. Verify document appears in list
# Check web interface for newly uploaded document

# 3. Test search
# Search for document using keywords

# 4. Test OCR
# Verify OCR text extraction for uploaded document

# 5. Test tagging
# Add tags to document

# 6. Test correspondent management
# Create/edit correspondents

# 7. Test document types
# Create/edit document types

# 8. Test custom fields
# Create/edit custom fields

# 9. Test bulk operations
# Select multiple documents, apply bulk action

# 10. Test API
kubectl exec -n $NAMESPACE $POD -- curl -H "Authorization: Token <api-token>" \
  http://localhost:8000/api/documents/ | jq '.count'
```

---

## Rollback Procedures

### Rolling Upgrade Rollback

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-upgrade-rollback
```

**Manual Procedure:**
```bash
# 1. Rollback Helm release
helm rollback -n $NAMESPACE $RELEASE_NAME

# 2. Wait for rollout to complete
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx

# 3. Verify old version is running
kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 4. Check pod logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=100

# 5. Verify application health
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

---

### Database Rollback (from backup)

**Use Case:** Database migration failed or data corruption after upgrade

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-rollback-database BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# 1. Scale down Paperless-ngx
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=0

# 2. Drop current database
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U postgres \
  -c 'DROP DATABASE $POSTGRES_DB;'"

# 3. Recreate database
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U postgres \
  -c 'CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;'"

# 4. Restore from backup
cat $BACKUP_DIR/$BACKUP_TIMESTAMP/paperless-db.dump | \
  kubectl exec -n $NAMESPACE $POD -i -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' pg_restore -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  --clean --if-exists --no-owner --no-privileges"

# 5. Scale up Paperless-ngx
kubectl scale deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --replicas=1

# 6. Verify database restore
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"
```

---

### Full System Rollback (from PVC snapshots)

**Use Case:** Complete system failure after upgrade

**Makefile Target:**
```bash
make -f make/ops/paperless-ngx.mk paperless-rollback-full BACKUP_DATE=20241208_100000
```

**Manual Procedure:**
```bash
# 1. Uninstall current release
helm uninstall -n $NAMESPACE $RELEASE_NAME

# 2. Delete current PVCs
kubectl delete pvc -n $NAMESPACE ${RELEASE_NAME}-consume ${RELEASE_NAME}-data ${RELEASE_NAME}-media ${RELEASE_NAME}-export

# 3. Restore PVCs from snapshots
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-consume
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-consume-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-data
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-data-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-media
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-media-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${RELEASE_NAME}-export
  namespace: $NAMESPACE
spec:
  dataSource:
    name: ${RELEASE_NAME}-export-snapshot-${BACKUP_TIMESTAMP}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# 4. Wait for PVCs to be bound
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-consume --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-data --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-media --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl wait pvc -n $NAMESPACE ${RELEASE_NAME}-export --for=jsonpath='{.status.phase}'=Bound --timeout=300s

# 5. Reinstall Helm release with previous version
helm install $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --version <previous-chart-version> \
  -f $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml \
  --wait --timeout 15m

# 6. Verify rollback
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

---

## Troubleshooting

### Issue 1: Upgrade Stuck on "Waiting for rollout"

**Symptoms:**
```
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx
Waiting for deployment "paperless-ngx" rollout to finish: 0 of 1 updated replicas are available...
(times out after 10 minutes)
```

**Solution:**
```bash
# 1. Check pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# 2. Check pod events
kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx

# 3. Check logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=paperless-ngx --tail=200

# 4. Common causes:
# - Database migration failure (check logs for migration errors)
# - Database connectivity issues (verify credentials)
# - Insufficient resources (check node resources)
# - ImagePullBackOff (verify image tag exists)

# 5. If migration is taking long (expected), increase timeout:
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  --set image.tag=2.15.0 \
  --reuse-values \
  --wait --timeout 30m  # Increase from default 10m
```

---

### Issue 2: Database Migration Fails

**Symptoms:**
```
django.db.utils.OperationalError: could not connect to server
django.db.migrations.exceptions.MigrationSchemaMissing
```

**Solution:**
```bash
# 1. Verify database connectivity
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c 'SELECT version();'"

# 2. Check database credentials in Secret
kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx -o yaml

# 3. Manually run migrations (if automatic migration failed)
kubectl exec -n $NAMESPACE $POD -- python manage.py migrate --noinput

# 4. If migration fails due to corrupted state, reset migrations (DANGER!)
# Only do this if you understand the consequences
kubectl exec -n $NAMESPACE $POD -- python manage.py migrate --fake-initial

# 5. If all else fails, restore from backup
make -f make/ops/paperless-ngx.mk paperless-rollback-database BACKUP_DATE=$BACKUP_TIMESTAMP
```

---

### Issue 3: Document Count Mismatch After Upgrade

**Symptoms:**
- Document count in web interface differs from pre-upgrade count
- Some documents missing

**Solution:**
```bash
# 1. Rebuild search index
kubectl exec -n $NAMESPACE $POD -- python manage.py document_index reindex

# 2. Verify database integrity
kubectl exec -n $NAMESPACE $POD -- sh -c \
  "PGPASSWORD='$POSTGRES_PASSWORD' psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB \
  -c 'SELECT COUNT(*) FROM documents_document;'"

# 3. Verify media files exist
kubectl exec -n $NAMESPACE $POD -- find /usr/src/paperless/media/documents/originals -type f | wc -l

# 4. If media files are missing, restore from backup
make -f make/ops/paperless-ngx.mk paperless-restore-documents BACKUP_DATE=$BACKUP_TIMESTAMP
```

---

### Issue 4: OCR Not Working After Upgrade

**Symptoms:**
- Documents uploaded but OCR text not extracted
- Search not finding document content

**Solution:**
```bash
# 1. Check OCR packages are installed
kubectl exec -n $NAMESPACE $POD -- which tesseract
kubectl exec -n $NAMESPACE $POD -- tesseract --version

# 2. Check OCR language packages
kubectl exec -n $NAMESPACE $POD -- tesseract --list-langs

# 3. Re-run OCR for existing documents
kubectl exec -n $NAMESPACE $POD -- python manage.py document_create_classifier

# 4. Check environment variables
kubectl exec -n $NAMESPACE $POD -- env | grep PAPERLESS_OCR

# 5. Verify OCR mode setting
# In values.yaml:
# paperless.ocr.mode: "skip"  # Change to "redo" or "force" to re-OCR
```

---

### Issue 5: Helm Rollback Fails

**Symptoms:**
```
Error: UPGRADE FAILED: failed to create resource: Deployment.apps "paperless-ngx" is invalid
```

**Solution:**
```bash
# 1. Force delete deployment
kubectl delete deployment -n $NAMESPACE ${RELEASE_NAME}-paperless-ngx --grace-period=0 --force

# 2. Retry rollback
helm rollback -n $NAMESPACE $RELEASE_NAME --force

# 3. If Helm state is corrupted, manually restore from backup
kubectl apply -f $BACKUP_DIR/$BACKUP_TIMESTAMP/deployment.yaml
kubectl apply -f $BACKUP_DIR/$BACKUP_TIMESTAMP/service.yaml
kubectl apply -f $BACKUP_DIR/$BACKUP_TIMESTAMP/configmaps.yaml
kubectl apply -f $BACKUP_DIR/$BACKUP_TIMESTAMP/pvcs.yaml

# 4. Update Helm release to match current state
helm upgrade $RELEASE_NAME scripton-charts/paperless-ngx \
  -n $NAMESPACE \
  -f $BACKUP_DIR/$BACKUP_TIMESTAMP/helm-values.yaml \
  --force
```

---

## Summary

This guide provides comprehensive upgrade procedures for Paperless-ngx. Key takeaways:

1. **4 Upgrade Strategies**: Rolling (recommended), Maintenance Mode, Blue-Green, Database Migration
2. **Always Backup First**: Full backup before every upgrade (documents, database, configuration, PVC snapshots)
3. **Choose Strategy Based on Change Magnitude**: Patch/minor = rolling, major = maintenance mode or blue-green
4. **Monitor Migrations**: Django migrations run automatically on startup - monitor logs
5. **Test Before Production**: Use Blue-Green strategy for high-stakes upgrades with full testing before cutover
6. **Rollback Plan**: Know your rollback procedure before starting upgrade

**Recommended Upgrade Workflow:**
```
Pre-Upgrade Backup → Choose Strategy → Review Release Notes →
Dry-Run Upgrade → Execute Upgrade → Monitor Migrations →
Post-Upgrade Validation → Keep Backup for 7 days
```

For backup procedures, see [Paperless-ngx Backup Guide](paperless-ngx-backup-guide.md).
