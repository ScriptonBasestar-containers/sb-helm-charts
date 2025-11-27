# Mimir Operations Makefile
# Usage: make -f make/ops/mimir.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := mimir
CHART_DIR := charts/$(CHART_NAME)

# Mimir specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= mimir
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Mimir Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  mimir-logs                  - View Mimir logs"
	@echo "  mimir-logs-all              - View logs from all Mimir pods"
	@echo "  mimir-shell                 - Open shell in Mimir pod"
	@echo "  mimir-port-forward          - Port forward Mimir HTTP (8080)"
	@echo "  mimir-port-forward-grpc     - Port forward Mimir gRPC (9095)"
	@echo "  mimir-restart               - Restart Mimir deployment/statefulset"
	@echo ""
	@echo "Health & Status:"
	@echo "  mimir-ready                 - Check if Mimir is ready"
	@echo "  mimir-healthy               - Check if Mimir is healthy"
	@echo "  mimir-version               - Get Mimir version"
	@echo "  mimir-config                - Show current Mimir configuration"
	@echo "  mimir-runtime-config        - Show runtime configuration"
	@echo "  mimir-status                - Show Mimir status"
	@echo ""
	@echo "Metrics & Queries:"
	@echo "  mimir-query                 - Execute PromQL query (QUERY='up' TENANT='demo')"
	@echo "  mimir-query-range           - Execute range query"
	@echo "  mimir-labels                - List all label names (TENANT='demo')"
	@echo "  mimir-label-values          - Get values for a label (LABEL='job' TENANT='demo')"
	@echo "  mimir-series                - List all time series (MATCH='{__name__=~\".+\"}' TENANT='demo')"
	@echo "  mimir-metrics               - Get Mimir own metrics"
	@echo ""
	@echo "Ingestion:"
	@echo "  mimir-remote-write-test     - Test remote write endpoint (TENANT='demo')"
	@echo "  mimir-limits                - Show tenant limits (TENANT='demo')"
	@echo ""
	@echo "Storage & TSDB:"
	@echo "  mimir-check-storage         - Check storage usage"
	@echo "  mimir-blocks                - List blocks in storage"
	@echo "  mimir-compactor-status      - Show compactor status"
	@echo "  mimir-store-gateway-status  - Show store-gateway status"
	@echo ""
	@echo "Tenants:"
	@echo "  mimir-tenants               - List all tenants"
	@echo "  mimir-tenant-stats          - Show tenant statistics (TENANT='demo')"
	@echo ""
	@echo "Scaling:"
	@echo "  mimir-scale                 - Scale Mimir (REPLICAS=2)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: mimir-logs mimir-logs-all mimir-shell mimir-port-forward mimir-port-forward-grpc mimir-restart

mimir-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

mimir-logs-all:
	@echo "Fetching logs from all Mimir pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

mimir-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

mimir-port-forward:
	@echo "Port forwarding Mimir HTTP to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 8080:8080

mimir-port-forward-grpc:
	@echo "Port forwarding Mimir gRPC to localhost:9095..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9095:9095

mimir-restart:
	@echo "Restarting Mimir..."
	@if kubectl get statefulset/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	fi

# Health & Status
.PHONY: mimir-ready mimir-healthy mimir-version mimir-config mimir-runtime-config mimir-status

mimir-ready:
	@echo "Checking if Mimir is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/ready

mimir-healthy:
	@echo "Checking if Mimir is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/services

mimir-version:
	@echo "Getting Mimir version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/mimir --version

mimir-config:
	@echo "Showing current Mimir configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/mimir/mimir.yaml 2>/dev/null || echo "Config file not found. Using environment variables."

mimir-runtime-config:
	@echo "Showing runtime configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/runtime_config

mimir-status:
	@echo "Showing Mimir status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/services

# Metrics & Queries
.PHONY: mimir-query mimir-query-range mimir-labels mimir-label-values mimir-series mimir-metrics

QUERY ?= up
TENANT ?= demo
START ?= -1h
END ?= now
STEP ?= 15s
LABEL ?= job
MATCH ?= {__name__=~".+"}

mimir-query:
	@echo "Executing query: $(QUERY) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" "http://localhost:8080/prometheus/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

mimir-query-range:
	@echo "Executing range query: $(QUERY) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c "wget -qO- --header='X-Scope-OrgID: $(TENANT)' 'http://localhost:8080/prometheus/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s)&end=$$(date -d '$(END)' +%s)&step=$(STEP)'"

mimir-labels:
	@echo "Listing all label names for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/prometheus/api/v1/labels

mimir-label-values:
	@echo "Getting values for label '$(LABEL)' for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/prometheus/api/v1/label/$(LABEL)/values

mimir-series:
	@echo "Listing time series matching: $(MATCH) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" "http://localhost:8080/prometheus/api/v1/series?match[]=$(MATCH)"

mimir-metrics:
	@echo "Fetching Mimir own metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/metrics

# Ingestion
.PHONY: mimir-remote-write-test mimir-limits

mimir-remote-write-test:
	@echo "Testing remote write endpoint for tenant: $(TENANT)"
	@echo "Remote write URL: http://$(CHART_NAME):8080/api/v1/push"
	@echo "Use with Prometheus remote_write config:"
	@echo "remote_write:"
	@echo "  - url: http://$(CHART_NAME):8080/api/v1/push"
	@echo "    headers:"
	@echo "      X-Scope-OrgID: $(TENANT)"

mimir-limits:
	@echo "Showing tenant limits for: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/api/v1/user_limits

# Storage & TSDB
.PHONY: mimir-check-storage mimir-blocks mimir-compactor-status mimir-store-gateway-status

mimir-check-storage:
	@echo "Checking storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || echo "No /data mount found"

mimir-blocks:
	@echo "Listing blocks in storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lh /data/blocks/ 2>/dev/null || echo "Blocks directory not found (may be using S3/GCS)"

mimir-compactor-status:
	@echo "Showing compactor status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/compactor/ring

mimir-store-gateway-status:
	@echo "Showing store-gateway status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/store-gateway/ring

# Tenants
.PHONY: mimir-tenants mimir-tenant-stats

mimir-tenants:
	@echo "Listing all tenants..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/api/v1/user_stats

mimir-tenant-stats:
	@echo "Showing tenant statistics for: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/api/v1/user_stats

# Scaling
.PHONY: mimir-scale

REPLICAS ?= 2

mimir-scale:
	@echo "Scaling Mimir to $(REPLICAS) replicas..."
	@if kubectl get statefulset/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	fi
