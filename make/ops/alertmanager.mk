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
	@echo "Backup & Recovery:"
	@echo "  am-backup-config             - Backup Alertmanager configuration"
	@echo "  am-backup-silences           - Backup active silences"
	@echo "  am-backup-templates          - Backup notification templates"
	@echo "  am-backup-all                - Backup configuration + silences + templates"
	@echo "  am-restore-config            - Restore configuration from backup"
	@echo "  am-restore-silences          - Restore silences from backup"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  am-pre-upgrade-check         - Pre-upgrade validation checks"
	@echo "  am-post-upgrade-check        - Post-upgrade validation"
	@echo "  am-upgrade-rollback          - Rollback to previous Helm release"
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

# Backup & Recovery
.PHONY: am-backup-config am-backup-silences am-backup-templates am-backup-all am-restore-config am-restore-silences

am-backup-config:
	@echo "Backing up Alertmanager configuration..."
	@BACKUP_FILE="alertmanager-config-backup-$$(date +%Y%m%d-%H%M%S).yaml"; \
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o yaml > $$BACKUP_FILE && \
	echo "Configuration backed up to: $$BACKUP_FILE"

am-backup-silences:
	@echo "Backing up active silences..."
	@BACKUP_FILE="alertmanager-silences-backup-$$(date +%Y%m%d-%H%M%S).json"; \
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences > $$BACKUP_FILE && \
	echo "Silences backed up to: $$BACKUP_FILE"

am-backup-templates:
	@echo "Backing up notification templates..."
	@TEMPLATES_CM="$(CHART_NAME)-templates"; \
	if kubectl get configmap -n $(NAMESPACE) $$TEMPLATES_CM >/dev/null 2>&1; then \
		BACKUP_FILE="alertmanager-templates-backup-$$(date +%Y%m%d-%H%M%S).yaml"; \
		kubectl get configmap -n $(NAMESPACE) $$TEMPLATES_CM -o yaml > $$BACKUP_FILE && \
		echo "Templates backed up to: $$BACKUP_FILE"; \
	else \
		echo "No templates ConfigMap found ($(CHART_NAME)-templates)"; \
	fi

am-backup-all:
	@echo "=== Full Alertmanager Backup ==="
	@echo ""
	@echo "[1/3] Backing up configuration..."
	@BACKUP_DIR="alertmanager-backup-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p $$BACKUP_DIR && \
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o yaml > $$BACKUP_DIR/config.yaml && \
	echo "  ✓ Configuration saved to $$BACKUP_DIR/config.yaml" && \
	echo "" && \
	echo "[2/3] Backing up silences..." && \
	kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences > $$BACKUP_DIR/silences.json && \
	echo "  ✓ Silences saved to $$BACKUP_DIR/silences.json" && \
	echo "" && \
	echo "[3/3] Backing up templates..." && \
	TEMPLATES_CM="$(CHART_NAME)-templates"; \
	if kubectl get configmap -n $(NAMESPACE) $$TEMPLATES_CM >/dev/null 2>&1; then \
		kubectl get configmap -n $(NAMESPACE) $$TEMPLATES_CM -o yaml > $$BACKUP_DIR/templates.yaml && \
		echo "  ✓ Templates saved to $$BACKUP_DIR/templates.yaml"; \
	else \
		echo "  - No templates ConfigMap found"; \
	fi && \
	echo "" && \
	echo "=== Backup Complete ===" && \
	echo "Backup directory: $$BACKUP_DIR"

am-restore-config:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/alertmanager.mk am-restore-config FILE=<backup-file.yaml>"; \
		exit 1; \
	fi
	@echo "Restoring Alertmanager configuration from $(FILE)..."
	@kubectl apply -f $(FILE)
	@echo ""
	@echo "Configuration restored. Reloading Alertmanager..."
	@if kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- --post-data='' http://localhost:9093/-/reload 2>/dev/null; then \
		echo "  ✓ Configuration reloaded successfully"; \
	else \
		echo "  ⚠ Reload failed (requires --web.enable-lifecycle)"; \
		echo "  Restarting pods instead..."; \
		kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	fi

am-restore-silences:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/alertmanager.mk am-restore-silences FILE=<backup-file.json>"; \
		exit 1; \
	fi
	@echo "Restoring silences from $(FILE)..."
	@jq -c '.[]' $(FILE) | while read silence; do \
		silence_data=$$(echo $$silence | jq 'del(.id, .status)'); \
		kubectl exec -n $(NAMESPACE) $(POD) -- sh -c "wget --post-data='$$silence_data' --header='Content-Type: application/json' -qO- http://localhost:9093/api/v2/silences"; \
	done
	@echo "  ✓ Silences restored successfully"

# Upgrade Operations
.PHONY: am-pre-upgrade-check am-post-upgrade-check am-upgrade-rollback

am-pre-upgrade-check:
	@echo "=== Pre-Upgrade Validation ==="
	@echo ""
	@echo "[1/6] Checking current status..."
	@kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) || (echo "  ✗ StatefulSet not found"; exit 1)
	@echo "  ✓ StatefulSet found"
	@echo ""
	@echo "[2/6] Checking pod readiness..."
	@READY=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l); \
	TOTAL=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[*].metadata.name}' | wc -w); \
	if [ "$$READY" -eq "$$TOTAL" ]; then \
		echo "  ✓ All $$TOTAL pods are ready"; \
	else \
		echo "  ⚠ Only $$READY/$$TOTAL pods are ready"; \
	fi
	@echo ""
	@echo "[3/6] Checking Alertmanager version..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --version 2>&1 | head -1
	@echo ""
	@echo "[4/6] Checking configuration validity..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check && \
	echo "  ✓ Configuration is valid"
	@echo ""
	@echo "[5/6] Checking active alerts..."
	@ALERTS=$$(kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/alerts | grep -o '"fingerprint"' | wc -l); \
	echo "  Active alerts: $$ALERTS"
	@echo ""
	@echo "[6/6] Checking active silences..."
	@SILENCES=$$(kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences | grep -o '"id"' | wc -l); \
	echo "  Active silences: $$SILENCES"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo ""
	@echo "⚠ IMPORTANT: Run backup before upgrading:"
	@echo "  make -f make/ops/alertmanager.mk am-backup-all"

am-post-upgrade-check:
	@echo "=== Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/6] Checking pod status..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$(CHART_NAME) -n $(NAMESPACE) --timeout=300s && \
	echo "  ✓ All pods are ready"
	@echo ""
	@echo "[2/6] Checking Alertmanager version..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --version 2>&1 | head -1
	@echo ""
	@echo "[3/6] Checking API v2 health..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/status | grep -o '"versionInfo":{[^}]*}' && \
	echo "  ✓ API v2 is responding"
	@echo ""
	@echo "[4/6] Checking cluster status (HA mode)..."
	@REPLICAS=$$(kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) -o jsonpath='{.spec.replicas}'); \
	if [ "$$REPLICAS" -gt 1 ]; then \
		PEERS=$$(kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/status | grep -o '"name":' | wc -l); \
		echo "  Cluster peers: $$PEERS (expected: $$REPLICAS)"; \
	else \
		echo "  Single replica mode (no clustering)"; \
	fi
	@echo ""
	@echo "[5/6] Validating configuration..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- /bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check && \
	echo "  ✓ Configuration is valid"
	@echo ""
	@echo "[6/6] Checking silences..."
	@SILENCES=$$(kubectl exec -n $(NAMESPACE) $(POD) -- wget -qO- http://localhost:9093/api/v2/silences | grep -o '"id"' | wc -l); \
	echo "  Active silences: $$SILENCES"
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

am-upgrade-rollback:
	@echo "Rolling back to previous Helm release..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Are you sure you want to rollback? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		helm rollback $(CHART_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "Waiting for rollback to complete..." && \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "=== Rollback Complete ===" && \
		echo "" && \
		echo "Verify with:" && \
		echo "  make -f make/ops/alertmanager.mk am-post-upgrade-check"; \
	else \
		echo "Rollback cancelled."; \
	fi
