# Release Notes: v1.0.0

## ScriptonBasestar Helm Charts v1.0.0 - First Stable Release

**Release Date**: 2025-11-21

We are excited to announce the first stable release of ScriptonBasestar Helm Charts! This release marks a major milestone with **36 production-ready charts** designed for simplicity, configuration file preservation, and real-world deployment scenarios.

## 🎯 Release Highlights

### Chart Portfolio
- **Total Charts**: 36 (35 production-ready v0.3.x + 1 development v0.2.0)
- **Application Charts**: 19 charts
- **Infrastructure Charts**: 17 charts
- **Production-Ready**: 35 charts at v0.3.x maturity level

### Major Milestones
- ✅ **Complete Prometheus Monitoring Stack**: 9 charts providing full observability
- ✅ **Full Database Support**: PostgreSQL, MySQL, MongoDB, Redis, Elasticsearch with replication
- ✅ **Database Administration Tools**: pgAdmin and phpMyAdmin with multi-server management
- ✅ **Comprehensive Documentation**: Testing guides, troubleshooting, production checklists
- ✅ **Metadata Automation**: Centralized management with validation and catalog generation
- ✅ **Production Features**: HA, security hardening, observability across all charts

## 📊 What's New in v1.0.0

### New Charts (20 charts added since v0.3.0)

#### Monitoring & Observability (9 charts)
| Chart | Version | Description |
|-------|---------|-------------|
| **prometheus** | 0.3.0 | Monitoring system and time series database |
| **alertmanager** | 0.3.0 | Alert routing and notification with HA clustering |
| **pushgateway** | 0.3.0 | Push-based metrics for batch jobs |
| **node-exporter** | 0.3.0 | Hardware and OS metrics (DaemonSet) |
| **kube-state-metrics** | 0.3.0 | Kubernetes object state metrics |
| **blackbox-exporter** | 0.3.0 | Endpoint probing (HTTP/HTTPS/TCP/DNS/ICMP) |
| **loki** | 0.3.0 | Log aggregation with StatefulSet clustering |
| **promtail** | 0.3.0 | Log collection agent (DaemonSet) |
| **grafana** | 0.3.0 | Metrics visualization and dashboarding |

**Complete Stack**: Full Prometheus observability with logging (Loki/Promtail), metrics (Prometheus/exporters), alerting (Alertmanager), and visualization (Grafana).

#### Database Administration (2 charts)
| Chart | Version | Description |
|-------|---------|-------------|
| **pgadmin** | 0.3.0 | PostgreSQL administration with multi-server support |
| **phpmyadmin** | 0.3.0 | MySQL/MariaDB administration with 3 connection modes |

**Features**: Server pre-configuration, session management, metadata backup/restore, 20+ operational commands.

#### Data Processing (3 charts)
| Chart | Version | Description |
|-------|---------|-------------|
| **airflow** | 0.3.0 | Workflow orchestration with KubernetesExecutor |
| **mlflow** | 0.3.0 | ML experiment tracking and model registry |
| **elasticsearch** | 0.3.0 | Search and analytics engine with Kibana |

**Use Cases**: ETL pipelines, ML model management, full-text search.

#### Infrastructure (6 charts)
| Chart | Version | Description |
|-------|---------|-------------|
| **postgresql** | 0.3.0 | Relational database with primary-replica replication |
| **mysql** | 0.3.0 | Relational database with master-replica replication |
| **mongodb** | 0.3.0 | NoSQL document database with replica sets |
| **kafka** | 0.3.0 | Streaming platform with KRaft mode (no Zookeeper) |
| **minio** | 0.3.0 | S3-compatible object storage with erasure coding |
| **harbor** | 0.2.0 | Container registry (Development - not production-ready) |

**Production Notes**: For production HA, consider using Operators (PostgreSQL, MySQL, MongoDB, Kafka, MinIO).

## 🔒 Production Features

All charts (except Harbor v0.2.0) include:

### Security
- Non-root users with dropped capabilities
- Read-only root filesystem (where applicable)
- Network policies for ingress/egress control
- Secret management for credentials
- RBAC with minimal ServiceAccount permissions

### High Availability
- PodDisruptionBudget support
- HorizontalPodAutoscaler support
- Anti-affinity rules for pod distribution
- Session affinity for stateful applications
- Clustering support (where applicable)

### Reliability
- InitContainers for dependency health checks
- Liveness, readiness, and startup probes
- Resource limits and requests
- Persistent storage with configurable reclaim policy

### Observability
- ServiceMonitor CRDs for Prometheus Operator
- Application-specific metrics endpoints
- Structured logging to stdout
- Health check endpoints

## 📚 Documentation

### New Documentation
- **CHANGELOG.md**: Complete version history and release notes
- **Production-ready READMEs**: Comprehensive documentation for all 36 charts
- **Operational Makefiles**: 36 chart-specific operations files (make/ops/*.mk)

### Existing Documentation
- **TESTING_GUIDE.md**: Comprehensive testing procedures
- **TROUBLESHOOTING.md**: Common issues and solutions
- **PRODUCTION_CHECKLIST.md**: Production readiness validation
- **CHARTS.md**: Auto-generated catalog with 36 charts
- **SCENARIO_VALUES_GUIDE.md**: Deployment scenario guide
- **CHART_DEVELOPMENT_GUIDE.md**: Development patterns and standards

## 🛠️ Deployment Profiles

All charts include multiple deployment profiles:

- **values-dev.yaml**: Minimal resources, debug logging, single replica
- **values-small-prod.yaml**: HA setup, production resources, security hardening
- **values-homeserver.yaml**: Low-resource configuration (selected charts)

### Resource Philosophy
- **Home Server**: 50-500m CPU, 128-512Mi RAM (Raspberry Pi, NUC, home labs)
- **Startup**: 100m-1Gi CPU, 256Mi-1Gi RAM (Small teams, startups)
- **Production HA**: 250m-2Gi CPU, 512Mi-2Gi RAM (Enterprise with scaling)

## 🤖 Automation

### Metadata Management
- **charts/charts-metadata.yaml**: Centralized metadata for all 36 charts
- **Validation**: Pre-commit hooks and CI/CD workflows
- **Sync**: Automated Chart.yaml keyword synchronization
- **Catalog**: Auto-generated CHARTS.md and Artifact Hub dashboard

### Scripts
- `scripts/validate-chart-metadata.py`: Metadata consistency validation
- `scripts/sync-chart-keywords.py`: Keyword sync automation
- `scripts/generate-chart-catalog.py`: Catalog generation
- `scripts/generate-artifacthub-dashboard.py`: Artifact Hub dashboard

## 📋 Chart List

### Application Charts (19)
airflow, browserless-chrome, devpi, grafana, harbor (dev), immich, jellyfin, keycloak, loki, mlflow, nextcloud, paperless-ngx, pgadmin, phpmyadmin, rsshub, rustfs, uptime-kuma, vaultwarden, wireguard, wordpress

### Infrastructure Charts (17)
alertmanager, blackbox-exporter, elasticsearch, kafka, kube-state-metrics, memcached, minio, mongodb, mysql, node-exporter, postgresql, prometheus, promtail, pushgateway, rabbitmq, redis

## 🔧 Operational Commands

Each chart includes a Makefile in `make/ops/{chart}.mk` with operational commands:

**Common operations**:
- Logs, shell access, port forwarding
- Health checks and status monitoring
- Restart and scaling operations

**Chart-specific operations**:
- Database backup/restore (PostgreSQL, MySQL, MongoDB, Redis)
- User management (databases, pgAdmin, phpMyAdmin)
- Cluster operations (Keycloak, Prometheus, Loki, databases)
- Metrics management (Prometheus, Alertmanager, Pushgateway)
- Configuration management (all charts)

## ⚠️ Known Limitations

1. **Harbor** (v0.2.0): Not production-ready - missing HA features (PDB, HPA, ServiceMonitor, documentation)
2. **Database Charts**: Simple replication only - use Operators for production HA
3. **Message Queue Charts**: Single-instance - use Operators for clustering

## 🚀 Migration Guide

### For New Installations
No migration needed. Install any chart directly:

```bash
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm install <release> sb-charts/<chart> -f values-small-prod.yaml
```

### For Existing Users (v0.x)
1. Review values.yaml changes in each chart's README
2. Backup all data before upgrading
3. Use `helm upgrade` with `--reuse-values=false` to apply new defaults
4. Test in non-production environment first

Example upgrade:
```bash
# Backup first!
make -f make/ops/<chart>.mk <chart>-backup

# Upgrade chart
helm upgrade <release> sb-charts/<chart> \
  -f values-small-prod.yaml \
  --reuse-values=false

# Validate
helm status <release>
```

## 📦 Installation

### Add Repository
```bash
# GitHub Pages (Traditional)
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update

# OCI Registry (Recommended - when available)
helm install <release> oci://ghcr.io/scriptonbasestar-containers/charts/<chart> --version 0.3.0
```

### Install Chart
```bash
# Quick install (development)
helm install <release> sb-charts/<chart>

# Production install
helm install <release> sb-charts/<chart> -f values-small-prod.yaml

# With custom values
helm install <release> sb-charts/<chart> \
  -f values-small-prod.yaml \
  --set postgresql.external.host=postgres.default.svc.cluster.local \
  --set postgresql.external.password=secure-password
```

## 🎓 Getting Started

1. **Explore the Catalog**: Check [docs/CHARTS.md](docs/CHARTS.md) for all 36 charts
2. **Review Documentation**: Read chart-specific READMEs for detailed configuration
3. **Choose Deployment Scenario**: Select from dev, homeserver, startup, or production
4. **Install External Dependencies**: Set up databases (PostgreSQL, MySQL, Redis) if needed
5. **Deploy Chart**: Use Helm install with appropriate values file
6. **Verify Deployment**: Use operational commands in make/ops/*.mk
7. **Monitor**: Set up Prometheus stack for observability

## 🌟 What's Next

### v1.1.0 Planning
- Complete Harbor chart to v0.3.0 (production-ready)
- Add more observability charts (Tempo for tracing, Mimir for metrics)
- Enhanced monitoring stack integration
- More homeserver-optimized profiles

### Future Plans
- Operator migration guides for infrastructure charts
- Advanced HA configurations
- Multi-tenancy support for selected charts
- Extended documentation and examples

## 📖 Resources

- **Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Helm Repository**: https://scriptonbasestar-container.github.io/sb-helm-charts
- **Documentation**: https://github.com/scriptonbasestar-container/sb-helm-charts/tree/master/docs
- **Issues**: https://github.com/scriptonbasestar-container/sb-helm-charts/issues
- **CHANGELOG**: [CHANGELOG.md](CHANGELOG.md)

## 🙏 Acknowledgments

This release represents a significant milestone in providing production-ready Helm charts with a focus on:
- **Simplicity**: Configuration files over environment variables
- **Preservation**: Keeping application configs in their original format
- **Reality**: External databases, no subchart complexity
- **Production**: Security, HA, and observability built-in

Thank you to all users who will help us improve these charts through feedback and contributions!

---

**Full Changelog**: [v1.0.0 CHANGELOG](CHANGELOG.md#100---2025-11-21)
