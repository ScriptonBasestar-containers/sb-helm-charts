# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 📚 Documentation Quick Reference

**Need chart operations?** → [docs/MAKEFILE_COMMANDS.md](docs/MAKEFILE_COMMANDS.md) - All chart-specific make commands

**Need chart information?** → [docs/CHARTS.md](docs/CHARTS.md) - Complete catalog of 39 charts

**Developing charts?** → [docs/CHART_DEVELOPMENT_GUIDE.md](docs/CHART_DEVELOPMENT_GUIDE.md) - Patterns and standards

**Production deployment?** → [docs/PRODUCTION_CHECKLIST.md](docs/PRODUCTION_CHECKLIST.md) - Readiness validation

**Testing?** → [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) - Comprehensive test procedures

**Troubleshooting?** → [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions

---

## Project Overview

**ScriptonBasestar Helm Charts** - Personal server Helm charts focused on simplicity and configuration file preservation.

**Core Philosophy:** Configuration files over env vars, no subchart complexity, external databases, simple Docker images.

**Key Guides:** [Chart Development](docs/CHART_DEVELOPMENT_GUIDE.md), [Version Policy](docs/CHART_VERSION_POLICY.md), [README Template](docs/CHART_README_TEMPLATE.md) & [Guide](docs/CHART_README_GUIDE.md), [Workflow Updates](docs/WORKFLOW_UPDATE_INSTRUCTIONS.md)

---

## Chart Structure

Standard: Chart.yaml, values.yaml, values-example.yaml, templates/ (deployment, service, ingress, configmap, secret, pvc, serviceaccount, optional: hpa, cronjob, tests/)

→ **Detailed structure:** [docs/CHART_DEVELOPMENT_GUIDE.md](docs/CHART_DEVELOPMENT_GUIDE.md)

---

## Chart Metadata

**⚠️ CRITICAL**: All chart metadata is centrally managed in `charts/charts-metadata.yaml`.

### When Adding or Modifying Charts

When you add a new chart or modify an existing one, you **MUST** update:

**1. Update `charts/charts-metadata.yaml`:**
   - `name`: Human-readable chart name
   - `path`: Chart directory path (e.g., `charts/chart-name`)
   - `category`: Either `application` or `infrastructure`
   - `tags`: List of categorization tags (e.g., `[Monitoring, Alerting]`)
   - `keywords`: List of searchable keywords for Chart.yaml
   - `description`: Brief description
   - `production_note`: (Optional) Production warnings for infrastructure charts

**2. Sync keywords to Chart.yaml:**
```bash
make sync-keywords-dry-run  # Preview changes
make sync-keywords          # Apply changes
```

**3. Validate consistency:**
```bash
make validate-metadata
```

**4. Regenerate catalog:**
```bash
make generate-catalog
```

**5. Update CLAUDE.md:** Update the "Available Charts" section if needed

### Metadata Tools

- `make validate-metadata` - Validates keywords consistency
- `make sync-keywords` - Syncs Chart.yaml keywords from metadata
- `make generate-catalog` - Generates docs/CHARTS.md
- `make generate-artifacthub-dashboard` - Generates docs/ARTIFACTHUB_DASHBOARD.md

**Dependencies:** Python 3.x + PyYAML (see `scripts/requirements.txt`)

---

## Available Charts

**39 Total Charts:**
- **20 Application Charts**: Airflow, Grafana, Harbor, Immich, Jellyfin, Keycloak, Loki, MLflow, Nextcloud, Paperless-ngx, pgAdmin, phpMyAdmin, Uptime Kuma, Vaultwarden, WireGuard, WordPress, and more
- **19 Infrastructure Charts**: Alertmanager, Blackbox Exporter, Elasticsearch, Grafana Mimir, Kafka, Kube State Metrics, Memcached, MinIO, MongoDB, MySQL, Node Exporter, OpenTelemetry Collector, PostgreSQL, Prometheus, Promtail, Pushgateway, RabbitMQ, Redis, RustFS, Tempo

**⚠️ 6 Enhanced Charts** with comprehensive RBAC, backup/recovery, and upgrade features: Keycloak, Airflow, Harbor, MLflow, Kafka, Elasticsearch (see Enhanced Operational Features section below)

**⚠️ Infrastructure charts** are suitable for dev/test. For production HA, consider using Kubernetes Operators (see [docs/CHARTS.md](docs/CHARTS.md) for operator links).

→ **Complete catalog:** [docs/CHARTS.md](docs/CHARTS.md)

---

## Common Development Commands

```bash
# All charts
make lint build template install upgrade validate-metadata sync-keywords

# Individual charts: make -f make/ops/{chart}.mk {command}

# Examples:
make -f make/ops/keycloak.mk kc-backup-all-realms
make -f make/ops/postgresql.mk pg-shell
make -f make/ops/prometheus.mk prom-port-forward
```

→ **All commands:** [docs/MAKEFILE_COMMANDS.md](docs/MAKEFILE_COMMANDS.md)

---

## Architecture Principles

### Configuration Management

**DO:** ConfigMaps for config files, Secrets for sensitive data, reference external services.
**DON'T:** Complex env var mappings, abstract away app config, include database subcharts.

### Database Strategy

**⚠️ CRITICAL:** All charts expect **external** databases. The `enabled: false` pattern is a core project value.

**Example configuration:**
```yaml
postgresql:
  enabled: false  # ALWAYS false - never auto-install
  external:
    enabled: true
    host: "postgres-service.default.svc.cluster.local"
    port: 5432
    database: "myapp"
    username: "myapp"
    password: ""  # Required - deployment will fail if empty
```

**Database Requirements:**
- **keycloak**: PostgreSQL 13+, Redis 6+ (optional)
- **nextcloud**: PostgreSQL 16, Redis 8
- **wordpress**: MySQL/MariaDB
- **wireguard**: No database required
- **devpi**: SQLite (built-in) or PostgreSQL

**Never suggest installing databases as subcharts.**

### Storage

PVC for persistence. Default: ReadWriteOnce + Retain. StatefulSet for stable identity (Keycloak, PostgreSQL, Redis), Deployment for external state (WordPress, Nextcloud).

---

## Values File Patterns

Standard structure: Application config, external services (`postgresql.enabled: false`), persistence, k8s resources (replicaCount, image, resources, ingress).

**Key patterns:**
- `postgresql.enabled: false` - Always use external databases
- `persistence.enabled: true` - PVC for data
- `values-example.yaml` - Production configurations

→ **Complete patterns:** [docs/CHART_DEVELOPMENT_GUIDE.md](docs/CHART_DEVELOPMENT_GUIDE.md)

---

## Git Workflow

**Main branch:** `master` (use for PRs)

**Helm repository:**
```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
```

**CI/CD:** Automated releases via GitHub Actions (`release.yaml`)

---

## Chart Versioning

Follows [Semantic Versioning 2.0.0](https://semver.org/). MAJOR: Breaking changes, MINOR: New features, PATCH: Bug fixes.

**License:** BSD-3-Clause (charts). Application licenses vary (see READMEs).

**Status:** All 39 charts at v0.3.0 (Mature - production-ready)

→ **Complete policy:** [docs/CHART_VERSION_POLICY.md](docs/CHART_VERSION_POLICY.md)

---

## Production Features

Modern charts include: PodDisruptionBudget, HorizontalPodAutoscaler, NetworkPolicy, RBAC, InitContainers, Health Probes, ServiceMonitor, Metrics, Structured Logging.

→ **Complete checklist:** [docs/PRODUCTION_CHECKLIST.md](docs/PRODUCTION_CHECKLIST.md)

---

## Enhanced Operational Features

**6 charts** have been enhanced with comprehensive RBAC, backup/recovery, and upgrade capabilities:

### Enhanced Charts

| Chart | RBAC | Backup Guide | Upgrade Guide | README Sections |
|-------|------|--------------|---------------|-----------------|
| **Keycloak** | ✅ | [keycloak-backup-guide.md](docs/keycloak-backup-guide.md) | [keycloak-upgrade-guide.md](docs/keycloak-upgrade-guide.md) | ✅ |
| **Airflow** | ✅ | [airflow-backup-guide.md](docs/airflow-backup-guide.md) | [airflow-upgrade-guide.md](docs/airflow-upgrade-guide.md) | ✅ |
| **Harbor** | ✅ | [harbor-backup-guide.md](docs/harbor-backup-guide.md) | [harbor-upgrade-guide.md](docs/harbor-upgrade-guide.md) | ✅ |
| **MLflow** | ✅ | [mlflow-backup-guide.md](docs/mlflow-backup-guide.md) | [mlflow-upgrade-guide.md](docs/mlflow-upgrade-guide.md) | ✅ |
| **Kafka** | ✅ | [kafka-backup-guide.md](docs/kafka-backup-guide.md) | [kafka-upgrade-guide.md](docs/kafka-upgrade-guide.md) | ✅ |
| **Elasticsearch** | ✅ | [elasticsearch-backup-guide.md](docs/elasticsearch-backup-guide.md) | [elasticsearch-upgrade-guide.md](docs/elasticsearch-upgrade-guide.md) | ✅ |

### RBAC Features

All enhanced charts include:
- **Role**: Namespace-scoped read access to ConfigMaps, Secrets, Pods, PVCs
- **RoleBinding**: Binds ServiceAccount to Role
- **Configurable**: `rbac.create` (default: true), `rbac.annotations`

**Example:**
```yaml
rbac:
  create: true
  annotations: {}
```

### Backup & Recovery Features

Each chart's backup strategy is tailored to its architecture:

**Keycloak:**
- Realm exports (via Admin API)
- PostgreSQL database dumps
- Redis cache snapshots (optional)
- PVC snapshots for data volumes

**Airflow:**
- DAG backups (Git-based recommended)
- PostgreSQL database dumps (metadata, connections, variables)
- Logs backups (S3/MinIO)

**Harbor:**
- Configuration backups (projects, users, policies)
- PostgreSQL database dumps
- Registry data (container images, Helm charts)

**MLflow:**
- Experiment metadata backups
- PostgreSQL database dumps
- Artifact storage (S3/MinIO)

**Kafka:**
- Topic metadata and configurations
- Consumer group offsets
- Broker configurations
- ACLs (Access Control Lists)
- Data volume snapshots

**Elasticsearch:**
- Snapshot repository (indices, cluster state)
- Index-level backups (_snapshot API)
- Cluster settings (templates, ILM policies)
- PVC snapshots for disaster recovery

### Upgrade Features

Each chart includes multiple upgrade strategies:

**Common Upgrade Strategies:**
1. **Rolling Upgrade** - Zero downtime (recommended for production)
2. **Blue-Green Deployment** - Parallel clusters with cutover
3. **Maintenance Window** - Full cluster restart (for major versions)

**Makefile Targets Available:**

```bash
# Pre-upgrade checks
make -f make/ops/{chart}.mk {chart}-pre-upgrade-check

# Post-upgrade validation
make -f make/ops/{chart}.mk {chart}-post-upgrade-check

# Backup before upgrade
make -f make/ops/{chart}.mk {chart}-backup-all
make -f make/ops/{chart}.mk {chart}-full-backup

# Rollback procedures
make -f make/ops/{chart}.mk {chart}-upgrade-rollback
```

**Example upgrade workflow:**
```bash
# 1. Pre-upgrade backup
make -f make/ops/keycloak.mk kc-backup-all-realms

# 2. Pre-upgrade validation
make -f make/ops/keycloak.mk kc-pre-upgrade-check

# 3. Upgrade via Helm
helm upgrade keycloak sb-charts/keycloak --set image.tag=26.0.0

# 4. Post-upgrade validation
make -f make/ops/keycloak.mk kc-post-upgrade-check
```

### Documentation Structure

Each enhanced chart includes:

1. **Comprehensive Backup Guide** (500-600 lines):
   - Backup strategy overview (3-5 components)
   - Detailed procedures for each component
   - Recovery workflows
   - RTO/RPO targets
   - Best practices and troubleshooting

2. **Comprehensive Upgrade Guide** (600-700 lines):
   - Pre-upgrade checklist
   - Multiple upgrade strategies
   - Version-specific notes
   - Post-upgrade validation
   - Rollback procedures
   - Troubleshooting

3. **README Sections**:
   - Backup & Recovery (80-110 lines)
   - Upgrading (120-200 lines)
   - Links to detailed guides

### values.yaml Configuration

Each enhanced chart's `values.yaml` includes documentation sections:

```yaml
# RBAC Configuration
rbac:
  create: true
  annotations: {}

# Backup & Recovery Configuration
backup:
  enabled: false  # Documentation only - no automated CronJobs
  documentation:
    strategy: "component1 + component2 + component3"
    tools: ["Tool1", "Tool2"]
    components:
      component1: "Description"
      component2: "Description"
    targets:
      rto: "< 2 hours"
      rpo: "24 hours"

# Upgrade Configuration
upgrade:
  enabled: false  # Documentation only - manual process
  preUpgradeBackup: true
  documentation:
    strategies:
      rolling: { description: "...", downtime: "None" }
      blue_green: { description: "...", downtime: "10-30 minutes" }
```

**Note:** `backup.enabled` and `upgrade.enabled` are **documentation flags only**. All backup/upgrade operations are performed via Makefile targets, never via automated CronJobs.

### RTO/RPO Targets

| Chart | RTO (Recovery Time) | RPO (Recovery Point) | Notes |
|-------|---------------------|---------------------|-------|
| Keycloak | < 1 hour | 24 hours | Realm restore via Admin API |
| Airflow | < 2 hours | 24 hours | Metadata DB + DAGs restore |
| Harbor | < 2 hours | 24 hours | Registry data + DB restore |
| MLflow | < 1 hour | 24 hours | Experiments + artifacts restore |
| Kafka | < 2 hours | 1 hour | Topic metadata + offsets |
| Elasticsearch | < 2 hours | 24 hours | Snapshot restore |

---

## Important Notes

### Kubernetes Environment Variable Precedence

**⚠️ CRITICAL:** When the same environment variable is defined multiple times in Kubernetes, the **first definition takes precedence**, not the last.

This means `extraEnv` in values.yaml **cannot override** chart-generated environment variables.

```yaml
# Chart template generates:
- name: KC_DB_URL
  value: "jdbc:postgresql://..."

# extraEnv attempting override (THIS WILL NOT WORK):
extraEnv:
  - name: KC_DB_URL
    value: "my-custom-url"  # IGNORED - first definition wins
```

**Workaround:**
1. Disable auto-generation: `postgresql.external.enabled=false`
2. Manually configure all database env vars in `extraEnv`

### Keycloak 26.x Breaking Changes

- **Health endpoints**: Moved from port 8080 to port 9000 (management port)
  - Liveness: `http://localhost:9000/health/live`
  - Readiness: `http://localhost:9000/health/ready`
  - Startup: `http://localhost:9000/health/started`
- **Hostname v1**: Completely removed - must use hostname v2
- **PostgreSQL 13+**: Minimum requirement increased from 12.x
- **CLI-based clustering**: Use `--cache-embedded-network-*` CLI options

### Chart Metadata Requirements

**ALWAYS update `charts/charts-metadata.yaml` when adding or modifying charts** - see Chart Metadata section above.

---

**Additional Resources:** [Chart Analysis](docs/05-chart-analysis-2025-11.md), [Makefile Architecture](docs/CHART_DEVELOPMENT_GUIDE.md), [Automation Scripts](scripts/)

**Last Updated:** 2025-11-27
