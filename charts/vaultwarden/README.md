# Vaultwarden Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/vaultwarden)

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is an unofficial Bitwarden-compatible server written in Rust. It is lightweight, self-hosted, and provides a complete password management solution without requiring enterprise licensing.

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install my-vaultwarden scripton-charts/vaultwarden
```

## Introduction

This chart bootstraps a Vaultwarden deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- 🔐 Complete password manager (personal & organizations)
- 🗄️ Dual-mode support: SQLite (embedded) or PostgreSQL/MySQL (external)
- 📦 Auto-switching: StatefulSet for SQLite, Deployment for external DB
- 🔒 Production-ready with 2FA, WebAuthn, SMTP, and admin panel
- 🚀 Lightweight and fast (Rust-based)

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install vaultwarden-home charts/vaultwarden \
  -f charts/vaultwarden/values-home-single.yaml
```

**Resource allocation:** 50-250m CPU, 128-256Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install vaultwarden-startup charts/vaultwarden \
  -f charts/vaultwarden/values-startup-single.yaml
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with PostgreSQL and enhanced security:

```bash
helm install vaultwarden-prod charts/vaultwarden \
  -f charts/vaultwarden/values-prod-master-replica.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Features:** PostgreSQL support, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 20Gi storage

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#vaultwarden).


- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support in the underlying infrastructure (for persistence)
- (Optional) External PostgreSQL 12+ or MySQL 5.7+ database

## Versioning

| Chart Version | App Version | Kubernetes | Helm | Notes |
|---------------|-------------|------------|------|-------|
| 0.1.0         | 1.34.3      | 1.19+      | 3.0+ | Initial release with dual-mode support |

## Installing the Chart

### Basic Installation (SQLite mode)

To install the chart with the release name `my-vaultwarden`:

```bash
helm install my-vaultwarden scripton-charts/vaultwarden
```

### Production Installation (PostgreSQL)

For production deployments with external PostgreSQL:

```bash
helm install my-vaultwarden scripton-charts/vaultwarden \
  --set sqlite.enabled=false \
  --set postgresql.enabled=true \
  --set postgresql.external.host=postgres.default.svc \
  --set postgresql.external.password=strongpassword \
  --set vaultwarden.domain=https://vault.example.com \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=vault.example.com
```

## Uninstalling the Chart

To uninstall/delete the `my-vaultwarden` deployment:

```bash
helm delete my-vaultwarden
```

## Configuration

### Basic Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Vaultwarden replicas (Deployment mode only) | `1` |
| `image.repository` | Vaultwarden image repository | `vaultwarden/server` |
| `image.tag` | Vaultwarden image tag | `1.34.3` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### Vaultwarden Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vaultwarden.domain` | Domain URL for web-vault (REQUIRED) | `""` |
| `vaultwarden.admin.enabled` | Enable admin panel | `true` |
| `vaultwarden.admin.token` | Admin token (argon2 PHC string) | `""` (random) |
| `vaultwarden.admin.disableAdminToken` | Disable admin authentication (NOT RECOMMENDED) | `false` |

#### SMTP Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vaultwarden.smtp.enabled` | Enable SMTP for email notifications | `false` |
| `vaultwarden.smtp.host` | SMTP server hostname | `""` |
| `vaultwarden.smtp.port` | SMTP server port | `587` |
| `vaultwarden.smtp.security` | SMTP security (`starttls`, `force_tls`, `off`) | `starttls` |
| `vaultwarden.smtp.username` | SMTP username | `""` |
| `vaultwarden.smtp.password` | SMTP password | `""` |
| `vaultwarden.smtp.from` | From email address | `""` |
| `vaultwarden.smtp.fromName` | From name | `Vaultwarden` |

#### Sign-up Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vaultwarden.signups.allowed` | Allow new user registrations | `true` |
| `vaultwarden.signups.verifySignup` | Require email verification | `false` |
| `vaultwarden.signups.allowedDomains` | Allowed email domains (comma-separated) | `""` (all) |
| `vaultwarden.signups.allowInvitations` | Allow invitations even if signups disabled | `true` |

#### Security Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vaultwarden.security.require2FA` | Require 2FA for all users | `false` |
| `vaultwarden.security.showPasswordHint` | Show password hints | `true` |
| `vaultwarden.security.websocketEnabled` | Enable WebSocket notifications | `true` |
| `vaultwarden.security.iconService` | Icon download service | `internal` |
| `vaultwarden.security.disableIconDownload` | Disable icon downloads | `false` |

### Database Configuration

#### SQLite Mode (Default)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sqlite.enabled` | Use embedded SQLite database | `true` |

#### PostgreSQL Mode

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.enabled` | Use external PostgreSQL | `false` |
| `postgresql.external.host` | PostgreSQL hostname | `""` |
| `postgresql.external.port` | PostgreSQL port | `5432` |
| `postgresql.external.database` | Database name | `vaultwarden` |
| `postgresql.external.username` | Database username | `vaultwarden` |
| `postgresql.external.password` | Database password | `""` (REQUIRED) |

#### MySQL Mode

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mysql.enabled` | Use external MySQL/MariaDB | `false` |
| `mysql.external.host` | MySQL hostname | `""` |
| `mysql.external.port` | MySQL port | `3306` |
| `mysql.external.database` | Database name | `vaultwarden` |
| `mysql.external.username` | Database username | `vaultwarden` |
| `mysql.external.password` | Database password | `""` (REQUIRED) |

### Persistence Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.data.enabled` | Enable data directory persistence | `true` |
| `persistence.data.size` | Data PVC size | `1Gi` |
| `persistence.data.storageClass` | Data storage class | `""` |
| `persistence.data.existingClaim` | Use existing PVC for data | `""` |
| `persistence.data.accessMode` | Access mode | `ReadWriteOnce` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.ports` | Service ports (http, websocket) | See `values.yaml` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts | `[]` |
| `ingress.tls` | Ingress TLS configuration | `[]` |

### Resource Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |

## Deployment Modes

This chart automatically switches between two deployment modes:

### StatefulSet Mode (SQLite)

**When**: `sqlite.enabled=true` (default)

**Characteristics:**
- Uses StatefulSet for stable storage
- Data stored in PVC via volumeClaimTemplates
- Single replica (SQLite doesn't support clustering)
- Headless service for DNS stability

**Best for:**
- Home servers, personal use
- Small teams (< 10 users)
- Simple deployments without external database

### Deployment Mode (PostgreSQL/MySQL)

**When**: `postgresql.enabled=true` OR `mysql.enabled=true`

**Characteristics:**
- Uses Deployment (stateless workload)
- Data stored in external database
- Supports multiple replicas (with autoscaling)
- Optional PVC for attachments only

**Best for:**
- Production environments
- High availability requirements
- Large teams and organizations

## Examples

### Example 1: Home Server (SQLite)

```bash
helm install vaultwarden scripton-charts/vaultwarden \
  --set vaultwarden.domain=http://vault.local \
  --set vaultwarden.signups.allowed=true \
  --set persistence.data.size=5Gi
```

### Example 2: Production with PostgreSQL and Ingress

```bash
helm install vaultwarden scripton-charts/vaultwarden \
  --set sqlite.enabled=false \
  --set postgresql.enabled=true \
  --set postgresql.external.host=postgres.database.svc \
  --set postgresql.external.password=strongpassword \
  --set vaultwarden.domain=https://vault.example.com \
  --set vaultwarden.smtp.enabled=true \
  --set vaultwarden.smtp.host=smtp.gmail.com \
  --set vaultwarden.smtp.username=noreply@example.com \
  --set vaultwarden.smtp.password=smtp-password \
  --set vaultwarden.smtp.from=noreply@example.com \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod \
  --set ingress.hosts[0].host=vault.example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --set ingress.tls[0].secretName=vaultwarden-tls \
  --set ingress.tls[0].hosts[0]=vault.example.com
```

### Example 3: Custom Configuration File

```yaml
# custom-values.yaml
vaultwarden:
  domain: "https://vault.example.com"
  admin:
    enabled: true
    token: ""  # Will generate random token
  smtp:
    enabled: true
    host: "smtp.sendgrid.net"
    port: 587
    security: "starttls"
    username: "apikey"
    password: "SG.xxx"
    from: "noreply@example.com"
  signups:
    allowed: false
    allowInvitations: true
    allowedDomains: "example.com,example.org"
  security:
    require2FA: true
    websocketEnabled: true

sqlite:
  enabled: false

postgresql:
  enabled: true
  external:
    host: "postgres-ha.database.svc"
    port: 5432
    database: "vaultwarden"
    username: "vaultwarden"
    password: "strong-db-password"

persistence:
  data:
    size: 10Gi
    storageClass: "fast-ssd"

ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: vault.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: vaultwarden-tls
      hosts:
        - vault.example.com

resources:
  limits:
    cpu: 2000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

```bash
helm install vaultwarden scripton-charts/vaultwarden -f custom-values.yaml
```

## Initial Setup

After installation, complete the setup:

1. **Access Vaultwarden Web UI:**
   ```bash
   kubectl port-forward svc/vaultwarden 8080:80
   ```
   Open http://localhost:8080

2. **Create Your First Account:**
   - Register a new account (if signups enabled)
   - Or use invitation system if signups disabled

3. **Configure Admin Panel:**
   - Navigate to /admin
   - Retrieve admin token:
     ```bash
     kubectl get secret vaultwarden -o jsonpath='{.data.admin-token}' | base64 -d
     ```
   - Configure SMTP, sign-up policies, and security settings

4. **Set Up SMTP (Recommended):**
   - Required for password resets and invitations
   - Update values.yaml with SMTP configuration
   - Test email sending from admin panel

5. **Enable Two-Factor Authentication:**
   - Available methods: Authenticator, Email, FIDO2, YubiKey, Duo
   - Enable from account settings

## Operational Commands

This chart includes operational commands via Makefile.

### Access & Debugging

```bash
# Port forward to localhost
make -f make/ops/vaultwarden.mk vw-port-forward

# View logs
make -f make/ops/vaultwarden.mk vw-logs

# Open shell
make -f make/ops/vaultwarden.mk vw-shell

# Restart deployment
make -f make/ops/vaultwarden.mk vw-restart
```

### Admin Panel

```bash
# Get admin token
make -f make/ops/vaultwarden.mk vw-get-admin-token

# Access admin panel (via port-forward)
make -f make/ops/vaultwarden.mk vw-admin
```

### Database Operations

```bash
# Backup database (SQLite mode)
make -f make/ops/vaultwarden.mk vw-backup-db

# Restore database (SQLite mode)
make -f make/ops/vaultwarden.mk vw-restore-db FILE=tmp/vaultwarden-backups/db.sqlite3

# Check database connection (PostgreSQL/MySQL mode)
make -f make/ops/vaultwarden.mk vw-db-test
```

### Monitoring

```bash
# Show resource usage
make -f make/ops/vaultwarden.mk vw-stats

# Describe pod
make -f make/ops/vaultwarden.mk vw-describe

# Show pod events
make -f make/ops/vaultwarden.mk vw-events
```

## Troubleshooting

### Web Vault Not Loading

**Symptom**: White screen or "Vault cannot be reached"

**Cause**: Web Crypto API requires HTTPS or http://localhost

**Solution**: Set proper domain URL:
```yaml
vaultwarden:
  domain: "https://vault.example.com"  # Must be HTTPS
```

### SMTP Not Working

**Check SMTP configuration:**
```bash
kubectl logs deployment/vaultwarden | grep -i smtp
```

**Test from admin panel**: /admin → Diagnostics → Test SMTP

### Database Connection Failed

**PostgreSQL:**
```bash
kubectl exec -it deployment/vaultwarden -- \
  pg_isready -h postgres-host -p 5432 -U vaultwarden
```

**MySQL:**
```bash
kubectl exec -it deployment/vaultwarden -- \
  mysqladmin ping -h mysql-host -P 3306 -u vaultwarden -p
```

### Admin Panel Locked Out

**Retrieve admin token:**
```bash
kubectl get secret vaultwarden -o jsonpath='{.data.admin-token}' | base64 -d
```

**Or disable token temporarily:**
```yaml
vaultwarden:
  admin:
    disableAdminToken: true  # WARNING: Insecure!
```

---

## Backup & Recovery

This chart includes comprehensive backup and recovery capabilities for Vaultwarden deployments.

### Backup Strategy

Vaultwarden backups consist of **4 complementary components**:

| Component | Priority | Frequency | RTO | Method |
|-----------|----------|-----------|-----|--------|
| **Data Directory** | CRITICAL | Hourly/Daily | 30 min | rsync/tar |
| **Database** (External) | CRITICAL | Daily | 15 min | pg_dump/mysqldump |
| **Configuration** | HIGH | On change | 10 min | kubectl export |
| **PVC Snapshots** | MEDIUM | Weekly | 30 min | VolumeSnapshot API |

**Recovery Targets:**
- **RTO**: < 1 hour (complete instance recovery)
- **RPO**: 24 hours (daily backups), 1 hour (critical deployments)

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/vaultwarden.mk vw-full-backup

# Individual component backups
make -f make/ops/vaultwarden.mk vw-backup-data-full       # Data directory (tar)
make -f make/ops/vaultwarden.mk vw-backup-data-incremental # Data directory (rsync)
make -f make/ops/vaultwarden.mk vw-backup-sqlite          # SQLite database
make -f make/ops/vaultwarden.mk vw-backup-postgres        # PostgreSQL database
make -f make/ops/vaultwarden.mk vw-backup-mysql           # MySQL database
make -f make/ops/vaultwarden.mk vw-backup-config          # Kubernetes resources

# PVC snapshots (requires VolumeSnapshot API)
make -f make/ops/vaultwarden.mk vw-snapshot-data
make -f make/ops/vaultwarden.mk vw-list-snapshots
```

### Quick Recovery Commands

```bash
# Restore from backups
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/path/to/backup.tar.gz
make -f make/ops/vaultwarden.mk vw-restore-postgres BACKUP_FILE=/path/to/backup.sql.gz
make -f make/ops/vaultwarden.mk vw-restore-mysql BACKUP_FILE=/path/to/backup.sql.gz
make -f make/ops/vaultwarden.mk vw-restore-config BACKUP_FILE=/path/to/config.tar.gz

# Full disaster recovery
make -f make/ops/vaultwarden.mk vw-full-recovery \
  DATA_BACKUP=/path/to/data.tar.gz \
  DB_BACKUP=/path/to/database.sql.gz \
  CONFIG_BACKUP=/path/to/config.tar.gz
```

### Backup Components in Detail

**1. Data Directory (`/data`):**
- Vault database (SQLite mode) or attachments (external DB mode)
- File attachments uploaded by users
- Send temporary files
- Website icon cache
- RSA keys for JWT signing

**2. Database (External mode):**
- Vault metadata and items (PostgreSQL/MySQL)
- User accounts and organizations
- Collection and group permissions
- Audit logs and events

**3. Configuration:**
- Kubernetes Deployment/StatefulSet manifests
- Helm values and release configuration
- Environment variables and secrets
- Ingress and service definitions

**4. PVC Snapshots:**
- Point-in-time storage snapshots
- Fast disaster recovery
- Storage-level consistency

### Best Practices

- ✅ **Test restore quarterly**: Schedule disaster recovery drills
- ✅ **Store off-site**: Use different availability zone or S3/MinIO
- ✅ **Encrypt backups**: Config contains admin tokens and SMTP passwords
- ✅ **Automate retention**: Keep 7 daily, 4 weekly, 12 monthly, 1 yearly
- ✅ **Monitor success**: Alert on failed backups
- ✅ **Document locations**: Maintain inventory with encryption keys

**Complete Guide:** [docs/vaultwarden-backup-guide.md](../../docs/vaultwarden-backup-guide.md)

---

## Security & RBAC

### RBAC Configuration

This chart creates namespace-scoped Role and RoleBinding for Vaultwarden operations.

**RBAC Resources Created:**
- **Role**: Read access to ConfigMaps, Secrets, Pods, Services, Endpoints, PVCs
- **RoleBinding**: Binds ServiceAccount to Role
- **ServiceAccount**: Dedicated service account for Vaultwarden pods

**Configuration:**
```yaml
rbac:
  create: true              # Create RBAC resources (default: true)
  annotations: {}           # Annotations for Role and RoleBinding
```

**Permissions Granted:**
| Resource | Verbs | Purpose |
|----------|-------|---------|
| configmaps | get, list, watch | Read configuration |
| secrets | get, list, watch | Read credentials (DB, SMTP, admin token) |
| pods | get, list, watch | Health checks and operations |
| services | get, list, watch | Service discovery |
| endpoints | get, list, watch | Service discovery |
| persistentvolumeclaims | get, list, watch | Storage operations |

**Security Considerations:**
- Namespace-scoped (not cluster-wide)
- Read-only permissions (no create/update/delete)
- Minimal permissions principle
- Compatible with Pod Security Standards (PSS)

### Pod Security

**Pod Security Context:**
```yaml
podSecurityContext:
  fsGroup: 1000              # File ownership for /data

securityContext:
  runAsUser: 1000            # Non-root user
  runAsGroup: 1000
  runAsNonRoot: true
  readOnlyRootFilesystem: false  # Vaultwarden needs /data write access
  capabilities:
    drop:
      - ALL
```

**Security Hardening:**
- ✅ Runs as non-root user (UID 1000)
- ✅ Drops all capabilities
- ✅ Read-only root filesystem (except /data volume)
- ✅ No privilege escalation
- ✅ Seccomp profile (if available)

### Network Security

**NetworkPolicy (optional):**
```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - podSelector:
          matchLabels: {}
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 3012  # WebSocket
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            name: database-namespace
      ports:
        - protocol: TCP
          port: 5432  # PostgreSQL
```

**Ingress Security:**
- TLS termination recommended
- HTTPS required for WebAuthn/Passkeys
- Rate limiting via ingress controller
- IP allowlisting for admin panel

---

## Operations

### Common Operational Tasks

**Status and Logs:**
```bash
make -f make/ops/vaultwarden.mk vw-status     # Pod status
make -f make/ops/vaultwarden.mk vw-logs       # View logs
make -f make/ops/vaultwarden.mk vw-logs-follow # Follow logs
make -f make/ops/vaultwarden.mk vw-shell      # Interactive shell
```

**Restart and Scaling:**
```bash
make -f make/ops/vaultwarden.mk vw-restart    # Restart pods
make -f make/ops/vaultwarden.mk vw-scale REPLICAS=2  # Scale replicas
```

**Admin Operations:**
```bash
make -f make/ops/vaultwarden.mk vw-admin-url  # Get admin panel URL
make -f make/ops/vaultwarden.mk vw-get-admin-token  # Retrieve admin token
make -f make/ops/vaultwarden.mk vw-disable-admin    # Disable admin panel
make -f make/ops/vaultwarden.mk vw-enable-admin     # Enable admin panel
```

**Database Operations:**

*SQLite mode:*
```bash
make -f make/ops/vaultwarden.mk vw-db-size         # Check database size
make -f make/ops/vaultwarden.mk vw-db-integrity    # Integrity check
make -f make/ops/vaultwarden.mk vw-db-vacuum       # Optimize database
```

*PostgreSQL mode:*
```bash
make -f make/ops/vaultwarden.mk vw-db-shell        # PostgreSQL shell
make -f make/ops/vaultwarden.mk vw-db-connections  # Active connections
make -f make/ops/vaultwarden.mk vw-db-table-sizes  # Table sizes
```

**User Management:**
```bash
make -f make/ops/vaultwarden.mk vw-list-users      # List all users
make -f make/ops/vaultwarden.mk vw-delete-user EMAIL=user@example.com
make -f make/ops/vaultwarden.mk vw-invite-user EMAIL=user@example.com
```

**Monitoring:**
```bash
make -f make/ops/vaultwarden.mk vw-disk-usage      # Data directory usage
make -f make/ops/vaultwarden.mk vw-resource-usage  # CPU/memory usage
make -f make/ops/vaultwarden.mk vw-port-forward    # Port forward to localhost
```

**Cleanup:**
```bash
make -f make/ops/vaultwarden.mk vw-cleanup-trashed # Delete trashed items
make -f make/ops/vaultwarden.mk vw-cleanup-sends   # Delete expired Sends
make -f make/ops/vaultwarden.mk vw-cleanup-icons   # Clear icon cache
```

### Health Checks

**Manual health check:**
```bash
# Check pod health
kubectl get pods -n default -l app.kubernetes.io/name=vaultwarden

# Check liveness
curl http://localhost:8080/alive

# Check readiness
curl http://localhost:8080/alive

# View health probe status
kubectl describe pod -n default -l app.kubernetes.io/name=vaultwarden | grep -A5 "Liveness\|Readiness"
```

**Configured probes:**
- **Liveness**: `GET /alive` - Pod is running
- **Readiness**: `GET /alive` - Pod can accept traffic
- **Startup**: `GET /alive` - Initial startup complete (300s timeout)

### Troubleshooting Commands

```bash
# Describe pod for events
make -f make/ops/vaultwarden.mk vw-describe

# Check resource usage
make -f make/ops/vaultwarden.mk vw-top

# View all events
kubectl get events -n default --field-selector involvedObject.name=vaultwarden

# Debug with temporary pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
```

---

## Upgrading

This chart supports multiple upgrade strategies for different scenarios.

### Upgrade Strategies

| Strategy | Downtime | Risk | Best For |
|----------|----------|------|----------|
| **Rolling Upgrade** | None | Low | Patch/minor versions |
| **In-Place Upgrade** | 10-15 min | Medium | Major versions, StatefulSet |
| **Blue-Green** | None | Low | Zero-downtime major upgrades |

### Pre-Upgrade Checklist

**CRITICAL steps before ANY upgrade:**

- [ ] Review release notes: https://github.com/dani-garcia/vaultwarden/releases
- [ ] Create full backup: `make -f make/ops/vaultwarden.mk vw-full-backup`
- [ ] Create PVC snapshot: `make -f make/ops/vaultwarden.mk vw-snapshot-data`
- [ ] Check database health: `make -f make/ops/vaultwarden.mk vw-db-integrity`
- [ ] Export current values: `helm get values vaultwarden > backup-values.yaml`
- [ ] Test backup restore (recommended): See [backup guide](../../docs/vaultwarden-backup-guide.md)
- [ ] Plan maintenance window (if downtime required)
- [ ] Notify users of upgrade schedule

### Quick Upgrade (Rolling)

**Best for:** Patch versions (1.34.0 → 1.34.3)

```bash
# 1. Pre-upgrade checks
make -f make/ops/vaultwarden.mk vw-pre-upgrade-check

# 2. Backup
make -f make/ops/vaultwarden.mk vw-full-backup

# 3. Upgrade
helm repo update sb-charts
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values.yaml \
  --set image.tag=1.34.3 \
  --wait

# 4. Verify
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

### Major Version Upgrade (In-Place)

**Best for:** Major versions (1.30.x → 1.34.x)

```bash
# 1. Pre-upgrade checks and backup
make -f make/ops/vaultwarden.mk vw-pre-upgrade-check
make -f make/ops/vaultwarden.mk vw-full-backup
make -f make/ops/vaultwarden.mk vw-snapshot-data

# 2. Stop service (downtime begins)
kubectl scale deployment/vaultwarden -n default --replicas=0

# 3. Upgrade
helm upgrade vaultwarden sb-charts/vaultwarden \
  -n default \
  -f values.yaml \
  --set image.tag=1.34.3 \
  --wait

# 4. Verify and restart
make -f make/ops/vaultwarden.mk vw-post-upgrade-check
```

### Database Backend Migration

**Migrating from SQLite to PostgreSQL:**

See detailed procedure in [upgrade guide](../../docs/vaultwarden-upgrade-guide.md#database-backend-migration-sqlite--postgresql)

**Estimated time:** 1-2 hours (full downtime)

### Post-Upgrade Validation

```bash
# Automated checks
make -f make/ops/vaultwarden.mk vw-post-upgrade-check

# Manual verification:
# 1. Login to web vault
# 2. Verify password items load correctly
# 3. Test password creation/update
# 4. Verify file attachments work
# 5. Test Send feature
# 6. Test organization features (if used)
# 7. Sync from mobile app
# 8. Check logs for errors: make -f make/ops/vaultwarden.mk vw-logs
```

### Rollback Procedures

**Scenario 1: Rollback via Helm (no database changes)**
```bash
helm rollback vaultwarden -n default
kubectl rollout status deployment/vaultwarden -n default
```

**Scenario 2: Rollback with database restore**
```bash
# Stop service
kubectl scale deployment/vaultwarden -n default --replicas=0

# Restore database
make -f make/ops/vaultwarden.mk vw-restore-data BACKUP_FILE=/path/to/backup.tar.gz

# Rollback Helm
helm rollback vaultwarden -n default
```

**Scenario 3: Rollback via PVC snapshot (fastest)**
```bash
kubectl scale deployment/vaultwarden -n default --replicas=0
make -f make/ops/vaultwarden.mk vw-restore-from-snapshot SNAPSHOT_NAME=vaultwarden-data-snapshot-*
helm rollback vaultwarden -n default
```

### Version-Specific Notes

**Vaultwarden 1.32.x → 1.34.x:**
- Alpine Linux 3.20 update (may require permission fixes)
- Database migration adds indices (< 1 minute)
- WebAuthn improvements
- Organization enhancements
- No breaking changes

**Vaultwarden 1.30.x → 1.32.x:**
- Emergency access feature added
- Event logging improvements
- SQLite performance optimizations
- No breaking changes

**Complete Guide:** [docs/vaultwarden-upgrade-guide.md](../../docs/vaultwarden-upgrade-guide.md)

---

## Migration from Other Charts

### From k8s-at-home/vaultwarden

Key differences:
- **Dual-mode support**: Auto-switching between StatefulSet/Deployment
- **External database**: First-class PostgreSQL/MySQL support
- **Production features**: HPA, PDB, NetworkPolicy
- **Operational commands**: Makefile targets for day-2 operations

**Migration steps:**
1. Backup existing data: `make -f make/ops/vaultwarden.mk vw-backup-db`
2. Export existing PVC
3. Install this chart with existing PVC
4. Restore data if needed

## Project Philosophy

This chart follows [ScriptonBasestar Helm Charts](https://github.com/scriptonbasestar-container/sb-helm-charts) principles:

- ✅ Flexible database backends (SQLite or external)
- ✅ Auto-switching workload types (StatefulSet/Deployment)
- ✅ Configuration files over complex env var abstractions
- ✅ Production-ready defaults with security hardening
- ✅ No database subcharts - external databases are separate

## Security Considerations

1. **Always use HTTPS in production**: Web Crypto API requirement
2. **Strong admin token**: Use `vaultwarden hash` to generate argon2 PHC string
3. **Enable 2FA**: Especially for admin accounts
4. **Restrict sign-ups**: Use `allowedDomains` or disable public registration
5. **SMTP security**: Use starttls or force_tls for email
6. **Regular backups**: Automate database backups
7. **Network policies**: Enable `networkPolicy.enabled=true` in production

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

- **Chart License:** BSD-3-Clause
- **Vaultwarden License:** GPL-3.0

## Links

- **Vaultwarden Official:** https://github.com/dani-garcia/vaultwarden
- **Vaultwarden Wiki:** https://github.com/dani-garcia/vaultwarden/wiki
- **Docker Hub:** https://hub.docker.com/r/vaultwarden/server
- **Chart Repository:** https://github.com/scriptonbasestar-container/sb-helm-charts

## Support

For issues and feature requests, please open an issue at:
https://github.com/scriptonbasestar-container/sb-helm-charts/issues
