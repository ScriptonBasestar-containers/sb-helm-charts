# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Vaultwarden 0.3.0 - Production-Ready Password Manager
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - Auto-switching workload type (StatefulSet for SQLite, Deployment for external DB)
  - Complete Makefile operational commands
- **Backup & Restore** (`make/ops/vaultwarden.mk`)
  - `vw-backup-db`: Backup SQLite database to tmp/vaultwarden-backups/
  - `vw-restore-db`: Restore SQLite database from backup
  - `vw-db-test`: Test external database connection (PostgreSQL/MySQL)
- **Admin Panel Management**
  - `vw-get-admin-token`: Retrieve admin panel token
  - `vw-admin`: Open admin panel in browser
  - `vw-get-config`: Show current configuration
- **Database Mode Support**
  - SQLite (embedded) mode: StatefulSet with PVC
  - PostgreSQL/MySQL mode: Deployment (stateless)
  - Automatic workload type selection based on database configuration
- **Security Features**
  - Admin token management
  - SMTP password retrieval (vw-get-smtp-password)
  - Database URL encryption
- **Comprehensive Documentation** (`README.md`)
  - Bitwarden feature comparison
  - Deployment scenarios (home server, startup, production)
  - Database mode switching guide
  - Admin panel security guide
  - Operational commands reference

#### Jellyfin 0.3.0 - Complete GPU Acceleration Support
- **AMD VAAPI GPU Support** (New)
  - Added AMD VAAPI hardware acceleration alongside Intel QSV and NVIDIA NVENC
  - Automatic `/dev/dri` device mounting for AMD GPUs
  - Automatic supplementalGroups (44, 109) for AMD VAAPI
  - Updated deployment.yaml, _helpers.tpl, and values.yaml
- **Home Server Configuration** (`values-home-single.yaml`)
  - Optimized for Raspberry Pi 4, Intel NUC, and Mini PCs
  - Minimal resources: 2 CPU cores, 2Gi RAM
  - Reduced storage: 2Gi config, 5Gi cache
  - hostPath media directories with NAS mount examples
  - Intel QSV GPU acceleration examples
  - Relaxed health checks for home server use
- **Comprehensive Documentation** (`README.md`)
  - Complete GPU acceleration guide for all vendors (Intel QSV, NVIDIA NVENC, AMD VAAPI)
  - Media library configuration guide (hostPath, PVC, existing claims)
  - Deployment scenarios (home server, startup, production)
  - Operational commands reference
  - Troubleshooting guide for GPU and media library issues
- **Enhanced Makefile Operations** (`make/ops/jellyfin.mk`)
  - Updated `jellyfin-check-gpu` command to support AMD VAAPI
  - Added renderD* device listing for debugging
  - Consolidated Intel/AMD GPU check logic

#### Chart Metadata Management System
- **Centralized Metadata** (`charts-metadata.yaml`)
  - Single source of truth for chart keywords, tags, descriptions
  - 16 charts documented with complete metadata
  - Categories: `application` and `infrastructure`
  - Searchable keywords for Artifact Hub integration
- **Automation Scripts**
  - `scripts/validate-chart-metadata.py` - Validates keywords consistency
  - `scripts/sync-chart-keywords.py` - Syncs Chart.yaml keywords from metadata
  - `scripts/generate-chart-catalog.py` - Generates comprehensive chart catalog
  - `scripts/generate-artifacthub-dashboard.py` - Generates Artifact Hub statistics dashboard
  - `scripts/requirements.txt` - Python dependencies (PyYAML>=6.0)
- **Makefile Targets**
  - `make validate-metadata` - Validate metadata consistency
  - `make sync-keywords` - Sync Chart.yaml keywords
  - `make sync-keywords-dry-run` - Preview sync changes
  - `make generate-catalog` - Generate docs/CHARTS.md from metadata
  - `make generate-artifacthub-dashboard` - Generate Artifact Hub dashboard
- **Pre-commit Hooks** (Enhanced)
  - Automatic metadata validation before commits
  - Validates Chart.yaml and charts-metadata.yaml consistency
  - Fixed configuration (removed unsupported additional_dependencies from system language hook)
  - Trailing whitespace and end-of-file auto-fixes applied
  - Conventional commits enforcement
  - YAML, Markdown, and Shell script linting
- **CI/CD Automation** (Ready for deployment)
  - Metadata validation job for GitHub Actions (manual application pending)
  - Catalog verification to ensure docs/CHARTS.md is up-to-date
  - Workflow triggers for metadata and scripts changes
  - See `WORKFLOW_MANUAL_APPLY.md` for deployment instructions
- **Artifact Hub Integration**
  - `artifacthub-repo.yml` - Repository metadata for Artifact Hub
  - Container image security scanning configuration
  - Repository links and maintainer information
  - Ready for Artifact Hub publishing (requires GitHub Pages)
- **Documentation**
  - [Chart Catalog](docs/CHARTS.md) - Auto-generated catalog of all 16 charts with badges and examples
  - [Artifact Hub Dashboard](docs/ARTIFACTHUB_DASHBOARD.md) - Artifact Hub statistics and publishing guide
  - [Chart README Template](docs/CHART_README_TEMPLATE.md) - Standard chart README structure
  - [Chart README Guide](docs/CHART_README_GUIDE.md) - Template usage guide
  - [Workflow Update Instructions](docs/WORKFLOW_UPDATE_INSTRUCTIONS.md) - CI workflow manual update
  - `WORKFLOW_MANUAL_APPLY.md` - Step-by-step guide for workflow deployment
  - Updated CLAUDE.md with metadata management workflow and catalog generation
  - Updated CONTRIBUTING.md with metadata workflow steps
  - Updated README.md with Available Charts section and catalog links

#### Development Tools
- Deployment Scenarios sections to all 16 chart READMEs
  - Home Server scenario (minimal resources)
  - Startup Environment scenario (balanced configuration)
  - Production HA scenario (high availability with monitoring)
- Artifact Hub metadata to all charts (16 charts total)
  - v0.3.0 charts (7 charts): keycloak, wireguard, memcached, rabbitmq, browserless-chrome, devpi, rsshub
  - v0.2.0 charts (9 charts): redis, rustfs, immich, jellyfin, vaultwarden, nextcloud, wordpress, paperless-ngx, uptime-kuma
  - Detailed changelog entries (`artifacthub.io/changes`)
  - Recommendations to Scenario Values Guide and Chart Development Guide
  - Links to chart source and upstream documentation
- Recent Changes section in main README.md
  - Highlights v0.3.0 release features
  - Links to CHANGELOG.md for complete version history
- `.gitattributes` file for Git optimization
  - Normalized line endings (LF)
  - Enhanced diff drivers for YAML, JSON, Markdown
  - Export-ignore for development files
- `.pre-commit-config.yaml` for code quality automation
  - General file checks (trailing whitespace, EOF, YAML validation)
  - YAML linting with yamllint (line-length: 120)
  - Helm chart linting for all charts
  - Chart metadata validation (NEW)
  - Markdown linting with markdownlint
  - Shell script linting with shellcheck
  - Conventional commits enforcement
  - CI auto-fix and auto-update configuration
- `.github/CONTRIBUTING.md` comprehensive contribution guide
  - Code of Conduct and Getting Started
  - Chart Development Guidelines (core principles, values.yaml structure, database strategy)
  - Chart Metadata Workflow (4-step process with sync and validation)
  - Pull Request Process and checklist
  - Coding Standards (Helm templates, helper functions, NOTES.txt pattern)
  - Testing Requirements (lint, template rendering, install/upgrade tests)
  - Documentation Standards (README, CHANGELOG, Artifact Hub annotations)

## [0.3.0] - 2025-11-16

### Added
- **Scenario Values Files**: Pre-configured deployment scenarios for all charts
  - `values-home-single.yaml` - Minimal resources for personal servers (Raspberry Pi, NUC, home labs)
  - `values-startup-single.yaml` - Balanced configuration for small teams and startups
  - `values-prod-master-replica.yaml` - High availability with clustering, monitoring, and auto-scaling
- **Documentation**:
  - Comprehensive [Scenario Values Guide](docs/SCENARIO_VALUES_GUIDE.md) with deployment examples
  - [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md) scenario testing section
  - Deployment Scenarios section in main README.md
- **CI/CD**:
  - Scenario file validation in GitHub Actions workflow
  - Automated linting for all scenario values files
- **Makefile Targets**:
  - `install-home`, `install-startup`, `install-prod` for scenario-based deployments
  - `validate-scenarios` and `list-scenarios` for scenario management

### Changed
- **Chart Versions** (MINOR bump for new features):
  - keycloak: 0.2.0 → 0.3.0
  - redis: 0.2.0 → 0.3.0
  - memcached: 0.2.0 → 0.3.0
  - rabbitmq: 0.2.0 → 0.3.0
  - wireguard: 0.2.0 → 0.3.0
  - browserless-chrome: 0.2.0 → 0.3.0
  - devpi: 0.2.0 → 0.3.0
  - rsshub: 0.2.0 → 0.3.0
  - rustfs: 0.2.0 → 0.3.0

### Details

**Charts with Scenario Files (Total: 18 scenario files across 16 charts)**:

| Chart | home-single | startup-single | prod-master-replica |
|-------|-------------|----------------|---------------------|
| browserless-chrome | ✅ | ✅ | ✅ |
| devpi | ✅ | ✅ | ✅ |
| immich | ✅ | ✅ | ✅ |
| jellyfin | ✅ | ✅ | ✅ |
| keycloak | ✅ | ✅ | ✅ |
| memcached | ✅ | ✅ | ✅ |
| nextcloud | ✅ | ✅ | ✅ |
| paperless-ngx | ✅ | ✅ | ✅ |
| rabbitmq | ✅ | ✅ | ✅ |
| redis | ✅ | ✅ | ✅ |
| rsshub | ✅ | ✅ | ✅ |
| rustfs | ✅ | ✅ | ✅ |
| uptime-kuma | ✅ | ✅ | ✅ |
| vaultwarden | ✅ | ✅ | ✅ |
| wireguard | ✅ | ✅ | ✅ |
| wordpress | ✅ | ✅ | ✅ |

**Resource Allocation Philosophy**:
- **Home Server**: 50-500m CPU, 128Mi-512Mi RAM - Optimized for edge devices
- **Startup Environment**: 100m-1000m CPU, 256Mi-1Gi RAM - Balanced for teams
- **Production HA**: 250m-2000m CPU, 512Mi-2Gi RAM - Enterprise-ready with scaling

## [0.2.0] - 2025-11-16

### Added
- Version bumps for charts transitioning from development (0.1.0) to beta (0.2.0)
  - nextcloud: 0.1.0 → 0.2.0
  - paperless-ngx: 0.1.0 → 0.2.0
  - uptime-kuma: 0.1.0 → 0.2.0
  - wordpress: 0.1.0 → 0.2.0

### Changed
- Aligned chart versions to reflect feature completeness and scenario values support

## [0.1.0] - Initial Releases

### Charts in Development (0.1.0)
- immich
- jellyfin
- vaultwarden

### Stable Charts (0.2.0+)
- keycloak: 0.3.0 (Keycloak 26.0.6, PostgreSQL 13+, Redis support, clustering)
- redis: 0.3.0 (Redis 7.4.1, master-replica replication, Prometheus metrics)
- wireguard: 0.3.0 (WireGuard VPN, no external dependencies)
- memcached: 0.3.0 (Memcached 1.6.32, HPA support)
- rabbitmq: 0.3.0 (RabbitMQ 4.0.4, management UI, Prometheus metrics)
- browserless-chrome: 0.3.0 (Headless Chrome for automation)
- devpi: 0.3.0 (Python package index, SQLite/PostgreSQL support)
- rsshub: 0.3.0 (RSS aggregator)
- rustfs: 0.3.0 (S3-compatible object storage, clustering)
- nextcloud: 0.2.0 (Nextcloud 31.0.10, PostgreSQL 16, Redis 8)
- paperless-ngx: 0.2.0 (Document management with OCR, 4 PVC architecture)
- uptime-kuma: 0.2.0 (Uptime monitoring, SQLite database)
- wordpress: 0.2.0 (WordPress 6.4.3, MySQL/MariaDB support)

---

## Version Policy

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes requiring user action
- **MINOR** (0.X.0): New features, backward-compatible
- **PATCH** (0.0.X): Bug fixes, documentation updates

See [Chart Version Policy](docs/CHART_VERSION_POLICY.md) for detailed versioning rules.

---

## Links

- **Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Helm Repository**: https://scriptonbasestar-container.github.io/sb-helm-charts
- **Documentation**: https://github.com/scriptonbasestar-container/sb-helm-charts/tree/master/docs
- **Issues**: https://github.com/scriptonbasestar-container/sb-helm-charts/issues

[Unreleased]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/releases/tag/v0.1.0
