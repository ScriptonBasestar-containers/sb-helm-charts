# Release Notes: v1.2.0

**Release Date**: TBD
**Focus**: GitOps Integration, Advanced Observability, Security Hardening

## Highlights

v1.2.0 brings significant improvements to observability, security, and GitOps workflows:

- **2 New Charts**: OpenTelemetry Collector and Grafana Mimir for unified telemetry
- **21 Chart Upgrades**: Latest stable versions across all categories
- **5 New Guides**: GitOps, Advanced HA, Security Hardening, Vault Integration, Dashboard Provisioning
- **4 Grafana Dashboards**: Ready-to-use monitoring dashboards
- **5 Alerting Rule Sets**: PrometheusRule templates for production monitoring

## New Charts

### OpenTelemetry Collector (v0.3.0)

Unified telemetry collection for traces, metrics, and logs.

```bash
helm install otel-collector scripton-charts/opentelemetry-collector -n monitoring
```

**Key Features:**
- OTLP gRPC (4317) and HTTP (4318) receivers
- Deployment mode (gateway) or DaemonSet mode (agent)
- k8sattributes processor for Kubernetes metadata enrichment
- Multiple exporters: Prometheus remote write, Loki, Tempo, Jaeger
- Production-ready: HPA, PDB, ServiceMonitor

### Grafana Mimir (v0.3.0)

Scalable, long-term storage for Prometheus metrics.

```bash
helm install mimir scripton-charts/mimir -n monitoring
```

**Key Features:**
- Monolithic deployment mode for simplicity
- S3/MinIO backend for blocks storage
- Multi-tenancy support with X-Scope-OrgID header
- Remote write endpoint compatible with Prometheus
- Production-ready: HPA, PDB, ServiceMonitor

## Chart Upgrades

### Infrastructure Charts (11)

| Chart | Previous | New | Notes |
|-------|----------|-----|-------|
| Harbor | 2.11.0 | 2.13.3 | Security fixes |
| Grafana | 11.2.0 | 12.2.2 | New dashboard features |
| Prometheus | 2.54.1 | 3.7.3 | Performance improvements |
| Elasticsearch | 8.15.0 | 8.17.0 | Bug fixes |
| Loki | 3.1.1 | 3.6.1 | Query improvements |
| Kafka | 3.8.0 | 3.9.0 | KRaft stability |
| Tempo | 2.5.0 | 2.9.0 | TraceQL enhancements |
| Promtail | 3.1.1 | 3.6.1 | Log parsing fixes |
| MySQL | 8.0.39 | 8.4.3 | Security updates |
| MinIO | 2024-08-17 | 2025-10-15 | Performance |
| PostgreSQL | 16.4 | 16.11 | Bug fixes |

### Application Charts (5)

| Chart | Previous | New | Notes |
|-------|----------|-----|-------|
| Keycloak | 25.0.6 | 26.4.2 | New features |
| Jellyfin | 10.9.11 | 10.11.3 | Transcoding improvements |
| Paperless-ngx | 2.11.6 | 2.19.6 | OCR improvements |
| WordPress | 6.6.2 | 6.8 | Security updates |
| phpMyAdmin | 5.2.1 | 5.2.3 | Bug fixes |

### Monitoring Charts (5)

| Chart | Previous | New |
|-------|----------|-----|
| Alertmanager | 0.27.0 | 0.29.0 |
| Blackbox Exporter | 0.25.0 | 0.27.0 |
| Node Exporter | 1.8.2 | 1.10.2 |
| kube-state-metrics | 2.13.0 | 2.15.0 |
| Pushgateway | 1.9.0 | 1.11.2 |

## New Documentation

### GitOps Guide

Complete guide for GitOps workflows with ArgoCD and Flux.

- ArgoCD ApplicationSet examples
- Flux HelmRelease with Kustomize
- Multi-environment patterns (dev/staging/prod)
- Secrets management with SOPS, Sealed Secrets

**Location**: `docs/GITOPS_GUIDE.md`

### Advanced HA Guide

Production patterns for high availability deployments.

- Multi-region deployment strategies
- Cross-zone pod distribution
- Disaster recovery procedures
- Backup and restore automation

**Location**: `docs/ADVANCED_HA_GUIDE.md`

### Security Hardening Guide

Comprehensive security best practices for Kubernetes.

- Pod Security Standards (PSS) configuration
- Network Policy patterns
- RBAC with least privilege
- Container security (non-root, capabilities)
- Secret management
- Audit logging

**Location**: `docs/SECURITY_HARDENING_GUIDE.md`

### Vault Integration Guide

HashiCorp Vault integration patterns.

- External Secrets Operator (recommended)
- Vault Agent Sidecar injection
- CSI Provider for volume mounts
- Dynamic database secrets
- PKI integration with cert-manager
- Secret rotation

**Location**: `docs/VAULT_INTEGRATION_GUIDE.md`

### Dashboard Provisioning Guide

Grafana dashboard management strategies.

- ConfigMap-based dashboard loading
- Dashboard auto-discovery
- Version control for dashboards

**Location**: `docs/DASHBOARD_PROVISIONING_GUIDE.md`

## Grafana Dashboards

Pre-built dashboards ready for import:

| Dashboard | Description |
|-----------|-------------|
| `prometheus-overview.json` | Prometheus server health and performance |
| `loki-overview.json` | Loki log aggregation metrics |
| `tempo-overview.json` | Tempo distributed tracing metrics |
| `kubernetes-cluster.json` | Kubernetes cluster overview |

**Location**: `dashboards/`

## Alerting Rules

PrometheusRule templates for production monitoring:

| Rule Set | Alerts |
|----------|--------|
| `prometheus-alerts.yaml` | Prometheus down, target scrape failures |
| `kubernetes-alerts.yaml` | Pod crashes, node issues, resource exhaustion |
| `loki-alerts.yaml` | Loki ingestion issues, query failures |
| `tempo-alerts.yaml` | Tempo trace ingestion, storage issues |
| `mimir-alerts.yaml` | Mimir ingestion, compaction, query issues |

**Location**: `alerting-rules/`

## Migration Guide

### From v1.1.0

No breaking changes. Standard upgrade:

```bash
helm repo update
helm upgrade <release> scripton-charts/<chart> -n <namespace>
```

### Chart-Specific Notes

**Prometheus 2.x → 3.x:**
- Some deprecated flags removed
- Check promtool for config validation

**Grafana 11.x → 12.x:**
- Dashboard schema changes (auto-migrated)
- New plugin requirements possible

**Keycloak 25.x → 26.x:**
- Health endpoints moved to port 9000
- Hostname v1 completely removed

## Planned Major Migrations

Charts requiring separate testing due to breaking changes:

| Chart | Current | Target | Priority |
|-------|---------|--------|----------|
| Immich | v1.122.3 | v2.3.1 | High |
| Airflow | 2.8.1 | 3.1.3 | Medium |
| pgAdmin | 8.13 | 9.10 | Low |
| MLflow | 2.9.2 | 3.6.0 | Medium |

These will be available on feature branches for testing before merge.

## Deferred Items

The following items are deferred to v1.3.0:

- Consul chart
- Service mesh examples (Istio/Linkerd)
- Policy enforcement guide (OPA/Kyverno)
- Chaos engineering integration

## Getting Started

### Add Repository

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

### Quick Install Examples

**Full Observability Stack:**
```bash
helm install prometheus scripton-charts/prometheus -n monitoring
helm install loki scripton-charts/loki -n monitoring
helm install tempo scripton-charts/tempo -n monitoring
helm install grafana scripton-charts/grafana -n monitoring
helm install otel-collector scripton-charts/opentelemetry-collector -n monitoring
```

**With Long-term Storage:**
```bash
helm install mimir scripton-charts/mimir -n monitoring \
  --set storage.s3.endpoint=minio:9000 \
  --set storage.s3.bucket=mimir-blocks
```

## Acknowledgments

Thanks to all contributors and users who provided feedback for this release.

## Links

- **Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Helm Repository**: https://scriptonbasestar-container.github.io/sb-helm-charts
- **Documentation**: https://github.com/scriptonbasestar-container/sb-helm-charts/tree/master/docs
- **Issues**: https://github.com/scriptonbasestar-container/sb-helm-charts/issues

---

**Full Changelog**: [v1.1.0...v1.2.0](https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v1.1.0...v1.2.0)
