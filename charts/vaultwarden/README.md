# Vaultwarden Helm Chart

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
