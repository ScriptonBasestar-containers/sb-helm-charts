# Roadmap: v1.2.0

## Overview

Planning document for v1.2.0 release following the v1.1.0 documentation-focused release.

**Target Release Date**: TBD (2-3 months after v1.1.0)
**Focus Areas**: GitOps integration, advanced HA, new charts, and operational tooling

## Goals

### Primary Goals
1. **GitOps Integration**: ArgoCD and Flux examples for all charts
2. **Mimir Chart**: Scalable Prometheus metrics backend
3. **Pre-configured Grafana Dashboards**: JSON dashboards for all observability charts
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
- [ ] GitOps guide with ArgoCD/Flux examples
- [ ] At least 5 Grafana dashboards
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
- [ ] Create Grafana dashboard collection
- [ ] Add PrometheusRule templates
- [ ] Dashboard provisioning guide

### Phase 3: GitOps & Documentation (Weeks 7-8)
- [ ] GitOps guide with examples
- [ ] Advanced HA guide
- [ ] Security hardening guide
- [ ] Enhanced chart READMEs

### Phase 4: Testing & Release (Weeks 9-10)
- [ ] Comprehensive testing
- [ ] Update CHANGELOG.md
- [ ] Create release notes
- [ ] Release v1.2.0

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
**Status**: Draft - Pending v1.1.0 release feedback
