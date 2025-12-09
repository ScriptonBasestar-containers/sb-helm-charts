# MongoDB Upgrade Guide

This guide provides comprehensive MongoDB upgrade procedures for the sb-helm-charts MongoDB deployment.

## Table of Contents

1. [Overview](#overview)
2. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
3. [Upgrade Strategies](#upgrade-strategies)
4. [Version-Specific Notes](#version-specific-notes)
5. [Post-Upgrade Validation](#post-upgrade-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Overview

MongoDB upgrades should be carefully planned and executed to minimize downtime and ensure data integrity.

### Supported Upgrade Paths

**MongoDB Version Compatibility:**
```
6.0 → 7.0  ✅ Supported (direct upgrade)
5.0 → 6.0  ✅ Supported (direct upgrade)
4.4 → 5.0  ✅ Supported (direct upgrade)
4.2 → 4.4  ✅ Supported (direct upgrade)

4.2 → 7.0  ❌ Not supported (upgrade through intermediate versions)
```

**Chart Version Upgrades:**
```
v0.3.0 → v0.4.0  ✅ Compatible
v0.2.0 → v0.4.0  ⚠️  Review CHANGELOG for breaking changes
```

### Upgrade Types

1. **Minor Version Upgrade** (e.g., 7.0.1 → 7.0.5)
   - Low risk
   - Typically bug fixes and performance improvements
   - Minimal downtime (<5 minutes)

2. **Major Version Upgrade** (e.g., 6.0 → 7.0)
   - Medium-high risk
   - New features, deprecated features
   - Requires careful planning
   - Downtime: 10-30 minutes (standalone), minimal (replica sets)

3. **Feature Compatibility Version (FCV) Upgrade**
   - Enables new version features
   - Must be done after binaries upgrade
   - Can be reverted before upgrading binaries

## Pre-Upgrade Checklist

### 1. Review Requirements

**Before starting the upgrade:**

- [ ] Review MongoDB release notes: https://docs.mongodb.com/manual/release-notes/
- [ ] Check chart CHANGELOG for breaking changes
- [ ] Verify application compatibility with new MongoDB version
- [ ] Identify deprecated features in use
- [ ] Review driver version compatibility
- [ ] Plan maintenance window (if needed)

### 2. Backup Verification

**Critical:** Always backup before upgrading!

```bash
# Full backup with Makefile
make -f make/ops/mongodb.mk mongo-full-backup

# Verify backup exists and is valid
ls -lh tmp/mongodb-backups/

# Test restore in separate environment (recommended)
```

**Checklist:**
- [ ] Full database backup completed
- [ ] Configuration backup completed
- [ ] Users & roles backup completed
- [ ] Backup tested and verified
- [ ] Backup stored offsite/external location

### 3. Current State Verification

**Check current deployment:**

```bash
# Check current MongoDB version
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- mongo --version

# Check current chart version
helm list -n default | grep mongodb

# Check Feature Compatibility Version (FCV)
kubectl exec -n default $POD -- mongo --eval "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"

# Check deployment health
kubectl get pods -n default -l app.kubernetes.io/name=mongodb
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('serverStatus')"
```

**Run pre-upgrade check:**
```bash
make -f make/ops/mongodb.mk mongo-pre-upgrade-check
```

### 4. Resource Verification

```bash
# Check PVC capacity
kubectl get pvc -n default -l app.kubernetes.io/name=mongodb

# Check node resources
kubectl describe node | grep -A 5 "Allocated resources"

# Check storage usage
kubectl exec -n default $POD -- df -h /data/db
```

### 5. Application Preparation

- [ ] Notify users of upcoming maintenance
- [ ] Reduce traffic to database (if possible)
- [ ] Disable scheduled jobs that write to MongoDB
- [ ] Prepare rollback plan
- [ ] Have support team on standby

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Replica Sets - Recommended)

**Best For:** Replica set deployments, zero-downtime upgrades

**Downtime:** None (if done correctly)

**Prerequisites:**
- Replica set with 3+ members
- Healthy replication
- All members on same version before starting

**Procedure:**

```bash
# 1. Verify replica set health
kubectl exec -n default mongodb-0 -- mongo --eval "rs.status()"

# 2. Upgrade secondaries first (one at a time)
# Start with secondary member mongodb-2
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set updateStrategy.type=RollingUpdate \
  --set updateStrategy.rollingUpdate.partition=2 \
  -n default

# Wait for mongodb-2 to be ready
kubectl rollout status statefulset mongodb -n default
kubectl exec -n default mongodb-2 -- mongo --version

# 3. Upgrade next secondary mongodb-1
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set updateStrategy.rollingUpdate.partition=1 \
  -n default

# Wait for mongodb-1 to be ready
kubectl rollout status statefulset mongodb -n default

# 4. Step down primary (force primary on mongodb-1 or mongodb-2)
kubectl exec -n default mongodb-0 -- mongo --eval "rs.stepDown(60)"

# 5. Upgrade former primary mongodb-0
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set updateStrategy.rollingUpdate.partition=0 \
  -n default

# Wait for mongodb-0 to be ready
kubectl rollout status statefulset mongodb -n default

# 6. Verify all members upgraded
for i in 0 1 2; do
  kubectl exec -n default mongodb-$i -- mongo --version
done

# 7. Upgrade Feature Compatibility Version (FCV)
kubectl exec -n default mongodb-0 -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"

# 8. Verify upgrade
kubectl exec -n default mongodb-0 -- mongo --eval \
  "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"
```

**Monitoring During Rolling Upgrade:**
```bash
# Watch pod updates
watch kubectl get pods -n default -l app.kubernetes.io/name=mongodb

# Monitor replica set status
watch 'kubectl exec -n default mongodb-0 -- mongo --quiet --eval "rs.status()" | grep -A 3 "name\|stateStr"'

# Check replication lag
kubectl exec -n default mongodb-0 -- mongo --eval "rs.printSecondaryReplicationInfo()"
```

### Strategy 2: In-Place Upgrade (Standalone)

**Best For:** Standalone deployments, development/testing

**Downtime:** 5-15 minutes

**Procedure:**

```bash
# 1. Stop applications
kubectl scale deployment myapp --replicas=0

# 2. Backup database
make -f make/ops/mongodb.mk mongo-full-backup

# 3. Upgrade chart
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  -n default

# 4. Wait for pod restart
kubectl rollout status statefulset mongodb -n default

# 5. Verify new version
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- mongo --version

# 6. Upgrade Feature Compatibility Version
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"

# 7. Verify data integrity
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('listDatabases')"
kubectl exec -n default $POD -- mongo myapp --eval "db.users.count()"

# 8. Restart applications
kubectl scale deployment myapp --replicas=3

# 9. Run post-upgrade checks
make -f make/ops/mongodb.mk mongo-post-upgrade-check
```

### Strategy 3: Blue-Green Deployment

**Best For:** Minimal risk upgrades, large databases, critical production

**Downtime:** <1 minute (traffic switch)

**Prerequisites:**
- Sufficient cluster resources
- External DNS or ingress for traffic switching
- Ability to run parallel MongoDB instances

**Procedure:**

```bash
# 1. Deploy new "green" MongoDB cluster (different namespace)
kubectl create namespace mongodb-green

helm install mongodb-green sb-charts/mongodb \
  --set image.tag=7.0.5 \
  --set persistence.size=100Gi \
  --set mongodb.replicaSet.enabled=true \
  --set replicaCount=3 \
  -n mongodb-green

# 2. Wait for green cluster to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb -n mongodb-green --timeout=600s

# 3. Backup blue cluster
make -f make/ops/mongodb.mk mongo-full-backup NAMESPACE=default

# 4. Restore data to green cluster
# Copy backup to green cluster
POD_GREEN=$(kubectl get pods -n mongodb-green -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl cp tmp/mongodb-backups/latest/ mongodb-green/$POD_GREEN:/tmp/restore/

# Restore
kubectl exec -n mongodb-green $POD_GREEN -- mongorestore \
  --drop \
  /tmp/restore/

# 5. Verify green cluster
kubectl exec -n mongodb-green $POD_GREEN -- mongo --eval "db.adminCommand('listDatabases')"

# 6. Upgrade FCV on green cluster
kubectl exec -n mongodb-green $POD_GREEN -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"

# 7. Test applications against green cluster
# Update application config to point to mongodb-green temporarily

# 8. Switch traffic from blue to green
# Update DNS, ingress, or service selectors
kubectl patch svc mongodb -n default -p '{"spec":{"selector":{"app.kubernetes.io/instance":"mongodb-green"}}}'

# 9. Monitor green cluster
watch kubectl get pods -n mongodb-green

# 10. After validation period, decommission blue cluster
helm uninstall mongodb -n default
```

### Strategy 4: Dump and Restore

**Best For:** Major version jumps, database schema changes, cleanup

**Downtime:** 1-4 hours (depends on data size)

**Procedure:**

```bash
# 1. Stop applications
kubectl scale deployment myapp --replicas=0

# 2. Export data from old version
POD_OLD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n default $POD_OLD -- mongodump \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --gzip \
  --out=/tmp/export

kubectl cp default/$POD_OLD:/tmp/export ./mongodb-export-$(date +%Y%m%d)

# 3. Upgrade MongoDB chart
helm upgrade mongodb sb-charts/mongodb \
  --set image.tag=7.0.5 \
  -n default

# 4. Wait for new version pod
kubectl rollout status statefulset mongodb -n default

# 5. Import data to new version
POD_NEW=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

kubectl cp ./mongodb-export-$(date +%Y%m%d) default/$POD_NEW:/tmp/import/

kubectl exec -n default $POD_NEW -- mongorestore \
  --username=root \
  --password=$MONGO_ROOT_PASSWORD \
  --authenticationDatabase=admin \
  --gzip \
  /tmp/import/

# 6. Verify data
kubectl exec -n default $POD_NEW -- mongo --eval "db.adminCommand('listDatabases')"

# 7. Upgrade FCV
kubectl exec -n default $POD_NEW -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"

# 8. Restart applications
kubectl scale deployment myapp --replicas=3
```

## Version-Specific Notes

### MongoDB 6.0 → 7.0

**Major Changes:**
- Improved Time Series collections
- New aggregation operators
- Enhanced change streams
- Updated query planner

**Breaking Changes:**
- Removed `db.collection.copyTo()`
- Removed `planCacheSetFilter` and `planCacheClearFilters`
- Updated replica set protocol version

**Before Upgrading:**
```bash
# Check for deprecated features in use
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({getLog: 'global'})" | grep -i deprecat

# Verify driver compatibility
# MongoDB 7.0 requires driver versions:
# - Java: 4.11+
# - Python (PyMongo): 4.5+
# - Node.js: 6.0+
# - Go: 1.12+
```

**After Upgrading:**
```bash
# Verify FCV upgrade
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"

# Test time series collections (if used)
kubectl exec -n default $POD -- mongo --eval \
  "db.getCollectionInfos({type: 'timeseries'})"
```

### MongoDB 5.0 → 6.0

**Major Changes:**
- Time Series collections GA
- Native support for array filters
- Improved sharding
- Change streams enhancements

**Before Upgrading:**
```bash
# Check FCV is set to 5.0
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"

# Should return: { "featureCompatibilityVersion" : { "version" : "5.0" } }
```

**Breaking Changes:**
- Removed `mapReduce` command (use aggregation pipeline)
- Changed authentication mechanisms

### MongoDB 4.4 → 5.0

**Major Changes:**
- Native time series collections
- Versioned API
- Improved aggregations
- Windows support improvements

**Breaking Changes:**
- Removed `geoNear` command
- Removed `db.collection.copyTo()`
- Changed replica set protocol

## Post-Upgrade Validation

### Automated Validation Script

```bash
#!/bin/bash
# mongodb-post-upgrade-validation.sh

POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

echo "=== MongoDB Post-Upgrade Validation ==="

# 1. Check MongoDB version
echo "1. MongoDB Version:"
kubectl exec -n default $POD -- mongo --version

# 2. Check FCV
echo "2. Feature Compatibility Version:"
kubectl exec -n default $POD -- mongo --quiet --eval \
  "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1}).featureCompatibilityVersion.version"

# 3. Check database status
echo "3. Database Status:"
kubectl exec -n default $POD -- mongo --quiet --eval \
  "db.adminCommand('listDatabases')"

# 4. Check replica set status (if replica set)
echo "4. Replica Set Status:"
kubectl exec -n default $POD -- mongo --quiet --eval \
  "rs.status().ok"

# 5. Check for errors in logs
echo "5. Recent Errors (last 100 lines):"
kubectl logs -n default $POD --tail=100 | grep -i error || echo "No errors found"

# 6. Check index status
echo "6. Index Status:"
kubectl exec -n default $POD -- mongo myapp --quiet --eval \
  "db.getCollectionNames().forEach(function(col) { print(col + ': ' + db[col].getIndexes().length + ' indexes') })"

# 7. Verify connections
echo "7. Current Connections:"
kubectl exec -n default $POD -- mongo --quiet --eval \
  "db.serverStatus().connections"

# 8. Check oplog (replica sets)
echo "8. Oplog Status:"
kubectl exec -n default $POD -- mongo --quiet --eval \
  "db.getReplicationInfo()"

echo "✅ Post-upgrade validation complete"
```

**Run validation:**
```bash
make -f make/ops/mongodb.mk mongo-post-upgrade-check
```

### Manual Validation Checklist

**After upgrade completion:**

- [ ] MongoDB version matches expected version
- [ ] Feature Compatibility Version upgraded
- [ ] All pods running and healthy
- [ ] Replica set status healthy (if applicable)
- [ ] No errors in MongoDB logs
- [ ] Database connections working
- [ ] Indexes present and functioning
- [ ] Application connectivity verified
- [ ] Performance metrics normal
- [ ] Backup successful post-upgrade

### Application Testing

```bash
# Test application connections
curl http://myapp/health

# Run application test suite
kubectl exec -n default myapp-test-pod -- npm test

# Check application logs for errors
kubectl logs -n default deployment/myapp --tail=100 | grep -i error
```

## Rollback Procedures

### Rollback Strategy 1: Helm Rollback (Before FCV Upgrade)

**When to Use:** Upgrade issues discovered before FCV upgrade

**Procedure:**
```bash
# 1. Check Helm history
helm history mongodb -n default

# 2. Rollback to previous revision
helm rollback mongodb -n default

# 3. Wait for rollout
kubectl rollout status statefulset mongodb -n default

# 4. Verify version
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- mongo --version

# 5. Verify data integrity
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('listDatabases')"
```

**Makefile Target:**
```bash
make -f make/ops/mongodb.mk mongo-upgrade-rollback
```

### Rollback Strategy 2: Restore from Backup (After FCV Upgrade)

**When to Use:** Critical issues after FCV upgrade, data corruption

**Procedure:**
```bash
# 1. Stop applications
kubectl scale deployment myapp --replicas=0

# 2. Downgrade chart
helm rollback mongodb -n default

# 3. Restore database from backup
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')

kubectl cp tmp/mongodb-backups/pre-upgrade/ default/$POD:/tmp/restore/

kubectl exec -n default $POD -- mongorestore \
  --drop \
  /tmp/restore/

# 4. Verify data
kubectl exec -n default $POD -- mongo --eval "db.adminCommand('listDatabases')"

# 5. Restart applications
kubectl scale deployment myapp --replicas=3
```

### Rollback Strategy 3: Blue-Green Rollback

**When to Use:** Blue-green deployment rollback

**Procedure:**
```bash
# 1. Switch traffic back to blue cluster
kubectl patch svc mongodb -n default -p \
  '{"spec":{"selector":{"app.kubernetes.io/instance":"mongodb"}}}'

# 2. Verify blue cluster health
kubectl get pods -n default -l app.kubernetes.io/instance=mongodb

# 3. Monitor application
watch kubectl logs -n default deployment/myapp --tail=20

# 4. Decommission green cluster
helm uninstall mongodb-green -n mongodb-green
kubectl delete namespace mongodb-green
```

## Troubleshooting

### Issue 1: Replica Set Not Electing Primary

**Symptoms:**
```
No primary found in replica set
```

**Diagnosis:**
```bash
# Check replica set status
kubectl exec -n default mongodb-0 -- mongo --eval "rs.status()"

# Check member states
kubectl exec -n default mongodb-0 -- mongo --eval \
  "rs.status().members.forEach(function(m) { print(m.name + ': ' + m.stateStr) })"
```

**Solutions:**
```bash
# Force reconfigure replica set
kubectl exec -n default mongodb-0 -- mongo --eval \
  "cfg = rs.conf(); rs.reconfig(cfg, {force: true})"

# Step down current primary and force election
kubectl exec -n default mongodb-0 -- mongo --eval "rs.stepDown(60)"
```

### Issue 2: FCV Upgrade Fails

**Symptoms:**
```
Error upgrading featureCompatibilityVersion
```

**Diagnosis:**
```bash
# Check current FCV
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"

# Check for incompatible features
kubectl logs -n default $POD --tail=200 | grep -i "incompatible\|upgrade"
```

**Solutions:**
```bash
# Downgrade FCV to previous version
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '6.0'})"

# Fix incompatibilities and retry
kubectl exec -n default $POD -- mongo --eval \
  "db.adminCommand({setFeatureCompatibilityVersion: '7.0'})"
```

### Issue 3: Pod Fails to Start After Upgrade

**Symptoms:**
```
CrashLoopBackOff or ImagePullBackOff
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod mongodb-0 -n default

# Check pod logs
kubectl logs -n default mongodb-0 --previous

# Check image
kubectl get pod mongodb-0 -n default -o jsonpath='{.spec.containers[0].image}'
```

**Solutions:**
```bash
# Verify image exists
docker pull mongo:7.0.5

# Rollback to previous version
helm rollback mongodb -n default

# Check PVC permissions
kubectl exec -n default mongodb-0 -- ls -la /data/db
```

### Issue 4: Performance Degradation After Upgrade

**Symptoms:**
```
Slow queries, high CPU/memory usage
```

**Diagnosis:**
```bash
# Check slow queries
kubectl exec -n default $POD -- mongo --eval \
  "db.system.profile.find({millis: {\$gt: 100}}).limit(10).pretty()"

# Check current operations
kubectl exec -n default $POD -- mongo --eval \
  "db.currentOp({'secs_running': {\$gt: 5}})"

# Check resource usage
kubectl top pod mongodb-0 -n default
```

**Solutions:**
```bash
# Rebuild indexes
kubectl exec -n default $POD -- mongo myapp --eval \
  "db.getCollectionNames().forEach(function(col) { db[col].reIndex() })"

# Update statistics
kubectl exec -n default $POD -- mongo myapp --eval \
  "db.runCommand({dbStats: 1})"

# Adjust WiredTiger cache
# Update values.yaml:
# mongodb:
#   wiredTiger:
#     cacheSizeGB: 2.0
```

## Best Practices

### 1. Planning

**DO:**
- ✅ Test upgrades in non-production environment first
- ✅ Review release notes and CHANGELOG
- ✅ Create comprehensive backup before upgrade
- ✅ Schedule during low-traffic periods
- ✅ Have rollback plan ready
- ✅ Notify stakeholders of maintenance window

**DON'T:**
- ❌ Skip testing in staging environment
- ❌ Upgrade production without backup
- ❌ Perform upgrades during peak hours
- ❌ Skip intermediate versions for major jumps

### 2. Execution

**DO:**
- ✅ Use rolling upgrades for replica sets
- ✅ Upgrade secondaries before primary
- ✅ Monitor replication lag during upgrade
- ✅ Verify each step before proceeding
- ✅ Document all commands executed

**DON'T:**
- ❌ Upgrade all replicas simultaneously
- ❌ Skip FCV upgrade (leaves cluster in mixed state)
- ❌ Ignore warning messages

### 3. Validation

**DO:**
- ✅ Run automated validation tests
- ✅ Verify application functionality
- ✅ Check performance metrics
- ✅ Monitor for errors in logs
- ✅ Test backup after upgrade

**DON'T:**
- ❌ Assume upgrade succeeded without verification
- ❌ Skip application testing
- ❌ Ignore performance changes

### 4. Rollback

**DO:**
- ✅ Have clear rollback criteria
- ✅ Test rollback procedures
- ✅ Keep backups accessible
- ✅ Document rollback steps

**DON'T:**
- ❌ Wait too long to rollback if issues arise
- ❌ Rollback without understanding root cause
- ❌ Delete backups immediately after upgrade

---

**Last Updated:** 2025-12-09
**Chart Version:** v0.4.0
**MongoDB Version:** 7.0+
