# WordPress Helm Chart

Production-ready WordPress deployment on Kubernetes with external MySQL support and Apache web server.

## Features

- **WordPress Apache Image**: Official WordPress with Apache HTTP Server
- **External Database**: MySQL support (no embedded database)
- **Persistent Storage**: Volume for WordPress content
- **Security**: Running as non-root user (www-data)
- **Production Ready**: Resource limits, health checks, and monitoring
- **Easy Configuration**: Simple values-based configuration

## Prerequisites

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

## Contributing

Contributions are welcome! Please submit issues and pull requests.

## License

This Helm chart is provided as-is under the MIT License.

## Support

- WordPress Documentation: https://wordpress.org/support/
- WordPress Forums: https://wordpress.org/support/forums/
- Issue Tracker: https://github.com/your-repo/issues
