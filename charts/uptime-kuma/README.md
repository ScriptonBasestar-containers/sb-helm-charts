# Uptime Kuma Helm Chart

A self-hosted monitoring tool with beautiful UI, multi-protocol support, and flexible alerting.

## Features

- 🖥️ **Beautiful Dashboard**: Modern, intuitive web interface
- 📊 **Multi-Protocol Monitoring**: HTTP(s), TCP, Ping, DNS, SMTP, and more
- 📱 **90+ Notification Services**: Telegram, Discord, Slack, Email, and many more
- 📈 **Status Pages**: Public status pages for your services
- 🔐 **Multi-User Support**: User management with 2FA
- 🌍 **Multi-Language**: Support for 25+ languages
- 📦 **Lightweight**: Single Docker container, low resource usage

## Prerequisites

- Kubernetes 1.22+
- Helm 3.0+
- PersistentVolume provisioner (for data persistence)
- **Optional**: External MySQL/MariaDB (for production environments)

## Quick Start

### 1. Install with SQLite (Default)

```bash
helm install uptime-kuma ./charts/uptime-kuma
```

### 2. Access Uptime Kuma

```bash
kubectl port-forward svc/uptime-kuma 3001:3001
# Visit http://localhost:3001
# Create admin account on first access
```

## Configuration

### Database Options

#### SQLite (Default - Recommended for Small Deployments)

```yaml
uptimeKuma:
  database:
    type: "sqlite"

persistence:
  enabled: true
  size: 4Gi
```

**Pros:**
- Zero configuration
- No external dependencies
- Perfect for homelab/small deployments

**Cons:**
- Single file database
- Not suitable for high-traffic environments

#### MariaDB (Recommended for Production)

```yaml
uptimeKuma:
  database:
    type: "mariadb"
    mariadb:
      host: "mariadb.default.svc.cluster.local"
      port: 3306
      database: "uptime_kuma"
      username: "uptime_kuma"
      password: "changeme123"
```

**Pros:**
- Better performance under load
- Easier backups
- Multiple replicas possible

**Setup external MariaDB:**
```bash
# Using sb-helm-charts MySQL chart
helm install mariadb ./charts/mysql \
  --set auth.database=uptime_kuma \
  --set auth.username=uptime_kuma \
  --set auth.password=secure_password
```

### SSL/TLS Configuration

```yaml
uptimeKuma:
  ssl:
    enabled: true
    keyPath: "/certs/tls.key"
    certPath: "/certs/tls.crt"
    keyPassphrase: ""  # Optional

extraVolumes:
  - name: ssl-certs
    secret:
      secretName: uptime-kuma-tls

extraVolumeMounts:
  - name: ssl-certs
    mountPath: /certs
    readOnly: true
```

### Ingress Configuration

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: uptime.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: uptime-kuma-tls
      hosts:
        - uptime.example.com
```

### WebSocket Configuration for Reverse Proxy

If using a reverse proxy, you may need to bypass WebSocket origin checks:

```yaml
uptimeKuma:
  security:
    wsOriginCheck: "bypass"  # Required for most reverse proxies
```

### Resource Limits

**Homelab/Small Deployment:**
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Production:**
```yaml
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 512Mi
```

## Persistent Storage

Uptime Kuma requires persistent storage for:
- SQLite database (if using SQLite)
- Configuration and certificates
- Status page data

**Important:** NFS is NOT supported. Use local directories or cloud-native persistent volumes.

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # Use fast storage for SQLite
  accessMode: ReadWriteOnce
  size: 4Gi
```

## Monitoring Setup

After installation, configure monitors via the web UI:

1. **HTTP(s) Monitor**
   - URL: `https://example.com`
   - Check interval: 60 seconds
   - Retries: 3

2. **TCP Monitor**
   - Hostname: `database.internal`
   - Port: 5432

3. **Ping Monitor**
   - Hostname: `8.8.8.8`
   - Packet count: 3

4. **DNS Monitor**
   - Resolver: `8.8.8.8`
   - Record: `example.com`
   - Type: A

## Notification Services

Uptime Kuma supports 90+ notification providers. Configure via web UI:

**Popular Services:**
- Telegram: Bot token + Chat ID
- Discord: Webhook URL
- Slack: Webhook URL
- Email: SMTP settings
- PagerDuty: Integration key
- Webhook: Custom webhooks

## Status Pages

Create public status pages:

1. Go to "Status Pages" in web UI
2. Create new status page
3. Select monitors to display
4. Customize appearance
5. Publish (accessible at `/status/{slug}`)

## Operational Commands

This chart includes a comprehensive Makefile for day-2 operations:

```bash
# View logs and access shell
make -f make/ops/uptime-kuma.mk uk-logs
make -f make/ops/uptime-kuma.mk uk-shell

# Port forward to localhost:3001
make -f make/ops/uptime-kuma.mk uk-port-forward

# Health checks
make -f make/ops/uptime-kuma.mk uk-check-db
make -f make/ops/uptime-kuma.mk uk-check-storage

# Database management (SQLite)
make -f make/ops/uptime-kuma.mk uk-backup-sqlite
make -f make/ops/uptime-kuma.mk uk-restore-sqlite FILE=path/to/kuma.db

# User management
make -f make/ops/uptime-kuma.mk uk-reset-password

# System information
make -f make/ops/uptime-kuma.mk uk-version
make -f make/ops/uptime-kuma.mk uk-node-info
make -f make/ops/uptime-kuma.mk uk-get-settings

# Monitoring (API-based)
make -f make/ops/uptime-kuma.mk uk-list-monitors
make -f make/ops/uptime-kuma.mk uk-status-pages

# Operations
make -f make/ops/uptime-kuma.mk uk-restart
make -f make/ops/uptime-kuma.mk uk-scale REPLICAS=2

# Full help
make -f make/ops/uptime-kuma.mk help
```

## Troubleshooting

### WebSocket Connection Failed

**Symptom:** "WebSocket connection failed" error in browser

**Solution:**
```yaml
uptimeKuma:
  security:
    wsOriginCheck: "bypass"
```

Also ensure reverse proxy forwards WebSocket headers:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Database Lock Errors (SQLite)

**Symptom:** "database is locked" errors

**Solution:**
- Ensure `strategy.type: Recreate` (only one pod at a time)
- Use `accessMode: ReadWriteOnce` for PVC
- Consider migrating to MariaDB for multi-replica setup

### High Memory Usage

**Symptom:** Pod OOMKilled

**Solution:**
```yaml
resources:
  limits:
    memory: 1Gi  # Increase from default 512Mi
  requests:
    memory: 256Mi
```

### NFS Mount Errors

**Symptom:** Database corruption or mount errors

**Solution:**
- Uptime Kuma does NOT support NFS
- Use local storage or cloud-native PVs (EBS, PD, Azure Disk)
- For NFS environments, use MariaDB instead of SQLite

## Production Deployment

### High Availability (with MariaDB)

```yaml
uptimeKuma:
  database:
    type: "mariadb"
    mariadb:
      host: "mariadb-primary"
      password: "secure_password"

replicaCount: 2

podDisruptionBudget:
  enabled: true
  minAvailable: 1

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: uptime-kuma
          topologyKey: kubernetes.io/hostname
```

**Note:** SQLite does NOT support multiple replicas. Use MariaDB for HA.

### Network Security

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: production
      ports:
        - protocol: TCP
          port: 3001
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 3306  # MariaDB
        - protocol: TCP
          port: 443   # HTTPS monitors
```

### Monitoring with Prometheus

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
```

**Note:** Uptime Kuma does not expose Prometheus metrics by default. You may need to configure external exporters or use Uptime Kuma's API.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `uptimeKuma.port` | int | `3001` | Application port |
| `uptimeKuma.database.type` | string | `"sqlite"` | Database type (sqlite or mariadb) |
| `uptimeKuma.database.mariadb.host` | string | `""` | MariaDB host (required if type=mariadb) |
| `uptimeKuma.database.mariadb.password` | string | `""` | MariaDB password (required if type=mariadb) |
| `persistence.enabled` | bool | `true` | Enable persistent storage |
| `persistence.size` | string | `"4Gi"` | Storage size |
| `ingress.enabled` | bool | `false` | Enable ingress |
| `resources.limits.memory` | string | `"512Mi"` | Memory limit |

For full configuration options, see [values.yaml](./values.yaml).

## Migration from Other Deployments

### From Docker to Kubernetes

1. Export data from Docker volume:
```bash
docker cp uptime-kuma:/app/data ./backup-data/
```

2. Create PVC and copy data:
```bash
helm install uptime-kuma ./charts/uptime-kuma
kubectl cp ./backup-data/kuma.db uptime-kuma-0:/app/data/
kubectl rollout restart deployment/uptime-kuma
```

### From SQLite to MariaDB

Uptime Kuma does not provide automatic migration. You'll need to:
1. Export monitors configuration (backup)
2. Deploy with MariaDB
3. Manually recreate monitors

## Architecture Notes

- **Single Container**: Uptime Kuma runs as a single Node.js application
- **No Separate Workers**: Background jobs run within the same process
- **Embedded Database**: SQLite is embedded, no separate database pod needed
- **Stateless with MariaDB**: With external database, the pod becomes stateless (except for temp files)

## License

Uptime Kuma is licensed under the [MIT License](https://github.com/louislam/uptime-kuma/blob/master/LICENSE).

This Helm chart is licensed under BSD-3-Clause.

## Resources

- Official Website: https://uptime.kuma.pet
- Documentation: https://github.com/louislam/uptime-kuma/wiki
- GitHub: https://github.com/louislam/uptime-kuma
- Docker Hub: https://hub.docker.com/r/louislam/uptime-kuma
- Demo: https://demo.uptime.kuma.pet
