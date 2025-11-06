# Keycloak Helm Chart

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

## Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak GitHub](https://github.com/keycloak/keycloak)
- [Keycloak Discourse](https://keycloak.discourse.group/)

## License

This Helm chart is licensed under the BSD 3-Clause License. See the [LICENSE](../../LICENSE) file for details.

Keycloak itself is licensed under the Apache License 2.0.

## Maintainers

| Name | Email |
|------|-------|
| archmagece | archmagece@users.noreply.github.com |
