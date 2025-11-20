# Loki Operations Makefile
# Usage: make -f make/ops/loki.mk <target>

include make/Makefile.common.mk

CHART_NAME := loki
CHART_DIR := charts/$(CHART_NAME)

# Loki specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= loki
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Loki Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  loki-logs                   - View Loki logs"
	@echo "  loki-logs-all               - View logs from all Loki pods"
	@echo "  loki-shell                  - Open shell in Loki pod"
	@echo "  loki-port-forward           - Port forward Loki HTTP (3100)"
	@echo "  loki-port-forward-grpc      - Port forward Loki gRPC (9095)"
	@echo "  loki-restart                - Restart Loki StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  loki-ready                  - Check if Loki is ready"
	@echo "  loki-health                 - Get health status"
	@echo "  loki-metrics                - Get Prometheus metrics"
	@echo "  loki-version                - Get Loki version"
	@echo "  loki-config                 - Show current Loki configuration"
	@echo ""
	@echo "Ring & Clustering:"
	@echo "  loki-ring-status            - Get ring status"
	@echo "  loki-memberlist-status      - Get memberlist status"
	@echo ""
	@echo "Query & Logs:"
	@echo "  loki-query                  - Query logs (QUERY='{job=\"app\"}' TIME=5m)"
	@echo "  loki-labels                 - Get all label names"
	@echo "  loki-label-values           - Get values for a label (LABEL=job)"
	@echo "  loki-tail                   - Tail logs in real-time (QUERY='{job=\"app\"}')"
	@echo ""
	@echo "Data Management:"
	@echo "  loki-flush-index            - Flush in-memory index to storage"
	@echo "  loki-check-storage          - Check storage configuration"
	@echo ""
	@echo "Testing & Integration:"
	@echo "  loki-test-push              - Send test log to Loki"
	@echo "  loki-grafana-datasource     - Get Grafana datasource URL"
	@echo ""
	@echo "Scaling:"
	@echo "  loki-scale                  - Scale Loki (REPLICAS=3)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: loki-logs loki-logs-all loki-shell loki-port-forward loki-port-forward-grpc loki-restart

loki-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

loki-logs-all:
	@echo "Fetching logs from all Loki pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

loki-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

loki-port-forward:
	@echo "Port forwarding Loki HTTP to localhost:3100..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3100:3100

loki-port-forward-grpc:
	@echo "Port forwarding Loki gRPC to localhost:9095..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9095:9095

loki-restart:
	@echo "Restarting Loki StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: loki-ready loki-health loki-metrics loki-version loki-config

loki-ready:
	@echo "Checking if Loki is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ready

loki-health:
	@echo "Getting Loki health status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ready

loki-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/metrics

loki-version:
	@echo "Getting Loki version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /usr/bin/loki --version

loki-config:
	@echo "Showing current Loki configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/loki/loki.yaml

# Ring & Clustering
.PHONY: loki-ring-status loki-memberlist-status

loki-ring-status:
	@echo "Getting ring status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ring

loki-memberlist-status:
	@echo "Getting memberlist status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/memberlist

# Query & Logs
.PHONY: loki-query loki-labels loki-label-values loki-tail

QUERY ?= {job="loki"}
TIME ?= 5m
LABEL ?= job

loki-query:
	@echo "Querying Loki: $(QUERY) (last $(TIME))..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/query_range?query=$(QUERY)&start=$$(date -u -d '$(TIME) ago' +%s)000000000&end=$$(date -u +%s)000000000"

loki-labels:
	@echo "Getting all label names..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/labels"

loki-label-values:
	@echo "Getting values for label '$(LABEL)'..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/label/$(LABEL)/values"

loki-tail:
	@echo "Tailing logs: $(QUERY)..."
	@echo "Note: This requires logcli to be installed locally"
	@echo "Install: go install github.com/grafana/loki/cmd/logcli@latest"
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3100:3100 &
	sleep 2
	logcli query '$(QUERY)' --addr=http://localhost:3100 --tail

# Data Management
.PHONY: loki-flush-index loki-check-storage

loki-flush-index:
	@echo "Flushing in-memory index to storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- -X POST http://localhost:3100/flush

loki-check-storage:
	@echo "Checking storage configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lah /loki

# Testing & Integration
.PHONY: loki-test-push loki-grafana-datasource

loki-test-push:
	@echo "Sending test log to Loki..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c 'echo "{\"streams\": [{\"stream\": {\"job\": \"test\"}, \"values\": [[\"$$(date -u +%s)000000000\", \"test log message from make\"]]}]}" | wget -qO- --post-data=@- --header="Content-Type: application/json" http://localhost:3100/loki/api/v1/push'
	@echo ""
	@echo "Test log sent. Query with: make -f make/ops/loki.mk loki-query QUERY='{job=\"test\"}'"

loki-grafana-datasource:
	@echo "Grafana datasource configuration:"
	@echo ""
	@echo "  Name: Loki"
	@echo "  Type: Loki"
	@echo "  URL: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:3100"
	@echo ""
	@echo "Add this datasource to Grafana to query Loki logs."

# Scaling
.PHONY: loki-scale

REPLICAS ?= 3

loki-scale:
	@echo "Scaling Loki to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
