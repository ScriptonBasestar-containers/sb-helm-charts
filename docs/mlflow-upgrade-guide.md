# MLflow Upgrade Guide

Comprehensive guide for upgrading MLflow tracking server deployments with minimal disruption and rollback procedures.

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
| **Patch** | 2.9.1 → 2.9.2 | Low | < 2 min | Easy |
| **Minor** | 2.8.x → 2.9.x | Medium | 5-10 min | Moderate |
| **Major** | 1.x.x → 2.x.x | High | 15-30 min | Complex |
| **Chart** | v0.2.0 → v0.3.0 | Low-Medium | < 2 min | Easy |

### Compatibility Matrix

| MLflow Version | Chart Version | PostgreSQL | Python | Kubernetes |
|----------------|---------------|------------|--------|------------|
| 2.9.x | 0.3.x | 12+ (optional) | 3.8-3.11 | 1.24+ |
| 2.8.x | 0.2.x | 11+ (optional) | 3.7-3.10 | 1.21+ |
| 2.7.x | 0.1.x | 11+ (optional) | 3.7-3.10 | 1.21+ |

**Note:** PostgreSQL is optional. Chart supports SQLite for development/small deployments.

---

## Pre-Upgrade Preparation

### 1. Health Check

**Verify current deployment health:**

```bash
# Run pre-upgrade health check
make -f make/ops/mlflow.mk mlflow-pre-upgrade-check
```

**What it checks:**
- Pod status (Running)
- MLflow service health endpoint
- Database connection (PostgreSQL or SQLite)
- MLflow client functionality

**Manual health check:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=mlflow

# Check MLflow service
kubectl exec -it mlflow-0 -- curl http://localhost:5000/health

# Test MLflow client
kubectl exec -it mlflow-0 -- \
  python -c "import mlflow; print(mlflow.__version__)"

# List experiments
kubectl exec -it mlflow-0 -- \
  mlflow experiments search --max-results 5
```

### 2. Backup Before Upgrade

**⚠️ CRITICAL: Always backup before upgrading**

```bash
# 1. Backup experiments metadata
make -f make/ops/mlflow.mk mlflow-experiments-backup

# 2. Backup database (if using external PostgreSQL)
make -f make/ops/mlflow.mk mlflow-db-backup

# 3. Backup artifacts
# For S3/MinIO:
aws s3 sync s3://mlflow-artifacts ./tmp/mlflow-backups/artifacts/$(date +%Y%m%d-%H%M%S)/
# For PVC: create snapshot

# 4. Verify backups
ls -lh tmp/mlflow-backups/experiments/
ls -lh tmp/mlflow-backups/db/
```

**Tag backups:**
```bash
# Create timestamped backup directory
BACKUP_TAG="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
mkdir -p "tmp/mlflow-backups/${BACKUP_TAG}"

# Copy backups to tagged directory
cp -r tmp/mlflow-backups/experiments/* "tmp/mlflow-backups/${BACKUP_TAG}/"
cp tmp/mlflow-backups/db/*.sql "tmp/mlflow-backups/${BACKUP_TAG}/" 2>/dev/null || true
```

### 3. Review Changelog

**Check for breaking changes:**

- [MLflow Release Notes](https://github.com/mlflow/mlflow/releases)
- [Chart CHANGELOG.md](../CHANGELOG.md)

**Common breaking changes:**
- API changes (tracking, models registry)
- Database schema migrations
- Python version requirements
- Dependency updates

### 4. Test in Staging

**Deploy to staging environment first:**

```bash
# Deploy to staging namespace
helm upgrade mlflow-staging charts/mlflow \
  -n staging \
  -f values-staging.yaml \
  --set image.tag=3.11-slim

# Validate staging deployment
kubectl get pods -n staging
make -f make/ops/mlflow.mk mlflow-post-upgrade-check NAMESPACE=staging
```

### 5. Plan Maintenance Window

**Recommended windows:**
- **Patch upgrades**: 5 minute window
- **Minor upgrades**: 15 minute window
- **Major upgrades**: 30-60 minute window

**Note:** MLflow upgrades typically require brief downtime for database migrations.

---

## Upgrade Procedures

### Method 1: Standard Upgrade (Recommended)

**Upgrade procedure with database migration:**

```bash
# Step 1: Update Helm repository
helm repo update

# Step 2: Scale down to prevent writes during migration
kubectl scale deployment mlflow --replicas=0

# Step 3: Backup database
make -f make/ops/mlflow.mk mlflow-db-backup

# Step 4: Upgrade chart
helm upgrade mlflow charts/mlflow \
  -f values.yaml \
  --wait \
  --timeout=10m

# Step 5: Run database migrations
make -f make/ops/mlflow.mk mlflow-db-upgrade

# Step 6: Scale up
kubectl scale deployment mlflow --replicas=1

# Step 7: Verify deployment
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

### Method 2: Blue-Green Upgrade

**For zero-downtime upgrades (requires dual environment):**

```bash
# Step 1: Deploy new "green" environment
helm install mlflow-green charts/mlflow \
  -f values.yaml \
  --set fullnameOverride=mlflow-green

# Step 2: Run database migrations on green
kubectl exec -it mlflow-green-0 -- \
  mlflow db upgrade $MLFLOW_BACKEND_STORE_URI

# Step 3: Validate green deployment
kubectl exec -it mlflow-green-0 -- \
  curl http://localhost:5000/health

kubectl exec -it mlflow-green-0 -- \
  mlflow experiments search --max-results 5

# Step 4: Switch traffic (update Service selector or Ingress)
kubectl patch service mlflow -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"mlflow-green"}}}'

# Step 5: Monitor green deployment
make -f make/ops/mlflow.mk mlflow-health

# Step 6: Decommission blue (after validation period)
helm uninstall mlflow  # Old blue deployment
```

### Method 3: In-Place Upgrade (Quick)

**For patch upgrades with minimal changes:**

```bash
# Step 1: Upgrade chart (rolling update)
helm upgrade mlflow charts/mlflow \
  -f values.yaml \
  --set image.tag=3.11-slim

# Step 2: Run database migrations (if needed)
make -f make/ops/mlflow.mk mlflow-db-upgrade

# Step 3: Verify deployment
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Run post-upgrade check
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

**What it checks:**
- Pod status (Running/Ready)
- Deployment available
- MLflow version
- Service health
- Experiment access

### Manual Validation Checklist

**1. Component Status:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=mlflow

# Expected: Pod Running/Ready
# mlflow-0           1/1     Running   0          2m
```

**2. MLflow Version:**
```bash
kubectl exec -it mlflow-0 -- \
  python -c "import mlflow; print(f'MLflow version: {mlflow.__version__}')"

# Expected: MLflow version: 2.9.2
```

**3. Service Health:**
```bash
kubectl exec -it mlflow-0 -- curl http://localhost:5000/health

# Expected: {"status": "ok"}
```

**4. Experiment Access:**
```bash
kubectl exec -it mlflow-0 -- \
  mlflow experiments search --max-results 5

# Verify experiments are listed
```

**5. Model Registry:**
```bash
kubectl exec -it mlflow-0 -- \
  mlflow models list --max-results 5

# Verify registered models are accessible
```

**6. UI Access:**
```bash
# Port-forward
make -f make/ops/mlflow.mk mlflow-port-forward

# Access http://localhost:5000
# Verify UI loads and experiments are visible
```

**7. Test Run Logging:**
```bash
# Create test run
kubectl exec -it mlflow-0 -- python3 <<EOF
import mlflow
mlflow.set_tracking_uri("http://localhost:5000")
with mlflow.start_run():
    mlflow.log_param("test_param", "upgrade_test")
    mlflow.log_metric("test_metric", 1.0)
print("Test run logged successfully")
EOF
```

---

## Rollback Procedures

### When to Rollback

- Database migration fails
- Experiments not accessible
- Model registry errors
- Performance degradation
- Critical functionality broken

### Method 1: Helm Rollback (Fast)

**Rollback to previous chart release:**

```bash
# Display rollback plan
make -f make/ops/mlflow.mk mlflow-upgrade-rollback

# Execute Helm rollback
helm rollback mlflow

# Verify rollback
kubectl exec -it mlflow-0 -- \
  python -c "import mlflow; print(mlflow.__version__)"
make -f make/ops/mlflow.mk mlflow-health
```

**Note:** Helm rollback reverts chart but NOT database schema. May need database restore.

### Method 2: Database Restore (Complete)

**Restore database to pre-upgrade state:**

```bash
# Step 1: Scale down
kubectl scale deployment mlflow --replicas=0

# Step 2: Restore database from backup
make -f make/ops/mlflow.mk mlflow-db-restore \
  FILE=tmp/mlflow-backups/pre-upgrade-*/mlflow-db-*.sql

# Step 3: Helm rollback to previous chart
helm rollback mlflow

# Step 4: Scale up
kubectl scale deployment mlflow --replicas=1

# Step 5: Verify rollback
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

### Method 3: Full Disaster Recovery

**Complete restore from backups:**

```bash
# Step 1: Uninstall broken deployment
helm uninstall mlflow

# Step 2: Reinstall previous chart version
helm install mlflow charts/mlflow \
  -f values.yaml \
  --version 0.2.0  # Previous working version

# Step 3: Restore database
make -f make/ops/mlflow.mk mlflow-db-restore \
  FILE=tmp/mlflow-backups/pre-upgrade-*/mlflow-db-*.sql

# Step 4: Restore artifacts (if needed)
aws s3 sync ./tmp/mlflow-backups/artifacts/* s3://mlflow-artifacts/

# Step 5: Verify full recovery
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

---

## Version-Specific Notes

### MLflow 2.9.x

**Key Features:**
- Enhanced model registry
- Improved artifact logging
- Better experiment organization

**Breaking Changes:**
- None (backward compatible with 2.8.x)

**Migration Notes:**
- Database migrations automatic
- No code changes required

### MLflow 2.8.x → 2.9.x

**Upgrade Path:**
```bash
helm upgrade mlflow charts/mlflow
make -f make/ops/mlflow.mk mlflow-db-upgrade
```

**Post-upgrade:**
- Verify experiment access
- Test model registry
- Check artifact logging

### MLflow 2.7.x → 2.8.x

**Breaking Changes:**
- Some API endpoints updated
- Database schema changes

**Migration:**
```bash
# Run database upgrade
make -f make/ops/mlflow.mk mlflow-db-upgrade

# Update client code if using deprecated APIs
```

### MLflow 1.x → 2.x

**⚠️ MAJOR UPGRADE - Requires careful planning**

**Breaking changes:**
- Complete API restructure
- Database schema major changes
- Python 3.8+ required

**Migration Path:**
1. Read [MLflow 2.0 Migration Guide](https://www.mlflow.org/docs/latest/migration.html)
2. Update all client code to MLflow 2.x APIs
3. Test extensively in staging
4. Plan 1-2 hour maintenance window
5. Backup extensively before upgrade

---

## Best Practices

### 1. Always Test in Staging

**Never upgrade production directly:**
```bash
# Deploy staging environment
helm install mlflow-staging charts/mlflow -n staging -f values-staging.yaml

# Test upgrade in staging
helm upgrade mlflow-staging charts/mlflow

# Validate for 24 hours before production upgrade
```

### 2. Incremental Upgrades

**Prefer small, frequent upgrades:**
- Patch upgrades: Every 1-2 months
- Minor upgrades: Every 3-4 months
- Major upgrades: Plan carefully

**Avoid skipping versions:**
- ❌ Bad: 2.7.0 → 2.9.0 (skip 2.8.x)
- ✅ Good: 2.7.0 → 2.8.3 → 2.9.2

### 3. Monitor After Upgrade

**Post-upgrade monitoring (24 hours):**
```bash
# Watch pod status
kubectl get pods -l app.kubernetes.io/name=mlflow -w

# Monitor logs
kubectl logs -f mlflow-0

# Check resource usage
kubectl top pod mlflow-0
```

### 4. Document Upgrade

**Maintain upgrade log:**
```markdown
## MLflow Upgrade Log

### 2025-11-27: 2.8.3 → 2.9.2
- **Performed by:** ML Team
- **Downtime:** 5 minutes (database migration)
- **Issues:** None
- **Rollback:** Not required
- **Notes:** Model registry performance improved
```

---

## Troubleshooting

### Database Migration Failures

**Problem: `mlflow db upgrade` fails**

**Solution:**
```bash
# Check migration logs
kubectl logs mlflow-0 | grep migration

# Manually run migration with verbose output
kubectl exec -it mlflow-0 -- \
  mlflow db upgrade $MLFLOW_BACKEND_STORE_URI --verbose
```

### Experiments Not Accessible

**Problem: Experiments not loading after upgrade**

**Solution:**
```bash
# Check database connection
kubectl exec -it mlflow-0 -- \
  python -c "import mlflow; mlflow.set_tracking_uri('http://localhost:5000'); print(mlflow.search_experiments())"

# Verify database schema
kubectl exec -it postgresql-0 -- \
  psql -U mlflow -d mlflow -c "\dt"

# Restart MLflow
kubectl rollout restart deployment mlflow
```

### Artifacts Not Loading

**Problem: Model artifacts not accessible**

**Solution:**
```bash
# Check artifact store configuration
kubectl exec -it mlflow-0 -- env | grep MLFLOW_ARTIFACT

# Verify S3/MinIO connectivity
kubectl exec -it mlflow-0 -- \
  aws s3 ls s3://mlflow-artifacts

# Check PVC mount
kubectl exec -it mlflow-0 -- ls -la /mlflow/artifacts
```

### Performance Degradation

**Problem: MLflow slower after upgrade**

**Solution:**
```bash
# Check resource usage
kubectl top pod mlflow-0

# Increase resources
helm upgrade mlflow charts/mlflow \
  --set resources.limits.cpu=2000m \
  --set resources.limits.memory=2Gi

# Check database performance
kubectl exec -it postgresql-0 -- \
  psql -U mlflow -d mlflow -c "SELECT * FROM pg_stat_activity;"
```

---

## Additional Resources

- [MLflow Documentation](https://www.mlflow.org/docs/latest/index.html)
- [MLflow Release Notes](https://github.com/mlflow/mlflow/releases)
- [MLflow Backup & Recovery Guide](mlflow-backup-guide.md)
- [Chart README](../charts/mlflow/README.md)

---

**Last Updated:** 2025-11-27
