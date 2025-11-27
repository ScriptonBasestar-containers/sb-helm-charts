# Keycloak Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/keycloak)

[Keycloak](https://www.keycloak.org/) is an open-source Identity and Access Management solution for modern applications and services.

## Features

- ✅ StatefulSet-based deployment for stable identity
- ✅ External PostgreSQL database support (required)
- ✅ Optional Redis for distributed caching
- ✅ High availability with clustering (JGroups + Infinispan)
- ✅ Realm import/export functionality
- ✅ Separate admin console access
- ✅ Prometheus metrics support
- ✅ Horizontal Pod Autoscaling
- ✅ Pod Disruption Budget for HA
- ✅ Network Policy for enhanced security
- ✅ Database health check (InitContainer)
- ✅ Customizable themes and extensions
- ✅ TLS/SSL support

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install keycloak-home charts/keycloak \
  -f charts/keycloak/values-home-single.yaml \
  --set keycloak.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install keycloak-startup charts/keycloak \
  -f charts/keycloak/values-startup-single.yaml \
  --set keycloak.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with clustering and monitoring:

```bash
helm install keycloak-prod charts/keycloak \
  -f charts/keycloak/values-prod-master-replica.yaml \
  --set keycloak.admin.password=your-secure-password \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local \
  --set redis.external.password=your-redis-password
```

**Features:** 3 replicas, JGroups clustering, pod anti-affinity, HPA, PodDisruptionBudget, NetworkPolicy, ServiceMonitor

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 20Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#keycloak).


- Kubernetes 1.19+
- Helm 3.2.0+
- **External PostgreSQL 13+ database** (required for Keycloak 26.x)
- PersistentVolume provisioner support in the underlying infrastructure

## Version Information

This chart is configured for **Keycloak 26.x** which includes significant changes from previous versions:

- **Hostname v2**: The old hostname v1 configuration has been completely removed. You must use the new hostname v2 format.
- **PostgreSQL 13+**: Minimum PostgreSQL version requirement has been increased from 12.x to 13.x.
- **CLI-based clustering**: JGroups network configuration now uses CLI options instead of environment variables.
- **OpenJDK 21**: While OpenJDK 17 is still supported, it's deprecated and will be removed in future releases.

## Installation

### 1. Prepare External PostgreSQL

This chart **does not** install PostgreSQL automatically. You must have a PostgreSQL database ready.

```bash
# Example: Create a database and user in your PostgreSQL
CREATE DATABASE keycloak;
CREATE USER keycloak WITH ENCRYPTED PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
```

### 2. Create values file

Create a `my-values.yaml` file:

```yaml
keycloak:
  admin:
    username: admin
    password: "change-me-secure-password"

postgresql:
  enabled: false
  external:
    enabled: true
    host: "postgres.database.svc.cluster.local"
    port: 5432
    database: "keycloak"
    username: "keycloak"
    password: "your-db-password"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: keycloak.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: keycloak-tls
      hosts:
        - keycloak.example.com
```

### 3. Install the chart

```bash
helm install my-keycloak ./charts/keycloak -f my-values.yaml
```

Or using Helm repository:

```bash
helm repo add sb-helm-charts https://scriptonbasestar-docker.github.io/sb-helm-charts/
helm repo update
helm install my-keycloak sb-helm-charts/keycloak -f my-values.yaml
```

## Configuration

See [values.yaml](./values.yaml) for all available options.

### Essential Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `keycloak.admin.username` | Admin username | `admin` |
| `keycloak.admin.password` | Admin password (required) | `""` |
| `postgresql.external.enabled` | Enable external PostgreSQL | `true` |
| `postgresql.external.host` | PostgreSQL host | `""` |
| `postgresql.external.database` | Database name | `keycloak` |
| `postgresql.external.username` | Database username | `keycloak` |
| `postgresql.external.password` | Database password (required) | `""` |

### Redis Configuration (Optional)

For distributed caching with Infinispan remote cache store:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `redis.enabled` | Enable Redis integration | `false` |
| `redis.external.enabled` | Use external Redis | `false` |
| `redis.external.host` | Redis hostname | `""` |
| `redis.external.port` | Redis port | `6379` |
| `redis.external.password` | Redis password | `""` |
| `redis.external.database` | Redis database number | `0` |
| `redis.external.ssl.enabled` | Enable SSL/TLS connection | `false` |
| `redis.external.ssl.certificateSecret` | Secret containing certificates | `""` |
| `redis.external.ssl.caCertKey` | CA certificate key in secret | `ca.crt` |
| `redis.external.ssl.clientCertKey` | Client cert key (mTLS) | `""` |
| `redis.external.ssl.clientKeyKey` | Client key (mTLS) | `""` |

See [Redis SSL Connection](#redis-ssl-connection) section for detailed configuration examples.

### Hostname Configuration (v2)

**Important**: Keycloak 26.x uses hostname v2 configuration. The old v1 format is no longer supported.

```yaml
keycloak:
  hostname:
    # KC_HOSTNAME - Full hostname or domain (without protocol for domain-only)
    hostname: "keycloak.example.com"
    # KC_HOSTNAME_ADMIN - Separate admin console hostname (optional)
    hostnameAdmin: "admin.keycloak.example.com"
    # KC_HOSTNAME_STRICT - Enforce strict hostname checking
    hostnameStrict: true
    # KC_HOSTNAME_BACKCHANNEL_DYNAMIC - Allow dynamic backchannel URLs
    hostnameBackchannelDynamic: false
```

**Migration from v1 to v2:**

| Old (v1) | New (v2) |
|----------|----------|
| `hostname.url` | `hostname.hostname` |
| `hostname.adminUrl` | `hostname.hostnameAdmin` |
| `hostname.strict` | `hostname.hostnameStrict` |
| `hostname.strictBackchannel` | Removed (use `hostnameBackchannelDynamic` instead) |

### High Availability Setup

For production deployments with multiple replicas:

```yaml
replicaCount: 3

clustering:
  enabled: true
  cache:
    ownersCount: 2
    stack: "tcp"
  # Network binding (Keycloak 26.x uses CLI options)
  network:
    bindAddress: "0.0.0.0"
    bindPort: 7800
  # JGroups discovery (backward compatibility)
  jgroups:
    discoveryProtocol: "dns.DNS_PING"

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
                  - keycloak
          topologyKey: kubernetes.io/hostname

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 75
```

### Realm Import

To import realms on startup:

1. Create a ConfigMap with realm JSON files:

```bash
kubectl create configmap keycloak-realms \
  --from-file=myrealm-realm.json
```

2. Configure values:

```yaml
keycloak:
  args:
    - "start"
    - "--optimized"
    - "--import-realm"

  realmImport:
    enabled: true
    configMapName: "keycloak-realms"
```

### Extensions (Providers)

The chart supports automatic downloading of Keycloak extensions (providers) via InitContainer.

**Prerequisites:**
- Persistence must be enabled (`persistence.data.enabled: true`)
- Extension JAR files must be publicly accessible URLs

**Basic usage:**

```yaml
keycloak:
  extensions:
    enabled: true
    downloads:
      - url: "https://github.com/aerogear/keycloak-metrics-spi/releases/download/2.5.3/keycloak-metrics-spi-2.5.3.jar"
      - url: "https://github.com/wadahiro/keycloak-discord/releases/download/v0.4.0/keycloak-discord-0.4.0.jar"

persistence:
  data:
    enabled: true  # Required for extensions
```

**With checksum verification:**

```yaml
keycloak:
  extensions:
    enabled: true
    downloads:
      - url: "https://example.com/my-extension.jar"
        sha256: "abc123def456..."  # Verifies file integrity
```

**How it works:**

1. InitContainer downloads extension JARs from specified URLs
2. Files are saved to `/opt/keycloak/providers/` (persisted via PVC)
3. Keycloak container starts and automatically loads the extensions

**Note:** Extensions are downloaded only when the pod starts. To update extensions:
1. Change the URL or version in `values.yaml`
2. Delete the pod: `kubectl delete pod keycloak-0`
3. StatefulSet will recreate the pod with new extensions

### Custom Themes

Mount custom themes using extraVolumes:

```yaml
extraVolumes:
  - name: custom-themes
    configMap:
      name: keycloak-custom-themes

extraVolumeMounts:
  - name: custom-themes
    mountPath: /opt/keycloak/themes/custom
    readOnly: true
```

### Monitoring with Prometheus

Enable metrics and ServiceMonitor:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    labels:
      prometheus: kube-prometheus
```

### Separate Admin Console

For security, expose admin console on a separate domain:

```yaml
adminService:
  enabled: true

adminIngress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
  hosts:
    - host: keycloak-admin.example.com
      paths:
        - path: /admin
          pathType: Prefix
  tls:
    - secretName: keycloak-admin-tls
      hosts:
        - keycloak-admin.example.com
```

### Pod Disruption Budget

For high availability, enable PodDisruptionBudget:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 2  # Keep at least 2 pods running during disruptions
```

### Network Policy

For enhanced security, enable NetworkPolicy:

```yaml
networkPolicy:
  enabled: true
  ingress:
    namespaceSelector:
      matchLabels:
        name: ingress-nginx
  egress:
    postgresql:
      podSelector:
        matchLabels:
          app: postgresql
```

### Database Health Check

The chart includes an InitContainer that waits for PostgreSQL to be ready before starting Keycloak. This is enabled by default:

```yaml
dbHealthCheck:
  enabled: true  # default
  image: postgres:16-alpine
```

### SSL/TLS Configuration

The chart supports SSL/TLS connections for PostgreSQL, Redis, and Keycloak HTTPS.

#### PostgreSQL SSL Connection

Enable SSL connection to PostgreSQL:

```yaml
postgresql:
  external:
    host: "postgres.example.com"
    # ... other database settings
    ssl:
      enabled: true
      mode: "verify-full"  # Options: disable, allow, prefer, require, verify-ca, verify-full
      certificateSecret: "postgres-ssl-certs"
      rootCertKey: "ca.crt"
      clientCertKey: "tls.crt"  # Optional for mutual TLS
      clientKeyKey: "tls.key"   # Optional for mutual TLS
```

Create the certificate secret:

```bash
kubectl create secret generic postgres-ssl-certs \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./client.crt \
  --from-file=tls.key=./client.key
```

**SSL Modes:**

The chart automatically generates the correct PostgreSQL JDBC URL based on the SSL mode:

- `disable`: No SSL connection
  - Generated JDBC URL: `jdbc:postgresql://host:port/database`

- `require`: SSL without certificate validation (uses `NonValidatingFactory`)
  - Generated JDBC URL: `jdbc:postgresql://host:port/database?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory`
  - **Use case**: Encrypted connection when you trust the network but don't have CA certificates

- `verify-ca`: Verify CA certificate (requires `certificateSecret`)
  - Generated JDBC URL: `jdbc:postgresql://host:port/database?ssl=true&sslmode=verify-ca&sslrootcert=/opt/keycloak/conf/db-ssl/ca.crt`
  - **Use case**: Ensure the server has a valid certificate from a trusted CA

- `verify-full`: Verify CA + hostname match (requires `certificateSecret`, most secure)
  - Generated JDBC URL: `jdbc:postgresql://host:port/database?ssl=true&sslmode=verify-full&sslrootcert=/opt/keycloak/conf/db-ssl/ca.crt`
  - **Use case**: Full verification including hostname validation (recommended for production)

**Important Notes:**
- PostgreSQL JDBC driver parameters differ from `psql` CLI parameters
- The chart uses `ssl=true&sslfactory=...` for basic SSL instead of just `sslmode`
- If `certificateSecret` is not provided for `verify-ca`/`verify-full` modes, the chart falls back to `NonValidatingFactory`

#### Redis SSL Connection

For distributed caching with SSL-enabled Redis:

```yaml
redis:
  enabled: true
  external:
    enabled: true
    host: "redis.example.com"
    port: 6379
    password: "secure-password"
    database: 0
    ssl:
      enabled: true
      certificateSecret: "redis-ssl-certs"
      caCertKey: "ca.crt"
      # Optional: for mutual TLS (mTLS)
      clientCertKey: "client.crt"
      clientKeyKey: "client.key"
```

Create the certificate secret:

```bash
# CA certificate only
kubectl create secret generic redis-ssl-certs \
  --from-file=ca.crt=./redis-ca.crt

# With client certificates (mTLS)
kubectl create secret generic redis-ssl-certs \
  --from-file=ca.crt=./redis-ca.crt \
  --from-file=client.crt=./redis-client.crt \
  --from-file=client.key=./redis-client.key
```

**Environment Variables Generated:**
- `KC_CACHE_REMOTE_TLS_ENABLED=true`
- `KC_CACHE_REMOTE_TLS_TRUST_STORE_FILE=/opt/keycloak/certs/redis/ca.crt`

**Certificate Mount:**
- Certificates are mounted at `/opt/keycloak/certs/redis/`
- Keycloak Infinispan uses these certificates for remote cache SSL connection

#### Keycloak HTTPS (Direct TLS Termination)

**Note**: For production, it's recommended to terminate TLS at the Ingress level. However, if you need Keycloak to handle TLS directly:

```yaml
keycloak:
  https:
    enabled: true
    port: 8443
    certificateSecret: "keycloak-tls-certs"
    certificateKey: "tls.crt"
    privateKeyKey: "tls.key"
  proxy:
    mode: "passthrough"  # or "reencrypt"
```

Create the certificate secret:

```bash
kubectl create secret tls keycloak-tls-certs \
  --cert=./keycloak.crt \
  --key=./keycloak.key
```

#### Advanced: Custom JDBC URL

If you need to override the auto-generated JDBC URL with custom parameters:

```yaml
extraEnv:
  - name: KC_DB_URL
    value: "jdbc:postgresql://postgres.example.com:5432/keycloak?ssl=true&sslmode=verify-full&sslrootcert=/opt/keycloak/conf/db-ssl/ca.crt&ApplicationName=keycloak-prod&options=-c%20statement_timeout=30000"
```

Or load from a secret:

```yaml
extraEnv:
  - name: KC_DB_URL
    valueFrom:
      secretKeyRef:
        name: custom-db-config
        key: jdbc-url
```

**Important**:
- Environment variables defined in `extraEnv` are appended **after** auto-generated variables
- In Kubernetes, when the same environment variable is defined multiple times, the **first definition** takes precedence
- To override `KC_DB_URL`, you need to prevent the chart from generating it (set `postgresql.external.enabled: false` and manually configure all database settings)
- Alternatively, use the chart's SSL configuration which generates the correct JDBC URL automatically

## Upgrading

### To 0.2.0

No breaking changes.

## Uninstalling

```bash
helm uninstall my-keycloak
```

Note: PersistentVolumeClaims are not deleted automatically. Delete them manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=my-keycloak
```

## Common Issues

### Keycloak not starting

1. Check database connection:
   ```bash
   kubectl logs -l app.kubernetes.io/name=keycloak
   ```

2. Verify PostgreSQL credentials:
   ```bash
   kubectl get secret my-keycloak -o yaml
   ```

### Clustering not working

1. Ensure headless service is created:
   ```bash
   kubectl get svc my-keycloak-headless
   ```

2. Check JGroups discovery:
   ```bash
   kubectl logs -l app.kubernetes.io/name=keycloak | grep -i jgroups
   ```

### Realm import failed

1. Verify ConfigMap exists:
   ```bash
   kubectl get configmap keycloak-realms
   ```

2. Check file format (must be `*-realm.json`):
   ```bash
   kubectl describe configmap keycloak-realms
   ```

## Backup & Recovery Strategy

This chart follows a **Makefile-driven backup approach** (no CronJob in chart) for maximum flexibility and control.

### Backup Strategy

The recommended backup strategy combines two approaches for data consistency:

1. **Realm exports** - Keycloak configuration, clients, roles, users
2. **Database dumps** - PostgreSQL database backup

### Backup Operations

**Backup all realms:**
```bash
make -f make/ops/keycloak.mk kc-backup-all-realms
# Saves to: tmp/keycloak-backups/<timestamp>/
```

**Backup PostgreSQL database:**
```bash
make -f make/ops/keycloak.mk kc-db-backup
# Saves to: tmp/keycloak-backups/db/keycloak-db-<timestamp>.sql
```

**Verify backup integrity:**
```bash
make -f make/ops/keycloak.mk kc-backup-verify DIR=tmp/keycloak-backups/<timestamp>
```

**Export single realm for migration:**
```bash
make -f make/ops/keycloak.mk kc-realm-migrate REALM=master
# Saves to: tmp/keycloak-backups/migration/<realm>-<timestamp>.json
```

### Recovery Operations

**Restore realms from backup:**
```bash
make -f make/ops/keycloak.mk kc-backup-restore FILE=tmp/keycloak-backups/<timestamp>
```

**Restore database:**
```bash
make -f make/ops/keycloak.mk kc-db-restore FILE=tmp/keycloak-backups/db/keycloak-db-<timestamp>.sql
```

For detailed backup/restore procedures, see [docs/keycloak-backup-guide.md](../../docs/keycloak-backup-guide.md).

---

## Security & RBAC

### RBAC Configuration

This chart creates minimal namespace-scoped RBAC permissions for Keycloak pods:

```yaml
rbac:
  create: true  # Create Role and RoleBinding
  annotations: {}
```

**Default permissions:**
- Read ConfigMaps (configuration access)
- Read Secrets (credentials access)
- Read Pods (service discovery for clustering)
- Read Endpoints (clustering, when enabled)

**Disable RBAC:**
```yaml
rbac:
  create: false
```

### Security Enhancements

**Seccomp Profile (Kubernetes 1.19+):**
```yaml
podSecurityContext:
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

**Security Context:**
```yaml
securityContext:
  runAsUser: 1000
  runAsNonRoot: true
  readOnlyRootFilesystem: false
  capabilities:
    drop:
      - ALL
```

**Network Policy:**
- Enabled by default in production scenarios
- Restricts ingress/egress traffic
- Allows PostgreSQL, Redis, and DNS connections

---

## Operations & Maintenance

### Upgrade Operations

**Pre-upgrade health check:**
```bash
make -f make/ops/keycloak.mk kc-pre-upgrade-check
```

**Recommended upgrade workflow:**
```bash
# 1. Pre-upgrade check
make -f make/ops/keycloak.mk kc-pre-upgrade-check

# 2. Backup (critical!)
make -f make/ops/keycloak.mk kc-backup-all-realms
make -f make/ops/keycloak.mk kc-db-backup

# 3. Upgrade Helm chart
helm upgrade keycloak charts/keycloak -f values.yaml

# 4. Post-upgrade validation
make -f make/ops/keycloak.mk kc-post-upgrade-check

# 5. Rollback plan (if needed)
make -f make/ops/keycloak.mk kc-upgrade-rollback-plan
```

**Post-upgrade validation:**
```bash
make -f make/ops/keycloak.mk kc-post-upgrade-check
```

### Monitoring Health

**Health endpoints (Keycloak 26.x):**
- `/health/live` - Liveness probe (port 9000)
- `/health/ready` - Readiness probe (port 9000)
- `/health/started` - Startup probe (port 9000)

**Check health:**
```bash
make -f make/ops/keycloak.mk kc-health
```

**Check metrics:**
```bash
make -f make/ops/keycloak.mk kc-metrics
```

**Check cluster status:**
```bash
make -f make/ops/keycloak.mk kc-cluster-status
```

### Common Operations

**List all realms:**
```bash
make -f make/ops/keycloak.mk kc-list-realms
```

**Import realm from file:**
```bash
make -f make/ops/keycloak.mk kc-import-realm FILE=path/to/realm.json
```

**Open shell in Keycloak pod:**
```bash
make -f make/ops/keycloak.mk kc-pod-shell
```

**Test database connectivity:**
```bash
make -f make/ops/keycloak.mk kc-db-test
```

For comprehensive operations guide, see [docs/keycloak-backup-guide.md](../../docs/keycloak-backup-guide.md).

---

## Upgrade Guide (Keycloak 26.x)

### Breaking Changes in Keycloak 26.x

**Important:** Keycloak 26.x introduces significant breaking changes. Review before upgrading.

1. **Hostname v1 Removed**
   - Old `KC_HOSTNAME` environment variable no longer supported
   - Must use hostname v2 configuration
   - Update your values.yaml accordingly

2. **Health Endpoints Moved**
   - Health endpoints moved from port 8080 to port 9000 (management port)
   - Update your health check configurations:
     - Liveness: `http://localhost:9000/health/live`
     - Readiness: `http://localhost:9000/health/ready`

3. **PostgreSQL 13+ Required**
   - Minimum PostgreSQL version increased from 12.x to 13.x
   - Upgrade your PostgreSQL database before upgrading Keycloak

4. **CLI-Based Clustering**
   - JGroups configuration now uses `--cache-embedded-network-*` CLI options
   - Environment variables for clustering deprecated

For detailed upgrade procedures and version-specific breaking changes, see [docs/keycloak-upgrade-guide.md](../../docs/keycloak-upgrade-guide.md).

---

## Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak GitHub](https://github.com/keycloak/keycloak)
- [Keycloak Discourse](https://keycloak.discourse.group/)

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

This Helm chart is licensed under the BSD 3-Clause License. See the [LICENSE](../../LICENSE) file for details.

Keycloak itself is licensed under the Apache License 2.0.

## Maintainers

| Name | Email |
|------|-------|
| archmagece | archmagece@users.noreply.github.com |
