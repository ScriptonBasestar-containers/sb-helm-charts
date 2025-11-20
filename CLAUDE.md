# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScriptonBasestar Helm Charts - Personal server Helm charts focused on simplicity and configuration file preservation.

**Core Philosophy:**
- Prefer configuration files over environment variables
- Avoid subchart complexity - external databases (PostgreSQL, MySQL, Redis) are separate
- Use simple Docker images where available; create custom images when needed
- Configuration files should be used as-is, not translated through complex Helm abstractions

**Development Guides:**
- [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md) - Comprehensive chart development patterns and standards
- [Chart Version Policy](docs/CHART_VERSION_POLICY.md) - Semantic versioning and release process
- [Chart README Template](docs/CHART_README_TEMPLATE.md) - Standard README template for all charts
- [Chart README Guide](docs/CHART_README_GUIDE.md) - How to use the README template effectively
- [Workflow Update Instructions](docs/WORKFLOW_UPDATE_INSTRUCTIONS.md) - Manual CI workflow update guide
- All new charts MUST follow the standard structure and patterns defined in the guides
- Existing charts should be updated to align with these patterns over time

**Operational Guides:**
- [Testing Guide](docs/TESTING_GUIDE.md) - Comprehensive testing procedures for all deployment scenarios
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions for production deployments
- [Production Checklist](docs/PRODUCTION_CHECKLIST.md) - Production readiness validation and deployment checklist
- [Chart Analysis Report](docs/05-chart-analysis-2025-11.md) - November 2025 comprehensive analysis of all 16 charts

## Chart Structure

Each chart follows a consistent structure:
```
charts/{chart-name}/
├── Chart.yaml
├── values.yaml
├── values-example.yaml (production-ready examples)
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml (configuration files)
    ├── secret.yaml
    ├── pvc.yaml
    ├── serviceaccount.yaml
    ├── hpa.yaml (optional)
    ├── cronjob.yaml (optional)
    └── tests/
```

## Chart Metadata

**IMPORTANT**: All chart metadata is centrally managed in `charts-metadata.yaml` at the repository root.

### When Adding or Modifying Charts

When you add a new chart or modify an existing one, you MUST update:

1. **`charts-metadata.yaml`**: Add/update chart entry with:
   - `name`: Human-readable chart name
   - `path`: Chart directory path (e.g., `charts/chart-name`)
   - `category`: Either `application` or `infrastructure`
   - `tags`: List of categorization tags (e.g., `[Monitoring, Alerting]`)
   - `keywords`: List of searchable keywords for Chart.yaml
   - `description`: Brief description matching CLAUDE.md
   - `production_note`: (Optional) Production warnings for infrastructure charts

2. **Sync keywords to Chart.yaml**:
   ```bash
   # Preview changes
   make sync-keywords-dry-run

   # Apply changes
   make sync-keywords
   # or for specific chart
   python3 scripts/sync-chart-keywords.py --chart chart-name
   ```

3. **Validate consistency**:
   ```bash
   make validate-metadata
   ```

4. **Regenerate catalog**:
   ```bash
   make generate-catalog
   ```

5. **Update this file (CLAUDE.md)**: Update the "Available Charts" section if needed

### Metadata Tools

**Validation:**
- `make validate-metadata` - Validates keywords consistency between Chart.yaml and charts-metadata.yaml
- Pre-commit hook automatically runs validation before commits
- CI workflow validates on PR/push (see docs/WORKFLOW_UPDATE_INSTRUCTIONS.md)

**Synchronization:**
- `make sync-keywords` - Syncs Chart.yaml keywords from charts-metadata.yaml
- `make sync-keywords-dry-run` - Preview changes without applying
- `python3 scripts/sync-chart-keywords.py --chart <name>` - Sync specific chart

**Catalog Generation:**
- `make generate-catalog` - Generates docs/CHARTS.md from charts-metadata.yaml
- Auto-generates comprehensive chart catalog with badges, descriptions, installation examples
- Organizes by category, tags, and keywords for easy discovery
- Run after updating charts-metadata.yaml

**Artifact Hub Dashboard:**
- `make generate-artifacthub-dashboard` - Generates docs/ARTIFACTHUB_DASHBOARD.md from charts-metadata.yaml
- Creates Artifact Hub statistics dashboard with repository and package badges
- Includes publishing guide and badge usage examples
- Shows quick statistics (total charts, categories breakdown)
- Provides ready-to-use badge markdown for chart READMEs

**Dependencies:**
- Python 3.x required
- Install dependencies: `pip install -r scripts/requirements.txt`

### Metadata Usage

The metadata file serves multiple purposes:
- **Documentation**: Single source of truth for chart categorization
- **Search**: Keywords used in Chart.yaml for Helm Hub/Artifact Hub
- **Automation**: Chart discovery and documentation generation
- **Consistency**: Ensures tags and keywords are consistent across all charts
- **Validation**: Pre-commit hooks and CI ensure metadata stays synchronized

## Available Charts

### Application Charts (Self-Hosted)

- **airflow**: Apache Airflow workflow orchestration (KubernetesExecutor, PostgreSQL, Git-sync, remote logging)
- **browserless-chrome**: Headless browser for crawling
- **devpi**: Python package index
- **immich**: AI-powered photo and video management
- **jellyfin**: Media server with hardware transcoding support
- **keycloak**: IAM solution (StatefulSet, PostgreSQL, clustering, realm management)
- **nextcloud**: Nextcloud with LinuxServer.io image (Deployment, PostgreSQL, config-based)
- **paperless-ngx**: Document management system with OCR (4 PVC architecture)
- **rsshub**: RSS aggregator (well-maintained external chart available)
- **rustfs**: High-performance S3-compatible object storage (StatefulSet, tiered storage, clustering)
- **uptime-kuma**: Self-hosted monitoring tool with beautiful UI and 90+ notification services
- **vaultwarden**: Bitwarden-compatible password manager
- **wireguard**: VPN solution (Deployment, no database, UDP service, NET_ADMIN capabilities)
- **wordpress**: WordPress CMS (Deployment, MySQL, Apache)

### Infrastructure Charts (Dev/Test - Consider Operators for Production)

- **elasticsearch**: Distributed search and analytics engine (StatefulSet, Kibana, cluster mode, S3 snapshots)
  - ⚠️ For large-scale production, consider [Elastic Cloud on Kubernetes (ECK) Operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- **kafka**: Apache Kafka streaming platform with KRaft mode and management UI (StatefulSet, no Zookeeper)
  - ⚠️ For production clustering, consider [Strimzi Kafka Operator](https://strimzi.io/)
- **memcached**: High-performance distributed memory caching system (Deployment, no database)
  - ⚠️ For production, consider [Memcached Operator](https://github.com/ianlewis/memcached-operator)
- **minio**: High-performance S3-compatible object storage (StatefulSet, distributed mode, erasure coding)
  - ⚠️ For production HA, consider [MinIO Operator](https://github.com/minio/operator) for advanced features
- **postgresql**: PostgreSQL relational database with replication support (StatefulSet, primary-replica mode)
  - ⚠️ For production HA, consider PostgreSQL Operator ([Zalando](https://github.com/zalando/postgres-operator), [Crunchy Data](https://github.com/CrunchyData/postgres-operator), [CloudNativePG](https://cloudnative-pg.io/))
- **rabbitmq**: Message broker with management UI (Deployment, no database, AMQP + Prometheus metrics)
  - ⚠️ For production clustering, consider [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)
- **redis**: In-memory data store (StatefulSet, no external database, full redis.conf support)
  - ⚠️ For production HA, consider [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)
  - See [docs/03-redis-operator-migration.md](docs/03-redis-operator-migration.md)

## Common Development Commands

### Working with All Charts

```bash
# Lint all charts
make lint

# Build/package all charts
make build

# Generate templates for all charts
make template

# Install all charts
make install

# Upgrade all charts
make upgrade

# Uninstall all charts
make uninstall

# Update dependencies for all charts
make dependency-update
```

### Chart Metadata and Documentation

```bash
# Validate chart metadata consistency
make validate-metadata

# Sync Chart.yaml keywords from metadata
make sync-keywords

# Preview keyword sync changes
make sync-keywords-dry-run

# Generate chart catalog
make generate-catalog

# Generate Artifact Hub dashboard
make generate-artifacthub-dashboard
```

### Working with Individual Charts

Each chart has operational commands in `make/ops/{chart-name}.mk`

```bash
# Work with specific chart (replace {chart} with: nextcloud, wordpress, etc.)
make -f make/ops/{chart}.mk lint
make -f make/ops/{chart}.mk build
make -f make/ops/{chart}.mk template
make -f make/ops/{chart}.mk install
make -f make/ops/{chart}.mk upgrade
make -f make/ops/{chart}.mk uninstall
```

### Airflow Specific Commands

```bash
# Get admin password
make -f make/ops/airflow.mk airflow-get-password

# Port forward webserver
make -f make/ops/airflow.mk airflow-port-forward

# Check health
make -f make/ops/airflow.mk airflow-health
make -f make/ops/airflow.mk airflow-version

# DAG management
make -f make/ops/airflow.mk airflow-dag-list
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag
make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag CONF='{"key":"value"}'
make -f make/ops/airflow.mk airflow-dag-pause DAG=example_dag
make -f make/ops/airflow.mk airflow-dag-unpause DAG=example_dag
make -f make/ops/airflow.mk airflow-dag-state DAG=example_dag
make -f make/ops/airflow.mk airflow-task-list DAG=example_dag

# Connections and variables
make -f make/ops/airflow.mk airflow-connections-list
make -f make/ops/airflow.mk airflow-connections-add CONN_ID=my_db CONN_TYPE=postgres CONN_URI='postgresql://...'
make -f make/ops/airflow.mk airflow-variables-list
make -f make/ops/airflow.mk airflow-variables-set KEY=api_key VALUE=secret

# User management
make -f make/ops/airflow.mk airflow-users-list
make -f make/ops/airflow.mk airflow-users-create USERNAME=dev PASSWORD=pass EMAIL=dev@example.com ROLE=User

# Database
make -f make/ops/airflow.mk airflow-db-check

# Logs and shell
make -f make/ops/airflow.mk airflow-webserver-logs
make -f make/ops/airflow.mk airflow-scheduler-logs
make -f make/ops/airflow.mk airflow-webserver-logs-all
make -f make/ops/airflow.mk airflow-webserver-shell
make -f make/ops/airflow.mk airflow-scheduler-shell

# Operations
make -f make/ops/airflow.mk airflow-webserver-restart
make -f make/ops/airflow.mk airflow-scheduler-restart
make -f make/ops/airflow.mk airflow-status
```

### WordPress Specific Commands

```bash
# Run wp-cli command
make -f make/ops/wordpress.mk wp-cli CMD="plugin list"

# Install WordPress
make -f make/ops/wordpress.mk wp-install \
  URL=https://example.com \
  TITLE="My Site" \
  ADMIN_USER=admin \
  ADMIN_PASSWORD=secure_pass \
  ADMIN_EMAIL=admin@example.com

# Update WordPress core, plugins, and themes
make -f make/ops/wordpress.mk wp-update
```

### Keycloak Specific Commands

```bash
# Backup all realms to tmp/keycloak-backups/
make -f make/ops/keycloak.mk kc-backup-all-realms

# Import realm from file
make -f make/ops/keycloak.mk kc-import-realm FILE=realm.json

# List all realms
make -f make/ops/keycloak.mk kc-list-realms

# Open shell in Keycloak pod
make -f make/ops/keycloak.mk kc-pod-shell

# Test PostgreSQL connection
make -f make/ops/keycloak.mk kc-db-test

# Run kcadm.sh command
make -f make/ops/keycloak.mk kc-cli CMD="get realms"

# Check cluster status
make -f make/ops/keycloak.mk kc-cluster-status

# Fetch Prometheus metrics
make -f make/ops/keycloak.mk kc-metrics
```

### WireGuard Specific Commands

```bash
# Show WireGuard status
make -f make/ops/wireguard.mk wg-show

# Get server public key
make -f make/ops/wireguard.mk wg-pubkey

# Get peer configuration (auto mode)
make -f make/ops/wireguard.mk wg-get-peer PEER=peer1

# List all peers (auto mode)
make -f make/ops/wireguard.mk wg-list-peers

# Display QR code for mobile (auto mode)
make -f make/ops/wireguard.mk wg-qr PEER=peer1

# Show current wg0.conf
make -f make/ops/wireguard.mk wg-config

# Get service endpoint (LoadBalancer IP or NodePort)
make -f make/ops/wireguard.mk wg-endpoint

# Restart WireGuard
make -f make/ops/wireguard.mk wg-restart

# View logs
make -f make/ops/wireguard.mk wg-logs

# Open shell
make -f make/ops/wireguard.mk wg-shell
```

### RabbitMQ Specific Commands

```bash
# Check cluster status
make -f make/ops/rabbitmq.mk rmq-status

# Check node health
make -f make/ops/rabbitmq.mk rmq-node-health

# List queues, exchanges, connections
make -f make/ops/rabbitmq.mk rmq-list-queues
make -f make/ops/rabbitmq.mk rmq-list-exchanges
make -f make/ops/rabbitmq.mk rmq-list-connections

# User management
make -f make/ops/rabbitmq.mk rmq-add-user USER=myuser PASSWORD=mypass
make -f make/ops/rabbitmq.mk rmq-set-user-tags USER=myuser TAGS=administrator
make -f make/ops/rabbitmq.mk rmq-set-permissions VHOST=/ USER=myuser
make -f make/ops/rabbitmq.mk rmq-list-users

# Virtual host management
make -f make/ops/rabbitmq.mk rmq-add-vhost VHOST=/my-vhost
make -f make/ops/rabbitmq.mk rmq-list-vhosts

# Access credentials
make -f make/ops/rabbitmq.mk rmq-get-credentials

# Port-forward services
make -f make/ops/rabbitmq.mk rmq-port-forward-ui        # Management UI (15672)
make -f make/ops/rabbitmq.mk rmq-port-forward-amqp      # AMQP (5672)
make -f make/ops/rabbitmq.mk rmq-port-forward-metrics   # Prometheus metrics (15692)

# Metrics and monitoring
make -f make/ops/rabbitmq.mk rmq-metrics

# Shell and logs
make -f make/ops/rabbitmq.mk rmq-shell
make -f make/ops/rabbitmq.mk rmq-logs

# Restart deployment
make -f make/ops/rabbitmq.mk rmq-restart
```

### Elasticsearch Specific Commands

```bash
# Get elastic user password
make -f make/ops/elasticsearch.mk es-get-password

# Port forward services
make -f make/ops/elasticsearch.mk es-port-forward           # ES API (9200)
make -f make/ops/elasticsearch.mk kibana-port-forward       # Kibana (5601)

# Health and status
make -f make/ops/elasticsearch.mk es-health
make -f make/ops/elasticsearch.mk es-cluster-status
make -f make/ops/elasticsearch.mk es-nodes
make -f make/ops/elasticsearch.mk es-version
make -f make/ops/elasticsearch.mk kibana-health

# Index management
make -f make/ops/elasticsearch.mk es-indices
make -f make/ops/elasticsearch.mk es-create-index INDEX=myindex
make -f make/ops/elasticsearch.mk es-delete-index INDEX=myindex
make -f make/ops/elasticsearch.mk es-shards
make -f make/ops/elasticsearch.mk es-allocation

# Monitoring
make -f make/ops/elasticsearch.mk es-stats
make -f make/ops/elasticsearch.mk es-tasks
make -f make/ops/elasticsearch.mk es-logs
make -f make/ops/elasticsearch.mk es-logs-all
make -f make/ops/elasticsearch.mk kibana-logs

# Operations
make -f make/ops/elasticsearch.mk es-shell
make -f make/ops/elasticsearch.mk kibana-shell
make -f make/ops/elasticsearch.mk es-restart
make -f make/ops/elasticsearch.mk kibana-restart
make -f make/ops/elasticsearch.mk es-scale REPLICAS=3

# Snapshot/Backup (S3/MinIO)
make -f make/ops/elasticsearch.mk es-snapshot-repos
make -f make/ops/elasticsearch.mk es-create-snapshot-repo REPO=minio BUCKET=backups ENDPOINT=http://minio:9000 ACCESS_KEY=xxx SECRET_KEY=xxx
make -f make/ops/elasticsearch.mk es-snapshots REPO=minio
make -f make/ops/elasticsearch.mk es-create-snapshot REPO=minio SNAPSHOT=snapshot_1
make -f make/ops/elasticsearch.mk es-restore-snapshot REPO=minio SNAPSHOT=snapshot_1
```

### Memcached Specific Commands

```bash
# Show memcached statistics
make -f make/ops/memcached.mk mc-stats

# Flush all data (WARNING: clears all cached data)
make -f make/ops/memcached.mk mc-flush

# Show memcached version
make -f make/ops/memcached.mk mc-version

# Show memcached settings
make -f make/ops/memcached.mk mc-settings

# Show slab statistics
make -f make/ops/memcached.mk mc-slabs

# Show item statistics
make -f make/ops/memcached.mk mc-items

# View logs
make -f make/ops/memcached.mk mc-logs

# Open shell
make -f make/ops/memcached.mk mc-shell

# Port forward to memcached
make -f make/ops/memcached.mk mc-port-forward
```

### MinIO Specific Commands

```bash
# Get credentials
make -f make/ops/minio.mk minio-get-credentials

# Port forward services
make -f make/ops/minio.mk minio-port-forward-api      # S3 API (9000)
make -f make/ops/minio.mk minio-port-forward-console  # Web Console (9001)

# Setup MinIO Client (mc) alias
make -f make/ops/minio.mk minio-mc-alias

# Bucket operations
make -f make/ops/minio.mk minio-create-bucket BUCKET=mybucket
make -f make/ops/minio.mk minio-list-buckets

# Health and monitoring
make -f make/ops/minio.mk minio-health
make -f make/ops/minio.mk minio-metrics
make -f make/ops/minio.mk minio-server-info

# Cluster operations
make -f make/ops/minio.mk minio-cluster-status
make -f make/ops/minio.mk minio-scale REPLICAS=4
make -f make/ops/minio.mk minio-restart

# Service endpoints
make -f make/ops/minio.mk minio-service-endpoint

# Logs and shell
make -f make/ops/minio.mk minio-logs
make -f make/ops/minio.mk minio-logs-all
make -f make/ops/minio.mk minio-shell

# Disk usage
make -f make/ops/minio.mk minio-disk-usage

# Version info
make -f make/ops/minio.mk minio-version
```

### PostgreSQL Specific Commands

```bash
# Connection and shell
make -f make/ops/postgresql.mk pg-shell
make -f make/ops/postgresql.mk pg-bash
make -f make/ops/postgresql.mk pg-logs

# Connection test
make -f make/ops/postgresql.mk pg-ping
make -f make/ops/postgresql.mk pg-version

# Database management
make -f make/ops/postgresql.mk pg-list-databases
make -f make/ops/postgresql.mk pg-list-tables
make -f make/ops/postgresql.mk pg-list-users
make -f make/ops/postgresql.mk pg-database-size
make -f make/ops/postgresql.mk pg-all-databases-size

# Statistics and monitoring
make -f make/ops/postgresql.mk pg-stats
make -f make/ops/postgresql.mk pg-activity           # Active connections and queries
make -f make/ops/postgresql.mk pg-connections        # Connection count
make -f make/ops/postgresql.mk pg-locks              # Current locks
make -f make/ops/postgresql.mk pg-slow-queries       # Slow queries (requires pg_stat_statements)

# Replication management
make -f make/ops/postgresql.mk pg-replication-status # Replication status from master
make -f make/ops/postgresql.mk pg-replication-lag    # Replication lag
make -f make/ops/postgresql.mk pg-recovery-status    # Recovery status (for replicas)
make -f make/ops/postgresql.mk pg-wal-status         # WAL status

# Backup and restore
make -f make/ops/postgresql.mk pg-backup             # Backup single database
make -f make/ops/postgresql.mk pg-backup-all         # Backup all databases
make -f make/ops/postgresql.mk pg-restore FILE=path/to/backup.sql

# Maintenance
make -f make/ops/postgresql.mk pg-vacuum             # Run VACUUM
make -f make/ops/postgresql.mk pg-vacuum-analyze     # Run VACUUM ANALYZE
make -f make/ops/postgresql.mk pg-vacuum-full        # Run VACUUM FULL (locks tables)
make -f make/ops/postgresql.mk pg-analyze            # Run ANALYZE
make -f make/ops/postgresql.mk pg-reindex TABLE=table_name

# Configuration
make -f make/ops/postgresql.mk pg-config             # Show all configuration
make -f make/ops/postgresql.mk pg-config-get PARAM=max_connections
make -f make/ops/postgresql.mk pg-reload             # Reload configuration

# Utilities
make -f make/ops/postgresql.mk pg-port-forward       # Port forward to localhost:5432
make -f make/ops/postgresql.mk pg-restart            # Restart StatefulSet
make -f make/ops/postgresql.mk pg-scale REPLICAS=2   # Scale replicas
make -f make/ops/postgresql.mk pg-get-password       # Get postgres password
make -f make/ops/postgresql.mk pg-get-replication-password # Get replication password
```

### Kafka Specific Commands

```bash
# Topic Management
make -f make/ops/kafka.mk kafka-topics-list
make -f make/ops/kafka.mk kafka-topic-create TOPIC=my-topic PARTITIONS=3 REPLICATION=2
make -f make/ops/kafka.mk kafka-topic-describe TOPIC=my-topic
make -f make/ops/kafka.mk kafka-topic-delete TOPIC=my-topic

# Consumer Groups
make -f make/ops/kafka.mk kafka-consumer-groups-list
make -f make/ops/kafka.mk kafka-consumer-group-describe GROUP=my-group

# Producer/Consumer
make -f make/ops/kafka.mk kafka-produce TOPIC=my-topic  # Interactive producer
make -f make/ops/kafka.mk kafka-consume TOPIC=my-topic  # Consumer from beginning

# Broker Information
make -f make/ops/kafka.mk kafka-broker-list
make -f make/ops/kafka.mk kafka-cluster-id

# Kafka UI
make -f make/ops/kafka.mk kafka-ui-port-forward  # Port forward UI to localhost:8080

# Utilities
make -f make/ops/kafka.mk kafka-port-forward  # Port forward to localhost:9092
make -f make/ops/kafka.mk kafka-restart       # Restart StatefulSet
make -f make/ops/kafka.mk kafka-scale REPLICAS=3  # Scale brokers
make -f make/ops/kafka.mk kafka-shell
make -f make/ops/kafka.mk kafka-logs
```

### Redis Specific Commands

```bash
# Ping Redis server
make -f make/ops/redis.mk redis-ping

# Get server info
make -f make/ops/redis.mk redis-info

# Monitor commands in real-time
make -f make/ops/redis.mk redis-monitor

# Check memory usage
make -f make/ops/redis.mk redis-memory

# Get statistics
make -f make/ops/redis.mk redis-stats

# List client connections
make -f make/ops/redis.mk redis-clients

# Data management
make -f make/ops/redis.mk redis-bgsave           # Trigger background save
make -f make/ops/redis.mk redis-backup           # Backup to tmp/redis-backups/
make -f make/ops/redis.mk redis-restore FILE=... # Restore from backup

# Analysis
make -f make/ops/redis.mk redis-slowlog          # Get slow query log
make -f make/ops/redis.mk redis-bigkeys          # Find biggest keys
make -f make/ops/redis.mk redis-config-get PARAM=maxmemory

# Replication (Master-Slave)
make -f make/ops/redis.mk redis-replication-info # Get replication status for all pods
make -f make/ops/redis.mk redis-master-info      # Get master pod replication info
make -f make/ops/redis.mk redis-replica-lag      # Check replication lag
make -f make/ops/redis.mk redis-role POD=redis-0 # Check role of specific pod

# Run redis-cli command
make -f make/ops/redis.mk redis-cli CMD="get mykey"

# Open shell
make -f make/ops/redis.mk redis-shell

# View logs
make -f make/ops/redis.mk redis-logs
```

### Paperless-ngx Specific Commands

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
```

### Uptime Kuma Specific Commands

```bash
# View logs and access shell
make -f make/ops/uptime-kuma.mk uk-logs
make -f make/ops/uptime-kuma.mk uk-shell

# Port forward to localhost:3001
make -f make/ops/uptime-kuma.mk uk-port-forward

# Health checks
make -f make/ops/uptime-kuma.mk uk-check-db
make -f make/ops/uptime-kuma.mk uk-check-storage

# Backup and restore (SQLite)
make -f make/ops/uptime-kuma.mk uk-backup-sqlite
make -f make/ops/uptime-kuma.mk uk-restore-sqlite FILE=path/to/kuma.db

# User management
make -f make/ops/uptime-kuma.mk uk-reset-password

# System information
make -f make/ops/uptime-kuma.mk uk-version
make -f make/ops/uptime-kuma.mk uk-node-info
make -f make/ops/uptime-kuma.mk uk-get-settings

# Operations
make -f make/ops/uptime-kuma.mk uk-restart
make -f make/ops/uptime-kuma.mk uk-scale REPLICAS=2
```

### RustFS Specific Commands

```bash
# Get RustFS credentials
make -f make/ops/rustfs.mk rustfs-get-credentials

# Port forward services
make -f make/ops/rustfs.mk rustfs-port-forward-api      # S3 API (9000)
make -f make/ops/rustfs.mk rustfs-port-forward-console  # Console (9001)

# Test S3 API (requires MinIO Client 'mc')
make -f make/ops/rustfs.mk rustfs-test-s3

# Health and monitoring
make -f make/ops/rustfs.mk rustfs-health
make -f make/ops/rustfs.mk rustfs-metrics
make -f make/ops/rustfs.mk rustfs-status
make -f make/ops/rustfs.mk rustfs-all

# Operations
make -f make/ops/rustfs.mk rustfs-scale REPLICAS=4
make -f make/ops/rustfs.mk rustfs-restart
make -f make/ops/rustfs.mk rustfs-backup SNAPSHOT_CLASS=csi-hostpath-snapclass

# Logs and shell
make -f make/ops/rustfs.mk rustfs-logs           # Pod 0 logs
make -f make/ops/rustfs.mk rustfs-logs-all       # All pods logs
make -f make/ops/rustfs.mk rustfs-shell
```

### Kind (Local Testing)

```bash
# Create local Kubernetes cluster
make kind-create

# Delete local cluster
make kind-delete

# Cluster name: sb-helm-charts (defined in KIND_CLUSTER_NAME)
# Config: kind-config.yaml
```

## Chart Testing

The repository uses chart-testing (ct) for validation:
- Config: `ct.yaml`
- Timeout: 600s for chart operations
- Chart directory: `charts/`

## Automation Scripts

### Metadata Management

**Validation Script** (`scripts/validate-chart-metadata.py`):
- Validates keywords consistency between Chart.yaml and charts-metadata.yaml
- Checks all charts have metadata entries
- Provides clear error messages for discrepancies
- Exit code 0 for success, 1 for failures

**Sync Script** (`scripts/sync-chart-keywords.py`):
- Syncs Chart.yaml keywords from charts-metadata.yaml
- Supports dry-run mode for preview
- Can sync all charts or specific chart with --chart flag
- Preserves Chart.yaml formatting during updates

**Catalog Generator** (`scripts/generate-chart-catalog.py`):
- Generates comprehensive chart catalog (docs/CHARTS.md) from charts-metadata.yaml
- Organizes charts by category (Application/Infrastructure)
- Creates searchable indexes by tags and keywords
- Includes version badges, descriptions, and installation examples
- Auto-discovers all charts from metadata

**Dependencies** (`scripts/requirements.txt`):
- PyYAML>=6.0 for YAML processing
- Install: `pip install -r scripts/requirements.txt`

### Usage Examples

```bash
# Validate metadata consistency
make validate-metadata
# or
python3 scripts/validate-chart-metadata.py

# Preview keyword sync
make sync-keywords-dry-run
# or
python3 scripts/sync-chart-keywords.py --dry-run

# Apply keyword sync
make sync-keywords
# or
python3 scripts/sync-chart-keywords.py

# Sync specific chart
python3 scripts/sync-chart-keywords.py --chart keycloak

# Generate chart catalog
make generate-catalog
# or
python3 scripts/generate-chart-catalog.py

# Specify custom output location
python3 scripts/generate-chart-catalog.py --output docs/CHARTS.md
```

## Architecture Principles

### Configuration Management

**DO:**
- Use ConfigMaps to mount entire configuration files (e.g., `config.php`, `wp-config.php`)
- Keep application configurations close to their original format
- Use Secrets for sensitive data (passwords, API keys)
- Reference external services (databases) via values

**DON'T:**
- Create complex environment variable mappings
- Try to abstract away application-specific configuration
- Include database charts as subcharts

### Database Strategy

All charts expect **external** databases:

- **keycloak**: External PostgreSQL 13+ (required for Keycloak 26.x), Redis 6+ (optional)
  - Supports SSL/TLS connections: `disable`, `require`, `verify-ca`, `verify-full`
  - Supports mutual TLS (mTLS) with client certificates
  - Health endpoints use management port 9000 (Keycloak 26.x breaking change)
- **nextcloud**: External PostgreSQL 16 + Redis 8
- **wordpress**: External MySQL/MariaDB
- **wireguard**: No database required (first chart without database dependency)
- **devpi**: Can use built-in SQLite or external PostgreSQL

Configure via `values.yaml`:
```yaml
postgresql:
  enabled: false  # ALWAYS false - never auto-install
  external:
    enabled: true
    host: "postgres-service.default.svc.cluster.local"
    port: 5432
    database: "nextcloud"
    username: "nextcloud"
    password: ""  # Required - deployment will fail if empty
    # SSL/TLS support (Keycloak chart)
    ssl:
      enabled: false
      mode: "require"  # disable, require, verify-ca, verify-full
      certificateSecret: ""  # Required for verify-ca/verify-full
      rootCertKey: "ca.crt"
      clientCertKey: ""  # Optional: for mutual TLS
      clientKeyKey: ""   # Optional: for mutual TLS
```

**CRITICAL**: The `enabled: false` pattern is a core project value. Never suggest installing databases as subcharts.

**PostgreSQL SSL Notes (Keycloak):**
- PostgreSQL JDBC driver uses different parameters than psql CLI
- `require` mode: Uses `ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory`
- `verify-ca`/`verify-full`: Uses `sslmode=verify-ca` or `sslmode=verify-full` with certificate paths
- InitContainer health checks support SSL via `PGSSLMODE` environment variable
- Client certificates (mTLS) must have empty default values to avoid always being included

### Storage

Charts use PersistentVolumeClaims for data persistence:

- **keycloak**: StatefulSet with `volumeClaimTemplates` for each pod
- **nextcloud**: `/data` (user files), `/config` (Nextcloud config)
- **wordpress**: `/var/www/html` (WordPress files)

Default: `ReadWriteOnce` with `Retain` reclaim policy for production safety.

## Values File Patterns

### Standard Structure

```yaml
# Application-specific config
{app}:
  adminUser: "admin"
  adminPassword: ""  # Required

# External services (disabled subcharts)
postgresql:
  enabled: false
  external:
    enabled: true
    host: ""
    database: ""
    username: ""
    password: ""

# Persistence
persistence:
  enabled: true
  storageClass: ""
  size: "10Gi"
  accessMode: ReadWriteOnce

# Standard k8s resources
replicaCount: 1
image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent

resources:
  limits:
    cpu: "1000m"
    memory: "1Gi"
  requests:
    cpu: "100m"
    memory: "128Mi"

ingress:
  enabled: false
  className: ""
  hosts: []
  tls: []
```

### Production Examples

Check `values-example.yaml` in each chart for production-ready configurations.

### Home Server / Low-Resource Configurations

Some charts include optimized configurations for home servers and low-resource environments:

- **WordPress**: `values-homeserver.yaml` provides:
  - 50% resource reduction (500m CPU, 512Mi RAM limits)
  - Reduced storage (5Gi default)
  - PHP memory optimizations (256M/512M limits)
  - Security hardening (file editing disabled, auto-updates disabled)
  - Reduced post revisions (5) and autosave interval (5 minutes)
  - Suitable for Raspberry Pi 4, Intel NUC, or small VPS

## Git Workflow

**Main branch:** `master` (use for PRs)
**Current branch:** `develop`

## CI/CD

GitHub Actions workflows:
- `release.yaml`: Automated chart releases using Helm chart-releaser
- `cleanup.yaml`: Maintenance tasks

## Chart Release Process

Charts are automatically released via GitHub Actions when changes are pushed to main branch. Packaged charts are available at:
- Repository: `https://scriptonbasestar-docker.github.io/sb-helm-charts`

Add to Helm:
```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update
```

## Production Features (Recent Charts)

Modern charts (WordPress, Nextcloud, Keycloak) include production-ready features:

### High Availability

- **PodDisruptionBudget**: `minAvailable` or `maxUnavailable` settings for maintenance windows
- **HorizontalPodAutoscaler**: CPU/memory-based auto-scaling
- **Clustering**: JGroups + DNS_PING for Keycloak distributed cache

### Security

- **NetworkPolicy**: Ingress/egress rules for database and inter-pod communication
- **RBAC**: ServiceAccount with minimal required permissions
- **Secret Management**: Separate secrets for database credentials, admin passwords

### Reliability

- **InitContainers**: Database health checks (e.g., `pg_isready`) before app startup
- **Health Probes**: Liveness, readiness, and startup probes configured per application
- **Resource Limits**: Memory/CPU requests and limits to prevent resource starvation

### Observability

- **ServiceMonitor**: Prometheus Operator CRD for metrics scraping
- **Metrics Endpoints**: Application-specific metrics exposed (e.g., `/metrics`, `/q/metrics`)
- **Structured Logging**: Logs written to stdout for Kubernetes log aggregation

## Chart Versioning

All charts follow [Semantic Versioning 2.0.0](https://semver.org/). See [docs/CHART_VERSION_POLICY.md](docs/CHART_VERSION_POLICY.md) for complete versioning rules.

### Version Components

- **Chart version**: Semantic version of the Helm chart (e.g., `0.2.0`)
  - MAJOR: Breaking changes requiring user action
  - MINOR: New features, backward-compatible
  - PATCH: Bug fixes, documentation updates
- **appVersion**: Upstream application version (e.g., `26.0.7` for Keycloak)
- **License**: `BSD-3-Clause` (chart license, documented in `Chart.yaml`)
- **sources**: Include both chart repository and upstream application repository

Application licenses differ from chart license (e.g., Keycloak: Apache 2.0) and are documented in README.md.

### Current Chart Versions

All 16 charts are now at **version 0.3.0 (Mature - production-ready)**:

**Application Charts (13):**
- browserless-chrome, devpi, immich, jellyfin, keycloak, nextcloud, paperless-ngx, rsshub, rustfs, uptime-kuma, vaultwarden, wireguard, wordpress

**Infrastructure Charts (3):**
- memcached, rabbitmq, redis

### Version Increment Guidelines

**MAJOR (X.0.0)** - Breaking changes:
- Renaming/removing values.yaml parameters
- Changing resource names or label selectors
- Restructuring configuration hierarchy
- Must provide migration guide

**MINOR (0.X.0)** - New features:
- Adding optional configuration parameters
- New features (disabled by default)
- New Makefile commands
- Backward-compatible template additions

**PATCH (0.0.X)** - Bug fixes:
- Template rendering errors
- Documentation updates
- Non-functional improvements
- Security fixes

## Template Patterns

### StatefulSet vs Deployment

- **StatefulSet**: For stable network identity, ordered scaling (Keycloak clustering)
- **Deployment**: For stateless or externally-stored state (WordPress, Nextcloud)

### Helper Functions (_helpers.tpl)

Standard helpers in all charts:

```yaml
{{- define "{chart}.fullname" -}}
{{- define "{chart}.name" -}}
{{- define "{chart}.labels" -}}
{{- define "{chart}.selectorLabels" -}}
{{- define "{chart}.serviceAccountName" -}}
```

Chart-specific helpers for complex patterns:

```yaml
{{- define "keycloak.postgresql.jdbcUrl" -}}
{{- define "keycloak.headlessServiceName" -}}
```

**Important Notes on Keycloak Helpers:**
- `keycloak.postgresql.jdbcUrl` generates PostgreSQL JDBC URLs with proper SSL parameters
- Handles all SSL modes: `disable`, `require`, `verify-ca`, `verify-full`
- Automatically constructs certificate paths for mTLS when client certificates are provided
- Falls back to NonValidatingFactory if certificates are not provided in verify modes

### NOTES.txt Pattern

Post-install instructions should include:

1. **Access information**: Ingress URLs, port-forward commands
2. **Credential retrieval**: kubectl commands to decode secrets
3. **Feature-specific guidance**: Clustering status, metrics endpoints
4. **Production warnings**: External DB requirements, TLS recommendations

## Makefile Architecture

The hierarchical Makefile system:

```text
Makefile                     # Root orchestrator
├── Makefile.common.mk       # Base targets (lint, build, install)
└── Makefile.{chart}.mk      # Chart-specific operations
```

Each chart-specific Makefile:

1. Includes `Makefile.common.mk`
2. Defines `CHART_NAME` and `CHART_DIR`
3. Adds operational commands (wp-cli, kc-backup-all-realms, etc.)
4. Extends help output

## Important Notes

- Configuration files are king - preserve application's native config format
- Keep it simple - if Helm complexity exceeds application complexity, something is wrong
- External dependencies (databases) are ALWAYS separate installations
- Use `values-example.yaml` as production deployment templates
- Chart version follows semantic versioning in `Chart.yaml`
- Git commits are automated; `git push` requires manual execution
- **ALWAYS update `charts-metadata.yaml` when adding or modifying charts** - see Chart Metadata section above

### Kubernetes Environment Variable Precedence

**CRITICAL**: When the same environment variable is defined multiple times in Kubernetes, the **first definition takes precedence**, not the last.

This means `extraEnv` in values.yaml **cannot override** chart-generated environment variables. For example:

```yaml
# Chart template generates:
- name: KC_DB_URL
  value: "jdbc:postgresql://..."

# extraEnv attempting override (THIS WILL NOT WORK):
extraEnv:
  - name: KC_DB_URL
    value: "my-custom-url"  # IGNORED - first definition wins
```

**Workaround**: To use custom database URLs or parameters not supported by the chart:
1. Disable auto-generation: `postgresql.external.enabled=false`
2. Manually configure all database env vars in `extraEnv`

### Keycloak 26.x Breaking Changes

- **Health endpoints**: Moved from port 8080 to port 9000 (management port)
  - Liveness: `http://localhost:9000/health/live`
  - Readiness: `http://localhost:9000/health/ready`
  - Startup: `http://localhost:9000/health/started`
- **Hostname v1**: Completely removed - must use hostname v2 configuration
- **PostgreSQL 13+**: Minimum requirement increased from 12.x
- **CLI-based clustering**: Use `--cache-embedded-network-*` CLI options instead of env vars
