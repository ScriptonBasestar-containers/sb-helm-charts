# Immich Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/immich)

[Immich](https://immich.app/) is a high-performance self-hosted photo and video management solution with AI-powered features including facial recognition, object detection, and smart search.

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install my-immich scripton-charts/immich \
  --set postgresql.external.host=postgres.default.svc \
  --set postgresql.external.password=strongpass \
  --set redis.external.host=redis.default.svc
```

## Introduction

This chart bootstraps an Immich deployment on a Kubernetes cluster using microservices architecture.

**Key Features:**
- 🎯 Microservices architecture (server + machine-learning)
- 🤖 AI-powered features (facial recognition, object detection, CLIP search)
- 📦 External PostgreSQL + Redis (pgvecto.rs extension required)
- 🚀 Hardware acceleration support (CUDA, ROCm, OpenVINO, ARMNN)
- 📱 Mobile app support (iOS & Android)
- 🔒 Production-ready with HPA, PDB, NetworkPolicy

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install immich-home charts/immich \
  -f charts/immich/values-home-single.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 20Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install immich-startup charts/immich \
  -f charts/immich/values-startup-single.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 50Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with machine learning and enhanced storage:

```bash
helm install immich-prod charts/immich \
  -f charts/immich/values-prod-master-replica.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Features:** ML-powered photo recognition, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 100Gi storage

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#immich).


- Kubernetes 1.19+
- Helm 3.0+
- **External PostgreSQL 14+** with [pgvecto.rs](https://github.com/tensorchord/pgvecto.rs) extension
- **External Redis/Valkey 6+**
- PV provisioner support

## Versioning

| Chart Version | App Version | Kubernetes | Helm | Notes |
|---------------|-------------|------------|------|-------|
| 0.1.0         | v1.122.3    | 1.19+      | 3.0+ | Initial release with microservices |

## Architecture

Immich consists of two main services:

1. **Server** (immich-server)
   - REST API backend
   - Web UI serving
   - Database & Redis coordination
   - Photo/video upload handling

2. **Machine Learning** (immich-ml)
   - Facial recognition
   - Object detection (CLIP)
   - Smart search indexing
   - Hardware acceleration (optional)

## Installing the Chart

### Basic Installation

```bash
helm install my-immich scripton-charts/immich \
  --set postgresql.external.host=postgres-host \
  --set postgresql.external.password=dbpass \
  --set redis.external.host=redis-host
```

### Production Installation with GPU

```bash
helm install my-immich scripton-charts/immich \
  -f values-example.yaml \
  --set postgresql.external.password=strongpass \
  --set redis.external.password=redispass
```

## Configuration

### Core Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `immich.server.enabled` | Enable server service | `true` |
| `immich.server.replicaCount` | Server replicas | `1` |
| `immich.machineLearning.enabled` | Enable ML service | `true` |
| `immich.machineLearning.acceleration` | Hardware acceleration (`none`, `cuda`, `rocm`, `openvino`) | `none` |

### External Services (REQUIRED)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.external.host` | PostgreSQL hostname | `""` (REQUIRED) |
| `postgresql.external.password` | PostgreSQL password | `""` (REQUIRED) |
| `redis.external.host` | Redis hostname | `""` (REQUIRED) |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.library.size` | Photo library size | `100Gi` |
| `immich.machineLearning.modelCache.size` | ML model cache | `10Gi` |

## S3 Object Storage

Immich can use S3-compatible object storage (MinIO, AWS S3, etc.) for photo and video storage instead of local PVCs.

### Quick Configuration

```yaml
immich:
  server:
    extraEnv:
      - name: IMMICH_MEDIA_LOCATION
        value: "s3"
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: immich-s3-credentials
            key: access-key-id
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: immich-s3-credentials
            key: secret-access-key
      - name: AWS_ENDPOINT
        value: "http://minio.default.svc.cluster.local:9000"
      - name: AWS_REGION
        value: "us-east-1"
      - name: AWS_S3_BUCKET
        value: "immich-media"
      - name: AWS_S3_FORCE_PATH_STYLE
        value: "true"
```

Create S3 credentials secret:
```bash
kubectl create secret generic immich-s3-credentials \
  --from-literal=access-key-id=immich-user \
  --from-literal=secret-access-key=immich-secure-password
```

**Benefits:**
- Significantly reduced PVC requirements (only thumbnails/cache need local storage)
- Scalable storage independent of pod lifecycle
- Multi-region replication support
- Lower storage costs

For complete S3 integration guide including MinIO setup, bucket creation, and security best practices, see the [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md#immich-photo--video-storage).

## Hardware Acceleration

Enable GPU acceleration for ML workloads:

### NVIDIA CUDA

```yaml
immich:
  machineLearning:
    acceleration: "cuda"
    resources:
      limits:
        nvidia.com/gpu: 1
```

### AMD ROCm

```yaml
immich:
  machineLearning:
    acceleration: "rocm"
```

### Intel OpenVINO

```yaml
immich:
  machineLearning:
    acceleration: "openvino"
```

## Backup & Recovery

Immich stores critical data across multiple components requiring a comprehensive backup strategy.

### Backup Components

| Component | Priority | Storage Size | Recovery Time |
|-----------|----------|--------------|---------------|
| Library PVC | **HIGH** | 100+ GB | < 2 hours |
| PostgreSQL DB | **HIGH** | 1-10 GB | < 30 minutes |
| Redis Cache | LOW | < 100 MB | < 10 minutes |
| ML Model Cache | MEDIUM | ~10 GB | < 1 hour |
| Configuration | HIGH | < 1 MB | < 10 minutes |

### Quick Backup

```bash
# Full backup (all components)
make -f make/ops/immich.mk immich-full-backup

# Individual component backups
make -f make/ops/immich.mk immich-backup-library      # Photos/videos (largest)
make -f make/ops/immich.mk immich-backup-db           # PostgreSQL metadata
make -f make/ops/immich.mk immich-backup-config       # Kubernetes configuration
```

### Recovery Workflow

```bash
# 1. Prepare environment (create namespace, secrets)
# 2. Restore PostgreSQL database
make -f make/ops/immich.mk immich-restore-db BACKUP_FILE=/backup/immich/db.dump

# 3. Restore library PVC
make -f make/ops/immich.mk immich-restore-library BACKUP_PATH=/backup/immich/library

# 4. Deploy Immich
helm install immich scripton-charts/immich -f values-recovery.yaml

# 5. Validate recovery
make -f make/ops/immich.mk immich-post-recovery-check
```

### Backup Strategies

**Incremental Backup (Recommended):**
```bash
# Using Restic for deduplication and compression
make -f make/ops/immich.mk immich-backup-library-restic
```

**Volume Snapshot (Fastest):**
```bash
# Requires CSI snapshot support
make -f make/ops/immich.mk immich-snapshot-library
```

### Recovery Targets

- **RTO (Recovery Time Objective):** < 2 hours
- **RPO (Recovery Point Objective):** 24 hours (with daily backups)

### Best Practices

1. ✅ **Daily backups** of Library PVC and PostgreSQL database
2. ✅ **Weekly backups** of ML model cache (optional, can be re-downloaded)
3. ✅ **3-2-1 rule**: 3 copies, 2 different media, 1 offsite
4. ✅ **Test restores** monthly to verify backup integrity
5. ✅ **Encrypt backups** containing sensitive photo metadata

**Comprehensive Guide:** [Immich Backup & Recovery Guide](../../docs/immich-backup-guide.md) - Detailed procedures, disaster recovery, and troubleshooting (1,046 lines)

---

## Security & RBAC

This chart includes comprehensive RBAC (Role-Based Access Control) for namespace-scoped resource access.

### RBAC Resources

**Role** (namespace-scoped):
- **ConfigMaps**: Read access for configuration
- **Secrets**: Read access for database credentials, Redis passwords, S3 keys
- **Pods**: Read access for health checks and operations
- **Services**: Read access for service discovery
- **Endpoints**: Read access for service discovery
- **PersistentVolumeClaims**: Read access for storage operations

**RoleBinding**: Links Role to ServiceAccount

### Configuration

```yaml
# Enable RBAC (default: enabled)
rbac:
  create: true
  annotations: {}

# ServiceAccount configuration
serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""  # Auto-generated if empty
```

### Security Context

**Pod Security:**
```yaml
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Immich needs write access for uploads
```

### Network Security

**NetworkPolicy** (optional):
```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: nginx-ingress
      ports:
        - protocol: TCP
          port: 2283
  egress:
    - to:
      - podSelector:
          matchLabels:
            app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    - to:
      - podSelector:
          matchLabels:
            app: redis
      ports:
        - protocol: TCP
          port: 6379
```

### Best Practices

1. ✅ Use **dedicated ServiceAccount** per Immich installation
2. ✅ Enable **NetworkPolicy** to restrict pod-to-pod communication
3. ✅ Use **Secrets** for sensitive data (database passwords, S3 credentials)
4. ✅ Enable **TLS/HTTPS** for Ingress (production requirement)
5. ✅ Regularly **rotate credentials** (database passwords, Redis passwords)
6. ✅ Use **Pod Security Standards** (Baseline or Restricted)

**RBAC Verification:**
```bash
# Check RBAC resources
kubectl get role,rolebinding -n $NAMESPACE -l app.kubernetes.io/instance=immich

# Verify ServiceAccount permissions
kubectl auth can-i get configmaps --as=system:serviceaccount:default:immich -n default
```

---

## Operations

### Daily Operations

```bash
# Port forward to localhost
make -f make/ops/immich.mk immich-port-forward

# View logs
make -f make/ops/immich.mk immich-logs-server
make -f make/ops/immich.mk immich-logs-ml

# Check connectivity
make -f make/ops/immich.mk immich-check-db
make -f make/ops/immich.mk immich-check-redis

# Get version
make -f make/ops/immich.mk immich-get-version
```

### Monitoring & Health Checks

```bash
# Check pod status
make -f make/ops/immich.mk immich-status

# Verify database connectivity
make -f make/ops/immich.mk immich-check-db

# Check ML service health
make -f make/ops/immich.mk immich-check-ml

# View resource usage
kubectl top pods -n $NAMESPACE -l app.kubernetes.io/instance=immich
```

### Database Operations

```bash
# Connect to PostgreSQL
make -f make/ops/immich.mk immich-db-shell

# Run SQL query
make -f make/ops/immich.mk immich-db-query QUERY="SELECT COUNT(*) FROM assets;"

# Check database size
make -f make/ops/immich.mk immich-db-size

# Vacuum database (maintenance)
make -f make/ops/immich.mk immich-db-vacuum
```

### ML Model Management

```bash
# List downloaded models
make -f make/ops/immich.mk immich-list-ml-models

# Check ML cache usage
make -f make/ops/immich.mk immich-check-ml-cache

# Clear ML cache (forces re-download)
make -f make/ops/immich.mk immich-clear-ml-cache
```

### Scaling Operations

```bash
# Scale server horizontally
kubectl scale deployment immich-server -n $NAMESPACE --replicas=3

# Scale ML service
kubectl scale statefulset immich-machine-learning -n $NAMESPACE --replicas=2

# Enable HorizontalPodAutoscaler
helm upgrade immich scripton-charts/immich \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=2 \
  --set autoscaling.maxReplicas=5 \
  --reuse-values
```

### Performance Tuning

**Database Optimization:**
```bash
# Analyze database
make -f make/ops/immich.mk immich-db-analyze

# Reindex database
make -f make/ops/immich.mk immich-db-reindex
```

**Resource Adjustment:**
```yaml
immich:
  server:
    resources:
      limits:
        cpu: 4000m      # Increase for high upload concurrency
        memory: 4Gi     # Increase for large photo libraries
      requests:
        cpu: 1000m
        memory: 2Gi

  machineLearning:
    resources:
      limits:
        cpu: 8000m      # Increase for faster ML processing
        memory: 8Gi     # Increase for large ML models
      requests:
        cpu: 2000m
        memory: 4Gi
```

### Troubleshooting

**Common Issues:**

1. **Photos not appearing after upload**
   ```bash
   # Check server logs
   make -f make/ops/immich.mk immich-logs-server | grep -i error

   # Verify library PVC mount
   kubectl exec -n $NAMESPACE immich-server-0 -- ls -la /data
   ```

2. **ML features not working**
   ```bash
   # Check ML service logs
   make -f make/ops/immich.mk immich-logs-ml

   # Verify ML models downloaded
   make -f make/ops/immich.mk immich-list-ml-models
   ```

3. **Database connection failures**
   ```bash
   # Test database connectivity
   make -f make/ops/immich.mk immich-check-db

   # Verify credentials
   kubectl get secret -n $NAMESPACE
   ```

**Complete Troubleshooting:** [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md#immich)

---

## Upgrading

Immich is under active development with frequent releases. This chart supports multiple upgrade strategies.

### Pre-Upgrade Checklist

**CRITICAL: Always backup before upgrading**

```bash
# 1. Review release notes
# Visit: https://github.com/immich-app/immich/releases

# 2. Full backup
make -f make/ops/immich.mk immich-full-backup

# 3. Pre-upgrade check
make -f make/ops/immich.mk immich-pre-upgrade-check
```

### Upgrade Strategies

#### Strategy 1: Rolling Upgrade (Zero Downtime)

**Best for:** Patch and minor version upgrades (e.g., v1.119.0 → v1.120.0)

```bash
# Upgrade using Helm
helm upgrade immich scripton-charts/immich \
  --set immich.server.image.tag=v1.120.0 \
  --set immich.machineLearning.image.tag=v1.120.0 \
  --reuse-values \
  --wait

# Or using Makefile
make -f make/ops/immich.mk immich-rolling-upgrade VERSION=v1.120.0
```

**Advantages:**
- ✅ Zero downtime
- ✅ Automatic rollback on failure
- ✅ Gradual pod replacement

**Downtime:** None

#### Strategy 2: Blue-Green Deployment

**Best for:** Major version upgrades (e.g., v1.x → v2.x)

```bash
# Deploy green environment (new version)
make -f make/ops/immich.mk immich-blue-green-deploy VERSION=v2.0.0

# Validate green environment
# (Test thoroughly before cutover)

# Switch traffic to green
make -f make/ops/immich.mk immich-blue-green-cutover

# Cleanup blue environment (after validation)
make -f make/ops/immich.mk immich-blue-green-cleanup
```

**Advantages:**
- ✅ Easy rollback (switch back to blue)
- ✅ Parallel testing before cutover
- ✅ Low risk

**Downtime:** 10-30 minutes (cutover)

#### Strategy 3: Maintenance Window

**Best for:** Major upgrades with breaking changes

```bash
# Schedule maintenance window
# Notify users of downtime

# Run maintenance upgrade
make -f make/ops/immich.mk immich-maintenance-upgrade VERSION=v2.0.0

# Post-upgrade validation
make -f make/ops/immich.mk immich-post-upgrade-check
```

**Advantages:**
- ✅ Simple process
- ✅ Full control over timing

**Downtime:** 30 minutes - 2 hours

### Post-Upgrade Validation

```bash
# Automated validation
make -f make/ops/immich.mk immich-post-upgrade-check

# Manual checks
# 1. Verify all pods running
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=immich

# 2. Check image versions
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=immich \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# 3. Test web interface
kubectl port-forward -n $NAMESPACE svc/immich 2283:2283
# Visit http://localhost:2283

# 4. Verify photo count
make -f make/ops/immich.mk immich-check-photo-count
```

### Rollback Procedures

**Helm Rollback (Simple):**
```bash
# Rollback to previous revision
helm rollback immich -n $NAMESPACE

# Or using Makefile
make -f make/ops/immich.mk immich-upgrade-rollback
```

**Full Rollback (Database + Application):**
```bash
# 1. Stop application
kubectl scale deployment immich-server -n $NAMESPACE --replicas=0

# 2. Restore database
make -f make/ops/immich.mk immich-restore-db BACKUP_FILE=/backup/immich/pre-upgrade/db.dump

# 3. Rollback Helm
helm rollback immich -n $NAMESPACE

# 4. Restart application
kubectl scale deployment immich-server -n $NAMESPACE --replicas=2
```

### Version-Specific Notes

**Immich v1.119.x → v1.120.x:**
- ✅ Rolling upgrade supported
- ✅ Automatic database migrations
- ✅ No configuration changes required

**Immich v1.x → v2.x (Future):**
- ⚠️ Major version - use Blue-Green or Maintenance Window
- ⚠️ Review breaking changes in release notes
- ⚠️ Test in staging environment first
- ⚠️ Expect manual migration steps

### Best Practices

1. ✅ **Backup first** - Always create full backup before upgrading
2. ✅ **Test in staging** - Validate upgrade in non-production environment
3. ✅ **Read release notes** - Understand breaking changes and requirements
4. ✅ **Monitor closely** - Watch logs and metrics during upgrade
5. ✅ **Plan rollback** - Have rollback procedure ready

**Comprehensive Guide:** [Immich Upgrade Guide](../../docs/immich-upgrade-guide.md) - Detailed strategies, database migrations, troubleshooting (1,101 lines)

## PostgreSQL Setup

Immich requires **pgvecto.rs** extension. Install it on your PostgreSQL:

```sql
CREATE EXTENSION IF NOT EXISTS vectors;
```

Or use PostgreSQL with extension pre-installed:
```yaml
postgresql:
  image: tensorchord/pgvecto-rs:pg17-v0.3.0
```

## Mobile App Setup

1. Install mobile app: [Immich Mobile](https://immich.app/docs/install/mobile)
2. Configure server URL in app settings
3. Use HTTPS for production deployments

## Troubleshooting

### PostgreSQL Extension Missing

**Error**: `extension "vectors" does not exist`

**Solution**: Install pgvecto.rs extension on PostgreSQL server.

### ML Service Not Processing

Check ML logs:
```bash
make -f make/ops/immich.mk immich-logs-ml
```

Verify model cache:
```bash
make -f make/ops/immich.mk immich-check-ml-cache
```

## Project Philosophy

Follows [ScriptonBasestar Helm Charts](https://github.com/scriptonbasestar-container/sb-helm-charts) principles:

- ✅ External databases (PostgreSQL + Redis)
- ✅ Microservices architecture
- ✅ Production-ready defaults
- ✅ No complex subcharts

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

- **Chart License:** BSD-3-Clause
- **Immich License:** AGPL-3.0

## Links

- **Immich Official:** https://immich.app
- **Documentation:** https://docs.immich.app
- **Docker Hub:** https://github.com/immich-app/immich/pkgs/container/immich-server
- **Chart Repository:** https://github.com/scriptonbasestar-container/sb-helm-charts

## Support

For issues: https://github.com/scriptonbasestar-container/sb-helm-charts/issues
