# phpMyAdmin Helm Chart

phpMyAdmin is a free software tool written in PHP, intended to handle the administration of MySQL and MariaDB over the Web. This chart provides a production-ready deployment with security best practices and flexible configuration options.

## Features

- **Web-based MySQL/MariaDB Management**: Full-featured GUI for database administration
- **Multi-Server Support**: Manage multiple MySQL/MariaDB instances
- **Pre-configured Servers**: Automatic server registration via values
- **Security Hardening**: Non-root user, network policies, blowfish encryption
- **High Availability**: Multi-replica support with session affinity
- **Flexible Upload Limits**: Configurable file upload and import sizes

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support (for persistence)
- MySQL or MariaDB database(s) to manage

## Installation

### Quick Start (Development)

```bash
helm install phpmyadmin charts/phpmyadmin \
  --namespace database-admin \
  --values charts/phpmyadmin/values-dev.yaml \
  --set phpmyadmin.host="mysql.default.svc.cluster.local"
```

### Production Installation

```bash
helm install phpmyadmin charts/phpmyadmin \
  --namespace database-admin \
  --values charts/phpmyadmin/values-small-prod.yaml
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | phpMyAdmin image | `phpmyadmin` |
| `image.tag` | Image tag | `5.2.1` |
| `phpmyadmin.host` | MySQL host (single server mode) | `""` |
| `phpmyadmin.port` | MySQL port | `3306` |

### Connection Modes

#### 1. Single Host (Default)

```yaml
phpmyadmin:
  host: "mysql.default.svc.cluster.local"
  port: 3306
```

#### 2. Arbitrary Server Connection

```yaml
phpmyadmin:
  arbitraryServerConnection: true
  allowArbitraryServer: true  # Security risk - use with caution
```

#### 3. Pre-configured Servers (Recommended for Production)

```yaml
phpmyadmin:
  servers:
    enabled: true
    config:
      - host: "mysql-prod.default.svc.cluster.local"
        port: 3306
        verbose: "Production MySQL"
        ssl: true
      - host: "mysql-staging.default.svc.cluster.local"
        port: 3306
        verbose: "Staging MySQL"
        ssl: false
```

### Upload/Import Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `phpmyadmin.uploadLimit` | Max upload size | `128M` |
| `phpmyadmin.maxExecutionTime` | Max execution time (seconds) | `600` |
| `phpmyadmin.memoryLimit` | PHP memory limit | `512M` |

### Security

#### Hide System Databases

```yaml
phpmyadmin:
  hideDatabases:
    - information_schema
    - performance_schema
    - mysql
    - sys
```

#### Network Policies

```yaml
networkPolicy:
  enabled: true
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            name: database
      ports:
      - protocol: TCP
        port: 3306
```

### Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "128m"  # Match uploadLimit
    nginx.ingress.kubernetes.io/affinity: "cookie"  # For multi-replica
  hosts:
    - host: phpmyadmin.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: phpmyadmin-tls
      hosts:
        - phpmyadmin.example.com
```

## Usage

### Accessing phpMyAdmin

```bash
# Port forward
make -f make/ops/phpmyadmin.mk phpmyadmin-port-forward
# Visit http://localhost:8080

# Or via Ingress
echo "https://$(kubectl get ingress -n database-admin phpmyadmin -o jsonpath='{.spec.rules[0].host}')"
```

### Login

- **Server**: Select from dropdown (pre-configured mode) or enter manually
- **Username**: Your MySQL/MariaDB username
- **Password**: Your MySQL/MariaDB password

## Security Best Practices

1. **Use HTTPS Only**
   - Configure Ingress with TLS
   - Never expose over HTTP

2. **Disable Arbitrary Server Connection**
   ```yaml
   phpmyadmin:
     allowArbitraryServer: false
   ```

3. **Use Read-Only Accounts**
   ```sql
   CREATE USER 'readonly'@'%' IDENTIFIED BY 'password';
   GRANT SELECT ON *.* TO 'readonly'@'%';
   ```

4. **Enable Network Policies**
   - Restrict access to specific namespaces/pods

5. **Regular Updates**
   - Keep phpMyAdmin image updated

6. **IP Whitelisting** (Ingress)
   ```yaml
   ingress:
     annotations:
       nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
   ```

## Operational Commands

```bash
# Port forward
make -f make/ops/phpmyadmin.mk phpmyadmin-port-forward

# View logs
make -f make/ops/phpmyadmin.mk phpmyadmin-logs

# Open shell
make -f make/ops/phpmyadmin.mk phpmyadmin-shell

# Restart
make -f make/ops/phpmyadmin.mk phpmyadmin-restart
```

## Troubleshooting

### Upload Limit Exceeded

Increase limits and update Ingress annotation:

```yaml
phpmyadmin:
  uploadLimit: "256M"

ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "256m"
```

### Session Lost After Pod Restart

Enable session affinity:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
```

### Cannot Connect to MySQL

1. Check MySQL service:
   ```bash
   kubectl get svc -n default mysql
   ```

2. Test connection from pod:
   ```bash
   kubectl exec -it phpmyadmin-xxx -- mysql -h mysql.default.svc.cluster.local -u root -p
   ```

3. Check network policies

## Values Profiles

### Development (values-dev.yaml)

- Single replica
- Arbitrary server connection enabled
- Smaller resources (300m CPU, 256Mi RAM)
- 200Mi storage

### Small Production (values-small-prod.yaml)

- 2 replicas for HA
- Pre-configured servers
- Network policies enabled
- Session affinity
- Hidden system databases
- Production resources (1 CPU, 1Gi RAM)
- 1Gi storage

## License

This Helm chart is licensed under BSD-3-Clause.

phpMyAdmin is licensed under GPL v2. See: https://www.phpmyadmin.net/license/

## Links

- **Chart Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **phpMyAdmin Official**: https://www.phpmyadmin.net/
- **Documentation**: https://docs.phpmyadmin.net/
