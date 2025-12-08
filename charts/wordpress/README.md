# WordPress Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/wordpress)

Production-ready WordPress deployment on Kubernetes with external MySQL support and Apache web server.

## Features

- **WordPress Apache Image**: Official WordPress with Apache HTTP Server
- **External Database**: MySQL support (no embedded database)
- **Persistent Storage**: Volume for WordPress content
- **Security**: Running as non-root user (www-data)
- **Production Ready**: Resource limits, health checks, and monitoring
- **Easy Configuration**: Simple values-based configuration

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install wordpress-home charts/wordpress \
  -f charts/wordpress/values-home-single.yaml \
  --set mysql.external.password=your-db-password \
  --set mysql.external.host=mysql.default.svc.cluster.local
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 5Gi storage

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install wordpress-startup charts/wordpress \
  -f charts/wordpress/values-startup-single.yaml \
  --set mysql.external.password=your-db-password \
  --set mysql.external.host=mysql.default.svc.cluster.local
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 10Gi storage

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with multiple replicas and monitoring:

```bash
helm install wordpress-prod charts/wordpress \
  -f charts/wordpress/values-prod-master-replica.yaml \
  --set mysql.external.password=your-db-password \
  --set mysql.external.host=mysql.default.svc.cluster.local
```

**Features:** 3 replicas, pod anti-affinity, HPA, PodDisruptionBudget, NetworkPolicy

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 20Gi storage per pod

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#wordpress).


- Kubernetes 1.19+
- Helm 3.0+
- External MySQL database
- PersistentVolume support (for data persistence)
- Ingress controller (for external access)

## Quick Start

### 🏠 Home Server Quick Start

For home server or low-resource environments, use the optimized configuration:

```bash
# Use pre-configured home server values
helm install my-wordpress ./charts/wordpress -f charts/wordpress/values-homeserver.yaml

# Or customize it
cp charts/wordpress/values-homeserver.yaml my-values.yaml
# Edit my-values.yaml with your settings
helm install my-wordpress ./charts/wordpress -f my-values.yaml
```

**Home Server Configuration includes:**
- Reduced resource limits (500m CPU, 512Mi RAM)
- Optimized storage (5Gi default)
- PHP memory optimizations
- Security hardening
- Performance tips and best practices

See [`values-homeserver.yaml`](./values-homeserver.yaml) for details.

---

### 1. Prepare External MySQL Database

Before installing WordPress, create a MySQL database:

```sql
CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wordpress'@'%' IDENTIFIED BY 'your-secure-password';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'%';
FLUSH PRIVILEGES;
```

### 2. Create Values File

Create a `my-values.yaml` file:

```yaml
# WordPress configuration
wordpress:
  title: "My WordPress Site"
  siteUrl: "https://myblog.example.com"
  homeUrl: "https://myblog.example.com"

  admin:
    username: "admin"
    password: "YourSecurePassword123!"
    email: "admin@example.com"

# External MySQL configuration
mysql:
  external:
    enabled: true
    host: "mysql-service.default.svc.cluster.local"
    port: 3306
    database: "wordpress"
    username: "wordpress"
    password: "your-secure-password"

# Ingress configuration
ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: myblog.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: wordpress-tls
      hosts:
        - myblog.example.com

# Storage configuration
persistence:
  content:
    size: 20Gi
```

### 3. Install the Chart

```bash
# Install WordPress
helm install myblog ./wordpress -f my-values.yaml

# Or upgrade if already installed
helm upgrade --install myblog ./wordpress -f my-values.yaml
```

### 4. Access WordPress

```bash
# Check the deployment status
kubectl get pods -l app.kubernetes.io/name=wordpress

# Get the Ingress URL
kubectl get ingress -l app.kubernetes.io/name=wordpress

# Access via browser
https://myblog.example.com
```

## Configuration

### WordPress Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `wordpress.title` | WordPress site title | `"My WordPress Site"` |
| `wordpress.siteUrl` | WordPress site URL | `"https://wordpress.example.com"` |
| `wordpress.homeUrl` | WordPress home URL | `"https://wordpress.example.com"` |
| `wordpress.admin.username` | Admin username | `"admin"` |
| `wordpress.admin.password` | Admin password (required) | `""` |
| `wordpress.admin.email` | Admin email | `"admin@example.com"` |
| `wordpress.debug` | Enable debug mode | `"false"` |
| `wordpress.tablePrefix` | Database table prefix | `"wp_"` |

### Image Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | WordPress image repository | `wordpress` |
| `image.tag` | Image tag | `"6.4.3-apache"` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### External MySQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mysql.external.enabled` | Enable external MySQL | `true` |
| `mysql.external.host` | MySQL host | `""` |
| `mysql.external.port` | MySQL port | `3306` |
| `mysql.external.database` | Database name | `"wordpress"` |
| `mysql.external.username` | Database username | `"wordpress"` |
| `mysql.external.password` | Database password | `""` |
| `mysql.external.existingSecret.enabled` | Use existing secret | `false` |

### Persistent Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.content.enabled` | Enable content volume | `true` |
| `persistence.content.size` | Content volume size | `10Gi` |
| `persistence.content.storageClass` | Storage class | `""` (default) |
| `persistence.content.existingClaim` | Use existing PVC | `""` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `"nginx"` |
| `ingress.annotations` | Ingress annotations | See values.yaml |
| `ingress.hosts` | Ingress hosts configuration | `[]` |
| `ingress.tls` | Ingress TLS configuration | `[]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `256Mi` |

## Advanced Configuration

### Using Existing Secrets

Instead of putting passwords in values.yaml, you can use existing Kubernetes secrets:

```yaml
mysql:
  external:
    existingSecret:
      enabled: true
      secretName: "mysql-credentials"
      usernameKey: "username"
      passwordKey: "password"
      databaseKey: "database"
```

Create the secret:

```bash
kubectl create secret generic mysql-credentials \
  --from-literal=username=wordpress \
  --from-literal=password=your-secure-password \
  --from-literal=database=wordpress
```

### Using Existing PVC

If you already have a PersistentVolumeClaim:

```yaml
persistence:
  content:
    existingClaim: "my-wordpress-content-pvc"
```

### WordPress Salts and Keys

For enhanced security, generate WordPress salts and keys:

```yaml
wordpress:
  salts:
    authKey: "put-unique-phrase-here"
    secureAuthKey: "put-unique-phrase-here"
    loggedInKey: "put-unique-phrase-here"
    nonceKey: "put-unique-phrase-here"
    authSalt: "put-unique-phrase-here"
    secureAuthSalt: "put-unique-phrase-here"
    loggedInSalt: "put-unique-phrase-here"
    nonceSalt: "put-unique-phrase-here"
```

Generate them at: https://api.wordpress.org/secret-key/1.1/salt/

### Installing Plugins and Themes

You can configure plugins and themes to be installed during initialization:

```yaml
wordpress:
  plugins:
    install:
      - woocommerce
      - contact-form-7
      - jetpack
    activate:
      - woocommerce
      - contact-form-7

  themes:
    install:
      - twentytwentyfour
      - astra
    activate: twentytwentyfour
```

### Custom Environment Variables

Add custom environment variables:

```yaml
extraEnv:
  - name: WORDPRESS_CONFIG_EXTRA
    value: |
      define('WP_MEMORY_LIMIT', '256M');
      define('WP_MAX_MEMORY_LIMIT', '512M');
      define('FORCE_SSL_ADMIN', true);
```

## High Availability & Security

WordPress chart supports production-grade high availability and security features:

### HorizontalPodAutoscaler

Automatically scale WordPress pods based on CPU and memory usage:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

**Benefits:**
- Automatically handles traffic spikes
- Scales down during low traffic to save resources
- Ensures consistent performance under varying loads

**Requirements:**
- Metrics Server installed in cluster
- ReadWriteMany (RWX) storage for multi-replica deployments

### PodDisruptionBudget

Ensures minimum availability during voluntary disruptions (node drains, updates, etc.):

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
  # Alternative: maxUnavailable: 1
```

**Benefits:**
- Prevents complete service outage during cluster maintenance
- Controls the rate of pod evictions
- Improves service reliability during rolling updates

**Use Cases:**
- Cluster upgrades without downtime
- Node maintenance with guaranteed availability
- Controlled rollout of configuration changes

### NetworkPolicy

Restricts network access to WordPress pods for enhanced security:

```yaml
networkPolicy:
  enabled: true
  ingress:
    # Allow traffic from ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 80
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Allow MySQL database access
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: mysql
      ports:
        - protocol: TCP
          port: 3306
```

**Benefits:**
- Zero-trust network security model
- Prevents lateral movement in case of compromise
- Compliance with security best practices

**Requirements:**
- CNI plugin with NetworkPolicy support (Calico, Cilium, etc.)
- Proper namespace and pod labels configured

### ServiceMonitor

Enable Prometheus metrics collection for monitoring:

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    path: /
    interval: 30s
    scrapeTimeout: 10s
    additionalLabels:
      prometheus: kube-prometheus
```

**Benefits:**
- Real-time visibility into WordPress performance
- Historical data for capacity planning
- Integration with alerting systems

**Requirements:**
- Prometheus Operator installed in cluster
- ServiceMonitor CRD available

### Production Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `autoscaling.minReplicas` | Minimum number of replicas | `1` |
| `autoscaling.maxReplicas` | Maximum number of replicas | `5` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` |
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget | `false` |
| `podDisruptionBudget.minAvailable` | Minimum available pods | `1` |
| `podDisruptionBudget.maxUnavailable` | Maximum unavailable pods | `""` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `networkPolicy.ingress` | Ingress rules | `[]` |
| `networkPolicy.egress` | Egress rules | `[]` |
| `monitoring.serviceMonitor.enabled` | Enable ServiceMonitor | `false` |
| `monitoring.serviceMonitor.path` | Metrics endpoint path | `/` |
| `monitoring.serviceMonitor.interval` | Scrape interval | `30s` |
| `monitoring.serviceMonitor.scrapeTimeout` | Scrape timeout | `10s` |

### Complete Production Example

See [values-example.yaml](./values-example.yaml) for a complete production-ready configuration with all HA features enabled.

## Maintenance

### Backup

Backup your PersistentVolume and database regularly:

```bash
# Backup WordPress content
kubectl exec -it <wordpress-pod> -- tar czf /tmp/wordpress-backup.tar.gz /var/www/html

# Backup database
kubectl exec -it <mysql-pod> -- mysqldump -u wordpress -p wordpress > wordpress-db-backup.sql
```

### Upgrade WordPress

```bash
# Update image tag in values.yaml
image:
  tag: "6.5.0-apache"

# Upgrade the release
helm upgrade myblog ./wordpress -f my-values.yaml

# Check upgrade status
kubectl logs -f <wordpress-pod>
```

### Scaling

Adjust replicas for high availability:

```yaml
replicaCount: 3

# Note: Requires ReadWriteMany (RWX) storage class
persistence:
  content:
    accessMode: ReadWriteMany
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=wordpress
kubectl describe pod <wordpress-pod>
kubectl logs <wordpress-pod>
```

### Check Initialization

```bash
# View init container logs
kubectl logs <wordpress-pod> -c init-wordpress
```

### Database Connection Issues

```bash
# Test MySQL connection from pod
kubectl exec -it <wordpress-pod> -- mysql -h <mysql-host> -u wordpress -p
```

### Access WordPress CLI

```bash
# Run WP-CLI commands
kubectl exec -it <wordpress-pod> -- wp --info --allow-root
kubectl exec -it <wordpress-pod> -- wp plugin list --allow-root
kubectl exec -it <wordpress-pod> -- wp theme list --allow-root
```

## Security Considerations

1. **Always use strong passwords** for admin and database users
2. **Enable HTTPS** via Ingress TLS configuration
3. **Use Kubernetes Secrets** for sensitive data
4. **Regularly update** WordPress and plugins
5. **Configure firewall rules** for database access
6. **Disable debug mode** in production (`wordpress.debug: "false"`)
7. **Monitor logs** for suspicious activities
8. **Use WordPress salts** for enhanced security

## Performance Tuning

### Recommended Resource Allocation

For production workloads:

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi

# Increase PHP limits
extraEnv:
  - name: WORDPRESS_CONFIG_EXTRA
    value: |
      define('WP_MEMORY_LIMIT', '512M');
      define('WP_MAX_MEMORY_LIMIT', '1024M');
```

### Storage Performance

Use high-performance storage classes for better performance:

```yaml
persistence:
  content:
    storageClass: "fast-ssd"  # Use SSD-backed storage
```

## Backup & Recovery

WordPress chart includes comprehensive backup and recovery capabilities for complete disaster recovery.

### Backup Components

WordPress backups consist of 4 critical components:

| Component | What's Included | Backup Method | Recovery Time |
|-----------|----------------|---------------|---------------|
| **WordPress Content** | Uploads, plugins, themes, wp-config.php | tar (full), rsync (incremental) | 10-30 min |
| **MySQL Database** | Posts, pages, settings, users | mysqldump | 5-15 min |
| **Configuration** | ConfigMaps, Secrets, Helm values | kubectl export | 5-10 min |
| **PVC Snapshots** | Point-in-time storage snapshots | VolumeSnapshot API | 5-10 min |

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/wordpress.mk wp-full-backup

# Component-specific backups
make -f make/ops/wordpress.mk wp-backup-content-full       # WordPress files
make -f make/ops/wordpress.mk wp-backup-content-incremental # Changed files only
make -f make/ops/wordpress.mk wp-backup-mysql              # Database
make -f make/ops/wordpress.mk wp-backup-config             # Kubernetes config
make -f make/ops/wordpress.mk wp-snapshot-content          # PVC snapshot
```

### Quick Recovery Commands

```bash
# Restore WordPress content
make -f make/ops/wordpress.mk wp-restore-content BACKUP_FILE=backups/wordpress-content-full-20250108-143022.tar.gz

# Restore MySQL database
make -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=backups/wordpress-mysql-20250108-143022.sql.gz

# Restore Kubernetes configuration
make -f make/ops/wordpress.mk wp-restore-config BACKUP_FILE=backups/wordpress-config-20250108-143022.tar.gz

# Full disaster recovery
make -f make/ops/wordpress.mk wp-full-recovery \
  CONTENT_BACKUP=backups/wordpress-content-full-20250108-143022.tar.gz \
  MYSQL_BACKUP=backups/wordpress-mysql-20250108-143022.sql.gz \
  CONFIG_BACKUP=backups/wordpress-config-20250108-143022.tar.gz
```

### Recovery Objectives

- **RTO (Recovery Time Objective)**: < 2 hours (complete instance recovery)
- **RPO (Recovery Point Objective)**: 24 hours (daily backups), 1 hour (hourly for critical)

**Recommended Backup Frequency:**
- WordPress Content: Hourly or Daily
- MySQL Database: Daily (hourly for critical deployments)
- Configuration: On every change
- PVC Snapshots: Weekly

### Backup Best Practices

1. ✅ **Store backups offsite** (different availability zone, S3, MinIO)
2. ✅ **Test restore procedures quarterly** in isolated namespace
3. ✅ **Encrypt backups** (wp-config.php contains database credentials)
4. ✅ **Always backup before upgrades** (critical!)
5. ✅ **Monitor backup success/failure** (alerting)

**Complete Backup Guide**: [docs/wordpress-backup-guide.md](../../docs/wordpress-backup-guide.md)

---

## Security & RBAC

WordPress chart implements comprehensive security controls following Kubernetes best practices.

### RBAC Permissions

The chart creates namespace-scoped RBAC resources with minimal read-only permissions:

| Resource | Permissions | Purpose |
|----------|-------------|---------|
| **ConfigMaps** | get, list, watch | Read WordPress environment variables |
| **Secrets** | get, list, watch | Access database credentials, SMTP passwords, WordPress salts |
| **Pods** | get, list, watch | Health checks and operations |
| **Services** | get, list, watch | Service discovery |
| **Endpoints** | get, list, watch | Service discovery |
| **PersistentVolumeClaims** | get, list, watch | Storage operations |

**Enable RBAC** (enabled by default):

```yaml
rbac:
  create: true
  annotations: {}
```

### Pod Security

**Security Context (non-root execution)**:

```yaml
podSecurityContext:
  fsGroup: 33  # www-data group
  runAsUser: 33  # www-data user
  runAsGroup: 33
  runAsNonRoot: true

securityContext:
  readOnlyRootFilesystem: false  # WordPress needs write access to /var/www/html
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

### Network Policies

Restrict network access to WordPress pods:

```yaml
networkPolicy:
  enabled: true
  ingress:
    # Allow only from ingress controller
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
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Allow MySQL
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: mysql
      ports:
        - protocol: TCP
          port: 3306
```

### Security Checklist

- ✅ **Strong Passwords**: Use unique, complex passwords for admin and database
- ✅ **HTTPS Only**: Enable TLS via Ingress (`ingress.tls`)
- ✅ **Disable Debug Mode**: Set `wordpress.debug: "false"` in production
- ✅ **Use Secrets**: Never put passwords in values.yaml
- ✅ **WordPress Salts**: Generate unique salts at https://api.wordpress.org/secret-key/1.1/salt/
- ✅ **Regular Updates**: Keep WordPress, plugins, and themes updated
- ✅ **RBAC Enabled**: Use `rbac.create: true` (default)
- ✅ **Network Policies**: Restrict pod-to-pod communication
- ✅ **Monitor Logs**: Watch for suspicious activities

---

## Operations

WordPress chart includes 50+ operational commands via Makefile for administration, monitoring, and troubleshooting.

### Basic Operations

```bash
# WordPress status
make -f make/ops/wordpress.mk wp-status                # Pod status
make -f make/ops/wordpress.mk wp-version               # WordPress version
make -f make/ops/wordpress.mk wp-php-version           # PHP version
make -f make/ops/wordpress.mk wp-logs                  # View logs
make -f make/ops/wordpress.mk wp-logs-follow           # Follow logs
make -f make/ops/wordpress.mk wp-shell                 # Shell access to pod
make -f make/ops/wordpress.mk wp-restart               # Restart WordPress
make -f make/ops/wordpress.mk wp-port-forward          # Port-forward to localhost:8080
```

### Database Operations

```bash
# Database health
make -f make/ops/wordpress.mk wp-db-check              # Test database connectivity
make -f make/ops/wordpress.mk wp-db-version            # Database schema version
make -f make/ops/wordpress.mk wp-db-size               # Database size
make -f make/ops/wordpress.mk wp-db-table-count        # Count tables
make -f make/ops/wordpress.mk wp-db-list-tables        # List all tables
make -f make/ops/wordpress.mk wp-db-shell              # MySQL shell access

# Database operations
make -f make/ops/wordpress.mk wp-db-optimize           # Optimize database tables
make -f make/ops/wordpress.mk wp-db-repair             # Repair database tables
make -f make/ops/wordpress.mk wp-db-upgrade            # Trigger database upgrade
```

### WordPress Management (WP-CLI)

```bash
# Plugin management
make -f make/ops/wordpress.mk wp-list-plugins          # List installed plugins
make -f make/ops/wordpress.mk wp-plugin-activate PLUGIN=woocommerce
make -f make/ops/wordpress.mk wp-plugin-deactivate PLUGIN=woocommerce
make -f make/ops/wordpress.mk wp-plugin-update PLUGIN=woocommerce

# Theme management
make -f make/ops/wordpress.mk wp-list-themes           # List installed themes
make -f make/ops/wordpress.mk wp-theme-activate THEME=twentytwentyfour

# User management
make -f make/ops/wordpress.mk wp-list-users            # List users
make -f make/ops/wordpress.mk wp-create-user USER=john EMAIL=john@example.com ROLE=editor
make -f make/ops/wordpress.mk wp-delete-user USER=john

# Content management
make -f make/ops/wordpress.mk wp-list-posts            # List posts
make -f make/ops/wordpress.mk wp-list-pages            # List pages
make -f make/ops/wordpress.mk wp-media-regenerate      # Regenerate thumbnails
```

### Maintenance Mode

```bash
# Enable maintenance mode (shows "Site under maintenance" to users)
make -f make/ops/wordpress.mk wp-enable-maintenance

# Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# Check maintenance status
make -f make/ops/wordpress.mk wp-maintenance-status
```

### Monitoring & Troubleshooting

```bash
# Resource monitoring
make -f make/ops/wordpress.mk wp-disk-usage            # Disk usage
make -f make/ops/wordpress.mk wp-resource-usage        # CPU/memory usage
make -f make/ops/wordpress.mk wp-top                   # Resource usage (live)
make -f make/ops/wordpress.mk wp-describe              # Pod details

# Health checks
make -f make/ops/wordpress.mk wp-health-check          # All health checks
make -f make/ops/wordpress.mk wp-liveness-check        # Liveness probe
make -f make/ops/wordpress.mk wp-readiness-check       # Readiness probe

# Cleanup
make -f make/ops/wordpress.mk wp-cleanup-revisions     # Delete post revisions
make -f make/ops/wordpress.mk wp-cleanup-spam          # Delete spam comments
make -f make/ops/wordpress.mk wp-cleanup-trash         # Empty trash
make -f make/ops/wordpress.mk wp-cache-flush           # Flush WordPress cache
```

### Backup & Recovery Operations

See [Backup & Recovery](#backup--recovery) section for backup commands.

### Upgrade Operations

```bash
# Pre-upgrade validation
make -f make/ops/wordpress.mk wp-pre-upgrade-check     # Pre-upgrade checklist

# Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check    # Post-upgrade validation
```

**Complete Makefile**: [make/ops/wordpress.mk](../../make/ops/wordpress.mk)

---

## Upgrading

WordPress chart supports multiple upgrade strategies based on upgrade complexity and downtime requirements.

### Upgrade Strategies

| Strategy | Downtime | Best For | Complexity |
|----------|----------|----------|------------|
| **Rolling Upgrade** | None | Patch/minor versions (6.7.1 → 6.7.2) | Low |
| **Maintenance Mode** | 10-15 min | Major versions (5.x → 6.x), PHP upgrades | Medium |
| **Blue-Green** | None | Zero-downtime major upgrades | High |
| **Database Migration** | 30 min - 2 hours | MySQL version upgrades (5.7 → 8.0) | Very High |

### Quick Upgrade Guide

**1. Patch Upgrade (e.g., 6.7.1 → 6.7.2)**

Zero-downtime rolling upgrade:

```bash
# 1. Pre-upgrade backup
make -f make/ops/wordpress.mk wp-full-backup

# 2. Pre-upgrade check
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 3. Upgrade via Helm
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.7.2-apache \
  --reuse-values

# 4. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

**2. Minor Upgrade (e.g., 6.7.x → 6.8.x)**

Recommended: Maintenance mode (10-15 minutes downtime):

```bash
# 1. Full backup
make -f make/ops/wordpress.mk wp-full-backup

# 2. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 3. Scale down
kubectl scale deployment wordpress -n wordpress --replicas=0

# 4. Upgrade
helm upgrade wordpress scripton-charts/wordpress \
  --set image.tag=6.8-apache \
  --reuse-values

# 5. Scale up
kubectl scale deployment wordpress -n wordpress --replicas=1

# 6. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# 7. Validation
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

**3. Major Upgrade (e.g., 5.x → 6.x)**

CRITICAL: Test in staging first!

```bash
# 1. Review WordPress 6.x release notes
# 2. Check plugin/theme compatibility
# 3. Full backup
make -f make/ops/wordpress.mk wp-full-backup

# 4. Create PVC snapshot for fast rollback
make -f make/ops/wordpress.mk wp-snapshot-content

# 5. Follow maintenance mode upgrade procedure (same as minor upgrade)
# 6. Extensive post-upgrade validation (test all plugins, themes, features)
```

### Pre-Upgrade Checklist

**CRITICAL**: Complete ALL steps before upgrading:

```bash
# 1. Review release notes
# Check: https://wordpress.org/news/category/releases/

# 2. Check current versions
make -f make/ops/wordpress.mk wp-version
make -f make/ops/wordpress.mk wp-php-version
make -f make/ops/wordpress.mk wp-db-version

# 3. Full backup (CRITICAL!)
make -f make/ops/wordpress.mk wp-full-backup

# 4. PVC snapshot (optional but recommended)
make -f make/ops/wordpress.mk wp-snapshot-content

# 5. Check plugin/theme compatibility
make -f make/ops/wordpress.mk wp-list-plugins
make -f make/ops/wordpress.mk wp-list-themes

# 6. Test database integrity
make -f make/ops/wordpress.mk wp-db-check

# 7. Export Helm values
helm get values wordpress -n wordpress > backups/helm-values-pre-upgrade.yaml
```

### Post-Upgrade Validation

```bash
# 1. Automated validation
make -f make/ops/wordpress.mk wp-post-upgrade-check

# 2. Manual validation
# - Login to /wp-admin
# - Verify posts/pages load
# - Test media library (upload image)
# - Test plugin functionality
# - Test theme rendering
# - Check for PHP errors in logs

# 3. Monitor logs for 1 hour
kubectl logs -f -l app.kubernetes.io/name=wordpress -n wordpress
```

### Rollback Procedures

**Rollback Decision Matrix:**

| Scenario | Rollback Method | Downtime | Data Loss Risk |
|----------|----------------|----------|----------------|
| Chart upgrade only | Helm rollback | None | None |
| WordPress patch/minor | Helm rollback + DB restore | 10-15 min | Data since upgrade |
| WordPress major | Helm rollback + DB restore | 10-15 min | Data since upgrade |
| Database corruption | PVC snapshot restore | 5-10 min | Data since snapshot |

**Quick Rollback (Helm only)**:

```bash
helm rollback wordpress -n wordpress
```

**Full Rollback (WordPress core upgrade)**:

```bash
# 1. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 2. Scale down
kubectl scale deployment wordpress -n wordpress --replicas=0

# 3. Restore database
make -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=backups/wordpress-mysql-20250108-143022.sql.gz

# 4. Rollback Helm
helm rollback wordpress -n wordpress

# 5. Scale up
kubectl scale deployment wordpress -n wordpress --replicas=1

# 6. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance
```

### Version-Specific Notes

**WordPress 6.7 → 6.8**:
- Performance improvements in block editor
- No breaking changes
- Database schema updated to 57155
- Rolling upgrade recommended

**WordPress 6.x → 7.x** (future):
- Expected major changes: Block-first architecture
- Minimum PHP 8.0 expected
- Test thoroughly in staging

### Upgrade Best Practices

1. ✅ **Always backup first** (wp-full-backup)
2. ✅ **Test in staging environment** before production
3. ✅ **Read release notes** (https://wordpress.org/news/)
4. ✅ **Check plugin/theme compatibility**
5. ✅ **Monitor logs for 1 hour** after upgrade
6. ✅ **Plan maintenance window** for major upgrades
7. ✅ **Incremental upgrades** (don't skip versions: 6.6 → 6.7 → 6.8)

**Complete Upgrade Guide**: [docs/wordpress-upgrade-guide.md](../../docs/wordpress-upgrade-guide.md)

---

## Contributing

Contributions are welcome! Please submit issues and pull requests.

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

This Helm chart is provided as-is under the MIT License.

## Support

- WordPress Documentation: https://wordpress.org/support/
- WordPress Forums: https://wordpress.org/support/forums/
- Issue Tracker: https://github.com/your-repo/issues
