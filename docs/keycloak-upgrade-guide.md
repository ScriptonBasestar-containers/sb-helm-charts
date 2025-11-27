# Keycloak Upgrade Guide

Comprehensive guide for upgrading Keycloak chart and handling version-specific breaking changes.

## Table of Contents

- [Overview](#overview)
- [Keycloak 26.x Breaking Changes](#keycloak-26x-breaking-changes)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Procedures](#upgrade-procedures)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Version-Specific Guides](#version-specific-guides)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Upgrade Philosophy

This chart follows **safe upgrade practices**:
1. Pre-upgrade health checks
2. Mandatory backups
3. Step-by-step validation
4. Documented rollback procedures

### Supported Upgrade Paths

| From Version | To Version | Complexity | Notes |
|--------------|------------|-----------|-------|
| 25.x | 26.x | **High** | Breaking changes |
| 26.0 | 26.4 | Low | Minor updates |
| Chart 0.2.x | Chart 0.3.x | Medium | RBAC + backup features added |

---

## Keycloak 26.x Breaking Changes

### 1. Hostname v1 Removed

**Impact:** High - Deployments using hostname v1 will fail

**What changed:**
- `KC_HOSTNAME` environment variable no longer supported
- Must migrate to hostname v2 configuration

**Migration:**

**Before (v1 - NO LONGER WORKS):**
```yaml
keycloak:
  extraEnv:
    - name: KC_HOSTNAME
      value: "auth.example.com"
    - name: KC_HOSTNAME_STRICT
      value: "false"
```

**After (v2 - REQUIRED):**
```yaml
keycloak:
  extraEnv:
    - name: KC_HOSTNAME_URL
      value: "https://auth.example.com"
    - name: KC_HOSTNAME_ADMIN_URL
      value: "https://admin.auth.example.com"
    - name: KC_HOSTNAME_STRICT_HTTPS
      value: "true"
```

**Testing:**
```bash
# Verify hostname configuration
kubectl exec keycloak-0 -- curl -s http://localhost:8080/realms/master/.well-known/openid-configuration | jq .issuer
# Expected: "https://auth.example.com/realms/master"
```

### 2. Health Endpoints Moved to Port 9000

**Impact:** Medium - Health probes will fail if not updated

**What changed:**
- Health endpoints moved from port 8080 to port 9000 (management port)
- Affects liveness, readiness, and startup probes

**Migration:**

**Chart already updated:**
```yaml
# templates/statefulset.yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 9000  # Changed from 8080

readinessProbe:
  httpGet:
    path: /health/ready
    port: 9000  # Changed from 8080

startupProbe:
  httpGet:
    path: /health/started
    port: 9000  # Changed from 8080
```

**Manual verification:**
```bash
# Check probes after upgrade
kubectl get pod keycloak-0 -o jsonpath='{.spec.containers[0].livenessProbe}'
```

### 3. PostgreSQL 13+ Required

**Impact:** Critical - Keycloak 26.x won't start with PostgreSQL 12.x

**What changed:**
- Minimum PostgreSQL version increased from 12.x to 13.x
- Uses PostgreSQL 13+ specific features

**Pre-upgrade:**
```bash
# Check PostgreSQL version
kubectl exec postgres-0 -- psql --version
# Must be: PostgreSQL 13.x or higher
```

**If PostgreSQL 12.x:**
```bash
# Option 1: Upgrade PostgreSQL (recommended)
# 1. Backup database
make -f make/ops/postgresql.mk pg-backup-all

# 2. Upgrade PostgreSQL chart
helm upgrade postgresql charts/postgresql --set image.tag=13.17

# 3. Verify version
kubectl exec postgres-0 -- psql --version

# Option 2: Deploy new PostgreSQL 13+ instance
# See PostgreSQL chart README
```

### 4. CLI-Based Clustering

**Impact:** Low - Environment variable clustering still works but deprecated

**What changed:**
- JGroups configuration moved to CLI options
- Environment variables deprecated (still work in 26.x)

**Recommended migration:**

**Old way (deprecated but works):**
```yaml
clustering:
  enabled: true
```

**New way (recommended):**
```yaml
keycloak:
  args:
    - "start"
    - "--optimized"
    - "--cache=ispn"
    - "--cache-stack=kubernetes"
```

**Testing:**
```bash
# Verify clustering
make -f make/ops/keycloak.mk kc-cluster-status
# Should show JGroups members
```

### 5. OpenJDK 21 Recommended

**Impact:** Low - OpenJDK 17 still supported

**What changed:**
- OpenJDK 17 deprecated (will be removed in future)
- OpenJDK 21 is default

**No action required** - Chart uses official Keycloak image with OpenJDK 21

---

## Pre-Upgrade Checklist

### Critical Steps (MANDATORY)

- [ ] **Backup all realms**
  ```bash
  make -f make/ops/keycloak.mk kc-backup-all-realms
  ```

- [ ] **Backup PostgreSQL database**
  ```bash
  make -f make/ops/keycloak.mk kc-db-backup
  ```

- [ ] **Verify PostgreSQL version (13+)**
  ```bash
  kubectl exec postgres-0 -- psql --version
  ```

- [ ] **Run pre-upgrade health check**
  ```bash
  make -f make/ops/keycloak.mk kc-pre-upgrade-check
  ```

- [ ] **Review breaking changes** (this document)

- [ ] **Test upgrade in staging** (if production)

### Recommended Steps

- [ ] **Document current configuration**
  ```bash
  helm get values keycloak > pre-upgrade-values.yaml
  ```

- [ ] **Check current Keycloak version**
  ```bash
  kubectl exec keycloak-0 -- /opt/keycloak/bin/kc.sh --version
  ```

- [ ] **Review Chart.yaml changes**
  ```bash
  diff charts/keycloak/Chart.yaml <(helm show chart keycloak/keycloak)
  ```

- [ ] **Schedule maintenance window** (production)

- [ ] **Notify users** (if applicable)

---

## Upgrade Procedures

### Standard Upgrade (Recommended)

**Step 1: Pre-Upgrade Health Check**
```bash
make -f make/ops/keycloak.mk kc-pre-upgrade-check
```

**Expected output:**
```
=== Pre-Upgrade Health Check ===
1. Checking Keycloak health endpoints...
  ✓ Ready
  ✓ Live

2. Checking database connectivity...
  ✓ Database OK

3. Listing current realms...
  master
  app-realm

Pre-upgrade check completed. Review results before proceeding.
```

**Step 2: Create Backups**
```bash
# Backup realms
make -f make/ops/keycloak.mk kc-backup-all-realms

# Backup database
make -f make/ops/keycloak.mk kc-db-backup

# Verify backups
ls -lh tmp/keycloak-backups/
```

**Step 3: Update values.yaml (if needed)**
```yaml
# Example: Update image version
image:
  tag: "26.4.2"

# Example: Update resource limits
resources:
  limits:
    memory: "2Gi"
```

**Step 4: Upgrade Helm Chart**
```bash
# Dry run first
helm upgrade keycloak charts/keycloak \
  -f values-prod-master-replica.yaml \
  --dry-run --debug

# Actual upgrade
helm upgrade keycloak charts/keycloak \
  -f values-prod-master-replica.yaml
```

**Step 5: Monitor Rollout**
```bash
# Watch pods restart
kubectl get pods -l app.kubernetes.io/name=keycloak -w

# Check rollout status
kubectl rollout status statefulset keycloak
```

**Step 6: Post-Upgrade Validation**
```bash
make -f make/ops/keycloak.mk kc-post-upgrade-check
```

**Expected output:**
```
=== Post-Upgrade Validation ===
1. Waiting for pods to be ready...
pod/keycloak-0 condition met
pod/keycloak-1 condition met
pod/keycloak-2 condition met

2. Checking health endpoints...
  ✓ Ready

3. Verifying realm integrity...
  master
  app-realm

Post-upgrade validation completed.
```

**Step 7: Functional Testing**
```bash
# Test Admin Console
open https://admin.auth.example.com

# Test authentication flow
make -f make/ops/keycloak.mk kc-cli CMD="get realms/master"

# Verify client connections
# (Test your applications using Keycloak)
```

### Blue-Green Upgrade (Zero Downtime)

For critical production environments:

**Step 1: Deploy new "green" environment**
```bash
helm install keycloak-green charts/keycloak \
  -f values-prod-master-replica.yaml \
  --set fullnameOverride=keycloak-green \
  --set image.tag=26.4.2
```

**Step 2: Migrate database**
```bash
# Create new database
kubectl exec postgres-0 -- psql -U postgres -c "CREATE DATABASE keycloak_green;"

# Copy data
kubectl exec postgres-0 -- pg_dump -U postgres keycloak | \
  kubectl exec -i postgres-0 -- psql -U postgres keycloak_green
```

**Step 3: Test green environment**
```bash
# Port-forward to test
kubectl port-forward svc/keycloak-green 8080:8080

# Validate functionality
curl http://localhost:8080/health/ready
```

**Step 4: Switch traffic**
```bash
# Update Ingress to point to green service
kubectl patch ingress keycloak --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "keycloak-green"}
]'
```

**Step 5: Monitor and rollback if needed**
```bash
# If issues, switch back to blue
kubectl patch ingress keycloak --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "keycloak"}
]'

# If successful, delete blue
helm uninstall keycloak
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
make -f make/ops/keycloak.mk kc-post-upgrade-check
```

### Manual Validation Checklist

- [ ] **Admin Console accessible**
  ```bash
  curl -I https://admin.auth.example.com
  # Expected: HTTP 200
  ```

- [ ] **All realms present**
  ```bash
  make -f make/ops/keycloak.mk kc-list-realms
  ```

- [ ] **User authentication works**
  - Test login via Admin Console
  - Test OIDC/SAML flow

- [ ] **Clustering operational** (if enabled)
  ```bash
  make -f make/ops/keycloak.mk kc-cluster-status
  # Should show all pods as cluster members
  ```

- [ ] **Metrics available** (if enabled)
  ```bash
  make -f make/ops/keycloak.mk kc-metrics
  ```

- [ ] **Database connections healthy**
  ```bash
  make -f make/ops/keycloak.mk kc-db-test
  ```

### Performance Validation

```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s https://auth.example.com/realms/master

# Monitor resource usage
kubectl top pod -l app.kubernetes.io/name=keycloak
```

---

## Rollback Procedures

### Automatic Rollback (Helm)

**If upgrade just completed:**
```bash
# Rollback to previous release
helm rollback keycloak

# Verify rollback
helm history keycloak
```

### Manual Rollback (Database Restore)

**If database was modified:**

**Step 1: Display rollback plan**
```bash
make -f make/ops/keycloak.mk kc-upgrade-rollback-plan
```

**Step 2: Scale down Keycloak**
```bash
kubectl scale statefulset keycloak --replicas=0
```

**Step 3: Restore database**
```bash
make -f make/ops/keycloak.mk kc-db-restore \
  FILE=tmp/keycloak-backups/db/keycloak-db-<timestamp>.sql
```

**Step 4: Rollback Helm chart**
```bash
helm rollback keycloak <revision>
```

**Step 5: Validate rollback**
```bash
make -f make/ops/keycloak.mk kc-post-upgrade-check
```

---

## Version-Specific Guides

### Upgrading from 25.x to 26.x

**Critical actions:**

1. **Update health probe ports to 9000**
   - Already done in chart templates
   - Verify in values.yaml if custom probes

2. **Migrate hostname v1 to v2**
   ```yaml
   # Remove:
   # KC_HOSTNAME, KC_HOSTNAME_STRICT

   # Add:
   KC_HOSTNAME_URL: "https://auth.example.com"
   KC_HOSTNAME_ADMIN_URL: "https://admin.auth.example.com"
   ```

3. **Upgrade PostgreSQL to 13+**
   ```bash
   # Before Keycloak upgrade!
   helm upgrade postgresql charts/postgresql --set image.tag=13.17
   ```

4. **Test in staging first** (highly recommended)

### Upgrading Chart from 0.2.x to 0.3.x

**New features in 0.3.x:**

1. **RBAC templates added**
   ```yaml
   rbac:
     create: true  # New feature
   ```

2. **Backup/upgrade values added**
   ```yaml
   backup:
     enabled: false  # Documentation only

   upgrade:
     enabled: false
   ```

3. **Seccomp profile added**
   ```yaml
   podSecurityContext:
     seccompProfile:
       type: RuntimeDefault  # New security feature
   ```

**Migration:**
- No breaking changes
- New features are opt-in or backward compatible
- Review new values sections

---

## Troubleshooting

### Upgrade fails: "hostname v1 not supported"

**Error:**
```
ERROR: KC_HOSTNAME configuration is no longer supported
```

**Solution:**
```yaml
# Remove old config from values.yaml
# keycloak:
#   extraEnv:
#     - name: KC_HOSTNAME
#       value: "auth.example.com"

# Add new config
keycloak:
  extraEnv:
    - name: KC_HOSTNAME_URL
      value: "https://auth.example.com"
```

### Pods stuck in CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods
# NAME         READY   STATUS             RESTARTS
# keycloak-0   0/1     CrashLoopBackOff   5
```

**Diagnosis:**
```bash
kubectl logs keycloak-0 --tail=50
```

**Common causes:**

1. **PostgreSQL version too old**
   ```
   Solution: Upgrade PostgreSQL to 13+
   ```

2. **Health probe failing (port 8080 vs 9000)**
   ```
   Solution: Verify probe ports in values.yaml
   ```

3. **Database connection failed**
   ```bash
   Solution: Check PostgreSQL credentials and connectivity
   kubectl exec keycloak-0 -- pg_isready -h postgres
   ```

### Rollback not working

**Error:**
```
Error: release keycloak has no previous revision
```

**Solution:**
```bash
# Manual rollback via database restore
make -f make/ops/keycloak.mk kc-upgrade-rollback-plan

# Follow the displayed steps
```

### Realm data missing after upgrade

**Symptoms:**
- Admin Console accessible but realms missing
- Users can't authenticate

**Solution:**
```bash
# Restore from backup
make -f make/ops/keycloak.mk kc-backup-restore \
  FILE=tmp/keycloak-backups/<latest-backup>

# Verify realms
make -f make/ops/keycloak.mk kc-list-realms
```

---

## Resources

- [Keycloak Upgrading Guide](https://www.keycloak.org/docs/latest/upgrading/)
- [Keycloak 26.x Release Notes](https://www.keycloak.org/docs/latest/release_notes/)
- [PostgreSQL Upgrade Guide](https://www.postgresql.org/docs/current/upgrading.html)
- [Chart README](../charts/keycloak/README.md)
- [Backup Guide](./keycloak-backup-guide.md)

---

**Last Updated:** 2025-11-27
