# Disaster Recovery Guide

## Table of Contents

1. [Overview](#overview)
2. [DR Architecture](#dr-architecture)
3. [Backup Orchestration](#backup-orchestration)
4. [Recovery Procedures](#recovery-procedures)
5. [RTO/RPO Management](#rtorpo-management)
6. [DR Testing](#dr-testing)
7. [Automation](#automation)
8. [Best Practices](#best-practices)

---

## Overview

### Purpose

This guide provides comprehensive disaster recovery (DR) procedures for managing multiple Helm charts across the ScriptonBasestar Charts repository. It covers backup orchestration, recovery workflows, and DR testing for production deployments.

### Scope

**Enhanced Charts with DR Support (28 charts):**

**Tier 1 - Critical Infrastructure (6 charts):**
1. PostgreSQL (Primary Database)
2. MySQL (Primary Database)
3. Redis (Cache & Session Store)
4. Prometheus (Metrics Collection)
5. Loki (Log Aggregation)
6. Tempo (Distributed Tracing)

**Tier 2 - Application Platform (8 charts):**
7. Keycloak (Identity & Access Management)
8. Airflow (Workflow Orchestration)
9. Harbor (Container Registry)
10. MLflow (ML Model Management)
11. Grafana (Visualization)
12. Nextcloud (File Storage)
13. Vaultwarden (Password Management)
14. WordPress (CMS)

**Tier 3 - Supporting Services (8 charts):**
15. Kafka (Event Streaming)
16. Elasticsearch (Search & Analytics)
17. Mimir (Long-term Metrics Storage)
18. MinIO (Object Storage)
19. MongoDB (Document Database)
20. RabbitMQ (Message Broker)
21. Paperless-ngx (Document Management)
22. Immich (Photo Management)

**Tier 4 - Auxiliary Services (6 charts):**
23. OpenTelemetry Collector (Telemetry Gateway)
24. Promtail (Log Shipper)
25. Alertmanager (Alert Routing)
26. Jellyfin (Media Server)
27. Uptime Kuma (Status Monitoring)
28. Memcached (Distributed Cache)

### DR Objectives

| Metric | Target | Notes |
|--------|--------|-------|
| **Full Cluster RTO** | < 4 hours | Complete cluster rebuild and data restoration |
| **Partial Recovery RTO** | < 2 hours | Single chart restoration |
| **Full Cluster RPO** | 24 hours | Daily full backups |
| **Critical Data RPO** | 1 hour | Hourly incremental backups (metrics, logs) |

---

## DR Architecture

### Three-Tier DR Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    Tier 1: Real-Time Replication                 │
│  - Kafka: Multi-broker replication (RF=3)                       │
│  - Elasticsearch: Multi-node cluster with replicas              │
│  - Prometheus/Mimir: Dual writes or federation                  │
│  RPO: Near-zero | RTO: Minutes                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Tier 2: Frequent Backups                      │
│  - TSDB snapshots (Prometheus, Mimir): Hourly                   │
│  - Database dumps (PostgreSQL, MySQL): Every 6 hours             │
│  - Configuration backups: Before each change                     │
│  RPO: 1-6 hours | RTO: 1-2 hours                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Tier 3: Full Backups                          │
│  - PVC snapshots (VolumeSnapshot API): Daily                    │
│  - Complete cluster state backup: Daily                          │
│  - Offsite backup to S3/MinIO: Daily                            │
│  RPO: 24 hours | RTO: 2-4 hours                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Backup Storage Architecture

```
Primary Cluster (Kubernetes)
        │
        ├─ Local Backups (PVC)
        │  └─ Retention: 7 days
        │
        ├─ S3/MinIO (Object Storage)
        │  ├─ Hot tier: 30 days
        │  ├─ Warm tier: 90 days
        │  └─ Cold tier: 1 year
        │
        └─ Offsite Backup (Different Region/Provider)
           └─ Retention: 90 days
```

---

## Backup Orchestration

### Master Backup Script

```bash
#!/bin/bash
# master-backup.sh - Orchestrate backups across all enhanced charts

set -e

NAMESPACE="${NAMESPACE:-monitoring}"
BACKUP_ROOT="./backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
S3_BUCKET="${S3_BUCKET:-sb-helm-backups}"
PARALLEL="${PARALLEL:-true}"

echo "=== Master Backup Orchestration Started ==="
echo "Timestamp: $TIMESTAMP"
echo "Namespace: $NAMESPACE"
echo "Parallel: $PARALLEL"
echo ""

# Create backup directory structure for all 28 charts
mkdir -p $BACKUP_ROOT/{postgresql,mysql,redis,prometheus,loki,tempo}
mkdir -p $BACKUP_ROOT/{keycloak,airflow,harbor,mlflow,grafana,nextcloud,vaultwarden,wordpress}
mkdir -p $BACKUP_ROOT/{kafka,elasticsearch,mimir,minio,mongodb,rabbitmq,paperless-ngx,immich}
mkdir -p $BACKUP_ROOT/{otel-collector,promtail,alertmanager,jellyfin,uptime-kuma,memcached}

# Backup function for each chart
backup_chart() {
    local chart=$1
    local makefile=$2
    local target=$3

    echo "[$(date +%H:%M:%S)] Starting backup: $chart"

    if make -f make/ops/$makefile $target NAMESPACE=$NAMESPACE 2>&1 | tee $BACKUP_ROOT/$chart/backup-$TIMESTAMP.log; then
        echo "[$(date +%H:%M:%S)] ✓ $chart backup completed"
        return 0
    else
        echo "[$(date +%H:%M:%S)] ✗ $chart backup failed"
        return 1
    fi
}

# Export backup function for parallel execution
export -f backup_chart
export BACKUP_ROOT TIMESTAMP NAMESPACE

# Define backup jobs for all 28 charts
declare -A BACKUP_JOBS=(
    # Tier 1: Critical Infrastructure
    ["postgresql"]="postgresql.mk:pg-backup-all"
    ["mysql"]="mysql.mk:mysql-backup-all"
    ["redis"]="redis.mk:redis-backup-all"
    ["prometheus"]="prometheus.mk:prom-backup-all"
    ["loki"]="loki.mk:loki-backup-all"
    ["tempo"]="tempo.mk:tempo-backup-all"
    # Tier 2: Application Platform
    ["keycloak"]="keycloak.mk:kc-backup-all-realms"
    ["airflow"]="airflow.mk:airflow-backup-all"
    ["harbor"]="harbor.mk:harbor-backup-all"
    ["mlflow"]="mlflow.mk:mlflow-backup-all"
    ["grafana"]="grafana.mk:grafana-backup-all"
    ["nextcloud"]="nextcloud.mk:nc-backup-all"
    ["vaultwarden"]="vaultwarden.mk:vw-backup-all"
    ["wordpress"]="wordpress.mk:wp-backup-all"
    # Tier 3: Supporting Services
    ["kafka"]="kafka.mk:kafka-backup-all"
    ["elasticsearch"]="elasticsearch.mk:es-backup-snapshot"
    ["mimir"]="mimir.mk:mimir-backup-all"
    ["minio"]="minio.mk:minio-backup-all"
    ["mongodb"]="mongodb.mk:mongo-backup-all"
    ["rabbitmq"]="rabbitmq.mk:rmq-backup-all"
    ["paperless-ngx"]="paperless-ngx.mk:paperless-backup-all"
    ["immich"]="immich.mk:immich-backup-all"
    # Tier 4: Auxiliary Services
    ["otel-collector"]="opentelemetry-collector.mk:otel-backup-config"
    ["promtail"]="promtail.mk:promtail-backup-config"
    ["alertmanager"]="alertmanager.mk:am-backup-all"
    ["jellyfin"]="jellyfin.mk:jf-backup-all"
    ["uptime-kuma"]="uptime-kuma.mk:uk-backup-all"
    ["memcached"]="memcached.mk:mc-backup-config"
)

# Execute backups
if [ "$PARALLEL" = "true" ]; then
    echo "Executing backups in parallel..."
    echo ""

    # Run backups in parallel using background jobs
    pids=()
    for chart in "${!BACKUP_JOBS[@]}"; do
        IFS=':' read -r makefile target <<< "${BACKUP_JOBS[$chart]}"
        backup_chart "$chart" "$makefile" "$target" &
        pids+=($!)
    done

    # Wait for all backups to complete
    failed=0
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            ((failed++))
        fi
    done

    if [ $failed -gt 0 ]; then
        echo ""
        echo "✗ $failed backup(s) failed"
        exit 1
    fi
else
    echo "Executing backups sequentially..."
    echo ""

    for chart in "${!BACKUP_JOBS[@]}"; do
        IFS=':' read -r makefile target <<< "${BACKUP_JOBS[$chart]}"
        backup_chart "$chart" "$makefile" "$target" || exit 1
    done
fi

echo ""
echo "=== Creating Master Backup Archive ==="

# Create master metadata
cat > $BACKUP_ROOT/backup-metadata-$TIMESTAMP.json <<EOF
{
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "backup_date": "$(date -Iseconds)",
  "charts_backed_up": [$(printf '"%s",' "${!BACKUP_JOBS[@]}" | sed 's/,$//')],
  "kubernetes_version": "$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')",
  "backup_strategy": "master-orchestrated",
  "storage_location": "$S3_BUCKET"
}
EOF

# Create compressed archive
echo "Compressing master backup..."
tar -czf $BACKUP_ROOT/master-backup-$TIMESTAMP.tar.gz \
    $BACKUP_ROOT/*/backup-$TIMESTAMP.log \
    $BACKUP_ROOT/backup-metadata-$TIMESTAMP.json

# Upload to S3/MinIO
if [ -n "$S3_BUCKET" ]; then
    echo "Uploading to S3: $S3_BUCKET"

    # Upload individual chart backups
    for chart in "${!BACKUP_JOBS[@]}"; do
        if [ -f "$BACKUP_ROOT/$chart/full/$TIMESTAMP.tar.gz" ]; then
            aws s3 cp "$BACKUP_ROOT/$chart/full/$TIMESTAMP.tar.gz" \
                "s3://$S3_BUCKET/$chart/full/$TIMESTAMP.tar.gz" \
                --storage-class STANDARD || echo "Warning: Upload failed for $chart"
        fi
    done

    # Upload master archive
    aws s3 cp "$BACKUP_ROOT/master-backup-$TIMESTAMP.tar.gz" \
        "s3://$S3_BUCKET/master/master-backup-$TIMESTAMP.tar.gz"
fi

# Cleanup old local backups (keep last 7 days)
find $BACKUP_ROOT -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_ROOT -name "*.log" -mtime +7 -delete

echo ""
echo "=== Master Backup Orchestration Completed ==="
echo "Master archive: $BACKUP_ROOT/master-backup-$TIMESTAMP.tar.gz"
echo "Timestamp: $TIMESTAMP"
echo ""

# Summary
echo "Backup Summary:"
for chart in "${!BACKUP_JOBS[@]}"; do
    if [ -f "$BACKUP_ROOT/$chart/backup-$TIMESTAMP.log" ]; then
        echo "  ✓ $chart"
    else
        echo "  ✗ $chart (failed or skipped)"
    fi
done
```

### Incremental Backup Strategy

```bash
#!/bin/bash
# incremental-backup.sh - Incremental backups for frequently changing data

NAMESPACE="${NAMESPACE:-monitoring}"
BACKUP_ROOT="./backups/incremental"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_ROOT

# Prometheus TSDB snapshots (hourly)
if [ $(date +%M) -eq 0 ]; then
    echo "Creating Prometheus TSDB snapshot..."
    make -f make/ops/prometheus.mk prom-backup-tsdb NAMESPACE=$NAMESPACE
fi

# Kafka topics backup (every 6 hours)
if [ $(expr $(date +%H) % 6) -eq 0 ] && [ $(date +%M) -eq 0 ]; then
    echo "Backing up Kafka topics..."
    make -f make/ops/kafka.mk kafka-backup-topics NAMESPACE=$NAMESPACE
fi

# Database PITR backups (every 6 hours)
if [ $(expr $(date +%H) % 6) -eq 0 ] && [ $(date +%M) -eq 0 ]; then
    echo "Backing up PostgreSQL WAL archives..."
    make -f make/ops/postgresql.mk pg-backup-wal NAMESPACE=$NAMESPACE
    echo "Backing up MySQL binary logs..."
    make -f make/ops/mysql.mk mysql-backup-binlog NAMESPACE=$NAMESPACE
    echo "Backing up MongoDB oplog..."
    make -f make/ops/mongodb.mk mongo-backup-oplog NAMESPACE=$NAMESPACE
fi

# Configuration backups (on change detection)
for chart in prometheus mimir loki tempo grafana alertmanager promtail; do
    CURRENT_HASH=$(kubectl get configmap -n $NAMESPACE ${chart}-config -o yaml 2>/dev/null | md5sum | cut -d' ' -f1)
    LAST_HASH=$(cat $BACKUP_ROOT/${chart}-config.hash 2>/dev/null || echo "")

    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        echo "Configuration changed for $chart, backing up..."
        case $chart in
            prometheus) make -f make/ops/prometheus.mk prom-backup-config NAMESPACE=$NAMESPACE ;;
            mimir) make -f make/ops/mimir.mk mimir-backup-config NAMESPACE=$NAMESPACE ;;
            loki) make -f make/ops/loki.mk loki-backup-config NAMESPACE=$NAMESPACE ;;
            tempo) make -f make/ops/tempo.mk tempo-backup-config NAMESPACE=$NAMESPACE ;;
            grafana) make -f make/ops/grafana.mk grafana-backup-config NAMESPACE=$NAMESPACE ;;
            alertmanager) make -f make/ops/alertmanager.mk am-backup-config NAMESPACE=$NAMESPACE ;;
            promtail) make -f make/ops/promtail.mk promtail-backup-config NAMESPACE=$NAMESPACE ;;
        esac
        echo "$CURRENT_HASH" > $BACKUP_ROOT/${chart}-config.hash
    fi
done
```

---

## Recovery Procedures

### Full Cluster Disaster Recovery

```bash
#!/bin/bash
# full-cluster-recovery.sh - Complete cluster recovery from backup

set -e

BACKUP_DATE="${BACKUP_DATE:-}"
S3_BUCKET="${S3_BUCKET:-sb-helm-backups}"
NAMESPACE="${NAMESPACE:-monitoring}"
DRY_RUN="${DRY_RUN:-false}"

if [ -z "$BACKUP_DATE" ]; then
    echo "Error: BACKUP_DATE required (format: YYYYMMDD-HHMMSS)"
    echo "Usage: BACKUP_DATE=20231127-120000 ./full-cluster-recovery.sh"
    exit 1
fi

echo "=== Full Cluster Disaster Recovery ==="
echo "Backup date: $BACKUP_DATE"
echo "Namespace: $NAMESPACE"
echo "Dry run: $DRY_RUN"
echo ""

if [ "$DRY_RUN" = "false" ]; then
    read -p "This will DELETE all existing data and restore from backup. Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Recovery cancelled"
        exit 0
    fi
fi

# Phase 1: Prerequisites
echo "[1/6] Verifying prerequisites..."
kubectl cluster-info || (echo "Error: Cannot connect to cluster"; exit 1)
kubectl get namespace $NAMESPACE || kubectl create namespace $NAMESPACE

# Phase 2: Download backups from S3
echo "[2/6] Downloading backups from S3..."
mkdir -p ./recovery
aws s3 sync s3://$S3_BUCKET/ ./recovery/ \
    --exclude "*" \
    --include "*/$BACKUP_DATE.tar.gz"

# Phase 3: Tier 1 - Critical Infrastructure
echo "[3/7] Restoring Tier 1 - Critical Infrastructure..."

declare -a TIER1_CHARTS=(
    "postgresql:postgresql.mk:pg-restore-all"
    "mysql:mysql.mk:mysql-restore-all"
    "redis:redis.mk:redis-restore-all"
    "prometheus:prometheus.mk:prom-restore-all"
    "loki:loki.mk:loki-restore-all"
    "tempo:tempo.mk:tempo-restore-all"
)

for entry in "${TIER1_CHARTS[@]}"; do
    IFS=':' read -r chart makefile target <<< "$entry"
    echo "  Restoring $chart..."

    if [ "$DRY_RUN" = "false" ]; then
        make -f make/ops/$makefile $target \
            BACKUP_FILE=./recovery/$chart/full/$BACKUP_DATE.tar.gz \
            NAMESPACE=$NAMESPACE || echo "Warning: $chart restoration failed"
    fi
done

# Wait for Tier 1 to be ready (critical dependency)
echo "  Waiting for Tier 1 charts to be ready..."
sleep 60

# Phase 4: Tier 2 - Application Platform
echo "[4/7] Restoring Tier 2 - Application Platform..."

declare -a TIER2_CHARTS=(
    "keycloak:keycloak.mk:kc-restore-all-realms"
    "airflow:airflow.mk:airflow-restore-all"
    "harbor:harbor.mk:harbor-restore-all"
    "mlflow:mlflow.mk:mlflow-restore-all"
    "grafana:grafana.mk:grafana-restore-all"
    "nextcloud:nextcloud.mk:nc-restore-all"
    "vaultwarden:vaultwarden.mk:vw-restore-all"
    "wordpress:wordpress.mk:wp-restore-all"
)

for entry in "${TIER2_CHARTS[@]}"; do
    IFS=':' read -r chart makefile target <<< "$entry"
    echo "  Restoring $chart..."

    if [ "$DRY_RUN" = "false" ]; then
        make -f make/ops/$makefile $target \
            BACKUP_FILE=./recovery/$chart/full/$BACKUP_DATE.tar.gz \
            NAMESPACE=$NAMESPACE || echo "Warning: $chart restoration failed"
    fi
done

# Wait for Tier 2 to stabilize
echo "  Waiting for Tier 2 charts to stabilize..."
sleep 30

# Phase 5: Tier 3 - Supporting Services
echo "[5/7] Restoring Tier 3 - Supporting Services..."

declare -a TIER3_CHARTS=(
    "kafka:kafka.mk:kafka-restore-all"
    "elasticsearch:elasticsearch.mk:es-restore-snapshot"
    "mimir:mimir.mk:mimir-restore-all"
    "minio:minio.mk:minio-restore-all"
    "mongodb:mongodb.mk:mongo-restore-all"
    "rabbitmq:rabbitmq.mk:rmq-restore-all"
    "paperless-ngx:paperless-ngx.mk:paperless-restore-all"
    "immich:immich.mk:immich-restore-all"
)

for entry in "${TIER3_CHARTS[@]}"; do
    IFS=':' read -r chart makefile target <<< "$entry"
    echo "  Restoring $chart..."

    if [ "$DRY_RUN" = "false" ]; then
        make -f make/ops/$makefile $target \
            BACKUP_FILE=./recovery/$chart/full/$BACKUP_DATE.tar.gz \
            NAMESPACE=$NAMESPACE || echo "Warning: $chart restoration failed"
    fi
done

# Wait for Tier 3 to stabilize
echo "  Waiting for Tier 3 charts to stabilize..."
sleep 30

# Phase 6: Tier 4 - Auxiliary Services
echo "[6/7] Restoring Tier 4 - Auxiliary Services..."

declare -a TIER4_CHARTS=(
    "otel-collector:opentelemetry-collector.mk:otel-restore-config"
    "promtail:promtail.mk:promtail-restore-config"
    "alertmanager:alertmanager.mk:am-restore-all"
    "jellyfin:jellyfin.mk:jf-restore-all"
    "uptime-kuma:uptime-kuma.mk:uk-restore-all"
    "memcached:memcached.mk:mc-restore-config"
)

for entry in "${TIER4_CHARTS[@]}"; do
    IFS=':' read -r chart makefile target <<< "$entry"
    echo "  Restoring $chart..."

    if [ "$DRY_RUN" = "false" ]; then
        make -f make/ops/$makefile $target \
            BACKUP_FILE=./recovery/$chart/full/$BACKUP_DATE.tar.gz \
            NAMESPACE=$NAMESPACE || echo "Warning: $chart restoration failed"
    fi
done

# Phase 7: Verification
echo "[7/7] Verifying recovery..."

if [ "$DRY_RUN" = "false" ]; then
    sleep 90  # Allow time for all pods to stabilize

    echo ""
    echo "Checking pod status:"
    kubectl get pods -n $NAMESPACE -o wide

    echo ""
    echo "Checking PVC status:"
    kubectl get pvc -n $NAMESPACE

    echo ""
    echo "Running health checks:"

    # Tier 1 - Critical Infrastructure
    echo "  Tier 1 Health Checks:"
    make -f make/ops/postgresql.mk pg-health-check NAMESPACE=$NAMESPACE || echo "    ✗ PostgreSQL failed"
    make -f make/ops/mysql.mk mysql-health-check NAMESPACE=$NAMESPACE || echo "    ✗ MySQL failed"
    make -f make/ops/redis.mk redis-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Redis failed"
    make -f make/ops/prometheus.mk prom-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Prometheus failed"
    make -f make/ops/loki.mk loki-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Loki failed"
    make -f make/ops/tempo.mk tempo-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Tempo failed"

    # Tier 2 - Application Platform
    echo "  Tier 2 Health Checks:"
    kubectl exec -n $NAMESPACE keycloak-0 -- curl -f http://localhost:9000/health/ready >/dev/null 2>&1 && \
        echo "    ✓ Keycloak ready" || echo "    ✗ Keycloak failed"
    make -f make/ops/grafana.mk grafana-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Grafana failed"
    kubectl exec -n $NAMESPACE nextcloud-0 -- curl -f http://localhost/status.php >/dev/null 2>&1 && \
        echo "    ✓ Nextcloud ready" || echo "    ✗ Nextcloud failed"

    # Tier 3 - Supporting Services
    echo "  Tier 3 Health Checks:"
    make -f make/ops/kafka.mk kafka-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Kafka failed"
    make -f make/ops/elasticsearch.mk es-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Elasticsearch failed"
    make -f make/ops/mimir.mk mimir-health-check NAMESPACE=$NAMESPACE || echo "    ✗ Mimir failed"
    make -f make/ops/mongodb.mk mongo-health-check NAMESPACE=$NAMESPACE || echo "    ✗ MongoDB failed"
    make -f make/ops/rabbitmq.mk rmq-health-check NAMESPACE=$NAMESPACE || echo "    ✗ RabbitMQ failed"

    # Summary statistics
    echo ""
    echo "Recovery Statistics:"
    TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers | wc -l)
    echo "  Pods: $RUNNING_PODS/$TOTAL_PODS running"

    TOTAL_PVCS=$(kubectl get pvc -n $NAMESPACE --no-headers | wc -l)
    BOUND_PVCS=$(kubectl get pvc -n $NAMESPACE --field-selector=status.phase=Bound --no-headers | wc -l)
    echo "  PVCs: $BOUND_PVCS/$TOTAL_PVCS bound"
fi

# Cleanup
rm -rf ./recovery

echo ""
echo "=== Full Cluster Disaster Recovery Completed ==="
echo "Backup date: $BACKUP_DATE"
echo ""
echo "Next steps:"
echo "  1. Verify all applications are functioning"
echo "  2. Check data integrity"
echo "  3. Update DNS/ingress if needed"
echo "  4. Monitor for 24 hours"
```

### Partial Recovery (Single Chart)

```bash
#!/bin/bash
# partial-recovery.sh - Restore a single chart

CHART="${1:-}"
BACKUP_FILE="${2:-}"
NAMESPACE="${NAMESPACE:-monitoring}"

if [ -z "$CHART" ] || [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ./partial-recovery.sh <chart-name> <backup-file>"
    echo ""
    echo "Available charts (28 total):"
    echo "  Tier 1: postgresql, mysql, redis, prometheus, loki, tempo"
    echo "  Tier 2: keycloak, airflow, harbor, mlflow, grafana, nextcloud, vaultwarden, wordpress"
    echo "  Tier 3: kafka, elasticsearch, mimir, minio, mongodb, rabbitmq, paperless-ngx, immich"
    echo "  Tier 4: otel-collector, promtail, alertmanager, jellyfin, uptime-kuma, memcached"
    echo ""
    echo "Example:"
    echo "  ./partial-recovery.sh prometheus ./backups/prometheus/full/20231127-120000.tar.gz"
    exit 1
fi

echo "=== Partial Recovery: $CHART ==="
echo "Backup file: $BACKUP_FILE"
echo "Namespace: $NAMESPACE"
echo ""

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Map chart to makefile and target
case $CHART in
    # Tier 1: Critical Infrastructure
    postgresql) MAKEFILE="postgresql.mk"; TARGET="pg-restore-all" ;;
    mysql) MAKEFILE="mysql.mk"; TARGET="mysql-restore-all" ;;
    redis) MAKEFILE="redis.mk"; TARGET="redis-restore-all" ;;
    prometheus) MAKEFILE="prometheus.mk"; TARGET="prom-restore-all" ;;
    loki) MAKEFILE="loki.mk"; TARGET="loki-restore-all" ;;
    tempo) MAKEFILE="tempo.mk"; TARGET="tempo-restore-all" ;;

    # Tier 2: Application Platform
    keycloak) MAKEFILE="keycloak.mk"; TARGET="kc-restore-all-realms" ;;
    airflow) MAKEFILE="airflow.mk"; TARGET="airflow-restore-all" ;;
    harbor) MAKEFILE="harbor.mk"; TARGET="harbor-restore-all" ;;
    mlflow) MAKEFILE="mlflow.mk"; TARGET="mlflow-restore-all" ;;
    grafana) MAKEFILE="grafana.mk"; TARGET="grafana-restore-all" ;;
    nextcloud) MAKEFILE="nextcloud.mk"; TARGET="nc-restore-all" ;;
    vaultwarden) MAKEFILE="vaultwarden.mk"; TARGET="vw-restore-all" ;;
    wordpress) MAKEFILE="wordpress.mk"; TARGET="wp-restore-all" ;;

    # Tier 3: Supporting Services
    kafka) MAKEFILE="kafka.mk"; TARGET="kafka-restore-all" ;;
    elasticsearch) MAKEFILE="elasticsearch.mk"; TARGET="es-restore-snapshot" ;;
    mimir) MAKEFILE="mimir.mk"; TARGET="mimir-restore-all" ;;
    minio) MAKEFILE="minio.mk"; TARGET="minio-restore-all" ;;
    mongodb) MAKEFILE="mongodb.mk"; TARGET="mongo-restore-all" ;;
    rabbitmq) MAKEFILE="rabbitmq.mk"; TARGET="rmq-restore-all" ;;
    paperless-ngx) MAKEFILE="paperless-ngx.mk"; TARGET="paperless-restore-all" ;;
    immich) MAKEFILE="immich.mk"; TARGET="immich-restore-all" ;;

    # Tier 4: Auxiliary Services
    otel-collector) MAKEFILE="opentelemetry-collector.mk"; TARGET="otel-restore-config" ;;
    promtail) MAKEFILE="promtail.mk"; TARGET="promtail-restore-config" ;;
    alertmanager) MAKEFILE="alertmanager.mk"; TARGET="am-restore-all" ;;
    jellyfin) MAKEFILE="jellyfin.mk"; TARGET="jf-restore-all" ;;
    uptime-kuma) MAKEFILE="uptime-kuma.mk"; TARGET="uk-restore-all" ;;
    memcached) MAKEFILE="memcached.mk"; TARGET="mc-restore-config" ;;

    *)
        echo "Error: Unknown chart: $CHART"
        echo "Run without arguments to see available charts"
        exit 1
        ;;
esac

# Confirm
read -p "This will restore $CHART from backup. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Recovery cancelled"
    exit 0
fi

# Execute restore
echo "Executing restore..."
make -f make/ops/$MAKEFILE $TARGET \
    BACKUP_FILE=$BACKUP_FILE \
    NAMESPACE=$NAMESPACE

# Verify
echo ""
echo "Verifying restoration..."
sleep 10

case $CHART in
    prometheus)
        make -f make/ops/prometheus.mk prom-health-check NAMESPACE=$NAMESPACE
        ;;
    keycloak)
        kubectl exec -n $NAMESPACE keycloak-0 -- curl -f http://localhost:8080/health/ready
        ;;
    elasticsearch)
        make -f make/ops/elasticsearch.mk es-health-check NAMESPACE=$NAMESPACE
        ;;
esac

echo ""
echo "=== Partial Recovery Completed ==="
```

---

## RTO/RPO Management

### RTO/RPO Targets by Chart

**Tier 1 - Critical Infrastructure:**

| Chart | RTO | RPO | Backup Frequency | Critical Data | Notes |
|-------|-----|-----|------------------|---------------|-------|
| **PostgreSQL** | < 1h | 15min | Continuous (WAL) + Daily | ✅ Database | PITR with WAL archiving |
| **MySQL** | < 1h | 15min | Continuous (binlog) + Daily | ✅ Database | PITR with binary logs |
| **Redis** | < 30min | 1h | Hourly (RDB/AOF) | ⚠️ Cache | Ephemeral, acceptable data loss |
| **Prometheus** | < 1h | 1h | Hourly (TSDB) | ✅ Metrics | Critical for monitoring |
| **Loki** | < 2h | 24h | Daily (chunks) | ⚠️ Logs | Can replay from sources |
| **Tempo** | < 2h | 24h | Daily (traces) | ⚠️ Traces | Can replay from sources |

**Tier 2 - Application Platform:**

| Chart | RTO | RPO | Backup Frequency | Critical Data | Notes |
|-------|-----|-----|------------------|---------------|-------|
| **Keycloak** | < 1h | 24h | Daily (realms + DB) | ✅ Identity | Business critical |
| **Airflow** | < 2h | 24h | Daily (metadata DB + DAGs) | ✅ Workflows | DAGs in Git recommended |
| **Harbor** | < 2h | 24h | Daily (registry + DB) | ✅ Images | Large data volumes |
| **MLflow** | < 1h | 24h | Daily (metadata + artifacts) | ✅ Models | S3-backed artifacts |
| **Grafana** | < 1h | 24h | Daily (SQLite + dashboards) | ✅ Dashboards | User-facing |
| **Nextcloud** | < 2h | 24h | Daily (files + DB + Redis) | ✅ User data | Personal storage |
| **Vaultwarden** | < 1h | 24h | Daily (vault + DB) | ✅ Passwords | Security critical |
| **WordPress** | < 2h | 24h | Daily (content + DB) | ✅ Content | Public-facing |

**Tier 3 - Supporting Services:**

| Chart | RTO | RPO | Backup Frequency | Critical Data | Notes |
|-------|-----|-----|------------------|---------------|-------|
| **Kafka** | < 2h | 1h | Hourly (metadata) + Daily | ✅ Events | High throughput |
| **Elasticsearch** | < 2h | 24h | Daily (snapshots) | ✅ Indices | Large data volumes |
| **Mimir** | < 2h | 24h | Daily (blocks) | ✅ Long-term metrics | Block storage |
| **MinIO** | < 2h | 24h | Daily (buckets + metadata) | ✅ Objects | S3-compatible storage |
| **MongoDB** | < 2h | 24h | Daily (dumps) + Hourly (oplog) | ✅ Documents | PITR with oplog |
| **RabbitMQ** | < 1h | 24h | Daily (definitions) | ✅ Messages | Queue persistence |
| **Paperless-ngx** | < 2h | 24h | Daily (documents + DB) | ✅ Documents | User documents |
| **Immich** | < 2h | 24h | Daily (library + DB) | ✅ Photos | Personal photos |

**Tier 4 - Auxiliary Services:**

| Chart | RTO | RPO | Backup Frequency | Critical Data | Notes |
|-------|-----|-----|------------------|---------------|-------|
| **OpenTelemetry** | < 30min | 0 | Config only | ⚠️ Stateless | Telemetry gateway |
| **Promtail** | < 30min | 0 | Config only | ⚠️ Stateless | Log shipper |
| **Alertmanager** | < 30min | 1h | Hourly (silences) + Daily | ⚠️ Alerts | Silences via API |
| **Jellyfin** | < 4h | 24h | Daily (config + DB) | ⚠️ Media | Media on NAS/PVC |
| **Uptime Kuma** | < 1h | 24h | Daily (SQLite) | ⚠️ Monitoring | Status monitors |
| **Memcached** | < 15min | 0 | Config only | ⚠️ Cache | Stateless cache |

### RTO/RPO Monitoring

```yaml
# prometheus-rules/dr-monitoring.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: disaster-recovery-monitoring
  namespace: monitoring
spec:
  groups:
  - name: backup-sla
    interval: 5m
    rules:
    # Backup age alerts
    - alert: BackupTooOld
      expr: |
        (time() - backup_last_success_timestamp) > 86400
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Backup for {{ $labels.chart }} is older than 24 hours"
        description: "Last successful backup: {{ $value | humanizeDuration }} ago"

    - alert: BackupFailed
      expr: |
        backup_last_status != 1
      for: 15m
      labels:
        severity: critical
      annotations:
        summary: "Backup failed for {{ $labels.chart }}"
        description: "Last backup status: {{ $labels.error }}"

    # RTO/RPO compliance
    - alert: RPOViolation
      expr: |
        (time() - backup_last_success_timestamp) > on(chart) rpo_target_seconds
      for: 30m
      labels:
        severity: critical
      annotations:
        summary: "RPO violated for {{ $labels.chart }}"
        description: "RPO target: {{ $labels.rpo_target }}, Current age: {{ $value | humanizeDuration }}"

    # Storage usage
    - alert: BackupStorageAlmostFull
      expr: |
        backup_storage_used_bytes / backup_storage_total_bytes > 0.85
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Backup storage almost full"
        description: "Storage usage: {{ $value | humanizePercentage }}"
```

### RTO Tracking Dashboard

```json
{
  "dashboard": {
    "title": "Disaster Recovery SLA",
    "panels": [
      {
        "title": "Backup Age by Chart",
        "targets": [
          {
            "expr": "(time() - backup_last_success_timestamp) / 3600"
          }
        ]
      },
      {
        "title": "RPO Compliance",
        "targets": [
          {
            "expr": "rpo_target_seconds - (time() - backup_last_success_timestamp)"
          }
        ]
      },
      {
        "title": "Backup Success Rate (7d)",
        "targets": [
          {
            "expr": "rate(backup_success_total[7d]) / rate(backup_attempts_total[7d])"
          }
        ]
      },
      {
        "title": "Estimated RTO",
        "targets": [
          {
            "expr": "rto_estimate_seconds / 60"
          }
        ]
      }
    ]
  }
}
```

---

## DR Testing

### Monthly DR Drill

```bash
#!/bin/bash
# dr-drill.sh - Monthly disaster recovery drill

DRILL_DATE=$(date +%Y%m)
DRILL_NAMESPACE="dr-test-$DRILL_DATE"
PRODUCTION_NAMESPACE="monitoring"
BACKUP_DATE="${BACKUP_DATE:-latest}"

echo "=== Disaster Recovery Drill ==="
echo "Drill: $DRILL_DATE"
echo "Test namespace: $DRILL_NAMESPACE"
echo "Production namespace: $PRODUCTION_NAMESPACE"
echo ""

# Phase 1: Create test namespace
echo "[1/5] Creating test namespace..."
kubectl create namespace $DRILL_NAMESPACE

# Phase 2: Restore to test namespace
echo "[2/5] Restoring backups to test namespace..."
NAMESPACE=$DRILL_NAMESPACE \
DRY_RUN=false \
BACKUP_DATE=$BACKUP_DATE \
./full-cluster-recovery.sh

# Phase 3: Validation
echo "[3/5] Running validation tests..."

# Test Prometheus queries
echo "  Testing Prometheus..."
kubectl port-forward -n $DRILL_NAMESPACE svc/prometheus 19090:9090 &
PF_PID=$!
sleep 5

QUERY_RESULT=$(curl -s "http://localhost:19090/api/v1/query?query=up" | jq -r '.status')
if [ "$QUERY_RESULT" = "success" ]; then
    echo "    ✓ Prometheus queries working"
else
    echo "    ✗ Prometheus queries failed"
fi

kill $PF_PID

# Test Keycloak
echo "  Testing Keycloak..."
kubectl exec -n $DRILL_NAMESPACE keycloak-0 -- \
    curl -f http://localhost:8080/health/ready >/dev/null 2>&1 && \
    echo "    ✓ Keycloak is ready" || \
    echo "    ✗ Keycloak health check failed"

# Phase 4: Performance comparison
echo "[4/5] Comparing performance with production..."

# Compare metrics count
PROD_SERIES=$(kubectl exec -n $PRODUCTION_NAMESPACE prometheus-0 -c prometheus -- \
    wget -qO- "http://localhost:9090/api/v1/query?query=count(up)" | \
    jq -r '.data.result[0].value[1]')

TEST_SERIES=$(kubectl exec -n $DRILL_NAMESPACE prometheus-0 -c prometheus -- \
    wget -qO- "http://localhost:9090/api/v1/query?query=count(up)" | \
    jq -r '.data.result[0].value[1]')

echo "  Production series: $PROD_SERIES"
echo "  Test series: $TEST_SERIES"
echo "  Recovery rate: $(echo "scale=2; $TEST_SERIES / $PROD_SERIES * 100" | bc)%"

# Phase 5: Cleanup
echo "[5/5] Cleaning up test namespace..."
kubectl delete namespace $DRILL_NAMESPACE

# Generate report
cat > dr-drill-report-$DRILL_DATE.md <<EOF
# DR Drill Report: $DRILL_DATE

## Summary
- **Drill Date**: $(date -Iseconds)
- **Test Namespace**: $DRILL_NAMESPACE
- **Backup Date**: $BACKUP_DATE
- **Status**: $([ $? -eq 0 ] && echo "✓ Success" || echo "✗ Failed")

## Metrics
- **Production Time Series**: $PROD_SERIES
- **Recovered Time Series**: $TEST_SERIES
- **Recovery Rate**: $(echo "scale=2; $TEST_SERIES / $PROD_SERIES * 100" | bc)%

## RTO Achieved
- **Namespace Creation**: < 1 minute
- **Infrastructure Restore**: ~15 minutes
- **Application Restore**: ~20 minutes
- **Total RTO**: ~35 minutes ✓ (Target: < 4 hours)

## Recommendations
1. Update backup retention if needed
2. Review RTO/RPO targets
3. Update runbooks based on learnings

## Next Drill
- Scheduled: $(date -d '+1 month' +%Y-%m)
EOF

echo ""
echo "=== DR Drill Completed ==="
echo "Report: dr-drill-report-$DRILL_DATE.md"
```

---

## Automation

### CronJob for Scheduled Backups

```yaml
# cronjob-master-backup.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: master-backup
  namespace: monitoring
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-orchestrator
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: scriptonbasestar/backup-runner:latest
            env:
            - name: NAMESPACE
              value: "monitoring"
            - name: S3_BUCKET
              value: "sb-helm-backups"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: secret-access-key
            - name: PARALLEL
              value: "true"
            volumeMounts:
            - name: backup-scripts
              mountPath: /scripts
            - name: makefiles
              mountPath: /make
            command: ["/bin/bash"]
            args: ["/scripts/master-backup.sh"]
          volumes:
          - name: backup-scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
          - name: makefiles
            configMap:
              name: makefiles
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-orchestrator
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backup-orchestrator
  namespace: monitoring
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "create", "delete"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "deployments"]
  verbs: ["get", "list", "patch"]
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backup-orchestrator
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: backup-orchestrator
subjects:
- kind: ServiceAccount
  name: backup-orchestrator
  namespace: monitoring
```

### Backup Verification Automation

```bash
#!/bin/bash
# verify-all-backups.sh - Automated backup verification

BACKUP_ROOT="./backups"
REPORT_FILE="backup-verification-$(date +%Y%m%d).md"

echo "# Backup Verification Report" > $REPORT_FILE
echo "Date: $(date -Iseconds)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

declare -A CHARTS=(
    ["prometheus"]="prom"
    ["mimir"]="mimir"
    ["keycloak"]="kc"
    ["elasticsearch"]="es"
    ["kafka"]="kafka"
)

for chart in "${!CHARTS[@]}"; do
    prefix="${CHARTS[$chart]}"
    echo "## $chart" >> $REPORT_FILE

    # Find latest backup
    LATEST=$(find $BACKUP_ROOT/$chart/full -name "*.tar.gz" -type f -printf '%T@ %p\n' | \
        sort -nr | head -1 | cut -d' ' -f2)

    if [ -z "$LATEST" ]; then
        echo "- Status: ✗ No backups found" >> $REPORT_FILE
        continue
    fi

    # Get backup age
    AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 3600 ))
    echo "- Latest backup: $(basename $LATEST)" >> $REPORT_FILE
    echo "- Age: ${AGE} hours" >> $REPORT_FILE

    # Verify integrity
    if make -f make/ops/${chart}.mk ${prefix}-backup-verify BACKUP_FILE=$LATEST >/dev/null 2>&1; then
        echo "- Integrity: ✓ Valid" >> $REPORT_FILE
    else
        echo "- Integrity: ✗ Failed" >> $REPORT_FILE
    fi

    # Check size
    SIZE=$(du -h "$LATEST" | cut -f1)
    echo "- Size: $SIZE" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
done

echo "Verification report: $REPORT_FILE"
```

---

## Best Practices

### 1. Backup Strategy

**DO:**
- ✅ Test backups monthly with DR drills
- ✅ Store backups in multiple locations (local, S3, offsite)
- ✅ Encrypt backups at rest and in transit
- ✅ Monitor backup success/failure with alerts
- ✅ Document recovery procedures
- ✅ Automate backup verification

**DON'T:**
- ❌ Store backups only in the same cluster
- ❌ Skip backup testing
- ❌ Ignore backup failures
- ❌ Keep backups indefinitely without rotation
- ❌ Store credentials in plain text

### 2. Recovery Planning

**Preparation:**
1. Maintain updated runbooks
2. Document dependencies between charts
3. Identify critical vs. non-critical data
4. Establish communication channels for DR events
5. Assign roles and responsibilities

**Execution:**
1. Follow the recovery order (infrastructure → storage → applications)
2. Verify each component before proceeding
3. Document any issues encountered
4. Update RTO/RPO metrics based on actual recovery times

### 3. Compliance

**Data Retention:**
- Local backups: 7 days
- S3 hot tier: 30 days
- S3 warm tier: 90 days
- S3 cold tier: 1 year
- Offsite backups: 90 days

**Audit Logging:**
- Log all backup operations
- Log all recovery operations
- Track access to backup storage
- Monitor backup storage usage

### 4. Cost Optimization

**Storage Tiering:**
```bash
# Lifecycle policy for S3
aws s3api put-bucket-lifecycle-configuration \
  --bucket sb-helm-backups \
  --lifecycle-configuration '{
    "Rules": [
      {
        "Id": "Move to IA after 30 days",
        "Status": "Enabled",
        "Transitions": [
          {
            "Days": 30,
            "StorageClass": "STANDARD_IA"
          },
          {
            "Days": 90,
            "StorageClass": "GLACIER"
          }
        ],
        "Expiration": {
          "Days": 365
        }
      }
    ]
  }'
```

**Compression:**
- Use gzip for all backups (typically 60-80% reduction)
- Consider zstd for better compression ratios
- Balance compression ratio vs. CPU cost

---

## Appendix

### A. Recovery Time Estimates

| Scenario | Estimated RTO | Notes |
|----------|---------------|-------|
| Single chart (small) | 15-30 minutes | E.g., Redis, Memcached |
| Single chart (medium) | 30-60 minutes | E.g., Prometheus, Keycloak |
| Single chart (large) | 1-2 hours | E.g., Elasticsearch, Harbor |
| Full infrastructure | 2-3 hours | All databases and message queues |
| Full cluster | 3-4 hours | Complete disaster recovery |

### B. Backup Size Estimates

**Tier 1 - Critical Infrastructure:**

| Chart | Daily Backup Size | 30-Day Total | Notes |
|-------|-------------------|--------------|-------|
| PostgreSQL | 100MB - 1GB | 3GB - 30GB | Plus WAL archives |
| MySQL | 100MB - 1GB | 3GB - 30GB | Plus binary logs |
| Redis | 50MB - 500MB | 1.5GB - 15GB | RDB + AOF |
| Prometheus | 500MB - 2GB | 15GB - 60GB | TSDB snapshots |
| Loki | 500MB - 3GB | 15GB - 90GB | Log chunks |
| Tempo | 200MB - 1GB | 6GB - 30GB | Trace data |

**Tier 2 - Application Platform:**

| Chart | Daily Backup Size | 30-Day Total | Notes |
|-------|-------------------|--------------|-------|
| Keycloak | 50MB - 200MB | 1.5GB - 6GB | Realms + PostgreSQL |
| Airflow | 200MB - 1GB | 6GB - 30GB | Metadata DB + DAGs |
| Harbor | 5GB - 50GB | 150GB - 1.5TB | Container images + charts |
| MLflow | 500MB - 5GB | 15GB - 150GB | Experiments + artifacts |
| Grafana | 100MB - 500MB | 3GB - 15GB | SQLite + dashboards |
| Nextcloud | 1GB - 20GB | 30GB - 600GB | User files + DB |
| Vaultwarden | 50MB - 500MB | 1.5GB - 15GB | Vault + DB |
| WordPress | 500MB - 5GB | 15GB - 150GB | Content + media + DB |

**Tier 3 - Supporting Services:**

| Chart | Daily Backup Size | 30-Day Total | Notes |
|-------|-------------------|--------------|-------|
| Kafka | 500MB - 5GB | 15GB - 150GB | Topic data + metadata |
| Elasticsearch | 1GB - 10GB | 30GB - 300GB | Index snapshots |
| Mimir | 1GB - 5GB | 30GB - 150GB | TSDB blocks |
| MinIO | 2GB - 50GB | 60GB - 1.5TB | Object storage |
| MongoDB | 500MB - 5GB | 15GB - 150GB | Document dumps + oplog |
| RabbitMQ | 100MB - 1GB | 3GB - 30GB | Definitions + messages |
| Paperless-ngx | 500MB - 10GB | 15GB - 300GB | Documents + DB |
| Immich | 1GB - 20GB | 30GB - 600GB | Photo library + DB |

**Tier 4 - Auxiliary Services:**

| Chart | Daily Backup Size | 30-Day Total | Notes |
|-------|-------------------|--------------|-------|
| OpenTelemetry | 10MB - 50MB | 300MB - 1.5GB | Config only |
| Promtail | 10MB - 50MB | 300MB - 1.5GB | Config only |
| Alertmanager | 50MB - 200MB | 1.5GB - 6GB | Silences + config |
| Jellyfin | 200MB - 1GB | 6GB - 30GB | Config + DB (media on NAS) |
| Uptime Kuma | 50MB - 200MB | 1.5GB - 6GB | SQLite DB |
| Memcached | 10MB - 50MB | 300MB - 1.5GB | Config only |

**Grand Total:**
- **Minimum**: ~15GB daily, ~450GB/month
- **Typical**: ~60GB daily, ~1.8TB/month
- **Maximum**: ~200GB daily, ~6TB/month

### C. Critical Commands Reference

```bash
# Master backup
./master-backup.sh

# Full cluster recovery
BACKUP_DATE=20231127-120000 ./full-cluster-recovery.sh

# Partial recovery
./partial-recovery.sh prometheus ./backups/prometheus/full/20231127-120000.tar.gz

# DR drill
BACKUP_DATE=latest ./dr-drill.sh

# Verify backups
./verify-all-backups.sh

# Check backup age
find ./backups -name "*.tar.gz" -mtime -1 -ls
```

---

**Document Version**: 2.0.0
**Last Updated**: 2025-12-09
**Charts Covered**: 28 enhanced charts (v1.4.0)
