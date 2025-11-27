# MLflow Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)
![AppVersion: 2.9.2](https://img.shields.io/badge/AppVersion-2.9.2-informational?style=flat-square)

MLflow experiment tracking and model registry platform for machine learning.

## Features

- ✅ **MLflow 2.9.2** - Latest version
- ✅ **PostgreSQL Backend** - Production-ready database
- ✅ **MinIO/S3 Artifacts** - Scalable artifact storage
- ✅ **Easy Development** - SQLite + local storage fallback
- ✅ **Model Registry** - Track and version models
- ✅ **Python Integration** - Native MLflow client support

## Quick Start

```bash
# Development (SQLite + local storage)
helm install my-mlflow scripton-charts/mlflow \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mlflow/values-dev.yaml

# Access MLflow UI
kubectl port-forward svc/my-mlflow 5000:5000
# Open http://localhost:5000
```

## Production Setup

```bash
# Install with PostgreSQL and MinIO
helm install my-mlflow scripton-charts/mlflow \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/mlflow/values-prod.yaml \
  --set postgresql.external.password='<DB_PASSWORD>' \
  --set minio.external.accessKey='<MINIO_KEY>' \
  --set minio.external.secretKey='<MINIO_SECRET>'
```

## Python Client Usage

```python
import mlflow

# Set tracking URI
mlflow.set_tracking_uri("http://my-mlflow.default.svc.cluster.local:5000")

# Log experiment
with mlflow.start_run():
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_artifact("model.pkl")
```

## Configuration

### External PostgreSQL

```yaml
postgresql:
  external:
    enabled: true
    host: "postgresql.default.svc.cluster.local"
    database: "mlflow"
    username: "mlflow"
    password: "<password>"
```

### External MinIO/S3

```yaml
minio:
  external:
    enabled: true
    endpoint: "http://minio:9000"
    accessKey: "<access-key>"
    secretKey: "<secret-key>"
    bucket: "mlflow"
```

## Values Profiles

- **values-dev.yaml**: SQLite + local storage, single replica
- **values-prod.yaml**: PostgreSQL + MinIO, 2 replicas, HA

## Backup & Recovery

MLflow supports comprehensive backup and recovery procedures for production deployments.

### Backup Strategy

MLflow backup consists of three critical components:

1. **Experiments & Runs Metadata** (tracking server data)
2. **PostgreSQL Database** (backend store - if using external DB)
3. **Artifacts** (model files, plots, data files)

### Backup Commands

```bash
# 1. Backup experiments metadata
make -f make/ops/mlflow.mk mlflow-experiments-backup

# 2. Backup PostgreSQL database (if using external DB)
make -f make/ops/mlflow.mk mlflow-db-backup

# 3. Backup artifacts from S3/MinIO
aws s3 sync s3://mlflow-artifacts ./tmp/mlflow-backups/artifacts/$(date +%Y%m%d-%H%M%S)/

# 4. Verify backups
ls -lh tmp/mlflow-backups/experiments/
ls -lh tmp/mlflow-backups/db/
```

**Backup storage locations:**
```
tmp/mlflow-backups/
├── experiments/               # Metadata exports
│   ├── YYYYMMDD-HHMMSS/
│   │   ├── experiments.json
│   │   └── models.json
├── db/                        # Database dumps
│   └── mlflow-db-YYYYMMDD-HHMMSS.sql
└── artifacts/                 # Artifact backups
    └── YYYYMMDD-HHMMSS/
```

### Recovery Commands

```bash
# 1. Restore database from backup
make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/db/mlflow-db-YYYYMMDD-HHMMSS.sql

# 2. Restore artifacts
aws s3 sync ./tmp/mlflow-backups/artifacts/YYYYMMDD-HHMMSS/ s3://mlflow-artifacts/

# 3. Verify recovery
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

### Best Practices

- **Production**: Daily automated backups + pre-upgrade backups
- **Retention**: 30 days (daily), 90 days (weekly), 1 year (monthly)
- **Verification**: Test restores quarterly
- **Security**: Encrypt backups at rest and in transit

**📖 Complete guide**: See [docs/mlflow-backup-guide.md](../../docs/mlflow-backup-guide.md) for detailed backup/recovery procedures.

---

## Upgrading

MLflow supports multiple upgrade strategies with database migration support.

### Pre-Upgrade Checklist

```bash
# 1. Run pre-upgrade health check
make -f make/ops/mlflow.mk mlflow-pre-upgrade-check

# 2. Backup everything
make -f make/ops/mlflow.mk mlflow-experiments-backup
make -f make/ops/mlflow.mk mlflow-db-backup

# 3. Review changelog
# - Check MLflow release notes: https://github.com/mlflow/mlflow/releases
# - Review chart CHANGELOG.md

# 4. Test in staging
helm upgrade mlflow-staging charts/mlflow -n staging -f values-staging.yaml
```

### Upgrade Procedures

**Method 1: Standard Upgrade (Recommended)**
```bash
# Scale down to prevent writes during migration
kubectl scale deployment mlflow --replicas=0

# Backup database
make -f make/ops/mlflow.mk mlflow-db-backup

# Upgrade chart
helm upgrade mlflow charts/mlflow -f values.yaml --wait --timeout=10m

# Run database migrations
make -f make/ops/mlflow.mk mlflow-db-upgrade

# Scale up
kubectl scale deployment mlflow --replicas=1

# Verify deployment
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

**Method 2: Blue-Green Upgrade (Zero downtime)**
```bash
# Deploy new "green" environment
helm install mlflow-green charts/mlflow -f values.yaml --set fullnameOverride=mlflow-green

# Run database migrations on green
kubectl exec -it mlflow-green-0 -- mlflow db upgrade $MLFLOW_BACKEND_STORE_URI

# Validate green deployment
kubectl exec -it mlflow-green-0 -- curl http://localhost:5000/health

# Switch traffic (update Service selector or Ingress)
kubectl patch service mlflow -p '{"spec":{"selector":{"app.kubernetes.io/instance":"mlflow-green"}}}'

# Decommission blue after validation
helm uninstall mlflow
```

**Method 3: In-Place Upgrade (Quick patch upgrades)**
```bash
# Upgrade chart (rolling update)
helm upgrade mlflow charts/mlflow -f values.yaml --set image.tag=3.11-slim

# Run database migrations if needed
make -f make/ops/mlflow.mk mlflow-db-upgrade

# Verify deployment
make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

### Post-Upgrade Validation

```bash
# Automated validation
make -f make/ops/mlflow.mk mlflow-post-upgrade-check

# Manual checks
kubectl get pods -l app.kubernetes.io/name=mlflow
kubectl exec -it mlflow-0 -- python -c "import mlflow; print(f'MLflow version: {mlflow.__version__}')"
kubectl exec -it mlflow-0 -- curl http://localhost:5000/health

# Test experiment access
kubectl exec -it mlflow-0 -- mlflow experiments search --max-results 5
```

### Rollback Procedures

**Option 1: Helm Rollback (Fast)**
```bash
make -f make/ops/mlflow.mk mlflow-upgrade-rollback  # Display rollback plan
helm rollback mlflow
make -f make/ops/mlflow.mk mlflow-health
```

**Option 2: Database Restore (Complete)**
```bash
kubectl scale deployment mlflow --replicas=0

make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/pre-upgrade-YYYYMMDD-HHMMSS/mlflow-db-*.sql

helm rollback mlflow

kubectl scale deployment mlflow --replicas=1

make -f make/ops/mlflow.mk mlflow-post-upgrade-check
```

**📖 Complete guide**: See [docs/mlflow-upgrade-guide.md](../../docs/mlflow-upgrade-guide.md) for detailed upgrade procedures and version-specific notes.

---

## License

BSD-3-Clause. MLflow is Apache 2.0 licensed.

---

**Chart Version:** 0.1.0  
**MLflow Version:** 2.9.2
