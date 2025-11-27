# OpenTelemetry Collector Operations Makefile
# Usage: make -f make/ops/opentelemetry-collector.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := opentelemetry-collector
CHART_DIR := charts/$(CHART_NAME)

# OTel Collector specific variables
POD_NAME ?= $(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
CONTAINER_NAME ?= opentelemetry-collector
NAMESPACE ?= default

.PHONY: help
help:
	@echo "OpenTelemetry Collector Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  otel-logs                   - View OTel Collector logs"
	@echo "  otel-logs-all               - View logs from all OTel Collector pods"
	@echo "  otel-shell                  - Open shell in OTel Collector pod"
	@echo "  otel-port-forward-grpc      - Port forward OTLP gRPC (4317)"
	@echo "  otel-port-forward-http      - Port forward OTLP HTTP (4318)"
	@echo "  otel-port-forward-metrics   - Port forward metrics (8888)"
	@echo "  otel-port-forward-health    - Port forward health check (13133)"
	@echo "  otel-restart                - Restart OTel Collector deployment/daemonset"
	@echo ""
	@echo "Health & Status:"
	@echo "  otel-ready                  - Check if OTel Collector is ready"
	@echo "  otel-healthy                - Check if OTel Collector is healthy"
	@echo "  otel-version                - Get OTel Collector version"
	@echo "  otel-config                 - Show current OTel Collector configuration"
	@echo "  otel-status                 - Show collector status"
	@echo "  otel-feature-gates          - Show enabled feature gates"
	@echo ""
	@echo "Metrics & Monitoring:"
	@echo "  otel-metrics                - Get OTel Collector own metrics"
	@echo "  otel-zpages                 - Show zpages debugging info (if enabled)"
	@echo "  otel-pipeline-metrics       - Show pipeline-specific metrics"
	@echo ""
	@echo "Receivers:"
	@echo "  otel-test-otlp-grpc         - Test OTLP gRPC receiver (send test trace)"
	@echo "  otel-test-otlp-http         - Test OTLP HTTP receiver (send test trace)"
	@echo "  otel-receivers-status       - Show receiver status"
	@echo ""
	@echo "Processors:"
	@echo "  otel-processors-status      - Show processor status"
	@echo "  otel-batch-stats            - Show batch processor statistics"
	@echo "  otel-memory-limiter-stats   - Show memory limiter statistics"
	@echo ""
	@echo "Exporters:"
	@echo "  otel-exporters-status       - Show exporter status"
	@echo "  otel-queue-stats            - Show exporter queue statistics"
	@echo ""
	@echo "Configuration:"
	@echo "  otel-validate-config        - Validate OTel Collector configuration"
	@echo "  otel-reload-config          - Reload configuration (if supported)"
	@echo ""
	@echo "Debugging:"
	@echo "  otel-trace-logs             - Show trace-related logs"
	@echo "  otel-metric-logs            - Show metric-related logs"
	@echo "  otel-error-logs             - Show error logs"
	@echo ""
	@echo "Scaling:"
	@echo "  otel-scale                  - Scale OTel Collector (REPLICAS=2, deployment mode only)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: otel-logs otel-logs-all otel-shell otel-port-forward-grpc otel-port-forward-http otel-port-forward-metrics otel-port-forward-health otel-restart

otel-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

otel-logs-all:
	@echo "Fetching logs from all OTel Collector pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

otel-shell:
	@echo "Opening shell in $(POD_NAME)..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

otel-port-forward-grpc:
	@echo "Port forwarding OTLP gRPC to localhost:4317..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4317:4317

otel-port-forward-http:
	@echo "Port forwarding OTLP HTTP to localhost:4318..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4318:4318

otel-port-forward-metrics:
	@echo "Port forwarding metrics endpoint to localhost:8888..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 8888:8888

otel-port-forward-health:
	@echo "Port forwarding health check endpoint to localhost:13133..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 13133:13133

otel-restart:
	@echo "Restarting OTel Collector..."
	@if kubectl get deployment/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	elif kubectl get daemonset/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl rollout restart daemonset/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status daemonset/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		echo "Error: No deployment or daemonset found for $(CHART_NAME)"; \
		exit 1; \
	fi

# Health & Status
.PHONY: otel-ready otel-healthy otel-version otel-config otel-status otel-feature-gates

otel-ready:
	@echo "Checking if OTel Collector is ready..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:13133/

otel-healthy:
	@echo "Checking if OTel Collector is healthy..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:13133/

otel-version:
	@echo "Getting OTel Collector version..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /otelcol-contrib --version 2>/dev/null || kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /otelcol --version

otel-config:
	@echo "Showing current OTel Collector configuration..."
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath='{.data.config\.yaml}'

otel-status:
	@echo "Showing OTel Collector status..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:13133/

otel-feature-gates:
	@echo "Showing enabled feature gates..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c 'env | grep OTEL_'

# Metrics & Monitoring
.PHONY: otel-metrics otel-zpages otel-pipeline-metrics

otel-metrics:
	@echo "Fetching OTel Collector own metrics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics

otel-zpages:
	@echo "Showing zpages debugging info..."
	@echo "Note: zpages must be enabled in configuration (extensions.zpages)"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:55679/debug/tracez 2>/dev/null || echo "zpages not enabled"

otel-pipeline-metrics:
	@echo "Showing pipeline-specific metrics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep -E "otelcol_(receiver|processor|exporter)_"

# Receivers
.PHONY: otel-test-otlp-grpc otel-test-otlp-http otel-receivers-status

otel-test-otlp-grpc:
	@echo "Testing OTLP gRPC receiver..."
	@echo "Sending test trace to $(CHART_NAME):4317"
	@echo "Note: Requires telemetrygen or similar tool"
	@echo "Example: telemetrygen traces --otlp-endpoint $(CHART_NAME).$(NAMESPACE):4317 --otlp-insecure"

otel-test-otlp-http:
	@echo "Testing OTLP HTTP receiver..."
	@echo "Sending test trace to $(CHART_NAME):4318"
	@echo "Example: telemetrygen traces --otlp-endpoint $(CHART_NAME).$(NAMESPACE):4318 --otlp-http"

otel-receivers-status:
	@echo "Showing receiver status from metrics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_receiver_"

# Processors
.PHONY: otel-processors-status otel-batch-stats otel-memory-limiter-stats

otel-processors-status:
	@echo "Showing processor status from metrics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_processor_"

otel-batch-stats:
	@echo "Showing batch processor statistics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_processor_batch_"

otel-memory-limiter-stats:
	@echo "Showing memory limiter statistics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_processor_memory_limiter_"

# Exporters
.PHONY: otel-exporters-status otel-queue-stats

otel-exporters-status:
	@echo "Showing exporter status from metrics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_exporter_"

otel-queue-stats:
	@echo "Showing exporter queue statistics..."
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8888/metrics | grep "otelcol_exporter_queue_"

# Configuration
.PHONY: otel-validate-config otel-reload-config

otel-validate-config:
	@echo "Validating OTel Collector configuration..."
	@echo "Fetching config from ConfigMap..."
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o jsonpath='{.data.config\.yaml}' > /tmp/otel-config-validate.yaml
	@echo "Config saved to /tmp/otel-config-validate.yaml"
	@echo "Note: Use otelcol-contrib validate /tmp/otel-config-validate.yaml locally to validate"

otel-reload-config:
	@echo "Reloading OTel Collector configuration..."
	@echo "Note: Configuration reload is not supported. Restarting collector instead."
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) otel-restart

# Debugging
.PHONY: otel-trace-logs otel-metric-logs otel-error-logs

otel-trace-logs:
	@echo "Showing trace-related logs..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i "trace"

otel-metric-logs:
	@echo "Showing metric-related logs..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i "metric"

otel-error-logs:
	@echo "Showing error logs..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -iE "error|fail|panic"

# Scaling
.PHONY: otel-scale

REPLICAS ?= 2

otel-scale:
	@echo "Scaling OTel Collector to $(REPLICAS) replicas..."
	@if kubectl get deployment/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		echo "Error: Scaling only supported for deployment mode, not daemonset"; \
		exit 1; \
	fi
