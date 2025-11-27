# Apache Airflow

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/airflow)
[![Chart Version](https://img.shields.io/badge/chart-0.1.0-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-2.8.1-green.svg)](https://airflow.apache.org/)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

Opinionated Apache Airflow chart with KubernetesExecutor for workflow orchestration and data pipeline automation.

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-container/sb-helm-charts
helm repo update

# Install chart with default values (KubernetesExecutor)
helm install airflow sb-charts/airflow \
  --set airflow.admin.password=your-secure-password \
  --set postgresql.external.password=pg-password

# Install with production settings
helm install airflow sb-charts/airflow \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/airflow/values-small-prod.yaml \
  --set airflow.admin.password=your-secure-password \
  --set postgresql.external.password=pg-password
```

## Introduction

This chart bootstraps an Apache Airflow deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ KubernetesExecutor for scalable task execution
- ✅ LocalExecutor support for simple deployments
- ✅ Webserver, Scheduler, and Triggerer components
- ✅ PostgreSQL integration (external database)
- ✅ Git-sync for DAG synchronization
- ✅ Persistent logs and DAG storage
- ✅ Auto-generated Fernet and secret keys
- ✅ Remote logging support (S3/MinIO)
- ✅ Production-ready with HA support

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- PersistentVolume provisioner support in the underlying infrastructure

### External Dependencies

**Required:**
- **PostgreSQL**: External PostgreSQL database (recommended 13+)

**Optional:**
- **S3/MinIO**: For remote logging and DAG storage
- **Git Repository**: For DAG synchronization via git-sync

## Installing the Chart

### Quick Start

```bash
# Install with default values (KubernetesExecutor, requires PostgreSQL and admin password)
helm install my-airflow sb-charts/airflow \
  --set airflow.admin.password=admin123 \
  --set postgresql.external.password=pgpass
```

### Deployment Scenarios

This chart includes pre-configured values for different deployment scenarios:

#### Development Environment

```bash
helm install my-airflow sb-charts/airflow \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/airflow/values-dev.yaml
```

**Configuration:**
- LocalExecutor (simple single-scheduler setup)
- Example DAGs enabled for learning
- Minimal resources (250m-1000m CPU, 256Mi-1Gi RAM)
- PVC for DAGs (manual upload)
- Smaller log storage (5Gi)
- Simple admin credentials (change for your environment)

**Use Case:** Local development, testing, learning Airflow

#### Small Production Deployment

```bash
helm install my-airflow sb-charts/airflow \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/airflow/values-small-prod.yaml \
  --set airflow.admin.password=your-secure-password \
  --set postgresql.external.password=pg-password
```

**Configuration:**
- KubernetesExecutor (scalable task execution)
- HA: 2 webserver + 2 scheduler + 1 triggerer replicas
- Git-sync for DAG synchronization
- Remote logging to S3/MinIO
- Production resources (1-2 CPU, 1-2Gi RAM per component)
- Ingress with TLS support
- Pod anti-affinity for HA
- Production annotations (Prometheus scrape)

**Use Case:** Small production deployments, data pipelines, workflow automation

## Configuration

### Deployment Executors

Airflow supports different executors for task execution:

**LocalExecutor:**
- Single scheduler process
- Tasks run on the scheduler machine
- Suitable for development/testing
- Lower resource requirements
- No task distribution

**KubernetesExecutor:**
- Tasks run as Kubernetes pods
- Scalable and isolated task execution
- Each task gets its own pod
- Recommended for production
- Better resource utilization

```yaml
airflow:
  executor: KubernetesExecutor  # or LocalExecutor
```

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `airflow.executor` | Executor type (KubernetesExecutor/LocalExecutor) | `KubernetesExecutor` |
| `airflow.loadExamples` | Load example DAGs | `false` |
| `airflow.parallelism` | Max number of task instances running concurrently | `32` |
| `airflow.admin.username` | Admin username | `admin` |
| `airflow.admin.password` | Admin password (required) | `""` |
| `airflow.fernetKey` | Fernet key for encryption (auto-generated if empty) | `""` |
| `airflow.webserverSecretKey` | Webserver secret key (auto-generated if empty) | `""` |
| `postgresql.external.enabled` | Use external PostgreSQL | `true` |
| `postgresql.external.host` | PostgreSQL host | `postgresql.default.svc.cluster.local` |
| `postgresql.external.database` | PostgreSQL database name | `airflow` |
| `postgresql.external.username` | PostgreSQL username | `airflow` |
| `postgresql.external.password` | PostgreSQL password (required) | `""` |
| `dags.persistence.enabled` | Enable DAG PVC | `false` |
| `dags.gitSync.enabled` | Enable git-sync for DAGs | `false` |
| `logs.persistence.enabled` | Enable log PVC | `true` |
| `logs.persistence.size` | Log storage size | `10Gi` |
| `webserver.replicaCount` | Number of webserver replicas | `1` |
| `scheduler.replicaCount` | Number of scheduler replicas | `1` |
| `triggerer.enabled` | Enable triggerer component | `true` |
| `ingress.enabled` | Enable ingress | `false` |

See [values.yaml](values.yaml) for all available options.

### Fernet Key and Secret Key

Airflow requires Fernet key for encrypting connections and webserver secret key for Flask sessions.

**Auto-generate (development):**
```yaml
airflow:
  fernetKey: ""  # Auto-generated
  webserverSecretKey: ""  # Auto-generated
```

**Manual generation (production):**
```bash
# Generate Fernet key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Generate webserver secret key
openssl rand -hex 32

# Set in values
helm install airflow sb-charts/airflow \
  --set airflow.fernetKey=<fernet-key> \
  --set airflow.webserverSecretKey=<secret-key>
```

### Using Existing Secrets

```yaml
airflow:
  existingSecret: "my-airflow-secret"
  # Secret must contain keys:
  # - fernet-key
  # - webserver-secret-key
  # - admin-password (optional)
  # - postgresql-url
```

### DAG Management

#### Option 1: Git-sync (Recommended for Production)

Automatically synchronize DAGs from a Git repository:

```yaml
dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/airflow-dags.git"
    branch: "main"
    subPath: "dags"  # If DAGs are in subdirectory
    wait: 60  # Sync interval in seconds
```

For private repositories, add SSH key or token via secret.

#### Option 2: PersistentVolume

Manually upload DAGs to PVC:

```yaml
dags:
  persistence:
    enabled: true
    accessMode: ReadWriteMany  # Required for multiple pods
    size: 1Gi
```

Upload DAGs:
```bash
kubectl cp my_dag.py airflow-webserver-0:/opt/airflow/dags/
```

#### Option 3: ConfigMap (Small DAGs)

For development with small DAGs:

```yaml
extraVolumes:
  - name: dags-cm
    configMap:
      name: airflow-dags

extraVolumeMounts:
  - name: dags-cm
    mountPath: /opt/airflow/dags
    readOnly: true
```

### Remote Logging (S3/MinIO)

Store logs in S3-compatible object storage:

```yaml
airflow:
  remoteLogging:
    enabled: true
    remoteBaseLogFolder: "s3://airflow-logs"
    remoteLogConnId: "aws_default"
```

Create connection:
```bash
make -f make/ops/airflow.mk airflow-connections-add \
  CONN_ID=aws_default \
  CONN_TYPE=aws \
  CONN_URI='aws://access_key:secret_key@?host=http://minio:9000'
```

## Persistence

The chart creates Persistent Volumes for logs and optionally for DAGs.

**PVC Configuration:**

```yaml
logs:
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    accessMode: ReadWriteOnce
    size: 50Gi

dags:
  persistence:
    enabled: true
    storageClass: ""
    accessMode: ReadWriteMany  # Required for multiple pods
    size: 1Gi
```

## Networking

### Service Configuration

Webserver service exposes the Airflow UI:

```yaml
webserver:
  service:
    type: ClusterIP  # or LoadBalancer/NodePort
    port: 8080
```

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
  hosts:
    - host: airflow.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: airflow-tls
      hosts:
        - airflow.example.com
```

## Security

### Admin User

Admin user is created automatically during database migrations:

```yaml
airflow:
  admin:
    username: "admin"
    password: "your-secure-password"  # Required
    email: "admin@example.com"
```

**Retrieve password:**
```bash
kubectl get secret airflow-secret -o jsonpath='{.data.admin-password}' | base64 -d
```

### Pod Security Context

Airflow runs as non-root user (UID 50000):

```yaml
podSecurityContext:
  fsGroup: 50000
  runAsUser: 50000
  runAsGroup: 50000

securityContext:
  runAsNonRoot: true
  runAsUser: 50000
  capabilities:
    drop:
      - ALL
```

## High Availability

### Multiple Schedulers

Airflow 2.x supports multiple schedulers for HA:

```yaml
scheduler:
  replicaCount: 2  # HA
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/component
                  operator: In
                  values:
                    - scheduler
            topologyKey: kubernetes.io/hostname
```

### Multiple Webservers

Scale webserver for HA:

```yaml
webserver:
  replicaCount: 2  # HA
```

### Triggerer

For deferrable operators (Airflow 2.2+):

```yaml
triggerer:
  enabled: true
  replicaCount: 1
```

## Monitoring

### Health Probes

Chart includes comprehensive health checks:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Prometheus Integration

Enable Prometheus scraping:

```yaml
webserver:
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
```

## Airflow Setup

### Accessing Web UI

**Port Forward:**
```bash
kubectl port-forward svc/airflow-webserver 8080:8080
# Access at http://localhost:8080
```

**Ingress:**
```yaml
ingress:
  enabled: true
  hosts:
    - host: airflow.example.com
# Access at https://airflow.example.com
```

Login:
- Username: `admin` (or configured value)
- Password: (retrieve with `make -f make/ops/airflow.mk airflow-get-password`)

### Managing DAGs

**List DAGs:**
```bash
make -f make/ops/airflow.mk airflow-dag-list
```

**Trigger a DAG:**
```bash
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag
```

**Pause/Unpause DAG:**
```bash
make -f make/ops/airflow.mk airflow-dag-pause DAG=example_dag
make -f make/ops/airflow.mk airflow-dag-unpause DAG=example_dag
```

### Managing Connections

**List connections:**
```bash
make -f make/ops/airflow.mk airflow-connections-list
```

**Add connection:**
```bash
make -f make/ops/airflow.mk airflow-connections-add \
  CONN_ID=my_postgres \
  CONN_TYPE=postgres \
  CONN_URI='postgresql://user:pass@host:5432/db'
```

### Managing Variables

**List variables:**
```bash
make -f make/ops/airflow.mk airflow-variables-list
```

**Set variable:**
```bash
make -f make/ops/airflow.mk airflow-variables-set KEY=my_var VALUE=my_value
```

### Managing Users

**List users:**
```bash
make -f make/ops/airflow.mk airflow-users-list
```

**Create user:**
```bash
make -f make/ops/airflow.mk airflow-users-create \
  USERNAME=john \
  PASSWORD=secret \
  EMAIL=john@example.com \
  ROLE=Admin
```

## Operational Commands

Using Makefile (`make/ops/airflow.mk`):

### Access and Credentials

```bash
# Get admin password
make -f make/ops/airflow.mk airflow-get-password

# Port forward webserver
make -f make/ops/airflow.mk airflow-port-forward

# Check health
make -f make/ops/airflow.mk airflow-health

# Show version
make -f make/ops/airflow.mk airflow-version
```

### DAG Management

```bash
# List all DAGs
make -f make/ops/airflow.mk airflow-dag-list

# Trigger a DAG
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag

# Trigger with config
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag CONF='{"key":"value"}'

# Pause/unpause DAG
make -f make/ops/airflow.mk airflow-dag-pause DAG=example_dag
make -f make/ops/airflow.mk airflow-dag-unpause DAG=example_dag

# Show DAG state
make -f make/ops/airflow.mk airflow-dag-state DAG=example_dag

# List tasks in DAG
make -f make/ops/airflow.mk airflow-task-list DAG=example_dag
```

### Connections and Variables

```bash
# List connections
make -f make/ops/airflow.mk airflow-connections-list

# Add connection
make -f make/ops/airflow.mk airflow-connections-add \
  CONN_ID=my_db \
  CONN_TYPE=postgres \
  CONN_URI='postgresql://user:pass@host:5432/db'

# List variables
make -f make/ops/airflow.mk airflow-variables-list

# Set variable
make -f make/ops/airflow.mk airflow-variables-set KEY=api_key VALUE=secret
```

### User Management

```bash
# List users
make -f make/ops/airflow.mk airflow-users-list

# Create user
make -f make/ops/airflow.mk airflow-users-create \
  USERNAME=developer \
  PASSWORD=devpass \
  EMAIL=dev@example.com \
  ROLE=User
```

### Database

```bash
# Check database connection
make -f make/ops/airflow.mk airflow-db-check
```

### Logs and Shell

```bash
# View webserver logs
make -f make/ops/airflow.mk airflow-webserver-logs

# View scheduler logs
make -f make/ops/airflow.mk airflow-scheduler-logs

# View all webserver logs
make -f make/ops/airflow.mk airflow-webserver-logs-all

# Open shell in webserver
make -f make/ops/airflow.mk airflow-webserver-shell

# Open shell in scheduler
make -f make/ops/airflow.mk airflow-scheduler-shell
```

### Operations

```bash
# Restart webserver
make -f make/ops/airflow.mk airflow-webserver-restart

# Restart scheduler
make -f make/ops/airflow.mk airflow-scheduler-restart

# Show all resource status
make -f make/ops/airflow.mk airflow-status
```

## Backup & Recovery

### Backup Strategy

Airflow backup consists of three critical components:

1. **Airflow Metadata** (connections, variables, pools, DAG runs)
   - Exported via `airflow db export-archived`
   - Stored as YAML/JSON files

2. **DAGs** (workflow definitions)
   - Backed up from PVC or Git repository
   - Critical for workflow recovery

3. **PostgreSQL Database** (complete state including task history)
   - Backed up via `pg_dump`
   - Stored as SQL dump files

**Recommended Schedule:**

| Environment | Metadata Export | DAGs Backup | DB Dump | Retention |
|-------------|-----------------|-------------|---------|-----------|
| **Production** | Daily (2 AM) | Daily | Daily | 30 days |
| **Staging** | Weekly | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | On-demand | 7 days |

### Backup Commands

**Backup Airflow metadata:**
```bash
make -f make/ops/airflow.mk af-backup-metadata
# Exports connections, variables, pools to tmp/airflow-backups/metadata-<timestamp>.yaml
```

**Backup DAGs from PVC:**
```bash
make -f make/ops/airflow.mk af-backup-dags
# Copies DAG files to tmp/airflow-backups/dags-<timestamp>/
```

**Backup PostgreSQL database:**
```bash
make -f make/ops/airflow.mk af-db-backup
# Creates SQL dump in tmp/airflow-backups/db/airflow-db-<timestamp>.sql
```

**Full backup workflow:**
```bash
# 1. Backup metadata
make -f make/ops/airflow.mk af-backup-metadata

# 2. Backup DAGs
make -f make/ops/airflow.mk af-backup-dags

# 3. Backup database
make -f make/ops/airflow.mk af-db-backup
```

### Recovery Commands

**Restore database from backup:**
```bash
make -f make/ops/airflow.mk af-db-restore FILE=tmp/airflow-backups/db/airflow-db-20251127-020000.sql
```

**Restore DAGs manually:**
```bash
kubectl cp tmp/airflow-backups/dags-20251127-020000/ airflow-webserver-0:/opt/airflow/dags/
```

**Restore metadata manually:**
```bash
# Import connections, variables from backup YAML
kubectl exec -it airflow-webserver-0 -- airflow connections import /path/to/connections.yaml
kubectl exec -it airflow-webserver-0 -- airflow variables import /path/to/variables.json
```

**See Also:** [Airflow Backup & Recovery Guide](../../docs/airflow-backup-guide.md)

---

## Security & RBAC

### RBAC Configuration

Airflow chart includes namespace-scoped RBAC for Kubernetes API access.

**Enable RBAC (default):**
```yaml
rbac:
  create: true
  annotations: {}
```

**Role Permissions:**

The chart creates a Role with these permissions:

- **ConfigMaps**: `get`, `list` (for configuration access)
- **Secrets**: `get`, `list` (for credentials)
- **Pods**: `get`, `list` (for service discovery)
- **PersistentVolumeClaims**: `get`, `list` (for storage)

**KubernetesExecutor Additional Permissions:**

When `airflow.executor=KubernetesExecutor`, the Role includes:

- **Pods**: `create`, `delete`, `get`, `list`, `watch`, `update`, `patch`
- **Pods/log**: `get`, `list`
- **Pods/exec**: `create`, `get`

**Disable RBAC (not recommended for KubernetesExecutor):**
```yaml
rbac:
  create: false
```

### Security Context

Airflow runs as non-root user (UID 50000):

```yaml
podSecurityContext:
  fsGroup: 50000
  runAsUser: 50000
  runAsGroup: 50000

securityContext:
  runAsNonRoot: true
  runAsUser: 50000
  capabilities:
    drop:
      - ALL
```

### Admin Credentials

**Set admin password during installation:**
```bash
helm install airflow sb-charts/airflow \
  --set airflow.admin.password=your-secure-password
```

**Retrieve password from secret:**
```bash
kubectl get secret airflow-secret -o jsonpath='{.data.admin-password}' | base64 -d
```

**Use existing secret:**
```yaml
airflow:
  existingSecret: "my-airflow-secret"
  # Secret must contain keys:
  # - admin-password
  # - fernet-key
  # - webserver-secret-key
  # - postgresql-url
```

### Fernet Key Management

**Auto-generate (development):**
```yaml
airflow:
  fernetKey: ""  # Chart generates random key
```

**Manual generation (production):**
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

helm install airflow sb-charts/airflow \
  --set airflow.fernetKey=<generated-key>
```

**⚠️ Warning:** Changing Fernet key after installation will break existing encrypted connections.

---

## Operations & Maintenance

### Health Checks

**Check overall health:**
```bash
make -f make/ops/airflow.mk airflow-health
# Checks webserver health endpoint
```

**Check Airflow version:**
```bash
make -f make/ops/airflow.mk airflow-version
```

**Check database connection:**
```bash
make -f make/ops/airflow.mk airflow-db-check
```

### Component Restarts

**Restart webserver:**
```bash
make -f make/ops/airflow.mk airflow-webserver-restart
```

**Restart scheduler:**
```bash
make -f make/ops/airflow.mk airflow-scheduler-restart
```

**View all component status:**
```bash
make -f make/ops/airflow.mk airflow-status
```

### Log Management

**View webserver logs:**
```bash
make -f make/ops/airflow.mk airflow-webserver-logs
```

**View scheduler logs:**
```bash
make -f make/ops/airflow.mk airflow-scheduler-logs
```

**View all webserver logs:**
```bash
make -f make/ops/airflow.mk airflow-webserver-logs-all
```

### Shell Access

**Open webserver shell:**
```bash
make -f make/ops/airflow.mk airflow-webserver-shell
```

**Open scheduler shell:**
```bash
make -f make/ops/airflow.mk airflow-scheduler-shell
```

---

## Upgrading

### Pre-Upgrade Checklist

**1. Run pre-upgrade health check:**
```bash
make -f make/ops/airflow.mk af-pre-upgrade-check
```

**2. Backup before upgrade:**
```bash
# Backup metadata
make -f make/ops/airflow.mk af-backup-metadata

# Backup database
make -f make/ops/airflow.mk af-db-backup
```

**3. Review changelog:**
- Check [Apache Airflow Release Notes](https://airflow.apache.org/docs/apache-airflow/stable/release_notes.html)
- Review chart [CHANGELOG.md](../../CHANGELOG.md)

### Upgrade Procedure

**1. Update Helm repository:**
```bash
helm repo update
```

**2. Upgrade chart:**
```bash
helm upgrade my-airflow sb-charts/airflow -f my-values.yaml
```

**3. Run database migrations (if needed):**
```bash
make -f make/ops/airflow.mk af-db-upgrade
```

**4. Post-upgrade validation:**
```bash
make -f make/ops/airflow.mk af-post-upgrade-check
```

**5. Verify deployment:**
```bash
# Check rollout status
kubectl rollout status deployment/airflow-webserver
kubectl rollout status deployment/airflow-scheduler

# Check component health
make -f make/ops/airflow.mk airflow-health
```

### Rollback Procedure

**If upgrade fails, rollback to previous version:**

**1. Display rollback plan:**
```bash
make -f make/ops/airflow.mk af-upgrade-rollback-plan
```

**2. Execute Helm rollback:**
```bash
helm rollback my-airflow
```

**3. Restore database (if needed):**
```bash
make -f make/ops/airflow.mk af-db-restore FILE=tmp/airflow-backups/db/airflow-db-<timestamp>.sql
```

**4. Verify rollback:**
```bash
make -f make/ops/airflow.mk airflow-version
make -f make/ops/airflow.mk airflow-health
```

**See Also:** [Airflow Upgrade Guide](../../docs/airflow-upgrade-guide.md)

---

## Advanced Configuration

### Using Custom ConfigMap

```yaml
airflow:
  existingConfigMap: "my-airflow-config"
```

### ConfigMap and Secret Annotations

For tools like [Reloader](https://github.com/stakater/Reloader) or [External Secrets](https://external-secrets.io/):

```yaml
airflow:
  configMapAnnotations:
    reloader.stakater.com/match: "true"
  secretAnnotations:
    external-secrets.io/backend: vault
```

## Uninstalling

```bash
# Uninstall release
helm uninstall my-airflow

# Optionally delete PVCs (WARNING: This deletes all data!)
kubectl delete pvc -l app.kubernetes.io/name=airflow
```

## Troubleshooting

### Pod not starting

Check logs:
```bash
kubectl logs -l app.kubernetes.io/component=webserver
kubectl logs -l app.kubernetes.io/component=scheduler
```

Common issues:
- **Database connection failed**: Check PostgreSQL credentials and connectivity
- **Fernet key mismatch**: Ensure consistent fernet key across deployments
- **PVC not bound**: Check StorageClass and PV provisioner
- **Permission denied**: Check podSecurityContext.fsGroup (50000)

### Database migrations failed

Check init container logs:
```bash
kubectl logs airflow-webserver-0 -c db-migrations
```

Manually run migrations:
```bash
kubectl exec -it airflow-webserver-0 -- airflow db migrate
```

### DAGs not showing up

**Git-sync:**
```bash
# Check git-sync sidecar logs
kubectl logs airflow-webserver-0 -c git-sync

# Verify repository access
kubectl exec -it airflow-webserver-0 -c git-sync -- ls -la /opt/airflow/dags
```

**PVC:**
```bash
# Check DAG files
kubectl exec -it airflow-webserver-0 -- ls -la /opt/airflow/dags

# Check DAG parsing errors
make -f make/ops/airflow.mk airflow-webserver-shell
airflow dags list-import-errors
```

### Tasks not executing (KubernetesExecutor)

Check scheduler logs:
```bash
make -f make/ops/airflow.mk airflow-scheduler-logs
```

Verify ServiceAccount permissions:
```bash
kubectl get serviceaccount airflow
kubectl describe serviceaccount airflow
```

### Performance Issues

- Increase parallelism: `airflow.parallelism`
- Scale schedulers: `scheduler.replicaCount`
- Scale webservers: `webserver.replicaCount`
- Use KubernetesExecutor for better resource utilization
- Enable remote logging to reduce disk I/O

## Additional Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
- [KubernetesExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
- [Chart Development Guide](../../docs/CHART_DEVELOPMENT_GUIDE.md)
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md)

## License

This Helm chart is licensed under the BSD-3-Clause License.
Apache Airflow is licensed under the Apache License 2.0.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.
