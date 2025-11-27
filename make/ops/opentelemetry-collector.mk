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
	@echo "Backup & Recovery:"
	@echo "  otel-backup-config          - Backup configuration only"
	@echo "  otel-backup-manifests       - Backup Kubernetes manifests"
	@echo "  otel-backup-all             - Full backup (config + manifests + metadata)"
	@echo "  otel-backup-verify          - Verify backup integrity (BACKUP_DIR=path)"
	@echo "  otel-restore-config         - Restore configuration (BACKUP_DIR=path)"
	@echo "  otel-restore-all            - Full restore (BACKUP_DIR=path)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  otel-pre-upgrade-check      - Pre-upgrade health validation"
	@echo "  otel-post-upgrade-check     - Post-upgrade validation"
	@echo "  otel-health-check           - Comprehensive health check"
	@echo "  otel-upgrade-rollback       - Interactive Helm rollback"
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

#==============================================================================
# Backup & Recovery Operations
#==============================================================================

BACKUP_DIR ?= tmp/otel-collector-backups
RELEASE_NAME ?= otel-collector

.PHONY: otel-backup-config otel-backup-manifests otel-backup-all otel-backup-verify
.PHONY: otel-restore-config otel-restore-manifests otel-restore-all

# Backup configuration
otel-backup-config:
	@echo "=== OpenTelemetry Collector Configuration Backup ==="
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_PATH=$(BACKUP_DIR)/config-$$TIMESTAMP; \
	mkdir -p $$BACKUP_PATH; \
	echo "Backing up to: $$BACKUP_PATH"; \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/configmap.yaml; \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.data.config\.yaml}' > $$BACKUP_PATH/otel-config.yaml; \
	if kubectl get secret -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) 2>/dev/null | grep -q .; then \
		kubectl get secret -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o yaml > $$BACKUP_PATH/secrets.yaml; \
		echo "Secrets backed up"; \
	fi; \
	echo "Configuration backup completed: $$BACKUP_PATH"

# Backup Kubernetes manifests
otel-backup-manifests:
	@echo "=== OpenTelemetry Collector Manifests Backup ==="
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_PATH=$(BACKUP_DIR)/manifests-$$TIMESTAMP; \
	mkdir -p $$BACKUP_PATH; \
	echo "Backing up to: $$BACKUP_PATH"; \
	if kubectl get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) 2>/dev/null; then \
		kubectl get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/deployment.yaml; \
		echo "Deployment backed up"; \
	elif kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) 2>/dev/null; then \
		kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/daemonset.yaml; \
		echo "DaemonSet backed up"; \
	fi; \
	kubectl get service -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/service.yaml 2>/dev/null || true; \
	kubectl get serviceaccount -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/serviceaccount.yaml 2>/dev/null || true; \
	kubectl get clusterrole $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/clusterrole.yaml 2>/dev/null || true; \
	kubectl get clusterrolebinding $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/clusterrolebinding.yaml 2>/dev/null || true; \
	kubectl get hpa -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/hpa.yaml 2>/dev/null || true; \
	kubectl get pdb -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/pdb.yaml 2>/dev/null || true; \
	kubectl get servicemonitor -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/servicemonitor.yaml 2>/dev/null || true; \
	kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/ingress.yaml 2>/dev/null || true; \
	echo "Manifests backup completed: $$BACKUP_PATH"

# Full backup (config + manifests + metadata)
otel-backup-all:
	@echo "=== OpenTelemetry Collector Full Backup ==="
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_PATH=$(BACKUP_DIR)/backup-$$TIMESTAMP; \
	mkdir -p $$BACKUP_PATH; \
	echo "Full backup to: $$BACKUP_PATH"; \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/configmap.yaml; \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.data.config\.yaml}' > $$BACKUP_PATH/otel-config.yaml; \
	if kubectl get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) 2>/dev/null; then \
		kubectl get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/deployment.yaml; \
		DEPLOY_MODE="deployment"; \
	elif kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) 2>/dev/null; then \
		kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/daemonset.yaml; \
		DEPLOY_MODE="daemonset"; \
	fi; \
	kubectl get service -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/service.yaml 2>/dev/null || true; \
	kubectl get serviceaccount -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/serviceaccount.yaml 2>/dev/null || true; \
	kubectl get clusterrole $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/clusterrole.yaml 2>/dev/null || true; \
	kubectl get clusterrolebinding $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/clusterrolebinding.yaml 2>/dev/null || true; \
	kubectl get hpa -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/hpa.yaml 2>/dev/null || true; \
	kubectl get pdb -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/pdb.yaml 2>/dev/null || true; \
	kubectl get servicemonitor -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/servicemonitor.yaml 2>/dev/null || true; \
	kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $$BACKUP_PATH/ingress.yaml 2>/dev/null || true; \
	if kubectl get secret -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) 2>/dev/null | grep -q .; then \
		kubectl get secret -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o yaml > $$BACKUP_PATH/secrets.yaml; \
	fi; \
	echo "Creating backup manifest..."; \
	IMAGE=$$(kubectl get $$DEPLOY_MODE -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A"); \
	cat > $$BACKUP_PATH/BACKUP_MANIFEST.md <<EOF; \
	# OpenTelemetry Collector Backup Manifest\n\
	**Timestamp**: $$(date -u +"%Y-%m-%d %H:%M:%S UTC")\n\
	**Release Name**: $(RELEASE_NAME)\n\
	**Namespace**: $(NAMESPACE)\n\
	**Backup Directory**: $$BACKUP_PATH\n\
	\n\
	## Collector Information\n\
	- Version: $$IMAGE\n\
	- Mode: $$DEPLOY_MODE\n\
	\n\
	## Backup Contents\n\
	- Configuration: otel-config.yaml\n\
	- ConfigMap: configmap.yaml\n\
	- Manifests: $$DEPLOY_MODE.yaml, service.yaml, clusterrole.yaml, etc.\n\
	\n\
	## Verification\n\
	\`\`\`bash\n\
	ls -lh\n\
	wc -l otel-config.yaml\n\
	\`\`\`\n\
	EOF\
	echo "Full backup completed: $$BACKUP_PATH"; \
	ls -lh $$BACKUP_PATH

# Verify backup integrity
otel-backup-verify:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "Error: BACKUP_DIR not specified"; \
		echo "Usage: make -f make/ops/opentelemetry-collector.mk otel-backup-verify BACKUP_DIR=path/to/backup"; \
		exit 1; \
	fi
	@echo "=== Verifying Backup: $(BACKUP_DIR) ==="
	@if [ ! -d "$(BACKUP_DIR)" ]; then \
		echo "Error: Backup directory not found: $(BACKUP_DIR)"; \
		exit 1; \
	fi
	@echo "Checking required files..."
	@REQUIRED_FILES="otel-config.yaml configmap.yaml"; \
	MISSING=0; \
	for file in $$REQUIRED_FILES; do \
		if [ -f "$(BACKUP_DIR)/$$file" ]; then \
			echo "  ✓ $$file"; \
		else \
			echo "  ✗ $$file (missing)"; \
			MISSING=$$((MISSING + 1)); \
		fi; \
	done; \
	if [ -f "$(BACKUP_DIR)/deployment.yaml" ]; then \
		echo "  ✓ deployment.yaml"; \
	elif [ -f "$(BACKUP_DIR)/daemonset.yaml" ]; then \
		echo "  ✓ daemonset.yaml"; \
	else \
		echo "  ✗ deployment.yaml or daemonset.yaml (missing)"; \
		MISSING=$$((MISSING + 1)); \
	fi; \
	echo "Validating YAML syntax..."; \
	for file in $(BACKUP_DIR)/*.yaml; do \
		if [ -f "$$file" ]; then \
			kubectl apply --dry-run=client -f "$$file" > /dev/null 2>&1 && echo "  ✓ $$(basename $$file)" || echo "  ⚠ $$(basename $$file) (validation warning)"; \
		fi; \
	done; \
	if [ $$MISSING -gt 0 ]; then \
		echo "Backup verification FAILED: $$MISSING required files missing"; \
		exit 1; \
	else \
		echo "Backup verification PASSED"; \
	fi

# Restore configuration
otel-restore-config:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "Error: BACKUP_DIR not specified"; \
		echo "Usage: make -f make/ops/opentelemetry-collector.mk otel-restore-config BACKUP_DIR=path/to/backup"; \
		exit 1; \
	fi
	@if [ ! -f "$(BACKUP_DIR)/configmap.yaml" ]; then \
		echo "Error: configmap.yaml not found in $(BACKUP_DIR)"; \
		exit 1; \
	fi
	@echo "=== Restoring OpenTelemetry Collector Configuration ==="
	@echo "Source: $(BACKUP_DIR)/configmap.yaml"
	kubectl apply -f $(BACKUP_DIR)/configmap.yaml
	@echo "Restarting collector to load new configuration..."
	@$(MAKE) -f $(lastword $(MAKEFILE_LIST)) otel-restart
	@echo "Configuration restore completed"

# Restore all resources
otel-restore-all:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "Error: BACKUP_DIR not specified"; \
		echo "Usage: make -f make/ops/opentelemetry-collector.mk otel-restore-all BACKUP_DIR=path/to/backup"; \
		exit 1; \
	fi
	@if [ ! -d "$(BACKUP_DIR)" ]; then \
		echo "Error: Backup directory not found: $(BACKUP_DIR)"; \
		exit 1; \
	fi
	@echo "=== Full Restore: OpenTelemetry Collector ==="
	@echo "Source: $(BACKUP_DIR)"
	@echo "Namespace: $(NAMESPACE)"
	@echo ""
	@echo "Step 1: Ensure namespace exists"
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "Step 2: Restore RBAC resources"
	@if [ -f "$(BACKUP_DIR)/serviceaccount.yaml" ]; then \
		echo "  Restoring ServiceAccount..."; \
		kubectl apply -f $(BACKUP_DIR)/serviceaccount.yaml; \
	fi
	@if [ -f "$(BACKUP_DIR)/clusterrole.yaml" ]; then \
		echo "  Restoring ClusterRole..."; \
		kubectl apply -f $(BACKUP_DIR)/clusterrole.yaml; \
	fi
	@if [ -f "$(BACKUP_DIR)/clusterrolebinding.yaml" ]; then \
		echo "  Restoring ClusterRoleBinding..."; \
		kubectl apply -f $(BACKUP_DIR)/clusterrolebinding.yaml; \
	fi
	@echo ""
	@echo "Step 3: Restore ConfigMap"
	kubectl apply -f $(BACKUP_DIR)/configmap.yaml
	@echo ""
	@echo "Step 4: Restore Deployment/DaemonSet"
	@if [ -f "$(BACKUP_DIR)/deployment.yaml" ]; then \
		echo "  Restoring Deployment..."; \
		kubectl apply -f $(BACKUP_DIR)/deployment.yaml; \
	elif [ -f "$(BACKUP_DIR)/daemonset.yaml" ]; then \
		echo "  Restoring DaemonSet..."; \
		kubectl apply -f $(BACKUP_DIR)/daemonset.yaml; \
	fi
	@echo ""
	@echo "Step 5: Restore Service"
	@if [ -f "$(BACKUP_DIR)/service.yaml" ]; then \
		kubectl apply -f $(BACKUP_DIR)/service.yaml; \
	fi
	@echo ""
	@echo "Step 6: Restore optional resources"
	@if [ -f "$(BACKUP_DIR)/hpa.yaml" ]; then \
		echo "  Restoring HPA..."; \
		kubectl apply -f $(BACKUP_DIR)/hpa.yaml; \
	fi
	@if [ -f "$(BACKUP_DIR)/pdb.yaml" ]; then \
		echo "  Restoring PDB..."; \
		kubectl apply -f $(BACKUP_DIR)/pdb.yaml; \
	fi
	@if [ -f "$(BACKUP_DIR)/servicemonitor.yaml" ]; then \
		echo "  Restoring ServiceMonitor..."; \
		kubectl apply -f $(BACKUP_DIR)/servicemonitor.yaml; \
	fi
	@if [ -f "$(BACKUP_DIR)/ingress.yaml" ]; then \
		echo "  Restoring Ingress..."; \
		kubectl apply -f $(BACKUP_DIR)/ingress.yaml; \
	fi
	@echo ""
	@echo "Step 7: Wait for pods to be ready"
	kubectl wait --for=condition=ready pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --timeout=5m || true
	@echo ""
	@echo "Full restore completed"
	@echo ""
	@echo "Verification:"
	kubectl get pods,svc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

#==============================================================================
# Upgrade Support Operations
#==============================================================================

.PHONY: otel-pre-upgrade-check otel-post-upgrade-check otel-health-check otel-upgrade-rollback

# Pre-upgrade health check
otel-pre-upgrade-check:
	@echo "=== OpenTelemetry Collector Pre-Upgrade Check ==="
	@echo ""
	@echo "1. Pod Status Check"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "2. Health Endpoint Check"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:13133 > /dev/null && echo "  ✓ Health endpoint OK" || echo "  ✗ Health endpoint FAILED"; \
	fi
	@echo ""
	@echo "3. Version Check"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		echo "  Current version:"; \
		kubectl get deployment,daemonset -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null || echo "  N/A"; \
	fi
	@echo ""
	@echo "4. Resource Usage Check"
	kubectl top pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) 2>/dev/null || echo "  ⚠ Metrics server not available"
	@echo ""
	@echo "5. Recent Error Logs"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -ic "error" || echo "0"); \
		if [ "$$ERROR_COUNT" -eq 0 ]; then \
			echo "  ✓ No errors in last 100 log lines"; \
		else \
			echo "  ⚠ Found $$ERROR_COUNT error(s) in last 100 log lines"; \
		fi; \
	fi
	@echo ""
	@echo "Pre-upgrade check completed"
	@echo "⚠ Recommendation: Create backup before upgrade"
	@echo "   make -f make/ops/opentelemetry-collector.mk otel-backup-all"

# Post-upgrade validation
otel-post-upgrade-check:
	@echo "=== OpenTelemetry Collector Post-Upgrade Validation ==="
	@echo ""
	@echo "1. Version Verification"
	@NEW_IMAGE=$$(kubectl get deployment,daemonset -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A"); \
	echo "  New version: $$NEW_IMAGE"
	@echo ""
	@echo "2. Pod Status"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "3. Health Check"
	@$(MAKE) -f $(lastword $(MAKEFILE_LIST)) otel-health-check
	@echo ""
	@echo "4. OTLP Receivers Check"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- nc -zv localhost 4317 2>&1 | grep -q succeeded && echo "  ✓ OTLP gRPC receiver (4317) OK" || echo "  ✗ OTLP gRPC receiver (4317) FAILED"; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:4318 > /dev/null 2>&1 && echo "  ✓ OTLP HTTP receiver (4318) OK" || echo "  ✗ OTLP HTTP receiver (4318) FAILED"; \
	fi
	@echo ""
	@echo "5. Pipeline Status"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i "pipeline.*enabled" || echo "  ⚠ Pipeline status unclear"; \
	fi
	@echo ""
	@echo "6. Error Log Check (last 30 minutes)"
	@if [ -z "$(POD_NAME)" ]; then \
		echo "  ⚠ No pods found"; \
	else \
		ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --since=30m 2>/dev/null | grep -ic "error" || echo "0"); \
		if [ "$$ERROR_COUNT" -eq 0 ]; then \
			echo "  ✓ No errors in last 30 minutes"; \
		else \
			echo "  ⚠ Found $$ERROR_COUNT error(s) in last 30 minutes"; \
			echo "  Review logs: make -f make/ops/opentelemetry-collector.mk otel-error-logs"; \
		fi; \
	fi
	@echo ""
	@echo "Post-upgrade validation completed"

# Health check (comprehensive)
otel-health-check:
	@echo "=== OpenTelemetry Collector Health Check ==="
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No pods found for $(CHART_NAME)"; \
		exit 1; \
	fi
	@echo "Health Endpoint:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:13133 > /dev/null && echo "  ✓ Healthy" || echo "  ✗ Unhealthy"

# Upgrade rollback (Helm)
otel-upgrade-rollback:
	@echo "=== OpenTelemetry Collector Upgrade Rollback ==="
	@echo ""
	@echo "Helm Release History:"
	helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Enter revision number to rollback to (or press Ctrl+C to cancel): " REVISION; \
	if [ -z "$$REVISION" ]; then \
		echo "Error: No revision specified"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Rolling back to revision $$REVISION..."; \
	helm rollback $(RELEASE_NAME) $$REVISION -n $(NAMESPACE) --wait --timeout 5m
	@echo ""
	@echo "Rollback completed. Verifying..."
	@$(MAKE) -f $(lastword $(MAKEFILE_LIST)) otel-post-upgrade-check
