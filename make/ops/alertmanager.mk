# Alertmanager Operations Makefile
# Usage: make -f make/ops/alertmanager.mk <target>

include make/Makefile.common.mk

CHART_NAME := alertmanager
CHART_DIR := charts/$(CHART_NAME)

# Alertmanager specific variables
NAMESPACE ?= default
POD ?= $(CHART_NAME)-0

.PHONY: help
help:
	@echo "Alertmanager Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  am-logs                      - View logs from first Alertmanager pod"
	@echo "  am-logs-all                  - View logs from all Alertmanager pods"
	@echo "  am-shell                     - Open shell in Alertmanager pod"
	@echo "  am-restart                   - Restart Alertmanager StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  am-status                    - Show StatefulSet and pods status"
	@echo "  am-version                   - Get Alertmanager version"
	@echo "  am-health                    - Check health endpoint"
	@echo "  am-ready                     - Check readiness endpoint"
	@echo "  am-cluster-status            - Check cluster status (HA mode)"
	@echo ""
	@echo "Configuration:"
	@echo "  am-config                    - View current configuration"
	@echo "  am-reload                    - Reload configuration (requires --web.enable-lifecycle)"
	@echo "  am-validate-config           - Validate configuration without applying"
	@echo ""
	@echo "Alerts Management:"
	@echo "  am-list-alerts               - List all active alerts"
	@echo "  am-list-alerts-json          - List alerts in JSON format"
	@echo "  am-get-alert                 - Get specific alert (FINGERPRINT=...)"
	@echo ""
	@echo "Silences Management:"
	@echo "  am-list-silences             - List all silences"
	@echo "  am-list-silences-json        - List silences in JSON format"
	@echo "  am-get-silence               - Get specific silence (ID=...)"
	@echo "  am-delete-silence            - Delete silence (ID=...)"
	@echo ""
	@echo "Receivers & Routes:"
	@echo "  am-list-receivers            - List configured receivers"
	@echo "  am-test-receiver             - Test receiver configuration"
	@echo ""
	@echo "Metrics & Monitoring:"
	@echo "  am-metrics                   - Fetch Prometheus metrics"
	@echo "  am-port-forward              - Port forward to localhost:9093"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: am-logs am-logs-all am-shell am-restart

am-logs:
	@echo "Fetching logs from Alertmanager pod $(POD)..."
	kubectl logs -n $(NAMESPACE) $(POD) --tail=100 -f

am-logs-all:
	@echo "Fetching logs from all Alertmanager pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 -f

am-shell:
	@echo "Opening shell in Alertmanager pod $(POD)..."
	kubectl exec -it -n $(NAMESPACE) $(POD) -- /bin/sh

am-restart:
	@echo "Restarting Alertmanager StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: am-status am-version am-health am-ready am-cluster-status

am-status:
	@echo "StatefulSet status:"
	kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

am-version:
	@echo "Getting Alertmanager version..."
	kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --version 2>&1 | head -1

am-health:
	@echo "Checking health endpoint..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/-/healthy

am-ready:
	@echo "Checking readiness endpoint..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/-/ready

am-cluster-status:
	@echo "Cluster status:"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/status | grep -o '"clusterStatus":{[^}]*}' || echo "Run 'kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/status' for full output"

# Configuration
.PHONY: am-config am-reload am-validate-config

am-config:
	@echo "Current Alertmanager configuration:"
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath="{.data['alertmanager\.yml']}"

am-reload:
	@echo "Reloading Alertmanager configuration..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- --post-data='' http://localhost:9093/-/reload

am-validate-config:
	@echo "Validating configuration..."
	kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check

# Alerts Management
.PHONY: am-list-alerts am-list-alerts-json am-get-alert

am-list-alerts:
	@echo "Active alerts:"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/alerts

am-list-alerts-json:
	@echo "Active alerts (JSON):"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/alerts | python3 -m json.tool 2>/dev/null || kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/alerts

am-get-alert:
	@if [ -z "$(FINGERPRINT)" ]; then \
		echo "Error: FINGERPRINT parameter is required"; \
		echo "Usage: make -f make/ops/alertmanager.mk am-get-alert FINGERPRINT=<fingerprint>"; \
		exit 1; \
	fi
	@echo "Getting alert with fingerprint $(FINGERPRINT)..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/alert/$(FINGERPRINT)

# Silences Management
.PHONY: am-list-silences am-list-silences-json am-get-silence am-delete-silence

am-list-silences:
	@echo "All silences:"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences

am-list-silences-json:
	@echo "All silences (JSON):"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences | python3 -m json.tool 2>/dev/null || kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences

am-get-silence:
	@if [ -z "$(ID)" ]; then \
		echo "Error: ID parameter is required"; \
		echo "Usage: make -f make/ops/alertmanager.mk am-get-silence ID=<silence-id>"; \
		exit 1; \
	fi
	@echo "Getting silence $(ID)..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silence/$(ID)

am-delete-silence:
	@if [ -z "$(ID)" ]; then \
		echo "Error: ID parameter is required"; \
		echo "Usage: make -f make/ops/alertmanager.mk am-delete-silence ID=<silence-id>"; \
		exit 1; \
	fi
	@echo "Deleting silence $(ID)..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- --method=DELETE http://localhost:9093/api/v2/silence/$(ID)

# Receivers & Routes
.PHONY: am-list-receivers am-test-receiver

am-list-receivers:
	@echo "Configured receivers:"
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/receivers

am-test-receiver:
	@echo "Testing receiver configuration..."
	@echo "Visit the Alertmanager UI to test receivers: http://localhost:9093"
	@echo "Use 'make am-port-forward' to access the UI"

# Metrics & Monitoring
.PHONY: am-metrics am-port-forward

am-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/metrics

am-port-forward:
	@echo "Port forwarding Alertmanager to localhost:9093..."
	kubectl port-forward -n $(NAMESPACE) $(POD) 9093:9093
