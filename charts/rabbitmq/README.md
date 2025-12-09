# RabbitMQ Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/rabbitmq)

A production-ready Helm chart for deploying [RabbitMQ](https://www.rabbitmq.com/) message broker on Kubernetes with management UI and Prometheus metrics support.

## ⚠️ Production Consideration

**For production environments requiring clustering and high availability**, consider using [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator):

- ✅ Native RabbitMQ clustering support
- ✅ Automatic node recovery
- ✅ CRD-based management
- ✅ Official operator from RabbitMQ team

**This chart is recommended for:**
- Development/testing environments
- Single-node deployments
- Simple message queuing needs
- Configuration-first approach preference

## Overview

RabbitMQ is a widely-used open-source message broker that implements the Advanced Message Queuing Protocol (AMQP). This chart provides a simple, configuration-first approach to deploying RabbitMQ on Kubernetes.

### Features

- ✅ **Configuration-First Design**: Native `rabbitmq.conf` and `enabled_plugins` mounted as ConfigMaps
- ✅ **Management UI**: Built-in web interface for monitoring and management (port 15672)
- ✅ **Prometheus Metrics**: Export metrics via `rabbitmq_prometheus` plugin (port 15692)
- ✅ **Persistent Storage**: PVC support for `/var/lib/rabbitmq` data directory
- ✅ **Security Hardened**: Non-root user, minimal capabilities, configurable secrets
- ✅ **Production-Ready**: Health probes, resource limits, ServiceMonitor support
- ✅ **Simple by Default**: Single-node deployment (clustering deferred to future release)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume provisioner (if persistence is enabled)

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install rabbitmq-home charts/rabbitmq \
  -f charts/rabbitmq/values-home-single.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install rabbitmq-startup charts/rabbitmq \
  -f charts/rabbitmq/values-startup-single.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with multiple replicas and monitoring:

```bash
helm install rabbitmq-prod charts/rabbitmq \
  -f charts/rabbitmq/values-prod-master-replica.yaml \
  --set rabbitmq.admin.password=your-secure-password
```

**Features:** 3 replicas, pod anti-affinity, HPA, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 20Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#rabbitmq).

## ⚠️ Important: Password Requirement

**The RabbitMQ admin password is mandatory** for both installation and template validation:

```bash
# ❌ This will FAIL (no password provided)
helm template my-rabbitmq ./charts/rabbitmq

# ✅ This will SUCCEED
helm template my-rabbitmq ./charts/rabbitmq \
  --set rabbitmq.admin.password='test-password'

# ✅ Or use existing secret
helm template my-rabbitmq ./charts/rabbitmq \
  --set rabbitmq.admin.existingSecret.enabled=true \
  --set rabbitmq.admin.existingSecret.secretName='my-secret'
```

This is a **security feature by design** - the chart refuses to generate templates without proper credentials configuration.

## Installation

### Add Repository

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

### Install Chart

```bash
# Basic installation with required password
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set rabbitmq.admin.password='your-strong-password'

# Install with custom values file
helm install my-rabbitmq scripton-charts/rabbitmq -f values.yaml
```

### Verify Installation

```bash
# Check deployment status
kubectl get pods -l app.kubernetes.io/name=rabbitmq

# Get admin credentials
kubectl get secret my-rabbitmq -o jsonpath="{.data.username}" | base64 --decode
kubectl get secret my-rabbitmq -o jsonpath="{.data.password}" | base64 --decode

# Access Management UI (port-forward)
kubectl port-forward svc/my-rabbitmq 15672:15672
# Open browser: http://localhost:15672
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of RabbitMQ replicas | `1` |
| `image.repository` | RabbitMQ image repository | `rabbitmq` |
| `image.tag` | RabbitMQ image tag | `3.13.1-management` |
| `rabbitmq.admin.username` | Admin username | `guest` |
| `rabbitmq.admin.password` | Admin password (required) | `""` |
| `rabbitmq.conf` | Native rabbitmq.conf content | See values.yaml |
| `rabbitmq.plugins` | Enabled plugins list | `[rabbitmq_management,...]` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | PVC size | `10Gi` |
| `service.type` | Service type | `ClusterIP` |
| `monitoring.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` |
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget | `false` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |

For all available parameters, see [values.yaml](values.yaml).

### Example Configurations

#### Minimal Production Deployment

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "CHANGE_ME_STRONG_PASSWORD"

persistence:
  enabled: true
  size: 50Gi

resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

#### With Prometheus Monitoring

```yaml
rabbitmq:
  admin:
    password: "your-password"

monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus
```

#### Custom Configuration

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "secure-password"

  conf: |
    listeners.tcp.default = 5672
    management.tcp.port = 15672
    vm_memory_high_watermark.relative = 0.7
    disk_free_limit.absolute = 5GB
    consumer_timeout = 3600000
    heartbeat = 60

  plugins: |
    [rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel].
```

#### High Availability with Autoscaling

```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "secure-password"

# Enable autoscaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75

# Ensure minimum availability during maintenance
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Restrict network access
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      ports:
        - protocol: TCP
          port: 5672

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

## Usage

### Accessing RabbitMQ

#### Management UI

```bash
# Port-forward to local machine
kubectl port-forward svc/my-rabbitmq 15672:15672

# Access UI in browser
open http://localhost:15672
```

#### AMQP Connection

**From within the cluster:**
```
Host: my-rabbitmq.default.svc.cluster.local
Port: 5672
Connection string: amqp://USERNAME:PASSWORD@my-rabbitmq.default.svc.cluster.local:5672/
```

**From outside the cluster (port-forward):**
```bash
kubectl port-forward svc/my-rabbitmq 5672:5672

# Connection string
amqp://USERNAME:PASSWORD@localhost:5672/
```

### Common Operations

#### Check Cluster Status

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl cluster_status
```

#### List Queues

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_queues
```

#### List Exchanges

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_exchanges
```

#### Create User and Permissions

```bash
# Create user
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_user myuser mypassword

# Set permissions
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_permissions -p / myuser ".*" ".*" ".*"

# Set user tags (e.g., administrator)
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_user_tags myuser administrator
```

#### Create Virtual Host

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_vhost /my-vhost
```

#### Check Node Health

```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-diagnostics ping
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-diagnostics check_running
```

### Makefile Commands

If you're using the chart from the repository:

```bash
# Lint chart
make -f Makefile.rabbitmq.mk lint

# Generate templates
make -f Makefile.rabbitmq.mk template

# Install chart
make -f Makefile.rabbitmq.mk install

# Check RabbitMQ status
make -f Makefile.rabbitmq.mk rmq-status

# List queues
make -f Makefile.rabbitmq.mk rmq-list-queues

# Open shell in pod
make -f Makefile.rabbitmq.mk rmq-shell

# Tail logs
make -f Makefile.rabbitmq.mk rmq-logs
```

## Persistence

RabbitMQ requires persistent storage for queue data and node metadata. By default, a 10Gi PVC is created and mounted at `/var/lib/rabbitmq`.

### Using Existing PVC

```yaml
persistence:
  enabled: true
  existingClaim: "my-existing-pvc"
```

### Disable Persistence (Not Recommended for Production)

```yaml
persistence:
  enabled: false
```

⚠️ **Warning**: Disabling persistence will cause data loss when the pod is terminated.

## Security

### Credentials Management

**Option 1: Set password in values.yaml (default)**
```yaml
rabbitmq:
  admin:
    username: "admin"
    password: "your-password"
```

**Option 2: Use existing secret**
```yaml
rabbitmq:
  admin:
    existingSecret:
      enabled: true
      secretName: "my-rabbitmq-secret"
      usernameKey: "username"
      passwordKey: "password"
```

Create the secret:
```bash
kubectl create secret generic my-rabbitmq-secret \
  --from-literal=username=admin \
  --from-literal=password='your-strong-password'
```

### Security Context

The chart runs RabbitMQ as non-root user (UID 999) with minimal capabilities:

```yaml
securityContext:
  runAsUser: 999
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

## Monitoring

### Prometheus Metrics

RabbitMQ exposes metrics via the `rabbitmq_prometheus` plugin on port 15692.

#### Enable ServiceMonitor (Prometheus Operator)

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus
```

#### Manual Scraping

If not using Prometheus Operator, configure scrape target:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['my-rabbitmq.default.svc.cluster.local:15692']
```

### Metrics Endpoint

```bash
# Port-forward metrics port
kubectl port-forward svc/my-rabbitmq 15692:15692

# Fetch metrics
curl http://localhost:15692/metrics
```

## Upgrading

### Upgrade Chart

```bash
helm upgrade my-rabbitmq scripton-charts/rabbitmq -f values.yaml
```

### Rollback

```bash
helm rollback my-rabbitmq
```

## Uninstallation

```bash
# Uninstall chart
helm uninstall my-rabbitmq

# Optional: Delete PVC (data will be lost)
kubectl delete pvc my-rabbitmq
```

## Troubleshooting

### Pod Not Starting

Check pod events and logs:
```bash
kubectl describe pod -l app.kubernetes.io/name=rabbitmq
kubectl logs -l app.kubernetes.io/name=rabbitmq
```

### Permission Denied Errors

Ensure PVC permissions match `fsGroup: 999`:
```yaml
podSecurityContext:
  fsGroup: 999
```

### Memory Issues

Adjust memory limits and RabbitMQ memory threshold:
```yaml
resources:
  limits:
    memory: 2Gi

rabbitmq:
  conf: |
    vm_memory_high_watermark.relative = 0.6
```

### Connection Refused

Verify service and endpoints:
```bash
kubectl get svc my-rabbitmq
kubectl get endpoints my-rabbitmq
```

## Backup & Recovery

### Backup Strategy

RabbitMQ backup covers 4 critical components:

| Component | Priority | Backup Method | Frequency |
|-----------|----------|---------------|-----------|
| **Definitions** | Critical | rabbitmqadmin export | Every 6 hours |
| **Messages** | Important | Persistent queues + Shovel | Daily or continuous |
| **Configuration** | Important | ConfigMaps, Secrets | On change |
| **Mnesia Database** | Critical | PVC Snapshots | Daily |

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/rabbitmq.mk rmq-full-backup

# Definitions backup (exchanges, queues, bindings, users, policies)
make -f make/ops/rabbitmq.mk rmq-backup-definitions

# Configuration backup (rabbitmq.conf, enabled_plugins)
make -f make/ops/rabbitmq.mk rmq-backup-config

# Mnesia database backup (via PVC snapshot)
make -f make/ops/rabbitmq.mk rmq-snapshot-create

# Check backup status
make -f make/ops/rabbitmq.mk rmq-backup-status
```

### Backup Methods

**1. Definitions Export (Recommended for Quick Recovery)**
```bash
POD=$(kubectl get pods -n default -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')

# Export definitions via Management API
kubectl exec -n default $POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json

# Copy from pod
kubectl cp default/$POD:/tmp/definitions.json ./definitions-backup.json
```

**2. PVC Snapshots (Fastest Recovery)**
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rabbitmq-snapshot-20251209
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: my-rabbitmq
```

**3. Persistent Queues (Message Durability)**
```bash
# Ensure durable queues
kubectl exec -n default $POD -- rabbitmqctl list_queues name durable

# Publish persistent messages (delivery_mode=2)
```

**4. Federation/Shovel (Continuous Replication)**
```bash
# Enable shovel plugin for message backup
kubectl exec -n default $POD -- rabbitmq-plugins enable rabbitmq_shovel

# Configure shovel to backup cluster
```

**5. Restic (Incremental Backups to S3)**
```bash
# Backup to S3/MinIO with encryption and deduplication
restic -r s3:https://s3.amazonaws.com/bucket/rabbitmq backup /var/lib/rabbitmq
```

### Recovery Procedures

**Restore Definitions**:
```bash
# Import definitions
kubectl cp ./definitions-backup.json default/$POD:/tmp/definitions.json

kubectl exec -n default $POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -H "Content-Type: application/json" \
  -d @/tmp/definitions.json
```

**Full Disaster Recovery**:
```bash
# 1. Create PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rabbitmq-restored
spec:
  dataSource:
    name: rabbitmq-snapshot-20251209
    kind: VolumeSnapshot
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
EOF

# 2. Deploy with restored PVC
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set persistence.existingClaim=rabbitmq-restored

# 3. Verify data integrity
kubectl exec -n default $POD -- rabbitmqctl list_queues
kubectl exec -n default $POD -- rabbitmqctl list_users
```

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|----------|---------------------|---------------------|
| Definitions restore | < 15 minutes | 6 hours |
| Messages restore | < 2 hours | 24 hours |
| Configuration restore | < 10 minutes | 24 hours |
| Full disaster recovery | < 1 hour | 24 hours |

For comprehensive backup procedures, see the [RabbitMQ Backup Guide](../../docs/rabbitmq-backup-guide.md).

---

## Security & RBAC

### RBAC Resources

This chart creates the following RBAC resources by default:

- **ServiceAccount**: Pod identity for RabbitMQ
- **Role**: Namespace-scoped permissions for ConfigMaps, Secrets, Pods, Services, Endpoints, PVCs
- **RoleBinding**: Binds Role to ServiceAccount

### RBAC Configuration

```yaml
# Enable/disable RBAC (default: enabled)
rbac:
  create: true
  annotations: {}

# ServiceAccount configuration
serviceAccount:
  create: true
  name: ""  # Auto-generated if empty
  annotations: {}
```

### Security Best Practices

**DO**:
- ✅ Use strong admin passwords (minimum 16 characters)
- ✅ Enable network policies to restrict access
- ✅ Run RabbitMQ as non-root user (UID 999)
- ✅ Use TLS/SSL for AMQP and Management UI connections
- ✅ Enable audit logging
- ✅ Regularly rotate credentials
- ✅ Use persistent queues for critical messages
- ✅ Limit user permissions (vhost-specific)

**DON'T**:
- ❌ Use default credentials (guest/guest)
- ❌ Expose Management UI publicly without authentication
- ❌ Run RabbitMQ as root
- ❌ Store credentials in plain text
- ❌ Grant administrator tags to application users
- ❌ Allow unrestricted network access

### Pod Security Context

```yaml
podSecurityContext:
  fsGroup: 999
  runAsUser: 999
  runAsGroup: 999
  runAsNonRoot: true

securityContext:
  capabilities:
    drop: [ALL]
  readOnlyRootFilesystem: false
  allowPrivilegeEscalation: false
```

### Network Policy Example

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - podSelector:
          matchLabels:
            app: my-app
      ports:
        - protocol: TCP
          port: 5672  # AMQP
        - protocol: TCP
          port: 15672  # Management UI
```

### TLS/SSL Configuration

```yaml
# Configure TLS for AMQP
rabbitmq:
  conf: |
    listeners.ssl.default = 5671
    ssl_options.cacertfile = /etc/rabbitmq/ca_certificate.pem
    ssl_options.certfile = /etc/rabbitmq/server_certificate.pem
    ssl_options.keyfile = /etc/rabbitmq/server_key.pem
    ssl_options.verify = verify_peer
    ssl_options.fail_if_no_peer_cert = false

# Mount TLS certificates
extraVolumes:
  - name: tls-certs
    secret:
      secretName: rabbitmq-tls

extraVolumeMounts:
  - name: tls-certs
    mountPath: /etc/rabbitmq/certs
    readOnly: true
```

### Verify RBAC

```bash
# Check ServiceAccount
kubectl get serviceaccount -l app.kubernetes.io/name=rabbitmq

# Check Role
kubectl get role -l app.kubernetes.io/name=rabbitmq

# Check RoleBinding
kubectl get rolebinding -l app.kubernetes.io/name=rabbitmq

# Verify permissions
kubectl auth can-i get configmaps --as=system:serviceaccount:default:my-rabbitmq
```

---

## Operations

### Daily Operations

**Access RabbitMQ shell**:
```bash
make -f make/ops/rabbitmq.mk rmq-shell
# Or manually:
kubectl exec -it deployment/my-rabbitmq -- bash
```

**Port-forward services**:
```bash
# Management UI (http://localhost:15672)
make -f make/ops/rabbitmq.mk rmq-port-forward

# AMQP (amqp://localhost:5672)
kubectl port-forward svc/my-rabbitmq 5672:5672

# Metrics (http://localhost:15692/metrics)
kubectl port-forward svc/my-rabbitmq 15692:15692
```

**View logs**:
```bash
# Tail logs
make -f make/ops/rabbitmq.mk rmq-logs

# All logs
kubectl logs deployment/my-rabbitmq --all-containers=true
```

### Monitoring & Health Checks

**Check cluster status**:
```bash
make -f make/ops/rabbitmq.mk rmq-status
# Or manually:
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl cluster_status
```

**Node health check**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl node_health_check
```

**List queues**:
```bash
make -f make/ops/rabbitmq.mk rmq-list-queues
# Or manually:
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_queues name messages consumers memory
```

**List exchanges**:
```bash
make -f make/ops/rabbitmq.mk rmq-list-exchanges
```

**Check connections**:
```bash
make -f make/ops/rabbitmq.mk rmq-list-connections
```

**Check memory usage**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl status | grep -A 10 "Memory"
```

### Queue Management

**Declare queue**:
```bash
# Durable queue
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl eval \
  'rabbit_amqqueue:declare({resource, <<"/">>, queue, <<"my-queue">>}, true, false, [], none, "guest").'

# Quorum queue (HA)
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl eval \
  'rabbit_amqqueue:declare({resource, <<"/">>, queue, <<"my-quorum-queue">>}, quorum, true, false, [], none, "guest").'
```

**Purge queue**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl purge_queue my-queue
```

**Delete queue**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl delete_queue my-queue
```

### User Management

**List users**:
```bash
make -f make/ops/rabbitmq.mk rmq-list-users
```

**Create user**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_user myuser mypassword

# Set permissions
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_permissions -p / myuser ".*" ".*" ".*"

# Set tags (administrator, monitoring, etc.)
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_user_tags myuser administrator
```

**Delete user**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl delete_user myuser
```

**Change password**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl change_password myuser newpassword
```

### Virtual Host Management

**Create vhost**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl add_vhost /my-vhost
```

**List vhosts**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_vhosts
```

**Delete vhost**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl delete_vhost /my-vhost
```

### Policy Management

**Set policy**:
```bash
# HA policy (mirroring)
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_policy ha-all \
  "^ha\\." '{"ha-mode":"all"}' --apply-to queues

# TTL policy
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_policy ttl-policy \
  "^ttl\\." '{"message-ttl":60000}' --apply-to queues

# Max-length policy
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl set_policy max-length \
  "^limited\\." '{"max-length":10000}' --apply-to queues
```

**List policies**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl list_policies
```

### Plugin Management

**List enabled plugins**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-plugins list -E
```

**Enable plugin**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-plugins enable rabbitmq_stream
```

**Disable plugin**:
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmq-plugins disable rabbitmq_stream
```

### Maintenance Operations

**Restart RabbitMQ application** (no pod restart):
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl stop_app
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl start_app
```

**Restart pod**:
```bash
kubectl rollout restart deployment my-rabbitmq
```

**Reset RabbitMQ** (⚠️ DESTRUCTIVE - deletes all data):
```bash
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl stop_app
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl reset
kubectl exec -it deployment/my-rabbitmq -- rabbitmqctl start_app
```

### Troubleshooting

| Issue | Command | Notes |
|-------|---------|-------|
| Pod not starting | `kubectl describe pod -l app.kubernetes.io/name=rabbitmq` | Check events |
| Permission denied | `kubectl logs -l app.kubernetes.io/name=rabbitmq` | Verify fsGroup: 999 |
| Connection refused | `kubectl get svc,endpoints my-rabbitmq` | Verify service |
| High memory | `kubectl exec $POD -- rabbitmqctl status \| grep Memory` | Check watermark |
| Alarms | `kubectl exec $POD -- rabbitmqctl alarm_status` | Clear alarms |

**Debug commands**:
```bash
# Get pod events
kubectl describe pod -l app.kubernetes.io/name=rabbitmq

# Check service endpoints
kubectl get endpoints my-rabbitmq

# Test connectivity
kubectl run test --rm -it --restart=Never --image=curlimages/curl -- \
  curl -u guest:guest http://my-rabbitmq:15672/api/overview

# Check alarms
kubectl exec $POD -- rabbitmqctl alarm_status

# Force alarm clear (if false positive)
kubectl exec $POD -- rabbitmqctl eval 'rabbit_alarm:clear_alarm(disk).'
```

---

## Upgrading

### Upgrade Strategies

| Strategy | Downtime | Complexity | Use Case |
|----------|----------|------------|----------|
| **In-Place** | 5-15 minutes | Low | Development, staging |
| **Blue-Green** | < 1 minute | Medium | Production, zero-risk |
| **Backup & Restore** | 1-2 hours | Low | Major version jumps |

### Pre-Upgrade Checklist

```bash
# 1. Check current version
kubectl exec $POD -- rabbitmqctl version

# 2. Backup all components
make -f make/ops/rabbitmq.mk rmq-full-backup

# 3. Verify cluster health
kubectl exec $POD -- rabbitmqctl node_health_check

# 4. Record current state
kubectl exec $POD -- rabbitmqctl list_queues > pre-upgrade-queues.txt
kubectl exec $POD -- rabbitmqctl list_users > pre-upgrade-users.txt
```

### Upgrade Procedures

**In-Place Upgrade** (Single-Node):
```bash
# 1. Backup
make -f make/ops/rabbitmq.mk rmq-full-backup

# 2. Upgrade via Helm
helm upgrade my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management \
  --reuse-values

# 3. Wait for pod restart
kubectl rollout status deployment my-rabbitmq

# 4. Verify upgrade
kubectl exec $POD -- rabbitmqctl version
kubectl exec $POD -- rabbitmqctl list_queues
```

**Blue-Green Deployment**:
```bash
# 1. Deploy green environment (new version)
helm install my-rabbitmq-green scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management \
  --set fullnameOverride=rabbitmq-green

# 2. Import definitions to green
kubectl cp ./definitions-backup.json $GREEN_POD:/tmp/definitions.json
kubectl exec $GREEN_POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -d @/tmp/definitions.json

# 3. Test green deployment thoroughly

# 4. Switch traffic
kubectl patch service my-rabbitmq \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"rabbitmq-green"}}}'

# 5. Monitor for 24 hours, then decommission blue
helm uninstall my-rabbitmq
```

**Major Version Upgrade** (Export/Import):
```bash
# 1. Export definitions
kubectl exec $POD -- curl -u guest:guest \
  http://localhost:15672/api/definitions \
  -o /tmp/definitions.json
kubectl cp $POD:/tmp/definitions.json ./definitions-v3.12.json

# 2. Uninstall old version
helm uninstall my-rabbitmq

# 3. Install new version
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.13.1-management

# 4. Import definitions
kubectl cp ./definitions-v3.12.json $NEW_POD:/tmp/definitions.json
kubectl exec $NEW_POD -- curl -u guest:guest \
  -X POST http://localhost:15672/api/definitions \
  -d @/tmp/definitions.json
```

### Post-Upgrade Validation

```bash
# Run automated validation
make -f make/ops/rabbitmq.mk rmq-post-upgrade-check

# Manual checks
kubectl exec $POD -- rabbitmqctl version  # Verify version
kubectl exec $POD -- rabbitmqctl node_health_check  # Health
kubectl exec $POD -- rabbitmqctl list_queues  # Queues
kubectl exec $POD -- rabbitmqctl list_users  # Users
kubectl exec $POD -- rabbitmq-plugins list -E  # Plugins
```

### Rollback Procedures

**Helm Rollback**:
```bash
# Check rollback history
helm history my-rabbitmq

# Rollback to previous revision
helm rollback my-rabbitmq

# Verify rollback
kubectl exec $POD -- rabbitmqctl version
```

**Blue-Green Rollback** (instant):
```bash
# Switch traffic back to blue
kubectl patch service my-rabbitmq \
  -p '{"spec":{"selector":{"app.kubernetes.io/instance":"my-rabbitmq"}}}'
```

**Restore from Backup**:
```bash
# Uninstall broken deployment
helm uninstall my-rabbitmq

# Restore from VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-rabbitmq
spec:
  dataSource:
    name: rabbitmq-pre-upgrade-snapshot
    kind: VolumeSnapshot
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
EOF

# Reinstall with old version
helm install my-rabbitmq scripton-charts/rabbitmq \
  --set image.tag=3.12.14-management
```

### Version-Specific Notes

**RabbitMQ 3.13.x** (Latest):
- Khepri metadata store (experimental, opt-in)
- Improved Quorum queues performance
- Enhanced stream plugin

**RabbitMQ 3.12.x**:
- Quorum queues scalability improvements
- Classic queue v2 (CQv2) - optional

**RabbitMQ 3.11.x**:
- Stream support (pub/sub with replay)
- Super Streams (partitioned streams)

**RabbitMQ 3.10.x**:
- Improved Quorum queues
- Classic mirrored queues deprecated

For comprehensive upgrade procedures, see the [RabbitMQ Upgrade Guide](../../docs/rabbitmq-upgrade-guide.md).

---

## Limitations

- **Single-node only**: Clustering is not yet supported in this release
- **No TLS/SSL**: AMQP+SSL configuration must be added manually via `extraEnv`
- **No federation/shovel**: Advanced plugins can be enabled via `rabbitmq.plugins`

## Recent Changes

### Version 0.3.1 (2025-11-17)

**Documentation:**
- ✅ Clarified single-instance architecture in `values-prod-master-replica.yaml`
- ✅ Added production clustering alternatives:
  - RabbitMQ Cluster Operator (recommended for production)
  - Bitnami RabbitMQ Helm Chart with clustering support
- ✅ Documented migration path from single to clustered deployment

For full changelog, see [Chart.yaml](./Chart.yaml) or [docs/05-chart-analysis-2025-11.md](../../docs/05-chart-analysis-2025-11.md).

## Testing

For comprehensive testing scenarios, see [Testing Guide](../../docs/TESTING_GUIDE.md).

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## Roadmap

- [ ] StatefulSet support for multi-node clustering
- [ ] Built-in TLS/SSL configuration
- [ ] Federation and shovel plugin configuration
- [ ] LoadDefinitions support for auto-configuration
- [ ] HorizontalPodAutoscaler examples

## License

This Helm chart is licensed under the **BSD-3-Clause License**.

RabbitMQ itself is licensed under the **Mozilla Public License 2.0 (MPL 2.0)**. See [RabbitMQ License](https://www.rabbitmq.com/mpl.html) for details.

## Contributing

Contributions are welcome! Please submit issues and pull requests to the [GitHub repository](https://github.com/scriptonbasestar-container/sb-helm-charts).

## Resources

- [RabbitMQ Official Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Configuration Reference](https://www.rabbitmq.com/configure.html)
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)
- [RabbitMQ Prometheus Plugin](https://www.rabbitmq.com/prometheus.html)
- [AMQP 0-9-1 Reference](https://www.rabbitmq.com/amqp-0-9-1-reference.html)
