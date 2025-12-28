# Thanos Query Operations Makefile
# Usage: make -f make/ops/thanos-query.mk <target>

include make/Makefile.common.mk

CHART_NAME := thanos-query
CHART_DIR := charts/$(CHART_NAME)

# Thanos Query specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-query
NAMESPACE ?= default
HTTP_PORT ?= 10904
GRPC_PORT ?= 10903

.PHONY: help
help:
	@echo "Thanos Query Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tq-logs                     - View Thanos Query logs"
	@echo "  tq-logs-all                 - View logs from all Thanos Query pods"
	@echo "  tq-shell                    - Open shell in Thanos Query pod"
	@echo "  tq-port-forward             - Port forward Thanos Query HTTP ($(HTTP_PORT))"
	@echo "  tq-port-forward-grpc        - Port forward Thanos Query gRPC ($(GRPC_PORT))"
	@echo "  tq-restart                  - Restart Thanos Query Deployment"
	@echo ""
	@echo "Health & Status:"
	@echo "  tq-ready                    - Check if Thanos Query is ready"
	@echo "  tq-healthy                  - Check if Thanos Query is healthy"
	@echo "  tq-version                  - Get Thanos version"
	@echo "  tq-config                   - Show current Thanos Query configuration"
	@echo ""
	@echo "Store & Discovery:"
	@echo "  tq-stores                   - List connected stores"
	@echo "  tq-stores-detailed          - List stores with detailed info"
	@echo "  tq-targets                  - List targets (if target discovery enabled)"
	@echo "  tq-exemplars                - List exemplars (if supported)"
	@echo ""
	@echo "Metrics & Queries:"
	@echo "  tq-query                    - Execute PromQL query (QUERY='up')"
	@echo "  tq-query-range              - Execute range query (QUERY='up' START='-1h' END='now' STEP='15s')"
	@echo "  tq-labels                   - List all label names"
	@echo "  tq-label-values             - Get values for a label (LABEL=job)"
	@echo "  tq-series                   - List time series (MATCH='{job=\"prometheus\"}')"
	@echo "  tq-metrics                  - Get Thanos Query own metrics"
	@echo ""
	@echo "Testing:"
	@echo "  tq-test-query               - Run sample queries to verify Thanos Query"
	@echo ""
	@echo "Scaling:"
	@echo "  tq-scale                    - Scale Thanos Query (REPLICAS=2)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  tq-pre-upgrade-check        - Pre-upgrade validation"
	@echo "  tq-post-upgrade-check       - Post-upgrade validation"
	@echo "  tq-health-check             - Quick health check"
	@echo "  tq-upgrade-rollback         - Rollback to previous Helm revision"
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

.PHONY: tq-logs tq-logs-all tq-shell tq-port-forward tq-port-forward-grpc tq-restart

tq-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tq-logs-all:
	@echo "Fetching logs from all Thanos Query pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tq-shell:
	@echo "Opening shell in Thanos Query pod..."
	kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- /bin/sh

tq-port-forward:
	@echo "Port forwarding Thanos Query HTTP to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tq-port-forward-grpc:
	@echo "Port forwarding Thanos Query gRPC to localhost:$(GRPC_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(GRPC_PORT):$(GRPC_PORT)

tq-restart:
	@echo "Restarting Thanos Query Deployment..."
	kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Health & Status
# =============================================================================

.PHONY: tq-ready tq-healthy tq-version tq-config

tq-ready:
	@echo "Checking if Thanos Query is ready..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready

tq-healthy:
	@echo "Checking if Thanos Query is healthy..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

tq-version:
	@echo "Getting Thanos version..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- thanos --version

tq-config:
	@echo "Showing Thanos Query configuration (from pod environment)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- printenv | grep -E '^(THANOS|GRPC|HTTP|LOG)' | sort

# =============================================================================
# Store & Discovery
# =============================================================================

.PHONY: tq-stores tq-stores-detailed tq-targets tq-exemplars

tq-stores:
	@echo "Listing connected stores..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/stores

tq-stores-detailed:
	@echo "Listing stores with detailed info..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/stores 2>/dev/null | \
		grep -o '"name":"[^"]*"\|"labelSets":\[[^]]*\]\|"minTime":"[^"]*"\|"maxTime":"[^"]*"'

tq-targets:
	@echo "Listing targets (if target discovery enabled)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/targets 2>/dev/null || \
		echo "Targets API not available (may require targets discovery configuration)"

tq-exemplars:
	@echo "Listing exemplars..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- 'http://localhost:$(HTTP_PORT)/api/v1/query_exemplars?query=up' 2>/dev/null || \
		echo "Exemplars API not available"

# =============================================================================
# Metrics & Queries
# =============================================================================

.PHONY: tq-query tq-query-range tq-labels tq-label-values tq-series tq-metrics

QUERY ?= up
START ?= -1h
END ?= now
STEP ?= 15s
LABEL ?= job
MATCH ?= {job="prometheus"}

tq-query:
	@echo "Executing query: $(QUERY)"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

tq-query-range:
	@echo "Executing range query: $(QUERY) from $(START) to $(END) step $(STEP)"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- sh -c "wget -qO- 'http://localhost:$(HTTP_PORT)/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s 2>/dev/null || date -v$(START) +%s)&end=$$(date -d '$(END)' +%s 2>/dev/null || date +%s)&step=$(STEP)'"

tq-labels:
	@echo "Listing all label names..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/labels

tq-label-values:
	@echo "Getting values for label '$(LABEL)'..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/label/$(LABEL)/values

tq-series:
	@echo "Listing time series matching: $(MATCH)"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/series?match[]=$(MATCH)"

tq-metrics:
	@echo "Fetching Thanos Query own metrics..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/metrics

# =============================================================================
# Testing
# =============================================================================

.PHONY: tq-test-query

tq-test-query:
	@echo "Running sample queries..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	echo ""; \
	echo "1. Check 'up' metric:"; \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=up"; \
	echo ""; \
	echo ""; \
	echo "2. Count all time series:"; \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=count(up)"; \
	echo ""; \
	echo ""; \
	echo "3. List connected stores:"; \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/stores

# =============================================================================
# Scaling
# =============================================================================

.PHONY: tq-scale

REPLICAS ?= 2

tq-scale:
	@echo "Scaling Thanos Query to $(REPLICAS) replicas..."
	kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Upgrade Support Operations
# =============================================================================

.PHONY: tq-pre-upgrade-check tq-post-upgrade-check tq-health-check tq-upgrade-rollback

# Pre-upgrade validation
tq-pre-upgrade-check:
	@echo "=== Thanos Query Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/6] Checking current version..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	CURRENT_VERSION=$$(kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- thanos --version 2>&1 | head -1); \
	echo "  Current version: $$CURRENT_VERSION"
	@echo ""
	@echo "[2/6] Checking pod health..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	POD_STATUS=$$(kubectl get pod $$POD -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[3/6] Checking if Thanos Query is ready..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Thanos Query is ready" || \
		(echo "  ERROR: Thanos Query is not ready"; exit 1)
	@echo ""
	@echo "[4/6] Checking connected stores..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	STORES=$$(kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/api/v1/stores 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l); \
	echo "  Connected stores: $$STORES"
	@echo ""
	@echo "[5/6] Testing query execution..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=up" >/dev/null 2>&1 && \
		echo "  Query execution: OK" || \
		(echo "  ERROR: Query execution failed"; exit 1)
	@echo ""
	@echo "[6/6] Checking replica count..."
	@REPLICAS=$$(kubectl get deployment $(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.status.replicas}'); \
	READY=$$(kubectl get deployment $(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}'); \
	echo "  Replicas: $$READY/$$REPLICAS ready"
	@echo ""
	@echo "=== Pre-Upgrade Check Completed ==="
	@echo ""
	@echo "Next Steps:"
	@echo "  1. Review release notes for target version"
	@echo "  2. Proceed with upgrade strategy"

# Post-upgrade validation
tq-post-upgrade-check:
	@echo "=== Thanos Query Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	POD_STATUS=$$(kubectl get pod $$POD -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS"
	@echo ""
	@echo "[2/5] Verifying new version..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	NEW_VERSION=$$(kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- thanos --version 2>&1 | head -1); \
	echo "  New version: $$NEW_VERSION"
	@echo ""
	@echo "[3/5] Checking ready endpoint..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  Ready endpoint: OK" || \
		(echo "  ERROR: Thanos Query is not ready"; exit 1)
	@echo ""
	@echo "[4/5] Verifying connected stores..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	STORES=$$(kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/api/v1/stores 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l); \
	echo "  Connected stores: $$STORES"; \
	if [ $$STORES -eq 0 ]; then \
		echo "  WARNING: No stores connected!"; \
	fi
	@echo ""
	@echo "[5/5] Checking for errors in logs..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl logs $$POD -n $(NAMESPACE) -c $(CONTAINER_NAME) --tail=50 | \
		grep -i "error\|fatal" && echo "  WARNING: Errors found in logs" || \
		echo "  No errors found in recent logs"
	@echo ""
	@echo "=== Post-Upgrade Validation Completed ==="

# Health check (lightweight validation)
tq-health-check:
	@echo "=== Thanos Query Health Check ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "Thanos Query is healthy" || \
		(echo "Thanos Query is unhealthy"; exit 1)
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "Thanos Query is ready" || \
		(echo "Thanos Query is not ready"; exit 1)

# Rollback to previous Helm revision
tq-upgrade-rollback:
	@echo "=== Thanos Query Upgrade Rollback ==="
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
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	echo ""; \
	echo "Rollback completed."
