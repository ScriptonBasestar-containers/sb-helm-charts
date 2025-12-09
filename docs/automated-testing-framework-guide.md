# Automated Testing Framework Guide

## Table of Contents

1. [Overview](#overview)
2. [Test Architecture](#test-architecture)
3. [Integration Tests](#integration-tests)
4. [Upgrade Tests](#upgrade-tests)
5. [Performance Tests](#performance-tests)
6. [CI/CD Automation](#cicd-automation)
7. [Test Utilities](#test-utilities)
8. [Best Practices](#best-practices)

---

## Overview

### Purpose

This guide provides a comprehensive automated testing framework for all 39 Helm charts in the ScriptonBasestar Charts repository. It covers integration testing, upgrade testing, performance testing, and CI/CD automation.

### Testing Goals

| Goal | Target | Status |
|------|--------|--------|
| **Chart Coverage** | 39/39 charts (100%) | Automated |
| **Test Execution Time** | < 30 minutes (full suite) | Optimized |
| **PR Validation** | Automated on every PR | GitHub Actions |
| **Release Validation** | Automated on release | GitHub Actions |
| **Performance Baseline** | All enhanced charts | Tracked |

### Test Categories

**1. Static Analysis:**
- Helm lint validation
- Template rendering validation
- YAML syntax validation
- Security scanning (Checkov, Trivy)

**2. Integration Tests:**
- Chart deployment verification
- Health check validation
- Connectivity tests
- Configuration validation

**3. Upgrade Tests:**
- Version-to-version upgrade paths
- Data persistence validation
- Configuration migration
- Rollback procedures

**4. Performance Tests:**
- Resource usage benchmarking
- Latency measurements
- Throughput testing
- Scalability validation

---

## Test Architecture

### Framework Structure

```
tests/
├── integration/          # Integration test suite
│   ├── tier1/           # Critical infrastructure (6 charts)
│   ├── tier2/           # Application platform (8 charts)
│   ├── tier3/           # Supporting services (8 charts)
│   ├── tier4/           # Auxiliary services (6 charts)
│   └── common/          # Shared test utilities
├── upgrade/             # Upgrade test suite
│   ├── scenarios/       # Version-specific upgrade scenarios
│   └── fixtures/        # Test data and configurations
├── performance/         # Performance test suite
│   ├── benchmarks/      # Baseline performance data
│   └── reports/         # Performance test reports
├── fixtures/            # Test fixtures (values files, test data)
├── helpers/             # Test helper scripts
└── reports/             # Test execution reports
```

### Test Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. Static Analysis                            │
│  helm lint → helm template → YAML validation → security scan    │
│  Duration: ~2 minutes (all 39 charts)                           │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    2. Integration Tests                          │
│  deploy chart → wait ready → run health checks → verify config  │
│  Duration: ~15 minutes (tier-based parallel execution)          │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    3. Upgrade Tests                              │
│  deploy v1 → upgrade to v2 → verify data → check compatibility  │
│  Duration: ~10 minutes (critical charts only)                   │
└──────────────────────┬──────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    4. Performance Tests                          │
│  deploy chart → run benchmarks → collect metrics → generate     │
│  Duration: ~5 minutes (enhanced charts only)                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Integration Tests

### Test Framework: BATS (Bash Automated Testing System)

**Installation:**
```bash
# Install BATS
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local

# Install helpers
git clone https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git clone https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```

### Integration Test Template

```bash
#!/usr/bin/env bats
# tests/integration/tier1/postgresql_test.bats

load '../common/helpers'
load '../common/assertions'

setup_file() {
    # Called once before all tests in this file
    export CHART_NAME="postgresql"
    export NAMESPACE="test-postgresql-$(date +%s)"
    export RELEASE_NAME="test-pg"

    kubectl create namespace "$NAMESPACE"
}

teardown_file() {
    # Called once after all tests in this file
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    kubectl delete namespace "$NAMESPACE" --wait=false || true
}

@test "[$CHART_NAME] Helm lint succeeds" {
    run helm lint "charts/$CHART_NAME"
    assert_success
    assert_output --partial "1 chart(s) linted"
}

@test "[$CHART_NAME] Helm template renders successfully" {
    run helm template "$RELEASE_NAME" "charts/$CHART_NAME" \
        --namespace "$NAMESPACE" \
        -f tests/fixtures/postgresql/values-test.yaml
    assert_success
}

@test "[$CHART_NAME] Chart deploys successfully" {
    run helm install "$RELEASE_NAME" "charts/$CHART_NAME" \
        --namespace "$NAMESPACE" \
        --create-namespace \
        -f tests/fixtures/postgresql/values-test.yaml \
        --wait --timeout 5m
    assert_success
}

@test "[$CHART_NAME] Pods are running" {
    run kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].status.phase}'
    assert_success
    assert_output "Running"
}

@test "[$CHART_NAME] StatefulSet is ready" {
    run kubectl get statefulset -n "$NAMESPACE" "$RELEASE_NAME-postgresql" -o jsonpath='{.status.readyReplicas}'
    assert_success
    assert_output "1"
}

@test "[$CHART_NAME] Service exists and is accessible" {
    run kubectl get service -n "$NAMESPACE" "$RELEASE_NAME-postgresql"
    assert_success
}

@test "[$CHART_NAME] PVC is bound" {
    run kubectl get pvc -n "$NAMESPACE" "data-$RELEASE_NAME-postgresql-0" -o jsonpath='{.status.phase}'
    assert_success
    assert_output "Bound"
}

@test "[$CHART_NAME] Database is accepting connections" {
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -c "SELECT 1" -t
    assert_success
    assert_output --partial "1"
}

@test "[$CHART_NAME] Health check passes" {
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        pg_isready -U postgres
    assert_success
    assert_output --partial "accepting connections"
}

@test "[$CHART_NAME] Can create and query database" {
    # Create test database
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -c "CREATE DATABASE testdb"
    assert_success

    # Insert test data
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -d testdb -c "CREATE TABLE test (id INTEGER, name VARCHAR(50)); INSERT INTO test VALUES (1, 'test')"
    assert_success

    # Query test data
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -d testdb -c "SELECT name FROM test WHERE id=1" -t
    assert_success
    assert_output --partial "test"
}

@test "[$CHART_NAME] Metrics endpoint is accessible" {
    skip_if_not_enabled "metrics"

    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        curl -s http://localhost:9187/metrics
    assert_success
    assert_output --partial "pg_up"
}

@test "[$CHART_NAME] ServiceMonitor exists" {
    skip_if_not_enabled "monitoring"

    run kubectl get servicemonitor -n "$NAMESPACE" "$RELEASE_NAME-postgresql"
    assert_success
}

@test "[$CHART_NAME] RBAC resources exist" {
    run kubectl get serviceaccount -n "$NAMESPACE" "$RELEASE_NAME-postgresql"
    assert_success

    run kubectl get role -n "$NAMESPACE" "$RELEASE_NAME-postgresql"
    assert_success

    run kubectl get rolebinding -n "$NAMESPACE" "$RELEASE_NAME-postgresql"
    assert_success
}

@test "[$CHART_NAME] Pod security context is correct" {
    run kubectl get pod -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" \
        -o jsonpath='{.spec.securityContext.runAsNonRoot}'
    assert_success
    assert_output "true"
}

@test "[$CHART_NAME] Chart can be upgraded" {
    run helm upgrade "$RELEASE_NAME" "charts/$CHART_NAME" \
        --namespace "$NAMESPACE" \
        -f tests/fixtures/postgresql/values-test.yaml \
        --wait --timeout 5m
    assert_success
}

@test "[$CHART_NAME] Data persists after pod restart" {
    # Verify test data exists
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -d testdb -c "SELECT name FROM test WHERE id=1" -t
    assert_success
    assert_output --partial "test"

    # Delete pod
    run kubectl delete pod -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0"
    assert_success

    # Wait for pod to restart
    kubectl wait --for=condition=Ready pod -n "$NAMESPACE" \
        -l "app.kubernetes.io/name=postgresql" --timeout=2m

    # Verify data still exists
    run kubectl exec -n "$NAMESPACE" "$RELEASE_NAME-postgresql-0" -- \
        psql -U postgres -d testdb -c "SELECT name FROM test WHERE id=1" -t
    assert_success
    assert_output --partial "test"
}
```

### Common Test Helpers

**tests/integration/common/helpers.bash:**
```bash
#!/usr/bin/env bash

# Skip test if feature is not enabled
skip_if_not_enabled() {
    local feature=$1
    local enabled=$(helm get values "$RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r ".$feature.enabled // false")

    if [ "$enabled" != "true" ]; then
        skip "Feature $feature is not enabled"
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}

    kubectl wait --for=condition=Available deployment/"$deployment" \
        -n "$namespace" --timeout="${timeout}s"
}

# Wait for statefulset to be ready
wait_for_statefulset() {
    local statefulset=$1
    local namespace=$2
    local replicas=${3:-1}
    local timeout=${4:-300}

    kubectl wait --for=jsonpath='{.status.readyReplicas}'="$replicas" \
        statefulset/"$statefulset" -n "$namespace" --timeout="${timeout}s"
}

# Get pod name by label
get_pod_name() {
    local namespace=$1
    local label=$2

    kubectl get pod -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}'
}

# Check if service is accessible
check_service_accessible() {
    local service=$1
    local namespace=$2
    local port=$3

    kubectl run -n "$namespace" curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
        curl -s -o /dev/null -w "%{http_code}" "http://$service:$port"
}

# Execute command in pod
exec_in_pod() {
    local pod=$1
    local namespace=$2
    shift 2
    local cmd=("$@")

    kubectl exec -n "$namespace" "$pod" -- "${cmd[@]}"
}

# Port forward to service
port_forward() {
    local service=$1
    local namespace=$2
    local local_port=$3
    local remote_port=$4

    kubectl port-forward -n "$namespace" "svc/$service" "$local_port:$remote_port" &
    local pid=$!
    sleep 2
    echo "$pid"
}

# Cleanup port forward
cleanup_port_forward() {
    local pid=$1
    kill "$pid" 2>/dev/null || true
}

# Get resource count
get_resource_count() {
    local resource=$1
    local namespace=$2
    local label=$3

    kubectl get "$resource" -n "$namespace" -l "$label" --no-headers 2>/dev/null | wc -l
}

# Check if resource exists
resource_exists() {
    local resource=$1
    local name=$2
    local namespace=$3

    kubectl get "$resource" "$name" -n "$namespace" &>/dev/null
}
```

### Test Execution Scripts

**tests/run-integration-tests.sh:**
```bash
#!/bin/bash
# Run integration tests for all charts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/integration"
PARALLEL="${PARALLEL:-true}"
TIER="${TIER:-all}"
CHART="${CHART:-}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== ScriptonBasestar Charts - Integration Test Suite ==="
echo "Tier: $TIER"
echo "Parallel: $PARALLEL"
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not found${NC}"
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}✗ helm not found${NC}"
        exit 1
    fi

    # Check bats
    if ! command -v bats &> /dev/null; then
        echo -e "${RED}✗ bats not found${NC}"
        echo "Install BATS: https://github.com/bats-core/bats-core"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# Run tests for a specific tier
run_tier_tests() {
    local tier=$1
    local tier_dir="$TEST_DIR/$tier"

    if [ ! -d "$tier_dir" ]; then
        echo -e "${YELLOW}⚠ Tier directory not found: $tier_dir${NC}"
        return 0
    fi

    echo "Running tests for $tier..."

    if [ "$PARALLEL" = "true" ]; then
        # Run tests in parallel
        find "$tier_dir" -name "*_test.bats" -print0 | \
            xargs -0 -P 4 -I {} bats "{}" --formatter tap | \
            tee "$SCRIPT_DIR/reports/${tier}-test-results.tap"
    else
        # Run tests sequentially
        bats "$tier_dir"/*.bats --formatter tap | \
            tee "$SCRIPT_DIR/reports/${tier}-test-results.tap"
    fi
}

# Run tests for specific chart
run_chart_test() {
    local chart=$1
    local test_file

    # Find test file for chart
    test_file=$(find "$TEST_DIR" -name "${chart}_test.bats" | head -1)

    if [ -z "$test_file" ]; then
        echo -e "${RED}✗ Test file not found for chart: $chart${NC}"
        exit 1
    fi

    echo "Running test for $chart..."
    bats "$test_file" --formatter tap | \
        tee "$SCRIPT_DIR/reports/${chart}-test-results.tap"
}

# Create reports directory
mkdir -p "$SCRIPT_DIR/reports"

# Run prerequisites check
check_prerequisites

# Run tests
if [ -n "$CHART" ]; then
    # Run tests for specific chart
    run_chart_test "$CHART"
elif [ "$TIER" = "all" ]; then
    # Run tests for all tiers
    for tier in tier1 tier2 tier3 tier4; do
        run_tier_tests "$tier"
    done
else
    # Run tests for specific tier
    run_tier_tests "$TIER"
fi

echo ""
echo "=== Test Execution Complete ==="
echo "Reports saved to: $SCRIPT_DIR/reports/"
```

---

## Upgrade Tests

### Upgrade Test Template

**tests/upgrade/keycloak_upgrade_test.sh:**
```bash
#!/bin/bash
# Upgrade test for Keycloak chart

set -e

NAMESPACE="test-upgrade-keycloak-$(date +%s)"
RELEASE_NAME="test-keycloak"
OLD_VERSION="0.3.0"
NEW_VERSION="0.4.0"

echo "=== Keycloak Upgrade Test: v$OLD_VERSION → v$NEW_VERSION ==="

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    kubectl delete namespace "$NAMESPACE" --wait=false || true
}

trap cleanup EXIT

# Step 1: Deploy old version
echo "[1/7] Deploying Keycloak v$OLD_VERSION..."
kubectl create namespace "$NAMESPACE"

helm install "$RELEASE_NAME" charts/keycloak \
    --version "$OLD_VERSION" \
    --namespace "$NAMESPACE" \
    -f tests/fixtures/keycloak/values-upgrade-test.yaml \
    --wait --timeout 10m

# Step 2: Verify old version is running
echo "[2/7] Verifying old version..."
kubectl wait --for=condition=Ready pod -n "$NAMESPACE" \
    -l "app.kubernetes.io/name=keycloak" --timeout=5m

POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/name=keycloak" -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    curl -f http://localhost:9000/health/ready || {
    echo "✗ Old version health check failed"
    exit 1
}

echo "✓ Old version is healthy"

# Step 3: Create test data
echo "[3/7] Creating test data..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user admin \
    --password admin

kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    /opt/keycloak/bin/kcadm.sh create realms \
    -s realm=test-upgrade \
    -s enabled=true

echo "✓ Test realm created"

# Step 4: Backup before upgrade
echo "[4/7] Creating backup..."
make -f make/ops/keycloak.mk kc-backup-all-realms \
    NAMESPACE="$NAMESPACE" \
    RELEASE="$RELEASE_NAME"

echo "✓ Backup created"

# Step 5: Upgrade to new version
echo "[5/7] Upgrading to v$NEW_VERSION..."
helm upgrade "$RELEASE_NAME" charts/keycloak \
    --version "$NEW_VERSION" \
    --namespace "$NAMESPACE" \
    -f tests/fixtures/keycloak/values-upgrade-test.yaml \
    --wait --timeout 10m

# Step 6: Verify new version is running
echo "[6/7] Verifying new version..."
kubectl wait --for=condition=Ready pod -n "$NAMESPACE" \
    -l "app.kubernetes.io/name=keycloak" --timeout=5m

POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/name=keycloak" -o jsonpath='{.items[0].metadata.name}')

# Health check on new management port (9000)
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    curl -f http://localhost:9000/health/ready || {
    echo "✗ New version health check failed"
    exit 1
}

echo "✓ New version is healthy"

# Step 7: Verify data integrity
echo "[7/7] Verifying data integrity..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user admin \
    --password admin

REALM_EXISTS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    /opt/keycloak/bin/kcadm.sh get realms/test-upgrade -F realm 2>/dev/null | grep -c "test-upgrade" || echo "0")

if [ "$REALM_EXISTS" != "1" ]; then
    echo "✗ Test realm not found after upgrade"
    exit 1
fi

echo "✓ Test realm persisted after upgrade"

echo ""
echo "=== Upgrade Test Passed ==="
echo "Successfully upgraded from v$OLD_VERSION to v$NEW_VERSION"
echo "Data integrity verified"
```

### Upgrade Test Matrix

**tests/upgrade/upgrade-matrix.yaml:**
```yaml
# Upgrade test matrix for all enhanced charts
charts:
  # Tier 1: Critical Infrastructure
  - name: postgresql
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "SELECT 1 FROM test_table"
        critical: true

  - name: mysql
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "SELECT 1 FROM test_table"
        critical: true

  - name: redis
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "GET test_key"
        critical: true

  - name: prometheus
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "query=up"
        critical: true

  - name: loki
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "query={job=\"test\"}"
        critical: true

  - name: tempo
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "traces query"
        critical: true

  # Tier 2: Application Platform
  - name: keycloak
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "realm=test-upgrade"
        critical: true

  - name: grafana
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "dashboard exists"
        critical: false

  - name: nextcloud
    versions:
      - from: "0.3.0"
        to: "0.4.0"
        data_check: "file exists"
        critical: false

  # Additional charts...
```

---

## Performance Tests

### Performance Test Template

**tests/performance/postgresql_perf_test.sh:**
```bash
#!/bin/bash
# Performance test for PostgreSQL chart

set -e

NAMESPACE="test-perf-postgresql-$(date +%s)"
RELEASE_NAME="test-pg-perf"
DURATION="60"  # seconds
REPORT_DIR="tests/performance/reports"

echo "=== PostgreSQL Performance Test ==="

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    kubectl delete namespace "$NAMESPACE" --wait=false || true
}

trap cleanup EXIT

# Deploy PostgreSQL
echo "[1/4] Deploying PostgreSQL..."
kubectl create namespace "$NAMESPACE"

helm install "$RELEASE_NAME" charts/postgresql \
    --namespace "$NAMESPACE" \
    -f tests/fixtures/postgresql/values-perf-test.yaml \
    --wait --timeout 5m

POD_NAME=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/name=postgresql" -o jsonpath='{.items[0].metadata.name}')

# Initialize pgbench database
echo "[2/4] Initializing pgbench database..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    createdb -U postgres pgbench

kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    pgbench -U postgres -i -s 10 pgbench

# Run performance test
echo "[3/4] Running performance test (${DURATION}s)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    pgbench -U postgres -c 10 -j 2 -T "$DURATION" pgbench > "$REPORT_DIR/postgresql-perf-$(date +%Y%m%d-%H%M%S).txt"

# Extract metrics
echo "[4/4] Extracting metrics..."
TPS=$(grep "tps" "$REPORT_DIR/postgresql-perf-"*.txt | tail -1 | awk '{print $3}')
LATENCY=$(grep "latency average" "$REPORT_DIR/postgresql-perf-"*.txt | tail -1 | awk '{print $4}')

# Get resource usage
CPU_USAGE=$(kubectl top pod -n "$NAMESPACE" "$POD_NAME" --no-headers | awk '{print $2}')
MEM_USAGE=$(kubectl top pod -n "$NAMESPACE" "$POD_NAME" --no-headers | awk '{print $3}')

# Generate report
cat > "$REPORT_DIR/postgresql-summary-$(date +%Y%m%d-%H%M%S).json" <<EOF
{
  "chart": "postgresql",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $DURATION,
  "performance": {
    "tps": $TPS,
    "latency_avg_ms": $LATENCY
  },
  "resources": {
    "cpu": "$CPU_USAGE",
    "memory": "$MEM_USAGE"
  },
  "baseline": {
    "tps_min": 500,
    "latency_max_ms": 10
  },
  "status": "$([ $(echo "$TPS > 500" | bc) -eq 1 ] && [ $(echo "$LATENCY < 10" | bc) -eq 1 ] && echo "PASS" || echo "FAIL")"
}
EOF

echo ""
echo "=== Performance Test Results ==="
echo "TPS: $TPS (baseline: >500)"
echo "Latency: ${LATENCY}ms (baseline: <10ms)"
echo "CPU Usage: $CPU_USAGE"
echo "Memory Usage: $MEM_USAGE"
echo ""
echo "Report saved to: $REPORT_DIR/"
```

### Performance Baseline Tracking

**tests/performance/baselines.yaml:**
```yaml
# Performance baselines for all enhanced charts
baselines:
  # Tier 1: Critical Infrastructure
  postgresql:
    tps_min: 500
    latency_max_ms: 10
    cpu_max: "500m"
    memory_max: "512Mi"
    connections_max: 100

  mysql:
    qps_min: 1000
    latency_max_ms: 5
    cpu_max: "500m"
    memory_max: "512Mi"
    connections_max: 150

  redis:
    ops_min: 50000
    latency_max_ms: 1
    cpu_max: "250m"
    memory_max: "256Mi"
    connections_max: 1000

  prometheus:
    query_latency_max_ms: 100
    ingestion_rate_min: 10000  # samples/sec
    cpu_max: "1000m"
    memory_max: "2Gi"

  # Tier 2: Application Platform
  keycloak:
    login_latency_max_ms: 500
    token_latency_max_ms: 100
    cpu_max: "1000m"
    memory_max: "1Gi"
    concurrent_users_min: 100

  grafana:
    dashboard_load_max_ms: 2000
    query_latency_max_ms: 500
    cpu_max: "500m"
    memory_max: "512Mi"

  # Additional charts...
```

---

## CI/CD Automation

### GitHub Actions Workflow

**.github/workflows/chart-testing.yaml:**
```yaml
name: Chart Testing

on:
  pull_request:
    branches:
      - master
      - main
    paths:
      - 'charts/**'
      - 'tests/**'
  push:
    branches:
      - master
      - main
    paths:
      - 'charts/**'

env:
  HELM_VERSION: v3.14.0
  K8S_VERSION: v1.28.0
  KIND_VERSION: v0.20.0

jobs:
  lint:
    name: Lint Charts
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: ${{ env.HELM_VERSION }}

      - name: Run Helm Lint
        run: |
          for chart in charts/*/; do
            echo "Linting $(basename $chart)..."
            helm lint "$chart" || exit 1
          done

      - name: Run Helm Template
        run: |
          for chart in charts/*/; do
            echo "Templating $(basename $chart)..."
            helm template test "$chart" > /dev/null || exit 1
          done

  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run Trivy Scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: 'charts/'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'

  integration-test:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: [lint, security-scan]
    strategy:
      matrix:
        tier: [tier1, tier2, tier3, tier4]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: ${{ env.HELM_VERSION }}

      - name: Set up kind
        uses: helm/kind-action@v1
        with:
          version: ${{ env.KIND_VERSION }}
          cluster_name: chart-testing
          node_image: kindest/node:${{ env.K8S_VERSION }}

      - name: Install BATS
        run: |
          git clone https://github.com/bats-core/bats-core.git
          cd bats-core
          sudo ./install.sh /usr/local

          # Install helpers
          mkdir -p tests/test_helper
          git clone https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
          git clone https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert

      - name: Run Integration Tests
        run: |
          chmod +x tests/run-integration-tests.sh
          TIER=${{ matrix.tier }} PARALLEL=false ./tests/run-integration-tests.sh

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results-${{ matrix.tier }}
          path: tests/reports/${{ matrix.tier }}-test-results.tap

  upgrade-test:
    name: Upgrade Tests
    runs-on: ubuntu-latest
    needs: [lint, security-scan]
    strategy:
      matrix:
        chart: [postgresql, mysql, redis, prometheus, keycloak]
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: ${{ env.HELM_VERSION }}

      - name: Set up kind
        uses: helm/kind-action@v1
        with:
          version: ${{ env.KIND_VERSION }}
          cluster_name: upgrade-testing
          node_image: kindest/node:${{ env.K8S_VERSION }}

      - name: Run Upgrade Test
        run: |
          chmod +x tests/upgrade/${{ matrix.chart }}_upgrade_test.sh
          ./tests/upgrade/${{ matrix.chart }}_upgrade_test.sh

  performance-test:
    name: Performance Tests
    runs-on: ubuntu-latest
    needs: [integration-test]
    if: github.event_name == 'push'
    strategy:
      matrix:
        chart: [postgresql, mysql, redis, prometheus]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: ${{ env.HELM_VERSION }}

      - name: Set up kind
        uses: helm/kind-action@v1
        with:
          version: ${{ env.KIND_VERSION }}
          cluster_name: perf-testing
          node_image: kindest/node:${{ env.K8S_VERSION }}

      - name: Install Metrics Server
        run: |
          kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
          kubectl patch -n kube-system deployment metrics-server --type=json \
            -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
          kubectl wait --for=condition=Available -n kube-system deployment/metrics-server --timeout=2m

      - name: Run Performance Test
        run: |
          chmod +x tests/performance/${{ matrix.chart }}_perf_test.sh
          ./tests/performance/${{ matrix.chart }}_perf_test.sh

      - name: Upload Performance Results
        uses: actions/upload-artifact@v3
        with:
          name: perf-results-${{ matrix.chart }}
          path: tests/performance/reports/

  release:
    name: Release Charts
    runs-on: ubuntu-latest
    needs: [integration-test, upgrade-test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/master'
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure Git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"

      - name: Install Helm
        uses: azure/setup-helm@v3
        with:
          version: ${{ env.HELM_VERSION }}

      - name: Run chart-releaser
        uses: helm/chart-releaser-action@v1.6.0
        env:
          CR_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
```

---

## Test Utilities

### Chart Test Utility Script

**tests/helpers/chart-tester.sh:**
```bash
#!/bin/bash
# Chart testing utility script

set -e

# Configuration
CHART_NAME=""
NAMESPACE=""
RELEASE_NAME=""
VALUES_FILE=""
TIMEOUT="5m"
SKIP_CLEANUP="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --chart)
            CHART_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --values)
            VALUES_FILE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --skip-cleanup)
            SKIP_CLEANUP="true"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$CHART_NAME" ]; then
    echo "Error: --chart is required"
    exit 1
fi

# Set defaults
NAMESPACE="${NAMESPACE:-test-$CHART_NAME-$(date +%s)}"
RELEASE_NAME="${RELEASE_NAME:-test-$CHART_NAME}"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup function
cleanup() {
    if [ "$SKIP_CLEANUP" = "false" ]; then
        echo "Cleaning up..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
        kubectl delete namespace "$NAMESPACE" --wait=false || true
    fi
}

trap cleanup EXIT

# Test functions
test_helm_lint() {
    echo -n "Testing Helm lint... "
    if helm lint "charts/$CHART_NAME" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

test_helm_template() {
    echo -n "Testing Helm template... "
    local extra_args=""
    [ -n "$VALUES_FILE" ] && extra_args="-f $VALUES_FILE"

    if helm template "$RELEASE_NAME" "charts/$CHART_NAME" $extra_args &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

test_chart_install() {
    echo -n "Testing chart installation... "
    kubectl create namespace "$NAMESPACE" &>/dev/null || true

    local extra_args="--wait --timeout $TIMEOUT"
    [ -n "$VALUES_FILE" ] && extra_args="$extra_args -f $VALUES_FILE"

    if helm install "$RELEASE_NAME" "charts/$CHART_NAME" -n "$NAMESPACE" $extra_args &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

test_pods_running() {
    echo -n "Testing pods are running... "
    local pods_ready=$(kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name' | wc -l)

    if [ "$pods_ready" -gt 0 ]; then
        echo -e "${GREEN}✓ ($pods_ready pods)${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

test_services_exist() {
    echo -n "Testing services exist... "
    local services=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    if [ "$services" -gt 0 ]; then
        echo -e "${GREEN}✓ ($services services)${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Run all tests
echo "=== Chart Testing Utility ==="
echo "Chart: $CHART_NAME"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

FAILED=0

test_helm_lint || ((FAILED++))
test_helm_template || ((FAILED++))
test_chart_install || ((FAILED++))
sleep 5  # Allow pods to start
test_pods_running || ((FAILED++))
test_services_exist || ((FAILED++))

echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}=== All Tests Passed ===${NC}"
    exit 0
else
    echo -e "${RED}=== $FAILED Test(s) Failed ===${NC}"
    exit 1
fi
```

---

## Best Practices

### 1. Test Organization

**DO:**
- ✅ Organize tests by tier (tier1-4)
- ✅ Use descriptive test names
- ✅ Keep tests independent
- ✅ Use fixtures for test data
- ✅ Clean up after each test

**DON'T:**
- ❌ Mix integration and unit tests
- ❌ Create test dependencies
- ❌ Leave test namespaces running
- ❌ Hard-code test values
- ❌ Skip cleanup on failure

### 2. Test Execution

**Parallel Execution:**
```bash
# Run tests in parallel (faster)
PARALLEL=true ./tests/run-integration-tests.sh

# Run tests sequentially (easier debugging)
PARALLEL=false ./tests/run-integration-tests.sh
```

**Selective Testing:**
```bash
# Test specific tier
TIER=tier1 ./tests/run-integration-tests.sh

# Test specific chart
CHART=postgresql ./tests/run-integration-tests.sh
```

### 3. CI/CD Integration

**Branch Protection:**
- Require all tests to pass before merge
- Require security scan to pass
- Require code review approval

**Performance Baselines:**
- Track performance metrics over time
- Alert on performance degradation
- Update baselines after optimization

### 4. Test Maintenance

**Regular Updates:**
- Update tests when charts change
- Review test coverage monthly
- Update baselines quarterly
- Archive old test reports

**Documentation:**
- Document test purpose
- Document test data requirements
- Document known failures
- Document troubleshooting steps

---

**Document Version**: 1.0.0
**Last Updated**: 2025-12-09
**Test Coverage**: 39 charts (100%)
