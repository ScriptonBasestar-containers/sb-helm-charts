# Memcached Backup & Recovery Guide

## Overview

This guide provides comprehensive backup and recovery procedures for Memcached deployments on Kubernetes using the scripton-charts Helm chart.

**Important**: Memcached is a **stateless in-memory cache** with **no data persistence**. Cache data is ephemeral and lost on pod restarts. Backup focuses on configuration and infrastructure, not cache data.

### Backup Strategy

Memcached backup covers **2 components**:

| Component | Priority | Size | Backup Method | Notes |
|-----------|----------|------|---------------|-------|
| **Configuration** | Critical | <5 KB | ConfigMap export | Cache settings, connection limits |
| **Kubernetes Manifests** | Important | <10 KB | Helm values | Deployment configuration |

**Note**: Cache data is **not backed up** as it's ephemeral and can be regenerated from source applications.

### Recovery Objectives

- **Recovery Time Objective (RTO)**: < 15 minutes
- **Recovery Point Objective (RPO)**: 0 (no data loss - cache is ephemeral)
- **Data Loss**: None (cache data is transient and regenerated on access)

### Backup Components

#### 1. Configuration (Critical)

**What**: Memcached runtime configuration
- Cache size (`-m` parameter)
- Connection limits (`-c` parameter)
- Slab settings (`-f` parameter)
- Additional command-line arguments

**Size**: < 5 KB

**Backup Method**: ConfigMap export or Helm values backup

**Why Important**: Configuration determines cache behavior, memory allocation, and performance characteristics.

#### 2. Kubernetes Manifests (Important)

**What**: Deployment configuration
- Deployment YAML (replicas, resources, probes)
- Service YAML (port, type)
- HPA/PDB configuration
- NetworkPolicy

**Size**: < 10 KB

**Backup Method**: Helm values backup or Git-based configuration management

**Why Important**: Required to recreate the Memcached cluster with correct resources and scaling policies.

---

## Backup Methods

### Method 1: ConfigMap Export (Recommended for Configuration)

**Use Case**: Quick configuration backup

**Tools Required**: kubectl

**Procedure**:

```bash
# 1. Export Memcached ConfigMap
kubectl get configmap -n default my-memcached -o yaml > memcached-config-backup.yaml

# 2. Verify backup file
cat memcached-config-backup.yaml

# 3. Store backup securely
# Option A: Upload to S3/MinIO
aws s3 cp memcached-config-backup.yaml s3://my-backups/memcached/config-$(date +%Y%m%d).yaml

# Option B: Commit to Git repository
git add memcached-config-backup.yaml
git commit -m "backup: memcached configuration $(date +%Y-%m-%d)"
git push
```

**Pros**:
- ✅ Simple and fast
- ✅ No external dependencies
- ✅ Works with any Kubernetes cluster

**Cons**:
- ⚠️ Manual process (requires scripting for automation)
- ⚠️ Doesn't capture Helm values

**Backup Frequency**: Daily (or before configuration changes)

---

### Method 2: Helm Values Backup (Recommended for Infrastructure)

**Use Case**: Comprehensive infrastructure backup

**Tools Required**: kubectl, yq (optional for YAML processing)

**Procedure**:

```bash
# 1. Export current Helm values
helm get values my-memcached -n default > memcached-values-backup.yaml

# 2. Backup full Helm release configuration
helm get all my-memcached -n default > memcached-helm-full-backup.yaml

# 3. Export all Kubernetes resources
kubectl get all,cm,secret,pdb,networkpolicy -n default -l app.kubernetes.io/name=memcached -o yaml > memcached-k8s-backup.yaml

# 4. Store backups
BACKUP_DIR="memcached-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
mv memcached-values-backup.yaml $BACKUP_DIR/
mv memcached-helm-full-backup.yaml $BACKUP_DIR/
mv memcached-k8s-backup.yaml $BACKUP_DIR/

# 5. Upload to S3/MinIO
tar czf $BACKUP_DIR.tar.gz $BACKUP_DIR
aws s3 cp $BACKUP_DIR.tar.gz s3://my-backups/memcached/
```

**Pros**:
- ✅ Complete infrastructure backup
- ✅ Includes Helm metadata
- ✅ Easy to restore via Helm

**Cons**:
- ⚠️ Requires Helm access
- ⚠️ Larger backup size

**Backup Frequency**: Weekly (or before major changes)

---

### Method 3: Git-Based Configuration Management (Best for Production)

**Use Case**: GitOps workflows with version control

**Tools Required**: Git, kubectl

**Procedure**:

```bash
# 1. Initialize Git repository (if not already done)
mkdir -p ~/memcached-config
cd ~/memcached-config
git init

# 2. Export current configuration
kubectl get configmap -n default my-memcached -o yaml > configmap.yaml
helm get values my-memcached -n default > values.yaml
kubectl get deployment -n default my-memcached -o yaml > deployment.yaml
kubectl get service -n default my-memcached -o yaml > service.yaml

# 3. Commit to Git
git add .
git commit -m "backup: memcached configuration $(date +%Y-%m-%d)"
git tag "backup-$(date +%Y%m%d-%H%M%S)"
git push origin main --tags

# 4. (Optional) Automated backup script
cat > backup.sh <<'EOF'
#!/bin/bash
NAMESPACE="default"
RELEASE="my-memcached"
BACKUP_DIR="$(date +%Y%m%d-%H%M%S)"

mkdir -p $BACKUP_DIR
kubectl get configmap -n $NAMESPACE $RELEASE -o yaml > $BACKUP_DIR/configmap.yaml
helm get values $RELEASE -n $NAMESPACE > $BACKUP_DIR/values.yaml

git add $BACKUP_DIR
git commit -m "backup: memcached configuration $(date +%Y-%m-%d)"
git push
EOF

chmod +x backup.sh
```

**Pros**:
- ✅ Full version history
- ✅ Supports GitOps workflows (ArgoCD, Flux)
- ✅ Audit trail for all changes
- ✅ Easy rollback to previous versions

**Cons**:
- ⚠️ Requires Git infrastructure
- ⚠️ More complex setup

**Backup Frequency**: Continuous (every configuration change)

---

## Recovery Procedures

### Recovery Scenario 1: Configuration-Only Recovery

**Situation**: Configuration change caused cache issues (e.g., wrong memory size, connection limits)

**Recovery Steps**:

```bash
# 1. Restore configuration from backup
kubectl apply -f memcached-config-backup.yaml

# 2. Restart Memcached pods to apply new configuration
kubectl rollout restart deployment/my-memcached -n default

# 3. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=120s

# 4. Verify configuration
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- memcached -h | grep -E "^-m|-c|-f"

# 5. Test cache functionality
echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211
```

**Expected Outcome**: Memcached pods restart with restored configuration.

**RTO**: < 5 minutes

---

### Recovery Scenario 2: Full Cluster Recreation

**Situation**: Complete cluster failure or namespace deletion

**Recovery Steps**:

```bash
# 1. Recreate namespace (if deleted)
kubectl create namespace default

# 2. Restore configuration from backup
kubectl apply -f memcached-config-backup.yaml

# 3. Reinstall Memcached via Helm
helm install my-memcached scripton-charts/memcached \
  -f memcached-values-backup.yaml \
  -n default

# 4. Wait for deployment to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n default --timeout=300s

# 5. Verify cluster status
kubectl get pods,svc -n default -l app.kubernetes.io/name=memcached

# 6. Test cache functionality
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211'
```

**Expected Outcome**: Memcached cluster is fully operational with restored configuration.

**RTO**: < 15 minutes

**Note**: Cache data is lost (expected for ephemeral cache). Applications will repopulate cache on first access.

---

### Recovery Scenario 3: Rollback to Previous Configuration

**Situation**: Recent configuration change caused performance degradation

**Recovery Steps** (Git-based):

```bash
# 1. List recent backups
git log --oneline --all

# 2. Checkout previous configuration
git checkout backup-20250101-120000

# 3. Apply previous configuration
kubectl apply -f configmap.yaml
kubectl apply -f values.yaml

# 4. Restart pods
kubectl rollout restart deployment/my-memcached -n default

# 5. Verify rollback
kubectl rollout status deployment/my-memcached -n default

# 6. Return to main branch (if satisfied)
git checkout main
```

**Expected Outcome**: Configuration reverted to previous known-good state.

**RTO**: < 10 minutes

---

## Backup Automation

### Automated Backup with CronJob

**Purpose**: Automated daily configuration backups

**Implementation**:

```yaml
# memcached-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: memcached-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: memcached-backup-sa
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Backup configuration
              kubectl get configmap -n default my-memcached -o yaml > /backup/config-$(date +%Y%m%d).yaml

              # Backup Helm values
              helm get values my-memcached -n default > /backup/values-$(date +%Y%m%d).yaml

              # Upload to S3 (requires AWS credentials)
              # aws s3 sync /backup/ s3://my-backups/memcached/

              # Clean up old backups (keep last 30 days)
              find /backup -name "config-*.yaml" -mtime +30 -delete
              find /backup -name "values-*.yaml" -mtime +30 -delete

              echo "Backup completed successfully"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: memcached-backup-pvc
          restartPolicy: OnFailure
---
# ServiceAccount for backup operations
apiVersion: v1
kind: ServiceAccount
metadata:
  name: memcached-backup-sa
  namespace: default
---
# Role for backup operations
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: memcached-backup-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
# RoleBinding for backup operations
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: memcached-backup-rolebinding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: memcached-backup-role
subjects:
- kind: ServiceAccount
  name: memcached-backup-sa
  namespace: default
```

**Deploy Backup CronJob**:

```bash
# Create backup PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: memcached-backup-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Deploy CronJob
kubectl apply -f memcached-backup-cronjob.yaml

# Verify CronJob
kubectl get cronjob -n default memcached-backup

# Test backup immediately
kubectl create job --from=cronjob/memcached-backup memcached-backup-manual -n default
kubectl logs -n default job/memcached-backup-manual -f
```

---

### Retention Policy Script

**Purpose**: Manage backup retention and cleanup

**Script**:

```bash
#!/bin/bash
# retention-cleanup.sh

BACKUP_DIR="/backups/memcached"
RETENTION_DAYS=30

echo "=== Memcached Backup Retention Cleanup ==="
echo "Retention period: $RETENTION_DAYS days"
echo "Backup directory: $BACKUP_DIR"

# Count backups before cleanup
BEFORE=$(find $BACKUP_DIR -name "*.yaml" -type f | wc -l)
echo "Backups before cleanup: $BEFORE"

# Delete old backups
find $BACKUP_DIR -name "*.yaml" -type f -mtime +$RETENTION_DAYS -delete

# Count backups after cleanup
AFTER=$(find $BACKUP_DIR -name "*.yaml" -type f | wc -l)
echo "Backups after cleanup: $AFTER"
echo "Removed: $((BEFORE - AFTER)) backups"

echo "=== Cleanup Complete ==="
```

**Schedule via cron**:

```bash
# Add to crontab (daily at 3 AM)
0 3 * * * /path/to/retention-cleanup.sh >> /var/log/memcached-backup-retention.log 2>&1
```

---

## Testing Backups

### Backup Validation Procedure

**Purpose**: Verify backup integrity and completeness

**Test Script**:

```bash
#!/bin/bash
# test-backup.sh

NAMESPACE="default"
RELEASE="my-memcached"
BACKUP_FILE="memcached-config-backup.yaml"

echo "=== Memcached Backup Test ==="

# 1. Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "✗ Backup file not found: $BACKUP_FILE"
  exit 1
fi
echo "✓ Backup file found"

# 2. Validate YAML syntax
if ! kubectl apply --dry-run=client -f $BACKUP_FILE > /dev/null 2>&1; then
  echo "✗ Invalid YAML syntax"
  exit 1
fi
echo "✓ YAML syntax valid"

# 3. Check required fields
if ! grep -q "kind: ConfigMap" $BACKUP_FILE; then
  echo "✗ Missing ConfigMap kind"
  exit 1
fi
echo "✓ ConfigMap kind present"

# 4. Verify metadata
if ! grep -q "name: $RELEASE" $BACKUP_FILE; then
  echo "✗ Missing release name in metadata"
  exit 1
fi
echo "✓ Metadata valid"

# 5. Test restore in test namespace
TEST_NS="memcached-test"
kubectl create namespace $TEST_NS 2>/dev/null || true

# Apply backup to test namespace
cat $BACKUP_FILE | sed "s/namespace: $NAMESPACE/namespace: $TEST_NS/g" | kubectl apply -f -

if [ $? -eq 0 ]; then
  echo "✓ Backup restore test successful"
  kubectl delete namespace $TEST_NS
else
  echo "✗ Backup restore test failed"
  kubectl delete namespace $TEST_NS
  exit 1
fi

echo "=== Backup Test Complete ==="
```

**Run Test**:

```bash
chmod +x test-backup.sh
./test-backup.sh
```

---

### Disaster Recovery Drill

**Purpose**: Practice full cluster recovery

**Procedure**:

```bash
# 1. Create test namespace
kubectl create namespace memcached-dr-test

# 2. Deploy Memcached to test namespace
helm install memcached-test scripton-charts/memcached \
  -f memcached-values-backup.yaml \
  -n memcached-dr-test

# 3. Wait for deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=memcached -n memcached-dr-test --timeout=300s

# 4. Verify functionality
POD=$(kubectl get pods -n memcached-dr-test -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n memcached-dr-test $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211'

# 5. Cleanup
helm uninstall memcached-test -n memcached-dr-test
kubectl delete namespace memcached-dr-test

echo "✓ DR drill completed successfully"
```

**Recommended Frequency**: Quarterly

---

## Troubleshooting

### Issue 1: Backup CronJob Fails

**Symptoms**:
```bash
$ kubectl get jobs -n default
NAME                              COMPLETIONS   DURATION   AGE
memcached-backup-1234567890       0/1           5m         5m
```

**Diagnosis**:
```bash
# Check job logs
kubectl logs -n default job/memcached-backup-1234567890

# Check pod events
kubectl describe job -n default memcached-backup-1234567890
```

**Common Causes & Solutions**:

1. **Insufficient RBAC permissions**:
   ```bash
   # Verify ServiceAccount has correct permissions
   kubectl auth can-i get configmaps --as=system:serviceaccount:default:memcached-backup-sa -n default

   # Fix: Update Role with correct permissions
   ```

2. **PVC not mounted**:
   ```bash
   # Check PVC status
   kubectl get pvc -n default memcached-backup-pvc

   # Fix: Ensure PVC is bound and has sufficient storage
   ```

3. **S3 credentials missing**:
   ```bash
   # Verify AWS credentials secret
   kubectl get secret -n default aws-credentials

   # Fix: Create secret with AWS credentials
   kubectl create secret generic aws-credentials \
     --from-literal=AWS_ACCESS_KEY_ID=<key> \
     --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
   ```

---

### Issue 2: Configuration Restore Fails

**Symptoms**:
```bash
$ kubectl apply -f memcached-config-backup.yaml
Error from server (Invalid): error when creating "memcached-config-backup.yaml": ConfigMap "my-memcached" is invalid
```

**Diagnosis**:
```bash
# Validate YAML syntax
kubectl apply --dry-run=client -f memcached-config-backup.yaml

# Check for API version compatibility
kubectl api-resources | grep ConfigMap
```

**Solutions**:

1. **Remove immutable fields**:
   ```bash
   # Remove resourceVersion, uid, creationTimestamp
   yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' memcached-config-backup.yaml > clean-backup.yaml
   kubectl apply -f clean-backup.yaml
   ```

2. **Force replacement**:
   ```bash
   kubectl replace --force -f memcached-config-backup.yaml
   ```

---

### Issue 3: Pods Not Restarting After Config Change

**Symptoms**: Configuration restored but pods still using old config

**Diagnosis**:
```bash
# Check if ConfigMap was updated
kubectl get configmap -n default my-memcached -o yaml

# Check pod startup time
kubectl get pods -n default -l app.kubernetes.io/name=memcached -o wide
```

**Solution**:
```bash
# Force rolling restart
kubectl rollout restart deployment/my-memcached -n default

# Wait for rollout
kubectl rollout status deployment/my-memcached -n default

# Verify new pods are using updated config
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod -n default $POD | grep -A5 "Environment:"
```

---

## Best Practices

### 1. Configuration Management

**Git-Based Workflow**:
- ✅ Store `values.yaml` in Git repository
- ✅ Use GitOps tools (ArgoCD, Flux) for automated deployments
- ✅ Tag releases for easy rollback (`git tag backup-YYYYMMDD`)
- ✅ Review all configuration changes via Pull Requests

**Why**: Version control provides audit trail and easy rollback.

---

### 2. Backup Frequency

**Recommended Schedule**:
- **Configuration**: Daily (or before every change)
- **Kubernetes Manifests**: Weekly
- **Git commits**: Continuous (on every change)

**Why**: Memcached has no data to backup, only configuration.

---

### 3. Off-Cluster Storage

**Storage Options**:
- ✅ S3/MinIO for backups
- ✅ Remote Git repository (GitHub, GitLab, Bitbucket)
- ✅ Separate backup namespace with PVC

**Why**: Protects against cluster-wide failures.

---

### 4. Test Recovery Procedures

**Quarterly DR Drills**:
- Test full cluster recreation from backup
- Verify configuration restore procedures
- Measure actual RTO vs. target RTO
- Document lessons learned

**Why**: Ensures team readiness and validates backup integrity.

---

### 5. Monitor Backup Health

**Metrics to Track**:
- Backup job success rate (target: 100%)
- Backup file size over time
- Time to complete backup (target: < 2 minutes)
- Storage utilization

**Alerts**:
```yaml
# Example Prometheus alert
- alert: MemcachedBackupFailed
  expr: kube_job_failed{job_name=~"memcached-backup.*"} > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Memcached backup job failed"
    description: "Backup job {{ $labels.job_name }} has failed"
```

---

### 6. Documentation

**Maintain Runbooks**:
- Document backup procedures
- Document restore procedures
- Include troubleshooting steps
- Keep contact information for escalation

**Why**: Enables faster incident response during outages.

---

### 7. Cache Warming Strategy

**Post-Recovery**:
Since Memcached cache is lost on recovery, implement cache warming:

```bash
# Example cache warming script
#!/bin/bash
# warm-cache.sh

# Preload frequently accessed keys
curl http://my-app/api/warm-cache

# Monitor cache hit rate
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=memcached -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $POD -- sh -c 'echo -e "stats\r\nquit\r" | nc localhost 11211' | grep -E "get_hits|get_misses"
```

**Why**: Reduces cache miss rate after recovery, improving application performance.

---

## Summary

### Backup Checklist

- [ ] Configuration backed up daily
- [ ] Helm values stored in Git repository
- [ ] Automated backup CronJob deployed
- [ ] Backup retention policy configured (30 days)
- [ ] Off-cluster backup storage configured (S3/Git)
- [ ] Quarterly DR drills scheduled
- [ ] Backup monitoring and alerting enabled
- [ ] Recovery runbooks documented

### Key Takeaways

1. **Memcached is stateless**: No data backup required, cache is ephemeral
2. **Configuration is critical**: Backup ConfigMap and Helm values
3. **RTO < 15 minutes**: Fast recovery due to minimal backup footprint
4. **RPO = 0**: No data loss (cache is regenerated on access)
5. **GitOps recommended**: Version control for configuration management
6. **Cache warming**: Plan for cache repopulation after recovery

### Additional Resources

- [Memcached Documentation](https://memcached.org/)
- [Memcached Protocol Specification](https://github.com/memcached/memcached/blob/master/doc/protocol.txt)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)
- [Kubernetes Backup Best Practices](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-09
**Tested With**: Memcached 1.6.39, Kubernetes 1.28+, Helm 3.12+
