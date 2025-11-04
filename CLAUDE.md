# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScriptonBasestar Helm Charts - Personal server Helm charts focused on simplicity and configuration file preservation.

**Core Philosophy:**
- Prefer configuration files over environment variables
- Avoid subchart complexity - external databases (PostgreSQL, MySQL, Redis) are separate
- Use simple Docker images where available; create custom images when needed
- Configuration files should be used as-is, not translated through complex Helm abstractions

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

- **keycloak**: IAM solution (StatefulSet, PostgreSQL, clustering, realm management)
- **wordpress**: WordPress CMS (Deployment, MySQL, Apache)
- **nextcloud**: Nextcloud with LinuxServer.io image (Deployment, PostgreSQL, config-based)
- **wireguard**: VPN solution (Deployment, no database, UDP service, NET_ADMIN capabilities)
- **rsshub**: RSS aggregator (well-maintained external chart available)
- **browserless-chrome**: Headless browser for crawling
- **devpi**: Python package index

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

Each chart has its own Makefile: `Makefile.{chart-name}.mk`

```bash
# Work with specific chart (replace {chart} with: nextcloud, wordpress, etc.)
make -f Makefile.{chart}.mk lint
make -f Makefile.{chart}.mk build
make -f Makefile.{chart}.mk template
make -f Makefile.{chart}.mk install
make -f Makefile.{chart}.mk upgrade
make -f Makefile.{chart}.mk uninstall
```

### WordPress Specific Commands

```bash
# Run wp-cli command
make -f Makefile.wordpress.mk wp-cli CMD="plugin list"

# Install WordPress
make -f Makefile.wordpress.mk wp-install \
  URL=https://example.com \
  TITLE="My Site" \
  ADMIN_USER=admin \
  ADMIN_PASSWORD=secure_pass \
  ADMIN_EMAIL=admin@example.com

# Update WordPress core, plugins, and themes
make -f Makefile.wordpress.mk wp-update
```

### Keycloak Specific Commands

```bash
# Backup all realms to tmp/keycloak-backups/
make -f Makefile.keycloak.mk kc-backup-all-realms

# Import realm from file
make -f Makefile.keycloak.mk kc-import-realm FILE=realm.json

# List all realms
make -f Makefile.keycloak.mk kc-list-realms

# Open shell in Keycloak pod
make -f Makefile.keycloak.mk kc-pod-shell

# Test PostgreSQL connection
make -f Makefile.keycloak.mk kc-db-test

# Run kcadm.sh command
make -f Makefile.keycloak.mk kc-cli CMD="get realms"

# Check cluster status
make -f Makefile.keycloak.mk kc-cluster-status

# Fetch Prometheus metrics
make -f Makefile.keycloak.mk kc-metrics
```

### WireGuard Specific Commands

```bash
# Show WireGuard status
make -f Makefile.wireguard.mk wg-show

# Get server public key
make -f Makefile.wireguard.mk wg-pubkey

# Get peer configuration (auto mode)
make -f Makefile.wireguard.mk wg-get-peer PEER=peer1

# List all peers (auto mode)
make -f Makefile.wireguard.mk wg-list-peers

# Display QR code for mobile (auto mode)
make -f Makefile.wireguard.mk wg-qr PEER=peer1

# Show current wg0.conf
make -f Makefile.wireguard.mk wg-config

# Get service endpoint (LoadBalancer IP or NodePort)
make -f Makefile.wireguard.mk wg-endpoint

# Restart WireGuard
make -f Makefile.wireguard.mk wg-restart

# View logs
make -f Makefile.wireguard.mk wg-logs

# Open shell
make -f Makefile.wireguard.mk wg-shell
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

- **keycloak**: External PostgreSQL 12+ (required), Redis 6+ (optional)
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
```

**CRITICAL**: The `enabled: false` pattern is a core project value. Never suggest installing databases as subcharts.

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
