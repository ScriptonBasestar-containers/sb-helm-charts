# Grafana Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 12.2.2](https://img.shields.io/badge/AppVersion-12.2.2-informational?style=flat-square)

Grafana metrics visualization and dashboarding platform for Kubernetes

## Features

- **Flexible Database**: SQLite (default) or external PostgreSQL/MySQL
- **Data Source Support**: Prometheus, Loki, and 100+ data sources
- **Persistent Storage**: PVC for dashboards and settings
- **Security**: Auto-generated passwords, non-root execution
- **Ingress Support**: External access with TLS
- **Health Probes**: Liveness and readiness checks
- **Operational Tools**: 15+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with SQLite (development)
helm install my-grafana scripton-charts/grafana

# Install with PostgreSQL (production)
helm install my-grafana scripton-charts/grafana \
  --set database.external.enabled=true \
  --set database.external.host=postgresql \
  --set database.external.password=dbpass \
  --set grafana.adminPassword=admin123
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner (for persistence)

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.adminUser` | Admin username | `admin` |
| `grafana.adminPassword` | Admin password (auto-generated if empty) | `""` |
| `database.external.enabled` | Use external database | `false` |
| `database.external.type` | Database type (postgres/mysql) | `postgres` |
| `persistence.enabled` | Enable persistence | `true` |
| `persistence.size` | PVC size | `10Gi` |
| `ingress.enabled` | Enable ingress | `false` |

## Operational Commands

```bash
# Get admin password
make -f make/ops/grafana.mk grafana-get-password

# Port forward
make -f make/ops/grafana.mk grafana-port-forward

# Add Prometheus data source
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus:9090

# Add Loki data source
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100

# List dashboards
make -f make/ops/grafana.mk grafana-list-dashboards

# Export dashboard
make -f make/ops/grafana.mk grafana-export-dashboard UID=dashboard-uid

# Backup database
make -f make/ops/grafana.mk grafana-db-backup
```

## Production Setup

```yaml
# values-prod.yaml
grafana:
  adminPassword: "secure-password"

database:
  external:
    enabled: true
    type: "postgres"
    host: "postgresql"
    password: "db-password"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - grafana.example.com
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.example.com

persistence:
  storageClass: "fast-ssd"
  size: 20Gi
```

## Data Sources

### Add Prometheus

```bash
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus-server:9090
```

### Add Loki

```bash
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100
```

## Dashboard Import

Import from Grafana.com:

1. Browse https://grafana.com/grafana/dashboards/
2. Copy dashboard ID or JSON
3. Import via UI or CLI

## License

- Chart: BSD 3-Clause License
- Grafana: Apache License 2.0

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Dashboard Gallery](https://grafana.com/grafana/dashboards/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.1.0
**Grafana Version**: 10.2.3
