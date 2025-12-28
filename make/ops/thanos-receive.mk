# Thanos Receive Operations Makefile
# Usage: make -f make/ops/thanos-receive.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := thanos-receive
CHART_DIR := charts/$(CHART_NAME)

# Thanos Receive specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-receive
NAMESPACE ?= default

# Port definitions
HTTP_PORT ?= 10909
GRPC_PORT ?= 10907
REMOTE_WRITE_PORT ?= 10908

.PHONY: help
help:
	@echo "Thanos Receive Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tr-logs                     - View Thanos Receive logs"
	@echo "  tr-logs-all                 - View logs from all Thanos Receive pods"
	@echo "  tr-shell                    - Open shell in Thanos Receive pod"
	@echo "  tr-port-forward             - Port forward HTTP ($(HTTP_PORT))"
	@echo "  tr-port-forward-grpc        - Port forward gRPC ($(GRPC_PORT))"
	@echo "  tr-port-forward-remote-write - Port forward remote write ($(REMOTE_WRITE_PORT))"
	@echo "  tr-restart                  - Restart Thanos Receive StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  tr-ready                    - Check if Thanos Receive is ready"
	@echo "  tr-healthy                  - Check if Thanos Receive is healthy"
	@echo "  tr-metrics                  - Get Prometheus metrics"
	@echo "  tr-config                   - Show current configuration flags"
	@echo ""
	@echo "Thanos-Specific:"
	@echo "  tr-hashring                 - Show hashring status"
	@echo "  tr-tenants                  - List tenants (multi-tenancy mode)"
	@echo "  tr-check-storage            - Check PVC storage usage"
	@echo "  tr-remote-write-test        - Test remote write endpoint"
	@echo ""
	@echo "Scaling:"
	@echo "  tr-scale                    - Scale Thanos Receive (REPLICAS=3)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  tr-pre-upgrade-check        - Pre-upgrade validation"
	@echo "  tr-post-upgrade-check       - Post-upgrade validation"
	@echo "  tr-upgrade-rollback         - Rollback to previous Helm revision"
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

.PHONY: tr-logs tr-logs-all tr-shell tr-port-forward tr-port-forward-grpc tr-port-forward-remote-write tr-restart

tr-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tr-logs-all:
	@echo "Fetching logs from all Thanos Receive pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tr-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tr-port-forward:
	@echo "Port forwarding Thanos Receive HTTP to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tr-port-forward-grpc:
	@echo "Port forwarding Thanos Receive gRPC to localhost:$(GRPC_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(GRPC_PORT):$(GRPC_PORT)

tr-port-forward-remote-write:
	@echo "Port forwarding Thanos Receive remote write to localhost:$(REMOTE_WRITE_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(REMOTE_WRITE_PORT):$(REMOTE_WRITE_PORT)

tr-restart:
	@echo "Restarting Thanos Receive StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Health & Status
# =============================================================================

.PHONY: tr-ready tr-healthy tr-metrics tr-config

tr-ready:
	@echo "Checking if Thanos Receive is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready

tr-healthy:
	@echo "Checking if Thanos Receive is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

tr-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/metrics

tr-config:
	@echo "Showing current configuration flags..."
	@kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n'
	@echo ""

# =============================================================================
# Thanos-Specific Operations
# =============================================================================

.PHONY: tr-hashring tr-tenants tr-check-storage tr-remote-write-test

tr-hashring:
	@echo "Showing hashring status..."
	@echo "Checking hashring ConfigMap..."
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-hashring -o yaml 2>/dev/null || \
		echo "Hashring ConfigMap not found (using default or file-based config)"
	@echo ""
	@echo "Checking active receive replicas..."
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

tr-tenants:
	@echo "Listing tenants (multi-tenancy mode)..."
	@echo "Note: Tenants are determined by X-Scope-OrgID header in remote write requests"
	@echo ""
	@echo "Checking recent tenant activity from logs..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i "tenant" || \
		echo "No tenant activity found in recent logs"
	@echo ""
	@echo "To enable multi-tenancy, configure:"
	@echo "  --receive.tenant-header=X-Scope-OrgID"
	@echo "  --receive.default-tenant-id=default-tenant"

tr-check-storage:
	@echo "Checking PVC storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /var/thanos/receive 2>/dev/null || \
		echo "Data directory not found at /data or /var/thanos/receive"
	@echo ""
	@echo "PVC Status:"
	kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

TENANT ?= default-tenant

tr-remote-write-test:
	@echo "Testing remote write endpoint..."
	@echo "Remote write URL: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:$(REMOTE_WRITE_PORT)/api/v1/receive"
	@echo ""
	@echo "Example Prometheus remote_write configuration:"
	@echo "remote_write:"
	@echo "  - url: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:$(REMOTE_WRITE_PORT)/api/v1/receive"
	@echo "    headers:"
	@echo "      X-Scope-OrgID: $(TENANT)"
	@echo ""
	@echo "Testing endpoint availability..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(REMOTE_WRITE_PORT)/-/ready && \
		echo "Remote write endpoint is ready" || echo "Remote write endpoint not responding"

# =============================================================================
# Scaling
# =============================================================================

.PHONY: tr-scale

REPLICAS ?= 3

tr-scale:
	@echo "Scaling Thanos Receive to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@echo "Note: Update hashring configuration if needed for proper distribution"

# =============================================================================
# Upgrade Support
# =============================================================================

.PHONY: tr-pre-upgrade-check tr-post-upgrade-check tr-upgrade-rollback

tr-pre-upgrade-check:
	@echo "=== Thanos Receive Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/7] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}' 2>/dev/null); \
	if [ "$$POD_STATUS" = "Running" ]; then \
		echo "  Pod status: $$POD_STATUS"; \
	else \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi
	@echo ""
	@echo "[2/7] Checking health..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Thanos Receive is healthy" || \
		(echo "  ERROR: Thanos Receive is unhealthy"; exit 1)
	@echo ""
	@echo "[3/7] Checking readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Thanos Receive is ready" || \
		(echo "  ERROR: Thanos Receive is not ready"; exit 1)
	@echo ""
	@echo "[4/7] Checking storage usage..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /data 2>/dev/null | tail -1 || echo "  Storage check skipped (S3 mode)"
	@echo ""
	@echo "[5/7] Checking PVC status..."
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) || echo "  No PVCs found"
	@echo ""
	@echo "[6/7] Checking for recent errors..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i error | wc -l); \
	if [ $$ERROR_COUNT -eq 0 ]; then \
		echo "  No errors in recent logs"; \
	else \
		echo "  WARNING: Found $$ERROR_COUNT error messages in recent logs"; \
	fi
	@echo ""
	@echo "[7/7] Checking hashring configuration..."
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-hashring -o jsonpath='{.data}' 2>/dev/null || \
		echo "  Using default hashring configuration"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo "Recommendations:"
	@echo "  1. Create backup if using local storage"
	@echo "  2. Review Thanos Receive release notes"
	@echo "  3. Ensure hashring configuration is compatible"

tr-post-upgrade-check:
	@echo "=== Thanos Receive Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/6] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "[2/6] Checking health..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  Thanos Receive is healthy" || \
		(echo "  ERROR: Thanos Receive is unhealthy"; exit 1)
	@echo ""
	@echo "[3/6] Checking readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Thanos Receive is ready" || \
		(echo "  ERROR: Thanos Receive is not ready"; exit 1)
	@echo ""
	@echo "[4/6] Checking remote write port..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(REMOTE_WRITE_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Remote write endpoint is ready" || \
		echo "  WARNING: Remote write endpoint not responding"
	@echo ""
	@echo "[5/6] Checking for errors in logs..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --since=5m | grep -i error | wc -l); \
	if [ $$ERROR_COUNT -eq 0 ]; then \
		echo "  No errors in last 5 minutes"; \
	else \
		echo "  WARNING: Found $$ERROR_COUNT error messages"; \
		echo "  Review logs: make -f make/ops/thanos-receive.mk tr-logs"; \
	fi
	@echo ""
	@echo "[6/6] Checking gRPC store connectivity..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		netstat -ln 2>/dev/null | grep $(GRPC_PORT) && \
		echo "  gRPC port $(GRPC_PORT) is listening" || \
		echo "  gRPC port check skipped (netstat not available)"
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

tr-upgrade-rollback:
	@echo "=== Thanos Receive Upgrade Rollback ==="
	@echo "Listing Helm revisions..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Enter revision number to rollback to: " REVISION; \
	if [ -n "$$REVISION" ]; then \
		echo "Rolling back to revision $$REVISION..."; \
		helm rollback $(CHART_NAME) $$REVISION -n $(NAMESPACE); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
		echo "Rollback complete"; \
		$(MAKE) -f make/ops/thanos-receive.mk tr-post-upgrade-check; \
	else \
		echo "Rollback cancelled"; \
	fi
