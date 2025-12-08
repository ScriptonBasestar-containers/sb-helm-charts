# Paperless-ngx Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/paperless-ngx)

A powerful document management system with OCR, full-text search, and modern web UI for Kubernetes.

## Features

- 📄 **Document Management**: Scan, index, and archive documents with OCR
- 🔍 **Full-Text Search**: Find documents instantly with powerful search
- 🏷️ **Smart Tagging**: Auto-tag documents with machine learning
- 📧 **Email Integration**: Import documents from email
- 📱 **Mobile Apps**: iOS and Android support
- 🔐 **Multi-User**: User management with permissions
- 🌍 **Multi-Language OCR**: Support for 100+ languages

## Prerequisites

## Deployment Scenarios

This chart includes three pre-configured deployment scenarios optimized for different use cases:

### Home Server (`values-home-single.yaml`)

Minimal resources for personal servers, home labs, Raspberry Pi, or Intel NUC:

```bash
helm install paperless-home charts/paperless-ngx \
  -f charts/paperless-ngx/values-home-single.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 100-500m CPU, 256-512Mi RAM, 15Gi total storage (4 PVCs)

### Startup Environment (`values-startup-single.yaml`)

Balanced configuration for small teams, startups, and development environments:

```bash
helm install paperless-startup charts/paperless-ngx \
  -f charts/paperless-ngx/values-startup-single.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Resource allocation:** 250m-1000m CPU, 512Mi-1Gi RAM, 50Gi total storage (4 PVCs)

### Production HA (`values-prod-master-replica.yaml`)

High availability deployment with monitoring and enhanced storage:

```bash
helm install paperless-prod charts/paperless-ngx \
  -f charts/paperless-ngx/values-prod-master-replica.yaml \
  --set postgresql.external.password=your-db-password \
  --set postgresql.external.host=postgres.default.svc.cluster.local
```

**Features:** PodDisruptionBudget, NetworkPolicy, ServiceMonitor, enhanced OCR resources

**Resource allocation:** 500m-2000m CPU, 1-2Gi RAM, 200Gi total storage (4 PVCs)

For detailed comparison and configuration examples, see the [Scenario Values Guide](../../docs/SCENARIO_VALUES_GUIDE.md#paperless-ngx).


- Kubernetes 1.22+
- Helm 3.0+
- **External PostgreSQL** 13+ (required)
- **External Redis** 6+ (required)
- PersistentVolume provisioner

## Quick Start

### 1. Prepare External Services

```bash
# Install PostgreSQL (example using sb-helm-charts)
helm install postgres ./charts/postgresql \
  --set auth.database=paperless \
  --set auth.username=paperless \
  --set auth.password=paperless123

# Install Redis
helm install redis ./charts/redis
```

### 2. Generate Secret Key

```bash
openssl rand -base64 32
# Save this for values.yaml
```

### 3. Install Paperless-ngx

Create `my-values.yaml`:

```yaml
paperless:
  adminUser: "admin"
  adminPassword: "changeme123"
  adminEmail: "admin@example.com"
  secretKey: "YOUR_GENERATED_SECRET_KEY"  # From step 2
  url: "http://paperless.local"

postgresql:
  external:
    enabled: true
    host: "postgres-postgresql"
    password: "paperless123"

redis:
  external:
    enabled: true
    host: "redis"
```

Install the chart:

```bash
helm install paperless ./charts/paperless-ngx -f my-values.yaml
```

### 4. Access Paperless-ngx

```bash
kubectl port-forward svc/paperless-paperless-ngx 8000:8000
# Visit http://localhost:8000
# Login: admin / changeme123
```

## Configuration

### Required Settings

| Parameter | Description | Example |
|-----------|-------------|---------|
| `paperless.adminPassword` | Admin user password | `"changeme123"` |
| `paperless.secretKey` | Secret key for encryption | Generated with openssl |
| `postgresql.external.host` | PostgreSQL host | `"postgres-postgresql"` |
| `postgresql.external.password` | Database password | `"dbpass123"` |
| `redis.external.host` | Redis host | `"redis"` |

### OCR Configuration

```yaml
paperless:
  ocr:
    language: "eng+deu+fra"  # English, German, French
    mode: "skip"  # skip, redo, force
```

**Available Languages**: eng, deu, fra, spa, ita, nld, por, pol, rus, chi-sim, chi-tra, jpn, kor, ara

### Persistence Configuration

```yaml
persistence:
  enabled: true
  consume:
    size: 10Gi  # Incoming documents
  data:
    size: 10Gi  # Application data
  media:
    size: 50Gi  # Processed documents
  export:
    size: 10Gi  # Exports and backups
```

## S3 Object Storage

Paperless-ngx can store documents in S3-compatible object storage instead of local PVCs, significantly reducing storage requirements.

### Quick Configuration

```yaml
paperless:
  extraEnv:
    - name: PAPERLESS_STORAGE_TYPE
      value: "s3"
    - name: PAPERLESS_AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: paperless-s3-credentials
          key: access-key-id
    - name: PAPERLESS_AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: paperless-s3-credentials
          key: secret-access-key
    - name: PAPERLESS_AWS_STORAGE_BUCKET_NAME
      value: "paperless-documents"
    - name: PAPERLESS_AWS_S3_ENDPOINT_URL
      value: "http://minio.default.svc.cluster.local:9000"
    - name: PAPERLESS_AWS_S3_REGION_NAME
      value: "us-east-1"
```

Create S3 credentials secret:
```bash
kubectl create secret generic paperless-s3-credentials \
  --from-literal=access-key-id=paperless-user \
  --from-literal=secret-access-key=paperless-secure-password
```

### Reduced PVC Sizes with S3

When using S3 storage, reduce PVC sizes significantly:

```yaml
persistence:
  data:
    size: 5Gi      # Reduced from 50Gi (only for thumbnails/cache)
  media:
    size: 2Gi      # Reduced from 10Gi (temp files only)
  consume:
    size: 2Gi      # Inbox for new documents
  export:
    size: 2Gi      # Export destination
```

**Benefits:**
- Massive storage cost reduction (documents stored in S3, not PVCs)
- Scalable storage independent of Kubernetes volumes
- Simplified backup and disaster recovery
- Multi-region replication support

For complete S3 integration guide including MinIO setup, bucket creation, and security best practices, see the [S3 Integration Guide](../../docs/S3_INTEGRATION_GUIDE.md#paperless-ngx-document-storage).

### Email Integration

```yaml
paperless:
  email:
    enabled: true
    host: "smtp.gmail.com"
    port: 587
    username: "your-email@gmail.com"
    password: "your-app-password"
    from: "paperless@example.com"
    useTLS: true
```

## Document Upload Methods

### 1. Web UI

Visit `http://your-server:8000/upload/`

### 2. File System

Copy files to the consume directory:

```bash
kubectl cp document.pdf paperless-paperless-ngx-0:/usr/src/paperless/consume/
```

### 3. Email

Configure email settings and send documents as attachments.

### 4. Mobile Apps

- **iOS**: Paperless Mobile
- **Android**: Paperless Mobile

## Production Features

### High Availability

```yaml
replicaCount: 2

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

### Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: paperless.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: paperless-tls
      hosts:
        - paperless.example.com
```

### Network Security

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: production
      ports:
        - protocol: TCP
          port: 8000
```

## Storage Directories

| Directory | Purpose | Default Size |
|-----------|---------|--------------|
| `/consume` | Incoming documents for processing | 10Gi |
| `/data` | Application data and search index | 10Gi |
| `/media` | Processed documents (PDF, thumbnails) | 50Gi |
| `/export` | Document exports and backups | 10Gi |

## Operational Commands

This chart includes a comprehensive Makefile for day-2 operations:

```bash
# View logs and access shell
make -f make/ops/paperless-ngx.mk paperless-logs
make -f make/ops/paperless-ngx.mk paperless-shell

# Port forward to localhost:8000
make -f make/ops/paperless-ngx.mk paperless-port-forward

# Health checks
make -f make/ops/paperless-ngx.mk paperless-check-db
make -f make/ops/paperless-ngx.mk paperless-check-redis
make -f make/ops/paperless-ngx.mk paperless-check-storage

# Database management
make -f make/ops/paperless-ngx.mk paperless-migrate
make -f make/ops/paperless-ngx.mk paperless-create-superuser

# Document operations
make -f make/ops/paperless-ngx.mk paperless-document-exporter
make -f make/ops/paperless-ngx.mk paperless-consume-list
make -f make/ops/paperless-ngx.mk paperless-process-status

# Restart deployment
make -f make/ops/paperless-ngx.mk paperless-restart

# Full help
make -f make/ops/paperless-ngx.mk help
```

## Troubleshooting

### OCR Not Working

Check OCR language installation:

```bash
kubectl exec deployment/paperless-paperless-ngx -- tesseract --list-langs
```

Install additional languages:

```yaml
extraEnv:
  - name: PAPERLESS_OCR_LANGUAGES
    value: "eng deu fra spa"
```

### High Memory Usage

Adjust resource limits:

```yaml
resources:
  limits:
    memory: 4Gi
  requests:
    memory: 1Gi
```

### Slow Document Processing

Increase worker resources or add more replicas:

```yaml
replicaCount: 3

resources:
  requests:
    cpu: 1000m
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `paperless.adminPassword` | string | `""` | Admin password (required) |
| `paperless.secretKey` | string | `""` | Secret key (required) |
| `paperless.url` | string | `"http://localhost:8000"` | Public URL |
| `paperless.ocr.language` | string | `"eng"` | OCR language code |
| `postgresql.external.host` | string | `""` | PostgreSQL host (required) |
| `redis.external.host` | string | `""` | Redis host (required) |
| `persistence.media.size` | string | `"50Gi"` | Media storage size |

For full configuration options, see [values.yaml](./values.yaml).

## Backup & Recovery

Comprehensive backup procedures ensure document safety and system recoverability.

### Backup Strategy

**4-Layer Backup Approach:**
1. **Documents** - PDF files, images, OCR data (PVCs: consume, data, media, export)
2. **Database** - PostgreSQL (document metadata, tags, correspondents, custom fields)
3. **Redis** - Task queue state (optional, can be rebuilt)
4. **Configuration** - Kubernetes manifests, Helm values, PVC snapshots

**RTO/RPO Targets:**
- **RTO (Recovery Time Objective)**: < 2 hours
- **RPO (Recovery Point Objective)**: 24 hours (daily backups)

### Quick Backup Commands

```bash
# Full backup (all components)
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Component-specific backups
make -f make/ops/paperless-ngx.mk paperless-backup-documents
make -f make/ops/paperless-ngx.mk paperless-backup-database
make -f make/ops/paperless-ngx.mk paperless-backup-helm-values

# Create PVC snapshots (requires VolumeSnapshot CRD)
make -f make/ops/paperless-ngx.mk paperless-create-pvc-snapshots

# Incremental document backup (rsync)
make -f make/ops/paperless-ngx.mk paperless-backup-documents-incremental

# Backup to S3/MinIO
make -f make/ops/paperless-ngx.mk paperless-backup-documents-s3
```

### Recovery Procedures

```bash
# Restore documents from backup
make -f make/ops/paperless-ngx.mk paperless-restore-documents BACKUP_DATE=20241208_100000

# Restore database from backup
make -f make/ops/paperless-ngx.mk paperless-restore-database BACKUP_DATE=20241208_100000

# Restore Helm configuration
make -f make/ops/paperless-ngx.mk paperless-restore-helm-values BACKUP_DATE=20241208_100000

# Full disaster recovery (complete system rebuild)
make -f make/ops/paperless-ngx.mk paperless-full-recovery BACKUP_DATE=20241208_100000
```

### Document Backup Components

| Component | Path | Purpose | Backup Method |
|-----------|------|---------|---------------|
| **Consume** | `/usr/src/paperless/consume` | Incoming documents | tar/rsync + PVC snapshot |
| **Data** | `/usr/src/paperless/data` | App data, search index | tar/rsync + PVC snapshot |
| **Media** | `/usr/src/paperless/media` | Processed docs, OCR | tar/rsync + PVC snapshot |
| **Export** | `/usr/src/paperless/export` | Document exports | tar/rsync + PVC snapshot |

### Database Backup

**PostgreSQL backup via pg_dump:**
```bash
# Custom format (recommended for recovery)
make -f make/ops/paperless-ngx.mk paperless-backup-database

# Plain SQL format (for version control)
make -f make/ops/paperless-ngx.mk paperless-backup-database-sql

# Schema only (for testing)
make -f make/ops/paperless-ngx.mk paperless-backup-database-schema
```

**Key database tables:**
- `documents_document` - Document metadata
- `documents_tag` - Tags
- `documents_correspondent` - Correspondents
- `documents_documenttype` - Document types
- `documents_customfield` - Custom fields
- `auth_user` - User accounts and permissions

### Redis Backup (Optional)

Redis stores task queue state and caching data. Can be rebuilt from database if lost.

```bash
# Trigger Redis BGSAVE
make -f make/ops/paperless-ngx.mk paperless-backup-redis
```

### PVC Snapshots (VolumeSnapshot API)

**Requirements:**
- CSI driver with snapshot support
- VolumeSnapshotClass configured

```bash
# Create snapshots for all PVCs
make -f make/ops/paperless-ngx.mk paperless-create-pvc-snapshots

# List existing snapshots
kubectl get volumesnapshot -n default

# Restore from snapshot (disaster recovery)
# See full procedure in backup guide
```

### Backup Best Practices

1. **Daily Backups**: Automate daily backups at low-traffic periods
2. **Off-Cluster Storage**: Store backups in S3/MinIO/NFS (not same cluster)
3. **3-2-1 Rule**: 3 copies, 2 media types, 1 off-site
4. **Retention Policy**:
   - Daily: 7 days
   - Weekly: 4 weeks
   - Monthly: 12 months
5. **Test Recovery**: Monthly test restore in non-production namespace
6. **Encrypt Backups**: Use GPG for sensitive document backups

### Backup Automation Example

```bash
# Automated daily backup (cron example)
# Add to cluster automation:

# Daily full backup at 2 AM
0 2 * * * /path/to/scripts/paperless-full-backup.sh

# Weekly off-cluster backup to S3 (Sunday 3 AM)
0 3 * * 0 /path/to/scripts/paperless-backup-s3.sh

# Cleanup old backups (keep last 7 days)
0 4 * * * find /backups/paperless -type d -name "202*" -mtime +7 -exec rm -rf {} \;
```

### Backup Validation

```bash
# Verify backup integrity
ls -lh /backups/paperless-ngx/20241208_100000/

# Expected files:
# - consume.tar.gz
# - data.tar.gz
# - media.tar.gz (largest file)
# - export.tar.gz
# - paperless-db.dump
# - helm-values.yaml
# - volumesnapshots.yaml

# Test database backup readability
pg_restore --list /backups/paperless-ngx/20241208_100000/paperless-db.dump | head -20
```

**For detailed backup procedures, recovery workflows, and troubleshooting, see:**
- **[Paperless-ngx Backup Guide](../../docs/paperless-ngx-backup-guide.md)** - Comprehensive backup and recovery procedures

---

## Security & RBAC

Paperless-ngx chart includes comprehensive RBAC (Role-Based Access Control) templates for production security.

### RBAC Configuration

**Enable RBAC (default: enabled):**
```yaml
rbac:
  create: true
  annotations: {}
```

**What RBAC Provides:**
- **ServiceAccount**: Dedicated identity for Paperless-ngx pods
- **Role**: Namespace-scoped permissions (read-only access)
- **RoleBinding**: Links ServiceAccount to Role

### RBAC Permissions

The Role grants **read-only** access to:

| Resource | Permissions | Purpose |
|----------|-------------|---------|
| **ConfigMaps** | get, list, watch | Read configuration |
| **Secrets** | get, list, watch | Access credentials (database, Redis, admin password) |
| **Pods** | get, list, watch | Health checks and operations |
| **Services** | get, list, watch | Service discovery |
| **Endpoints** | get, list, watch | Service discovery |
| **PersistentVolumeClaims** | get, list, watch | Storage operations |

**Security Principle**: Least privilege - only read access, no write/delete permissions.

### ServiceAccount Usage

The chart automatically creates and uses a ServiceAccount:

```yaml
serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""  # Auto-generated: paperless-ngx-{release-name}
```

**Custom ServiceAccount:**
```yaml
serviceAccount:
  create: false
  name: "my-custom-sa"
```

### Pod Security Context

**Default security settings:**
```yaml
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false  # Paperless needs write access to temp dirs
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
```

**Why `readOnlyRootFilesystem: false`:**
- Paperless-ngx requires write access to `/tmp` for document processing
- OCR operations create temporary files
- Media file processing requires writable directories

### Network Security

**Enable NetworkPolicy for traffic control:**
```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - podSelector: {}
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8000
  egress:
    # Allow DNS
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
    # Allow PostgreSQL
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 5432
    # Allow Redis
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 6379
    # Allow HTTP/HTTPS (for email, OCR packages)
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 443
```

**NetworkPolicy Benefits:**
- Restrict pod-to-pod communication
- Control egress to external services
- Compliance with security policies (PCI-DSS, SOC 2)

### Secrets Management

**Required Secrets:**
1. **Admin Password** - Initial admin account
2. **Secret Key** - Django secret key for encryption
3. **Database Credentials** - PostgreSQL password
4. **Redis Password** - Redis authentication (optional)
5. **Email Credentials** - SMTP password (if email enabled)

**Using External Secret Management:**
```yaml
# Example: Using Sealed Secrets
extraEnvFrom:
  - secretRef:
      name: paperless-sealed-secrets

# Example: Using Vault
extraEnv:
  - name: PAPERLESS_DBPASS
    valueFrom:
      secretKeyRef:
        name: vault-database-credentials
        key: password
```

### TLS/SSL Configuration

**Ingress TLS:**
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: paperless.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: paperless-tls
      hosts:
        - paperless.example.com
```

**PostgreSQL SSL:**
```yaml
postgresql:
  external:
    host: "postgres.example.com"
    sslMode: "require"  # disable, allow, prefer, require, verify-ca, verify-full
```

### Security Best Practices

1. **Strong Passwords**: Use 32+ character passwords for admin and database
2. **Secret Key**: Generate with `openssl rand -base64 32` and **never reuse**
3. **Database SSL**: Always use `sslMode: require` or higher in production
4. **Network Policies**: Enable NetworkPolicy in multi-tenant environments
5. **RBAC**: Never disable RBAC (`rbac.create: false`) in production
6. **Image Security**:
   - Use specific image tags (not `latest`)
   - Enable image pull secrets for private registries
   - Scan images for vulnerabilities (Trivy, Clair)
7. **Secrets Rotation**: Rotate admin password and secret key annually
8. **Audit Logging**: Enable Kubernetes audit logging for sensitive namespaces

### Compliance Considerations

**GDPR/Privacy:**
- Paperless-ngx stores documents with potentially sensitive PII
- Enable encryption at rest for PVCs
- Configure data retention policies
- Document data processing activities

**SOC 2/ISO 27001:**
- Enable RBAC and NetworkPolicy
- Use Secrets management (Vault/Sealed Secrets)
- Enable audit logging
- Regular security patching and updates

---

## Operations

Comprehensive operational tooling via Makefile for day-2 operations.

### Makefile Overview

The chart includes 60+ operational targets organized in 11 sections:

```bash
# Display all available commands
make -f make/ops/paperless-ngx.mk help
```

### Basic Operations

```bash
# View pod information
make -f make/ops/paperless-ngx.mk paperless-info
make -f make/ops/paperless-ngx.mk paperless-describe

# Stream logs (real-time)
make -f make/ops/paperless-ngx.mk paperless-logs
make -f make/ops/paperless-ngx.mk paperless-logs-follow

# Access shell
make -f make/ops/paperless-ngx.mk paperless-shell

# Port forward to localhost:8000
make -f make/ops/paperless-ngx.mk paperless-port-forward

# Restart deployment
make -f make/ops/paperless-ngx.mk paperless-restart

# Get pod events
make -f make/ops/paperless-ngx.mk paperless-events
```

### Database Operations

```bash
# Database connectivity check
make -f make/ops/paperless-ngx.mk paperless-check-db

# PostgreSQL shell (psql)
make -f make/ops/paperless-ngx.mk paperless-db-shell

# Run database migrations
make -f make/ops/paperless-ngx.mk paperless-migrate

# Database statistics
make -f make/ops/paperless-ngx.mk paperless-db-stats

# Document count
make -f make/ops/paperless-ngx.mk paperless-document-count

# Database size
make -f make/ops/paperless-ngx.mk paperless-db-size

# Vacuum database (performance)
make -f make/ops/paperless-ngx.mk paperless-db-vacuum
```

### Redis Operations

```bash
# Redis connectivity check
make -f make/ops/paperless-ngx.mk paperless-check-redis

# Redis CLI
make -f make/ops/paperless-ngx.mk paperless-redis-cli

# Redis info
make -f make/ops/paperless-ngx.mk paperless-redis-info

# Clear Redis cache
make -f make/ops/paperless-ngx.mk paperless-redis-flushdb

# Monitor Redis commands
make -f make/ops/paperless-ngx.mk paperless-redis-monitor
```

### Document Management

```bash
# List documents in consume directory
make -f make/ops/paperless-ngx.mk paperless-consume-list

# Document processing status
make -f make/ops/paperless-ngx.mk paperless-process-status

# Document exporter (export all documents)
make -f make/ops/paperless-ngx.mk paperless-document-exporter

# Rebuild search index
make -f make/ops/paperless-ngx.mk paperless-reindex

# Create document classifier
make -f make/ops/paperless-ngx.mk paperless-create-classifier

# OCR re-processing
make -f make/ops/paperless-ngx.mk paperless-ocr-redo
```

### User Management

```bash
# Create superuser (admin)
make -f make/ops/paperless-ngx.mk paperless-create-superuser

# List users
make -f make/ops/paperless-ngx.mk paperless-list-users

# Change user password
make -f make/ops/paperless-ngx.mk paperless-change-password

# Create API token
make -f make/ops/paperless-ngx.mk paperless-create-api-token
```

### Storage Operations

```bash
# Check storage usage
make -f make/ops/paperless-ngx.mk paperless-check-storage

# Consume directory size
make -f make/ops/paperless-ngx.mk paperless-consume-size

# Data directory size
make -f make/ops/paperless-ngx.mk paperless-data-size

# Media directory size
make -f make/ops/paperless-ngx.mk paperless-media-size

# Export directory size
make -f make/ops/paperless-ngx.mk paperless-export-size

# Total storage usage
make -f make/ops/paperless-ngx.mk paperless-total-storage

# PVC status
make -f make/ops/paperless-ngx.mk paperless-pvc-status
```

### Backup Operations

```bash
# Full backup (all components)
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Component backups
make -f make/ops/paperless-ngx.mk paperless-backup-documents
make -f make/ops/paperless-ngx.mk paperless-backup-database
make -f make/ops/paperless-ngx.mk paperless-backup-helm-values
make -f make/ops/paperless-ngx.mk paperless-backup-k8s-resources

# PVC snapshots
make -f make/ops/paperless-ngx.mk paperless-create-pvc-snapshots

# S3 backup
make -f make/ops/paperless-ngx.mk paperless-backup-documents-s3
```

### Restore Operations

```bash
# Restore documents
make -f make/ops/paperless-ngx.mk paperless-restore-documents BACKUP_DATE=20241208_100000

# Restore database
make -f make/ops/paperless-ngx.mk paperless-restore-database BACKUP_DATE=20241208_100000

# Restore Helm values
make -f make/ops/paperless-ngx.mk paperless-restore-helm-values BACKUP_DATE=20241208_100000

# Full disaster recovery
make -f make/ops/paperless-ngx.mk paperless-full-recovery BACKUP_DATE=20241208_100000
```

### Upgrade Operations

```bash
# Pre-upgrade check
make -f make/ops/paperless-ngx.mk paperless-pre-upgrade-check

# Check latest version
make -f make/ops/paperless-ngx.mk paperless-check-latest-version

# Rolling upgrade
make -f make/ops/paperless-ngx.mk paperless-upgrade-rolling VERSION=2.15.0

# Maintenance mode upgrade
make -f make/ops/paperless-ngx.mk paperless-upgrade-maintenance VERSION=3.0.0

# Blue-green deployment
make -f make/ops/paperless-ngx.mk paperless-upgrade-blue-green VERSION=3.0.0

# Post-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check

# Upgrade rollback
make -f make/ops/paperless-ngx.mk paperless-upgrade-rollback
```

### Monitoring & Troubleshooting

```bash
# Health checks
make -f make/ops/paperless-ngx.mk paperless-health-check

# Resource usage
make -f make/ops/paperless-ngx.mk paperless-top

# Network connectivity tests
make -f make/ops/paperless-ngx.mk paperless-test-connectivity

# OCR test
make -f make/ops/paperless-ngx.mk paperless-test-ocr

# Check application settings
make -f make/ops/paperless-ngx.mk paperless-check-settings

# Django system check
make -f make/ops/paperless-ngx.mk paperless-django-check
```

### Cleanup Operations

```bash
# Clean old documents from consume
make -f make/ops/paperless-ngx.mk paperless-cleanup-consume

# Clean export directory
make -f make/ops/paperless-ngx.mk paperless-cleanup-export

# Clean thumbnails (will be regenerated)
make -f make/ops/paperless-ngx.mk paperless-cleanup-thumbnails

# Database cleanup (remove orphaned records)
make -f make/ops/paperless-ngx.mk paperless-db-cleanup
```

### Common Operational Tasks

**Daily Operations:**
```bash
# Morning health check
make -f make/ops/paperless-ngx.mk paperless-health-check
make -f make/ops/paperless-ngx.mk paperless-check-storage

# Process new documents
make -f make/ops/paperless-ngx.mk paperless-consume-list
make -f make/ops/paperless-ngx.mk paperless-process-status
```

**Weekly Operations:**
```bash
# Database maintenance
make -f make/ops/paperless-ngx.mk paperless-db-vacuum
make -f make/ops/paperless-ngx.mk paperless-db-stats

# Storage cleanup
make -f make/ops/paperless-ngx.mk paperless-cleanup-export
make -f make/ops/paperless-ngx.mk paperless-total-storage
```

**Monthly Operations:**
```bash
# Full backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Test backup restore (in test namespace)
export NAMESPACE="paperless-test"
make -f make/ops/paperless-ngx.mk paperless-full-recovery BACKUP_DATE=<latest>

# Rebuild search index (if search performance degrades)
make -f make/ops/paperless-ngx.mk paperless-reindex
```

**Before Upgrades:**
```bash
# 1. Full backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# 2. Pre-upgrade check
make -f make/ops/paperless-ngx.mk paperless-pre-upgrade-check

# 3. Perform upgrade
make -f make/ops/paperless-ngx.mk paperless-upgrade-rolling VERSION=2.15.0

# 4. Post-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

### Makefile Environment Variables

```bash
# Override defaults
export RELEASE_NAME="my-paperless"
export NAMESPACE="documents"
export BACKUP_DIR="/mnt/backups/paperless"
export BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Run command with overrides
make -f make/ops/paperless-ngx.mk paperless-backup-documents
```

**For complete Makefile reference and advanced usage, see:**
- **[Makefile Commands Guide](../../docs/MAKEFILE_COMMANDS.md)** - All available commands

---

## Upgrading

Comprehensive upgrade procedures for all Paperless-ngx version changes.

### Upgrade Strategy Selection

| Version Change | Strategy | Downtime | Complexity |
|----------------|----------|----------|------------|
| **Patch** (2.14.0 → 2.14.1) | Rolling Upgrade | None | Low |
| **Minor** (2.14.x → 2.15.x) | Rolling Upgrade | None | Low |
| **Major** (2.x → 3.x) | Maintenance Mode | 10-30 min | Medium |
| **Breaking** (PostgreSQL 13 → 17) | Database Migration | 30-60 min | High |

### Pre-Upgrade Requirements

**⚠️ CRITICAL: Always backup before upgrading!**

```bash
# 1. Full backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# 2. Pre-upgrade validation
make -f make/ops/paperless-ngx.mk paperless-pre-upgrade-check

# 3. Review release notes
# Visit: https://github.com/paperless-ngx/paperless-ngx/releases
```

### Rolling Upgrade (Recommended)

**Use Case:** Patch and minor version upgrades with no breaking changes

**Advantages:**
- Zero downtime
- Automatic rollback on failure
- Simple procedure

**Procedure:**
```bash
# Step 1: Backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Update chart repository
helm repo update scripton-charts

# Step 3: Perform rolling upgrade
helm upgrade paperless-ngx scripton-charts/paperless-ngx \
  --set image.tag=2.15.0 \
  --reuse-values \
  --wait --timeout 10m

# Or use Makefile target:
make -f make/ops/paperless-ngx.mk paperless-upgrade-rolling VERSION=2.15.0

# Step 4: Verify upgrade
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

**Database migrations run automatically** on pod startup via Django migrations.

### Maintenance Mode Upgrade

**Use Case:** Major version upgrades with breaking changes or significant database schema changes

**Downtime:** 10-30 minutes (depends on migration time)

**Procedure:**
```bash
# Step 1: Backup
make -f make/ops/paperless-ngx.mk paperless-full-backup

# Step 2: Scale down to 0 (enter maintenance mode)
kubectl scale deployment paperless-ngx --replicas=0

# Step 3: Backup database one final time (while app is down)
make -f make/ops/paperless-ngx.mk paperless-backup-database

# Step 4: Perform upgrade
helm upgrade paperless-ngx scripton-charts/paperless-ngx \
  --set image.tag=3.0.0 \
  --reuse-values \
  --wait --timeout 15m

# Or use Makefile target:
make -f make/ops/paperless-ngx.mk paperless-upgrade-maintenance VERSION=3.0.0

# Step 5: Verify upgrade
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

### Blue-Green Deployment

**Use Case:** Zero-downtime upgrades for major versions with instant rollback capability

**Downtime:** None (instant cutover)

**Advantages:**
- Zero downtime
- Instant rollback (switch back to "blue")
- Full testing before cutover

**High-Level Procedure:**
1. Deploy "green" environment with new version
2. Copy data from "blue" to "green" PVCs
3. Test green environment thoroughly
4. Cutover traffic to green (update Ingress/Service)
5. Monitor and validate
6. Keep blue for 24-48 hours, then decommission

```bash
# Use Makefile target (handles all steps)
make -f make/ops/paperless-ngx.mk paperless-upgrade-blue-green VERSION=3.0.0
```

### Database Migration Upgrade

**Use Case:** PostgreSQL version upgrades (e.g., PostgreSQL 13 → 17)

**Downtime:** 30-60 minutes (depends on database size)

**High-Level Procedure:**
1. Full backup
2. Scale down Paperless-ngx
3. Deploy new PostgreSQL instance
4. Restore database to new instance
5. Update Paperless-ngx to use new database
6. Verify and test
7. Decommission old database after 7 days

```bash
# Use Makefile target (handles all steps)
make -f make/ops/paperless-ngx.mk paperless-upgrade-database-migration
```

### Post-Upgrade Validation

**Automated Validation:**
```bash
make -f make/ops/paperless-ngx.mk paperless-post-upgrade-check
```

**Manual Validation Checklist:**
- [ ] Pod running (1/1 Ready)
- [ ] Image version matches target
- [ ] No errors in logs
- [ ] Database connectivity OK
- [ ] Document count matches pre-upgrade
- [ ] Health endpoint returns 200 OK
- [ ] Search functionality working
- [ ] OCR processing functional
- [ ] Upload test document
- [ ] API access working

**Smoke Tests:**
```bash
make -f make/ops/paperless-ngx.mk paperless-smoke-test
```

### Rollback Procedures

**Rolling Upgrade Rollback:**
```bash
# Helm automatic rollback
helm rollback paperless-ngx

# Or use Makefile target:
make -f make/ops/paperless-ngx.mk paperless-upgrade-rollback
```

**Database Rollback (from backup):**
```bash
make -f make/ops/paperless-ngx.mk paperless-rollback-database BACKUP_DATE=20241208_100000
```

**Full System Rollback (from PVC snapshots):**
```bash
make -f make/ops/paperless-ngx.mk paperless-rollback-full BACKUP_DATE=20241208_100000
```

### Version-Specific Notes

**Upgrading to Paperless-ngx 2.15.x:**
- No breaking changes
- Standard rolling upgrade applies
- Database migrations are minimal

**Upgrading to Paperless-ngx 3.0.x (Future):**
- PostgreSQL 16+ required
- Redis 7+ required
- New document storage format (automatic migration)
- Allow 30-60 minutes for migration on large document sets

**PostgreSQL 13 → 17 Upgrade:**
- Use Database Migration strategy
- Cannot use in-place upgrade (requires new instance)
- Test restore before production cutover

### Upgrade Best Practices

1. **Always Backup**: Full backup before every upgrade (documents, database, config, snapshots)
2. **Read Release Notes**: Review breaking changes and migration notes
3. **Test in Non-Production**: Upgrade dev/staging environment first
4. **Choose Right Strategy**: Match strategy to version change magnitude
5. **Monitor Migrations**: Watch logs during database migrations
6. **Validate Thoroughly**: Run post-upgrade checks before declaring success
7. **Keep Backups**: Retain pre-upgrade backups for 7 days minimum
8. **Plan Downtime**: Communicate maintenance windows for major upgrades

### Upgrade Troubleshooting

**Issue: Upgrade stuck on "Waiting for rollout"**
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=paperless-ngx

# Check pod events
kubectl describe pod -l app.kubernetes.io/name=paperless-ngx

# Check logs
make -f make/ops/paperless-ngx.mk paperless-logs

# Common causes:
# - Database migration taking long (expected, wait longer)
# - Database connectivity issues (verify credentials)
# - Insufficient resources (check node resources)
# - ImagePullBackOff (verify image tag exists)
```

**Issue: Database migration fails**
```bash
# Manually run migrations
kubectl exec deployment/paperless-ngx -- python manage.py migrate --noinput

# If fails, restore from backup
make -f make/ops/paperless-ngx.mk paperless-rollback-database BACKUP_DATE=$BACKUP_TIMESTAMP
```

**Issue: Document count mismatch after upgrade**
```bash
# Rebuild search index
make -f make/ops/paperless-ngx.mk paperless-reindex

# Verify database integrity
make -f make/ops/paperless-ngx.mk paperless-document-count

# If media files missing, restore from backup
make -f make/ops/paperless-ngx.mk paperless-restore-documents BACKUP_DATE=$BACKUP_TIMESTAMP
```

**For detailed upgrade procedures, strategies, and troubleshooting, see:**
- **[Paperless-ngx Upgrade Guide](../../docs/paperless-ngx-upgrade-guide.md)** - Comprehensive upgrade procedures

---

## Additional Resources

- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Production Checklist](../../docs/PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Testing Guide](../../docs/TESTING_GUIDE.md) - Comprehensive testing procedures
- [Chart Analysis Report](../../docs/05-chart-analysis-2025-11.md) - November 2025 analysis

## License

Paperless-ngx is licensed under the [GPL-3.0 License](https://github.com/paperless-ngx/paperless-ngx/blob/main/LICENSE).

This Helm chart is licensed under BSD-3-Clause.

## Resources

- Documentation: https://docs.paperless-ngx.com/
- GitHub: https://github.com/paperless-ngx/paperless-ngx
- Docker Hub: https://hub.docker.com/r/paperlessngx/paperless-ngx
