# WordPress Home Server - Example Deployment

Optimized WordPress deployment for home servers and low-resource environments.

## Stack Components

### Application

- **WordPress** - Content management system (Apache)
- **MySQL** - Database for WordPress content

### Features

- Resource-optimized for home servers (Raspberry Pi, NUC, small VPS)
- Reduced resource requirements (50% of production)
- Security hardening (file editing disabled, auto-updates disabled)
- Persistent storage for content and database
- Optional ingress for external access
- Single replica for minimal resource usage

## Architecture

```
┌──────────────────────────────────────────────────┐
│          Ingress (Optional)                       │
│       blog.home.example.com                       │
└─────────────────┬────────────────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │   WordPress    │
         │  (Deployment)  │
         └────────┬───────┘
                  │
                  ▼
         ┌────────────────┐
         │     MySQL      │
         │   (External)   │
         └────────┬───────┘
                  │
             ┌────┴────┐
             ▼         ▼
        ┌──────┐  ┌──────┐
        │  PVC │  │  PVC │
        │(WP)  │  │ (DB) │
        └──────┘  └──────┘
```

## Target Hardware

This configuration is optimized for:

- **Raspberry Pi 4** (4GB+ RAM)
- **Intel NUC** (i3+, 8GB+ RAM)
- **Small VPS** (2 vCPU, 4GB RAM)
- **Home Server** (any x86_64 with 4GB+ RAM)

## Prerequisites

### 1. Kubernetes Cluster

- K3s, MicroK8s, or Kind (for home lab)
- Kubernetes 1.21+
- Single node is sufficient

### 2. External MySQL

```bash
# Create database and user
CREATE DATABASE wordpress;
CREATE USER 'wordpress'@'%' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'%';
FLUSH PRIVILEGES;
```

### 3. Storage

- Local path provisioner (k3s default) or hostPath
- Minimum: 10GB total (5GB WordPress + 5GB MySQL)
- Recommended: 20GB+ for growth

### 4. Helm Repository

```bash
helm repo add scripton-charts <https://scriptonbasestar-container.github.io/sb-helm-charts>
helm repo update
```

## Installation

### Step 1: Create Namespace

```bash
kubectl create namespace wordpress
```

### Step 2: Create Secrets

```bash
# MySQL password
kubectl create secret generic wordpress-db-secret \
  --from-literal=password='your-mysql-password' \
  -n wordpress
```

### Step 3: Customize Values

Edit `values-wordpress.yaml`:

1. Set `wordpress.siteUrl` to your desired URL
2. Update `mysql.external.host` to your MySQL service
3. Adjust storage sizes if needed (default: 5Gi each)
4. Optional: Enable ingress for external access

### Step 4: Install WordPress

```bash
helm install wordpress scripton-charts/wordpress \
  -f values-wordpress.yaml \
  -n wordpress
```

### Step 5: Verify Installation

```bash
# Check pod is running
kubectl get pods -n wordpress

# Expected output:
# wordpress-...    1/1     Running

# Check service
kubectl get svc -n wordpress
```

## Access

### Local Access (Port Forward)

```bash
# Port forward to localhost
kubectl port-forward svc/wordpress 8080:80 -n wordpress

# Access in browser
# URL: http://localhost:8080
```

### External Access (Ingress)

If ingress is enabled in values.yaml:

```bash
# Get ingress URL
kubectl get ingress wordpress -n wordpress

# Access via browser
# URL: http://blog.home.example.com
```

### Complete WordPress Setup

1. Open browser to WordPress URL
2. Select language
3. Set site title and admin credentials
4. Click "Install WordPress"
5. Login with admin credentials

## Configuration

### Initial WordPress Setup

After installation, configure these settings:

#### General Settings

- Site Title: Your blog name
- Tagline: Brief description
- WordPress Address (URL): Your site URL
- Site Address (URL): Your site URL
- Timezone: Your local timezone

#### Permalinks

```
Settings → Permalinks → Post name
```

Recommended: Post name (`/%postname%/`)

### Security Hardening

The example configuration includes:

```yaml
# File editing disabled (values.yaml)
wordpress:
  disableFileEdit: true
  disableAutoUpdate: true

  # Reduced post revisions
  postRevisions: 5
  autosaveInterval: 5  # minutes
```

Additional recommendations:

1. **Install Security Plugin**: Wordfence or Sucuri
2. **Enable HTTPS**: Use cert-manager for TLS
3. **Regular Backups**: Setup backup cron jobs
4. **Strong Passwords**: Use password manager
5. **Two-Factor Authentication**: Install 2FA plugin

### Recommended Plugins

```bash
# Access WordPress pod
kubectl exec -it wordpress-xxx -n wordpress -- bash

# Install WP-CLI plugins
wp plugin install wordfence --activate
wp plugin install jetpack --activate
wp plugin install wp-super-cache --activate
```

Or install via WordPress admin:

- **Wordfence Security** - Security and firewall
- **Jetpack** - Performance and security
- **WP Super Cache** - Page caching
- **Akismet** - Spam protection
- **Yoast SEO** - SEO optimization

### Performance Optimization

#### Enable Caching

```bash
kubectl exec wordpress-xxx -n wordpress -- \
  wp plugin install wp-super-cache --activate

kubectl exec wordpress-xxx -n wordpress -- \
  wp super-cache enable
```

#### Optimize Database

```bash
# Cleanup revisions
kubectl exec wordpress-xxx -n wordpress -- \
  wp post delete $(wp post list --post_type='revision' --format=ids)

# Optimize tables
kubectl exec mysql-0 -n database -- \
  mysqlcheck -u wordpress -p wordpress --optimize
```

## Maintenance

### Backup

```bash
# Backup WordPress files
kubectl exec wordpress-xxx -n wordpress -- \
  tar czf /tmp/wordpress-backup.tar.gz /var/www/html
kubectl cp wordpress/wordpress-xxx:/tmp/wordpress-backup.tar.gz ./wordpress-backup.tar.gz

# Backup MySQL database
kubectl exec mysql-0 -n database -- \
  mysqldump -u wordpress -p wordpress > wordpress-db-backup.sql
```

### Updates

```bash
# Update WordPress core
kubectl exec wordpress-xxx -n wordpress -- \
  wp core update

# Update plugins
kubectl exec wordpress-xxx -n wordpress -- \
  wp plugin update --all

# Update themes
kubectl exec wordpress-xxx -n wordpress -- \
  wp theme update --all
```

### Restore

```bash
# Restore files
kubectl cp ./wordpress-backup.tar.gz wordpress/wordpress-xxx:/tmp/
kubectl exec wordpress-xxx -n wordpress -- \
  tar xzf /tmp/wordpress-backup.tar.gz -C /

# Restore database
kubectl exec -i mysql-0 -n database -- \
  mysql -u wordpress -p wordpress < wordpress-db-backup.sql
```

## Resource Requirements

### Minimum (Single Site)

- 1 CPU core
- 2 GB RAM
- 10 GB storage

### Recommended (Multiple Sites)

- 2 CPU cores
- 4 GB RAM
- 20 GB storage

### Per Component

| Component | CPU (req/limit) | Memory (req/limit) | Storage |
|-----------|-----------------|-------------------|---------|
| WordPress | 200m/500m | 256Mi/512Mi | 5Gi |
| MySQL | 200m/500m | 256Mi/512Mi | 5Gi |

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl describe pod wordpress-xxx -n wordpress

# Check logs
kubectl logs wordpress-xxx -n wordpress

# Common issues:
# 1. Database connection failed - check MySQL credentials
# 2. PVC not binding - check storage class
# 3. Resource limits - reduce in values.yaml
```

### Database connection errors

```bash
# Test MySQL connection
kubectl exec wordpress-xxx -n wordpress -- \
  mysql -h mysql.database.svc.cluster.local -u wordpress -p -e "SELECT 1"

# Check database exists
kubectl exec mysql-0 -n database -- \
  mysql -u root -p -e "SHOW DATABASES"
```

### WordPress installation loop

```bash
# Check wp-config.php exists
kubectl exec wordpress-xxx -n wordpress -- \
  ls -la /var/www/html/wp-config.php

# Check database tables
kubectl exec mysql-0 -n database -- \
  mysql -u wordpress -p wordpress -e "SHOW TABLES"
```

### Slow performance

```bash
# Check resource usage
kubectl top pod wordpress-xxx -n wordpress

# Increase resources in values.yaml
# Enable caching (WP Super Cache)
# Optimize images (WP Smush plugin)
```

### File upload issues

```bash
# Check PHP upload limits
kubectl exec wordpress-xxx -n wordpress -- \
  php -i | grep upload_max_filesize

# Check disk space
kubectl exec wordpress-xxx -n wordpress -- df -h

# Increase limits in values.yaml:
# wordpress:
#   php:
#     uploadMaxFilesize: 64M
#     postMaxSize: 64M
```

## Uninstallation

```bash
# Remove WordPress
helm uninstall wordpress -n wordpress

# (Optional) Delete PVCs
kubectl delete pvc -n wordpress -l app.kubernetes.io/name=wordpress

# (Optional) Delete namespace
kubectl delete namespace wordpress
```

## Home Server Tips

### Power Management

```yaml
# Schedule downtime for backups
# Use CronJob for automated backups
# Scale down during low-usage hours
```

### External Access

```yaml
# Use Cloudflare Tunnel for secure access
# Or setup Dynamic DNS + port forwarding
# Or use Tailscale for private access
```

### Monitoring

```yaml
# Use Uptime Kuma for health checks
# Monitor resource usage with Prometheus
# Setup alerts for downtime
```

### Backup Strategy

```bash
# Daily backups via CronJob
# Keep 7 daily + 4 weekly backups
# Offsite backup to cloud storage
```

## Next Steps

1. **Complete Setup**: Finish WordPress installation wizard
2. **Install Theme**: Choose and customize a theme
3. **Install Plugins**: Security, caching, SEO
4. **Create Content**: Write first blog post
5. **Setup Backups**: Automated backup schedule
6. **Enable HTTPS**: Use cert-manager for TLS
7. **Configure SEO**: Setup Yoast SEO plugin
8. **Monitor Performance**: Track resource usage

## References

- [WordPress Documentation](<https://wordpress.org/documentation/>)
- [WP-CLI Commands](<https://developer.wordpress.org/cli/commands/>)
- [WordPress Codex](<https://codex.wordpress.org/>)
- [K3s Documentation](<https://docs.k3s.io/>)
