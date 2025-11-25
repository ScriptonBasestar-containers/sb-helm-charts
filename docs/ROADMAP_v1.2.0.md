# Roadmap: v1.2.0

## Overview

Planning document for v1.2.0 release following the v1.1.0 documentation-focused release.

**Target Release Date**: TBD (2-3 months after v1.1.0)
**Focus Areas**: GitOps integration, advanced HA, new charts, and operational tooling

## Goals

### Primary Goals
1. **GitOps Integration**: ArgoCD and Flux examples for all charts ✅ *(GITOPS_GUIDE.md created)*
2. **Mimir Chart**: Scalable Prometheus metrics backend
3. **Pre-configured Grafana Dashboards**: JSON dashboards for all observability charts ✅ *(4 dashboards in dashboards/)*
4. **Enhanced Chart READMEs**: Security considerations, performance tuning sections

### Secondary Goals
1. **OpenTelemetry Collector**: Alternative tracing/metrics ingestion
2. **Vault Integration**: HashiCorp Vault for secrets management examples
3. **Policy Enforcement**: OPA/Kyverno policy examples
4. **Service Mesh Examples**: Istio/Linkerd integration guides

## Planned Charts

### High Priority
- **mimir** (v0.3.0) - Scalable Prometheus metrics backend
  - Long-term metrics storage
  - Multi-tenancy support
  - S3/MinIO backend
  - Alternative to Prometheus for large-scale deployments

- **opentelemetry-collector** (v0.3.0) - Unified telemetry collection
  - OTLP receiver
  - Multiple exporters (Prometheus, Loki, Tempo, Jaeger)
  - Pipeline configuration

### Medium Priority
- **vault** (v0.3.0) - Secrets management
  - External Secrets Operator integration
  - Kubernetes authentication
  - PKI and transit encryption

- **consul** (v0.3.0) - Service discovery and mesh
  - Connect sidecar injection
  - Service mesh capabilities
  - KV store

## Documentation Enhancements

### New Documentation

1. **GitOps Guide** (docs/GITOPS_GUIDE.md)
   - ArgoCD ApplicationSet examples
   - Flux HelmRelease examples
   - Multi-environment deployment patterns
   - Secrets management with SOPS/Sealed Secrets

2. **Advanced HA Guide** (docs/ADVANCED_HA_GUIDE.md)
   - Multi-region deployment patterns
   - Cross-zone pod distribution
   - Disaster recovery procedures
   - Backup and restore automation

3. **Security Hardening Guide** (docs/SECURITY_HARDENING_GUIDE.md)
   - Pod Security Standards
   - Network Policy best practices
   - RBAC patterns
   - Secret rotation strategies

### Dashboard Collection

1. **Grafana Dashboards** (dashboards/)
   - prometheus-overview.json
   - loki-overview.json
   - tempo-overview.json
   - kubernetes-cluster.json
   - per-chart dashboards

## Technical Improvements

### Observability Enhancements

1. **Dashboard Provisioning**
   - ConfigMap-based dashboard loading
   - Grafana dashboard auto-discovery
   - Dashboard versioning

2. **Alerting Rules**
   - Standard PrometheusRule CRDs per chart
   - Alert routing templates
   - Runbook links in alerts

### Automation

1. **Chart Testing**
   - Integration test framework
   - Automated deployment testing
   - Performance benchmarks

2. **Release Automation**
   - Automated version bumping
   - Changelog generation
   - Release notes templates

## Success Criteria

### Must Have (Required for v1.2.0)
- [ ] Mimir chart implemented
- [x] GitOps guide with ArgoCD/Flux examples *(2025-11-25: docs/GITOPS_GUIDE.md)*
- [x] At least 5 Grafana dashboards *(4 core dashboards created: prometheus-overview, loki-overview, tempo-overview, kubernetes-cluster)*
- [ ] Enhanced chart READMEs (security, performance sections)

### Should Have (High Priority)
- [ ] OpenTelemetry Collector chart
- [ ] Pre-configured alerting rules
- [ ] Advanced HA guide
- [ ] Vault integration examples

### Nice to Have (Optional)
- [ ] Consul chart
- [ ] Service mesh examples
- [ ] Policy enforcement guide
- [ ] Chaos engineering integration

## Timeline (Tentative)

### Phase 1: Charts (Weeks 1-4)
- [ ] Implement Mimir chart
- [ ] Implement OpenTelemetry Collector chart
- [ ] Add operational commands for new charts

### Phase 2: Dashboards & Alerts (Weeks 5-6)
- [x] Create Grafana dashboard collection *(2025-11-25: 4 dashboards in dashboards/)*
- [ ] Add PrometheusRule templates
- [ ] Dashboard provisioning guide

### Phase 3: GitOps & Documentation (Weeks 7-8)
- [x] GitOps guide with examples *(2025-11-25: docs/GITOPS_GUIDE.md)*
- [ ] Advanced HA guide
- [ ] Security hardening guide
- [ ] Enhanced chart READMEs

### Phase 4: Testing & Release (Weeks 9-10)
- [ ] Comprehensive testing
- [ ] Update CHANGELOG.md
- [ ] Create release notes
- [ ] Release v1.2.0

## ✅ Completed (2025-11-25)

### Chart Version Upgrades

21 charts upgraded to latest stable versions:

**Infrastructure (11):** Harbor 2.13.3, Grafana 12.2.2, Prometheus 3.7.3, Elasticsearch 8.17.0, Loki 3.6.1, Kafka 3.9.0, Tempo 2.9.0, Promtail 3.6.1, MySQL 8.4.3, MinIO 2025-10-15, PostgreSQL 16.11

**Application (5):** Keycloak 26.4.2, Jellyfin 10.11.3, Paperless-ngx 2.19.6, WordPress 6.8, phpMyAdmin 5.2.3

**Monitoring (5):** Alertmanager 0.29.0, Blackbox Exporter 0.27.0, Node Exporter 1.10.2, kube-state-metrics 2.15.0, Pushgateway 1.11.2

---

## 🔄 Planned: Major Version Migrations

Charts requiring separate testing due to breaking changes:

| Chart | Current | Target | Priority | Notes |
|-------|---------|--------|----------|-------|
| Immich | v1.122.3 | v2.3.1 | High | Breaking API changes, migration required |
| Airflow | 2.8.1 | 3.1.3 | Medium | New executor model, DAG format changes |
| pgAdmin | 8.13 | 9.10 | Low | UI changes, new features |
| MLflow | 2.9.2 | 3.6.0 | Medium | Python 3.10+ required, new APIs |

### Migration Plan

1. **Create feature branch** for each major migration
2. **Test in isolated environment** before merging
3. **Document breaking changes** in chart README
4. **Provide migration guide** if needed

### Deferred (License/Breaking)

| Chart | Current | Latest | Reason |
|-------|---------|--------|--------|
| RabbitMQ | 3.13.1 | 4.x | AMQP 1.0 protocol changes |
| MongoDB | 7.0.14 | 8.x | Major version, compatibility testing needed |
| Redis | 7.4.1 | 8.x | License changed to RSALv2/SSPLv1 |

---

## Deferred from v1.1.0

Items intentionally deferred:
- Mimir chart (complex, requires careful design)
- Pre-configured Grafana dashboards (time-consuming)
- Enhanced chart READMEs (incremental improvement)
- Community discussion categories (GitHub manual setup)

## Notes

This roadmap builds on v1.1.0's documentation foundation to add:
- More production-ready tooling
- GitOps workflow support
- Enhanced observability capabilities

**Created**: 2025-11-25
**Updated**: 2025-11-25
**Status**: Active - Chart upgrades completed, Major migrations planned
