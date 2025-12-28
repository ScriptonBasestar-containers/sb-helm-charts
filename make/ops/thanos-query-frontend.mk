# Thanos Query Frontend Operations Makefile
# Usage: make -f make/ops/thanos-query-frontend.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := thanos-query-frontend
CHART_DIR := charts/$(CHART_NAME)

# Thanos Query Frontend specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= thanos-query-frontend
NAMESPACE ?= default
HTTP_PORT ?= 10913

.PHONY: help
help:
	@echo "Thanos Query Frontend Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tqf-logs                    - View Thanos Query Frontend logs"
	@echo "  tqf-logs-all                - View logs from all pods"
	@echo "  tqf-shell                   - Open shell in pod"
	@echo "  tqf-port-forward            - Port forward HTTP ($(HTTP_PORT))"
	@echo "  tqf-restart                 - Restart deployment"
	@echo ""
	@echo "Health & Status:"
	@echo "  tqf-ready                   - Check if Query Frontend is ready"
	@echo "  tqf-healthy                 - Check if Query Frontend is healthy"
	@echo "  tqf-version                 - Get Thanos version"
	@echo "  tqf-config                  - Show current configuration"
	@echo "  tqf-metrics                 - Get Query Frontend metrics"
	@echo ""
	@echo "Query Operations:"
	@echo "  tqf-query                   - Execute query through frontend (QUERY='up')"
	@echo "  tqf-query-range             - Execute range query (QUERY='up' START='-1h' END='now' STEP='15s')"
	@echo "  tqf-labels                  - List all label names"
	@echo ""
	@echo "Cache Operations:"
	@echo "  tqf-cache-stats             - Show cache statistics (if available)"
	@echo ""
	@echo "Scaling:"
	@echo "  tqf-scale                   - Scale deployment (REPLICAS=2)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  tqf-pre-upgrade-check       - Pre-upgrade validation"
	@echo "  tqf-post-upgrade-check      - Post-upgrade validation"
	@echo "  tqf-health-check            - Quick health check"
	@echo "  tqf-upgrade-rollback        - Rollback to previous Helm revision"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: tqf-logs tqf-logs-all tqf-shell tqf-port-forward tqf-restart

tqf-logs:
	@echo "Fetching logs from $(CHART_NAME)..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tqf-logs-all:
	@echo "Fetching logs from all Thanos Query Frontend pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tqf-shell:
	@echo "Opening shell in $(CHART_NAME) pod..."
	kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- /bin/sh

tqf-port-forward:
	@echo "Port forwarding Thanos Query Frontend to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tqf-restart:
	@echo "Restarting Thanos Query Frontend deployment..."
	kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: tqf-ready tqf-healthy tqf-version tqf-config tqf-metrics

tqf-ready:
	@echo "Checking if Thanos Query Frontend is ready..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready

tqf-healthy:
	@echo "Checking if Thanos Query Frontend is healthy..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy

tqf-version:
	@echo "Getting Thanos version..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- thanos --version

tqf-config:
	@echo "Showing Query Frontend configuration..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- cat /etc/thanos/query-frontend.yaml 2>/dev/null || echo "Config file not found. Check container args."

tqf-metrics:
	@echo "Fetching Thanos Query Frontend metrics..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/metrics

# Query Operations
.PHONY: tqf-query tqf-query-range tqf-labels

QUERY ?= up
START ?= -1h
END ?= now
STEP ?= 15s

tqf-query:
	@echo "Executing query through frontend: $(QUERY)"
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

tqf-query-range:
	@echo "Executing range query through frontend: $(QUERY)"
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- sh -c "wget -qO- 'http://localhost:$(HTTP_PORT)/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s 2>/dev/null || date -v$(START) +%s)&end=$$(date -d '$(END)' +%s 2>/dev/null || date +%s)&step=$(STEP)'"

tqf-labels:
	@echo "Listing all label names..."
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/api/v1/labels

# Cache Operations
.PHONY: tqf-cache-stats

tqf-cache-stats:
	@echo "Showing cache statistics (from metrics)..."
	@echo "Cache hit/miss metrics:"
	kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | grep -E "thanos_query_frontend_cache|cortex_cache" || echo "No cache metrics found (caching may not be enabled)"

# Scaling
.PHONY: tqf-scale

REPLICAS ?= 2

tqf-scale:
	@echo "Scaling Thanos Query Frontend to $(REPLICAS) replicas..."
	kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# Upgrade Support
.PHONY: tqf-pre-upgrade-check tqf-post-upgrade-check tqf-health-check tqf-upgrade-rollback

tqf-pre-upgrade-check:
	@echo "=== Thanos Query Frontend Pre-Upgrade Check ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "[2/5] Checking health endpoints..."
	@$(MAKE) -f make/ops/thanos-query-frontend.mk tqf-health-check 2>/dev/null && echo "  Health: OK" || echo "  Health: FAILED"
	@echo ""
	@echo "[3/5] Checking current version..."
	@echo -n "  Version: "
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- thanos --version 2>&1 | head -1 || echo "Unable to get version"
	@echo ""
	@echo "[4/5] Checking replica count..."
	@echo -n "  Replicas: "
	@kubectl get deployment/$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'
	@echo ""
	@echo ""
	@echo "[5/5] Testing query endpoint..."
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=up" >/dev/null 2>&1 && echo "  Query: OK" || echo "  Query: FAILED"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="

tqf-post-upgrade-check:
	@echo "=== Thanos Query Frontend Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/5] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "[2/5] Verifying new version..."
	@echo -n "  Version: "
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- thanos --version 2>&1 | head -1 || echo "Unable to get version"
	@echo ""
	@echo "[3/5] Checking health endpoints..."
	@$(MAKE) -f make/ops/thanos-query-frontend.mk tqf-health-check 2>/dev/null && echo "  Health: OK" || echo "  Health: FAILED"
	@echo ""
	@echo "[4/5] Testing query endpoint..."
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:$(HTTP_PORT)/api/v1/query?query=up" >/dev/null 2>&1 && echo "  Query: OK" || echo "  Query: FAILED"
	@echo ""
	@echo "[5/5] Checking for errors in logs..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --since=5m 2>/dev/null | grep -i "error\|fatal" | wc -l); \
	if [ $$ERROR_COUNT -eq 0 ]; then \
		echo "  No errors in last 5 minutes"; \
	else \
		echo "  Found $$ERROR_COUNT error messages"; \
	fi
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

tqf-health-check:
	@echo "=== Thanos Query Frontend Health Check ==="
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && echo "Healthy: OK" || (echo "Healthy: FAILED"; exit 1)
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') -c $(CONTAINER_NAME) -- wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && echo "Ready: OK" || (echo "Ready: FAILED"; exit 1)

tqf-upgrade-rollback:
	@echo "=== Thanos Query Frontend Upgrade Rollback ==="
	@echo "Listing Helm revisions..."
	helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Enter revision number to rollback to: " REVISION; \
	if [ -n "$$REVISION" ]; then \
		echo "Rolling back to revision $$REVISION..."; \
		helm rollback $(CHART_NAME) $$REVISION -n $(NAMESPACE); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
		echo "Rollback complete"; \
		$(MAKE) -f make/ops/thanos-query-frontend.mk tqf-post-upgrade-check; \
	else \
		echo "Rollback cancelled"; \
	fi
