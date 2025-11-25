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

## Security Considerations

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
