# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 📚 Documentation Quick Reference

**Need chart operations?** → [docs/MAKEFILE_COMMANDS.md](docs/MAKEFILE_COMMANDS.md) - All chart-specific make commands

**Need chart information?** → [docs/CHARTS.md](docs/CHARTS.md) - Complete catalog of 36 charts

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

**36 Total Charts:**
- **20 Application Charts**: Airflow, Grafana, Harbor, Immich, Jellyfin, Keycloak, Loki, MLflow, Nextcloud, Paperless-ngx, pgAdmin, phpMyAdmin, Uptime Kuma, Vaultwarden, WireGuard, WordPress, and more
- **16 Infrastructure Charts**: Alertmanager, Blackbox Exporter, Elasticsearch, Kafka, Memcached, MinIO, MongoDB, MySQL, Node Exporter, PostgreSQL, Prometheus, Promtail, Pushgateway, RabbitMQ, Redis, RustFS

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

**Status:** All 36 charts at v0.3.0 (Mature - production-ready)

→ **Complete policy:** [docs/CHART_VERSION_POLICY.md](docs/CHART_VERSION_POLICY.md)

---

## Production Features

Modern charts include: PodDisruptionBudget, HorizontalPodAutoscaler, NetworkPolicy, RBAC, InitContainers, Health Probes, ServiceMonitor, Metrics, Structured Logging.

→ **Complete checklist:** [docs/PRODUCTION_CHECKLIST.md](docs/PRODUCTION_CHECKLIST.md)

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

**Last Updated:** 2025-11-23
