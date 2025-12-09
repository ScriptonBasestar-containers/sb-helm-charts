# Backup Orchestration Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Master Backup Script](#master-backup-script)
4. [Backup Verification](#backup-verification)
5. [Retention Management](#retention-management)
6. [Storage Integration](#storage-integration)
7. [Monitoring & Alerting](#monitoring--alerting)
8. [Scheduling & Automation](#scheduling--automation)

---

## Overview

### Purpose

This guide provides a comprehensive backup orchestration system for managing backups across all 28 enhanced Helm charts. It enables centralized backup management, verification, retention policy enforcement, and monitoring.

### Orchestration Goals

| Goal | Target | Status |
|------|--------|--------|
| **Chart Coverage** | 28/28 enhanced charts (100%) | Automated |
| **Backup Execution** | < 2 hours (full cluster) | Optimized |
| **Verification Rate** | 100% (all backups verified) | Automated |
| **Retention Compliance** | 100% (policies enforced) | Automated |
| **Storage Efficiency** | 60-80% compression | Optimized |

### Backup Categories

**Tier 1 - Critical Infrastructure (Priority: High):**
- PostgreSQL, MySQL, Redis (PITR-enabled)
- Prometheus, Loki, Tempo (observability)

**Tier 2 - Application Platform (Priority: High):**
- Keycloak, Airflow, Harbor, MLflow
- Grafana, Nextcloud, Vaultwarden, WordPress

**Tier 3 - Supporting Services (Priority: Medium):**
- Kafka, Elasticsearch, Mimir, MinIO
- MongoDB, RabbitMQ, Paperless-ngx, Immich

**Tier 4 - Auxiliary Services (Priority: Low):**
- OpenTelemetry, Promtail, Alertmanager
- Jellyfin, Uptime Kuma, Memcached

---

## Architecture

### Orchestration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. Pre-Backup Validation                      │
│  Check cluster health → Verify storage → Check prerequisites    │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    2. Tier-Based Backup                          │
│  Tier 1 → Tier 2 → Tier 3 → Tier 4 (sequential or parallel)    │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    3. Backup Verification                        │
│  Checksum validation → Size validation → Integrity checks       │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    4. Storage Upload                             │
│  Local storage → S3/MinIO upload → Offsite replication         │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    5. Post-Backup Actions                        │
│  Retention cleanup → Metrics update → Alerting → Reporting     │
└─────────────────────────────────────────────────────────────────┘
```

### Storage Architecture

```
Primary Cluster (Kubernetes)
        │
        ├─ Local Backups (PVC)
        │  ├─ Location: /backups/
        │  ├─ Retention: 7 days
        │  └─ Purpose: Fast recovery
        │
        ├─ S3/MinIO (Object Storage)
        │  ├─ Hot tier: 30 days (Standard)
        │  ├─ Warm tier: 90 days (Standard-IA)
        │  ├─ Cold tier: 1 year (Glacier)
        │  └─ Purpose: Long-term retention
        │
        └─ Offsite Backup (Different Region/Provider)
           ├─ Retention: 90 days
           ├─ Purpose: Disaster recovery
           └─ Sync: Daily (incremental)
```

---

## Master Backup Script

### Orchestration Script

**scripts/backup-orchestrator.sh:**
```bash
#!/bin/bash
# Master backup orchestration script for all 28 enhanced charts

set -e

# ============================================================================
# Configuration
# ============================================================================

NAMESPACE="${NAMESPACE:-default}"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
S3_BUCKET="${S3_BUCKET:-sb-helm-backups}"
S3_ENDPOINT="${S3_ENDPOINT:-}"  # Optional for MinIO
PARALLEL="${PARALLEL:-true}"
TIER_FILTER="${TIER_FILTER:-all}"  # all, tier1, tier2, tier3, tier4
DRY_RUN="${DRY_RUN:-false}"
VERIFY="${VERIFY:-true}"
UPLOAD="${UPLOAD:-true}"
RETENTION_CLEANUP="${RETENTION_CLEANUP:-true}"

# ============================================================================
# Color Codes
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Logging
# ============================================================================

LOG_FILE="$BACKUP_ROOT/orchestrator-$TIMESTAMP.log"
mkdir -p "$BACKUP_ROOT"

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# ============================================================================
# Chart Definitions
# ============================================================================

declare -A TIER1_CHARTS=(
    ["postgresql"]="postgresql.mk:pg-backup-all"
    ["mysql"]="mysql.mk:mysql-backup-all"
    ["redis"]="redis.mk:redis-backup-all"
    ["prometheus"]="prometheus.mk:prom-backup-all"
    ["loki"]="loki.mk:loki-backup-all"
    ["tempo"]="tempo.mk:tempo-backup-all"
)

declare -A TIER2_CHARTS=(
    ["keycloak"]="keycloak.mk:kc-backup-all-realms"
    ["airflow"]="airflow.mk:airflow-backup-all"
    ["harbor"]="harbor.mk:harbor-backup-all"
    ["mlflow"]="mlflow.mk:mlflow-backup-all"
    ["grafana"]="grafana.mk:grafana-backup-all"
    ["nextcloud"]="nextcloud.mk:nc-backup-all"
    ["vaultwarden"]="vaultwarden.mk:vw-backup-all"
    ["wordpress"]="wordpress.mk:wp-backup-all"
)

declare -A TIER3_CHARTS=(
    ["kafka"]="kafka.mk:kafka-backup-all"
    ["elasticsearch"]="elasticsearch.mk:es-backup-snapshot"
    ["mimir"]="mimir.mk:mimir-backup-all"
    ["minio"]="minio.mk:minio-backup-all"
    ["mongodb"]="mongodb.mk:mongo-backup-all"
    ["rabbitmq"]="rabbitmq.mk:rmq-backup-all"
    ["paperless-ngx"]="paperless-ngx.mk:paperless-backup-all"
    ["immich"]="immich.mk:immich-backup-all"
)

declare -A TIER4_CHARTS=(
    ["otel-collector"]="opentelemetry-collector.mk:otel-backup-config"
    ["promtail"]="promtail.mk:promtail-backup-config"
    ["alertmanager"]="alertmanager.mk:am-backup-all"
    ["jellyfin"]="jellyfin.mk:jf-backup-all"
    ["uptime-kuma"]="uptime-kuma.mk:uk-backup-all"
    ["memcached"]="memcached.mk:mc-backup-config"
)

# ============================================================================
# Pre-Backup Validation
# ============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm not found"
        exit 1
    fi

    # Check make
    if ! command -v make &> /dev/null; then
        log_error "make not found"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace not found: $NAMESPACE"
        exit 1
    fi

    # Check backup directory
    if [ ! -d "$BACKUP_ROOT" ]; then
        mkdir -p "$BACKUP_ROOT" || {
            log_error "Cannot create backup directory: $BACKUP_ROOT"
            exit 1
        }
    fi

    # Check disk space (require at least 10GB free)
    local free_space=$(df -BG "$BACKUP_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$free_space" -lt 10 ]; then
        log_warn "Low disk space: ${free_space}GB available (recommend >10GB)"
    fi

    log_success "Prerequisites validated"
}

# ============================================================================
# Backup Execution
# ============================================================================

backup_chart() {
    local chart=$1
    local makefile=$2
    local target=$3
    local start_time=$(date +%s)

    log_info "[${chart}] Starting backup..."

    # Create chart backup directory
    mkdir -p "$BACKUP_ROOT/$chart"

    # Execute backup
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[${chart}] DRY RUN - Would execute: make -f make/ops/$makefile $target"
        echo "success" > "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt"
        return 0
    fi

    if make -f make/ops/$makefile $target \
        NAMESPACE="$NAMESPACE" \
        BACKUP_DIR="$BACKUP_ROOT/$chart" \
        2>&1 | tee "$BACKUP_ROOT/$chart/backup-$TIMESTAMP.log"; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo "success" > "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt"
        echo "$duration" > "$BACKUP_ROOT/$chart/duration-$TIMESTAMP.txt"

        log_success "[${chart}] Backup completed in ${duration}s"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo "failed" > "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt"
        echo "$duration" > "$BACKUP_ROOT/$chart/duration-$TIMESTAMP.txt"

        log_error "[${chart}] Backup failed after ${duration}s"
        return 1
    fi
}

# Export for parallel execution
export -f backup_chart log_info log_success log_error
export BACKUP_ROOT TIMESTAMP NAMESPACE DRY_RUN RED GREEN YELLOW NC

backup_tier() {
    local tier_name=$1
    local -n charts=$2
    local tier_start=$(date +%s)

    log_info "========================================="
    log_info "Backing up $tier_name"
    log_info "========================================="

    if [ "$PARALLEL" = "true" ]; then
        log_info "[$tier_name] Executing backups in parallel..."

        # Run backups in parallel
        local pids=()
        for chart in "${!charts[@]}"; do
            IFS=':' read -r makefile target <<< "${charts[$chart]}"
            backup_chart "$chart" "$makefile" "$target" &
            pids+=($!)
        done

        # Wait for all backups to complete
        local failed=0
        for pid in "${pids[@]}"; do
            if ! wait $pid; then
                ((failed++))
            fi
        done

        if [ $failed -gt 0 ]; then
            log_error "[$tier_name] $failed backup(s) failed"
            return 1
        fi
    else
        log_info "[$tier_name] Executing backups sequentially..."

        local failed=0
        for chart in "${!charts[@]}"; do
            IFS=':' read -r makefile target <<< "${charts[$chart]}"
            if ! backup_chart "$chart" "$makefile" "$target"; then
                ((failed++))
            fi
        done

        if [ $failed -gt 0 ]; then
            log_error "[$tier_name] $failed backup(s) failed"
            return 1
        fi
    fi

    local tier_end=$(date +%s)
    local tier_duration=$((tier_end - tier_start))

    log_success "[$tier_name] All backups completed in ${tier_duration}s"
    return 0
}

# ============================================================================
# Backup Verification
# ============================================================================

verify_backup() {
    local chart=$1

    log_info "[${chart}] Verifying backup..."

    # Check if backup status file exists
    if [ ! -f "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt" ]; then
        log_error "[${chart}] Backup status file not found"
        return 1
    fi

    # Check backup status
    local status=$(cat "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt")
    if [ "$status" != "success" ]; then
        log_error "[${chart}] Backup status is: $status"
        return 1
    fi

    # Find latest backup file
    local backup_file=$(find "$BACKUP_ROOT/$chart" -name "*.tar.gz" -type f -newer "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt" 2>/dev/null | head -1)

    if [ -z "$backup_file" ]; then
        # Some charts may not create tar.gz (config-only backups)
        log_info "[${chart}] No tar.gz backup file (config-only backup)"
        return 0
    fi

    # Verify file size (must be > 0)
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [ "$file_size" -eq 0 ]; then
        log_error "[${chart}] Backup file is empty: $backup_file"
        return 1
    fi

    # Verify tar.gz integrity
    if ! tar -tzf "$backup_file" &>/dev/null; then
        log_error "[${chart}] Backup file is corrupted: $backup_file"
        return 1
    fi

    # Calculate and save checksum
    local checksum=$(sha256sum "$backup_file" | awk '{print $1}')
    echo "$checksum" > "${backup_file}.sha256"

    log_success "[${chart}] Backup verified (${file_size} bytes, SHA256: ${checksum:0:16}...)"
    return 0
}

verify_all_backups() {
    if [ "$VERIFY" != "true" ]; then
        log_info "Skipping backup verification (VERIFY=false)"
        return 0
    fi

    log_info "========================================="
    log_info "Verifying all backups"
    log_info "========================================="

    local failed=0
    local total=0

    for tier in TIER1_CHARTS TIER2_CHARTS TIER3_CHARTS TIER4_CHARTS; do
        local -n charts=$tier
        for chart in "${!charts[@]}"; do
            ((total++))
            if ! verify_backup "$chart"; then
                ((failed++))
            fi
        done
    done

    if [ $failed -gt 0 ]; then
        log_error "Verification failed for $failed/$total backups"
        return 1
    else
        log_success "All $total backups verified successfully"
        return 0
    fi
}

# ============================================================================
# Storage Upload
# ============================================================================

upload_to_s3() {
    if [ "$UPLOAD" != "true" ]; then
        log_info "Skipping S3 upload (UPLOAD=false)"
        return 0
    fi

    if [ -z "$S3_BUCKET" ]; then
        log_warn "S3_BUCKET not set, skipping upload"
        return 0
    fi

    log_info "========================================="
    log_info "Uploading backups to S3: $S3_BUCKET"
    log_info "========================================="

    # Build AWS CLI command
    local aws_cmd="aws s3"
    if [ -n "$S3_ENDPOINT" ]; then
        aws_cmd="$aws_cmd --endpoint-url $S3_ENDPOINT"
    fi

    # Upload each chart's backup
    local uploaded=0
    local failed=0

    for tier in TIER1_CHARTS TIER2_CHARTS TIER3_CHARTS TIER4_CHARTS; do
        local -n charts=$tier
        for chart in "${!charts[@]}"; do
            # Find backup files for this chart
            local backup_files=$(find "$BACKUP_ROOT/$chart" -name "*$TIMESTAMP*" -type f)

            if [ -z "$backup_files" ]; then
                log_warn "[${chart}] No backup files found for upload"
                continue
            fi

            # Upload each file
            for file in $backup_files; do
                local s3_path="s3://$S3_BUCKET/$chart/$(basename $file)"

                if $aws_cmd cp "$file" "$s3_path" &>/dev/null; then
                    log_success "[${chart}] Uploaded: $(basename $file)"
                    ((uploaded++))
                else
                    log_error "[${chart}] Upload failed: $(basename $file)"
                    ((failed++))
                fi
            done
        done
    done

    if [ $failed -gt 0 ]; then
        log_error "S3 upload: $uploaded succeeded, $failed failed"
        return 1
    else
        log_success "S3 upload: All $uploaded files uploaded successfully"
        return 0
    fi
}

# ============================================================================
# Retention Management
# ============================================================================

cleanup_old_backups() {
    if [ "$RETENTION_CLEANUP" != "true" ]; then
        log_info "Skipping retention cleanup (RETENTION_CLEANUP=false)"
        return 0
    fi

    log_info "========================================="
    log_info "Cleaning up old backups"
    log_info "========================================="

    # Local retention: 7 days
    local local_retention_days=7
    local deleted=0

    log_info "Deleting local backups older than $local_retention_days days..."

    for tier in TIER1_CHARTS TIER2_CHARTS TIER3_CHARTS TIER4_CHARTS; do
        local -n charts=$tier
        for chart in "${!charts[@]}"; do
            if [ -d "$BACKUP_ROOT/$chart" ]; then
                local old_files=$(find "$BACKUP_ROOT/$chart" -type f -mtime +$local_retention_days 2>/dev/null)

                if [ -n "$old_files" ]; then
                    echo "$old_files" | while read file; do
                        rm -f "$file"
                        ((deleted++))
                        log_info "[${chart}] Deleted: $(basename $file)"
                    done
                fi
            fi
        done
    done

    log_success "Deleted $deleted old backup files"

    # S3 retention (if configured)
    if [ -n "$S3_BUCKET" ] && [ "$UPLOAD" = "true" ]; then
        log_info "S3 retention policies are managed by bucket lifecycle rules"
    fi
}

# ============================================================================
# Reporting
# ============================================================================

generate_report() {
    log_info "========================================="
    log_info "Generating backup report"
    log_info "========================================="

    local report_file="$BACKUP_ROOT/backup-report-$TIMESTAMP.json"

    # Collect backup statistics
    local total_charts=0
    local successful_charts=0
    local failed_charts=0
    local total_size=0
    local total_duration=0

    for tier in TIER1_CHARTS TIER2_CHARTS TIER3_CHARTS TIER4_CHARTS; do
        local -n charts=$tier
        for chart in "${!charts[@]}"; do
            ((total_charts++))

            if [ -f "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt" ]; then
                local status=$(cat "$BACKUP_ROOT/$chart/status-$TIMESTAMP.txt")
                if [ "$status" = "success" ]; then
                    ((successful_charts++))
                else
                    ((failed_charts++))
                fi
            else
                ((failed_charts++))
            fi

            # Get backup size
            local chart_size=$(du -sb "$BACKUP_ROOT/$chart" 2>/dev/null | awk '{print $1}')
            total_size=$((total_size + chart_size))

            # Get duration
            if [ -f "$BACKUP_ROOT/$chart/duration-$TIMESTAMP.txt" ]; then
                local duration=$(cat "$BACKUP_ROOT/$chart/duration-$TIMESTAMP.txt")
                total_duration=$((total_duration + duration))
            fi
        done
    done

    # Generate JSON report
    cat > "$report_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "backup_id": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "execution_mode": "$([ "$PARALLEL" = "true" ] && echo "parallel" || echo "sequential")",
  "tier_filter": "$TIER_FILTER",
  "statistics": {
    "total_charts": $total_charts,
    "successful": $successful_charts,
    "failed": $failed_charts,
    "success_rate": $(echo "scale=2; $successful_charts * 100 / $total_charts" | bc),
    "total_size_bytes": $total_size,
    "total_size_human": "$(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size}B")",
    "total_duration_seconds": $total_duration,
    "total_duration_human": "$(printf '%dh %dm %ds' $((total_duration/3600)) $((total_duration%3600/60)) $((total_duration%60)))"
  },
  "storage": {
    "local_path": "$BACKUP_ROOT",
    "s3_bucket": "$S3_BUCKET",
    "s3_uploaded": $([ "$UPLOAD" = "true" ] && echo "true" || echo "false")
  },
  "verification": {
    "enabled": $([ "$VERIFY" = "true" ] && echo "true" || echo "false"),
    "status": "$([ $failed_charts -eq 0 ] && echo "passed" || echo "failed")"
  },
  "retention": {
    "cleanup_enabled": $([ "$RETENTION_CLEANUP" = "true" ] && echo "true" || echo "false"),
    "local_retention_days": 7
  }
}
EOF

    log_success "Report generated: $report_file"

    # Display summary
    echo ""
    echo "========================================="
    echo "Backup Summary"
    echo "========================================="
    echo "Total Charts:     $total_charts"
    echo "Successful:       $successful_charts"
    echo "Failed:           $failed_charts"
    echo "Success Rate:     $(echo "scale=1; $successful_charts * 100 / $total_charts" | bc)%"
    echo "Total Size:       $(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size}B")"
    echo "Total Duration:   $(printf '%dh %dm %ds' $((total_duration/3600)) $((total_duration%3600/60)) $((total_duration%60)))"
    echo "========================================="
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local script_start=$(date +%s)

    echo "========================================="
    echo "ScriptonBasestar Backup Orchestrator"
    echo "========================================="
    echo "Timestamp:     $TIMESTAMP"
    echo "Namespace:     $NAMESPACE"
    echo "Backup Root:   $BACKUP_ROOT"
    echo "S3 Bucket:     $S3_BUCKET"
    echo "Parallel:      $PARALLEL"
    echo "Tier Filter:   $TIER_FILTER"
    echo "Dry Run:       $DRY_RUN"
    echo "Verify:        $VERIFY"
    echo "Upload:        $UPLOAD"
    echo "========================================="
    echo ""

    # Step 1: Validate prerequisites
    validate_prerequisites || exit 1
    echo ""

    # Step 2: Execute backups
    local backup_failed=0

    case $TIER_FILTER in
        tier1)
            backup_tier "Tier 1" TIER1_CHARTS || ((backup_failed++))
            ;;
        tier2)
            backup_tier "Tier 2" TIER2_CHARTS || ((backup_failed++))
            ;;
        tier3)
            backup_tier "Tier 3" TIER3_CHARTS || ((backup_failed++))
            ;;
        tier4)
            backup_tier "Tier 4" TIER4_CHARTS || ((backup_failed++))
            ;;
        all)
            backup_tier "Tier 1" TIER1_CHARTS || ((backup_failed++))
            echo ""
            backup_tier "Tier 2" TIER2_CHARTS || ((backup_failed++))
            echo ""
            backup_tier "Tier 3" TIER3_CHARTS || ((backup_failed++))
            echo ""
            backup_tier "Tier 4" TIER4_CHARTS || ((backup_failed++))
            ;;
        *)
            log_error "Invalid tier filter: $TIER_FILTER (use: all, tier1, tier2, tier3, tier4)"
            exit 1
            ;;
    esac

    echo ""

    # Step 3: Verify backups
    verify_all_backups || ((backup_failed++))
    echo ""

    # Step 4: Upload to S3
    upload_to_s3 || log_warn "S3 upload had errors, but continuing..."
    echo ""

    # Step 5: Retention cleanup
    cleanup_old_backups || log_warn "Retention cleanup had errors, but continuing..."
    echo ""

    # Step 6: Generate report
    generate_report

    local script_end=$(date +%s)
    local script_duration=$((script_end - script_start))

    echo ""
    echo "========================================="
    if [ $backup_failed -eq 0 ]; then
        log_success "Backup orchestration completed successfully in ${script_duration}s"
        exit 0
    else
        log_error "Backup orchestration completed with errors in ${script_duration}s"
        exit 1
    fi
}

# Run main function
main
```

---

## Backup Verification

### Verification System

**scripts/backup-verifier.sh:**
```bash
#!/bin/bash
# Backup verification system

set -e

BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
BACKUP_DATE="${BACKUP_DATE:-latest}"
REPORT_FILE="$BACKUP_ROOT/verification-report-$(date +%Y%m%d-%H%M%S).json"

# Find latest backup if not specified
if [ "$BACKUP_DATE" = "latest" ]; then
    BACKUP_DATE=$(ls -1 "$BACKUP_ROOT"/backup-report-*.json 2>/dev/null | tail -1 | sed 's/.*backup-report-\(.*\)\.json/\1/')

    if [ -z "$BACKUP_DATE" ]; then
        echo "Error: No backups found in $BACKUP_ROOT"
        exit 1
    fi

    echo "Using latest backup: $BACKUP_DATE"
fi

# Verification results
declare -A VERIFICATION_RESULTS

verify_chart_backup() {
    local chart=$1
    local result="PASS"
    local errors=()

    # Check if backup directory exists
    if [ ! -d "$BACKUP_ROOT/$chart" ]; then
        errors+=("Backup directory not found")
        result="FAIL"
    fi

    # Check backup status
    if [ -f "$BACKUP_ROOT/$chart/status-$BACKUP_DATE.txt" ]; then
        local status=$(cat "$BACKUP_ROOT/$chart/status-$BACKUP_DATE.txt")
        if [ "$status" != "success" ]; then
            errors+=("Backup status: $status")
            result="FAIL"
        fi
    else
        errors+=("Status file not found")
        result="FAIL"
    fi

    # Check for backup files
    local backup_count=$(find "$BACKUP_ROOT/$chart" -name "*$BACKUP_DATE*" -type f | wc -l)
    if [ "$backup_count" -eq 0 ]; then
        errors+=("No backup files found")
        result="FAIL"
    fi

    # Verify checksums
    for file in $(find "$BACKUP_ROOT/$chart" -name "*.tar.gz" -type f); do
        if [ -f "${file}.sha256" ]; then
            local expected=$(cat "${file}.sha256")
            local actual=$(sha256sum "$file" | awk '{print $1}')

            if [ "$expected" != "$actual" ]; then
                errors+=("Checksum mismatch: $(basename $file)")
                result="FAIL"
            fi
        fi
    done

    # Store result
    if [ "$result" = "PASS" ]; then
        VERIFICATION_RESULTS[$chart]="PASS"
        echo "✓ $chart"
    else
        VERIFICATION_RESULTS[$chart]="FAIL: ${errors[*]}"
        echo "✗ $chart: ${errors[*]}"
    fi
}

echo "Verifying backups from $BACKUP_DATE..."
echo ""

# Verify all charts
for chart in postgresql mysql redis prometheus loki tempo \
             keycloak airflow harbor mlflow grafana nextcloud vaultwarden wordpress \
             kafka elasticsearch mimir minio mongodb rabbitmq paperless-ngx immich \
             otel-collector promtail alertmanager jellyfin uptime-kuma memcached; do
    verify_chart_backup "$chart"
done

# Generate report
echo ""
echo "Generating verification report..."

passed=0
failed=0
for chart in "${!VERIFICATION_RESULTS[@]}"; do
    if [[ "${VERIFICATION_RESULTS[$chart]}" == "PASS" ]]; then
        ((passed++))
    else
        ((failed++))
    fi
done

cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "backup_date": "$BACKUP_DATE",
  "verification": {
    "total": $((passed + failed)),
    "passed": $passed,
    "failed": $failed,
    "pass_rate": $(echo "scale=2; $passed * 100 / ($passed + $failed)" | bc)
  },
  "results": {
$(for chart in "${!VERIFICATION_RESULTS[@]}"; do
    echo "    \"$chart\": \"${VERIFICATION_RESULTS[$chart]}\","
done | sed '$ s/,$//')
  }
}
EOF

echo "Report saved: $REPORT_FILE"
echo ""
echo "Verification Summary:"
echo "  Total:  $((passed + failed))"
echo "  Passed: $passed"
echo "  Failed: $failed"

if [ $failed -eq 0 ]; then
    echo ""
    echo "✓ All backups verified successfully"
    exit 0
else
    echo ""
    echo "✗ $failed backup(s) failed verification"
    exit 1
fi
```

---

## Retention Management

### Retention Policy Configuration

**config/retention-policies.yaml:**
```yaml
# Backup retention policies for all storage tiers

# Local storage (fast recovery)
local:
  enabled: true
  location: /backups
  policies:
    - name: short-term
      retention_days: 7
      applies_to:
        - tier1  # Critical infrastructure
        - tier2  # Application platform
        - tier3  # Supporting services
        - tier4  # Auxiliary services

# S3/MinIO storage (long-term retention)
s3:
  enabled: true
  bucket: sb-helm-backups
  endpoint: ""  # Optional for MinIO
  policies:
    - name: hot
      storage_class: STANDARD
      retention_days: 30
      applies_to:
        - tier1
        - tier2

    - name: warm
      storage_class: STANDARD_IA
      retention_days: 90
      transition_from: hot
      applies_to:
        - tier1
        - tier2
        - tier3

    - name: cold
      storage_class: GLACIER
      retention_days: 365
      transition_from: warm
      applies_to:
        - tier1

    - name: delete
      action: expire
      retention_days: 365
      applies_to:
        - tier2
        - tier3
        - tier4

# Offsite storage (disaster recovery)
offsite:
  enabled: false
  location: s3://offsite-backups
  region: us-west-2
  policies:
    - name: dr-retention
      retention_days: 90
      applies_to:
        - tier1
        - tier2
```

### S3 Lifecycle Policy

**scripts/configure-s3-lifecycle.sh:**
```bash
#!/bin/bash
# Configure S3 lifecycle policies for backup retention

set -e

S3_BUCKET="${S3_BUCKET:-sb-helm-backups}"
AWS_CMD="aws s3api"

if [ -n "$S3_ENDPOINT" ]; then
    AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"
fi

echo "Configuring S3 lifecycle policy for bucket: $S3_BUCKET"

# Create lifecycle configuration
cat > /tmp/lifecycle-policy.json <<'EOF'
{
  "Rules": [
    {
      "Id": "tier1-tier2-hot-to-warm",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ]
    },
    {
      "Id": "tier3-tier4-cleanup",
      "Status": "Enabled",
      "Filter": {
        "And": {
          "Prefix": "",
          "Tags": [
            {
              "Key": "tier",
              "Value": "tier3"
            }
          ]
        }
      },
      "Expiration": {
        "Days": 90
      }
    },
    {
      "Id": "tier4-cleanup",
      "Status": "Enabled",
      "Filter": {
        "And": {
          "Prefix": "",
          "Tags": [
            {
              "Key": "tier",
              "Value": "tier4"
            }
          ]
        }
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
EOF

# Apply lifecycle policy
$AWS_CMD put-bucket-lifecycle-configuration \
    --bucket "$S3_BUCKET" \
    --lifecycle-configuration file:///tmp/lifecycle-policy.json

echo "✓ Lifecycle policy configured successfully"

# Cleanup
rm /tmp/lifecycle-policy.json
```

---

## Storage Integration

### S3/MinIO Configuration

**config/storage-config.yaml:**
```yaml
# Storage configuration for backup orchestration

s3:
  # S3-compatible storage endpoint
  endpoint: ""  # Leave empty for AWS S3, set for MinIO

  # Bucket configuration
  bucket: sb-helm-backups
  region: us-east-1

  # Authentication (use environment variables)
  # AWS_ACCESS_KEY_ID
  # AWS_SECRET_ACCESS_KEY

  # Encryption
  encryption:
    enabled: true
    type: AES256  # or aws:kms

  # Versioning
  versioning:
    enabled: true

  # Transfer settings
  multipart_threshold: 100MB
  multipart_chunksize: 10MB
  max_concurrent_requests: 10

# Local storage
local:
  path: /backups
  permissions: "0750"
  owner: backup:backup

# Offsite replication (optional)
offsite:
  enabled: false
  type: s3
  endpoint: ""
  bucket: offsite-backups
  region: us-west-2
  sync_schedule: "0 4 * * *"  # Daily at 4 AM
```

### Storage Upload Script

**scripts/upload-to-storage.sh:**
```bash
#!/bin/bash
# Upload backups to S3/MinIO with progress tracking

set -e

BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
S3_BUCKET="${S3_BUCKET:-sb-helm-backups}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
PARALLEL_UPLOADS="${PARALLEL_UPLOADS:-5}"

# Build AWS CLI command
AWS_CMD="aws s3"
if [ -n "$S3_ENDPOINT" ]; then
    AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"
fi

# Upload with progress
upload_file() {
    local file=$1
    local chart=$(basename $(dirname "$file"))
    local s3_path="s3://$S3_BUCKET/$chart/$(basename $file)"

    # Add tier tag
    local tier_tag=""
    case $chart in
        postgresql|mysql|redis|prometheus|loki|tempo)
            tier_tag="tier=tier1"
            ;;
        keycloak|airflow|harbor|mlflow|grafana|nextcloud|vaultwarden|wordpress)
            tier_tag="tier=tier2"
            ;;
        kafka|elasticsearch|mimir|minio|mongodb|rabbitmq|paperless-ngx|immich)
            tier_tag="tier=tier3"
            ;;
        *)
            tier_tag="tier=tier4"
            ;;
    esac

    # Upload with metadata
    aws s3 cp "$file" "$s3_path" \
        --storage-class STANDARD \
        --metadata "tier=$tier_tag,backup_timestamp=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file")" \
        --tagging "$tier_tag" \
        $([ -n "$S3_ENDPOINT" ] && echo "--endpoint-url $S3_ENDPOINT")

    if [ $? -eq 0 ]; then
        echo "✓ Uploaded: $chart/$(basename $file)"
        return 0
    else
        echo "✗ Failed: $chart/$(basename $file)"
        return 1
    fi
}

export -f upload_file
export S3_BUCKET S3_ENDPOINT AWS_CMD

# Find all backup files
echo "Finding backup files in $BACKUP_ROOT..."
backup_files=$(find "$BACKUP_ROOT" -type f \( -name "*.tar.gz" -o -name "*.sql" -o -name "*.json" \) | grep -v "report")

total_files=$(echo "$backup_files" | wc -l)
echo "Found $total_files files to upload"
echo ""

# Upload files in parallel
echo "$backup_files" | xargs -P "$PARALLEL_UPLOADS" -I {} bash -c 'upload_file "$@"' _ {}

echo ""
echo "✓ Upload complete"
```

---

## Monitoring & Alerting

### Prometheus Metrics

**config/backup-metrics.yaml:**
```yaml
# Prometheus metrics for backup orchestration

apiVersion: v1
kind: ConfigMap
metadata:
  name: backup-metrics
  namespace: monitoring
data:
  backup_metrics.sh: |
    #!/bin/bash
    # Export backup metrics to Prometheus

    BACKUP_ROOT="/backups"
    METRICS_FILE="/var/lib/node_exporter/textfile_collector/backup_metrics.prom"

    # Backup age metrics
    echo "# HELP backup_last_success_timestamp Unix timestamp of last successful backup" > "$METRICS_FILE"
    echo "# TYPE backup_last_success_timestamp gauge" >> "$METRICS_FILE"

    for chart in postgresql mysql redis prometheus keycloak grafana; do
        if [ -f "$BACKUP_ROOT/$chart/status-*.txt" ]; then
            latest_status=$(ls -1t "$BACKUP_ROOT/$chart/status-*.txt" | head -1)
            if [ "$(cat $latest_status)" = "success" ]; then
                timestamp=$(stat -f%m "$latest_status" 2>/dev/null || stat -c%Y "$latest_status")
                echo "backup_last_success_timestamp{chart=\"$chart\"} $timestamp" >> "$METRICS_FILE"
            fi
        fi
    done

    # Backup size metrics
    echo "# HELP backup_size_bytes Size of latest backup in bytes" >> "$METRICS_FILE"
    echo "# TYPE backup_size_bytes gauge" >> "$METRICS_FILE"

    for chart in postgresql mysql redis prometheus keycloak grafana; do
        if [ -d "$BACKUP_ROOT/$chart" ]; then
            size=$(du -sb "$BACKUP_ROOT/$chart" 2>/dev/null | awk '{print $1}')
            echo "backup_size_bytes{chart=\"$chart\"} $size" >> "$METRICS_FILE"
        fi
    done

    # Backup success rate
    echo "# HELP backup_success_total Total successful backups" >> "$METRICS_FILE"
    echo "# TYPE backup_success_total counter" >> "$METRICS_FILE"

    for chart in postgresql mysql redis prometheus keycloak grafana; do
        success_count=$(find "$BACKUP_ROOT/$chart" -name "status-*.txt" -exec grep -l "success" {} \; 2>/dev/null | wc -l)
        echo "backup_success_total{chart=\"$chart\"} $success_count" >> "$METRICS_FILE"
    done
```

### Alertmanager Rules

**config/backup-alerts.yaml:**
```yaml
# Alertmanager rules for backup monitoring

apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: backup-orchestration-alerts
  namespace: monitoring
spec:
  groups:
  - name: backup-alerts
    interval: 5m
    rules:
    - alert: BackupTooOld
      expr: (time() - backup_last_success_timestamp) > 86400
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Backup too old for {{ $labels.chart }}"
        description: "Last successful backup was {{ $value | humanizeDuration }} ago"

    - alert: BackupFailed
      expr: backup_last_status != 1
      for: 15m
      labels:
        severity: critical
      annotations:
        summary: "Backup failed for {{ $labels.chart }}"
        description: "Last backup status: {{ $labels.error }}"

    - alert: BackupSizeAnomaly
      expr: |
        abs(backup_size_bytes - avg_over_time(backup_size_bytes[7d])) /
        avg_over_time(backup_size_bytes[7d]) > 0.5
      for: 30m
      labels:
        severity: warning
      annotations:
        summary: "Backup size anomaly for {{ $labels.chart }}"
        description: "Backup size is {{ $value | humanizePercentage }} different from 7-day average"

    - alert: BackupStorageAlmostFull
      expr: backup_storage_used_bytes / backup_storage_total_bytes > 0.85
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Backup storage almost full"
        description: "Storage usage: {{ $value | humanizePercentage }}"
```

---

## Scheduling & Automation

### Kubernetes CronJob

**manifests/backup-cronjob.yaml:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-orchestrator
  namespace: default
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: backup-orchestrator
        spec:
          serviceAccountName: backup-orchestrator
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: scriptonbasestar/backup-orchestrator:latest
            env:
            - name: NAMESPACE
              value: "default"
            - name: BACKUP_ROOT
              value: "/backups"
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
            - name: VERIFY
              value: "true"
            - name: UPLOAD
              value: "true"
            - name: RETENTION_CLEANUP
              value: "true"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
            - name: scripts
              mountPath: /scripts
            command: ["/bin/bash"]
            args: ["/scripts/backup-orchestrator.sh"]
            resources:
              requests:
                cpu: "500m"
                memory: "512Mi"
              limits:
                cpu: "2000m"
                memory: "2Gi"
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-storage
          - name: scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-storage
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: standard
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-orchestrator
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backup-orchestrator
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/log"]
  verbs: ["get", "list", "create", "delete"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "create"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "deployments"]
  verbs: ["get", "list"]
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backup-orchestrator
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: backup-orchestrator
subjects:
- kind: ServiceAccount
  name: backup-orchestrator
  namespace: default
```

---

**Document Version**: 1.0.0
**Last Updated**: 2025-12-09
**Charts Covered**: 28 enhanced charts (100%)
