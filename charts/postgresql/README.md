# PostgreSQL Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)
![AppVersion: 16.1](https://img.shields.io/badge/AppVersion-16.1-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

PostgreSQL relational database with replication support for Kubernetes.

## Features

- ✅ **PostgreSQL 16.1** - Latest stable version
- ✅ **Primary-Replica Replication** - Built-in streaming replication support
- ✅ **Production-Ready** - StatefulSet with persistent storage
- ✅ **Configuration Management** - Full postgresql.conf and pg_hba.conf support
- ✅ **Security** - Non-root containers, secret management, configurable authentication
- ✅ **High Availability** - Multi-replica support with automatic failover preparation
- ✅ **Operational Tools** - 40+ Makefile commands for database operations
- ✅ **Backup & Restore** - Built-in backup and restore capabilities
- ✅ **Monitoring Ready** - Health probes, metrics endpoints, activity monitoring
- ✅ **Customizable** - Initialization scripts, extensions, custom configuration

## Table of Contents

- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
  - [Development Installation](#development-installation)
  - [Production Installation](#production-installation)
- [Configuration](#configuration)
  - [PostgreSQL Settings](#postgresql-settings)
  - [Replication Setup](#replication-setup)
  - [Initialization Scripts](#initialization-scripts)
  - [Security Configuration](#security-configuration)
- [Replication](#replication)
  - [Primary-Replica Architecture](#primary-replica-architecture)
  - [Enabling Replication](#enabling-replication)
  - [Monitoring Replication](#monitoring-replication)
- [Operations](#operations)
  - [Database Management](#database-management)
  - [Backup and Restore](#backup-and-restore)
  - [Maintenance](#maintenance)
  - [Monitoring](#monitoring)
- [Values Profiles](#values-profiles)
- [Troubleshooting](#troubleshooting)
- [Production Recommendations](#production-recommendations)
- [Additional Resources](#additional-resources)

## Installation

### Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PersistentVolume support
- (Optional) StorageClass for dynamic provisioning

### Quick Start

```bash
# Add the Helm repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default values (development)
helm install my-postgres scripton-charts/postgresql

# Get the password
export POSTGRES_PASSWORD=$(kubectl get secret my-postgres-secret -o jsonpath="{.data.postgres-password}" | base64 -d)
echo "Password: $POSTGRES_PASSWORD"

# Connect to PostgreSQL
kubectl port-forward svc/my-postgres 5432:5432
PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U postgres -d postgres
```

### Development Installation

For local development and testing:

```bash
helm install my-postgres scripton-charts/postgresql \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/postgresql/values-dev.yaml
```

Features:
- Single node (replicaCount: 1)
- Reduced resources (512Mi RAM, 500m CPU limit)
- Smaller storage (5Gi)
- Development-friendly logging (log all statements)
- Simple password authentication

### Production Installation

For production environments with HA:

```bash
# Create namespace
kubectl create namespace production

# Install with production profile
helm install my-postgres scripton-charts/postgresql \
  -n production \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/postgresql/values-small-prod.yaml \
  --set postgresql.password='<STRONG_PASSWORD>' \
  --set postgresql.replication.password='<REPLICATION_PASSWORD>' \
  --set persistence.storageClass='fast-ssd'
```

Features:
- Primary + replica (replicaCount: 2)
- Production resources (4Gi RAM, 2 CPU limit)
- Larger storage (50Gi SSD)
- Streaming replication enabled
- Optimized configuration for SSD
- Anti-affinity rules

## Configuration

### PostgreSQL Settings

Key configuration parameters in `values.yaml`:

```yaml
postgresql:
  database: "postgres"
  username: "postgres"
  password: ""  # Auto-generated if empty

  # Connection Settings
  maxConnections: 100

  # Memory Settings
  sharedBuffers: "128MB"
  effectiveCacheSize: "4GB"
  workMem: "4MB"
  maintenanceWorkMem: "64MB"

  # WAL Settings
  walLevel: "replica"
  maxWalSenders: 10
  maxReplicationSlots: 10

  # Additional postgresql.conf parameters
  config:
    max_parallel_workers: "4"
    checkpoint_timeout: "15min"
```

### Replication Setup

Enable streaming replication for high availability:

```yaml
replicaCount: 2  # or more

postgresql:
  replication:
    enabled: true
    user: "replicator"
    password: ""  # Auto-generated if empty
```

Architecture:
- Pod 0: Primary (master)
- Pod 1+: Replicas (slaves)
- Automatic role assignment based on pod index
- WAL-based streaming replication

### Initialization Scripts

Run SQL scripts on database initialization:

```yaml
postgresql:
  initdbScripts:
    01-create-database.sql: |
      CREATE DATABASE myapp;
      CREATE USER myapp WITH PASSWORD 'myapp_password';
      GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp;

    02-create-extensions.sql: |
      \c myapp
      CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
      CREATE EXTENSION IF NOT EXISTS pgcrypto;
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

Scripts are executed in alphabetical order during first startup only.

### Security Configuration

#### Password Management

**Development:**
```bash
# Use simple password
helm install my-postgres scripton-charts/postgresql \
  --set postgresql.password='devpass123'
```

**Production:**
```bash
# Use strong password from environment variable
helm install my-postgres scripton-charts/postgresql \
  --set postgresql.password="${POSTGRES_PASSWORD}" \
  --set postgresql.replication.password="${REPLICATION_PASSWORD}"
```

**External Secret (Best Practice):**
```yaml
postgresql:
  existingSecret: "my-postgres-secret"
```

Create secret manually:
```bash
kubectl create secret generic my-postgres-secret \
  --from-literal=postgres-password='<strong-password>' \
  --from-literal=replication-password='<replication-password>'
```

#### Authentication Methods

The chart uses `md5` authentication by default. Customize via `pg_hba.conf`:

```yaml
postgresql:
  config:
    # Custom pg_hba.conf rules (extends default)
```

Or use existing ConfigMap:
```yaml
postgresql:
  existingConfigMap: "my-postgres-config"
```

## Replication

### Primary-Replica Architecture

```
┌─────────────────┐       ┌─────────────────┐
│   Pod 0         │       │   Pod 1         │
│   (Primary)     │──────>│   (Replica)     │
│   Read/Write    │  WAL  │   Read-only     │
└─────────────────┘       └─────────────────┘
        │                          │
        └──────────┬───────────────┘
                   │
            ┌──────▼──────┐
            │   Headless  │
            │   Service   │
            └─────────────┘
```

### Enabling Replication

1. **Set replica count:**
```yaml
replicaCount: 2  # or more
```

2. **Enable replication:**
```yaml
postgresql:
  replication:
    enabled: true
    user: "replicator"
    password: "strong-replication-password"
```

3. **Install/Upgrade:**
```bash
helm upgrade --install my-postgres scripton-charts/postgresql \
  --set replicaCount=2 \
  --set postgresql.replication.enabled=true \
  --set postgresql.replication.password='<password>'
```

### Monitoring Replication

**Check replication status:**
```bash
make -f make/ops/postgresql.mk pg-replication-status
```

Output:
```
  pid  | usename    | application_name | client_addr | state      | sync_state
-------+------------+------------------+-------------+------------+------------
 12345 | replicator | walreceiver      | 10.0.1.23   | streaming  | async
```

**Check replication lag:**
```bash
make -f make/ops/postgresql.mk pg-replication-lag
```

**Manual check on master:**
```sql
SELECT * FROM pg_stat_replication;
```

**Manual check on replica:**
```sql
SELECT pg_is_in_recovery();  -- Should return 't' (true)
```

## Operations

The chart includes 40+ operational commands via Makefile. See `make/ops/postgresql.mk`.

### Database Management

```bash
# Open psql shell
make -f make/ops/postgresql.mk pg-shell

# List databases
make -f make/ops/postgresql.mk pg-list-databases

# List tables
make -f make/ops/postgresql.mk pg-list-tables

# List users
make -f make/ops/postgresql.mk pg-list-users

# Get database size
make -f make/ops/postgresql.mk pg-database-size

# Get all databases size
make -f make/ops/postgresql.mk pg-all-databases-size
```

### Backup and Restore

**Backup single database:**
```bash
make -f make/ops/postgresql.mk pg-backup
# Saves to: tmp/postgresql-backups/<database>-<timestamp>.sql
```

**Backup all databases:**
```bash
make -f make/ops/postgresql.mk pg-backup-all
# Saves to: tmp/postgresql-backups/all-databases-<timestamp>.sql
```

**Restore from backup:**
```bash
make -f make/ops/postgresql.mk pg-restore FILE=tmp/postgresql-backups/backup.sql
```

**Manual backup (custom database):**
```bash
kubectl exec postgresql-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres myapp' > myapp-backup.sql
```

**Manual restore:**
```bash
cat myapp-backup.sql | kubectl exec -i postgresql-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres myapp'
```

### Maintenance

**VACUUM:**
```bash
# Regular VACUUM
make -f make/ops/postgresql.mk pg-vacuum

# VACUUM with ANALYZE (updates statistics)
make -f make/ops/postgresql.mk pg-vacuum-analyze

# VACUUM FULL (reclaims space, locks tables)
make -f make/ops/postgresql.mk pg-vacuum-full
```

**ANALYZE:**
```bash
make -f make/ops/postgresql.mk pg-analyze
```

**REINDEX:**
```bash
make -f make/ops/postgresql.mk pg-reindex TABLE=users
```

### Monitoring

**Database statistics:**
```bash
make -f make/ops/postgresql.mk pg-stats
```

**Active connections:**
```bash
make -f make/ops/postgresql.mk pg-activity
```

**Connection count:**
```bash
make -f make/ops/postgresql.mk pg-connections
```

**Current locks:**
```bash
make -f make/ops/postgresql.mk pg-locks
```

**Slow queries (requires pg_stat_statements):**
```bash
make -f make/ops/postgresql.mk pg-slow-queries
```

**Configuration:**
```bash
# Show all configuration
make -f make/ops/postgresql.mk pg-config

# Get specific parameter
make -f make/ops/postgresql.mk pg-config-get PARAM=max_connections

# Reload configuration (without restart)
make -f make/ops/postgresql.mk pg-reload
```

## Values Profiles

### values-dev.yaml

Development environment profile:
- Single node (replicaCount: 1)
- Reduced resources (512Mi RAM, 500m CPU)
- Smaller storage (5Gi)
- Debug logging enabled
- Simple passwords acceptable

### values-small-prod.yaml

Small production environment profile:
- HA setup (replicaCount: 2)
- Production resources (4Gi RAM, 2 CPU)
- SSD storage (50Gi)
- Replication enabled
- Optimized for SSD
- Anti-affinity rules
- Production logging

## Troubleshooting

### Common Issues

**1. Pod not starting - password not set**

Error:
```
Error: password authentication failed
```

Solution:
```bash
helm upgrade my-postgres scripton-charts/postgresql \
  --set postgresql.password='strong-password' \
  --reuse-values
```

**2. Replication not working**

Check:
```bash
# On master
make -f make/ops/postgresql.mk pg-replication-status

# On replica
kubectl exec postgresql-1 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "SELECT pg_is_in_recovery();"'
```

Common causes:
- Replication password not set
- `replicaCount` < 2
- Firewall blocking port 5432

**3. Out of disk space**

Check disk usage:
```bash
kubectl exec postgresql-0 -- df -h /var/lib/postgresql/data
```

Solutions:
- Run `VACUUM FULL` to reclaim space
- Increase PVC size:
```bash
kubectl edit pvc data-postgresql-0
# Edit spec.resources.requests.storage
```

**4. High connection count**

Check connections:
```bash
make -f make/ops/postgresql.mk pg-connections
```

Solutions:
- Increase `max_connections`
- Use connection pooling (PgBouncer)
- Investigate connection leaks

### Debugging

**View logs:**
```bash
make -f make/ops/postgresql.mk pg-logs

# All pods
make -f make/ops/postgresql.mk pg-logs-all
```

**Open shell:**
```bash
make -f make/ops/postgresql.mk pg-bash
```

**Test connection:**
```bash
make -f make/ops/postgresql.mk pg-ping
```

**Get password:**
```bash
make -f make/ops/postgresql.mk pg-get-password
```

## Production Recommendations

### 1. Use Operators for Large Deployments

For production HA with automatic failover, consider PostgreSQL operators:
- [CloudNativePG](https://cloudnative-pg.io/) - Recommended, CNCF project
- [Zalando PostgreSQL Operator](https://github.com/zalando/postgres-operator)
- [Crunchy Data PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator)

This chart is designed for:
- Development environments
- Small production deployments (1-3 replicas)
- Deployments where manual failover is acceptable

### 2. Storage Configuration

**Use SSD storage:**
```yaml
persistence:
  storageClass: "fast-ssd"
  size: 100Gi
```

**Set appropriate reclaim policy:**
```yaml
persistence:
  annotations:
    "helm.sh/resource-policy": "keep"
```

### 3. Resource Planning

**Memory guidelines:**
- `shared_buffers`: 25% of available RAM
- `effective_cache_size`: 75% of available RAM
- `work_mem`: `shared_buffers / max_connections`
- `maintenance_work_mem`: 5-10% of available RAM (max 2GB)

**Example for 8GB RAM node:**
```yaml
postgresql:
  sharedBuffers: "2GB"
  effectiveCacheSize: "6GB"
  workMem: "20MB"  # 2GB / 100 connections
  maintenanceWorkMem: "512MB"
```

### 4. Monitoring

**Enable pg_stat_statements:**
```yaml
postgresql:
  initdbScripts:
    00-extensions.sql: |
      CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

  config:
    shared_preload_libraries: "pg_stat_statements"
    pg_stat_statements.track: "all"
```

**Use postgres_exporter for Prometheus:**
- Deploy as sidecar container
- Scrape metrics on port 9187
- Monitor replication lag, connections, queries

### 5. Backup Strategy

**Automated backups with CronJob:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:16.1
            command:
            - sh
            - -c
            - |
              PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h postgresql -U postgres postgres > /backup/postgres-$(date +%Y%m%d).sql
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            persistentVolumeClaim:
              claimName: postgres-backup-pvc
```

**External backup solutions:**
- Velero for cluster-level backups
- pg_basebackup for physical backups
- WAL archiving to S3/MinIO

### 6. Security Hardening

**Network policies:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: postgresql
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: myapp  # Only allow from your application
    ports:
    - protocol: TCP
      port: 5432
```

**Use strong passwords:**
- Minimum 16 characters
- Mix of uppercase, lowercase, numbers, symbols
- Store in external secret manager (Vault, AWS Secrets Manager)

**SSL/TLS connections:**
```yaml
postgresql:
  config:
    ssl: "on"
    ssl_cert_file: "/etc/ssl/certs/server.crt"
    ssl_key_file: "/etc/ssl/private/server.key"
```

## Additional Resources

### Official Documentation
- [PostgreSQL Documentation](https://www.postgresql.org/docs/16/)
- [PostgreSQL Replication](https://www.postgresql.org/docs/16/high-availability.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

### Tools
- [pgAdmin](https://www.pgadmin.org/) - Web-based administration
- [PgBouncer](https://www.pgbouncer.org/) - Connection pooler
- [postgres_exporter](https://github.com/prometheus-community/postgres_exporter) - Prometheus exporter

### Community
- [PostgreSQL Slack](https://postgres-slack.herokuapp.com/)
- [PostgreSQL Mailing Lists](https://www.postgresql.org/list/)
- [r/PostgreSQL](https://www.reddit.com/r/PostgreSQL/)

## License

This Helm chart is licensed under the BSD-3-Clause License. See the [LICENSE](../../LICENSE) file for details.

PostgreSQL is licensed under the [PostgreSQL License](https://www.postgresql.org/about/licence/), a liberal Open Source license similar to the BSD or MIT licenses.

## Maintainers

- [ScriptonBasestar](https://github.com/scriptonbasestar-container)

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.

---

**Chart Version:** 0.1.0
**PostgreSQL Version:** 16.1
**Last Updated:** 2025-11
