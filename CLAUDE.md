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

- **nextcloud**: Nextcloud with LinuxServer.io image (config-based)
- **wordpress**: WordPress with official image
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
- **nextcloud**: External PostgreSQL 16 + Redis 8
- **wordpress**: External MySQL/MariaDB
- **devpi**: Can use built-in SQLite or external PostgreSQL

Configure via `values.yaml`:
```yaml
postgresql:
  enabled: false  # No subchart
  external:
    enabled: true
    host: "postgres-service.default.svc.cluster.local"
    database: "nextcloud"
    username: "nextcloud"
    password: "changeme"
```

### Storage

Charts use PersistentVolumeClaims for data persistence:
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

## Important Notes

- Configuration files are king - preserve application's native config format
- Keep it simple - if Helm complexity exceeds application complexity, something is wrong
- External dependencies (databases) are always separate installations
- Use `values-example.yaml` as production deployment templates
- Chart version follows semantic versioning in `Chart.yaml`
