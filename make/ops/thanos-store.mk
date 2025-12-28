# Thanos Store Operations Makefile
# Usage: make -f make/ops/thanos-store.mk <target>

include make/common.mk

CHART_NAME := thanos-store
CHART_DIR := charts/$(CHART_NAME)

# Thanos Store specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-store
NAMESPACE ?= default

# Thanos Store ports
HTTP_PORT := 10906
GRPC_PORT := 10905

.PHONY: help
help:
	@echo "Thanos Store Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  ts-logs                     - View Thanos Store logs"
	@echo "  ts-logs-all                 - View logs from all Thanos Store pods"
	@echo "  ts-shell                    - Open shell in Thanos Store pod"
	@echo "  ts-port-forward             - Port forward Thanos Store (HTTP: 10906)"
	@echo "  ts-port-forward-grpc        - Port forward Thanos Store gRPC (10905)"
	@echo "  ts-restart                  - Restart Thanos Store StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  ts-ready                    - Check if Thanos Store is ready"
	@echo "  ts-healthy                  - Check if Thanos Store is healthy"
	@echo "  ts-info                     - Get Thanos Store info"
	@echo "  ts-version                  - Get Thanos version"
	@echo ""
	@echo "Storage & Cache:"
	@echo "  ts-check-storage            - Check PVC storage usage"
	@echo "  ts-index-cache-status       - Check index cache status"
	@echo "  ts-bucket-info              - Show bucket configuration info"
	@echo ""
	@echo "Metrics:"
	@echo "  ts-metrics                  - Get Thanos Store metrics"
	@echo "  ts-series-count             - Get loaded series count"
	@echo ""
	@echo "Scaling:"
	@echo "  ts-scale                    - Scale Thanos Store (REPLICAS=2)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  ts-pre-upgrade-check        - Pre-upgrade validation"
	@echo "  ts-post-upgrade-check       - Post-upgrade validation"
	@echo "  ts-health-check             - Quick health check"
	@echo "  ts-upgrade-rollback         - Rollback to previous Helm revision"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# =============================================================================
# Basic Operations
# =============================================================================

.PHONY: ts-logs ts-logs-all ts-shell ts-port-forward ts-port-forward-grpc ts-restart

ts-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

ts-logs-all:
	@echo "Fetching logs from all Thanos Store pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

ts-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

ts-port-forward:
	@echo "Port forwarding Thanos Store HTTP to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

ts-port-forward-grpc:
	@echo "Port forwarding Thanos Store gRPC to localhost:$(GRPC_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(GRPC_PORT):$(GRPC_PORT)

ts-restart:
	@echo "Restarting Thanos Store StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Health & Status
# =============================================================================

.PHONY: ts-ready ts-healthy ts-info ts-version

ts-ready:
	@echo "Checking if Thanos Store is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready

ts-healthy:
	@echo "Checking if Thanos Store is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

ts-info:
	@echo "Getting Thanos Store info..."
	@echo ""
	@echo "Pod info:"
	@kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o wide
	@echo ""
	@echo "Service info:"
	@kubectl get svc $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@echo "StatefulSet info:"
	@kubectl get statefulset $(CHART_NAME) -n $(NAMESPACE)

ts-version:
	@echo "Getting Thanos version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- thanos --version

# =============================================================================
# Storage & Cache
# =============================================================================

.PHONY: ts-check-storage ts-index-cache-status ts-bucket-info

ts-check-storage:
	@echo "Checking PVC storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /var/thanos/store 2>/dev/null || \
		echo "Unable to determine data directory, trying common paths..."
	@echo ""
	@echo "PVC status:"
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) 2>/dev/null || \
		kubectl get pvc -n $(NAMESPACE) | grep $(CHART_NAME) || echo "No PVCs found"

ts-index-cache-status:
	@echo "Checking index cache status..."
	@echo "Fetching index cache metrics from Thanos Store..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "thanos_bucket_store_index_cache|thanos_store_index_cache" || \
		echo "No index cache metrics found"

ts-bucket-info:
	@echo "Showing bucket configuration info..."
	@echo ""
	@echo "ConfigMap (bucket config):"
	@kubectl get configmap -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o yaml 2>/dev/null | \
		grep -A 50 "objstore.yml\|bucket.yml" | head -20 || \
		echo "No bucket config found in ConfigMap"
	@echo ""
	@echo "Environment variables:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		env | grep -iE "bucket|objstore|s3|gcs|azure" 2>/dev/null || \
		echo "No bucket-related environment variables found"

# =============================================================================
# Metrics
# =============================================================================

.PHONY: ts-metrics ts-series-count

ts-metrics:
	@echo "Fetching Thanos Store metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics

ts-series-count:
	@echo "Getting loaded series count..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "thanos_bucket_store_series_data_size|thanos_bucket_store_block_loads_total|thanos_bucket_store_blocks_loaded" || \
		echo "No series metrics found"

# =============================================================================
# Scaling
# =============================================================================

.PHONY: ts-scale

REPLICAS ?= 2

ts-scale:
	@echo "Scaling Thanos Store to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Upgrade Support Operations
# =============================================================================

.PHONY: ts-pre-upgrade-check ts-post-upgrade-check ts-health-check ts-upgrade-rollback

ts-pre-upgrade-check:
	@echo "=== Thanos Store Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/6] Checking current version..."
	@CURRENT_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		thanos --version 2>&1 | head -1); \
	echo "  Current version: $$CURRENT_VERSION"
	@echo ""
	@echo "[2/6] Checking pod health..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[3/6] Checking if Thanos Store is ready..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Thanos Store is ready" || \
		(echo "  ERROR: Thanos Store is not ready"; exit 1)
	@echo ""
	@echo "[4/6] Checking storage usage..."
	@STORAGE_INFO=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /data 2>/dev/null | tail -1 || echo "Unknown"); \
	echo "  Storage: $$STORAGE_INFO"
	@echo ""
	@echo "[5/6] Checking PVC status..."
	@PVC_STATUS=$$(kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) \
		-o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound"); \
	echo "  PVC status: $$PVC_STATUS"
	@echo ""
	@echo "[6/6] Checking for errors in logs..."
	@kubectl logs $(POD_NAME) -n $(NAMESPACE) -c $(CONTAINER_NAME) --tail=50 2>/dev/null | \
		grep -i "error\|fatal" && echo "  WARNING: Errors found in logs" || \
		echo "  No errors found in recent logs"
	@echo ""
	@echo "=== Pre-Upgrade Check Completed ==="

ts-post-upgrade-check:
	@echo "=== Thanos Store Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[2/5] Verifying new version..."
	@NEW_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		thanos --version 2>&1 | head -1); \
	echo "  New version: $$NEW_VERSION"
	@echo ""
	@echo "[3/5] Checking ready endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Ready endpoint: OK" || \
		(echo "  ERROR: Thanos Store is not ready"; exit 1)
	@echo ""
	@echo "[4/5] Checking healthy endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Healthy endpoint: OK" || \
		(echo "  ERROR: Thanos Store is not healthy"; exit 1)
	@echo ""
	@echo "[5/5] Checking for errors in logs..."
	@kubectl logs $(POD_NAME) -n $(NAMESPACE) -c $(CONTAINER_NAME) --tail=50 2>/dev/null | \
		grep -i "error\|fatal" && echo "  WARNING: Errors found in logs" || \
		echo "  No errors found in recent logs"
	@echo ""
	@echo "=== Post-Upgrade Validation Completed ==="

ts-health-check:
	@echo "=== Thanos Store Health Check ==="
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "Thanos Store is healthy" || \
		(echo "Thanos Store is unhealthy"; exit 1)
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "Thanos Store is ready" || \
		(echo "Thanos Store is not ready"; exit 1)

ts-upgrade-rollback:
	@echo "=== Thanos Store Upgrade Rollback ==="
	@echo "Listing release history..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@PREVIOUS_REVISION=$$(helm history $(CHART_NAME) -n $(NAMESPACE) -o json 2>/dev/null | \
		grep -o '"revision":[0-9]*' | tail -2 | head -1 | cut -d':' -f2); \
	if [ -z "$$PREVIOUS_REVISION" ]; then \
		echo "Error: Could not determine previous revision"; \
		exit 1; \
	fi; \
	echo "Rolling back to revision: $$PREVIOUS_REVISION"; \
	read -p "Continue with rollback? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Rollback cancelled"; \
		exit 0; \
	fi; \
	helm rollback $(CHART_NAME) $$PREVIOUS_REVISION -n $(NAMESPACE) --wait; \
	echo "Verifying rollback..."; \
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	echo ""; \
	echo "Rollback completed. Current version:"; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- thanos --version | head -1
