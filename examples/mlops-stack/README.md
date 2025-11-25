# MLOps Stack - Example Deployment

Complete MLOps stack with experiment tracking, model registry, and artifact storage.

## Stack Components

### Experiment Tracking & Model Registry

- **MLflow** - Experiment tracking, model versioning, and registry

### Storage

- **MinIO** - S3-compatible object storage for artifacts
- **PostgreSQL** - Metadata and experiment tracking database

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       MLflow UI (5000)                          │
│                 Experiment Tracking & Model Registry             │
└───────────────────────┬───────────────────┬─────────────────────┘
                        │                   │
                        ▼                   ▼
              ┌──────────────────┐  ┌──────────────────┐
              │    PostgreSQL    │  │      MinIO       │
              │   (Metadata DB)  │  │  (Artifact Store) │
              │     port 5432    │  │    port 9000     │
              └──────────────────┘  └──────────────────┘
                                           │
                                    ┌──────┴───────┐
                                    │ MinIO Console │
                                    │   port 9001   │
                                    └──────────────┘
```

### Data Flow

**Experiment Tracking:**
```
Training Script → MLflow Client → MLflow Server → PostgreSQL (metrics/params)
                                              → MinIO (artifacts/models)
```

**Model Registry:**
```
MLflow Server ← Model Registration ← Training Script
      │
      └─→ PostgreSQL (model metadata, versions, stages)
      └─→ MinIO (model artifacts)
```

## Prerequisites

### 1. Kubernetes Cluster

- Kubernetes 1.19+
- Sufficient resources (see Resource Requirements below)

### 2. Storage

- StorageClass with dynamic provisioning
- Or pre-created PersistentVolumes

### 3. Helm

```bash
helm repo add sb-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

## Installation

### Step 1: Create Namespace

```bash
kubectl create namespace mlops
```

### Step 2: Install Storage (MinIO)

```bash
helm install minio sb-charts/minio \
  -f values-minio.yaml \
  -n mlops
```

### Step 3: Install Database (PostgreSQL)

```bash
helm install postgresql sb-charts/postgresql \
  -f values-postgresql.yaml \
  -n mlops
```

### Step 4: Wait for Dependencies

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n mlops --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n mlops --timeout=300s
```

### Step 5: Install MLflow

```bash
helm install mlflow sb-charts/mlflow \
  -f values-mlflow.yaml \
  -n mlops
```

### Step 6: Verify Installation

```bash
kubectl get pods -n mlops

# Expected output:
# minio-0           1/1     Running
# postgresql-0      1/1     Running
# mlflow-...        1/1     Running
```

## Access

### MLflow UI

```bash
kubectl port-forward -n mlops svc/mlflow 5000:5000
open http://localhost:5000
```

### MinIO Console

```bash
kubectl port-forward -n mlops svc/minio 9001:9001
open http://localhost:9001
# Login: minio-admin / <password-from-values>
```

### PostgreSQL

```bash
kubectl port-forward -n mlops svc/postgresql 5432:5432
# Connect: psql -h localhost -U mlflow -d mlflow
```

## Using MLflow

### Python Client Setup

```python
import mlflow
import os

# Set tracking URI
mlflow.set_tracking_uri("http://mlflow.mlops.svc.cluster.local:5000")
# Or for local development:
# mlflow.set_tracking_uri("http://localhost:5000")

# Set experiment
mlflow.set_experiment("my-experiment")

# Log a run
with mlflow.start_run():
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_artifact("model.pkl")
```

### Environment Variables for S3 Artifacts

When logging artifacts directly to MinIO:

```python
import os

os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://minio.mlops.svc.cluster.local:9000"
os.environ["AWS_ACCESS_KEY_ID"] = "minio-admin"
os.environ["AWS_SECRET_ACCESS_KEY"] = "<your-secret-key>"
```

### Registering Models

```python
# Log and register a model
with mlflow.start_run():
    mlflow.sklearn.log_model(model, "model", registered_model_name="my-model")

# Or register an existing run's model
mlflow.register_model("runs:/<run-id>/model", "my-model")
```

### Model Stages

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()

# Transition model to staging
client.transition_model_version_stage(
    name="my-model",
    version=1,
    stage="Staging"
)

# Transition to production
client.transition_model_version_stage(
    name="my-model",
    version=1,
    stage="Production"
)
```

## Configuration

### MinIO Buckets

The `mlflow` bucket is created automatically. To create additional buckets:

```bash
kubectl exec -n mlops minio-0 -- mc mb /data/my-bucket
```

### PostgreSQL Databases

Additional databases can be created:

```bash
kubectl exec -n mlops postgresql-0 -- psql -U postgres -c "CREATE DATABASE mydb;"
```

### MLflow Experiments

Create experiments programmatically or via UI:

```python
mlflow.create_experiment("production-models", artifact_location="s3://mlflow/production")
```

## Resource Requirements

### Minimum (Development)

- 2 CPU cores
- 4 GB RAM
- 30 GB storage

### Recommended (Production)

- 4 CPU cores
- 8 GB RAM
- 100 GB storage

### Per Component

| Component | CPU (req/limit) | Memory (req/limit) | Storage |
|-----------|-----------------|-------------------|---------|
| MLflow | 100m/1000m | 256Mi/1Gi | - |
| PostgreSQL | 100m/500m | 256Mi/1Gi | 10Gi |
| MinIO | 100m/1000m | 256Mi/2Gi | 50Gi |

## Scaling

### MLflow

```yaml
# Increase replicas for HA
replicaCount: 3
```

### MinIO

For production, consider MinIO distributed mode:

```yaml
replicaCount: 4
minio:
  mode: distributed
  drivesPerNode: 1
```

### PostgreSQL

For HA, consider using PostgreSQL Operator (Zalando, CloudNativePG):

```bash
# See docs/migrations/postgresql-to-operator.md
```

## Backup & Recovery

### MinIO

```bash
# Create bucket backup
kubectl exec -n mlops minio-0 -- mc mirror /data/mlflow /backup/mlflow-backup

# Restore
kubectl exec -n mlops minio-0 -- mc mirror /backup/mlflow-backup /data/mlflow
```

### PostgreSQL

```bash
# Backup
kubectl exec -n mlops postgresql-0 -- pg_dump -U mlflow mlflow > mlflow-backup.sql

# Restore
kubectl exec -i -n mlops postgresql-0 -- psql -U mlflow mlflow < mlflow-backup.sql
```

## Troubleshooting

### MLflow Cannot Connect to PostgreSQL

```bash
# Check PostgreSQL is running
kubectl get pods -n mlops -l app.kubernetes.io/name=postgresql

# Check PostgreSQL logs
kubectl logs -n mlops -l app.kubernetes.io/name=postgresql

# Verify connection from MLflow pod
kubectl exec -n mlops -l app.kubernetes.io/name=mlflow -- \
  python -c "import psycopg2; psycopg2.connect('postgresql://mlflow:mlflow-password@postgresql:5432/mlflow')"
```

### MLflow Cannot Write to MinIO

```bash
# Check MinIO is running
kubectl get pods -n mlops -l app.kubernetes.io/name=minio

# Verify bucket exists
kubectl exec -n mlops minio-0 -- mc ls /data/

# Test write access
kubectl exec -n mlops minio-0 -- mc cp /etc/hosts /data/mlflow/test.txt
```

### Experiments Not Showing

```bash
# Check MLflow server logs
kubectl logs -n mlops -l app.kubernetes.io/name=mlflow

# Verify database connection
kubectl exec -n mlops postgresql-0 -- psql -U mlflow -d mlflow -c "SELECT * FROM experiments;"
```

## Uninstallation

```bash
# Remove components
helm uninstall -n mlops mlflow postgresql minio

# (Optional) Delete namespace and PVCs
kubectl delete namespace mlops
```

## Next Steps

1. **Add GPU Support**: Configure node selectors for GPU training jobs
2. **Add Model Serving**: Deploy MLflow model serving or KServe
3. **Enable Monitoring**: Add Prometheus metrics for MLflow
4. **Set Up CI/CD**: Integrate with GitHub Actions for automated training
5. **Add Authentication**: Enable MLflow authentication via reverse proxy
6. **Scale Storage**: Expand MinIO to distributed mode

## References

- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
