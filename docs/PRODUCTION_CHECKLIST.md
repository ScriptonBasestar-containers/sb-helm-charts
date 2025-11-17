# Production Deployment Checklist

> **Last Updated**: 2025-11-17
> **Purpose**: Ensure production-ready deployments for sb-helm-charts
> **Status**: Use this checklist before deploying to production

This checklist helps ensure your Helm chart deployments are production-ready with proper security, reliability, and operational practices.

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Deployment Configuration](#deployment-configuration)
3. [Security Checklist](#security-checklist)
4. [High Availability Checklist](#high-availability-checklist)
5. [Monitoring & Observability](#monitoring--observability)
6. [Backup & Disaster Recovery](#backup--disaster-recovery)
7. [Post-Deployment Verification](#post-deployment-verification)
8. [Operational Readiness](#operational-readiness)
9. [Chart-Specific Checklists](#chart-specific-checklists)

---

## Pre-Deployment Checklist

### Infrastructure Readiness

- [ ] **Kubernetes cluster is production-ready**
  - [ ] Running Kubernetes 1.24+ (minimum supported version)
  - [ ] At least 3 worker nodes for HA workloads
  - [ ] Node resources meet chart requirements
  - [ ] Cluster has monitoring (Prometheus/Grafana) installed

- [ ] **Storage provisioning configured**
  - [ ] Dynamic storage provisioner available
  - [ ] Storage class created and tested
  - [ ] Sufficient disk space on nodes
  - [ ] Backup solution for persistent volumes in place

- [ ] **Networking configured**
  - [ ] Ingress controller installed (nginx/traefik)
  - [ ] Load balancer provisioner configured (MetalLB/cloud LB)
  - [ ] DNS records created for services
  - [ ] TLS certificates obtained (cert-manager/manual)
  - [ ] Network policies planned (if using)

- [ ] **Container registry access**
  - [ ] Public images accessible (or mirrored internally)
  - [ ] Image pull secrets created for private registries
  - [ ] Registry has high availability and backup

### Database Readiness (if required)

- [ ] **External database deployed**
  - [ ] PostgreSQL 13+, MySQL 8+, or MariaDB 10.6+ running
  - [ ] Database is production-hardened
  - [ ] Automatic backups configured
  - [ ] Point-in-time recovery tested
  - [ ] Connection pooling configured (PgBouncer/ProxySQL)

- [ ] **Database credentials secured**
  - [ ] Strong passwords generated
  - [ ] Passwords stored in Kubernetes Secrets
  - [ ] Database user has minimum required privileges
  - [ ] Separate database users per application (recommended)

- [ ] **Database connectivity tested**
  - [ ] Can connect from Kubernetes cluster
  - [ ] SSL/TLS encryption enabled (if required)
  - [ ] Firewall rules allow connections
  - [ ] Connection limits configured appropriately

### Redis Readiness (if required)

- [ ] **Redis cluster deployed**
  - [ ] Redis 6+ running
  - [ ] Persistence configured (RDB + AOF)
  - [ ] Memory limits set appropriately
  - [ ] Password authentication enabled
  - [ ] Automatic backups configured

- [ ] **Redis architecture chosen**
  - [ ] Single instance (dev/test)
  - [ ] Master-replica (production single-datacenter)
  - [ ] Sentinel (HA - consider Redis Operator)
  - [ ] Cluster (sharding - consider Redis Operator)

---

## Deployment Configuration

### Values File Review

- [ ] **Use production values file**
  - [ ] Started from `values-prod-*.yaml` template
  - [ ] Reviewed all default values
  - [ ] Customized for your environment
  - [ ] Secrets replaced with real values (not example values)

- [ ] **Resource sizing configured**
  - [ ] CPU requests/limits set based on expected load
  - [ ] Memory requests/limits set based on application requirements
  - [ ] Storage sizes appropriate for data volume
  - [ ] Tested resource limits in staging environment

- [ ] **Environment-specific settings**
  - [ ] Hostnames/domains configured
  - [ ] Database connection strings set
  - [ ] External service URLs configured
  - [ ] Time zones set correctly
  - [ ] Localization configured

### Image Configuration

- [ ] **Production image tags**
  - [ ] Using specific version tags (NOT `latest`)
  - [ ] Image versions tested in staging
  - [ ] Security vulnerabilities scanned
  - [ ] Images pulled from trusted registry

- [ ] **Image pull policy**
  - [ ] Set to `IfNotPresent` or `Always` (not `Never`)
  - [ ] imagePullSecrets configured if needed

### Replica Configuration

- [ ] **Replica count set appropriately**
  - [ ] At least 2 replicas for stateless apps
  - [ ] 1 replica for stateful apps with RWO volumes
  - [ ] Consider using HorizontalPodAutoscaler

---

## Security Checklist

### Authentication & Authorization

- [ ] **Strong credentials configured**
  - [ ] All default passwords changed
  - [ ] Passwords meet complexity requirements (12+ chars, mixed case, numbers, symbols)
  - [ ] Admin credentials documented securely (password manager)
  - [ ] Service account credentials unique per environment

- [ ] **RBAC configured**
  - [ ] ServiceAccount created per application
  - [ ] Minimal Role/RoleBinding permissions
  - [ ] ClusterRole only if truly needed
  - [ ] Reviewed generated RBAC permissions

- [ ] **Network security**
  - [ ] NetworkPolicy created to restrict traffic
  - [ ] Only required ports exposed
  - [ ] Internal services not exposed externally
  - [ ] Database access restricted to application pods

### Secret Management

- [ ] **Secrets properly stored**
  - [ ] All secrets in Kubernetes Secrets (not ConfigMaps)
  - [ ] Secrets encrypted at rest (Kubernetes encryption)
  - [ ] External secret management considered (Vault/Sealed Secrets/External Secrets Operator)
  - [ ] Secrets not committed to git
  - [ ] Secret rotation procedure documented

- [ ] **Secret referencing**
  - [ ] Using `existingSecret` pattern where supported
  - [ ] Secrets mounted as volumes (not env vars) where possible
  - [ ] Secret keys match expected format

### Container Security

- [ ] **Security context configured**
  - [ ] Containers run as non-root user
  - [ ] Read-only root filesystem (where supported)
  - [ ] Capabilities dropped (drop ALL, add specific)
  - [ ] seccompProfile set to RuntimeDefault
  - [ ] Privilege escalation disabled

- [ ] **Pod security standards**
  - [ ] Namespace has PodSecurityStandard labels
  - [ ] Pods meet restricted or baseline standard
  - [ ] SecurityContext enforced

### TLS/SSL Configuration

- [ ] **TLS enabled for external traffic**
  - [ ] Valid TLS certificates installed
  - [ ] Certificate expiration monitoring configured
  - [ ] Auto-renewal configured (cert-manager)
  - [ ] Redirect HTTP to HTTPS

- [ ] **TLS for internal traffic (optional)**
  - [ ] Database connections use TLS
  - [ ] Redis connections use TLS
  - [ ] Service mesh configured (Istio/Linkerd)

---

## High Availability Checklist

### Pod Distribution

- [ ] **Anti-affinity rules configured**
  - [ ] Pod anti-affinity to spread replicas across nodes
  - [ ] Topology spread constraints for even distribution
  - [ ] Zone anti-affinity for multi-zone deployments

- [ ] **Node selection**
  - [ ] nodeSelector for workload isolation (optional)
  - [ ] Tolerations for tainted nodes (if applicable)
  - [ ] Node affinity for performance requirements

### Disruption Management

- [ ] **PodDisruptionBudget configured**
  - [ ] minAvailable or maxUnavailable set
  - [ ] Allows cluster maintenance without downtime
  - [ ] Tested with node drain operations

- [ ] **Update strategy**
  - [ ] RollingUpdate strategy configured
  - [ ] maxUnavailable and maxSurge set appropriately
  - [ ] Update tested in staging

### Health Probes

- [ ] **Liveness probe configured**
  - [ ] Appropriate endpoint/command
  - [ ] initialDelaySeconds allows for startup
  - [ ] failureThreshold prevents premature restarts
  - [ ] Tested manually

- [ ] **Readiness probe configured**
  - [ ] Checks application is ready to serve traffic
  - [ ] More sensitive than liveness probe
  - [ ] Tested during rolling updates

- [ ] **Startup probe configured (for slow-starting apps)**
  - [ ] Allows long initialization time
  - [ ] Prevents liveness probe from killing during startup

### Autoscaling

- [ ] **HorizontalPodAutoscaler configured (optional)**
  - [ ] Target CPU/memory utilization set
  - [ ] Min/max replicas defined
  - [ ] Metrics server installed
  - [ ] Scale-up/down behavior tested

- [ ] **Vertical Pod Autoscaler considered (optional)**
  - [ ] VPA installed if using
  - [ ] Update mode configured
  - [ ] Resource recommendations reviewed

---

## Monitoring & Observability

### Metrics Collection

- [ ] **Prometheus metrics exposed**
  - [ ] Application exposes /metrics endpoint
  - [ ] ServiceMonitor created (if using Prometheus Operator)
  - [ ] Custom metrics configured
  - [ ] Metrics validated in Prometheus UI

- [ ] **Key metrics monitored**
  - [ ] Application-specific metrics (requests, errors, latency)
  - [ ] Resource usage (CPU, memory, disk)
  - [ ] Database connection pool metrics
  - [ ] Cache hit rates (Redis)

### Logging

- [ ] **Centralized logging configured**
  - [ ] Logs sent to central system (ELK/Loki/CloudWatch)
  - [ ] Log aggregation tested
  - [ ] Log retention policy set
  - [ ] Log queries documented

- [ ] **Structured logging**
  - [ ] JSON log format (if supported)
  - [ ] Appropriate log levels set
  - [ ] Sensitive data not logged
  - [ ] Request IDs for tracing

### Alerting

- [ ] **Alerts configured**
  - [ ] Pod restarts alert
  - [ ] High error rate alert
  - [ ] Resource exhaustion alert
  - [ ] Certificate expiration alert
  - [ ] Backup failure alert

- [ ] **Alert routing**
  - [ ] AlertManager configured
  - [ ] On-call rotation defined
  - [ ] Escalation policy documented
  - [ ] Alert channels tested (PagerDuty/Slack/Email)

### Tracing (optional)

- [ ] **Distributed tracing configured**
  - [ ] Jaeger/Zipkin/Tempo configured
  - [ ] Application instrumented
  - [ ] Service dependencies mapped

---

## Backup & Disaster Recovery

### Backup Strategy

- [ ] **Database backups automated**
  - [ ] Daily full backups
  - [ ] Point-in-time recovery configured
  - [ ] Backup retention policy (30+ days)
  - [ ] Backups stored offsite/off-cluster
  - [ ] Backup encryption enabled

- [ ] **Persistent volume backups**
  - [ ] VolumeSnapshot configuration
  - [ ] Snapshot schedule configured (Velero/Kasten)
  - [ ] Snapshots tested for restore
  - [ ] Cross-region replication (for critical data)

- [ ] **Configuration backups**
  - [ ] Helm values files in version control
  - [ ] Secrets backed up securely
  - [ ] Kubernetes manifests exported
  - [ ] Infrastructure-as-code (Terraform/Pulumi)

### Disaster Recovery

- [ ] **Recovery procedures documented**
  - [ ] Step-by-step restore instructions
  - [ ] RTO (Recovery Time Objective) defined
  - [ ] RPO (Recovery Point Objective) defined
  - [ ] Runbooks created for common failures

- [ ] **DR testing**
  - [ ] Database restore tested
  - [ ] Full application restore tested
  - [ ] Failover to secondary region tested (if multi-region)
  - [ ] DR test schedule defined (quarterly minimum)

### Chart-Specific Backup Commands

```bash
# Redis backups
make -f make/ops/redis.mk redis-backup

# WordPress backups (database + wp-content)
make -f make/ops/wordpress.mk wp-backup

# Keycloak realm exports
make -f make/ops/keycloak.mk kc-backup-all-realms

# Uptime Kuma database backup
make -f make/ops/uptime-kuma.mk uk-backup-sqlite
```

---

## Post-Deployment Verification

### Deployment Health

- [ ] **All pods running**
  - [ ] `kubectl get pods` shows all Running
  - [ ] No CrashLoopBackOff or Error states
  - [ ] Pods pass readiness probes
  - [ ] Check events: `kubectl get events`

- [ ] **Services accessible**
  - [ ] ClusterIP services reachable internally
  - [ ] Ingress/LoadBalancer services accessible externally
  - [ ] DNS resolution working
  - [ ] Test with curl/browser

### Functionality Testing

- [ ] **Application works**
  - [ ] Login with admin credentials
  - [ ] Create test data
  - [ ] Verify integrations (database, Redis, external APIs)
  - [ ] Test key workflows

- [ ] **Performance acceptable**
  - [ ] Response times meet SLAs
  - [ ] Resource usage within limits
  - [ ] No memory leaks observed
  - [ ] Database queries optimized

### Security Verification

- [ ] **Security scan passed**
  - [ ] Container image scan (Trivy/Snyk)
  - [ ] Kubernetes config scan (kubesec/Polaris)
  - [ ] Network policy working (test blocked connections)
  - [ ] Secrets not exposed in logs

- [ ] **Penetration testing (for critical apps)**
  - [ ] OWASP Top 10 vulnerabilities checked
  - [ ] SQL injection tested
  - [ ] XSS tested
  - [ ] Authentication bypass tested

### Monitoring Verification

- [ ] **Metrics flowing**
  - [ ] Prometheus scraping targets
  - [ ] Grafana dashboards showing data
  - [ ] Custom metrics working

- [ ] **Logs flowing**
  - [ ] Application logs in centralized system
  - [ ] Log queries return results
  - [ ] Error logs visible

- [ ] **Alerts working**
  - [ ] Test alerts trigger correctly
  - [ ] Alert notifications received
  - [ ] Runbooks linked in alerts

---

## Operational Readiness

### Documentation

- [ ] **Deployment documented**
  - [ ] Architecture diagram created
  - [ ] Component dependencies mapped
  - [ ] Configuration decisions documented
  - [ ] Contact information for escalations

- [ ] **Runbooks created**
  - [ ] Common operations documented
  - [ ] Troubleshooting guide available (see `docs/TROUBLESHOOTING.md`)
  - [ ] Scaling procedures documented
  - [ ] Backup/restore procedures documented

- [ ] **Change management**
  - [ ] Deployment process documented
  - [ ] Rollback procedure defined
  - [ ] Change approval workflow
  - [ ] Maintenance windows scheduled

### Team Readiness

- [ ] **Team trained**
  - [ ] Operators familiar with application
  - [ ] Access to documentation
  - [ ] Access to monitoring/logging systems
  - [ ] On-call rotation defined

- [ ] **Access control**
  - [ ] RBAC configured for team members
  - [ ] Break-glass procedures for emergencies
  - [ ] Access regularly reviewed
  - [ ] Audit logging enabled

### Maintenance Planning

- [ ] **Update strategy defined**
  - [ ] Security patch process
  - [ ] Minor version upgrade process
  - [ ] Major version upgrade process
  - [ ] Testing procedure for updates

- [ ] **Capacity planning**
  - [ ] Growth projections documented
  - [ ] Scaling thresholds defined
  - [ ] Resource monitoring for trends
  - [ ] Budget for infrastructure growth

---

## Chart-Specific Checklists

### Keycloak

- [ ] **Keycloak-specific checks**
  - [ ] PostgreSQL 13+ database configured
  - [ ] Hostname v2 configuration set correctly
  - [ ] Admin credentials secured
  - [ ] Realms imported/configured
  - [ ] Clustering working (if multi-replica)
  - [ ] Health endpoints on port 9000 working
  - [ ] Prometheus metrics enabled
  - [ ] SSL/TLS for database (if required)
  - [ ] Backup realm exports automated
  - [ ] Identity provider integrations tested

**Verify clustering:**
```bash
make -f make/ops/keycloak.mk kc-cluster-status
make -f make/ops/keycloak.mk kc-metrics
```

### Redis

- [ ] **Redis-specific checks**
  - [ ] Architecture chosen (standalone/replication)
  - [ ] ⚠️ NOT using Sentinel/Cluster values (not implemented)
  - [ ] Password authentication enabled
  - [ ] Persistence enabled (AOF + RDB)
  - [ ] Replication working (if master-replica)
  - [ ] Memory limits configured
  - [ ] Eviction policy set
  - [ ] Backup schedule configured

**For master-replica deployments:**
```bash
make -f make/ops/redis.mk redis-replication-info
make -f make/ops/redis.mk redis-replica-lag
```

**Production alternative for HA:**
- Consider [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)

### RabbitMQ

- [ ] **RabbitMQ-specific checks**
  - [ ] ⚠️ Single-instance deployment (clustering not implemented)
  - [ ] Management UI accessible
  - [ ] Default credentials changed
  - [ ] Prometheus metrics enabled
  - [ ] Virtual hosts configured
  - [ ] User permissions set
  - [ ] Queue policies configured
  - [ ] Memory/disk alarms configured

**Verify status:**
```bash
make -f make/ops/rabbitmq.mk rmq-status
make -f make/ops/rabbitmq.mk rmq-metrics
```

**Production alternative for clustering:**
- Use [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)
- Or [Bitnami RabbitMQ chart](https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq)

### Memcached

- [ ] **Memcached-specific checks**
  - [ ] ⚠️ No replication (each instance independent)
  - [ ] Client-side consistent hashing configured
  - [ ] Memory limits configured
  - [ ] Multiple instances for distribution
  - [ ] Application knows all memcached IPs
  - [ ] Monitoring connection counts

**Verify status:**
```bash
make -f make/ops/memcached.mk mc-stats
```

### WordPress

- [ ] **WordPress-specific checks**
  - [ ] MySQL/MariaDB configured
  - [ ] PHP memory limits set appropriately
  - [ ] wp-content permissions correct
  - [ ] Plugins installed and activated
  - [ ] Theme configured
  - [ ] Permalink structure set
  - [ ] Search engine indexing configured
  - [ ] Backup automated (files + database)

**Operations:**
```bash
make -f make/ops/wordpress.mk wp-cli CMD="plugin list"
make -f make/ops/wordpress.mk wp-update
```

### Nextcloud

- [ ] **Nextcloud-specific checks**
  - [ ] PostgreSQL + Redis configured
  - [ ] Data directory mounted
  - [ ] Config directory persisted
  - [ ] Cron jobs running
  - [ ] Apps installed/updated
  - [ ] External storage configured (if used)
  - [ ] Preview generation working
  - [ ] Email configured

### Paperless-ngx

- [ ] **Paperless-ngx-specific checks**
  - [ ] PostgreSQL + Redis configured
  - [ ] All 4 PVCs created (data, media, consume, export)
  - [ ] OCR languages installed
  - [ ] Tika container running (for Office docs)
  - [ ] Gotenberg container running (for PDFs)
  - [ ] Consumption directory monitored
  - [ ] Document retention policies set

**Verify components:**
```bash
make -f make/ops/paperless-ngx.mk paperless-check-db
make -f make/ops/paperless-ngx.mk paperless-check-redis
make -f make/ops/paperless-ngx.mk paperless-check-storage
```

### Uptime Kuma

- [ ] **Uptime Kuma-specific checks**
  - [ ] Database choice (SQLite or MariaDB)
  - [ ] Single replica for SQLite
  - [ ] Monitors configured
  - [ ] Notification channels set up
  - [ ] Status pages created (if public)
  - [ ] Maintenance windows scheduled
  - [ ] Backup automated

**Operations:**
```bash
make -f make/ops/uptime-kuma.mk uk-backup-sqlite
make -f make/ops/uptime-kuma.mk uk-version
```

### Vaultwarden

- [ ] **Vaultwarden-specific checks**
  - [ ] Admin token secured
  - [ ] Admin panel access restricted
  - [ ] SMTP configured for invitations
  - [ ] Database backend chosen (SQLite or external)
  - [ ] Backups automated and tested
  - [ ] 2FA enabled for admin account
  - [ ] Organization features tested

### Immich

- [ ] **Immich-specific checks**
  - [ ] PostgreSQL + Redis configured
  - [ ] Microservices deployment working
  - [ ] Machine learning container running
  - [ ] Upload directory mounted
  - [ ] Library directory mounted
  - [ ] Thumbnail generation working
  - [ ] Face detection enabled (if desired)
  - [ ] Mobile app can connect

### Jellyfin

- [ ] **Jellyfin-specific checks**
  - [ ] Media directories mounted
  - [ ] Hardware transcoding configured (if GPU available)
  - [ ] Library scanning working
  - [ ] User accounts created
  - [ ] Streaming quality settings configured
  - [ ] DLNA enabled (if desired)

### WireGuard

- [ ] **WireGuard-specific checks**
  - [ ] NET_ADMIN capability granted
  - [ ] Peer configurations created
  - [ ] Server endpoint accessible (LoadBalancer or NodePort)
  - [ ] Clients can connect
  - [ ] Routing configured correctly
  - [ ] Interface wg0 up

**Operations:**
```bash
make -f make/ops/wireguard.mk wg-show
make -f make/ops/wireguard.mk wg-endpoint
make -f make/ops/wireguard.mk wg-get-peer PEER=peer1
```

---

## Final Sign-Off

### Approval Checklist

- [ ] **Technical approval**
  - [ ] Deployment reviewed by senior engineer
  - [ ] Security team approval (for security-critical apps)
  - [ ] Architecture approved
  - [ ] Risks documented and accepted

- [ ] **Business approval**
  - [ ] Stakeholders notified
  - [ ] Deployment window approved
  - [ ] Budget approved
  - [ ] SLA commitments documented

- [ ] **Go/No-Go decision**
  - [ ] All critical items checked
  - [ ] Rollback plan ready
  - [ ] On-call coverage confirmed
  - [ ] Communication plan in place

### Post-Deployment Review (after 1 week)

- [ ] **Stability review**
  - [ ] No unexpected restarts
  - [ ] Performance meets expectations
  - [ ] No critical errors in logs
  - [ ] Resource usage stable

- [ ] **Operations review**
  - [ ] Monitoring effective
  - [ ] Alerts appropriately tuned
  - [ ] Runbooks accurate
  - [ ] Team comfortable operating

- [ ] **Continuous improvement**
  - [ ] Lessons learned documented
  - [ ] Process improvements identified
  - [ ] Documentation updates made
  - [ ] Next deployment planned

---

## Additional Resources

- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions for production deployments
- [Testing Guide](TESTING_GUIDE.md) - Comprehensive testing procedures for all deployment scenarios
- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md) - Development patterns and standards
- [Chart Version Policy](CHART_VERSION_POLICY.md) - Semantic versioning and release process
- [Analysis Report](05-chart-analysis-2025-11.md) - Comprehensive analysis of all charts
- [Scenario Values Guide](SCENARIO_VALUES_GUIDE.md) - Deployment scenarios explained

---

## Checklist Template

Copy this template for each production deployment:

```markdown
# Production Deployment: [Chart Name] - [Environment]

**Date**: YYYY-MM-DD
**Deployer**: [Name]
**Chart Version**: [Version]
**App Version**: [Version]

## Pre-Deployment
- [ ] Infrastructure ready
- [ ] Database ready
- [ ] Values file reviewed
- [ ] Security review complete
- [ ] Backup plan in place

## Deployment
- [ ] Deployed successfully
- [ ] All pods running
- [ ] Health checks passing
- [ ] Application functional

## Post-Deployment
- [ ] Metrics flowing
- [ ] Logs centralized
- [ ] Alerts configured
- [ ] Documentation updated
- [ ] Team notified

## Sign-Off
- [ ] Technical approval: [Name]
- [ ] Business approval: [Name]
- [ ] Deployment complete: [Name]

**Notes**: [Any special considerations or issues]
```

---

**Document maintained by**: ScriptonBasestar Helm Charts
**Repository**: https://github.com/ScriptonBasestar-containers/sb-helm-charts
