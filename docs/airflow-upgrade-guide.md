# Airflow Upgrade Guide

Comprehensive guide for upgrading Apache Airflow deployments with zero-downtime strategies and rollback procedures.

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
| **Patch** | 2.8.1 → 2.8.2 | Low | None | Easy |
| **Minor** | 2.7.x → 2.8.x | Medium | < 5 min | Moderate |
| **Major** | 1.10.x → 2.x.x | High | 15-30 min | Complex |
| **Chart** | v0.1.0 → v0.2.0 | Low-Medium | None | Easy |

### Compatibility Matrix

| Airflow Version | Chart Version | PostgreSQL | Python | Kubernetes |
|-----------------|---------------|------------|--------|------------|
| 2.8.x | 0.3.x | 12+ | 3.8-3.11 | 1.24+ |
| 2.7.x | 0.2.x | 11+ | 3.7-3.10 | 1.21+ |
| 2.6.x | 0.1.x | 11+ | 3.7-3.10 | 1.21+ |

---

## Pre-Upgrade Preparation

### 1. Health Check

**Verify current deployment health:**

```bash
# Run pre-upgrade health check
make -f make/ops/airflow.mk af-pre-upgrade-check
```

**What it checks:**
- Webserver health endpoint
- Scheduler heartbeat
- Database connectivity
- DAG parsing status
- Task execution capability

**Manual health check:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=airflow

# Check webserver health
kubectl exec -it airflow-webserver-0 -- curl http://localhost:8080/health

# Check scheduler heartbeat
kubectl logs -l app.kubernetes.io/component=scheduler --tail=50 | grep "heartbeat"

# Check database connection
make -f make/ops/airflow.mk airflow-db-check
```

### 2. Backup Before Upgrade

**⚠️ CRITICAL: Always backup before upgrading**

```bash
# 1. Backup metadata (connections, variables)
make -f make/ops/airflow.mk af-backup-metadata

# 2. Backup DAGs
make -f make/ops/airflow.mk af-backup-dags

# 3. Backup database
make -f make/ops/airflow.mk af-db-backup

# 4. Verify backups
ls -lh tmp/airflow-backups/metadata/
ls -lh tmp/airflow-backups/dags/
ls -lh tmp/airflow-backups/db/
```

**Tag backups:**
```bash
# Create timestamped backup directory
BACKUP_TAG="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
mkdir -p "tmp/airflow-backups/${BACKUP_TAG}"

# Move backups to tagged directory
mv tmp/airflow-backups/metadata/*.yaml "tmp/airflow-backups/${BACKUP_TAG}/"
mv tmp/airflow-backups/db/*.sql "tmp/airflow-backups/${BACKUP_TAG}/"
```

### 3. Review Changelog

**Check for breaking changes:**

- [Apache Airflow Release Notes](https://airflow.apache.org/docs/apache-airflow/stable/release_notes.html)
- [Chart CHANGELOG.md](../CHANGELOG.md)

**Common breaking changes:**
- Database schema changes (require migrations)
- Configuration parameter renames
- Executor behavior changes
- API endpoint changes
- Deprecated features removal

### 4. Test in Staging

**Deploy to staging environment first:**

```bash
# Deploy to staging namespace
helm upgrade airflow-staging sb-charts/airflow \
  -n staging \
  -f values-staging.yaml \
  --set image.tag=2.8.2

# Validate staging deployment
kubectl get pods -n staging
make -f make/ops/airflow.mk af-post-upgrade-check NAMESPACE=staging
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
helm upgrade airflow sb-charts/airflow \
  -f values.yaml \
  --set image.tag=2.8.2 \
  --wait \
  --timeout=10m

# Step 3: Run database migrations (if needed)
make -f make/ops/airflow.mk af-db-upgrade

# Step 4: Verify deployment
make -f make/ops/airflow.mk af-post-upgrade-check
```

**Rolling update behavior:**
- Webserver: New pods created before old ones terminated
- Scheduler: Brief interruption (task execution continues)
- Triggerer: Seamless transition

### Method 2: Blue-Green Upgrade

**For major version upgrades with zero downtime:**

```bash
# Step 1: Deploy new "green" environment
helm install airflow-green sb-charts/airflow \
  -f values.yaml \
  --set image.tag=2.8.0 \
  --set fullnameOverride=airflow-green

# Step 2: Run database migrations on green
kubectl exec -it airflow-green-webserver-0 -- airflow db migrate

# Step 3: Validate green deployment
kubectl exec -it airflow-green-webserver-0 -- airflow version
kubectl exec -it airflow-green-webserver-0 -- airflow dags list

# Step 4: Switch traffic (update Ingress/Service)
kubectl patch ingress airflow-ingress -p '{"spec":{"rules":[{"host":"airflow.example.com","http":{"paths":[{"backend":{"service":{"name":"airflow-green-webserver"}}}]}}]}}'

# Step 5: Monitor green deployment
make -f make/ops/airflow.mk airflow-health

# Step 6: Decommission blue (after validation)
helm uninstall airflow  # Old blue deployment
```

### Method 3: Maintenance Window Upgrade

**For major version upgrades with planned downtime:**

```bash
# Step 1: Pause DAGs (prevent new task runs)
kubectl exec -it airflow-webserver-0 -- \
  airflow dags pause-all

# Step 2: Wait for running tasks to complete
kubectl exec -it airflow-webserver-0 -- \
  airflow tasks states-for-dag-run <dag_id> <run_id>

# Step 3: Scale down components
kubectl scale deployment airflow-webserver --replicas=0
kubectl scale deployment airflow-scheduler --replicas=0

# Step 4: Backup database
make -f make/ops/airflow.mk af-db-backup

# Step 5: Upgrade chart
helm upgrade airflow sb-charts/airflow -f values.yaml

# Step 6: Run database migrations
make -f make/ops/airflow.mk af-db-upgrade

# Step 7: Scale up components
kubectl scale deployment airflow-webserver --replicas=2
kubectl scale deployment airflow-scheduler --replicas=2

# Step 8: Unpause DAGs
kubectl exec -it airflow-webserver-0 -- \
  airflow dags unpause-all

# Step 9: Validate upgrade
make -f make/ops/airflow.mk af-post-upgrade-check
```

---

## Post-Upgrade Validation

### Automated Validation

```bash
# Run post-upgrade check
make -f make/ops/airflow.mk af-post-upgrade-check
```

**What it checks:**
- All pods running and ready
- Webserver health endpoint
- Scheduler logs for errors
- DAG parsing status
- Database connectivity

### Manual Validation Checklist

**1. Component Status:**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=airflow

# Expected output: All pods Running/Ready
# airflow-webserver-0         2/2     Running   0          5m
# airflow-scheduler-0         1/1     Running   0          5m
# airflow-triggerer-0         1/1     Running   0          5m
```

**2. Airflow Version:**
```bash
make -f make/ops/airflow.mk airflow-version

# Expected: New version number
# Airflow version: 2.8.2
```

**3. DAG Integrity:**
```bash
make -f make/ops/airflow.mk airflow-dag-list

# Verify all DAGs present
# Check for import errors
kubectl exec -it airflow-webserver-0 -- \
  airflow dags list-import-errors
```

**4. Connections and Variables:**
```bash
kubectl exec -it airflow-webserver-0 -- airflow connections list
kubectl exec -it airflow-webserver-0 -- airflow variables list
```

**5. Test Task Execution:**
```bash
# Trigger test DAG
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_bash_operator

# Monitor task execution
kubectl exec -it airflow-webserver-0 -- \
  airflow tasks states-for-dag-run example_bash_operator <run_id>
```

**6. UI Access:**
```bash
# Port-forward webserver
make -f make/ops/airflow.mk airflow-port-forward

# Access http://localhost:8080
# Login and verify UI functionality
```

**7. Logs and Monitoring:**
```bash
# Check webserver logs
make -f make/ops/airflow.mk airflow-webserver-logs | tail -50

# Check scheduler logs
make -f make/ops/airflow.mk airflow-scheduler-logs | tail -50

# Look for errors or warnings
```

---

## Rollback Procedures

### When to Rollback

- Upgrade validation fails
- Critical functionality broken
- Performance degradation
- Database migration errors
- DAG parsing failures

### Method 1: Helm Rollback (Fast)

**Rollback to previous chart release:**

```bash
# Step 1: Display rollback plan
make -f make/ops/airflow.mk af-upgrade-rollback-plan

# Step 2: Execute Helm rollback
helm rollback airflow

# Step 3: Verify rollback
make -f make/ops/airflow.mk airflow-version
make -f make/ops/airflow.mk airflow-health

# Step 4: Check component status
kubectl get pods -l app.kubernetes.io/name=airflow
```

**Helm rollback behavior:**
- Reverts to previous Helm release configuration
- Recreates pods with old image version
- Does NOT revert database schema changes

### Method 2: Database Restore (Complete)

**Restore database to pre-upgrade state:**

```bash
# Step 1: Scale down components (prevent writes)
kubectl scale deployment airflow-webserver --replicas=0
kubectl scale deployment airflow-scheduler --replicas=0

# Step 2: Restore database from backup
make -f make/ops/airflow.mk af-db-restore \
  FILE=tmp/airflow-backups/pre-upgrade-20251127-020000/airflow-db-20251127-020000.sql

# Step 3: Helm rollback to previous chart
helm rollback airflow

# Step 4: Scale up components
kubectl scale deployment airflow-webserver --replicas=2
kubectl scale deployment airflow-scheduler --replicas=2

# Step 5: Verify rollback
make -f make/ops/airflow.mk airflow-version
make -f make/ops/airflow.mk airflow-dag-list
```

### Method 3: Full Disaster Recovery

**Complete restore from backups:**

```bash
# Step 1: Uninstall broken deployment
helm uninstall airflow

# Step 2: Reinstall previous chart version
helm install airflow sb-charts/airflow \
  -f values.yaml \
  --version 0.2.0  # Previous working version

# Step 3: Restore database
make -f make/ops/airflow.mk af-db-restore \
  FILE=tmp/airflow-backups/pre-upgrade-YYYYMMDD-HHMMSS/airflow-db-*.sql

# Step 4: Restore DAGs
kubectl cp tmp/airflow-backups/dags-YYYYMMDD-HHMMSS/ \
  airflow-webserver-0:/opt/airflow/dags/

# Step 5: Restore metadata
kubectl cp tmp/airflow-backups/metadata/connections.json airflow-webserver-0:/tmp/
kubectl exec -it airflow-webserver-0 -- \
  airflow connections import /tmp/connections.json

# Step 6: Verify full recovery
make -f make/ops/airflow.mk airflow-health
make -f make/ops/airflow.mk airflow-dag-list
```

---

## Version-Specific Notes

### Airflow 2.8.x

**Key Features:**
- Improved KubernetesExecutor performance
- Enhanced security features
- Better DAG serialization

**Breaking Changes:**
- None (backward compatible with 2.7.x)

**Migration Notes:**
- Database migrations automatic (via init container)
- No configuration changes required

### Airflow 2.7.x → 2.8.x

**Upgrade Path:**
```bash
helm upgrade airflow sb-charts/airflow --set image.tag=2.8.2
```

**Post-upgrade:**
- Verify KubernetesExecutor pod creation
- Test DAG imports
- Check task execution

### Airflow 2.6.x → 2.7.x

**Breaking Changes:**
- `sql_alchemy_conn` renamed to `database.sql_alchemy_conn`
- Some deprecated operators removed

**Migration:**
```bash
# Update values.yaml if using custom config
airflow:
  config:
    database:
      sql_alchemy_conn: "postgresql://..."
```

### Airflow 1.10.x → 2.x.x

**⚠️ MAJOR UPGRADE - Requires careful planning**

**Breaking Changes:**
- Complete configuration restructure
- RBAC enabled by default
- Removed SubDAGs (use TaskGroups)
- Executor configuration changes

**Migration Path:**
1. Read [Airflow 2.0 Migration Guide](https://airflow.apache.org/docs/apache-airflow/stable/upgrading-from-1-10/index.html)
2. Update all DAGs to Airflow 2.0 syntax
3. Test in staging environment thoroughly
4. Plan 2-4 hour maintenance window
5. Backup extensively before upgrade

---

## Best Practices

### 1. Always Test in Staging

**Never upgrade production directly:**
```bash
# Deploy staging environment
helm install airflow-staging sb-charts/airflow -n staging -f values-staging.yaml

# Test upgrade in staging
helm upgrade airflow-staging sb-charts/airflow --set image.tag=2.8.2

# Validate for 24-48 hours before production upgrade
```

### 2. Incremental Upgrades

**Prefer small, frequent upgrades:**
- Patch upgrades: Every 1-2 months
- Minor upgrades: Every 3-6 months
- Major upgrades: Plan carefully (6-12 months)

**Avoid skipping versions:**
- ❌ Bad: 2.6.0 → 2.8.0 (skip 2.7.x)
- ✅ Good: 2.6.0 → 2.7.3 → 2.8.2

### 3. Monitor After Upgrade

**Post-upgrade monitoring (48 hours):**
```bash
# Watch pod status
kubectl get pods -l app.kubernetes.io/name=airflow -w

# Monitor logs
kubectl logs -f -l app.kubernetes.io/component=scheduler

# Check task success rate
kubectl exec -it airflow-webserver-0 -- \
  airflow tasks stats
```

### 4. Document Upgrade

**Maintain upgrade log:**
```markdown
## Airflow Upgrade Log

### 2025-11-27: 2.7.3 → 2.8.2
- **Performed by:** DevOps Team
- **Downtime:** 5 minutes (scheduler restart)
- **Issues:** None
- **Rollback:** Not required
- **Notes:** KubernetesExecutor performance improved
```

---

## Troubleshooting

### Database Migration Failures

**Problem: `airflow db migrate` fails**

**Solution:**
```bash
# Check current schema version
kubectl exec -it airflow-webserver-0 -- \
  airflow db current

# Check migration logs
kubectl logs airflow-webserver-0 -c db-migrations

# Manually run migration with verbose output
kubectl exec -it airflow-webserver-0 -- \
  airflow db migrate --verbose
```

### DAG Import Errors After Upgrade

**Problem: DAGs not loading after upgrade**

**Solution:**
```bash
# Check import errors
kubectl exec -it airflow-webserver-0 -- \
  airflow dags list-import-errors

# Validate DAG syntax
kubectl exec -it airflow-webserver-0 -- \
  python -m py_compile /opt/airflow/dags/*.py

# Check scheduler logs
make -f make/ops/airflow.mk airflow-scheduler-logs | grep -i error
```

### KubernetesExecutor Pod Creation Fails

**Problem: Tasks not executing after upgrade**

**Solution:**
```bash
# Check RBAC permissions
kubectl get role airflow
kubectl describe role airflow

# Verify ServiceAccount
kubectl get serviceaccount airflow
kubectl describe serviceaccount airflow

# Check scheduler logs for permission errors
kubectl logs -l app.kubernetes.io/component=scheduler | grep -i "permission denied"
```

### Performance Degradation

**Problem: Airflow slower after upgrade**

**Solution:**
```bash
# Check resource usage
kubectl top pods -l app.kubernetes.io/name=airflow

# Increase resources if needed
helm upgrade airflow sb-charts/airflow \
  --set scheduler.resources.limits.cpu=2000m \
  --set scheduler.resources.limits.memory=2Gi

# Check database connection pool
kubectl exec -it airflow-webserver-0 -- \
  airflow config get-value core sql_alchemy_pool_size
```

### Webserver Unavailable

**Problem: Webserver not responding after upgrade**

**Solution:**
```bash
# Check webserver logs
make -f make/ops/airflow.mk airflow-webserver-logs

# Check liveness/readiness probes
kubectl describe pod airflow-webserver-0 | grep -A10 "Liveness\|Readiness"

# Restart webserver
make -f make/ops/airflow.mk airflow-webserver-restart
```

---

## Additional Resources

- [Apache Airflow Upgrade Documentation](https://airflow.apache.org/docs/apache-airflow/stable/upgrading-to-2.html)
- [Airflow Release Notes](https://airflow.apache.org/docs/apache-airflow/stable/release_notes.html)
- [Airflow Backup & Recovery Guide](airflow-backup-guide.md)
- [Chart README](../charts/airflow/README.md)
- [PostgreSQL Upgrade Guide](https://www.postgresql.org/docs/current/upgrading.html)

---

**Last Updated:** 2025-11-27
