# Harbor Upgrade Guide

Comprehensive guide for upgrading Harbor container registry deployments with zero-downtime strategies and rollback procedures.

## Table of Contents

- [Overview](#overview)
- [Pre-Upgrade Preparation](#pre-upgrade-preparation)
- [Upgrade Procedures](#upgrade-procedures)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Rollback Procedures](#rollback-procedures)
- [Version-Specific Notes](#version-specific-notes)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Upgrade Types

| Upgrade Type | Example | Risk Level | Downtime | Rollback Complexity |
|--------------|---------|------------|----------|---------------------|
| **Patch** | 2.13.1 → 2.13.3 | Low | None | Easy |
| **Minor** | 2.12.x → 2.13.x | Medium | < 5 min | Moderate |
| **Major** | 2.x.x → 3.x.x | High | 15-30 min | Complex |
| **Chart** | v0.2.0 → v0.3.0 | Low-Medium | None | Easy |

### Compatibility Matrix

| Harbor Version | Chart Version | PostgreSQL | Redis | Kubernetes |
|----------------|---------------|------------|-------|------------|
| 2.13.x | 0.3.x | 12+ | 6+ | 1.24+ |
| 2.12.x | 0.2.x | 11+ | 6+ | 1.21+ |
| 2.11.x | 0.1.x | 11+ | 5+ | 1.21+ |

---

## Pre-Upgrade Preparation

### 1. Health Check

**Verify current deployment health:**

```bash
# Run pre-upgrade health check
make -f make/ops/harbor.mk harbor-pre-upgrade-check
```

**What it checks:**
- Pod status (all Running)
- Core component health endpoint
- Registry component health endpoint
- Database connectivity
- Redis connectivity

**Manual health check:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=harbor

# Check core health
kubectl exec -it harbor-core-0 -- \
  curl http://localhost:8080/api/v2.0/health

# Check registry health
kubectl exec -it harbor-registry-0 -- \
  curl http://localhost:5000/v2/

# Check database
make -f make/ops/harbor.mk harbor-db-test

# Check Redis
make -f make/ops/harbor.mk harbor-redis-test
```

### 2. Backup Before Upgrade

**⚠️ CRITICAL: Always backup before upgrading**

```bash
# 1. Backup configuration (projects, users, policies)
make -f make/ops/harbor.mk harbor-config-backup

# 2. Backup database
make -f make/ops/harbor.mk harbor-db-backup

# 3. Backup registry data (create snapshot)
make -f make/ops/harbor.mk harbor-registry-backup

# 4. Verify backups
ls -lh tmp/harbor-backups/config/
ls -lh tmp/harbor-backups/db/
kubectl get volumesnapshot -n harbor
```

**Tag backups:**
```bash
# Create timestamped backup directory
BACKUP_TAG="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
mkdir -p "tmp/harbor-backups/${BACKUP_TAG}"

# Copy backups to tagged directory
mv tmp/harbor-backups/config/* "tmp/harbor-backups/${BACKUP_TAG}/"
mv tmp/harbor-backups/db/*.sql "tmp/harbor-backups/${BACKUP_TAG}/"
```

### 3. Review Changelog

**Check for breaking changes:**

- [Harbor Release Notes](https://github.com/goharbor/harbor/releases)
- [Chart CHANGELOG.md](../CHANGELOG.md)

**Common breaking changes:**
- API endpoint changes
- Configuration parameter renames
- Database schema migrations
- Deprecated features removal

### 4. Test in Staging

**Deploy to staging environment first:**

```bash
# Deploy to staging namespace
helm upgrade harbor-staging charts/harbor \
  -n staging \
  -f values-staging.yaml \
  --set image.tag=v2.13.3

# Validate staging deployment
kubectl get pods -n staging
make -f make/ops/harbor.mk harbor-post-upgrade-check NAMESPACE=staging
```

### 5. Plan Maintenance Window

**Recommended windows:**
- **Patch upgrades**: No window needed (rolling update)
- **Minor upgrades**: 15-30 minute window
- **Major upgrades**: 1-2 hour window

**Notify stakeholders:**
- Schedule during low-traffic periods
- Announce maintenance window to users
- Prepare rollback plan

---

## Upgrade Procedures

### Method 1: Rolling Upgrade (Recommended)

**Zero-downtime upgrade for patch/minor versions:**

```bash
# Step 1: Update Helm repository
helm repo update

# Step 2: Upgrade chart (with rolling update)
helm upgrade harbor charts/harbor \
  -f values.yaml \
  --wait \
  --timeout=10m

# Step 3: Run database migrations (if needed)
make -f make/ops/harbor.mk harbor-db-migrate

# Step 4: Verify deployment
make -f make/ops/harbor.mk harbor-post-upgrade-check
```

**Rolling update behavior:**
- Core: New pods created before old ones terminated
- Registry: Brief interruption during pod replacement
- Database: No changes (external database)

### Method 2: Blue-Green Upgrade

**For major version upgrades with zero downtime:**

```bash
# Step 1: Deploy new "green" environment
helm install harbor-green charts/harbor \
  -f values.yaml \
  --set image.core.tag=v2.13.0 \
  --set image.registry.tag=v2.13.0 \
  --set fullnameOverride=harbor-green

# Step 2: Run database migrations on green
kubectl exec -it harbor-green-core-0 -- harbor_core migrate

# Step 3: Validate green deployment
kubectl exec -it harbor-green-core-0 -- \
  curl http://localhost:8080/api/v2.0/health

# Step 4: Switch traffic (update Ingress/Service)
kubectl patch ingress harbor-ingress -p \
  '{"spec":{"rules":[{"host":"harbor.example.com","http":{"paths":[{"backend":{"service":{"name":"harbor-green"}}}]}}]}}'

# Step 5: Monitor green deployment
make -f make/ops/harbor.mk harbor-health

# Step 6: Decommission blue (after validation)
helm uninstall harbor  # Old blue deployment
```

### Method 3: Maintenance Window Upgrade

**For major version upgrades with planned downtime:**

```bash
# Step 1: Enable maintenance mode (if supported)
# Update Ingress to show maintenance page

# Step 2: Scale down components
kubectl scale deployment harbor-core --replicas=0
kubectl scale deployment harbor-registry --replicas=0

# Step 3: Backup database
make -f make/ops/harbor.mk harbor-db-backup

# Step 4: Upgrade chart
helm upgrade harbor charts/harbor -f values.yaml

# Step 5: Run database migrations
make -f make/ops/harbor.mk harbor-db-migrate

# Step 6: Scale up components
kubectl scale deployment harbor-core --replicas=1
kubectl scale deployment harbor-registry --replicas=1

# Step 7: Validate upgrade
make -f make/ops/harbor.mk harbor-post-upgrade-check

# Step 8: Disable maintenance mode
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Run post-upgrade check
make -f make/ops/harbor.mk harbor-post-upgrade-check
```

**What it checks:**
- All pods running and ready
- Deployments available
- Harbor version
- Component health
- Projects accessible

### Manual Validation Checklist

**1. Component Status:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=harbor

# Expected: All pods Running/Ready
# harbor-core-0           1/1     Running   0          5m
# harbor-registry-0       1/1     Running   0          5m
```

**2. Harbor Version:**
```bash
# Check version via API
kubectl exec -it harbor-core-0 -- \
  curl -s http://localhost:8080/api/v2.0/systeminfo | jq '.harbor_version'

# Expected: "v2.13.3"
```

**3. Project Access:**
```bash
make -f make/ops/harbor.mk harbor-projects

# Verify all projects present
```

**4. Registry Functionality:**
```bash
# Test image push
docker tag busybox:latest harbor.example.com/library/test:latest
docker push harbor.example.com/library/test:latest

# Test image pull
docker pull harbor.example.com/library/test:latest
```

**5. UI Access:**
```bash
# Port-forward
make -f make/ops/harbor.mk harbor-port-forward

# Access http://localhost:8080
# Login and verify UI functionality
```

**6. Replication (if configured):**
```bash
# Check replication policies
kubectl exec -it harbor-core-0 -- \
  curl -s http://localhost:8080/api/v2.0/replication/policies | jq '.'
```

**7. Vulnerability Scanning (if enabled):**
```bash
# Trigger a scan
# Verify scan results accessible via UI
```

---

## Rollback Procedures

### When to Rollback

- Upgrade validation fails
- Critical functionality broken
- Performance degradation
- Database migration errors
- Registry images not accessible

### Method 1: Helm Rollback (Fast)

**Rollback to previous chart release:**

```bash
# Display rollback plan
make -f make/ops/harbor.mk harbor-upgrade-rollback

# Execute Helm rollback
helm rollback harbor

# Verify rollback
kubectl exec -it harbor-core-0 -- \
  curl http://localhost:8080/api/v2.0/systeminfo | jq '.harbor_version'
make -f make/ops/harbor.mk harbor-health
```

**Helm rollback behavior:**
- Reverts to previous Helm release configuration
- Recreates pods with old image versions
- Does NOT revert database schema changes

### Method 2: Database Restore (Complete)

**Restore database to pre-upgrade state:**

```bash
# Step 1: Scale down components
kubectl scale deployment harbor-core --replicas=0
kubectl scale deployment harbor-registry --replicas=0

# Step 2: Restore database from backup
make -f make/ops/harbor.mk harbor-db-restore \
  FILE=tmp/harbor-backups/pre-upgrade-YYYYMMDD-HHMMSS/harbor-db-*.sql

# Step 3: Helm rollback to previous chart
helm rollback harbor

# Step 4: Scale up components
kubectl scale deployment harbor-core --replicas=1
kubectl scale deployment harbor-registry --replicas=1

# Step 5: Verify rollback
make -f make/ops/harbor.mk harbor-health
make -f make/ops/harbor.mk harbor-projects
```

### Method 3: Full Disaster Recovery

**Complete restore from backups:**

```bash
# Step 1: Uninstall broken deployment
helm uninstall harbor

# Step 2: Reinstall previous chart version
helm install harbor charts/harbor \
  -f values.yaml \
  --version 0.2.0  # Previous working version

# Step 3: Restore database
make -f make/ops/harbor.mk harbor-db-restore \
  FILE=tmp/harbor-backups/pre-upgrade-*/harbor-db-*.sql

# Step 4: Restore registry data (if needed)
# Using VolumeSnapshot or S3 sync

# Step 5: Verify full recovery
make -f make/ops/harbor.mk harbor-health
make -f make/ops/harbor.mk harbor-projects
```

---

## Version-Specific Notes

### Harbor 2.13.x

**Key Features:**
- Enhanced security scanning
- Improved replication performance
- Better OIDC support

**Breaking Changes:**
- None (backward compatible with 2.12.x)

**Migration Notes:**
- Database migrations automatic
- No configuration changes required

### Harbor 2.12.x → 2.13.x

**Upgrade Path:**
```bash
helm upgrade harbor charts/harbor --set image.core.tag=v2.13.3
```

**Post-upgrade:**
- Verify replication policies still active
- Test vulnerability scanning
- Check project quotas

### Harbor 2.11.x → 2.12.x

**Breaking Changes:**
- API endpoint changes for some v1.0 endpoints
- Removed deprecated configuration options

**Migration:**
```bash
# Update API clients to use v2.0 endpoints
# Review and update any custom scripts
```

### Harbor 2.x → 3.x (Future)

**⚠️ MAJOR UPGRADE - Requires careful planning**

**Expected breaking changes:**
- Complete API restructure
- Database schema major changes
- Configuration format changes

**Migration Path:**
1. Read Harbor 3.0 Migration Guide
2. Test extensively in staging
3. Plan 2-4 hour maintenance window
4. Backup extensively before upgrade

---

## Best Practices

### 1. Always Test in Staging

**Never upgrade production directly:**
```bash
# Deploy staging environment
helm install harbor-staging charts/harbor -n staging -f values-staging.yaml

# Test upgrade in staging
helm upgrade harbor-staging charts/harbor --set image.tag=v2.13.3

# Validate for 24-48 hours before production upgrade
```

### 2. Incremental Upgrades

**Prefer small, frequent upgrades:**
- Patch upgrades: Every 1-2 months
- Minor upgrades: Every 3-6 months
- Major upgrades: Plan carefully (6-12 months)

**Avoid skipping versions:**
- ❌ Bad: 2.11.0 → 2.13.0 (skip 2.12.x)
- ✅ Good: 2.11.0 → 2.12.3 → 2.13.3

### 3. Monitor After Upgrade

**Post-upgrade monitoring (48 hours):**
```bash
# Watch pod status
kubectl get pods -l app.kubernetes.io/name=harbor -w

# Monitor logs
kubectl logs -f -l app.kubernetes.io/component=core
kubectl logs -f -l app.kubernetes.io/component=registry

# Check metrics
kubectl top pods -l app.kubernetes.io/name=harbor
```

### 4. Document Upgrade

**Maintain upgrade log:**
```markdown
## Harbor Upgrade Log

### 2025-11-27: 2.12.3 → 2.13.3
- **Performed by:** DevOps Team
- **Downtime:** None (rolling update)
- **Issues:** None
- **Rollback:** Not required
- **Notes:** Replication performance improved significantly
```

---

## Troubleshooting

### Database Migration Failures

**Problem: `harbor_core migrate` fails**

**Solution:**
```bash
# Check migration logs
kubectl logs harbor-core-0 | grep migration

# Manually run migration with verbose output
kubectl exec -it harbor-core-0 -- harbor_core migrate --verbose
```

### Registry Images Not Accessible

**Problem: Images not pullable after upgrade**

**Solution:**
```bash
# Check registry logs
kubectl logs -l app.kubernetes.io/component=registry

# Verify registry storage mount
kubectl exec -it harbor-registry-0 -- ls -la /storage

# Test registry health
kubectl exec -it harbor-registry-0 -- \
  curl http://localhost:5000/v2/
```

### Replication Stopped Working

**Problem: Replication policies not executing**

**Solution:**
```bash
# Check replication policies
kubectl exec -it harbor-core-0 -- \
  curl http://localhost:8080/api/v2.0/replication/policies

# Restart core component
kubectl rollout restart deployment harbor-core

# Manually trigger replication
# Via Harbor UI: Administration → Replication → Execute
```

### Performance Degradation

**Problem: Harbor slower after upgrade**

**Solution:**
```bash
# Check resource usage
kubectl top pods -l app.kubernetes.io/name=harbor

# Increase resources if needed
helm upgrade harbor charts/harbor \
  --set core.resources.limits.cpu=2000m \
  --set core.resources.limits.memory=2Gi

# Check database performance
kubectl exec -it postgresql-0 -- \
  psql -U harbor -d harbor -c "SELECT * FROM pg_stat_activity;"
```

---

## Additional Resources

- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor Release Notes](https://github.com/goharbor/harbor/releases)
- [Harbor Backup & Recovery Guide](harbor-backup-guide.md)
- [Chart README](../charts/harbor/README.md)

---

**Last Updated:** 2025-11-27
