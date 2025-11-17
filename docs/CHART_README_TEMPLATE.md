# {CHART_NAME}

<!-- Badges -->
[![Chart Version](https://img.shields.io/badge/chart-{VERSION}-blue.svg)](https://github.com/scriptonbasestar-container/sb-helm-charts)
[![App Version](https://img.shields.io/badge/app-{APP_VERSION}-green.svg)]({APP_URL})
[![License](https://img.shields.io/badge/license-BSD--3--Clause-orange.svg)](https://opensource.org/licenses/BSD-3-Clause)

{BRIEF_DESCRIPTION}

## TL;DR

```bash
# Add Helm repository
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# Install chart with default values
helm install {chart-name} sb-charts/{chart-name}

# Install with custom values
helm install {chart-name} sb-charts/{chart-name} -f values.yaml
```

## Introduction

This chart bootstraps a {APPLICATION_NAME} deployment on a Kubernetes cluster using the Helm package manager.

**Key Features:**
- ✅ {FEATURE_1}
- ✅ {FEATURE_2}
- ✅ {FEATURE_3}
- ✅ Configuration-first approach (uses native config files)
- ✅ External database support (PostgreSQL/MySQL/Redis)
- ✅ Production-ready with HA support

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- {ADDITIONAL_PREREQUISITES}

### External Dependencies

This chart requires external services:

- **Database**: {DATABASE_TYPE} {VERSION}+ (required)
- **Cache**: {CACHE_TYPE} {VERSION}+ (optional)

See the [Database Strategy](#database-strategy) section for setup instructions.

## Installing the Chart

### Quick Start

```bash
# Install with default values (not recommended for production)
helm install my-{chart-name} sb-charts/{chart-name}
```

### Deployment Scenarios

This chart includes pre-configured values for three deployment scenarios:

#### Home Server / Personal Use

```bash
helm install my-{chart-name} sb-charts/{chart-name} \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/{chart-name}/values-home-single.yaml \
  --set postgresql.external.password=your-secure-password
```

**Resources**: 50-500m CPU, 128Mi-512Mi RAM

#### Startup / Small Team

```bash
helm install my-{chart-name} sb-charts/{chart-name} \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/{chart-name}/values-startup-single.yaml \
  --set postgresql.external.password=your-secure-password
```

**Resources**: 100m-1000m CPU, 256Mi-1Gi RAM

#### Production / High Availability

```bash
helm install my-{chart-name} sb-charts/{chart-name} \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/{chart-name}/values-prod-master-replica.yaml \
  --set postgresql.external.password=your-secure-password
```

**Resources**: 250m-2000m CPU, 512Mi-2Gi RAM, HA with multiple replicas

See [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md) for detailed specifications.

## Configuration

### Database Strategy

This chart follows an **external database** pattern - databases are NOT included as subcharts.

#### Setup External PostgreSQL

```bash
# Install PostgreSQL separately
helm install postgres bitnami/postgresql \
  --set auth.database={chart-name} \
  --set auth.username={chart-name} \
  --set auth.password=secure-password

# Configure chart to use external database
helm install my-{chart-name} sb-charts/{chart-name} \
  --set postgresql.external.enabled=true \
  --set postgresql.external.host=postgres-postgresql.default.svc.cluster.local \
  --set postgresql.external.port=5432 \
  --set postgresql.external.database={chart-name} \
  --set postgresql.external.username={chart-name} \
  --set postgresql.external.password=secure-password
```

### Common Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `{IMAGE_REPO}` |
| `image.tag` | Image tag (overrides appVersion) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `postgresql.external.enabled` | Enable external PostgreSQL | `false` |
| `postgresql.external.host` | PostgreSQL host | `""` |
| `postgresql.external.password` | PostgreSQL password | `""` (required) |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | Storage size | `{DEFAULT_SIZE}` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.hosts` | Ingress hosts | `[]` |

See [values.yaml](values.yaml) for all available options.

### Using Configuration Files

This chart uses native configuration files instead of environment variables:

```yaml
{chart-name}:
  config: |
    # Native {APPLICATION_NAME} configuration
    {SAMPLE_CONFIG}
```

## Persistence

The chart mounts a Persistent Volume at `{MOUNT_PATH}`. The volume is created using dynamic volume provisioning.

**PVC Configuration:**

```yaml
persistence:
  enabled: true
  storageClass: ""  # Use cluster default
  accessMode: ReadWriteOnce
  size: {DEFAULT_SIZE}
  annotations: {}
```

## Networking

### Service Configuration

```yaml
service:
  type: ClusterIP
  port: {SERVICE_PORT}
```

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: {chart-name}.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: {chart-name}-tls
      hosts:
        - {chart-name}.example.com
```

## Security

### Network Policies

Enable network policies to restrict traffic:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
```

### Pod Security

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

## High Availability

### Horizontal Pod Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

## Monitoring

### Prometheus Metrics

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  path: /metrics
```

## Upgrading

### From 0.1.x to 0.2.x

```bash
# Backup your data first
kubectl exec -it {chart-name}-0 -- backup-command

# Upgrade chart
helm upgrade my-{chart-name} sb-charts/{chart-name} \
  --reuse-values \
  --set image.tag={NEW_VERSION}

# Verify upgrade
kubectl rollout status deployment/{chart-name}
```

See [CHANGELOG.md](../../CHANGELOG.md) for version-specific upgrade notes.

## Uninstalling the Chart

```bash
# Uninstall release
helm uninstall my-{chart-name}

# Delete PVC (optional - data will be lost!)
kubectl delete pvc data-my-{chart-name}-0
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name={chart-name}

# View pod logs
kubectl logs -l app.kubernetes.io/name={chart-name}

# Describe pod for events
kubectl describe pod {chart-name}-0
```

### Database Connection Issues

```bash
# Test database connectivity
kubectl run -it --rm debug --image=postgres:alpine --restart=Never -- \
  psql -h postgres-postgresql -U {chart-name} -d {chart-name}

# Check database secret
kubectl get secret {chart-name}-db -o yaml
```

### Common Issues

1. **PVC not binding**: Check storage class availability
2. **Database connection failed**: Verify external database credentials
3. **Image pull errors**: Check image repository and credentials

## Development

### Local Testing

```bash
# Render templates locally
helm template my-{chart-name} ./charts/{chart-name} -f values.yaml

# Lint chart
helm lint ./charts/{chart-name}

# Install in local cluster (kind/minikube)
helm install my-{chart-name} ./charts/{chart-name} --dry-run --debug
```

## Contributing

Contributions are welcome! Please see our [Contributing Guide](../../.github/CONTRIBUTING.md) for details.

## License

This Helm chart is licensed under the BSD 3-Clause License.

**Note**: The {APPLICATION_NAME} application itself may be licensed differently. See the [official documentation]({APP_URL}) for details.

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Application Homepage**: {APP_URL}
- **Application Documentation**: {DOCS_URL}
- **Chart Development Guide**: [docs/CHART_DEVELOPMENT_GUIDE.md](../../docs/CHART_DEVELOPMENT_GUIDE.md)
- **Scenario Values Guide**: [docs/SCENARIO_VALUES_GUIDE.md](../../docs/SCENARIO_VALUES_GUIDE.md)

---

**Maintained by**: [ScriptonBasestar](https://github.com/scriptonbasestar-container)
