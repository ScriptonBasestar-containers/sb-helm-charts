# ScriptonBasestar Helm Charts Repository

> Self-hosted application Helm charts focused on simplicity and configuration file preservation

[![Release Charts](https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions/workflows/release.yaml/badge.svg)](https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions/workflows/release.yaml)
[![Lint and Test](https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions/workflows/lint-test.yaml/badge.svg)](https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions/workflows/lint-test.yaml)

## Quick Start

```bash
# Add the repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts

# Update repository index
helm repo update

# Search available charts
helm search repo scripton-charts

# Install a chart
helm install my-release scripton-charts/<chart-name>
```

## Available Charts

### Application Charts (Self-Hosted)

| Chart | Description | Version | App Version |
|-------|-------------|---------|-------------|
| [browserless-chrome](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/browserless-chrome) | Headless Chrome for web scraping and automation | 0.2.0 | 1.61.1 |
| [devpi](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/devpi) | Python Package Index mirror and private server | 0.2.0 | 6.17.0 |
| [immich](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/immich) | AI-powered photo and video management | 0.1.0 | v1.122.3 |
| [jellyfin](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/jellyfin) | Free software media system (Plex alternative) | 0.1.0 | 10.10.3 |
| [keycloak](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/keycloak) | Identity and Access Management (IAM) | 0.3.0 | 26.0.6 |
| [nextcloud](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/nextcloud) | Self-hosted productivity platform | 0.1.0 | 31.0.10 |
| [paperless-ngx](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/paperless-ngx) | Document management with OCR | 0.1.0 | 2.14.3 |
| [rsshub](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/rsshub) | RSS feed generator for everything | 0.2.0 | 2025-11-09 |
| [rustfs](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/rustfs) | S3-compatible object storage (Rust) | 0.1.0 | latest |
| [uptime-kuma](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/uptime-kuma) | Monitoring with 90+ notification services | 0.1.0 | 2.0.2 |
| [vaultwarden](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/vaultwarden) | Bitwarden-compatible password manager | 0.1.0 | 1.32.5 |
| [wireguard](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/wireguard) | Fast, modern, secure VPN tunnel | 0.1.0 | latest |
| [wordpress](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/wordpress) | The world's most popular CMS | 0.1.0 | 6.4.3 |

### Infrastructure Charts (Dev/Test)

> ⚠️ For production high-availability, consider using Kubernetes Operators

| Chart | Description | Version | App Version | Production Alternative |
|-------|-------------|---------|-------------|----------------------|
| [memcached](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/memcached) | High-performance memory caching | 0.2.0 | 1.6.39 | [Memcached Operator](https://github.com/ianlewis/memcached-operator) |
| [rabbitmq](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/rabbitmq) | Message broker with management UI | 0.1.0 | 3.13.1 | [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator) |
| [redis](https://github.com/ScriptonBasestar-containers/sb-helm-charts/tree/master/charts/redis) | In-memory data structure store | 0.2.0 | 7.4.1 | [Spotahome Redis Operator](https://github.com/spotahome/redis-operator) |

## Chart Philosophy

### Core Principles

1. **Configuration Files Over Environment Variables**
   - Preserve application's native configuration format
   - Mount entire config files via ConfigMaps (e.g., `wp-config.php`, `redis.conf`)
   - Avoid complex environment variable mappings

2. **External Database Pattern**
   - All charts expect external databases (PostgreSQL, MySQL, Redis)
   - No subchart dependencies - keep it simple
   - Configure via `values.yaml` external database settings

3. **Production-Ready Features**
   - PodDisruptionBudget, HorizontalPodAutoscaler support
   - NetworkPolicy for isolation
   - Comprehensive health probes (liveness, readiness, startup)
   - ServiceMonitor for Prometheus integration

4. **Home Server Support**
   - `values-homeserver.yaml` configurations available
   - Optimized for Raspberry Pi, Intel NUC, small VPS
   - Reduced resource requirements for personal use

## Installation Examples

### Basic Installation

```bash
# Install WordPress with external MySQL
helm install wordpress scripton-charts/wordpress \
  --set mysql.external.host=mysql.default.svc.cluster.local \
  --set mysql.external.database=wordpress \
  --set mysql.external.username=wordpress \
  --set mysql.external.password=secure_password
```

### Using Example Values

```bash
# Download example values file
curl -O https://raw.githubusercontent.com/ScriptonBasestar-containers/sb-helm-charts/master/charts/keycloak/values-example.yaml

# Install with custom values
helm install keycloak scripton-charts/keycloak \
  -f values-example.yaml
```

### Home Server Deployment

```bash
# Install Nextcloud with home server configuration
helm install nextcloud scripton-charts/nextcloud \
  -f https://raw.githubusercontent.com/ScriptonBasestar-containers/sb-helm-charts/master/charts/nextcloud/values-homeserver.yaml \
  --set postgresql.external.host=postgres.default.svc.cluster.local \
  --set postgresql.external.password=your_password \
  --set redis.external.host=redis.default.svc.cluster.local
```

## Publishing Locations

Charts are published to two locations:

1. **GitHub Pages** (Traditional Helm Repository)
   ```bash
   helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
   ```

2. **GHCR OCI Registry**
   ```bash
   helm install my-release oci://ghcr.io/scriptonbasestar-containers/charts/<chart-name>
   ```

## Chart Development

See [Chart Development Guide](https://github.com/ScriptonBasestar-containers/sb-helm-charts/blob/master/docs/CHART_DEVELOPMENT_GUIDE.md) for:
- Standard chart structure and patterns
- Template best practices
- Values file conventions
- Testing and validation

## Repository Structure

```
.
├── charts/                    # All Helm charts
│   ├── keycloak/             # Example chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-example.yaml
│   │   ├── values-homeserver.yaml
│   │   └── templates/
│   └── ...
├── docs/                      # Documentation
├── make/                      # Makefile operations
│   ├── ops/                  # Chart-specific makefiles
│   └── Makefile.common.mk    # Shared targets
└── .github/workflows/         # CI/CD automation
```

## Common Operations

### Repository Commands

```bash
# Search all charts
helm search repo scripton-charts

# Show chart information
helm show chart scripton-charts/keycloak

# Show chart values
helm show values scripton-charts/nextcloud

# Show chart README
helm show readme scripton-charts/wordpress
```

### Installation and Management

```bash
# Install with custom name
helm install my-app scripton-charts/uptime-kuma

# Install in specific namespace
helm install my-app scripton-charts/immich -n media --create-namespace

# Upgrade existing release
helm upgrade my-app scripton-charts/uptime-kuma

# Uninstall release
helm uninstall my-app
```

## Database Setup

Most charts require external databases. Quick setup examples:

### PostgreSQL (for Keycloak, Nextcloud, Paperless-ngx, Immich)

```bash
# Using Bitnami PostgreSQL chart
helm install postgres bitnami/postgresql \
  --set auth.database=mydb \
  --set auth.username=myuser \
  --set auth.password=mypassword

# Service: postgres-postgresql.default.svc.cluster.local:5432
```

### MySQL/MariaDB (for WordPress)

```bash
# Using Bitnami MariaDB chart
helm install mysql bitnami/mariadb \
  --set auth.database=wordpress \
  --set auth.username=wordpress \
  --set auth.password=secure_password

# Service: mysql-mariadb.default.svc.cluster.local:3306
```

### Redis (for Nextcloud, Immich, Paperless-ngx)

```bash
# Using Bitnami Redis chart
helm install redis bitnami/redis \
  --set auth.password=redis_password

# Service: redis-master.default.svc.cluster.local:6379
```

## Chart-Specific Features

### Keycloak
- JGroups clustering support with DNS_PING
- PostgreSQL SSL/TLS support (including mutual TLS)
- Redis session caching (optional)
- Realm import/export operations
- Prometheus metrics endpoint

### WordPress
- WP-CLI integration for management
- Automated installation support
- PHP memory optimization
- Security hardening (file editing disabled)
- Home server optimized configuration

### RustFS
- S3-compatible object storage
- High-performance Rust implementation
- Tiered storage support (hot/cold)
- Migration from MinIO/Ceph support
- StatefulSet with clustering

### Paperless-ngx
- 4-PVC architecture (consume, data, media, export)
- OCR with multiple language support
- PostgreSQL + Redis backend
- Document import/export operations
- Full-text search capabilities

### Uptime-kuma
- 90+ notification service integrations
- Beautiful status page UI
- SQLite or MariaDB backend
- Multi-language support
- Docker container monitoring

## Support and Contributing

- **Issues**: [GitHub Issues](https://github.com/ScriptonBasestar-containers/sb-helm-charts/issues)
- **Source**: [GitHub Repository](https://github.com/ScriptonBasestar-containers/sb-helm-charts)
- **License**: BSD-3-Clause

## Version Policy

All charts follow [Semantic Versioning](https://semver.org/):

- **Chart version**: Independent versioning for Helm chart itself
- **appVersion**: Upstream application version
- See [Chart Version Policy](https://github.com/ScriptonBasestar-containers/sb-helm-charts/blob/master/docs/CHART_VERSION_POLICY.md) for details

## Artifact Hub

Find our charts on [Artifact Hub](https://artifacthub.io/packages/search?org=scriptonbasestar-containers) for:
- Enhanced search and discovery
- Version history and changelogs
- Security scanning results
- Community ratings and feedback

---

**Maintained by**: [ScriptonBasestar](https://github.com/ScriptonBasestar-containers)

**Chart Repository**: https://scriptonbasestar-container.github.io/sb-helm-charts
