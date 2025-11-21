# Promtail Operations Makefile
# Usage: make -f make/ops/promtail.mk <target>

include make/Makefile.common.mk

CHART_NAME := promtail
CHART_DIR := charts/$(CHART_NAME)

# Promtail specific variables
NAMESPACE ?= default
NODE ?=

.PHONY: help
help:
	@echo "Promtail Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  promtail-logs                - View logs from all Promtail pods"
	@echo "  promtail-logs-node           - View logs from Promtail on specific node (NODE=node-name)"
	@echo "  promtail-shell               - Open shell in a Promtail pod"
	@echo "  promtail-shell-node          - Open shell in Promtail pod on specific node (NODE=node-name)"
	@echo "  promtail-restart             - Restart Promtail DaemonSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  promtail-status              - Show DaemonSet status"
	@echo "  promtail-ready               - Check if Promtail pods are ready"
	@echo "  promtail-version             - Get Promtail version"
	@echo "  promtail-config              - Show Promtail configuration"
	@echo "  promtail-targets             - Show scrape targets"
	@echo "  promtail-metrics             - Get Promtail metrics"
	@echo ""
	@echo "Node Operations:"
	@echo "  promtail-list-nodes          - List all nodes running Promtail"
	@echo "  promtail-pod-on-node         - Get Promtail pod name on specific node (NODE=node-name)"
	@echo ""
	@echo "Troubleshooting:"
	@echo "  promtail-test-loki           - Test connection to Loki"
	@echo "  promtail-check-positions     - Check positions file"
	@echo "  promtail-check-logs-path     - Check if log paths are accessible"
	@echo "  promtail-debug               - Show debug information"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: promtail-logs promtail-logs-node promtail-shell promtail-shell-node promtail-restart

promtail-logs:
	@echo "Fetching logs from all Promtail pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 -f

promtail-logs-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk promtail-logs-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Fetching logs from Promtail on node $(NODE)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl logs -n $(NAMESPACE) $$POD --tail=100 -f

promtail-shell:
	@echo "Opening shell in a Promtail pod..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

promtail-shell-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk promtail-shell-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Opening shell in Promtail pod on node $(NODE)..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

promtail-restart:
	@echo "Restarting Promtail DaemonSet..."
	kubectl rollout restart daemonset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status daemonset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: promtail-status promtail-ready promtail-version promtail-config promtail-targets promtail-metrics

promtail-status:
	@echo "DaemonSet status:"
	kubectl get daemonset -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

promtail-ready:
	@echo "Checking if Promtail pods are ready..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/ready

promtail-version:
	@echo "Getting Promtail version..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- /usr/bin/promtail --version

promtail-config:
	@echo "Showing Promtail configuration..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /etc/promtail/promtail.yaml

promtail-targets:
	@echo "Showing scrape targets..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/targets

promtail-metrics:
	@echo "Fetching Promtail metrics..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics

# Node Operations
.PHONY: promtail-list-nodes promtail-pod-on-node

promtail-list-nodes:
	@echo "Nodes running Promtail:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o custom-columns=NODE:.spec.nodeName,POD:.metadata.name,STATUS:.status.phase

promtail-pod-on-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk promtail-pod-on-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "Promtail pod on node $(NODE):"
	@kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"

# Troubleshooting
.PHONY: promtail-test-loki promtail-check-positions promtail-check-logs-path promtail-debug

promtail-test-loki:
	@echo "Testing connection to Loki..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	LOKI_URL=$$(kubectl get cm -n $(NAMESPACE) $(CHART_NAME)-config -o jsonpath='{.data.promtail\.yaml}' | grep 'url:' | head -1 | awk '{print $$2}' | sed 's|/loki/api/v1/push|/ready|'); \
	echo "Loki URL: $$LOKI_URL"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- $$LOKI_URL

promtail-check-positions:
	@echo "Checking positions file..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /tmp/positions.yaml

promtail-check-logs-path:
	@echo "Checking if log paths are accessible..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Checking /var/log/pods:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -la /var/log/pods | head -10; \
	echo ""; \
	echo "Checking /var/lib/docker/containers:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -la /var/lib/docker/containers 2>/dev/null | head -10 || echo "Not accessible or doesn't exist"

promtail-debug:
	@echo "=== Promtail Debug Information ==="
	@echo ""
	@echo "1. DaemonSet Status:"
	@kubectl get daemonset -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "2. Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "3. Recent Logs (last 20 lines):"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=20
	@echo ""
	@echo "4. Loki Connection Test:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	LOKI_URL=$$(kubectl get cm -n $(NAMESPACE) $(CHART_NAME)-config -o jsonpath='{.data.promtail\.yaml}' | grep 'url:' | head -1 | awk '{print $$2}' | sed 's|/loki/api/v1/push|/ready|'); \
	echo "Testing Loki at: $$LOKI_URL"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- $$LOKI_URL 2>&1 || echo "Failed to connect to Loki"
