# Grafana Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 12.2.2](https://img.shields.io/badge/AppVersion-12.2.2-informational?style=flat-square)

Grafana metrics visualization and dashboarding platform for Kubernetes

## Features

- **Flexible Database**: SQLite (default) or external PostgreSQL/MySQL
- **Data Source Support**: Prometheus, Loki, and 100+ data sources
- **Persistent Storage**: PVC for dashboards and settings
- **Security**: Auto-generated passwords, non-root execution
- **Ingress Support**: External access with TLS
- **Health Probes**: Liveness and readiness checks
- **Operational Tools**: 15+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with SQLite (development)
helm install my-grafana scripton-charts/grafana

# Install with PostgreSQL (production)
helm install my-grafana scripton-charts/grafana \
  --set database.external.enabled=true \
  --set database.external.host=postgresql \
  --set database.external.password=dbpass \
  --set grafana.adminPassword=admin123
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner (for persistence)

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.adminUser` | Admin username | `admin` |
| `grafana.adminPassword` | Admin password (auto-generated if empty) | `""` |
| `database.external.enabled` | Use external database | `false` |
| `database.external.type` | Database type (postgres/mysql) | `postgres` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `10Gi` |
| `ingress.enabled` | Enable ingress | `false` |

## Operational Commands

```bash
# Get admin password
make -f make/ops/grafana.mk grafana-get-password

# Port forward
make -f make/ops/grafana.mk grafana-port-forward

# Add Prometheus data source
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus:9090

# Add Loki data source
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100

# List dashboards
make -f make/ops/grafana.mk grafana-list-dashboards

# Export dashboard
make -f make/ops/grafana.mk grafana-export-dashboard UID=dashboard-uid

# Backup database
make -f make/ops/grafana.mk grafana-db-backup
```

## Production Setup

```yaml
# values-prod.yaml
grafana:
  adminPassword: "secure-password"

database:
  external:
    enabled: true
    type: "postgres"
    host: "postgresql"
    password: "db-password"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - grafana.example.com
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com

persistence:
  storageClass: "fast-ssd"
  size: 20Gi
```

## Data Sources

### Add Prometheus

```bash
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus-server:9090
```

### Add Loki

```bash
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100
```

## Dashboard Import

Import from Grafana.com:

1. Browse https://grafana.com/grafana/dashboards/
2. Copy dashboard ID or JSON
3. Import via UI or CLI

---

## Backup & Recovery

This chart provides comprehensive backup and recovery capabilities for Grafana instances.

**Backup Strategy:**
- **Dashboards & Datasources**: Daily API exports (critical)
- **SQLite Database**: Daily file backups (critical)
- **Configuration**: ConfigMaps and Secrets backup (high priority)
- **Plugins**: Plugin list and data backup (medium priority)
- **PVC Snapshots**: Weekly VolumeSnapshots (high priority)

**Recovery Time Objectives (RTO/RPO):**
- RTO: < 1 hour for complete instance recovery
- RPO: 24 hours (daily backups recommended)
- Dashboard Recovery: < 15 minutes via API
- Database Recovery: < 30 minutes

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/grafana.mk grafana-full-backup

# Component-specific backups
make -f make/ops/grafana.mk grafana-backup-dashboards
make -f make/ops/grafana.mk grafana-backup-datasources
make -f make/ops/grafana.mk grafana-backup-db
make -f make/ops/grafana.mk grafana-backup-config
make -f make/ops/grafana.mk grafana-backup-plugins

# PVC snapshot backup (if VolumeSnapshot supported)
make -f make/ops/grafana.mk grafana-backup-snapshot
```

### Recovery Procedures

**Restore Dashboards:**
```bash
# Restore all dashboards from backup
make -f make/ops/grafana.mk grafana-restore-dashboards BACKUP_DIR=grafana-dashboards-backup-YYYYMMDD

# Restore single dashboard
make -f make/ops/grafana.mk grafana-restore-dashboard DASHBOARD_FILE=dashboard-uid.json
```

**Restore Database:**
```bash
# Restore SQLite database (requires Grafana downtime)
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD.db
```

**Restore Configuration:**
```bash
# Restore ConfigMaps and Secrets
make -f make/ops/grafana.mk grafana-restore-config BACKUP_FILE=grafana-config-backup-YYYYMMDD.yaml
make -f make/ops/grafana.mk grafana-restore-secrets BACKUP_FILE=grafana-secret-backup-YYYYMMDD.yaml
```

### Disaster Recovery

**Complete Grafana instance recovery from PVC snapshot:**

```bash
# 1. Restore PVC from VolumeSnapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data-restored
  namespace: <namespace>
spec:
  storageClassName: <storage-class>
  dataSource:
    name: grafana-data-snapshot-YYYYMMDD
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# 2. Update Helm release to use restored PVC
helm upgrade grafana charts/grafana \
  --namespace <namespace> \
  --set persistence.existingClaim=grafana-data-restored \
  --reuse-values

# 3. Verify recovery
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

**Database corruption recovery:**

```bash
# Stop Grafana, restore database, restart
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD.db
```

For comprehensive backup and recovery procedures, see [Backup Guide](../../docs/grafana-backup-guide.md).

---

## Security & RBAC

### RBAC Configuration

This chart includes Role-Based Access Control (RBAC) resources for secure operation.

**RBAC Components:**
- **ServiceAccount**: Dedicated service account for Grafana pod
- **Role**: Namespace-scoped permissions for accessing Kubernetes resources
- **RoleBinding**: Binds the Role to the ServiceAccount

**Default RBAC Configuration:**

```yaml
rbac:
  create: true  # Creates Role and RoleBinding
  annotations: {}  # Additional annotations for RBAC resources

serviceAccount:
  create: true  # Creates ServiceAccount
  annotations: {}
  name: ""  # Auto-generated if empty
```

**RBAC Permissions:**

The default Role grants the following namespace-scoped permissions:

| Resource | Verbs | Purpose |
|----------|-------|---------|
| ConfigMaps | get, list, watch | Dashboard provisioning, configuration |
| Secrets | get, list, watch | Datasource credentials, admin password |
| Pods | get, list, watch | Health checks, operations |
| Services | get, list, watch | Service discovery |
| Endpoints | get, list, watch | Service discovery |
| PersistentVolumeClaims | get, list, watch | Storage operations |

**Custom RBAC Example:**

```yaml
# values-rbac.yaml
rbac:
  create: true
  annotations:
    description: "Grafana RBAC resources"

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/grafana-role"  # For AWS IRSA
  name: "grafana-sa"
```

**Disable RBAC (not recommended):**

```yaml
rbac:
  create: false

serviceAccount:
  create: false
  name: "default"  # Use default service account
```

### Authentication

**LDAP/OAuth Integration:**
```yaml
grafana:
  extraConfig:
    auth.ldap: |
      enabled = true
      config_file = /etc/grafana/ldap.toml

    auth.generic_oauth: |
      enabled = true
      name = Keycloak
      allow_sign_up = true
      client_id = grafana
      client_secret = ${GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}
      scopes = openid email profile
      auth_url = https://keycloak.example.com/realms/master/protocol/openid-connect/auth
      token_url = https://keycloak.example.com/realms/master/protocol/openid-connect/token
      api_url = https://keycloak.example.com/realms/master/protocol/openid-connect/userinfo
```

**Disable Anonymous Access (Production):**
```yaml
grafana:
  extraConfig:
    auth.anonymous: |
      enabled = false
```

### Network Security

**Network Policy:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: grafana-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
```

### Ingress Security

**TLS with Cert-Manager:**
```yaml
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com
```

**IP Whitelist:**
```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

### Secret Management

**Use External Secrets:**
```yaml
# ExternalSecret for Grafana admin password
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana-admin-secret
  data:
    - secretKey: admin-password
      remoteRef:
        key: secret/grafana
        property: admin-password
```

### Data Source Security

**Use Credentials from Secrets:**
```yaml
grafana:
  datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus:9090
      secureJsonData:
        httpHeaderValue1: "${PROMETHEUS_TOKEN}"
```

### Security Best Practices

1. **Strong Passwords**: Use auto-generated admin password or strong custom password
2. **External Secrets**: Store sensitive data in external secret managers (Vault, AWS Secrets Manager)
3. **RBAC**: Always enable RBAC in production (`rbac.create: true`)
4. **Network Policies**: Restrict network access to Grafana pods
5. **TLS**: Enable TLS for ingress with valid certificates
6. **Regular Updates**: Keep Grafana and plugins updated
7. **Audit Logs**: Enable Grafana audit logging for compliance
8. **Disable Anonymous Access**: Require authentication for all access

---

## Operations

This chart includes 40+ operational commands for day-to-day Grafana management.

### Common Operations

**Access Grafana:**

```bash
# Get admin password
make -f make/ops/grafana.mk grafana-get-password

# Port forward to access UI
make -f make/ops/grafana.mk grafana-port-forward
# Access: http://localhost:3000

# Get Grafana URL (if ingress enabled)
make -f make/ops/grafana.mk grafana-get-url
```

**Dashboard Management:**

```bash
# List all dashboards
make -f make/ops/grafana.mk grafana-list-dashboards

# Export dashboard by UID
make -f make/ops/grafana.mk grafana-export-dashboard UID=dashboard-uid

# Export all dashboards
make -f make/ops/grafana.mk grafana-backup-dashboards

# Import dashboard from file
make -f make/ops/grafana.mk grafana-import-dashboard FILE=dashboard.json

# Delete dashboard
make -f make/ops/grafana.mk grafana-delete-dashboard UID=dashboard-uid
```

**Datasource Management:**

```bash
# List all datasources
make -f make/ops/grafana.mk grafana-list-datasources

# Add Prometheus datasource
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus:9090

# Add Loki datasource
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100

# Test datasource connectivity
make -f make/ops/grafana.mk grafana-test-datasource ID=1

# Delete datasource
make -f make/ops/grafana.mk grafana-delete-datasource ID=1
```

### Backup Operations

```bash
# Full comprehensive backup
make -f make/ops/grafana.mk grafana-full-backup

# Component backups
make -f make/ops/grafana.mk grafana-backup-dashboards
make -f make/ops/grafana.mk grafana-backup-datasources
make -f make/ops/grafana.mk grafana-backup-db
make -f make/ops/grafana.mk grafana-backup-config
make -f make/ops/grafana.mk grafana-backup-secrets
make -f make/ops/grafana.mk grafana-backup-plugins

# PVC snapshot
make -f make/ops/grafana.mk grafana-backup-snapshot
make -f make/ops/grafana.mk grafana-list-snapshots
```

### Recovery Operations

```bash
# Restore dashboards
make -f make/ops/grafana.mk grafana-restore-dashboards BACKUP_DIR=grafana-dashboards-backup-YYYYMMDD

# Restore datasources
make -f make/ops/grafana.mk grafana-restore-datasources BACKUP_DIR=grafana-datasources-backup-YYYYMMDD

# Restore database
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD.db

# Restore configuration
make -f make/ops/grafana.mk grafana-restore-config BACKUP_FILE=grafana-config-backup-YYYYMMDD.yaml
make -f make/ops/grafana.mk grafana-restore-secrets BACKUP_FILE=grafana-secret-backup-YYYYMMDD.yaml
```

### Maintenance Operations

```bash
# Check pod status
make -f make/ops/grafana.mk grafana-status

# View logs (follow mode)
make -f make/ops/grafana.mk grafana-logs

# View logs (last 100 lines)
make -f make/ops/grafana.mk grafana-logs-tail

# Shell into Grafana pod
make -f make/ops/grafana.mk grafana-shell

# Database integrity check
make -f make/ops/grafana.mk grafana-db-integrity-check

# Get Grafana version
make -f make/ops/grafana.mk grafana-version

# Restart Grafana
kubectl rollout restart deployment/grafana -n <namespace>
```

### Plugin Operations

```bash
# List installed plugins
make -f make/ops/grafana.mk grafana-list-plugins

# Install plugin
make -f make/ops/grafana.mk grafana-install-plugin PLUGIN_ID=grafana-piechart-panel

# Update all plugins
make -f make/ops/grafana.mk grafana-update-plugins

# Backup plugin list
make -f make/ops/grafana.mk grafana-backup-plugins
```

### Debugging Operations

```bash
# Check Grafana health
make -f make/ops/grafana.mk grafana-health-check

# Get Grafana metrics
make -f make/ops/grafana.mk grafana-metrics

# Describe pod
kubectl describe pod -l app.kubernetes.io/name=grafana -n <namespace>

# Check resource usage
kubectl top pod -l app.kubernetes.io/name=grafana -n <namespace>

# View events
kubectl get events -n <namespace> --field-selector involvedObject.name=grafana
```

For a complete list of operational commands, run:
```bash
make -f make/ops/grafana.mk help
```

---

## Upgrading

This chart supports multiple upgrade strategies based on the scope of the upgrade.

### Upgrade Strategies

| Strategy | Downtime | Complexity | Best For |
|----------|----------|------------|----------|
| **Rolling Upgrade** | None | Low | Patch/minor versions (10.3.0 → 10.3.1) |
| **In-Place Upgrade** | 1-5 min | Medium | Minor/major versions (10.x → 11.x) |
| **Blue-Green** | None | High | Major versions with easy rollback |
| **Database Migration** | 30-60 min | Very High | Multi-major versions (9.x → 11.x) |

### Pre-Upgrade Checklist

**CRITICAL:** Always perform these steps before upgrading:

```bash
# 1. Review Grafana release notes for breaking changes
# Visit: https://grafana.com/docs/grafana/latest/whatsnew/

# 2. Comprehensive backup (MANDATORY)
make -f make/ops/grafana.mk grafana-pre-upgrade-check
make -f make/ops/grafana.mk grafana-full-backup

# 3. Document current state
helm get values grafana -n <namespace> > grafana-values-current.yaml

# 4. Check current version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# 5. Verify plugin compatibility
kubectl exec -n <namespace> deployment/grafana -- grafana-cli plugins ls
# Check each plugin compatibility at https://grafana.com/grafana/plugins/

# 6. Test upgrade in staging (for major versions)
# ... (deploy to staging namespace first)
```

### Rolling Upgrade (Recommended for Patch/Minor Versions)

**Zero downtime upgrade for patch and minor versions (e.g., 10.3.0 → 10.3.1):**

```bash
# 1. Pre-upgrade backup
make -f make/ops/grafana.mk grafana-full-backup

# 2. Update Helm repository
helm repo update

# 3. Upgrade using Helm (rolling upgrade)
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --reuse-values \
  --wait

# 4. Monitor rollout
kubectl rollout status deployment/grafana -n <namespace>

# 5. Verify upgrade
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

### In-Place Upgrade (For Major Versions)

**Brief downtime upgrade for major versions (e.g., 10.x → 11.x):**

```bash
# 1. Pre-upgrade backup
make -f make/ops/grafana.mk grafana-full-backup

# 2. Scale down Grafana
kubectl scale deployment grafana -n <namespace> --replicas=0

# 3. Upgrade Helm release
helm upgrade grafana scripton-charts/grafana \
  --namespace <namespace> \
  --set image.tag=<new-version> \
  --reuse-values

# 4. Scale up Grafana
kubectl scale deployment grafana -n <namespace> --replicas=1

# 5. Wait for pod readiness
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n <namespace> --timeout=600s

# 6. Verify upgrade
make -f make/ops/grafana.mk grafana-post-upgrade-check
```

### Post-Upgrade Validation

```bash
# Automated validation
make -f make/ops/grafana.mk grafana-post-upgrade-check

# Manual checks:
# 1. Verify Grafana version
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v

# 2. Verify dashboards count
make -f make/ops/grafana.mk grafana-list-dashboards | wc -l

# 3. Verify datasources
make -f make/ops/grafana.mk grafana-list-datasources

# 4. Test datasource connectivity
# Access UI and verify dashboards load correctly

# 5. Check logs for errors
kubectl logs -l app.kubernetes.io/name=grafana -n <namespace> --tail=100 | grep -i error
```

### Version-Specific Upgrade Notes

**Grafana 10.x → 11.x:**
- **Breaking Change**: Angular plugin support removed
- **Action Required**: Replace Angular plugins with React alternatives
  ```bash
  # List Angular plugins
  kubectl exec deployment/grafana -- grafana-cli plugins ls | grep -i angular

  # Replace with React alternatives:
  # grafana-piechart-panel → piechart-panel-v2
  # grafana-worldmap-panel → geomap panel (built-in)
  ```
- **Upgrade Strategy**: Blue-Green deployment recommended

**Grafana 9.x → 10.x:**
- **Breaking Change**: Legacy alerting disabled by default
- **Action Required**: Migrate to unified alerting via UI (Alerting > Admin > Upgrade legacy alerts)
- **Upgrade Strategy**: Rolling upgrade acceptable

**Grafana 8.x → 9.x:**
- **Breaking Change**: Plugin signature enforcement
- **Action Required**: Verify all plugins are signed or allow unsigned plugins (not recommended)
- **Upgrade Strategy**: Rolling upgrade acceptable

### Rollback Procedures

**Quick Rollback (Helm):**

```bash
# Rollback to previous Helm revision
helm rollback grafana -n <namespace>

# Verify rollback
kubectl exec -n <namespace> deployment/grafana -- grafana-cli -v
```

**Database Restore Rollback:**

```bash
# If database migration fails, restore database
kubectl scale deployment grafana -n <namespace> --replicas=0
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD.db
helm rollback grafana -n <namespace>
kubectl scale deployment grafana -n <namespace> --replicas=1
```

### Upgrade Troubleshooting

**Issue: Pod CrashLoopBackOff after upgrade**

```bash
# Check logs for error details
kubectl logs -l app.kubernetes.io/name=grafana -n <namespace> --tail=200

# Common causes:
# - Database migration failed → Restore database
# - Configuration error → Verify ConfigMap/Secrets
# - Plugin incompatibility → Remove incompatible plugins
```

**Issue: Dashboards missing after upgrade**

```bash
# Check database contents
kubectl exec deployment/grafana -n <namespace> -- sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM dashboard;"

# If count is 0, restore database
make -f make/ops/grafana.mk grafana-restore-db BACKUP_FILE=grafana-db-backup-YYYYMMDD.db
```

**Issue: Plugin compatibility errors**

```bash
# Update plugins to compatible versions
kubectl exec deployment/grafana -n <namespace> -- grafana-cli plugins update-all

# Or remove incompatible plugins
kubectl exec deployment/grafana -n <namespace> -- grafana-cli plugins remove <plugin-id>
```

For comprehensive upgrade procedures and version-specific notes, see [Upgrade Guide](../../docs/grafana-upgrade-guide.md).

## Performance Tuning

### Database Optimization

**External PostgreSQL (Recommended for Production):**
```yaml
database:
  external:
    enabled: true
    type: postgres
    host: postgresql.database.svc.cluster.local
    port: 5432
    name: grafana
    user: grafana
    # Use connection pooling for high concurrency
```

**SQLite Tuning (Development Only):**
```yaml
grafana:
  extraConfig:
    database: |
      type = sqlite3
      cache_mode = shared
      wal = true
```

### Resource Sizing

| Users | Dashboards | Memory | CPU | Notes |
|-------|------------|--------|-----|-------|
| < 10 | < 50 | 256Mi | 100m | Development |
| 10-50 | 50-200 | 512Mi | 250m | Small team |
| 50-200 | 200-500 | 1Gi | 500m | Medium deployment |
| 200+ | 500+ | 2Gi | 1000m | Large deployment |

**Production Resources:**
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 512Mi
```

### Caching

**Enable Query Caching:**
```yaml
grafana:
  extraConfig:
    caching: |
      enabled = true
      backend = redis

    caching.redis: |
      url = redis://redis:6379/0
```

**Dashboard Caching:**
```yaml
grafana:
  extraConfig:
    dashboards: |
      versions_to_keep = 20
      min_refresh_interval = 5s
```

### Rendering Performance

**Remote Rendering (for PDF/PNG export):**
```yaml
grafana:
  extraConfig:
    rendering: |
      server_url = http://grafana-image-renderer:8081/render
      callback_url = http://grafana:3000/
```

**Disable Unused Features:**
```yaml
grafana:
  extraConfig:
    explore: |
      enabled = false  # If not using Explore

    alerting: |
      enabled = false  # If using external alerting
```

### High Availability

**Session Affinity for HA:**
```yaml
replicaCount: 2

service:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800

# Use external database for session storage
database:
  external:
    enabled: true
```

**Redis for HA Caching:**
```yaml
grafana:
  extraConfig:
    remote_cache: |
      type = redis
      connstr = addr=redis:6379,pool_size=100
```

## Troubleshooting

### Check Pod Status

```bash
# Pod status
kubectl get pods -l app.kubernetes.io/name=grafana

# Logs
kubectl logs -l app.kubernetes.io/name=grafana -f

# Describe pod
kubectl describe pod -l app.kubernetes.io/name=grafana
```

### Common Issues

1. **Login fails**: Check admin password secret, verify database connectivity
2. **Dashboard not loading**: Check data source connectivity, increase query timeout
3. **High memory usage**: Reduce dashboard complexity, enable query caching
4. **Slow startup**: Use external database, reduce provisioned dashboards

### Health Check

```bash
# Readiness check
kubectl exec -n monitoring grafana-0 -- curl -s http://localhost:3000/api/health

# Get version
kubectl exec -n monitoring grafana-0 -- curl -s http://localhost:3000/api/health | jq '.version'
```

## License

- Chart: BSD 3-Clause License
- Grafana: Apache License 2.0

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Dashboard Gallery](https://grafana.com/grafana/dashboards/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**Grafana Version**: 10.2.3
