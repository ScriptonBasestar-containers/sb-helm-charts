# Thanos Compactor Operations Makefile
# Usage: make -f make/ops/thanos-compactor.mk <target>
#
# IMPORTANT: Thanos Compactor MUST run as a single replica!
# Running multiple compactors will cause data corruption.
# Do NOT scale this component.

include make/common.mk

CHART_NAME := thanos-compactor
CHART_DIR := charts/$(CHART_NAME)

# Thanos Compactor specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-compactor
NAMESPACE ?= default
HTTP_PORT := 10902

.PHONY: help
help:
	@echo "Thanos Compactor Operations"
	@echo ""
	@echo "*** WARNING: Compactor MUST run as single replica! ***"
	@echo "*** Running multiple compactors causes data corruption! ***"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tc-logs                     - View Thanos Compactor logs"
	@echo "  tc-shell                    - Open shell in Thanos Compactor pod"
	@echo "  tc-port-forward             - Port forward Thanos Compactor (10902)"
	@echo "  tc-restart                  - Restart Thanos Compactor StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  tc-ready                    - Check if Thanos Compactor is ready"
	@echo "  tc-healthy                  - Check if Thanos Compactor is healthy"
	@echo "  tc-status                   - Get compactor status and information"
	@echo ""
	@echo "Storage & Compaction:"
	@echo "  tc-check-storage            - Check work directory PVC usage (critical!)"
	@echo "  tc-progress                 - Show compaction progress"
	@echo "  tc-metrics                  - Fetch Prometheus metrics"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  tc-pre-upgrade-check        - Pre-upgrade validation"
	@echo "  tc-post-upgrade-check       - Post-upgrade validation"
	@echo "  tc-upgrade-rollback         - Rollback to previous Helm revision"
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

.PHONY: tc-logs tc-shell tc-port-forward tc-restart

tc-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tc-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tc-port-forward:
	@echo "Port forwarding Thanos Compactor to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tc-restart:
	@echo "Restarting Thanos Compactor StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Health & Status
# =============================================================================

.PHONY: tc-ready tc-healthy tc-status

tc-ready:
	@echo "Checking if Thanos Compactor is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready

tc-healthy:
	@echo "Checking if Thanos Compactor is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

tc-status:
	@echo "=== Thanos Compactor Status ==="
	@echo ""
	@echo "StatefulSet:"
	kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) -o wide
	@echo ""
	@echo "Pod:"
	kubectl get pod -n $(NAMESPACE) $(POD_NAME) -o wide
	@echo ""
	@echo "Health Check:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy 2>/dev/null && \
		echo "  Status: Healthy" || echo "  Status: Unhealthy"

# =============================================================================
# Storage & Compaction
# =============================================================================

.PHONY: tc-check-storage tc-progress tc-metrics

tc-check-storage:
	@echo "=== Thanos Compactor Work Directory Storage ==="
	@echo ""
	@echo "IMPORTANT: Compactor requires significant disk space for"
	@echo "downloading, deduplicating, and compacting blocks."
	@echo ""
	@echo "PVC Status:"
	kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "Disk Usage:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /
	@echo ""
	@echo "Work Directory Contents:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -la /data 2>/dev/null || \
		echo "  (Could not list /data directory)"

tc-progress:
	@echo "=== Thanos Compactor Progress ==="
	@echo ""
	@echo "Recent compaction activity (from metrics):"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "^thanos_compact_(group_compactions|garbage_collection)" | head -20
	@echo ""
	@echo "Block operations:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "^thanos_compact_blocks" | head -10

tc-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics

# =============================================================================
# Scaling Warning
# =============================================================================

.PHONY: tc-scale

tc-scale:
	@echo ""
	@echo "*** ERROR: Scaling Thanos Compactor is NOT allowed! ***"
	@echo ""
	@echo "Thanos Compactor MUST run as exactly 1 replica."
	@echo "Running multiple compactors against the same bucket will cause:"
	@echo "  - Data corruption"
	@echo "  - Block conflicts"
	@echo "  - Undefined behavior"
	@echo ""
	@echo "If you need horizontal scaling, consider:"
	@echo "  - Sharding by tenant (with separate buckets)"
	@echo "  - Using Thanos Receive with hash-ring for write distribution"
	@echo ""
	@exit 1

# =============================================================================
# Upgrade Operations
# =============================================================================

.PHONY: tc-pre-upgrade-check tc-post-upgrade-check tc-upgrade-rollback

tc-pre-upgrade-check:
	@echo "=== Thanos Compactor Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/5] Checking StatefulSet status..."
	@REPLICAS=$$(kubectl get statefulset $(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.replicas}'); \
	if [ "$$REPLICAS" != "1" ]; then \
		echo "  ERROR: Replica count is $$REPLICAS, must be 1!"; \
		exit 1; \
	fi; \
	echo "  Replica count: 1 (correct)"
	@echo ""
	@echo "[2/5] Checking pod health..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[3/5] Checking readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Readiness: OK" || \
		(echo "  ERROR: Compactor is not ready"; exit 1)
	@echo ""
	@echo "[4/5] Checking storage usage..."
	@STORAGE_USED=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /data 2>/dev/null | tail -1 | awk '{print $$5}' || echo "Unknown"); \
	echo "  Storage used: $$STORAGE_USED"
	@echo ""
	@echo "[5/5] Checking PVC status..."
	@PVC_STATUS=$$(kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) \
		-o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound"); \
	echo "  PVC status: $$PVC_STATUS"
	@echo ""
	@echo "=== Pre-Upgrade Check Completed ==="

tc-post-upgrade-check:
	@echo "=== Thanos Compactor Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/4] Checking pod status..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[2/4] Checking readiness endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Readiness: OK" || \
		(echo "  ERROR: Compactor is not ready"; exit 1)
	@echo ""
	@echo "[3/4] Checking health endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Health: OK" || \
		(echo "  ERROR: Compactor is not healthy"; exit 1)
	@echo ""
	@echo "[4/4] Checking for errors in logs..."
	@kubectl logs $(POD_NAME) -n $(NAMESPACE) -c $(CONTAINER_NAME) --tail=50 | \
		grep -i "error\|fatal" && echo "  WARNING: Errors found in logs" || \
		echo "  No errors found in recent logs"
	@echo ""
	@echo "=== Post-Upgrade Validation Completed ==="

tc-upgrade-rollback:
	@echo "=== Thanos Compactor Upgrade Rollback ==="
	@echo "Listing release history..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Are you sure you want to rollback? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		helm rollback $(CHART_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "Waiting for rollback to complete..." && \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "=== Rollback Complete ===" && \
		echo "" && \
		echo "Verify with:" && \
		echo "  make -f make/ops/thanos-compactor.mk tc-post-upgrade-check"; \
	else \
		echo "Rollback cancelled."; \
	fi
