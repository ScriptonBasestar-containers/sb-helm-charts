# Release Notes: v1.1.0

## Overview

v1.1.0 focuses on documentation excellence, observability enhancements, and developer experience improvements. This release brings comprehensive guides for production deployments, operator migrations, and multi-tenancy patterns.

**Release Date**: 2025-11-25

**Chart Count**: 37 production-ready charts

## Highlights

### Observability Stack Complete

The full observability stack is now production-ready with Tempo distributed tracing:

- **Prometheus** - Metrics collection and alerting
- **Loki** - Log aggregation
- **Tempo** - Distributed tracing (NEW)
- **Grafana** - Visualization and dashboards

### Comprehensive Documentation

Six new guides covering critical deployment scenarios:

| Guide | Description |
|-------|-------------|
| [Observability Stack Guide](OBSERVABILITY_STACK_GUIDE.md) | Complete Prometheus + Loki + Tempo setup |
| [Homeserver Optimization](HOMESERVER_OPTIMIZATION.md) | K3s deployments on limited hardware |
| [Multi-Tenancy Guide](MULTI_TENANCY_GUIDE.md) | Namespace isolation and RBAC patterns |
| [Operator Migration Guides](migrations/) | 6 guides for database and messaging operators |

### Developer Experience

New automation tools for faster deployments:

- **Quick Start Script** - One-command stack deployments
- **Chart Generator** - Automated chart scaffolding

## New Features

### Tempo Chart (v0.3.0)

Grafana Tempo distributed tracing backend:

- OTLP, Jaeger, and Zipkin receivers
- S3/MinIO storage backend
- Grafana datasource integration
- 25+ operational commands (`make/ops/tempo.mk`)

### Documentation

#### Observability Stack Guide
Complete setup guide for the monitoring trinity:
- Architecture diagrams
- Installation sequences
- Query examples (PromQL, LogQL, TraceQL)
- Dashboard recommendations

#### Operator Migration Guides
Six comprehensive guides for migrating from Helm charts to Kubernetes Operators:

| Source Chart | Target Operators |
|--------------|------------------|
| PostgreSQL | Zalando, Crunchy, CloudNativePG |
| MySQL | Oracle, Percona, Vitess |
| MongoDB | Community, Enterprise, Percona |
| Redis | Spotahome Redis Operator |
| RabbitMQ | RabbitMQ Cluster Operator |
| Kafka | Strimzi Kafka Operator |

#### Homeserver Optimization Guide
Deployment strategies for resource-constrained environments:
- Hardware recommendations (Raspberry Pi, NUC, Mini PCs)
- K3s configuration
- Chart-specific resource profiles
- Power management and cost analysis

#### Multi-Tenancy Guide
Patterns for shared Kubernetes clusters:
- Namespace isolation strategies
- ResourceQuota and LimitRange
- RBAC patterns (admin, developer, viewer)
- NetworkPolicy for tenant isolation
- Storage and secrets isolation

### Automation Scripts

#### Quick Start Script (`scripts/quick-start.sh`)
Deploy complete stacks with one command:

```bash
# Deploy monitoring stack
./scripts/quick-start.sh monitoring default

# Deploy MLOps stack
./scripts/quick-start.sh mlops mlops

# Available scenarios: monitoring, mlops, database, nextcloud, wordpress, messaging
```

#### Chart Generator (`scripts/generate-chart.sh`)
Create new charts following project conventions:

```bash
./scripts/generate-chart.sh my-app 1.0.0 --type=application
```

Generates:
- Chart.yaml with proper metadata
- values.yaml with standard structure
- All production templates (HPA, PDB, ServiceMonitor, NetworkPolicy)
- Test templates

### Example Deployments

#### MLOps Stack (`examples/mlops-stack/`)
Complete MLflow experiment tracking:
- MinIO for artifact storage
- PostgreSQL for metadata
- MLflow server with S3 integration

## Chart Updates

### Harbor (v0.3.0) - Production Ready
Harbor container registry with full production features:
- PodDisruptionBudget
- HorizontalPodAutoscaler
- ServiceMonitor
- NetworkPolicy
- Values profiles (home, startup, production)
- 35+ operational commands

## Validation

All 37 charts validated:
- ✅ `helm lint` passes for all charts
- ✅ Metadata consistency verified
- ✅ Template rendering tested

## Migration Notes

### From v1.0.0

No breaking changes. Direct upgrade supported:

```bash
helm repo update
helm upgrade <release> sb-charts/<chart> --reuse-values
```

### New Recommendations

1. **Use Tempo for tracing** - Complete observability stack now available
2. **Review operator migration guides** - Consider operators for production HA
3. **Use quick-start scripts** - Faster stack deployments with validated configurations

## Known Limitations

1. **Grafana dashboards** - Pre-configured JSON dashboards not yet included
2. **Mimir chart** - Not implemented (optional Nice-to-Have)

## Statistics

| Metric | Value |
|--------|-------|
| Total Charts | 37 |
| New Charts | 1 (Tempo) |
| New Documentation | 10+ guides |
| New Scripts | 2 |
| Migration Guides | 6 |

## Contributors

- ScriptonBasestar Team
- Claude (AI Assistant)

## Links

- [Chart Catalog](CHARTS.md)
- [CHANGELOG](../CHANGELOG.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [Helm Repository](https://scriptonbasestar-container.github.io/sb-helm-charts)

---

*Released with assistance from Claude Code*
