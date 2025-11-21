# Node Exporter Operations Makefile
# Usage: make -f make/ops/node-exporter.mk <target>

include make/Makefile.common.mk

CHART_NAME := node-exporter
CHART_DIR := charts/$(CHART_NAME)

# Node Exporter specific variables
NAMESPACE ?= default
NODE ?=

.PHONY: help
help:
	@echo "Node Exporter Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  ne-logs                      - View logs from all Node Exporter pods"
	@echo "  ne-logs-node                 - View logs from Node Exporter on specific node (NODE=node-name)"
	@echo "  ne-shell                     - Open shell in a Node Exporter pod"
	@echo "  ne-shell-node                - Open shell in Node Exporter pod on specific node (NODE=node-name)"
	@echo "  ne-restart                   - Restart Node Exporter DaemonSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  ne-status                    - Show DaemonSet status"
	@echo "  ne-version                   - Get Node Exporter version"
	@echo "  ne-metrics                   - Get Node Exporter metrics (from first pod)"
	@echo "  ne-metrics-node              - Get metrics from specific node (NODE=node-name)"
	@echo ""
	@echo "Node Operations:"
	@echo "  ne-list-nodes                - List all nodes running Node Exporter"
	@echo "  ne-pod-on-node               - Get Node Exporter pod name on specific node (NODE=node-name)"
	@echo ""
	@echo "Metrics Queries:"
	@echo "  ne-cpu-metrics               - Get CPU metrics"
	@echo "  ne-memory-metrics            - Get memory metrics"
	@echo "  ne-disk-metrics              - Get disk metrics"
	@echo "  ne-network-metrics           - Get network metrics"
	@echo "  ne-load-metrics              - Get load average metrics"
	@echo ""
	@echo "Port Forward:"
	@echo "  ne-port-forward              - Port forward to a Node Exporter pod"
	@echo "  ne-port-forward-node         - Port forward to Node Exporter on specific node (NODE=node-name)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: ne-logs ne-logs-node ne-shell ne-shell-node ne-restart

ne-logs:
	@echo "Fetching logs from all Node Exporter pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 -f

ne-logs-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/node-exporter.mk ne-logs-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Fetching logs from Node Exporter on node $(NODE)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl logs -n $(NAMESPACE) $$POD --tail=100 -f

ne-shell:
	@echo "Opening shell in a Node Exporter pod..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

ne-shell-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/node-exporter.mk ne-shell-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Opening shell in Node Exporter pod on node $(NODE)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

ne-restart:
	@echo "Restarting Node Exporter DaemonSet..."
	kubectl rollout restart daemonset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status daemonset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: ne-status ne-version ne-metrics ne-metrics-node

ne-status:
	@echo "DaemonSet status:"
	kubectl get daemonset -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

ne-version:
	@echo "Getting Node Exporter version..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- /bin/node_exporter --version 2>&1 | head -1

ne-metrics:
	@echo "Fetching Node Exporter metrics from first pod..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics

ne-metrics-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/node-exporter.mk ne-metrics-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Fetching metrics from Node Exporter on node $(NODE)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics

# Node Operations
.PHONY: ne-list-nodes ne-pod-on-node

ne-list-nodes:
	@echo "Nodes running Node Exporter:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o custom-columns=NODE:.spec.nodeName,POD:.metadata.name,STATUS:.status.phase

ne-pod-on-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/node-exporter.mk ne-pod-on-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Node Exporter pod on node $(NODE):"
	@kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"

# Metrics Queries
.PHONY: ne-cpu-metrics ne-memory-metrics ne-disk-metrics ne-network-metrics ne-load-metrics

ne-cpu-metrics:
	@echo "CPU metrics:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics | grep "^node_cpu"

ne-memory-metrics:
	@echo "Memory metrics:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics | grep "^node_memory"

ne-disk-metrics:
	@echo "Disk metrics:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics | grep "^node_disk\|^node_filesystem"

ne-network-metrics:
	@echo "Network metrics:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics | grep "^node_network"

ne-load-metrics:
	@echo "Load average metrics:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9100/metrics | grep "^node_load"

# Port Forward
.PHONY: ne-port-forward ne-port-forward-node

ne-port-forward:
	@echo "Port forwarding Node Exporter to localhost:9100..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl port-forward -n $(NAMESPACE) $$POD 9100:9100

ne-port-forward-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/node-exporter.mk ne-port-forward-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Port forwarding Node Exporter on node $(NODE) to localhost:9100..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl port-forward -n $(NAMESPACE) $$POD 9100:9100
