# Nextcloud Production Deployment - Example

Enterprise-ready Nextcloud deployment with PostgreSQL, Redis, and high availability.

## Stack Components

### Application

- **Nextcloud** - Self-hosted file sync and share platform (LinuxServer.io image)
- **PostgreSQL** - Primary database for metadata
- **Redis** - Caching and file locking

### Features

- High availability with 2 replicas
- Redis for distributed caching and file locking
- PostgreSQL for reliable data storage
- Persistent storage for user data and configuration
- Ingress with TLS for secure access
- Prometheus metrics via ServiceMonitor
- Resource limits and security hardening

## Architecture

```
┌──────────────────────────────────────────────────┐
│              Ingress (HTTPS)                      │
│          nextcloud.example.com                    │
└─────────────────┬────────────────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │  Nextcloud (x2) │  ← Load Balanced
         │   (Deployment)  │
         └────┬──────┬─────┘
              │      │
         ┌────┘      └────┐
         ▼                ▼
    ┌──────────┐    ┌───────────┐
    │PostgreSQL│    │   Redis   │
    │(External)│    │(External) │
    └──────────┘    └───────────┘
         │
         ▼
    ┌──────────────┐
    │  PVC (Data)  │
    │PVC (Config)  │
    └──────────────┘
```

## Prerequisites

### 1. Kubernetes Cluster

- Kubernetes 1.21+
- Ingress controller (nginx recommended)
- cert-manager for TLS certificates

### 2. External Services

#### PostgreSQL 16+

```bash
# Create database and user
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
```

#### Redis 8+

```bash
# No special configuration needed
# Just ensure Redis is accessible
```

### 3. Storage

- StorageClass with ReadWriteOnce support
- Recommended: 100GB+ for user data
- Recommended: 5GB for configuration

### 4. Helm Repository

```bash
helm repo add scripton-charts <https://scriptonbasestar-container.github.io/sb-helm-charts>
helm repo update
```

## Installation

### Step 1: Create Namespace

```bash
kubectl create namespace nextcloud
```

### Step 2: Create Secrets

```bash
# PostgreSQL password
kubectl create secret generic nextcloud-db-secret \
  --from-literal=password='your-postgresql-password' \
  -n nextcloud

# Redis password (if Redis requires auth)
kubectl create secret generic nextcloud-redis-secret \
  --from-literal=password='your-redis-password' \
  -n nextcloud

# Nextcloud admin password
kubectl create secret generic nextcloud-admin-secret \
  --from-literal=password='your-admin-password' \
  -n nextcloud
```

### Step 3: Customize Values

Edit `values-nextcloud.yaml`:

1. Update `nextcloud.host` to your domain
2. Set `postgresql.external.host` to your PostgreSQL service
3. Set `redis.external.host` to your Redis service
4. Update ingress `hosts` and `tls` sections
5. Adjust storage sizes if needed

### Step 4: Install Nextcloud

```bash
helm install nextcloud scripton-charts/nextcloud \
  -f values-nextcloud.yaml \
  -n nextcloud
```

### Step 5: Verify Installation

```bash
# Check pods are running
kubectl get pods -n nextcloud

# Expected output:
# nextcloud-0    1/1     Running
# nextcloud-1    1/1     Running

# Check ingress
kubectl get ingress -n nextcloud
```

## Access

### Web Interface

```bash
# Get ingress URL
kubectl get ingress nextcloud -n nextcloud

# Access via browser
# URL: https://nextcloud.example.com
# Username: admin
# Password: (from nextcloud-admin-secret)
```

### Get Admin Password

```bash
kubectl get secret nextcloud-admin-secret -n nextcloud \
  -o jsonpath="{.data.password}" | base64 --decode
```

### CLI Access

```bash
# Open shell in Nextcloud pod
kubectl exec -it nextcloud-0 -n nextcloud -- bash

# Run occ commands
sudo -u abc php /config/www/nextcloud/occ status
sudo -u abc php /config/www/nextcloud/occ user:list
sudo -u abc php /config/www/nextcloud/occ app:list
```

## Configuration

### Initial Setup

After first login, complete the setup:

1. **Admin Account**: Already configured via environment variables
2. **Database**: Already configured (PostgreSQL)
3. **Data Directory**: `/data` (pre-configured)

### Recommended Apps

Enable these apps for enhanced functionality:

```bash
# Files
sudo -u abc php /config/www/nextcloud/occ app:enable files_external
sudo -u abc php /config/www/nextcloud/occ app:enable files_versions
sudo -u abc php /config/www/nextcloud/occ app:enable files_trashbin

# Collaboration
sudo -u abc php /config/www/nextcloud/occ app:enable contacts
sudo -u abc php /config/www/nextcloud/occ app:enable calendar
sudo -u abc php /config/www/nextcloud/occ app:enable deck

# Security
sudo -u abc php /config/www/nextcloud/occ app:enable twofactor_totp
sudo -u abc php /config/www/nextcloud/occ app:enable bruteforcesettings
```

### Performance Tuning

```bash
# Enable Redis for file locking
# Already configured in values.yaml

# Set memory cache
# Already configured via REDIS_HOST

# Background jobs (cron)
sudo -u abc php /config/www/nextcloud/occ background:cron
```

## Maintenance

### Backup

```bash
# Backup user data
kubectl exec nextcloud-0 -n nextcloud -- tar czf /tmp/data-backup.tar.gz /data
kubectl cp nextcloud/nextcloud-0:/tmp/data-backup.tar.gz ./data-backup.tar.gz

# Backup PostgreSQL
kubectl exec postgresql-0 -n database -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql
```

### Updates

```bash
# Update Nextcloud
helm upgrade nextcloud scripton-charts/nextcloud \
  -f values-nextcloud.yaml \
  -n nextcloud

# Run database migrations
kubectl exec nextcloud-0 -n nextcloud -- \
  sudo -u abc php /config/www/nextcloud/occ upgrade
```

### Scaling

```bash
# Scale replicas
kubectl scale deployment nextcloud -n nextcloud --replicas=3

# Or update values.yaml and upgrade
helm upgrade nextcloud scripton-charts/nextcloud \
  -f values-nextcloud.yaml \
  -n nextcloud
```

## Resource Requirements

### Minimum (Development)

- 2 CPU cores
- 4 GB RAM
- 20 GB storage

### Recommended (Production)

- 4 CPU cores
- 8 GB RAM
- 100+ GB storage

### Per Component

| Component | CPU (req/limit) | Memory (req/limit) | Storage |
|-----------|-----------------|-------------------|---------|
| Nextcloud | 500m/2000m | 512Mi/2Gi | 100Gi (data) + 5Gi (config) |
| PostgreSQL | 500m/2000m | 512Mi/2Gi | 20Gi |
| Redis | 200m/1000m | 256Mi/1Gi | - |

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl describe pod nextcloud-0 -n nextcloud

# Check logs
kubectl logs nextcloud-0 -n nextcloud

# Common issues:
# 1. Database connection failed - check PostgreSQL credentials
# 2. Redis connection failed - check Redis host/password
# 3. PVC not binding - check StorageClass
```

### Database connection errors

```bash
# Test PostgreSQL connection
kubectl exec nextcloud-0 -n nextcloud -- \
  psql -h postgresql.database.svc.cluster.local -U nextcloud -d nextcloud -c "SELECT 1"

# Check database credentials
kubectl get secret nextcloud-db-secret -n nextcloud -o yaml
```

### Redis connection errors

```bash
# Test Redis connection
kubectl exec nextcloud-0 -n nextcloud -- \
  redis-cli -h redis.cache.svc.cluster.local ping

# Check Redis password
kubectl get secret nextcloud-redis-secret -n nextcloud -o yaml
```

### File upload issues

```bash
# Check PHP upload limits
kubectl exec nextcloud-0 -n nextcloud -- \
  grep -i upload /config/php/www.conf

# Increase via values.yaml:
# nextcloud:
#   php:
#     uploadMaxFilesize: 10G
#     postMaxSize: 10G
```

### Performance issues

```bash
# Check resource usage
kubectl top pod nextcloud-0 -n nextcloud

# Check database performance
kubectl exec postgresql-0 -n database -- \
  psql -U nextcloud -d nextcloud -c "SELECT * FROM pg_stat_activity"

# Check Redis memory
kubectl exec redis-0 -n cache -- redis-cli INFO memory
```

## Uninstallation

```bash
# Remove Nextcloud
helm uninstall nextcloud -n nextcloud

# (Optional) Delete PVCs
kubectl delete pvc -n nextcloud -l app.kubernetes.io/name=nextcloud

# (Optional) Delete namespace
kubectl delete namespace nextcloud
```

## Next Steps

1. **Enable HTTPS**: Configure ingress with TLS certificate
2. **Add Users**: Create user accounts via admin panel
3. **Install Apps**: Enable collaboration apps (Calendar, Contacts, Talk)
4. **Setup Backup**: Configure automated backups
5. **Enable 2FA**: Require two-factor authentication
6. **Configure Email**: Setup SMTP for notifications
7. **External Storage**: Mount external storage (S3, NFS, etc.)

## References

- [Nextcloud Documentation](<https://docs.nextcloud.com/>)
- [Nextcloud Admin Manual](<https://docs.nextcloud.com/server/latest/admin_manual/>)
- [LinuxServer.io Nextcloud Image](<https://docs.linuxserver.io/images/docker-nextcloud/>)
