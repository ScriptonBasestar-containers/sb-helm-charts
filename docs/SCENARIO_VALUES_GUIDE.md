# Scenario Values Guide

This guide explains how to use the scenario-specific values files provided with each chart for different deployment environments.

> **See Also**: [Chart Catalog](CHARTS.md) - Browse all available charts to see which ones support these scenario values.

## Overview

All charts in this repository include pre-configured values files for three deployment scenarios:

- **Home Server** (`values-home-single.yaml`): Minimal resources for personal/home lab use
- **Startup** (`values-startup-single.yaml`): Balanced configuration for small teams
- **Production** (`values-prod-master-replica.yaml`): High availability deployment

## Quick Start

### Using Scenario Values

Instead of customizing `values.yaml` manually, use the appropriate scenario file for your environment:

```bash
# Home Server deployment
helm install myapp ./charts/nextcloud -f charts/nextcloud/values-home-single.yaml

# Startup deployment
helm install myapp ./charts/nextcloud -f charts/nextcloud/values-startup-single.yaml

# Production deployment
helm install myapp ./charts/nextcloud -f charts/nextcloud/values-prod-master-replica.yaml
```

### Overriding Scenario Values

You can override specific values on top of a scenario file:

```bash
helm install myapp ./charts/nextcloud \
  -f charts/nextcloud/values-home-single.yaml \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=nextcloud.mydomain.com
```

Or use multiple values files:

```bash
helm install myapp ./charts/nextcloud \
  -f charts/nextcloud/values-home-single.yaml \
  -f my-custom-values.yaml
```

## Scenario Characteristics

### Home Server (values-home-single.yaml)

**Target Environment:**
- Personal use, home lab, development
- Single user or small family
- Cost-conscious deployment

**Characteristics:**
- Minimal resource allocation (CPU/memory)
- Single replica (no HA)
- Smaller persistent storage
- No autoscaling
- No pod disruption budgets
- Network policies disabled
- Monitoring disabled by default

**Example Resource Allocation:**
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**When to Use:**
- Running on Raspberry Pi, Intel NUC, or home server
- Learning and experimentation
- Personal productivity tools
- Non-critical workloads

### Startup (values-startup-single.yaml)

**Target Environment:**
- Small team (5-20 users)
- Development/staging environments
- Cost-optimized production

**Characteristics:**
- Balanced resource allocation
- Single replica (limited HA)
- Medium persistent storage
- No autoscaling (manual scaling)
- Optional monitoring
- Network policies optional

**Example Resource Allocation:**
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 256Mi
```

**When to Use:**
- Small team deployments
- Development/staging environments
- Budget-conscious production
- Services with moderate load

### Production (values-prod-master-replica.yaml)

**Target Environment:**
- Production workloads
- Business-critical applications
- High availability requirements

**Characteristics:**
- High resource allocation
- Multiple replicas (2-3+)
- Large persistent storage (often ReadWriteMany)
- Autoscaling enabled
- Pod disruption budgets
- Network policies enabled
- Monitoring/ServiceMonitor enabled
- Pod anti-affinity for HA
- Ingress with TLS

**Example Resource Allocation:**
```yaml
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi

replicaCount: 3

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

**When to Use:**
- Production deployments
- Business-critical services
- High availability requirements
- Compliance/security requirements

## Charts with Scenario Values

All 16 charts in this repository include scenario values files:

### Infrastructure Charts
- **redis**: Includes 5 scenarios (home, startup, prod-master-replica, prod-sentinel, prod-cluster)
- **memcached**: Standard 3 scenarios
- **rabbitmq**: Standard 3 scenarios

### Application Charts
- **keycloak**: IAM with clustering support
- **nextcloud**: File hosting platform
- **wordpress**: CMS platform
- **paperless-ngx**: Document management
- **uptime-kuma**: Monitoring tool
- **wireguard**: VPN solution
- **browserless-chrome**: Headless browser
- **devpi**: Python package index
- **immich**: Photo/video management
- **jellyfin**: Media server
- **vaultwarden**: Password manager
- **rustfs**: S3-compatible storage
- **rsshub**: RSS feed aggregator

## Configuration Requirements

### Common Required Values

Most charts require these values to be set regardless of scenario:

**Database Charts (Keycloak, Nextcloud, WordPress, etc.):**
```bash
--set postgresql.external.host=postgres-host \
--set postgresql.external.password=secure-password
```

**Password-Protected Charts (Vaultwarden, RustFS, etc.):**
```bash
--set vaultwarden.admin.token=secure-token
# or
--set rustfs.rootPassword=secure-password
```

**Domain/Ingress Configuration:**
```bash
--set ingress.enabled=true \
--set ingress.hosts[0].host=myapp.example.com \
--set ingress.tls[0].secretName=myapp-tls \
--set ingress.tls[0].hosts[0]=myapp.example.com
```

### Redis Cache Configuration

Charts using Redis (RSSHub, Nextcloud, etc.):

```bash
--set redis.external.host=redis-host \
--set redis.external.port=6379
```

## Scenario Testing

All scenario values files have been validated with:

```bash
# Lint validation
helm lint charts/CHART_NAME -f charts/CHART_NAME/values-SCENARIO.yaml

# Template validation
helm template RELEASE_NAME charts/CHART_NAME \
  -f charts/CHART_NAME/values-SCENARIO.yaml \
  --validate
```

## Migration Between Scenarios

### Home → Startup

1. Update storage class if needed
2. Increase resource limits gradually
3. Enable monitoring if desired

```bash
helm upgrade myapp ./charts/nextcloud \
  -f charts/nextcloud/values-startup-single.yaml \
  --reuse-values
```

### Startup → Production

1. **IMPORTANT**: Change storage `accessMode` to `ReadWriteMany` if scaling horizontally
2. Enable autoscaling
3. Configure pod disruption budgets
4. Enable network policies
5. Configure monitoring/alerts
6. Set up TLS/ingress

```bash
helm upgrade myapp ./charts/nextcloud \
  -f charts/nextcloud/values-prod-master-replica.yaml \
  --set persistence.accessMode=ReadWriteMany
```

## Best Practices

1. **Start Small**: Begin with home/startup scenario and scale up as needed
2. **Test Upgrades**: Always test scenario changes in development first
3. **Review Defaults**: Check scenario files for required values before deployment
4. **Custom Values**: Use custom values files on top of scenarios for environment-specific settings
5. **Version Pin**: Lock chart versions in production
6. **Backup First**: Always backup data before changing scenarios

## Troubleshooting

### Common Issues

**Issue: Pods stuck in Pending**
```bash
# Check resource availability
kubectl describe pod POD_NAME
```
- Reduce resource requests in custom values file

**Issue: PVC not binding**
```bash
kubectl get pvc
```
- Check storage class exists
- For multi-replica deployments, verify ReadWriteMany support

**Issue: Ingress not working**
```bash
kubectl get ingress
kubectl describe ingress INGRESS_NAME
```
- Verify ingress controller is installed
- Check TLS certificate secrets exist

## Examples

### Complete Home Server Deployment

```bash
# Nextcloud with external PostgreSQL
helm install nextcloud ./charts/nextcloud \
  -f charts/nextcloud/values-home-single.yaml \
  --set postgresql.external.host=postgres.default.svc.cluster.local \
  --set postgresql.external.password=secret123 \
  --set redis.external.host=redis.default.svc.cluster.local \
  --set nextcloud.adminUser=admin \
  --set nextcloud.adminPassword=changeme123
```

### Complete Production Deployment

```bash
# Keycloak with HA, clustering, and monitoring
helm install keycloak ./charts/keycloak \
  -f charts/keycloak/values-prod-master-replica.yaml \
  --set postgresql.external.host=postgres-cluster.database.svc.cluster.local \
  --set postgresql.external.password=$(cat /secrets/pg-password) \
  --set keycloak.admin.password=$(cat /secrets/kc-admin-password) \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=auth.example.com \
  --set ingress.tls[0].secretName=keycloak-tls \
  --set ingress.tls[0].hosts[0]=auth.example.com
```

## Contributing

When creating new scenario values files:

1. Follow the naming convention: `values-SCENARIO.yaml`
2. Include all three standard scenarios (home, startup, prod)
3. Validate with `helm lint` and `helm template --validate`
4. Document any required values in chart README
5. Test actual deployment if possible

## See Also

- [Chart Development Guide](./CHART_DEVELOPMENT_GUIDE.md)
- [Chart Version Policy](./CHART_VERSION_POLICY.md)
- Individual chart READMEs for chart-specific configuration
