# Makefile Commands Reference

Complete reference for all chart-specific make commands in sb-helm-charts repository.

## Quick Links

- [Common Commands](#common-commands)
- [Application Charts](#application-charts)
  - [Airflow](#airflow) | [Grafana](#grafana) | [Harbor](#harbor) | [Immich](#immich) | [Jellyfin](#jellyfin)
  - [Keycloak](#keycloak) | [MLflow](#mlflow) | [Nextcloud](#nextcloud) | [Paperless-ngx](#paperless-ngx)
  - [Uptime Kuma](#uptime-kuma) | [Vaultwarden](#vaultwarden) | [WireGuard](#wireguard) | [WordPress](#wordpress)
- [Infrastructure Charts](#infrastructure-charts)
  - [Alertmanager](#alertmanager) | [Blackbox Exporter](#blackbox-exporter) | [Elasticsearch](#elasticsearch)
  - [Kafka](#kafka) | [Kube State Metrics](#kube-state-metrics) | [Loki](#loki) | [Memcached](#memcached)
  - [MinIO](#minio) | [MongoDB](#mongodb) | [MySQL](#mysql) | [Node Exporter](#node-exporter)
  - [pgAdmin](#pgadmin) | [phpMyAdmin](#phpmyadmin) | [PostgreSQL](#postgresql) | [Prometheus](#prometheus)
  - [Promtail](#promtail) | [Pushgateway](#pushgateway) | [RabbitMQ](#rabbitmq) | [Redis](#redis) | [RustFS](#rustfs)
- [Local Testing](#local-testing-kind)

## Usage Pattern

All chart-specific commands follow this pattern:

```bash
make -f make/ops/{chart-name}.mk {command}
```

**Examples:**
```bash
# WordPress
make -f make/ops/wordpress.mk wp-cli CMD="plugin list"

# Keycloak
make -f make/ops/keycloak.mk kc-backup-all-realms

# PostgreSQL
make -f make/ops/postgresql.mk pg-shell
```

---

## Common Commands

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

---

## Application Charts

### Airflow

Apache Airflow workflow orchestration platform.

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

### Grafana

Grafana metrics visualization and dashboarding platform.

```bash
# Access and credentials
make -f make/ops/grafana.mk grafana-get-password
make -f make/ops/grafana.mk grafana-port-forward
make -f make/ops/grafana.mk grafana-shell
make -f make/ops/grafana.mk grafana-logs

# Data sources
make -f make/ops/grafana.mk grafana-add-prometheus URL=http://prometheus:9090
make -f make/ops/grafana.mk grafana-add-loki URL=http://loki:3100
make -f make/ops/grafana.mk grafana-list-datasources

# Dashboards
make -f make/ops/grafana.mk grafana-list-dashboards
make -f make/ops/grafana.mk grafana-export-dashboard UID=dashboard-uid
make -f make/ops/grafana.mk grafana-import-dashboard FILE=dashboard.json

# Database operations
make -f make/ops/grafana.mk grafana-db-backup
make -f make/ops/grafana.mk grafana-db-restore FILE=backup.tar.gz

# Operations
make -f make/ops/grafana.mk grafana-reset-password PASSWORD=newpass
make -f make/ops/grafana.mk grafana-restart
make -f make/ops/grafana.mk grafana-api CMD='/api/health'
```

### Harbor

Private container registry with vulnerability scanning and image signing.

```bash
# Access & Credentials
make -f make/ops/harbor.mk harbor-get-admin-password
make -f make/ops/harbor.mk harbor-port-forward  # UI on localhost:8080

# Component Status
make -f make/ops/harbor.mk harbor-status
make -f make/ops/harbor.mk harbor-core-logs
make -f make/ops/harbor.mk harbor-core-logs-all
make -f make/ops/harbor.mk harbor-registry-logs
make -f make/ops/harbor.mk harbor-registry-logs-all
make -f make/ops/harbor.mk harbor-core-shell
make -f make/ops/harbor.mk harbor-registry-shell

# Health & Monitoring
make -f make/ops/harbor.mk harbor-health
make -f make/ops/harbor.mk harbor-core-health
make -f make/ops/harbor.mk harbor-registry-health
make -f make/ops/harbor.mk harbor-version
make -f make/ops/harbor.mk harbor-metrics

# Registry Operations
make -f make/ops/harbor.mk harbor-test-push
make -f make/ops/harbor.mk harbor-test-pull
make -f make/ops/harbor.mk harbor-catalog
make -f make/ops/harbor.mk harbor-projects
make -f make/ops/harbor.mk harbor-gc              # Trigger garbage collection
make -f make/ops/harbor.mk harbor-gc-status

# Database Operations
make -f make/ops/harbor.mk harbor-db-test
make -f make/ops/harbor.mk harbor-db-migrate
make -f make/ops/harbor.mk harbor-redis-test

# Operations
make -f make/ops/harbor.mk harbor-restart
make -f make/ops/harbor.mk harbor-scale REPLICAS=2
```

### Keycloak

IAM solution with SSO, clustering, and realm management.

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

### Paperless-ngx

Document management system with OCR.

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

### Uptime Kuma

Self-hosted monitoring tool with beautiful UI.

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

### WireGuard

VPN solution with peer management.

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

### WordPress

WordPress CMS with wp-cli integration.

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

---

## Infrastructure Charts

### Alertmanager

Prometheus Alertmanager for alert routing and notification.

```bash
# Basic operations
make -f make/ops/alertmanager.mk am-logs
make -f make/ops/alertmanager.mk am-logs-all
make -f make/ops/alertmanager.mk am-shell
make -f make/ops/alertmanager.mk am-restart

# Health and status
make -f make/ops/alertmanager.mk am-status
make -f make/ops/alertmanager.mk am-version
make -f make/ops/alertmanager.mk am-health
make -f make/ops/alertmanager.mk am-ready
make -f make/ops/alertmanager.mk am-cluster-status

# Configuration
make -f make/ops/alertmanager.mk am-config
make -f make/ops/alertmanager.mk am-reload
make -f make/ops/alertmanager.mk am-validate-config

# Alerts management
make -f make/ops/alertmanager.mk am-list-alerts
make -f make/ops/alertmanager.mk am-list-alerts-json
make -f make/ops/alertmanager.mk am-get-alert FINGERPRINT=abc123

# Silences management
make -f make/ops/alertmanager.mk am-list-silences
make -f make/ops/alertmanager.mk am-list-silences-json
make -f make/ops/alertmanager.mk am-get-silence ID=abc123
make -f make/ops/alertmanager.mk am-delete-silence ID=abc123

# Receivers and routes
make -f make/ops/alertmanager.mk am-list-receivers
make -f make/ops/alertmanager.mk am-test-receiver

# Metrics and monitoring
make -f make/ops/alertmanager.mk am-metrics
make -f make/ops/alertmanager.mk am-port-forward
```

### Blackbox Exporter

Blackbox Exporter for probing endpoints.

```bash
# Probe testing
make -f make/ops/blackbox-exporter.mk bbe-probe-http TARGET=https://example.com
make -f make/ops/blackbox-exporter.mk bbe-probe-https TARGET=https://example.com
make -f make/ops/blackbox-exporter.mk bbe-probe-tcp TARGET=example.com:443
make -f make/ops/blackbox-exporter.mk bbe-probe-dns TARGET=8.8.8.8
make -f make/ops/blackbox-exporter.mk bbe-probe-icmp TARGET=8.8.8.8
make -f make/ops/blackbox-exporter.mk bbe-probe-custom TARGET=https://api.example.com MODULE=http_2xx

# Module management
make -f make/ops/blackbox-exporter.mk bbe-list-modules
make -f make/ops/blackbox-exporter.mk bbe-test-module MODULE=http_2xx

# Basic operations
make -f make/ops/blackbox-exporter.mk bbe-logs
make -f make/ops/blackbox-exporter.mk bbe-shell
make -f make/ops/blackbox-exporter.mk bbe-restart
make -f make/ops/blackbox-exporter.mk bbe-status
make -f make/ops/blackbox-exporter.mk bbe-version
make -f make/ops/blackbox-exporter.mk bbe-health
make -f make/ops/blackbox-exporter.mk bbe-config

# Metrics
make -f make/ops/blackbox-exporter.mk bbe-metrics
make -f make/ops/blackbox-exporter.mk bbe-probe-metrics

# Port forward
make -f make/ops/blackbox-exporter.mk bbe-port-forward
```

### Elasticsearch

Distributed search and analytics engine with Kibana.

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

### Kafka

Apache Kafka streaming platform with KRaft mode and management UI.

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

### Kube State Metrics

Kube State Metrics exposes Kubernetes object state as Prometheus metrics.

```bash
# Basic operations
make -f make/ops/kube-state-metrics.mk ksm-logs
make -f make/ops/kube-state-metrics.mk ksm-shell
make -f make/ops/kube-state-metrics.mk ksm-restart

# Health and status
make -f make/ops/kube-state-metrics.mk ksm-status
make -f make/ops/kube-state-metrics.mk ksm-version
make -f make/ops/kube-state-metrics.mk ksm-health

# Metrics queries
make -f make/ops/kube-state-metrics.mk ksm-metrics
make -f make/ops/kube-state-metrics.mk ksm-pod-metrics
make -f make/ops/kube-state-metrics.mk ksm-deployment-metrics
make -f make/ops/kube-state-metrics.mk ksm-node-metrics
make -f make/ops/kube-state-metrics.mk ksm-service-metrics
make -f make/ops/kube-state-metrics.mk ksm-pv-metrics
make -f make/ops/kube-state-metrics.mk ksm-pvc-metrics
make -f make/ops/kube-state-metrics.mk ksm-namespace-metrics

# Resource status
make -f make/ops/kube-state-metrics.mk ksm-pod-status
make -f make/ops/kube-state-metrics.mk ksm-deployment-status
make -f make/ops/kube-state-metrics.mk ksm-node-status

# Port forward
make -f make/ops/kube-state-metrics.mk ksm-port-forward
make -f make/ops/kube-state-metrics.mk ksm-port-forward-telemetry
```

### Loki

Loki log aggregation system with Grafana integration.

```bash
# Basic operations
make -f make/ops/loki.mk loki-logs
make -f make/ops/loki.mk loki-logs-all
make -f make/ops/loki.mk loki-shell
make -f make/ops/loki.mk loki-port-forward          # HTTP (3100)
make -f make/ops/loki.mk loki-port-forward-grpc     # gRPC (9095)

# Health and status
make -f make/ops/loki.mk loki-ready
make -f make/ops/loki.mk loki-health
make -f make/ops/loki.mk loki-metrics
make -f make/ops/loki.mk loki-version
make -f make/ops/loki.mk loki-config

# Ring and clustering
make -f make/ops/loki.mk loki-ring-status
make -f make/ops/loki.mk loki-memberlist-status

# Query and logs
make -f make/ops/loki.mk loki-query QUERY='{job="app"}' TIME=5m
make -f make/ops/loki.mk loki-labels
make -f make/ops/loki.mk loki-label-values LABEL=job
make -f make/ops/loki.mk loki-tail QUERY='{job="app"}'

# Data management
make -f make/ops/loki.mk loki-flush-index
make -f make/ops/loki.mk loki-check-storage

# Testing and integration
make -f make/ops/loki.mk loki-test-push
make -f make/ops/loki.mk loki-grafana-datasource

# Scaling
make -f make/ops/loki.mk loki-scale REPLICAS=3
make -f make/ops/loki.mk loki-restart
```

### Memcached

High-performance distributed memory caching system.

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

### MinIO

High-performance S3-compatible object storage.

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

### MongoDB

MongoDB NoSQL database with replica set support.

```bash
# Basic operations
make -f make/ops/mongodb.mk mongo-shell
make -f make/ops/mongodb.mk mongo-bash
make -f make/ops/mongodb.mk mongo-logs
make -f make/ops/mongodb.mk mongo-port-forward

# Database operations
make -f make/ops/mongodb.mk mongo-backup
make -f make/ops/mongodb.mk mongo-restore FILE=backup.gz
make -f make/ops/mongodb.mk mongo-list-dbs
make -f make/ops/mongodb.mk mongo-list-collections DB=mydb
make -f make/ops/mongodb.mk mongo-db-stats DB=mydb

# Replica set operations
make -f make/ops/mongodb.mk mongo-rs-status
make -f make/ops/mongodb.mk mongo-rs-config
make -f make/ops/mongodb.mk mongo-rs-stepdown
make -f make/ops/mongodb.mk mongo-rs-add-member HOST=mongodb-3:27017
make -f make/ops/mongodb.mk mongo-rs-remove-member HOST=mongodb-3:27017

# User management
make -f make/ops/mongodb.mk mongo-create-user DB=mydb USER=user PASSWORD=pass ROLE=readWrite
make -f make/ops/mongodb.mk mongo-list-users DB=mydb
make -f make/ops/mongodb.mk mongo-grant-role DB=mydb USER=user ROLE=dbAdmin

# Performance & monitoring
make -f make/ops/mongodb.mk mongo-server-status
make -f make/ops/mongodb.mk mongo-current-ops
make -f make/ops/mongodb.mk mongo-top

# Maintenance
make -f make/ops/mongodb.mk mongo-compact DB=mydb COLLECTION=mycol
make -f make/ops/mongodb.mk mongo-reindex DB=mydb COLLECTION=mycol
make -f make/ops/mongodb.mk mongo-validate DB=mydb COLLECTION=mycol

# CLI commands
make -f make/ops/mongodb.mk mongo-cli CMD="db.version()"
make -f make/ops/mongodb.mk mongo-ping
make -f make/ops/mongodb.mk mongo-restart
```

### MySQL

MySQL relational database with replication support.

```bash
# Basic operations
make -f make/ops/mysql.mk mysql-shell
make -f make/ops/mysql.mk mysql-logs
make -f make/ops/mysql.mk mysql-port-forward

# Database operations
make -f make/ops/mysql.mk mysql-backup
make -f make/ops/mysql.mk mysql-restore FILE=backup.sql.gz
make -f make/ops/mysql.mk mysql-create-db DB=mydb
make -f make/ops/mysql.mk mysql-list-dbs
make -f make/ops/mysql.mk mysql-db-size

# User management
make -f make/ops/mysql.mk mysql-create-user USER=myuser PASSWORD=mypass
make -f make/ops/mysql.mk mysql-grant-privileges USER=myuser DB=mydb
make -f make/ops/mysql.mk mysql-list-users
make -f make/ops/mysql.mk mysql-show-grants USER=myuser

# Replication (Master-Replica)
make -f make/ops/mysql.mk mysql-replication-info
make -f make/ops/mysql.mk mysql-master-status POD=mysql-0
make -f make/ops/mysql.mk mysql-replica-status POD=mysql-1
make -f make/ops/mysql.mk mysql-replica-lag

# Performance & monitoring
make -f make/ops/mysql.mk mysql-status
make -f make/ops/mysql.mk mysql-processlist
make -f make/ops/mysql.mk mysql-variables
make -f make/ops/mysql.mk mysql-innodb-status

# Maintenance
make -f make/ops/mysql.mk mysql-optimize DB=mydb
make -f make/ops/mysql.mk mysql-check DB=mydb
make -f make/ops/mysql.mk mysql-repair DB=mydb
make -f make/ops/mysql.mk mysql-analyze DB=mydb

# CLI commands
make -f make/ops/mysql.mk mysql-cli CMD="SELECT VERSION();"
make -f make/ops/mysql.mk mysql-ping
make -f make/ops/mysql.mk mysql-version
make -f make/ops/mysql.mk mysql-restart
```

### Node Exporter

Prometheus Node Exporter for hardware and OS metrics.

```bash
# Basic operations
make -f make/ops/node-exporter.mk ne-logs
make -f make/ops/node-exporter.mk ne-logs-node NODE=node-name
make -f make/ops/node-exporter.mk ne-shell
make -f make/ops/node-exporter.mk ne-shell-node NODE=node-name

# Health and status
make -f make/ops/node-exporter.mk ne-status
make -f make/ops/node-exporter.mk ne-version
make -f make/ops/node-exporter.mk ne-metrics
make -f make/ops/node-exporter.mk ne-metrics-node NODE=node-name

# Node operations
make -f make/ops/node-exporter.mk ne-list-nodes
make -f make/ops/node-exporter.mk ne-pod-on-node NODE=node-name

# Metrics queries
make -f make/ops/node-exporter.mk ne-cpu-metrics
make -f make/ops/node-exporter.mk ne-memory-metrics
make -f make/ops/node-exporter.mk ne-disk-metrics
make -f make/ops/node-exporter.mk ne-network-metrics
make -f make/ops/node-exporter.mk ne-load-metrics

# Port forward
make -f make/ops/node-exporter.mk ne-port-forward
make -f make/ops/node-exporter.mk ne-port-forward-node NODE=node-name

# Operations
make -f make/ops/node-exporter.mk ne-restart
```

### pgAdmin

pgAdmin web-based PostgreSQL administration tool.

```bash
# Access & Credentials
make -f make/ops/pgadmin.mk pgadmin-get-password
make -f make/ops/pgadmin.mk pgadmin-port-forward

# Server Management
make -f make/ops/pgadmin.mk pgadmin-list-servers
make -f make/ops/pgadmin.mk pgadmin-test-connection HOST=postgresql.default.svc.cluster.local

# User Management
make -f make/ops/pgadmin.mk pgadmin-list-users

# Configuration
make -f make/ops/pgadmin.mk pgadmin-get-config
make -f make/ops/pgadmin.mk pgadmin-export-servers

# Backup & Restore
make -f make/ops/pgadmin.mk pgadmin-backup-metadata
make -f make/ops/pgadmin.mk pgadmin-restore-metadata FILE=<file>

# Monitoring
make -f make/ops/pgadmin.mk pgadmin-health
make -f make/ops/pgadmin.mk pgadmin-version
make -f make/ops/pgadmin.mk pgadmin-logs
make -f make/ops/pgadmin.mk pgadmin-shell

# Operations
make -f make/ops/pgadmin.mk pgadmin-restart
```

### phpMyAdmin

phpMyAdmin web-based MySQL/MariaDB administration tool.

```bash
# Access
make -f make/ops/phpmyadmin.mk phpmyadmin-port-forward

# Operations
make -f make/ops/phpmyadmin.mk phpmyadmin-logs
make -f make/ops/phpmyadmin.mk phpmyadmin-shell
make -f make/ops/phpmyadmin.mk phpmyadmin-restart
```

### PostgreSQL

PostgreSQL relational database with replication support.

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

### Prometheus

Prometheus monitoring system and time series database.

```bash
# Basic operations
make -f make/ops/prometheus.mk prom-logs
make -f make/ops/prometheus.mk prom-logs-all
make -f make/ops/prometheus.mk prom-shell
make -f make/ops/prometheus.mk prom-port-forward

# Health and status
make -f make/ops/prometheus.mk prom-ready
make -f make/ops/prometheus.mk prom-healthy
make -f make/ops/prometheus.mk prom-version
make -f make/ops/prometheus.mk prom-config
make -f make/ops/prometheus.mk prom-config-check

# Targets and service discovery
make -f make/ops/prometheus.mk prom-targets
make -f make/ops/prometheus.mk prom-targets-active
make -f make/ops/prometheus.mk prom-sd

# Metrics and queries
make -f make/ops/prometheus.mk prom-query QUERY='up'
make -f make/ops/prometheus.mk prom-query-range QUERY='up' START='-1h' END='now'
make -f make/ops/prometheus.mk prom-labels
make -f make/ops/prometheus.mk prom-label-values LABEL=job
make -f make/ops/prometheus.mk prom-series MATCH='{job="prometheus"}'

# TSDB and storage
make -f make/ops/prometheus.mk prom-tsdb-status
make -f make/ops/prometheus.mk prom-tsdb-snapshot
make -f make/ops/prometheus.mk prom-check-storage

# Configuration reload
make -f make/ops/prometheus.mk prom-reload

# Rules and alerts
make -f make/ops/prometheus.mk prom-rules
make -f make/ops/prometheus.mk prom-alerts

# Testing
make -f make/ops/prometheus.mk prom-test-query

# Scaling
make -f make/ops/prometheus.mk prom-scale REPLICAS=2
make -f make/ops/prometheus.mk prom-restart
```

### Promtail

Promtail log collection agent for Loki.

```bash
# Basic operations
make -f make/ops/promtail.mk promtail-logs
make -f make/ops/promtail.mk promtail-logs-node NODE=node-name
make -f make/ops/promtail.mk promtail-shell
make -f make/ops/promtail.mk promtail-shell-node NODE=node-name

# Health and status
make -f make/ops/promtail.mk promtail-status
make -f make/ops/promtail.mk promtail-ready
make -f make/ops/promtail.mk promtail-version
make -f make/ops/promtail.mk promtail-config
make -f make/ops/promtail.mk promtail-targets
make -f make/ops/promtail.mk promtail-metrics

# Node operations
make -f make/ops/promtail.mk promtail-list-nodes
make -f make/ops/promtail.mk promtail-pod-on-node NODE=node-name

# Troubleshooting
make -f make/ops/promtail.mk promtail-test-loki
make -f make/ops/promtail.mk promtail-check-positions
make -f make/ops/promtail.mk promtail-check-logs-path
make -f make/ops/promtail.mk promtail-debug

# Operations
make -f make/ops/promtail.mk promtail-restart
```

### Pushgateway

Prometheus Pushgateway for push-based metrics.

```bash
# Access
make -f make/ops/pushgateway.mk pushgateway-port-forward

# Metrics Management
make -f make/ops/pushgateway.mk pushgateway-metrics
make -f make/ops/pushgateway.mk pushgateway-delete-group JOB=batch_job

# Operations
make -f make/ops/pushgateway.mk pushgateway-health
make -f make/ops/pushgateway.mk pushgateway-logs
make -f make/ops/pushgateway.mk pushgateway-restart
```

### RabbitMQ

Message broker with management UI.

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

### Redis

In-memory data store.

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

### RustFS

High-performance S3-compatible object storage.

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

---

## Local Testing (Kind)

```bash
# Create local Kubernetes cluster
make kind-create

# Delete local cluster
make kind-delete

# Cluster name: sb-helm-charts (defined in KIND_CLUSTER_NAME)
# Config: kind-config.yaml
```

---

## Related Documentation

- **[CLAUDE.md](../CLAUDE.md)** - Main AI guidance and project overview
- **[CHARTS.md](CHARTS.md)** - Complete chart catalog with descriptions
- **[CHART_DEVELOPMENT_GUIDE.md](CHART_DEVELOPMENT_GUIDE.md)** - Chart development patterns
- **[CHART_VERSION_POLICY.md](CHART_VERSION_POLICY.md)** - Semantic versioning rules
- **[PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md)** - Production deployment checklist
- **[TESTING_GUIDE.md](TESTING_GUIDE.md)** - Comprehensive testing procedures
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions

---

**Last Updated:** 2025-11-23
**Total Charts:** 36 (20 Application + 16 Infrastructure)
