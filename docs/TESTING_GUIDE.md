# Helm Charts Testing Guide

> **Document Type**: Testing Guide
> **Created**: 2025-11-17
> **Purpose**: Define testing scenarios and procedures for all Helm charts
> **Target Audience**: Chart developers, QA engineers, DevOps teams
> **Prerequisites**: Kubernetes 1.24+, Helm 3.x, kubectl

---

## Overview

This document defines comprehensive testing scenarios for all charts in the sb-helm-charts repository. Each chart should be tested across multiple deployment scenarios (home server, startup, production) to ensure reliability and compatibility.

## Scenario Categories

### 1. Home Server (홈서버)
- **Cluster**: Single cluster
- **Nodes**: Single node
- **Instances**: Single instance
- **Resources**: Low (suitable for Raspberry Pi, NUC)
- **HA**: Not required
- **Backup**: Manual
- **Use case**: Personal use, learning, development

### 2. Startup (스타트업)
- **Cluster**: Single cluster
- **Nodes**: Multi-node (3-5 nodes)
- **Instances**: Single instance per service
- **Resources**: Medium
- **HA**: Basic (PDB, multiple replicas for stateless services)
- **Backup**: Automated daily
- **Use case**: Small business, MVP, growing user base

### 3. Production (운영서버)
- **Cluster**: Multi-cluster (or single with multi-region)
- **Nodes**: Multi-node (5+ nodes)
- **Instances**: Multi-instance with replication
- **Resources**: High
- **HA**: Full (PDB, HPA, anti-affinity, master-slave, clustering)
- **Backup**: Automated with PITR, multi-region
- **Use case**: Enterprise, high availability requirements

---

## Chart-Specific Scenarios

### Infrastructure Charts

#### Redis
1. **Home Server**: Single instance, no persistence, memory cache only
2. **Startup**: Single instance, RDB persistence, monitoring
3. **Production**: Master-Slave replication, AOF+RDB persistence, Sentinel/Cluster mode, metrics
4. **Special Modes**:
   - Sentinel: 3 instances (1 master, 2 slaves) + 3 sentinels
   - Cluster: 6 instances (3 masters, 3 slaves)

#### Memcached
1. **Home Server**: Single instance, minimal resources
2. **Startup**: 2-3 instances, connection pooling
3. **Production**: 3+ instances, consistent hashing, monitoring

#### RabbitMQ
1. **Home Server**: Single instance, no clustering
2. **Startup**: Single instance, management UI, basic monitoring
3. **Production**: 3-node cluster, mirrored queues, TLS, monitoring

### Application Charts (No External DB)

#### WireGuard
1. **Home Server**: Single instance, 5-10 peers, NodePort/LoadBalancer
2. **Startup**: Single instance, 20-50 peers, automated peer management
3. **Production**: Multi-instance (separate by region/purpose), 100+ peers

#### Uptime Kuma
1. **Home Server**: Single instance, SQLite, monitoring 10-20 services
2. **Startup**: Single instance, SQLite, monitoring 50+ services
3. **Production**: Multiple instances (by region), external DB consideration

#### RustFS (S3-compatible storage)
1. **Home Server**: Single instance, local storage
2. **Startup**: 2-4 instances, erasure coding
3. **Production**: 4+ instances, tiered storage, multi-region replication

### Application Charts (Require External DB)

#### Keycloak
1. **Home Server**: Single instance, external PostgreSQL (single), H2 cache
2. **Startup**: 2 instances, external PostgreSQL (single), Infinispan cache
3. **Production**: 3+ instances, external PostgreSQL (HA), Infinispan distributed cache, TLS

#### Nextcloud
1. **Home Server**: Single instance, external PostgreSQL, Redis cache, small storage
2. **Startup**: 1-2 instances, external PostgreSQL, Redis cache, S3 storage
3. **Production**: 3+ instances, external PostgreSQL (HA), Redis (HA), S3 storage, preview generator

#### WordPress
1. **Home Server**: Single instance, external MySQL, small storage (values-homeserver.yaml)
2. **Startup**: 1-2 instances, external MySQL, Redis cache, CDN
3. **Production**: 3+ instances, external MySQL (HA), Redis (HA), CDN, multiple regions

#### Paperless-ngx
1. **Home Server**: Single instance, external PostgreSQL, Redis, local storage
2. **Startup**: Single instance, external PostgreSQL, Redis, S3 storage
3. **Production**: 2+ instances (consumer workers), external PostgreSQL (HA), Redis (HA), S3 storage

#### Vaultwarden
1. **Home Server**: Single instance, SQLite, local storage
2. **Startup**: Single instance, external PostgreSQL, backups
3. **Production**: Single instance (no clustering support), external PostgreSQL (HA), automated backups

#### Immich
1. **Home Server**: Single instance, external PostgreSQL, Redis, local storage
2. **Startup**: 2 instances (web + ML), external PostgreSQL, Redis, S3 storage
3. **Production**: Multiple instances (web, ML, microservices), external PostgreSQL (HA), Redis (HA), S3

#### Jellyfin
1. **Home Server**: Single instance, hardware transcoding, local storage
2. **Startup**: Single instance, hardware transcoding, NFS/S3 storage
3. **Production**: Multiple instances (by region), shared storage, CDN

#### Devpi
1. **Home Server**: Single instance, SQLite, local storage
2. **Startup**: Single instance, external PostgreSQL, S3 storage
3. **Production**: Multiple instances, external PostgreSQL (HA), S3 storage, CDN

#### Browserless Chrome
1. **Home Server**: Single instance, no persistence
2. **Startup**: 2-3 instances, HPA based on load
3. **Production**: 5+ instances, HPA, resource limits, monitoring

#### RSShub
1. **Home Server**: Single instance, Redis cache (optional)
2. **Startup**: 2 instances, Redis cache, monitoring
3. **Production**: 3+ instances, Redis cache (HA), CDN, rate limiting

---

## Testing Checklist

For each scenario, verify:

### Deployment
- [ ] Chart lints successfully
- [ ] Templates render without errors
- [ ] Resources are created in correct order
- [ ] InitContainers complete successfully
- [ ] Main container starts and becomes ready
- [ ] Health probes pass (liveness, readiness, startup)

### Configuration
- [ ] ConfigMaps are created correctly
- [ ] Secrets are created and mounted
- [ ] Environment variables are set correctly
- [ ] Volume mounts work as expected
- [ ] Permissions are correct (SecurityContext)

### Connectivity
- [ ] Service is accessible within cluster
- [ ] Ingress routes traffic correctly (if enabled)
- [ ] External database connection works (if required)
- [ ] Cache connection works (if required)
- [ ] Inter-pod communication works (for StatefulSets)

### High Availability (Startup/Production)
- [ ] Multiple replicas start successfully
- [ ] PodDisruptionBudget prevents simultaneous eviction
- [ ] HPA scales up/down based on metrics (if configured)
- [ ] Anti-affinity spreads pods across nodes (if configured)
- [ ] Clustering/replication works correctly (if applicable)

### Persistence
- [ ] PVCs are created and bound
- [ ] Data persists after pod restart
- [ ] Volume expansion works (if supported)
- [ ] Backup/restore procedures work

### Operations
- [ ] Makefile commands work correctly
- [ ] Logs are accessible and meaningful
- [ ] Metrics are exposed (if configured)
- [ ] Upgrade preserves data and configuration
- [ ] Rollback works correctly

### Security
- [ ] ServiceAccount has minimal required permissions
- [ ] NetworkPolicy restricts traffic correctly (if enabled)
- [ ] Secrets are not exposed in logs or environment
- [ ] TLS/SSL connections work (if configured)
- [ ] Security contexts enforce non-root (where possible)

---

## Priority Testing Order

1. **Infrastructure Charts** (no dependencies):
   - Redis (all modes)
   - Memcached
   - RabbitMQ

2. **Simple Application Charts** (no external DB):
   - WireGuard
   - Uptime Kuma
   - RustFS
   - Jellyfin
   - Vaultwarden (with SQLite)

3. **PostgreSQL Setup** (for DB-dependent charts)

4. **Complex Application Charts** (need external DB):
   - Keycloak
   - Nextcloud
   - WordPress
   - Paperless-ngx
   - Immich
   - Devpi

5. **Stateless Application Charts**:
   - Browserless Chrome
   - RSShub

---

## Notes

- All tests assume Kubernetes 1.24+
- Storage class should support dynamic provisioning
- Ingress controller should be installed for ingress tests
- Metrics server should be installed for HPA tests
- Some charts may require specific hardware (GPU for Jellyfin transcoding, etc.)

---

## Additional Resources

- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions for production deployments
- [Production Checklist](PRODUCTION_CHECKLIST.md) - Production readiness validation and deployment checklist
- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md) - Development patterns and standards
- [Chart Version Policy](CHART_VERSION_POLICY.md) - Semantic versioning and release process
- [Analysis Report](05-chart-analysis-2025-11.md) - Comprehensive analysis of all charts
- [Scenario Values Guide](SCENARIO_VALUES_GUIDE.md) - Deployment scenarios explained
