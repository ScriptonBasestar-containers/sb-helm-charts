# Paperless-ngx Helm Chart

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

## License

Paperless-ngx is licensed under the [GPL-3.0 License](https://github.com/paperless-ngx/paperless-ngx/blob/main/LICENSE).

This Helm chart is licensed under BSD-3-Clause.

## Resources

- Documentation: https://docs.paperless-ngx.com/
- GitHub: https://github.com/paperless-ngx/paperless-ngx
- Docker Hub: https://hub.docker.com/r/paperlessngx/paperless-ngx
