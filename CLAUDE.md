# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScriptonBasestar Helm Charts - Personal server Helm charts focused on simplicity and configuration file preservation.

**Core Philosophy:**
- Prefer configuration files over environment variables
- Avoid subchart complexity - external databases (PostgreSQL, MySQL, Redis) are separate
- Use simple Docker images where available; create custom images when needed
- Configuration files should be used as-is, not translated through complex Helm abstractions

**Development Guide:**
- See [docs/CHART_DEVELOPMENT_GUIDE.md](docs/CHART_DEVELOPMENT_GUIDE.md) for comprehensive chart development patterns and standards
- All new charts MUST follow the standard structure and patterns defined in the guide
- Existing charts should be updated to align with these patterns over time

## Chart Structure

Each chart follows a consistent structure:
```
charts/{chart-name}/
├── Chart.yaml
├── values.yaml
├── values-example.yaml (production-ready examples)
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml (configuration files)
    ├── secret.yaml
    ├── pvc.yaml
    ├── serviceaccount.yaml
    ├── hpa.yaml (optional)
    ├── cronjob.yaml (optional)
    └── tests/
```

## Available Charts

### Application Charts (Self-Hosted)

- **keycloak**: IAM solution (StatefulSet, PostgreSQL, clustering, realm management)
- **wordpress**: WordPress CMS (Deployment, MySQL, Apache)
- **nextcloud**: Nextcloud with LinuxServer.io image (Deployment, PostgreSQL, config-based)
- **wireguard**: VPN solution (Deployment, no database, UDP service, NET_ADMIN capabilities)
- **rustfs**: High-performance S3-compatible object storage (StatefulSet, tiered storage, clustering)
- **rsshub**: RSS aggregator (well-maintained external chart available)
- **browserless-chrome**: Headless browser for crawling
- **devpi**: Python package index
- **jellyfin**: Media server with hardware transcoding support
- **vaultwarden**: Bitwarden-compatible password manager
- **immich**: AI-powered photo and video management

### Infrastructure Charts (Dev/Test - Consider Operators for Production)

- **redis**: In-memory data store (StatefulSet, no external database, full redis.conf support)
  - ⚠️ For production HA, consider [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)
  - See [docs/03-redis-operator-migration.md](docs/03-redis-operator-migration.md)
- **memcached**: High-performance distributed memory caching system (Deployment, no database)
  - ⚠️ For production, consider [Memcached Operator](https://github.com/ianlewis/memcached-operator)
- **rabbitmq**: Message broker with management UI (Deployment, no database, AMQP + Prometheus metrics)
  - ⚠️ For production clustering, consider [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)

## Common Development Commands

### Working with All Charts

```bash
# Lint all charts
make lint

# Build/package all charts
make build

# Generate templates for all charts
make template

# Install all charts
make install

# Upgrade all charts
make upgrade

# Uninstall all charts
make uninstall

# Update dependencies for all charts
make dependency-update
```

### Working with Individual Charts

Each chart has operational commands in `make/ops/{chart-name}.mk`

```bash
# Work with specific chart (replace {chart} with: nextcloud, wordpress, etc.)
make -f make/ops/{chart}.mk lint
make -f make/ops/{chart}.mk build
make -f make/ops/{chart}.mk template
make -f make/ops/{chart}.mk install
make -f make/ops/{chart}.mk upgrade
make -f make/ops/{chart}.mk uninstall
```

### WordPress Specific Commands

```bash
# Run wp-cli command
make -f make/ops/wordpress.mk wp-cli CMD="plugin list"

# Install WordPress
make -f make/ops/wordpress.mk wp-install \
  URL=https://example.com \
  TITLE="My Site" \
  ADMIN_USER=admin \
  ADMIN_PASSWORD=secure_pass \
  ADMIN_EMAIL=admin@example.com

# Update WordPress core, plugins, and themes
make -f make/ops/wordpress.mk wp-update
```

### Keycloak Specific Commands

```bash
# Backup all realms to tmp/keycloak-backups/
make -f make/ops/keycloak.mk kc-backup-all-realms

# Import realm from file
make -f make/ops/keycloak.mk kc-import-realm FILE=realm.json

# List all realms
make -f make/ops/keycloak.mk kc-list-realms

# Open shell in Keycloak pod
make -f make/ops/keycloak.mk kc-pod-shell

# Test PostgreSQL connection
make -f make/ops/keycloak.mk kc-db-test

# Run kcadm.sh command
make -f make/ops/keycloak.mk kc-cli CMD="get realms"

# Check cluster status
make -f make/ops/keycloak.mk kc-cluster-status

# Fetch Prometheus metrics
make -f make/ops/keycloak.mk kc-metrics
```

### WireGuard Specific Commands

```bash
# Show WireGuard status
make -f make/ops/wireguard.mk wg-show

# Get server public key
make -f make/ops/wireguard.mk wg-pubkey

# Get peer configuration (auto mode)
make -f make/ops/wireguard.mk wg-get-peer PEER=peer1

# List all peers (auto mode)
make -f make/ops/wireguard.mk wg-list-peers

# Display QR code for mobile (auto mode)
make -f make/ops/wireguard.mk wg-qr PEER=peer1

# Show current wg0.conf
make -f make/ops/wireguard.mk wg-config

# Get service endpoint (LoadBalancer IP or NodePort)
make -f make/ops/wireguard.mk wg-endpoint

# Restart WireGuard
make -f make/ops/wireguard.mk wg-restart

# View logs
make -f make/ops/wireguard.mk wg-logs

# Open shell
make -f make/ops/wireguard.mk wg-shell
```

### RabbitMQ Specific Commands

```bash
# Check cluster status
make -f make/ops/rabbitmq.mk rmq-status

# Check node health
make -f make/ops/rabbitmq.mk rmq-node-health

# List queues, exchanges, connections
make -f make/ops/rabbitmq.mk rmq-list-queues
make -f make/ops/rabbitmq.mk rmq-list-exchanges
make -f make/ops/rabbitmq.mk rmq-list-connections

# User management
make -f make/ops/rabbitmq.mk rmq-add-user USER=myuser PASSWORD=mypass
make -f make/ops/rabbitmq.mk rmq-set-user-tags USER=myuser TAGS=administrator
make -f make/ops/rabbitmq.mk rmq-set-permissions VHOST=/ USER=myuser
make -f make/ops/rabbitmq.mk rmq-list-users

# Virtual host management
make -f make/ops/rabbitmq.mk rmq-add-vhost VHOST=/my-vhost
make -f make/ops/rabbitmq.mk rmq-list-vhosts

# Access credentials
make -f make/ops/rabbitmq.mk rmq-get-credentials

# Port-forward services
make -f make/ops/rabbitmq.mk rmq-port-forward-ui        # Management UI (15672)
make -f make/ops/rabbitmq.mk rmq-port-forward-amqp      # AMQP (5672)
make -f make/ops/rabbitmq.mk rmq-port-forward-metrics   # Prometheus metrics (15692)

# Metrics and monitoring
make -f make/ops/rabbitmq.mk rmq-metrics

# Shell and logs
make -f make/ops/rabbitmq.mk rmq-shell
make -f make/ops/rabbitmq.mk rmq-logs

# Restart deployment
make -f make/ops/rabbitmq.mk rmq-restart
```

### Memcached Specific Commands

```bash
# Show memcached statistics
make -f make/ops/memcached.mk mc-stats

# Flush all data (WARNING: clears all cached data)
make -f make/ops/memcached.mk mc-flush

# Show memcached version
make -f make/ops/memcached.mk mc-version

# Show memcached settings
make -f make/ops/memcached.mk mc-settings

# Show slab statistics
make -f make/ops/memcached.mk mc-slabs

# Show item statistics
make -f make/ops/memcached.mk mc-items

# View logs
make -f make/ops/memcached.mk mc-logs

# Open shell
make -f make/ops/memcached.mk mc-shell

# Port forward to memcached
make -f make/ops/memcached.mk mc-port-forward
```

### Redis Specific Commands

```bash
# Ping Redis server
make -f make/ops/redis.mk redis-ping

# Get server info
make -f make/ops/redis.mk redis-info

# Monitor commands in real-time
make -f make/ops/redis.mk redis-monitor

# Check memory usage
make -f make/ops/redis.mk redis-memory

# Get statistics
make -f make/ops/redis.mk redis-stats

# List client connections
make -f make/ops/redis.mk redis-clients

# Data management
make -f make/ops/redis.mk redis-bgsave           # Trigger background save
make -f make/ops/redis.mk redis-backup           # Backup to tmp/redis-backups/
make -f make/ops/redis.mk redis-restore FILE=... # Restore from backup

# Analysis
make -f make/ops/redis.mk redis-slowlog          # Get slow query log
make -f make/ops/redis.mk redis-bigkeys          # Find biggest keys
make -f make/ops/redis.mk redis-config-get PARAM=maxmemory

# Run redis-cli command
make -f make/ops/redis.mk redis-cli CMD="get mykey"

# Open shell
make -f make/ops/redis.mk redis-shell

# View logs
make -f make/ops/redis.mk redis-logs
```

### RustFS Specific Commands

```bash
# Get RustFS credentials
make -f Makefile.rustfs.mk rustfs-get-credentials

# Port forward services
make -f Makefile.rustfs.mk rustfs-port-forward-api      # S3 API (9000)
make -f Makefile.rustfs.mk rustfs-port-forward-console  # Console (9001)

# Test S3 API (requires MinIO Client 'mc')
make -f Makefile.rustfs.mk rustfs-test-s3

# Health and metrics
make -f Makefile.rustfs.mk rustfs-health
make -f Makefile.rustfs.mk rustfs-metrics

# View logs and shell
make -f Makefile.rustfs.mk rustfs-logs
make -f Makefile.rustfs.mk rustfs-shell

# Scale cluster
make -f Makefile.rustfs.mk rustfs-scale REPLICAS=6

# Backup (requires VolumeSnapshot CRD)
make -f Makefile.rustfs.mk rustfs-backup

# View all resources
make -f Makefile.rustfs.mk rustfs-all

# Install variants
make -f Makefile.rustfs.mk install-homeserver  # Home server config
make -f Makefile.rustfs.mk install-startup     # Production config
```

### Kind (Local Testing)

```bash
# Create local Kubernetes cluster
make kind-create

# Delete local cluster
make kind-delete

# Cluster name: sb-helm-charts (defined in KIND_CLUSTER_NAME)
# Config: kind-config.yaml
```

## Chart Testing

The repository uses chart-testing (ct) for validation:
- Config: `ct.yaml`
- Timeout: 600s for chart operations
- Chart directory: `charts/`

## Architecture Principles

### Configuration Management

**DO:**
- Use ConfigMaps to mount entire configuration files (e.g., `config.php`, `wp-config.php`)
- Keep application configurations close to their original format
- Use Secrets for sensitive data (passwords, API keys)
- Reference external services (databases) via values

**DON'T:**
- Create complex environment variable mappings
- Try to abstract away application-specific configuration
- Include database charts as subcharts

### Database Strategy

All charts expect **external** databases:

- **keycloak**: External PostgreSQL 13+ (required for Keycloak 26.x), Redis 6+ (optional)
  - Supports SSL/TLS connections: `disable`, `require`, `verify-ca`, `verify-full`
  - Supports mutual TLS (mTLS) with client certificates
  - Health endpoints use management port 9000 (Keycloak 26.x breaking change)
- **nextcloud**: External PostgreSQL 16 + Redis 8
- **wordpress**: External MySQL/MariaDB
- **wireguard**: No database required (first chart without database dependency)
- **devpi**: Can use built-in SQLite or external PostgreSQL

Configure via `values.yaml`:
```yaml
postgresql:
  enabled: false  # ALWAYS false - never auto-install
  external:
    enabled: true
    host: "postgres-service.default.svc.cluster.local"
    port: 5432
    database: "nextcloud"
    username: "nextcloud"
    password: ""  # Required - deployment will fail if empty
    # SSL/TLS support (Keycloak chart)
    ssl:
      enabled: false
      mode: "require"  # disable, require, verify-ca, verify-full
      certificateSecret: ""  # Required for verify-ca/verify-full
      rootCertKey: "ca.crt"
      clientCertKey: ""  # Optional: for mutual TLS
      clientKeyKey: ""   # Optional: for mutual TLS
```

**CRITICAL**: The `enabled: false` pattern is a core project value. Never suggest installing databases as subcharts.

**PostgreSQL SSL Notes (Keycloak):**
- PostgreSQL JDBC driver uses different parameters than psql CLI
- `require` mode: Uses `ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory`
- `verify-ca`/`verify-full`: Uses `sslmode=verify-ca` or `sslmode=verify-full` with certificate paths
- InitContainer health checks support SSL via `PGSSLMODE` environment variable
- Client certificates (mTLS) must have empty default values to avoid always being included

### Storage

Charts use PersistentVolumeClaims for data persistence:

- **keycloak**: StatefulSet with `volumeClaimTemplates` for each pod
- **nextcloud**: `/data` (user files), `/config` (Nextcloud config)
- **wordpress**: `/var/www/html` (WordPress files)

Default: `ReadWriteOnce` with `Retain` reclaim policy for production safety.

## Values File Patterns

### Standard Structure

```yaml
# Application-specific config
{app}:
  adminUser: "admin"
  adminPassword: ""  # Required

# External services (disabled subcharts)
postgresql:
  enabled: false
  external:
    enabled: true
    host: ""
    database: ""
    username: ""
    password: ""

# Persistence
persistence:
  enabled: true
  storageClass: ""
  size: "10Gi"
  accessMode: ReadWriteOnce

# Standard k8s resources
replicaCount: 1
image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent

resources:
  limits:
    cpu: "1000m"
    memory: "1Gi"
  requests:
    cpu: "100m"
    memory: "128Mi"

ingress:
  enabled: false
  className: ""
  hosts: []
  tls: []
```

### Production Examples

Check `values-example.yaml` in each chart for production-ready configurations.

### Home Server / Low-Resource Configurations

Some charts include optimized configurations for home servers and low-resource environments:

- **WordPress**: `values-homeserver.yaml` provides:
  - 50% resource reduction (500m CPU, 512Mi RAM limits)
  - Reduced storage (5Gi default)
  - PHP memory optimizations (256M/512M limits)
  - Security hardening (file editing disabled, auto-updates disabled)
  - Reduced post revisions (5) and autosave interval (5 minutes)
  - Suitable for Raspberry Pi 4, Intel NUC, or small VPS

## Git Workflow

**Main branch:** `master` (use for PRs)
**Current branch:** `develop`

## CI/CD

GitHub Actions workflows:
- `release.yaml`: Automated chart releases using Helm chart-releaser
- `cleanup.yaml`: Maintenance tasks

## Chart Release Process

Charts are automatically released via GitHub Actions when changes are pushed to main branch. Packaged charts are available at:
- Repository: `https://scriptonbasestar-docker.github.io/sb-helm-charts`

Add to Helm:
```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

## Production Features (Recent Charts)

Modern charts (WordPress, Nextcloud, Keycloak) include production-ready features:

### High Availability

- **PodDisruptionBudget**: `minAvailable` or `maxUnavailable` settings for maintenance windows
- **HorizontalPodAutoscaler**: CPU/memory-based auto-scaling
- **Clustering**: JGroups + DNS_PING for Keycloak distributed cache

### Security

- **NetworkPolicy**: Ingress/egress rules for database and inter-pod communication
- **RBAC**: ServiceAccount with minimal required permissions
- **Secret Management**: Separate secrets for database credentials, admin passwords

### Reliability

- **InitContainers**: Database health checks (e.g., `pg_isready`) before app startup
- **Health Probes**: Liveness, readiness, and startup probes configured per application
- **Resource Limits**: Memory/CPU requests and limits to prevent resource starvation

### Observability

- **ServiceMonitor**: Prometheus Operator CRD for metrics scraping
- **Metrics Endpoints**: Application-specific metrics exposed (e.g., `/metrics`, `/q/metrics`)
- **Structured Logging**: Logs written to stdout for Kubernetes log aggregation

## Chart Versioning

All charts use:

- **Chart version**: `0.1.0` (initial development version)
- **License**: `BSD-3-Clause` (documented in `Chart.yaml`)
- **appVersion**: Matches the upstream Docker image version
- **sources**: Include both chart repository and upstream application repository

Application licenses differ from chart license (e.g., Keycloak: Apache 2.0) and are documented in README.md.

## Template Patterns

### StatefulSet vs Deployment

- **StatefulSet**: For stable network identity, ordered scaling (Keycloak clustering)
- **Deployment**: For stateless or externally-stored state (WordPress, Nextcloud)

### Helper Functions (_helpers.tpl)

Standard helpers in all charts:

```yaml
{{- define "{chart}.fullname" -}}
{{- define "{chart}.name" -}}
{{- define "{chart}.labels" -}}
{{- define "{chart}.selectorLabels" -}}
{{- define "{chart}.serviceAccountName" -}}
```

Chart-specific helpers for complex patterns:

```yaml
{{- define "keycloak.postgresql.jdbcUrl" -}}
{{- define "keycloak.headlessServiceName" -}}
```

**Important Notes on Keycloak Helpers:**
- `keycloak.postgresql.jdbcUrl` generates PostgreSQL JDBC URLs with proper SSL parameters
- Handles all SSL modes: `disable`, `require`, `verify-ca`, `verify-full`
- Automatically constructs certificate paths for mTLS when client certificates are provided
- Falls back to NonValidatingFactory if certificates are not provided in verify modes

### NOTES.txt Pattern

Post-install instructions should include:

1. **Access information**: Ingress URLs, port-forward commands
2. **Credential retrieval**: kubectl commands to decode secrets
3. **Feature-specific guidance**: Clustering status, metrics endpoints
4. **Production warnings**: External DB requirements, TLS recommendations

## Makefile Architecture

The hierarchical Makefile system:

```text
Makefile                     # Root orchestrator
├── Makefile.common.mk       # Base targets (lint, build, install)
└── Makefile.{chart}.mk      # Chart-specific operations
```

Each chart-specific Makefile:

1. Includes `Makefile.common.mk`
2. Defines `CHART_NAME` and `CHART_DIR`
3. Adds operational commands (wp-cli, kc-backup-all-realms, etc.)
4. Extends help output

## Important Notes

- Configuration files are king - preserve application's native config format
- Keep it simple - if Helm complexity exceeds application complexity, something is wrong
- External dependencies (databases) are ALWAYS separate installations
- Use `values-example.yaml` as production deployment templates
- Chart version follows semantic versioning in `Chart.yaml`
- Git commits are automated; `git push` requires manual execution

### Kubernetes Environment Variable Precedence

**CRITICAL**: When the same environment variable is defined multiple times in Kubernetes, the **first definition takes precedence**, not the last.

This means `extraEnv` in values.yaml **cannot override** chart-generated environment variables. For example:

```yaml
# Chart template generates:
- name: KC_DB_URL
  value: "jdbc:postgresql://..."

# extraEnv attempting override (THIS WILL NOT WORK):
extraEnv:
  - name: KC_DB_URL
    value: "my-custom-url"  # IGNORED - first definition wins
```

**Workaround**: To use custom database URLs or parameters not supported by the chart:
1. Disable auto-generation: `postgresql.external.enabled=false`
2. Manually configure all database env vars in `extraEnv`

### Keycloak 26.x Breaking Changes

- **Health endpoints**: Moved from port 8080 to port 9000 (management port)
  - Liveness: `http://localhost:9000/health/live`
  - Readiness: `http://localhost:9000/health/ready`
  - Startup: `http://localhost:9000/health/started`
- **Hostname v1**: Completely removed - must use hostname v2 configuration
- **PostgreSQL 13+**: Minimum requirement increased from 12.x
- **CLI-based clustering**: Use `--cache-embedded-network-*` CLI options instead of env vars
