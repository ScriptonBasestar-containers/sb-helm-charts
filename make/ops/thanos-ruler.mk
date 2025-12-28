# Thanos Ruler Operations Makefile
# Usage: make -f make/ops/thanos-ruler.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := thanos-ruler
CHART_DIR := charts/$(CHART_NAME)

# Thanos Ruler specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-ruler
NAMESPACE ?= default
HTTP_PORT ?= 10911
GRPC_PORT ?= 10910

.PHONY: help
help:
	@echo "Thanos Ruler Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tru-logs                    - View Thanos Ruler logs"
	@echo "  tru-logs-all                - View logs from all Thanos Ruler pods"
	@echo "  tru-shell                   - Open shell in Thanos Ruler pod"
	@echo "  tru-port-forward            - Port forward Thanos Ruler HTTP ($(HTTP_PORT))"
	@echo "  tru-port-forward-grpc       - Port forward Thanos Ruler gRPC ($(GRPC_PORT))"
	@echo "  tru-restart                 - Restart Thanos Ruler StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  tru-ready                   - Check if Thanos Ruler is ready"
	@echo "  tru-healthy                 - Check if Thanos Ruler is healthy"
	@echo "  tru-status                  - Show StatefulSet and pods status"
	@echo ""
	@echo "Rules & Alerts:"
	@echo "  tru-rules                   - List all rules (GET /api/v1/rules)"
	@echo "  tru-alerts                  - Show active alerts (GET /api/v1/alerts)"
	@echo "  tru-reload                  - Reload rule configuration"
	@echo ""
	@echo "Storage:"
	@echo "  tru-check-storage           - Check PVC usage"
	@echo ""
	@echo "Scaling:"
	@echo "  tru-scale                   - Scale Thanos Ruler (REPLICAS=2)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  tru-pre-upgrade-check       - Pre-upgrade validation"
	@echo "  tru-post-upgrade-check      - Post-upgrade validation"
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

.PHONY: tru-logs tru-logs-all tru-shell tru-port-forward tru-port-forward-grpc tru-restart

tru-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tru-logs-all:
	@echo "Fetching logs from all Thanos Ruler pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tru-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tru-port-forward:
	@echo "Port forwarding Thanos Ruler HTTP to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tru-port-forward-grpc:
	@echo "Port forwarding Thanos Ruler gRPC to localhost:$(GRPC_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(GRPC_PORT):$(GRPC_PORT)

tru-restart:
	@echo "Restarting Thanos Ruler StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Health & Status
# =============================================================================

.PHONY: tru-ready tru-healthy tru-status

tru-ready:
	@echo "Checking if Thanos Ruler is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready

tru-healthy:
	@echo "Checking if Thanos Ruler is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

tru-status:
	@echo "StatefulSet status:"
	kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

# =============================================================================
# Rules & Alerts
# =============================================================================

.PHONY: tru-rules tru-alerts tru-reload

tru-rules:
	@echo "Listing all rules..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/rules

tru-alerts:
	@echo "Showing active alerts..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/alerts

tru-reload:
	@echo "Reloading Thanos Ruler configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --post-data='' http://localhost:$(HTTP_PORT)/-/reload

# =============================================================================
# Storage
# =============================================================================

.PHONY: tru-check-storage

tru-check-storage:
	@echo "Checking PVC storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || echo "No /data mount found"

# =============================================================================
# Scaling
# =============================================================================

.PHONY: tru-scale

REPLICAS ?= 2

tru-scale:
	@echo "Scaling Thanos Ruler to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Upgrade Support
# =============================================================================

.PHONY: tru-pre-upgrade-check tru-post-upgrade-check

tru-pre-upgrade-check:
	@echo "=== Thanos Ruler Pre-Upgrade Check ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[2/5] Checking ready endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Ready: OK" || \
		(echo "  ERROR: Thanos Ruler is not ready"; exit 1)
	@echo ""
	@echo "[3/5] Checking healthy endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Healthy: OK" || \
		echo "  WARNING: Healthy check failed"
	@echo ""
	@echo "[4/5] Checking loaded rules..."
	@RULES_STATUS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/api/v1/rules 2>/dev/null); \
	if [ -n "$$RULES_STATUS" ]; then \
		echo "  Rules endpoint: OK"; \
	else \
		echo "  WARNING: Could not fetch rules"; \
	fi
	@echo ""
	@echo "[5/5] Checking storage..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /data 2>/dev/null | tail -1 || echo "  Using external storage"
	@echo ""
	@echo "=== Pre-Upgrade Check Completed ==="

tru-post-upgrade-check:
	@echo "=== Thanos Ruler Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$(CHART_NAME) \
		-n $(NAMESPACE) --timeout=300s && \
		echo "  All pods are ready" || \
		(echo "  ERROR: Pods not ready"; exit 1)
	@echo ""
	@echo "[2/5] Checking ready endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Ready: OK" || \
		(echo "  ERROR: Thanos Ruler is not ready"; exit 1)
	@echo ""
	@echo "[3/5] Checking healthy endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Healthy: OK" || \
		echo "  WARNING: Healthy check failed"
	@echo ""
	@echo "[4/5] Verifying rules are loaded..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/api/v1/rules >/dev/null 2>&1 && \
		echo "  Rules loaded: OK" || \
		echo "  WARNING: Could not verify rules"
	@echo ""
	@echo "[5/5] Checking for errors in logs..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --since=5m 2>/dev/null | grep -i error | wc -l); \
	if [ $$ERROR_COUNT -eq 0 ]; then \
		echo "  No errors in last 5 minutes"; \
	else \
		echo "  WARNING: Found $$ERROR_COUNT error(s) in logs"; \
	fi
	@echo ""
	@echo "=== Post-Upgrade Validation Completed ==="
