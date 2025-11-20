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

## License

BSD-3-Clause. MLflow is Apache 2.0 licensed.

---

**Chart Version:** 0.1.0  
**MLflow Version:** 2.9.2
