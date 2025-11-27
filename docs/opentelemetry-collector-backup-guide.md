# OpenTelemetry Collector - Comprehensive Backup and Recovery Guide

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Components](#backup-components)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Automation](#automation)
7. [Testing & Validation](#testing--validation)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive procedures for backing up and recovering OpenTelemetry Collector deployments in Kubernetes environments. While the OpenTelemetry Collector is primarily stateless (data flows through it), maintaining configuration backups is critical for disaster recovery and compliance.

### Architecture Considerations

**OpenTelemetry Collector Components:**
- **Receivers**: OTLP gRPC/HTTP, Prometheus, Jaeger, Zipkin, etc.
- **Processors**: Batch, memory_limiter, k8sattributes, resource, etc.
- **Exporters**: OTLP, Prometheus remote write, Loki, Tempo, etc.
- **Extensions**: Health check, pprof, zpages

**Deployment Modes:**
- **Gateway Mode (Deployment)**: Centralized collectors (2-10+ replicas)
- **Agent Mode (DaemonSet)**: Per-node collectors (1 per node)

### RTO/RPO Targets

| Component | RTO | RPO | Priority |
|-----------|-----|-----|----------|
| Configuration | < 30 minutes | 0 (immediate) | Critical |
| Pipeline State | N/A (stateless) | N/A | N/A |
| Custom Extensions | < 1 hour | 24 hours | Medium |

**Note**: OpenTelemetry Collector is designed to be stateless. Data is not persisted locally; it flows from receivers through processors to exporters. Focus is on configuration backup for rapid recovery.

---

## Backup Strategy

### Three-Component Strategy

1. **Configuration Backups**
   - Collector YAML configuration
   - Kubernetes ConfigMaps
   - RBAC resources (ClusterRole, ClusterRoleBinding)
   - Service configuration

2. **Kubernetes Resource Manifests**
   - Deployment/DaemonSet specifications
   - Service and Ingress definitions
   - HPA, PDB, ServiceMonitor configurations

3. **Custom Extensions** (if applicable)
   - Custom receiver/processor/exporter plugins
   - Sidecar containers
   - Init containers

### Backup Frequency

| Component | Frequency | Method | Retention |
|-----------|-----------|--------|-----------|
| Configuration | Before changes | kubectl get configmap | 90 days |
| K8s Manifests | Before changes | Helm + kubectl | 90 days |
| Custom Extensions | Weekly | kubectl describe | 30 days |

---

## Backup Components

### 1. Configuration Backup

**What to backup:**
- OpenTelemetry Collector configuration YAML
- ConfigMap: `{release-name}-opentelemetry-collector`
- Environment variables (via ConfigMap/Secret)

**Why critical:**
- Pipeline definitions (receivers → processors → exporters)
- Processing rules and transformations
- Export endpoints and credentials
- Resource limits and batch settings

**Backup location:**
```
tmp/otel-collector-backups/
├── config-20250127-120000/
│   ├── otel-config.yaml          # Main collector configuration
│   ├── configmap.yaml            # Kubernetes ConfigMap
│   └── secrets.yaml              # Secrets (if any, encrypted)
```

### 2. Kubernetes Resource Manifests

**What to backup:**
- Deployment/DaemonSet specifications
- Service definitions
- Ingress/ServiceMonitor
- RBAC (ClusterRole, ClusterRoleBinding)

**Why important:**
- Recreate deployment with exact specifications
- Service discovery and networking configuration
- Monitoring and observability setup

**Backup location:**
```
tmp/otel-collector-backups/
├── manifests-20250127-120000/
│   ├── deployment.yaml           # Or daemonset.yaml
│   ├── service.yaml
│   ├── clusterrole.yaml
│   ├── clusterrolebinding.yaml
│   ├── serviceaccount.yaml
│   ├── hpa.yaml                  # If enabled
│   ├── pdb.yaml                  # If enabled
│   └── servicemonitor.yaml       # If enabled
```

### 3. Custom Extensions

**What to backup:**
- Custom receiver/processor/exporter code
- Custom configuration files
- Sidecar container configurations

**Why optional:**
- Most deployments use standard contrib components
- Only needed if using custom-built collectors

**Backup location:**
```
tmp/otel-collector-backups/
├── custom-20250127-120000/
│   ├── custom-receiver/
│   ├── custom-processor/
│   └── Dockerfile                # If custom image
```

---

## Backup Procedures

### Prerequisites

**Required tools:**
```bash
# Install required tools
kubectl version --client
helm version

# Set environment variables
export NAMESPACE=monitoring
export RELEASE_NAME=otel-collector
export BACKUP_DIR=tmp/otel-collector-backups
```

**Permissions:**
```bash
# Verify access
kubectl auth can-i get configmaps -n $NAMESPACE
kubectl auth can-i get deployments -n $NAMESPACE
kubectl auth can-i get clusterroles
```

### Manual Backup: Configuration

**Step 1: Backup ConfigMap**
```bash
# Create backup directory
mkdir -p $BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S)
cd $BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S)

# Export ConfigMap
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > configmap.yaml

# Extract collector config from ConfigMap
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o jsonpath='{.data.otel-config\.yaml}' > otel-config.yaml
```

**Step 2: Backup Secrets (if any)**
```bash
# List secrets
kubectl get secrets -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector

# Export secrets (if exist)
kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-credentials -o yaml > secrets.yaml

# Note: Secrets are base64-encoded. For secure storage, encrypt with sops/sealed-secrets
```

**Step 3: Verify configuration backup**
```bash
# Check file sizes
ls -lh

# Validate YAML syntax
yamllint otel-config.yaml
kubectl apply --dry-run=client -f configmap.yaml
```

### Manual Backup: Kubernetes Manifests

**Step 1: Backup deployment resources**
```bash
# Create manifests backup directory
mkdir -p $BACKUP_DIR/manifests-$(date +%Y%m%d-%H%M%S)
cd $BACKUP_DIR/manifests-$(date +%Y%m%d-%H%M%S)

# Determine deployment mode
DEPLOY_MODE=$(kubectl get deployment,daemonset -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector -o jsonpath='{.items[0].kind}' | tr '[:upper:]' '[:lower:]')

# Export deployment or daemonset
kubectl get $DEPLOY_MODE -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > ${DEPLOY_MODE}.yaml

# Export service
kubectl get service -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > service.yaml

# Export ServiceAccount
kubectl get serviceaccount -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > serviceaccount.yaml
```

**Step 2: Backup RBAC resources**
```bash
# Export ClusterRole
kubectl get clusterrole ${RELEASE_NAME}-opentelemetry-collector -o yaml > clusterrole.yaml

# Export ClusterRoleBinding
kubectl get clusterrolebinding ${RELEASE_NAME}-opentelemetry-collector -o yaml > clusterrolebinding.yaml
```

**Step 3: Backup optional resources**
```bash
# HPA (if enabled)
kubectl get hpa -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > hpa.yaml 2>/dev/null || echo "HPA not found"

# PDB (if enabled)
kubectl get pdb -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > pdb.yaml 2>/dev/null || echo "PDB not found"

# ServiceMonitor (if enabled)
kubectl get servicemonitor -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > servicemonitor.yaml 2>/dev/null || echo "ServiceMonitor not found"

# Ingress (if enabled)
kubectl get ingress -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml > ingress.yaml 2>/dev/null || echo "Ingress not found"
```

### Manual Backup: Full Backup

**Step 1: Create backup directory**
```bash
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p $BACKUP_DIR/backup-$BACKUP_TIMESTAMP
cd $BACKUP_DIR/backup-$BACKUP_TIMESTAMP
```

**Step 2: Run all backup procedures**
```bash
# Configuration backup
make -f make/ops/opentelemetry-collector.mk otel-backup-config BACKUP_DIR=$(pwd)

# Manifests backup
make -f make/ops/opentelemetry-collector.mk otel-backup-manifests BACKUP_DIR=$(pwd)
```

**Step 3: Create backup manifest**
```bash
cat > BACKUP_MANIFEST.md <<EOF
# OpenTelemetry Collector Backup Manifest
**Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Release Name**: $RELEASE_NAME
**Namespace**: $NAMESPACE
**Backup Directory**: $(pwd)

## Collector Information
- Version: $(kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o jsonpath='{.spec.template.spec.containers[0].image}')
- Replicas: $(kubectl get deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o jsonpath='{.spec.replicas}')
- Mode: $(kubectl get deployment,daemonset -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector -o jsonpath='{.items[0].kind}')

## Backup Contents
- Configuration: otel-config.yaml
- ConfigMap: configmap.yaml
- Manifests: deployment.yaml, service.yaml, clusterrole.yaml, etc.

## Verification
\`\`\`bash
# Verify backup integrity
ls -lh
wc -l otel-config.yaml
\`\`\`
EOF
```

**Step 4: Compress backup (optional)**
```bash
cd $BACKUP_DIR
tar czf backup-$BACKUP_TIMESTAMP.tar.gz backup-$BACKUP_TIMESTAMP/
sha256sum backup-$BACKUP_TIMESTAMP.tar.gz > backup-$BACKUP_TIMESTAMP.tar.gz.sha256
```

### Backup Verification

**Verify configuration syntax:**
```bash
cd $BACKUP_DIR/backup-$BACKUP_TIMESTAMP

# Validate YAML syntax
yamllint otel-config.yaml

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f configmap.yaml
kubectl apply --dry-run=client -f deployment.yaml
```

**Verify backup completeness:**
```bash
# Check required files
required_files=(
  "otel-config.yaml"
  "configmap.yaml"
  "deployment.yaml"
  "service.yaml"
  "clusterrole.yaml"
  "clusterrolebinding.yaml"
  "serviceaccount.yaml"
  "BACKUP_MANIFEST.md"
)

for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    echo "✓ $file"
  else
    echo "✗ $file (missing)"
  fi
done
```

---

## Recovery Procedures

### Recovery Scenario 1: Configuration Recovery

**When to use:**
- Configuration was accidentally modified
- Need to roll back pipeline changes
- Restore after failed configuration update

**Recovery steps:**

**Step 1: Identify backup**
```bash
# List available backups
ls -lt $BACKUP_DIR/config-*/

# Choose backup (replace timestamp)
RESTORE_DIR=$BACKUP_DIR/config-20250127-120000
```

**Step 2: Restore ConfigMap**
```bash
# Delete existing ConfigMap (optional - kubectl apply will update)
kubectl delete configmap -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector --ignore-not-found

# Apply backup ConfigMap
kubectl apply -f $RESTORE_DIR/configmap.yaml
```

**Step 3: Restart collector pods**
```bash
# Restart deployment/daemonset to load new configuration
kubectl rollout restart deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector
# OR
kubectl rollout restart daemonset -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector

# Wait for rollout
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector --timeout=5m
```

**Step 4: Verify recovery**
```bash
# Check pod status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector

# Check logs for errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --tail=50

# Verify health endpoint
kubectl exec -n $NAMESPACE deploy/${RELEASE_NAME}-opentelemetry-collector -- wget -qO- http://localhost:13133
```

### Recovery Scenario 2: Full Disaster Recovery

**When to use:**
- Collector deployment was deleted
- Cluster was rebuilt
- Complete environment restoration

**Recovery steps:**

**Step 1: Identify and extract backup**
```bash
# List backups
ls -lt $BACKUP_DIR/backup-*.tar.gz

# Extract backup
cd $BACKUP_DIR
tar xzf backup-20250127-120000.tar.gz
RESTORE_DIR=$BACKUP_DIR/backup-20250127-120000
```

**Step 2: Verify namespace exists**
```bash
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
```

**Step 3: Restore RBAC resources first**
```bash
# RBAC must be created before deployment
kubectl apply -f $RESTORE_DIR/serviceaccount.yaml
kubectl apply -f $RESTORE_DIR/clusterrole.yaml
kubectl apply -f $RESTORE_DIR/clusterrolebinding.yaml
```

**Step 4: Restore ConfigMap**
```bash
kubectl apply -f $RESTORE_DIR/configmap.yaml
```

**Step 5: Restore deployment/daemonset**
```bash
# Check deployment mode
if [[ -f $RESTORE_DIR/deployment.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/deployment.yaml
elif [[ -f $RESTORE_DIR/daemonset.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/daemonset.yaml
fi
```

**Step 6: Restore service**
```bash
kubectl apply -f $RESTORE_DIR/service.yaml
```

**Step 7: Restore optional resources**
```bash
# HPA
if [[ -f $RESTORE_DIR/hpa.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/hpa.yaml
fi

# PDB
if [[ -f $RESTORE_DIR/pdb.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/pdb.yaml
fi

# ServiceMonitor
if [[ -f $RESTORE_DIR/servicemonitor.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/servicemonitor.yaml
fi

# Ingress
if [[ -f $RESTORE_DIR/ingress.yaml ]]; then
  kubectl apply -f $RESTORE_DIR/ingress.yaml
fi
```

**Step 8: Verify recovery**
```bash
# Wait for pods
kubectl wait --for=condition=ready pod -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --timeout=5m

# Check deployment status
kubectl get deployment,daemonset,pods,svc -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector

# Test health endpoint
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:13133

# Test OTLP receiver (gRPC)
kubectl exec -n $NAMESPACE $POD_NAME -- nc -zv localhost 4317

# Test OTLP receiver (HTTP)
kubectl exec -n $NAMESPACE $POD_NAME -- wget -qO- http://localhost:4318
```

### Recovery Scenario 3: Helm-Based Recovery

**When to use:**
- Original Helm release exists but needs restoration
- Prefer Helm-managed resources
- Configuration drift correction

**Recovery steps:**

**Step 1: Export configuration from backup**
```bash
RESTORE_DIR=$BACKUP_DIR/backup-20250127-120000

# Extract collector config
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o jsonpath='{.data.otel-config\.yaml}' > current-config.yaml
cp $RESTORE_DIR/otel-config.yaml restored-config.yaml
```

**Step 2: Compare configurations**
```bash
diff -u current-config.yaml restored-config.yaml
```

**Step 3: Create Helm values override**
```bash
cat > values-restore.yaml <<EOF
# Restored configuration from backup-20250127-120000
config:
$(cat $RESTORE_DIR/otel-config.yaml | sed 's/^/  /')
EOF
```

**Step 4: Upgrade Helm release**
```bash
helm upgrade $RELEASE_NAME scripton-charts/opentelemetry-collector \
  -n $NAMESPACE \
  -f values-restore.yaml
```

**Step 5: Verify Helm release**
```bash
helm list -n $NAMESPACE
helm get values $RELEASE_NAME -n $NAMESPACE
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector
```

### Recovery Scenario 4: Rollback to Previous Helm Revision

**When to use:**
- Recent Helm upgrade caused issues
- Quick rollback needed
- Helm history available

**Recovery steps:**

**Step 1: List Helm revisions**
```bash
helm history $RELEASE_NAME -n $NAMESPACE
```

**Step 2: Identify target revision**
```bash
# Show values for specific revision
helm get values $RELEASE_NAME -n $NAMESPACE --revision 2
```

**Step 3: Rollback**
```bash
helm rollback $RELEASE_NAME 2 -n $NAMESPACE
```

**Step 4: Verify rollback**
```bash
helm history $RELEASE_NAME -n $NAMESPACE
kubectl rollout status deployment -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector
```

---

## Automation

### Automated Backup via CronJob

**Create backup CronJob:**

```yaml
# otel-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: otel-collector-backup
  namespace: monitoring
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: otel-backup-sa
          containers:
            - name: backup
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
                  BACKUP_DIR=/backups/otel-collector-$BACKUP_DATE
                  mkdir -p $BACKUP_DIR

                  # Backup ConfigMap
                  kubectl get configmap -n monitoring otel-collector-opentelemetry-collector -o yaml > $BACKUP_DIR/configmap.yaml

                  # Backup Deployment
                  kubectl get deployment -n monitoring otel-collector-opentelemetry-collector -o yaml > $BACKUP_DIR/deployment.yaml

                  # Backup Service
                  kubectl get service -n monitoring otel-collector-opentelemetry-collector -o yaml > $BACKUP_DIR/service.yaml

                  echo "Backup completed: $BACKUP_DIR"
              volumeMounts:
                - name: backup-storage
                  mountPath: /backups
          restartPolicy: OnFailure
          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: otel-backup-pvc
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-backup-sa
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: otel-backup-role
  namespace: monitoring
rules:
  - apiGroups: [""]
    resources: ["configmaps", "services"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: otel-backup-rolebinding
  namespace: monitoring
subjects:
  - kind: ServiceAccount
    name: otel-backup-sa
roleRef:
  kind: Role
  name: otel-backup-role
  apiGroup: rbac.authorization.k8s.io
```

**Deploy CronJob:**
```bash
kubectl apply -f otel-backup-cronjob.yaml
```

### Makefile Integration

All backup operations are available via Makefile targets:

```bash
# Configuration backup
make -f make/ops/opentelemetry-collector.mk otel-backup-config

# Manifests backup
make -f make/ops/opentelemetry-collector.mk otel-backup-manifests

# Full backup
make -f make/ops/opentelemetry-collector.mk otel-backup-all

# Backup verification
make -f make/ops/opentelemetry-collector.mk otel-backup-verify BACKUP_DIR=tmp/otel-collector-backups/backup-20250127-120000

# Configuration restore
make -f make/ops/opentelemetry-collector.mk otel-restore-config BACKUP_DIR=tmp/otel-collector-backups/config-20250127-120000

# Full restore
make -f make/ops/opentelemetry-collector.mk otel-restore-all BACKUP_DIR=tmp/otel-collector-backups/backup-20250127-120000
```

---

## Testing & Validation

### Backup Validation

**1. Configuration validity:**
```bash
# Validate YAML syntax
yamllint $BACKUP_DIR/otel-config.yaml

# Validate Kubernetes YAML
kubectl apply --dry-run=client -f $BACKUP_DIR/configmap.yaml
```

**2. Pipeline validation:**
```bash
# Use otelcol validate (if available)
otelcol validate --config=$BACKUP_DIR/otel-config.yaml
```

**3. Backup completeness:**
```bash
# Run verification script
make -f make/ops/opentelemetry-collector.mk otel-backup-verify BACKUP_DIR=$BACKUP_DIR
```

### Recovery Testing

**Test recovery in staging:**
```bash
# 1. Create test namespace
kubectl create namespace otel-test

# 2. Restore to test namespace
export NAMESPACE=otel-test
make -f make/ops/opentelemetry-collector.mk otel-restore-all BACKUP_DIR=$BACKUP_DIR

# 3. Validate deployment
kubectl wait --for=condition=ready pod -n otel-test -l app.kubernetes.io/name=opentelemetry-collector --timeout=5m

# 4. Send test data
kubectl exec -n otel-test -it deploy/otel-collector -- sh
# Inside pod:
wget -qO- http://localhost:13133  # Health check

# 5. Cleanup
kubectl delete namespace otel-test
```

---

## Best Practices

### 1. Backup Schedule

**Recommended frequency:**
- **Configuration**: Before each change
- **Manifests**: Weekly or before major changes
- **Full backup**: Daily (automated)

### 2. Retention Policy

```
Daily backups:     7 days
Weekly backups:    30 days
Monthly backups:   90 days
Annual backups:    1 year (if required for compliance)
```

### 3. Storage Location

**Local backups:**
```bash
# Default location
tmp/otel-collector-backups/

# Organized by date
tmp/otel-collector-backups/2025/01/27/backup-120000/
```

**Remote backups (recommended):**
- S3-compatible storage (MinIO, AWS S3)
- Git repository (for configuration only)
- Network file share (NFS, SMB)

**Example: S3 backup**
```bash
# Upload to S3
aws s3 cp backup-20250127-120000.tar.gz s3://my-backup-bucket/otel-collector/

# Download from S3
aws s3 cp s3://my-backup-bucket/otel-collector/backup-20250127-120000.tar.gz .
```

### 4. Security

**Encrypt sensitive data:**
```bash
# Encrypt backup with GPG
gpg --encrypt --recipient admin@example.com backup-20250127-120000.tar.gz

# Decrypt backup
gpg --decrypt backup-20250127-120000.tar.gz.gpg > backup-20250127-120000.tar.gz
```

**Use sealed secrets:**
```bash
# For secrets in backup
kubeseal --format yaml < secrets.yaml > sealed-secrets.yaml
```

### 5. Documentation

Maintain backup logs:
```bash
# Create backup log
cat >> $BACKUP_DIR/backup-log.txt <<EOF
$(date +"%Y-%m-%d %H:%M:%S") - Backup created: backup-20250127-120000
Namespace: monitoring
Release: otel-collector
Size: $(du -sh backup-20250127-120000.tar.gz | cut -f1)
EOF
```

---

## Troubleshooting

### Issue 1: ConfigMap Not Found

**Symptom:**
```
Error from server (NotFound): configmaps "otel-collector-opentelemetry-collector" not found
```

**Solution:**
```bash
# List all configmaps
kubectl get configmaps -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector

# Check Helm release name
helm list -n $NAMESPACE

# Use correct ConfigMap name
export RELEASE_NAME=$(helm list -n $NAMESPACE -o json | jq -r '.[] | select(.chart | startswith("opentelemetry-collector")) | .name')
```

### Issue 2: Permission Denied

**Symptom:**
```
Error from server (Forbidden): configmaps is forbidden
```

**Solution:**
```bash
# Check permissions
kubectl auth can-i get configmaps -n $NAMESPACE

# Use admin credentials or service account with sufficient permissions
kubectl --as=system:serviceaccount:monitoring:otel-admin get configmaps -n $NAMESPACE
```

### Issue 3: Backup File Too Large

**Symptom:**
Backup file exceeds storage limits

**Solution:**
```bash
# Compress backup
gzip -9 backup-20250127-120000.tar

# Split large files
split -b 100M backup-20250127-120000.tar.gz backup-part-

# Reassemble
cat backup-part-* > backup-20250127-120000.tar.gz
```

### Issue 4: YAML Validation Errors

**Symptom:**
```
error: error validating "configmap.yaml": error validating data
```

**Solution:**
```bash
# Clean up exported YAML
kubectl get configmap -n $NAMESPACE ${RELEASE_NAME}-opentelemetry-collector -o yaml \
  | yq eval 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields)' - \
  > configmap-clean.yaml
```

### Issue 5: Pods Not Starting After Restore

**Symptom:**
Pods in CrashLoopBackOff after configuration restore

**Solution:**
```bash
# Check logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector --tail=100

# Common issues:
# 1. Invalid YAML syntax
yamllint $BACKUP_DIR/otel-config.yaml

# 2. Invalid pipeline configuration
# Check for missing exporters, receivers, or processors

# 3. Network issues
# Verify exporter endpoints are reachable
kubectl exec -n $NAMESPACE deploy/${RELEASE_NAME}-opentelemetry-collector -- nc -zv tempo 4317
```

---

## Appendix: Backup Checklist

### Pre-Backup Checklist

- [ ] Verify kubectl access to cluster
- [ ] Verify namespace and release name
- [ ] Create backup directory structure
- [ ] Check available disk space
- [ ] Review retention policy

### Backup Execution Checklist

- [ ] Export ConfigMap
- [ ] Export collector configuration
- [ ] Export deployment/daemonset
- [ ] Export service
- [ ] Export RBAC resources
- [ ] Export optional resources (HPA, PDB, ServiceMonitor)
- [ ] Create backup manifest
- [ ] Compress backup (optional)
- [ ] Calculate checksum
- [ ] Verify backup integrity

### Post-Backup Checklist

- [ ] Validate YAML syntax
- [ ] Verify backup completeness
- [ ] Document backup location
- [ ] Update backup log
- [ ] Upload to remote storage (if configured)
- [ ] Test restore in non-production environment (quarterly)

---

**Document Version**: 1.0
**Last Updated**: 2025-01-27
**Maintained by**: ScriptonBasestar
**Related**: [opentelemetry-collector-upgrade-guide.md](opentelemetry-collector-upgrade-guide.md)
