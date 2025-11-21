# Blackbox Exporter Operations Makefile
# Usage: make -f make/ops/blackbox-exporter.mk <target>

include make/Makefile.common.mk

CHART_NAME := blackbox-exporter
CHART_DIR := charts/$(CHART_NAME)

# Blackbox Exporter specific variables
NAMESPACE ?= default
POD_NAME := $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

.PHONY: help
help:
	@echo "Blackbox Exporter Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  bbe-logs                     - View logs from blackbox-exporter pod"
	@echo "  bbe-shell                    - Open shell in blackbox-exporter pod"
	@echo "  bbe-restart                  - Restart blackbox-exporter Deployment"
	@echo ""
	@echo "Health & Status:"
	@echo "  bbe-status                   - Show Deployment and pods status"
	@echo "  bbe-version                  - Get blackbox-exporter version"
	@echo "  bbe-health                   - Check health endpoint"
	@echo "  bbe-config                   - View current configuration"
	@echo ""
	@echo "Probe Testing:"
	@echo "  bbe-probe-http               - Test HTTP probe (TARGET=https://example.com)"
	@echo "  bbe-probe-https              - Test HTTPS probe (TARGET=https://example.com)"
	@echo "  bbe-probe-tcp                - Test TCP probe (TARGET=example.com:443)"
	@echo "  bbe-probe-dns                - Test DNS probe (TARGET=8.8.8.8)"
	@echo "  bbe-probe-icmp               - Test ICMP probe (TARGET=8.8.8.8)"
	@echo "  bbe-probe-custom             - Test custom probe (TARGET=..., MODULE=...)"
	@echo ""
	@echo "Module Management:"
	@echo "  bbe-list-modules             - List all configured modules"
	@echo "  bbe-test-module              - Test specific module (MODULE=http_2xx)"
	@echo ""
	@echo "Metrics:"
	@echo "  bbe-metrics                  - Fetch Prometheus metrics"
	@echo "  bbe-probe-metrics            - Fetch probe-specific metrics"
	@echo ""
	@echo "Port Forward:"
	@echo "  bbe-port-forward             - Port forward to localhost:9115"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: bbe-logs bbe-shell bbe-restart

bbe-logs:
	@echo "Fetching logs from blackbox-exporter pod..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 -f

bbe-shell:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Opening shell in blackbox-exporter pod $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -- /bin/sh

bbe-restart:
	@echo "Restarting blackbox-exporter Deployment..."
	kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: bbe-status bbe-version bbe-health bbe-config

bbe-status:
	@echo "Deployment status:"
	kubectl get deployment -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

bbe-version:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Getting blackbox-exporter version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- /bin/blackbox_exporter --version 2>&1 | head -1

bbe-health:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Checking health endpoint..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:9115/health

bbe-config:
	@echo "Current blackbox-exporter configuration:"
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath="{.data['blackbox\.yml']}"

# Probe Testing
.PHONY: bbe-probe-http bbe-probe-https bbe-probe-tcp bbe-probe-dns bbe-probe-icmp bbe-probe-custom

bbe-probe-http:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-http TARGET=https://example.com"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with http_2xx module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=http_2xx"

bbe-probe-https:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-https TARGET=https://example.com"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with https_2xx module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=https_2xx"

bbe-probe-tcp:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-tcp TARGET=example.com:443"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with tcp_connect module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=tcp_connect"

bbe-probe-dns:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-dns TARGET=8.8.8.8"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with dns_udp module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=dns_udp"

bbe-probe-icmp:
	@if [ -z "$(TARGET)" ]; then \
		echo "Error: TARGET parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-icmp TARGET=8.8.8.8"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with icmp module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=icmp"

bbe-probe-custom:
	@if [ -z "$(TARGET)" ] || [ -z "$(MODULE)" ]; then \
		echo "Error: Both TARGET and MODULE parameters are required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-probe-custom TARGET=https://example.com MODULE=http_2xx"; \
		exit 1; \
	fi
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Probing $(TARGET) with $(MODULE) module..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- "http://localhost:9115/probe?target=$(TARGET)&module=$(MODULE)"

# Module Management
.PHONY: bbe-list-modules bbe-test-module

bbe-list-modules:
	@echo "Configured modules:"
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath="{.data['blackbox\.yml']}" | grep -A1 "modules:" | tail -n +2 | grep ":" | sed 's/://' | sed 's/^  //'

bbe-test-module:
	@if [ -z "$(MODULE)" ]; then \
		echo "Error: MODULE parameter is required"; \
		echo "Usage: make -f make/ops/blackbox-exporter.mk bbe-test-module MODULE=http_2xx"; \
		exit 1; \
	fi
	@echo "Module configuration for $(MODULE):"
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath="{.data['blackbox\.yml']}" | sed -n "/$(MODULE):/,/^  [a-z]/p" | sed '$$d'

# Metrics
.PHONY: bbe-metrics bbe-probe-metrics

bbe-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:9115/metrics

bbe-probe-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Fetching probe metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:9115/metrics | grep "^probe_"

# Port Forward
.PHONY: bbe-port-forward

bbe-port-forward:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No blackbox-exporter pod found"; \
		exit 1; \
	fi
	@echo "Port forwarding blackbox-exporter to localhost:9115..."
	kubectl port-forward -n $(NAMESPACE) $(POD_NAME) 9115:9115
