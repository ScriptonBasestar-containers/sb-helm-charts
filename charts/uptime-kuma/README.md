# Uptime Kuma Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/uptime-kuma)

A self-hosted monitoring tool with beautiful UI, multi-protocol support, and flexible alerting.

## Features

- 🖥️ **Beautiful Dashboard**: Modern, intuitive web interface
- 📊 **Multi-Protocol Monitoring**: HTTP(s), TCP, Ping, DNS, SMTP, and more
- 📱 **90+ Notification Services**: Telegram, Discord, Slack, Email, and many more
- 📈 **Status Pages**: Public status pages for your services
- 🔐 **Multi-User Support**: User management with 2FA
- 🌍 **Multi-Language**: Support for 25+ languages
- 📦 **Lightweight**: Single Docker container, low resource usage

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install uptime-kuma-home charts/uptime-kuma \
  -f charts/uptime-kuma/values-home-single.yaml
```

**Resource allocation:** 50-250m CPU, 128-256Mi RAM, 2Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install uptime-kuma-startup charts/uptime-kuma \
  -f charts/uptime-kuma/values-startup-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 5Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with monitoring and enhanced reliability:

```bash
helm install uptime-kuma-prod charts/uptime-kuma \
  -f charts/uptime-kuma/values-prod-master-replica.yaml
```

**Features:** PodDisruptionBudget, NetworkPolicy, ServiceMonitor, enhanced probes

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 10Gi storage

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#uptime-kuma).


- Kubernetes 1.22+
- Helm 3.0+
- PersistentVolume provisioner (for data persistence)
- **Optional**: External MySQL/MariaDB (for production environments)

## Quick Start

### 1. Install with SQLite (Default)

```bash
helm install uptime-kuma ./charts/uptime-kuma
```

### 2. Access Uptime Kuma

```bash
kubectl port-forward svc/uptime-kuma 3001:3001
# Visit http://localhost:3001
# Create admin account on first access
```

## Configuration

### Database Options

#### SQLite (Default - Recommended for Small Deployments)

```yaml
uptimeKuma:
  database:
    type: "sqlite"

persistence:
  enabled: true
  size: 4Gi
```

**Pros:**
- Zero configuration
- No external dependencies
- Perfect for homelab/small deployments

**Cons:**
- Single file database
- Not suitable for high-traffic environments

#### MariaDB (Recommended for Production)

```yaml
uptimeKuma:
  database:
    type: "mariadb"
    mariadb:
      host: "mariadb.default.svc.cluster.local"
      port: 3306
      database: "uptime_kuma"
      username: "uptime_kuma"
      password: "changeme123"
```

**Pros:**
- Better performance under load
- Easier backups
- Multiple replicas possible

**Setup external MariaDB:**
```bash
# Using sb-helm-charts MySQL chart
helm install mariadb ./charts/mysql \
  --set auth.database=uptime_kuma \
  --set auth.username=uptime_kuma \
  --set auth.password=secure_password
```

### SSL/TLS Configuration

```yaml
uptimeKuma:
  ssl:
    enabled: true
    keyPath: "/certs/tls.key"
    certPath: "/certs/tls.crt"
    keyPassphrase: ""  # Optional

extraVolumes:
  - name: ssl-certs
    secret:
      secretName: uptime-kuma-tls

extraVolumeMounts:
  - name: ssl-certs
    mountPath: /certs
    readOnly: true
```

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: uptime.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: uptime-kuma-tls
      hosts:
        - uptime.example.com
```

### WebSocket Configuration for Reverse Proxy

If using a reverse proxy, you may need to bypass WebSocket origin checks:

```yaml
uptimeKuma:
  security:
    wsOriginCheck: "bypass"  # Required for most reverse proxies
```

### Resource Limits

**Homelab/Small Deployment:**
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Production:**
```yaml
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

## Persistent Storage

Uptime Kuma requires persistent storage for:
- SQLite database (if using SQLite)
- Configuration and certificates
- Status page data

**Important:** NFS is NOT supported. Use local directories or cloud-native persistent volumes.

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # Use fast storage for SQLite
  accessMode: ReadWriteOnce
  size: 4Gi
```

## Monitoring Setup

After installation, configure monitors via the web UI:

1. **HTTP(s) Monitor**
   - URL: `https://example.com`
   - Check interval: 60 seconds
   - Retries: 3

2. **TCP Monitor**
   - Hostname: `database.internal`
   - Port: 5432

3. **Ping Monitor**
   - Hostname: `8.8.8.8`
   - Packet count: 3

4. **DNS Monitor**
   - Resolver: `8.8.8.8`
   - Record: `example.com`
   - Type: A

## Notification Services

Uptime Kuma supports 90+ notification providers. Configure via web UI:

**Popular Services:**
- Telegram: Bot token + Chat ID
- Discord: Webhook URL
- Slack: Webhook URL
- Email: SMTP settings
- PagerDuty: Integration key
- Webhook: Custom webhooks

## Status Pages

Create public status pages:

1. Go to "Status Pages" in web UI
2. Create new status page
3. Select monitors to display
4. Customize appearance
5. Publish (accessible at `/status/{slug}`)

## Operational Commands

This chart includes a comprehensive Makefile for day-2 operations:

```bash
# View logs and access shell
make -f make/ops/uptime-kuma.mk uk-logs
make -f make/ops/uptime-kuma.mk uk-shell

# Port forward to localhost:3001
make -f make/ops/uptime-kuma.mk uk-port-forward

# Health checks
make -f make/ops/uptime-kuma.mk uk-check-db
make -f make/ops/uptime-kuma.mk uk-check-storage

# Database management (SQLite)
make -f make/ops/uptime-kuma.mk uk-backup-sqlite
make -f make/ops/uptime-kuma.mk uk-restore-sqlite FILE=path/to/kuma.db

# User management
make -f make/ops/uptime-kuma.mk uk-reset-password

# System information
make -f make/ops/uptime-kuma.mk uk-version
make -f make/ops/uptime-kuma.mk uk-node-info
make -f make/ops/uptime-kuma.mk uk-get-settings

# Monitoring (API-based)
make -f make/ops/uptime-kuma.mk uk-list-monitors
make -f make/ops/uptime-kuma.mk uk-status-pages

# Operations
make -f make/ops/uptime-kuma.mk uk-restart
make -f make/ops/uptime-kuma.mk uk-scale REPLICAS=2

# Full help
make -f make/ops/uptime-kuma.mk help
```

## Troubleshooting

### WebSocket Connection Failed

**Symptom:** "WebSocket connection failed" error in browser

**Solution:**
```yaml
uptimeKuma:
  security:
    wsOriginCheck: "bypass"
```

Also ensure reverse proxy forwards WebSocket headers:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Database Lock Errors (SQLite)

**Symptom:** "database is locked" errors

**Solution:**
- Ensure `strategy.type: Recreate` (only one pod at a time)
- Use `accessMode: ReadWriteOnce` for PVC
- Consider migrating to MariaDB for multi-replica setup

### High Memory Usage

**Symptom:** Pod OOMKilled

**Solution:**
```yaml
resources:
  limits:
    memory: 1Gi  # Increase from default 512Mi
  requests:
    memory: 256Mi
```

### NFS Mount Errors

**Symptom:** Database corruption or mount errors

**Solution:**
- Uptime Kuma does NOT support NFS
- Use local storage or cloud-native PVs (EBS, PD, Azure Disk)
- For NFS environments, use MariaDB instead of SQLite

## Production Deployment

### High Availability (with MariaDB)

```yaml
uptimeKuma:
  database:
    type: "mariadb"
    mariadb:
      host: "mariadb-primary"
      password: "secure_password"

replicaCount: 2

podDisruptionBudget:
  enabled: true
  minAvailable: 1

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: uptime-kuma
          topologyKey: kubernetes.io/hostname
```

**Note:** SQLite does NOT support multiple replicas. Use MariaDB for HA.

### Network Security

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: production
      ports:
        - protocol: TCP
          port: 3001
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 3306  # MariaDB
        - protocol: TCP
          port: 443   # HTTPS monitors
```

### Monitoring with Prometheus

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
```

**Note:** Uptime Kuma does not expose Prometheus metrics by default. You may need to configure external exporters or use Uptime Kuma's API.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `uptimeKuma.port` | int | `3001` | Application port |
| `uptimeKuma.database.type` | string | `"sqlite"` | Database type (sqlite or mariadb) |
| `uptimeKuma.database.mariadb.host` | string | `""` | MariaDB host (required if type=mariadb) |
| `uptimeKuma.database.mariadb.password` | string | `""` | MariaDB password (required if type=mariadb) |
| `persistence.enabled` | bool | `true` | Enable persistent storage |
| `persistence.size` | string | `"4Gi"` | Storage size |
| `ingress.enabled` | bool | `false` | Enable ingress |
| `resources.limits.memory` | string | `"512Mi"` | Memory limit |

For full configuration options, see [values.yaml](./values.yaml).

## Migration from Other Deployments

### From Docker to Kubernetes

1. Export data from Docker volume:
```bash
docker cp uptime-kuma:/app/data ./backup-data/
```

2. Create PVC and copy data:
```bash
helm install uptime-kuma ./charts/uptime-kuma
kubectl cp ./backup-data/kuma.db uptime-kuma-0:/app/data/
kubectl rollout restart deployment/uptime-kuma
```

### From SQLite to MariaDB

Uptime Kuma does not provide automatic migration. You'll need to:
1. Export monitors configuration (backup)
2. Deploy with MariaDB
3. Manually recreate monitors

## Backup & Recovery

Comprehensive backup and recovery procedures for Uptime Kuma deployments.

### Backup Components

Uptime Kuma backup strategy covers 4 components:

| Component | Priority | Size | Backup Method |
|-----------|----------|------|---------------|
| **Data PVC** | 🔴 Critical | 100MB-2GB | tar, Restic, VolumeSnapshot |
| **SQLite DB** | 🔴 Critical | 50MB-1GB | SQLite .backup |
| **Configuration** | 🟡 Important | <1MB | helm get values |
| **MariaDB** (optional) | 🟠 High | Varies | mysqldump |

### Quick Backup Commands

```bash
# Full backup (data PVC + database)
make -f make/ops/uptime-kuma.mk uk-full-backup

# Database-only backup
make -f make/ops/uptime-kuma.mk uk-backup-database

# Data PVC backup
make -f make/ops/uptime-kuma.mk uk-backup-data

# Check backup status
make -f make/ops/uptime-kuma.mk uk-backup-status
```

**Output**: Backups saved to `tmp/uptime-kuma-backups/data-YYYYMMDD-HHMMSS.tar.gz`

### Recovery Workflow

Complete disaster recovery in 4 steps:

```bash
# 1. Install fresh Uptime Kuma chart
helm install uptime-kuma sb-charts/uptime-kuma -f values.yaml

# 2. Restore data from backup
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=tmp/uptime-kuma-backups/data-20250109-143022.tar.gz

# 3. Restart pod to reload data
kubectl rollout restart deployment/uptime-kuma

# 4. Verify restoration
make -f make/ops/uptime-kuma.mk uk-check-monitors
```

**Validation**:
```bash
# Verify monitors restored
# Access UI: Dashboard → Monitors (check count)

# Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check
```

### Backup Strategies

**1. Automated Daily Backups (Recommended)**

Create a CronJob for automated backups:

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: uptime-kuma-backup
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: uptime-kuma
          containers:
          - name: backup
            image: alpine:3.18
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache tar gzip
              cd /app/data
              tar czf /backup/data-$(date +%Y%m%d-%H%M%S).tar.gz .
              # Keep only last 7 days
              find /backup -name "data-*.tar.gz" -mtime +7 -delete
            volumeMounts:
            - name: data
              mountPath: /app/data
            - name: backup
              mountPath: /backup
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: uptime-kuma-data
          - name: backup
            persistentVolumeClaim:
              claimName: uptime-kuma-backups
          restartPolicy: OnFailure
```

**2. Restic Incremental Backups**

Efficient incremental backups with deduplication:

```bash
# Initialize Restic repository
export RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-backups/uptime-kuma
export RESTIC_PASSWORD=<secure-password>
restic init

# Backup data PVC
POD=$(kubectl get pods -l app.kubernetes.io/name=uptime-kuma -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- tar czf - /app/data | \
  restic backup --stdin --stdin-filename uptime-kuma-data.tar.gz

# Verify backup
restic snapshots

# Restore specific snapshot
restic restore latest --target /restore/
```

**3. Volume Snapshots (Fastest)**

Use Kubernetes VolumeSnapshot API for instant backups:

```yaml
# volumesnapshot.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: uptime-kuma-data-snapshot
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: uptime-kuma-data
```

### Recovery Time Objectives (RTO/RPO)

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) |
|----------|---------------------|---------------------|
| **Data PVC Restore** | < 30 minutes | 24 hours |
| **Database Restore** | < 15 minutes | 24 hours |
| **Full Disaster Recovery** | < 1 hour | 24 hours |
| **Selective Monitor Recovery** | < 10 minutes | 24 hours |

**For comprehensive backup procedures**, see [Uptime Kuma Backup Guide](../../docs/uptime-kuma-backup-guide.md).

---

## Security & RBAC

Role-Based Access Control (RBAC) and security features for Uptime Kuma deployments.

### RBAC Resources

This chart creates namespace-scoped RBAC resources:

**Resources Created:**
- `Role`: Defines permissions for Uptime Kuma operations
- `RoleBinding`: Binds Role to ServiceAccount
- `ServiceAccount`: Pod identity for RBAC

**Permissions Granted** (read-only):
```yaml
- configmaps: [get, list, watch]       # Configuration
- secrets: [get, list, watch]          # Credentials
- pods: [get, list, watch]             # Health checks
- services: [get, list, watch]         # Service discovery
- endpoints: [get, list, watch]        # Service discovery
- persistentvolumeclaims: [get, list, watch]  # Storage operations
```

### RBAC Configuration

**Enable/Disable RBAC:**

```yaml
# values.yaml
rbac:
  create: true  # Enable RBAC (default)
  annotations:
    description: "Uptime Kuma RBAC for monitoring operations"
```

**Disable RBAC** (not recommended):

```bash
helm install uptime-kuma sb-charts/uptime-kuma --set rbac.create=false
```

### Security Context

**Pod-level security:**

```yaml
# values.yaml
podSecurityContext:
  fsGroup: 1000          # Uptime Kuma user group
  runAsUser: 1000        # Uptime Kuma user
  runAsNonRoot: true
```

**Container-level security:**

```yaml
# values.yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Uptime Kuma needs write access to /app
```

### Network Policies

Restrict network access to Uptime Kuma:

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: uptime-kuma-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: uptime-kuma
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow HTTP traffic from ingress controller
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
      ports:
      - protocol: TCP
        port: 3001
  egress:
    # Allow DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53
    # Allow monitoring endpoints (HTTP/HTTPS)
    - to:
      - podSelector: {}
      ports:
      - protocol: TCP
        port: 80
      - protocol: TCP
        port: 443
    # Allow external MariaDB (if used)
    - to:
      - podSelector:
          matchLabels:
            app: mariadb
      ports:
      - protocol: TCP
        port: 3306
```

### Security Best Practices

**DO:**
- ✅ Enable RBAC (default)
- ✅ Use non-root user (fsGroup: 1000)
- ✅ Apply NetworkPolicy to restrict traffic
- ✅ Enable TLS/SSL on ingress
- ✅ Use secrets for notification API keys
- ✅ Regularly update Uptime Kuma version

**DON'T:**
- ❌ Run as root user
- ❌ Disable RBAC in production
- ❌ Expose port 3001 directly (use ingress with TLS)
- ❌ Store notification credentials in ConfigMaps (use Secrets)

### RBAC Verification

**Verify RBAC resources:**

```bash
# Check Role
kubectl get role uptime-kuma-role -o yaml

# Check RoleBinding
kubectl get rolebinding uptime-kuma-rolebinding -o yaml

# Check ServiceAccount
kubectl get serviceaccount uptime-kuma -o yaml
```

**Test RBAC permissions:**

```bash
# Test read access to ConfigMaps
kubectl auth can-i get configmaps --as=system:serviceaccount:default:uptime-kuma
# Expected: yes

# Test write access to ConfigMaps (should fail)
kubectl auth can-i create configmaps --as=system:serviceaccount:default:uptime-kuma
# Expected: no
```

---

## Operations

Daily operations, monitoring, and maintenance for Uptime Kuma deployments.

### Daily Operations

**Access Uptime Kuma:**

```bash
# Get web UI URL
make -f make/ops/uptime-kuma.mk uk-get-url

# Port forward to localhost:3001
make -f make/ops/uptime-kuma.mk uk-port-forward
# Open http://localhost:3001
```

**Shell Access:**

```bash
# Interactive shell
make -f make/ops/uptime-kuma.mk uk-shell

# Execute one-off command
kubectl exec -it deployment/uptime-kuma -- ls -la /app/data
```

**Log Management:**

```bash
# Tail logs (follow)
make -f make/ops/uptime-kuma.mk uk-logs

# View last 100 lines
kubectl logs deployment/uptime-kuma --tail=100

# Search logs for errors
kubectl logs deployment/uptime-kuma | grep -i error
```

### Monitoring & Health Checks

**Resource Usage:**

```bash
# Show CPU/memory usage
make -f make/ops/uptime-kuma.mk uk-stats

# Describe pod
make -f make/ops/uptime-kuma.mk uk-describe

# Show events
make -f make/ops/uptime-kuma.mk uk-events
```

**Health Endpoints:**

```bash
# Check liveness (port 3001)
kubectl exec deployment/uptime-kuma -- wget -qO- http://localhost:3001/

# Uptime Kuma doesn't have dedicated health endpoints
# Use root path for basic availability check
```

**Storage Usage:**

```bash
# Check data directory size
make -f make/ops/uptime-kuma.mk uk-check-data

# Check database size
make -f make/ops/uptime-kuma.mk uk-check-database-size

# Check PVC usage
kubectl exec deployment/uptime-kuma -- df -h /app/data
```

### Database Operations

Uptime Kuma uses SQLite by default (MariaDB optional).

**SQLite Database Backup:**

```bash
# Backup database (SQLite)
make -f make/ops/uptime-kuma.mk uk-backup-database

# Output: tmp/uptime-kuma-backups/kuma-YYYYMMDD-HHMMSS.db
```

**Database Maintenance:**

```bash
# Vacuum database (reclaim space)
make -f make/ops/uptime-kuma.mk uk-db-vacuum

# Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check

# Analyze database (optimize query performance)
make -f make/ops/uptime-kuma.mk uk-db-analyze
```

**Database Statistics:**

```bash
# Show database size and table counts
make -f make/ops/uptime-kuma.mk uk-db-stats
```

### Monitor Management

**List Monitors:**

```bash
# Via UI: Dashboard → Monitors
# Or check via API:
curl -X GET http://localhost:3001/api/status-page/list
```

**Check Monitor Count:**

```bash
# Count monitors in database
make -f make/ops/uptime-kuma.mk uk-check-monitors
```

**Monitor Performance:**

```bash
# Check monitor execution times
# Via UI: Dashboard → Select Monitor → View Response Time graph
```

### Notification Management

**Test Notifications:**

```bash
# Via UI: Settings → Notifications
# For each channel:
# 1. Click "Test"
# 2. Verify notification received
```

**Notification Logs:**

```bash
# Check logs for notification send events
kubectl logs deployment/uptime-kuma | grep -i notification
```

### Status Page Management

**List Status Pages:**

```bash
# Via UI: Status Pages
# Or check via API (if public):
curl -X GET https://status.example.com/api/status-page/list
```

**Status Page Performance:**

```bash
# Check status page load time
curl -w "@curl-format.txt" -o /dev/null -s https://status.example.com/

# curl-format.txt:
# time_total: %{time_total}
```

### Performance Tuning

**Resource Adjustments:**

```bash
# Increase CPU/memory limits for large deployments
helm upgrade uptime-kuma sb-charts/uptime-kuma \
  --reuse-values \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=1Gi
```

**Database Optimization:**

```bash
# Vacuum database to improve performance
make -f make/ops/uptime-kuma.mk uk-db-vacuum

# Analyze database for query optimization
make -f make/ops/uptime-kuma.mk uk-db-analyze
```

**Switch to MariaDB** (for high-volume deployments):

```yaml
# values.yaml
uptimeKuma:
  database:
    type: mariadb
    mariadb:
      host: mariadb-host
      port: 3306
      database: uptime_kuma
      username: uptime_kuma
      password: <password>
```

### Troubleshooting Common Issues

**Pod Not Starting:**

```bash
# Check pod events
make -f make/ops/uptime-kuma.mk uk-events

# Check pod status
kubectl describe pod -l app.kubernetes.io/name=uptime-kuma

# Check logs
make -f make/ops/uptime-kuma.mk uk-logs
```

**Monitors Not Running:**

```bash
# Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check

# Restart deployment
kubectl rollout restart deployment/uptime-kuma

# Check monitor count
make -f make/ops/uptime-kuma.mk uk-check-monitors
```

**High CPU Usage:**

1. Check monitor count (reduce if excessive)
2. Increase monitor check intervals
3. Optimize database with vacuum
4. Consider switching to MariaDB

**Database Corruption:**

```bash
# Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check

# If corrupted, restore from backup
make -f make/ops/uptime-kuma.mk uk-restore-database \
  FILE=tmp/uptime-kuma-backups/kuma-20250109-143022.db
```

### Maintenance Windows

**Planned Maintenance:**

```bash
# 1. Backup before maintenance
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Scale down to 0 replicas
kubectl scale deployment uptime-kuma --replicas=0

# 3. Perform maintenance (upgrade, migrate, etc.)

# 4. Scale up
kubectl scale deployment uptime-kuma --replicas=1

# 5. Verify health
make -f make/ops/uptime-kuma.mk uk-stats
```

---

## Upgrading

Comprehensive procedures for upgrading Uptime Kuma deployments.

### Pre-Upgrade Checklist

**CRITICAL: Complete these steps before upgrading:**

1. **Backup Everything:**
   ```bash
   make -f make/ops/uptime-kuma.mk uk-full-backup
   ```

2. **Check Current Version:**
   ```bash
   kubectl get deployment uptime-kuma -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

3. **Review Release Notes:**
   - [Uptime Kuma Releases](https://github.com/louislam/uptime-kuma/releases)
   - Check for breaking changes
   - Note database schema changes

4. **Verify Current State:**
   ```bash
   # Check pod health
   make -f make/ops/uptime-kuma.mk uk-stats

   # Count monitors
   make -f make/ops/uptime-kuma.mk uk-check-monitors
   ```

5. **Check Storage Space:**
   ```bash
   # Ensure enough space for database migration
   kubectl exec deployment/uptime-kuma -- df -h /app/data
   ```

6. **Test in Staging:**
   - Deploy same version to staging environment
   - Restore production backup to staging
   - Perform test upgrade
   - Validate functionality

7. **Plan Maintenance Window:**
   - **Minimal downtime**: Use Rolling Upgrade (2-5 minutes)
   - **Zero downtime**: Use Blue-Green Deployment (30-60 minutes setup)
   - **Full restart**: Use Maintenance Window (10-20 minutes)

8. **Notify Users:**
   - Announce upgrade window
   - Warn about brief monitoring gap

### Upgrade Strategies

This chart supports 3 upgrade strategies:

#### Strategy 1: Rolling Upgrade (Recommended)

**Minimal downtime (2-5 minutes)** - Recommended for production.

```bash
# 1. Backup first
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Update chart
helm upgrade uptime-kuma sb-charts/uptime-kuma \
  --reuse-values \
  --set image.tag=1.24.0

# 3. Monitor rollout
kubectl rollout status deployment/uptime-kuma

# 4. Verify health
make -f make/ops/uptime-kuma.mk uk-stats
make -f make/ops/uptime-kuma.mk uk-get-url
```

**Limitations:**
- ⚠️ Brief monitoring gap during pod restart
- ⚠️ No rollback after database migration completes

#### Strategy 2: Blue-Green Deployment

**Low-risk with instant rollback capability.**

```bash
# 1. Deploy new version alongside old (green)
helm install uptime-kuma-green sb-charts/uptime-kuma \
  -f values.yaml \
  --set image.tag=1.24.0 \
  --set nameOverride=uptime-kuma-green

# 2. Stop blue to allow green exclusive PVC access
kubectl scale deployment/uptime-kuma --replicas=0

# 3. Start green
kubectl scale deployment/uptime-kuma-green --replicas=1

# 4. Validate new version
make -f make/ops/uptime-kuma.mk uk-port-forward RELEASE=uptime-kuma-green
# Test at http://localhost:3001

# 5. Switch ingress to green
kubectl patch ingress uptime-kuma -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"uptime-kuma-green"}}}]}}]}}'

# 6. Verify traffic switched
make -f make/ops/uptime-kuma.mk uk-get-url

# 7. Keep old version for 24h, then delete
helm uninstall uptime-kuma  # Delete old blue version
```

**Rollback (if issues):**
```bash
# Switch ingress back to blue
kubectl scale deployment/uptime-kuma-green --replicas=0
kubectl scale deployment/uptime-kuma --replicas=1
kubectl patch ingress uptime-kuma -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"service":{"name":"uptime-kuma"}}}]}}]}}'
```

#### Strategy 3: Maintenance Window

**Simple upgrade with full downtime (10-20 minutes).**

```bash
# 1. Backup
make -f make/ops/uptime-kuma.mk uk-full-backup

# 2. Uninstall old version
helm uninstall uptime-kuma

# 3. Install new version
helm install uptime-kuma sb-charts/uptime-kuma \
  -f values.yaml \
  --set image.tag=2.0.0

# 4. Verify
make -f make/ops/uptime-kuma.mk uk-stats
```

**Use when:**
- ✅ Major version upgrade (1.x → 2.x)
- ✅ Database type change (SQLite → MariaDB)
- ✅ Downtime is acceptable

### Post-Upgrade Validation

**Run these checks after every upgrade:**

```bash
# 1. Check pod status
kubectl get pods -l app.kubernetes.io/name=uptime-kuma

# 2. Verify version
kubectl exec deployment/uptime-kuma -- node --version

# 3. Check logs for errors
make -f make/ops/uptime-kuma.mk uk-logs | grep -i error

# 4. Test web UI
make -f make/ops/uptime-kuma.mk uk-get-url

# 5. Verify monitors count
make -f make/ops/uptime-kuma.mk uk-check-monitors

# 6. Test notifications
# Via UI: Settings → Notifications → Test each channel

# 7. Check status pages
# Via UI: Status Pages → Verify all pages accessible

# 8. Check database integrity
make -f make/ops/uptime-kuma.mk uk-db-check
```

**Automated validation script:**

```bash
make -f make/ops/uptime-kuma.mk uk-post-upgrade-check
```

### Rollback Procedures

#### Rollback via Helm

```bash
# 1. List release history
helm history uptime-kuma

# 2. Rollback to previous revision
helm rollback uptime-kuma

# 3. Verify rollback
kubectl rollout status deployment/uptime-kuma
make -f make/ops/uptime-kuma.mk uk-stats
```

#### Full Rollback (if Helm fails)

```bash
# 1. Uninstall current version
helm uninstall uptime-kuma

# 2. Reinstall old version
helm install uptime-kuma sb-charts/uptime-kuma \
  -f values-backup.yaml \
  --set image.tag=1.23.11  # Previous version

# 3. Restore from backup (if database corrupted)
make -f make/ops/uptime-kuma.mk uk-restore-data \
  FILE=tmp/uptime-kuma-backups/data-20250109-120000.tar.gz

# 4. Restart pod
kubectl rollout restart deployment/uptime-kuma
```

### Version-Specific Upgrade Notes

#### 1.23.x → 1.24.x (Minor Version)

**Changes:**
- Improved notification providers
- New monitor types
- UI enhancements

**Steps:**
1. Use Rolling Upgrade strategy
2. Database migration automatic
3. Verify monitors and notifications

#### 1.x → 2.x (Major Version - TBD)

**Breaking Changes:**
- Database schema overhaul (one-way migration)
- API changes
- Configuration format changes

**Steps:**
1. **MANDATORY**: Full backup before upgrade
2. Test upgrade in staging
3. Use Maintenance Window strategy (expect 20-30 min downtime)
4. Database migration automatic on first start
5. Test all features thoroughly

### Upgrade Best Practices

**DO:**
- ✅ Always backup before upgrading
- ✅ Test upgrades in staging first
- ✅ Review release notes for breaking changes
- ✅ Verify database integrity after upgrade
- ✅ Keep old backups for 30 days
- ✅ Upgrade during low-traffic periods

**DON'T:**
- ❌ Skip backups (database migrations are irreversible)
- ❌ Upgrade multiple major versions at once
- ❌ Ignore database migration logs
- ❌ Delete old backups immediately

**For comprehensive upgrade procedures and version-specific notes**, see [Uptime Kuma Upgrade Guide](../../docs/uptime-kuma-upgrade-guide.md).

---

## Architecture Notes

- **Single Container**: Uptime Kuma runs as a single Node.js application
- **No Separate Workers**: Background jobs run within the same process
- **Embedded Database**: SQLite is embedded, no separate database pod needed
- **Stateless with MariaDB**: With external database, the pod becomes stateless (except for temp files)

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

Uptime Kuma is licensed under the [MIT License](https://github.com/louislam/uptime-kuma/blob/master/LICENSE).

This Helm chart is licensed under BSD-3-Clause.

## Resources

- Official Website: https://uptime.kuma.pet
- Documentation: https://github.com/louislam/uptime-kuma/wiki
- GitHub: https://github.com/louislam/uptime-kuma
- Docker Hub: https://hub.docker.com/r/louislam/uptime-kuma
- Demo: https://demo.uptime.kuma.pet
