# pgAdmin Helm Chart

pgAdmin is a feature-rich web-based administration and management tool for PostgreSQL databases. This chart provides a production-ready deployment with security best practices, high availability support, and flexible configuration options.

## Features

- **Web-based PostgreSQL Management**: Full-featured GUI for database administration
- **Multi-Server Support**: Manage multiple PostgreSQL instances from single interface
- **Pre-configured Servers**: Automatic server registration via values configuration
- **Security Hardening**: Non-root user, network policies, session protection
- **High Availability**: Multi-replica support with session affinity
- **Production Ready**: TLS/HTTPS, MFA support, audit logging capabilities
- **Backup & Restore**: Built-in metadata backup and server configuration export

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support (for persistence)
- PostgreSQL database(s) to manage

## Installation

### Quick Start (Development)

```bash
# Create namespace
kubectl create namespace database-admin

# Install with development values
helm install pgadmin charts/pgadmin \
  --namespace database-admin \
  --values charts/pgadmin/values-dev.yaml
```

### Production Installation

```bash
# Install with production values and custom credentials
helm install pgadmin charts/pgadmin \
  --namespace database-admin \
  --values charts/pgadmin/values-small-prod.yaml \
  --set pgadmin.defaultEmail="dba@company.com" \
  --set pgadmin.defaultPassword="$(openssl rand -base64 32)"
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of pgAdmin replicas | `1` |
| `image.repository` | pgAdmin image repository | `dpage/pgadmin4` |
| `image.tag` | pgAdmin image tag | `8.13` |
| `pgadmin.defaultEmail` | Admin user email (required) | `admin@example.com` |
| `pgadmin.defaultPassword` | Admin password (required) | `""` |

### pgAdmin Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `pgadmin.serverMode` | Enable server mode (vs desktop) | `true` |
| `pgadmin.enhancedCookieProtection` | Enhanced cookie security | `true` |
| `pgadmin.sessionTimeout` | Session timeout in minutes | `60` |
| `pgadmin.mfaSupported` | Enable MFA/2FA support | `false` |
| `pgadmin.passwordLengthMin` | Minimum password length | `8` |
| `pgadmin.logLevel` | Log level (DEBUG, INFO, WARNING, ERROR) | `WARNING` |
| `pgadmin.extraEnv` | Additional environment variables | `[]` |

### Server Pre-configuration

Configure PostgreSQL servers that will be automatically available after login:

```yaml
servers:
  enabled: true
  config:
    - Name: "Production DB"
      Group: "Production"
      Host: "postgresql-prod.default.svc.cluster.local"
      Port: 5432
      MaintenanceDB: "postgres"
      Username: "pgadmin_readonly"
      SSLMode: "require"
      Comment: "Production PostgreSQL - Read Only"

    - Name: "Staging DB"
      Group: "Staging"
      Host: "postgresql-staging.default.svc.cluster.local"
      Port: 5432
      MaintenanceDB: "postgres"
      Username: "pgadmin"
      SSLMode: "prefer"
      Comment: "Staging PostgreSQL"
```

**Note**: Server passwords are not stored in configuration. Users must enter passwords on first connection.

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable data persistence | `true` |
| `persistence.storageClass` | Storage class name | `""` |
| `persistence.accessMode` | Access mode | `ReadWriteOnce` |
| `persistence.size` | Volume size | `1Gi` |
| `persistence.existingClaim` | Use existing PVC | `""` |

**What is persisted:**
- User accounts and preferences
- Server connection configurations
- Query history
- Saved queries and scripts
- Session data

### Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    # Session affinity for multi-replica deployments
    nginx.ingress.kubernetes.io/affinity: "cookie"
  hosts:
    - host: pgadmin.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: pgadmin-tls
      hosts:
        - pgadmin.example.com
```

**Important**: For multi-replica deployments, enable session affinity (cookie-based) to ensure users connect to the same pod.

### Security

#### Network Policies

Restrict network access to pgAdmin:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow from ingress controller
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
      ports:
      - protocol: TCP
        port: 80
  egress:
    # Allow DNS
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53
    # Allow PostgreSQL connections
    - to:
      - namespaceSelector:
          matchLabels:
            name: database
      ports:
      - protocol: TCP
        port: 5432
```

#### Password Policies

```yaml
pgadmin:
  passwordLengthMin: 12
  mfaSupported: true
  enhancedCookieProtection: true
  sessionTimeout: 30  # minutes
```

### High Availability

```yaml
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
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - pgadmin
          topologyKey: kubernetes.io/hostname
```

**Note**: pgAdmin stores session data in SQLite. For true HA, you need:
1. Ingress session affinity (cookie-based)
2. Anti-affinity to spread pods across nodes
3. Persistent storage for each replica

### Resources

#### Development
```yaml
resources:
  limits:
    cpu: 300m
    memory: 256Mi
  requests:
    cpu: 50m
    memory: 64Mi
```

#### Production (Small Team)
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi
```

## Usage

### Accessing pgAdmin

1. **Get the URL:**

```bash
# If using Ingress
echo "https://$(kubectl get ingress -n database-admin pgadmin -o jsonpath='{.spec.rules[0].host}')"

# If using port-forward
make -f make/ops/pgadmin.mk pgadmin-port-forward
# Visit http://localhost:8080
```

2. **Get credentials:**

```bash
# Get admin password
make -f make/ops/pgadmin.mk pgadmin-get-password
```

3. **Login:**
- Email: Value from `pgadmin.defaultEmail`
- Password: Retrieved from step 2

### Adding PostgreSQL Servers

#### Via Web UI

1. Login to pgAdmin
2. Right-click "Servers" → "Register" → "Server"
3. General Tab:
   - Name: `My Database`
4. Connection Tab:
   - Host: `postgresql.default.svc.cluster.local`
   - Port: `5432`
   - Maintenance database: `postgres`
   - Username: `postgres`
   - Password: `<your-password>`
5. SSL Tab:
   - SSL mode: `Prefer` or `Require`
6. Save

#### Via Configuration (Recommended for Production)

Update `values.yaml` before installation:

```yaml
servers:
  enabled: true
  config:
    - Name: "My Database"
      Group: "Production"
      Host: "postgresql.default.svc.cluster.local"
      Port: 5432
      MaintenanceDB: "postgres"
      Username: "postgres"
      SSLMode: "require"
```

### Backup and Restore

#### Backup pgAdmin Metadata

```bash
# Backup all pgAdmin data (users, servers, preferences)
make -f make/ops/pgadmin.mk pgadmin-backup-metadata
```

This creates: `tmp/pgadmin-backups/pgadmin-backup-YYYYMMDD-HHMMSS.tar.gz`

#### Restore pgAdmin Metadata

```bash
# Restore from backup
make -f make/ops/pgadmin.mk pgadmin-restore-metadata FILE=tmp/pgadmin-backups/pgadmin-backup.tar.gz

# Restart pgAdmin
make -f make/ops/pgadmin.mk pgadmin-restart
```

#### Export Server Configurations

```bash
# Export servers.json (server list, no passwords)
make -f make/ops/pgadmin.mk pgadmin-export-servers
```

### User Management

#### List Users

```bash
make -f make/ops/pgadmin.mk pgadmin-list-users
```

#### Create Additional Users

Use the web UI:
1. Login as admin
2. Go to: File → Preferences → User Management
3. Click "+" to add user
4. Set email, password, and role

## Operational Commands

Full list of operational commands:

```bash
# Access & Credentials
make -f make/ops/pgadmin.mk pgadmin-get-password
make -f make/ops/pgadmin.mk pgadmin-port-forward

# Server Management
make -f make/ops/pgadmin.mk pgadmin-list-servers
make -f make/ops/pgadmin.mk pgadmin-test-connection HOST=postgresql.default.svc.cluster.local

# User Management
make -f make/ops/pgadmin.mk pgadmin-list-users

# Configuration
make -f make/ops/pgadmin.mk pgadmin-get-config
make -f make/ops/pgadmin.mk pgadmin-export-servers

# Backup & Restore
make -f make/ops/pgadmin.mk pgadmin-backup-metadata
make -f make/ops/pgadmin.mk pgadmin-restore-metadata FILE=<file>

# Monitoring
make -f make/ops/pgadmin.mk pgadmin-health
make -f make/ops/pgadmin.mk pgadmin-version
make -f make/ops/pgadmin.mk pgadmin-logs
make -f make/ops/pgadmin.mk pgadmin-shell

# Operations
make -f make/ops/pgadmin.mk pgadmin-restart
```

## Security Best Practices

### Production Deployment

1. **Strong Passwords**
   - Use at least 16 characters
   - Generate securely: `openssl rand -base64 32`
   - Never commit passwords to git

2. **Enable MFA/2FA**
   ```yaml
   pgadmin:
     mfaSupported: true
   ```
   - Configure after first login in user preferences

3. **Use HTTPS Only**
   ```yaml
   ingress:
     enabled: true
     annotations:
       nginx.ingress.kubernetes.io/ssl-redirect: "true"
       nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
   ```

4. **Network Policies**
   - Enable to restrict access
   - Allow only necessary ingress/egress

5. **PostgreSQL Connections**
   - Use SSL/TLS for database connections
   - Create read-only users where appropriate
   - Never use superuser accounts for routine queries

6. **Audit Logging**
   ```yaml
   pgadmin:
     extraEnv:
       - name: PGADMIN_CONFIG_AUDIT_LOGGING
         value: "True"
   ```

7. **Regular Updates**
   - Keep pgAdmin image up to date
   - Monitor security advisories

8. **Data Protection**
   - Enable persistence for production
   - Regular backups of pgAdmin metadata
   - Use Velero or similar for PVC backups

### PostgreSQL Access Control

Create dedicated pgAdmin users in PostgreSQL:

```sql
-- Read-only user for query access
CREATE ROLE pgadmin_readonly LOGIN PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE mydb TO pgadmin_readonly;
GRANT USAGE ON SCHEMA public TO pgadmin_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pgadmin_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO pgadmin_readonly;

-- Admin user for schema changes (use sparingly)
CREATE ROLE pgadmin_admin LOGIN PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE mydb TO pgadmin_admin;
```

## Troubleshooting

### Common Issues

#### 1. Cannot Login - Incorrect Password

```bash
# Get the actual password
make -f make/ops/pgadmin.mk pgadmin-get-password

# Or check the secret directly
kubectl get secret -n database-admin pgadmin -o jsonpath='{.data.password}' | base64 -d
```

#### 2. Server List Empty After Upgrade

Pre-configured servers are only added on first startup. To restore:

```bash
# Export current servers (if any)
make -f make/ops/pgadmin.mk pgadmin-export-servers

# Edit ConfigMap
kubectl edit configmap -n database-admin pgadmin-servers

# Restart pgAdmin
make -f make/ops/pgadmin.mk pgadmin-restart
```

#### 3. Connection to PostgreSQL Fails

```bash
# Test connection from pgAdmin pod
make -f make/ops/pgadmin.mk pgadmin-test-connection HOST=postgresql.default.svc.cluster.local

# Check network policies
kubectl get networkpolicies -n database-admin

# Check PostgreSQL service
kubectl get svc -n default postgresql
```

#### 4. Session Lost After Pod Restart (Multi-Replica)

Enable session affinity in Ingress:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "pgadmin-session"
```

#### 5. Slow Startup or High Memory Usage

Increase resources or reduce configured servers:

```yaml
resources:
  limits:
    memory: 2Gi  # Increase if needed
```

### Debug Commands

```bash
# Check pod status
kubectl get pods -n database-admin -l app.kubernetes.io/name=pgadmin

# View logs
make -f make/ops/pgadmin.mk pgadmin-logs

# Get pod details
kubectl describe pod -n database-admin $(kubectl get pods -n database-admin -l app.kubernetes.io/name=pgadmin -o jsonpath='{.items[0].metadata.name}')

# Check configuration
make -f make/ops/pgadmin.mk pgadmin-get-config

# Interactive shell
make -f make/ops/pgadmin.mk pgadmin-shell
```

## Upgrading

### From Previous Version

1. **Backup current installation:**
   ```bash
   make -f make/ops/pgadmin.mk pgadmin-backup-metadata
   ```

2. **Update chart:**
   ```bash
   helm upgrade pgadmin charts/pgadmin \
     --namespace database-admin \
     --values my-values.yaml
   ```

3. **Verify:**
   ```bash
   kubectl get pods -n database-admin -l app.kubernetes.io/name=pgadmin
   make -f make/ops/pgadmin.mk pgadmin-health
   ```

### Breaking Changes

No breaking changes in current version (0.3.0).

## Uninstalling

```bash
# Uninstall release
helm uninstall pgadmin --namespace database-admin

# Delete PVC (if persistence.enabled=true)
kubectl delete pvc -n database-admin pgadmin

# Delete namespace (if dedicated)
kubectl delete namespace database-admin
```

## Values Profiles

### Development (values-dev.yaml)

- Single replica
- DEBUG logging
- Weaker password requirements
- Sample local PostgreSQL server
- Minimal resources (300m CPU, 256Mi RAM)
- 500Mi storage

### Small Production (values-small-prod.yaml)

- 2 replicas for HA
- Session affinity enabled
- Multiple pre-configured servers (prod, staging)
- Network policies enabled
- PodDisruptionBudget
- Anti-affinity for node distribution
- TLS/HTTPS configured
- MFA support enabled
- Production-grade resources (1 CPU, 1Gi RAM)
- 2Gi storage

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Ingress                       │
│          (TLS, Session Affinity)                │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│              Service (ClusterIP)                │
└────────┬─────────────────────┬──────────────────┘
         │                     │
┌────────▼────────┐   ┌───────▼────────┐
│  pgAdmin Pod 1  │   │  pgAdmin Pod 2 │
│                 │   │                │
│  ┌───────────┐  │   │  ┌───────────┐ │
│  │ pgAdmin   │  │   │  │ pgAdmin   │ │
│  │ (Port 80) │  │   │  │ (Port 80) │ │
│  └─────┬─────┘  │   │  └─────┬─────┘ │
│        │        │   │        │       │
│  ┌─────▼─────┐  │   │  ┌─────▼─────┐ │
│  │ SQLite DB │  │   │  │ SQLite DB │ │
│  │ (PVC)     │  │   │  │ (PVC)     │ │
│  └───────────┘  │   │  └───────────┘ │
└─────────────────┘   └────────────────┘
         │                     │
         └──────────┬──────────┘
                    │
         ┌──────────▼──────────┐
         │  PostgreSQL Servers │
         │  (External)         │
         └─────────────────────┘
```

## License

This Helm chart is licensed under BSD-3-Clause.

pgAdmin itself is licensed under the PostgreSQL License. See: https://www.pgadmin.org/licence/

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **pgAdmin Official**: https://www.pgadmin.org/
- **Documentation**: https://www.pgadmin.org/docs/
- **pgAdmin Docker Hub**: https://hub.docker.com/r/dpage/pgadmin4

## Support

For chart-related issues:
- GitHub Issues: https://github.com/scriptonbasestar-container/sb-helm-charts/issues

For pgAdmin issues:
- pgAdmin Support: https://www.pgadmin.org/support/
- pgAdmin Mailing List: https://www.postgresql.org/list/pgadmin-support/
