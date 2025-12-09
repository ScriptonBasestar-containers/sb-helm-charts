# Promtail Operations Makefile
# Usage: make -f make/ops/promtail.mk <target>

include make/Makefile.common.mk

CHART_NAME := promtail
CHART_DIR := charts/$(CHART_NAME)

# Promtail specific variables
NAMESPACE ?= default
RELEASE_NAME ?= my-promtail
NODE ?=
POD_SELECTOR := app.kubernetes.io/name=$(CHART_NAME)

# Backup variables
BACKUP_DIR ?= ./backups/promtail
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

.PHONY: help
help:
	@echo "Promtail Operations Makefile"
	@echo ""
	@echo "=== Access & Debugging ==="
	@echo "  pt-shell                     - Open shell in a Promtail pod"
	@echo "  pt-shell-node                - Open shell in Promtail pod on specific node (NODE=node-name)"
	@echo "  pt-logs                      - View logs from all Promtail pods"
	@echo "  pt-logs-node                 - View logs from Promtail on specific node (NODE=node-name)"
	@echo "  pt-logs-errors               - View error logs from all Promtail pods"
	@echo "  pt-port-forward              - Port-forward to Promtail metrics endpoint (3101)"
	@echo "  pt-restart                   - Restart Promtail DaemonSet"
	@echo "  pt-describe                  - Describe Promtail DaemonSet"
	@echo "  pt-events                    - Show Promtail-related events"
	@echo ""
	@echo "=== Status & Monitoring ==="
	@echo "  pt-status                    - Show DaemonSet and pod status"
	@echo "  pt-health                    - Check Promtail health endpoints"
	@echo "  pt-version                   - Get Promtail version"
	@echo "  pt-metrics                   - Get Promtail metrics"
	@echo "  pt-targets                   - Show active scrape targets"
	@echo "  pt-list-nodes                - List all nodes running Promtail"
	@echo ""
	@echo "=== Configuration ==="
	@echo "  pt-config                    - Show Promtail configuration"
	@echo "  pt-validate-config           - Validate Promtail configuration syntax"
	@echo "  pt-positions                 - Show positions file content"
	@echo "  pt-clear-positions           - Clear positions file (will re-read logs)"
	@echo ""
	@echo "=== Loki Integration ==="
	@echo "  pt-test-loki                 - Test connection to Loki"
	@echo "  pt-test-log-shipping         - Test log shipping to Loki"
	@echo "  pt-check-logs-path           - Check if log paths are accessible"
	@echo ""
	@echo "=== Backup & Recovery ==="
	@echo "  pt-backup-config             - Backup Promtail ConfigMap"
	@echo "  pt-backup-positions          - Backup positions file from all pods"
	@echo "  pt-backup-manifest           - Backup Kubernetes manifests"
	@echo "  pt-full-backup               - Full backup (config + positions + manifest)"
	@echo "  pt-backup-status             - Show backup directory status"
	@echo "  pt-restore-config            - Restore Promtail ConfigMap from backup"
	@echo ""
	@echo "=== Upgrade Support ==="
	@echo "  pt-pre-upgrade-check         - Pre-upgrade validation"
	@echo "  pt-post-upgrade-check        - Post-upgrade validation"
	@echo "  pt-upgrade-rollback          - Rollback to previous Helm revision"
	@echo ""
	@echo "=== Debug & Troubleshooting ==="
	@echo "  pt-debug                     - Show comprehensive debug information"
	@echo "  pt-debug-node                - Debug specific node (NODE=node-name)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Access & Debugging
.PHONY: pt-shell pt-shell-node pt-logs pt-logs-node pt-logs-errors pt-port-forward pt-restart pt-describe pt-events

## pt-shell: Open shell in a Promtail pod
.PHONY: pt-shell
pt-shell:
	@echo "=== Opening shell in Promtail pod ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Pod: $$POD"; \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## pt-shell-node: Open shell in Promtail pod on specific node
.PHONY: pt-shell-node
pt-shell-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk pt-shell-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "=== Opening shell in Promtail pod on node $(NODE) ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Pod: $$POD"; \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## pt-logs: View logs from all Promtail pods
.PHONY: pt-logs
pt-logs:
	@echo "=== Fetching logs from all Promtail pods ==="
	kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=100 -f

## pt-logs-node: View logs from Promtail on specific node
.PHONY: pt-logs-node
pt-logs-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk pt-logs-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "=== Fetching logs from Promtail on node $(NODE) ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl logs -n $(NAMESPACE) $$POD --tail=100 -f

## pt-logs-errors: View error logs from all Promtail pods
.PHONY: pt-logs-errors
pt-logs-errors:
	@echo "=== Fetching error logs from all Promtail pods ==="
	kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=500 | grep -i "error\|fail\|fatal"

## pt-port-forward: Port-forward to Promtail metrics endpoint
.PHONY: pt-port-forward
pt-port-forward:
	@echo "=== Port-forwarding to Promtail metrics endpoint ==="
	@echo "Metrics will be available at http://localhost:3101/metrics"
	@echo "Targets at http://localhost:3101/targets"
	@echo "Health at http://localhost:3101/ready"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl port-forward -n $(NAMESPACE) $$POD 3101:3101

## pt-restart: Restart Promtail DaemonSet
.PHONY: pt-restart
pt-restart:
	@echo "=== Restarting Promtail DaemonSet ==="
	kubectl rollout restart daemonset/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status daemonset/$(RELEASE_NAME) -n $(NAMESPACE)

## pt-describe: Describe Promtail DaemonSet
.PHONY: pt-describe
pt-describe:
	@echo "=== Describing Promtail DaemonSet ==="
	kubectl describe daemonset -n $(NAMESPACE) $(RELEASE_NAME)

## pt-events: Show Promtail-related events
.PHONY: pt-events
pt-events:
	@echo "=== Promtail Events ==="
	kubectl get events -n $(NAMESPACE) --field-selector involvedObject.name=$(RELEASE_NAME) --sort-by='.lastTimestamp'

# Status & Monitoring
.PHONY: pt-status pt-health pt-version pt-metrics pt-targets pt-list-nodes

## pt-status: Show DaemonSet and pod status
.PHONY: pt-status
pt-status:
	@echo "=== Promtail Status ==="
	@echo ""
	@echo "DaemonSet:"
	@kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o wide
	@echo ""
	@echo "Node Distribution:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) \
		-o custom-columns=NODE:.spec.nodeName,POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount

## pt-health: Check Promtail health endpoints
.PHONY: pt-health
pt-health:
	@echo "=== Promtail Health Check ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Pod: $$POD"; \
	echo ""; \
	echo "Readiness:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/ready || echo "Failed"; \
	echo ""; \
	echo "Metrics endpoint:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics | head -5 || echo "Failed"

## pt-version: Get Promtail version
.PHONY: pt-version
pt-version:
	@echo "=== Promtail Version ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- /usr/bin/promtail --version 2>&1 || \
	kubectl exec -n $(NAMESPACE) $$POD -- promtail --version 2>&1 || \
	echo "Could not determine version"

## pt-metrics: Get Promtail metrics
.PHONY: pt-metrics
pt-metrics:
	@echo "=== Promtail Metrics ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics | grep -E "promtail_sent_entries_total|promtail_dropped_entries_total|promtail_targets_active|promtail_sent_bytes_total"

## pt-targets: Show active scrape targets
.PHONY: pt-targets
pt-targets:
	@echo "=== Promtail Active Targets ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/targets

## pt-list-nodes: List all nodes running Promtail
.PHONY: pt-list-nodes
pt-list-nodes:
	@echo "=== Nodes Running Promtail ==="
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) \
		-o custom-columns=NODE:.spec.nodeName,POD:.metadata.name,STATUS:.status.phase,STARTED:.status.startTime

# Configuration
.PHONY: pt-config pt-validate-config pt-positions pt-clear-positions

## pt-config: Show Promtail configuration
.PHONY: pt-config
pt-config:
	@echo "=== Promtail Configuration ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /etc/promtail/promtail.yaml || \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-config -o yaml

## pt-validate-config: Validate Promtail configuration syntax
.PHONY: pt-validate-config
pt-validate-config:
	@echo "=== Validating Promtail Configuration ==="
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-config -o yaml > /tmp/promtail-config-validate.yaml
	@echo "Checking YAML syntax..."
	@yamllint /tmp/promtail-config-validate.yaml || echo "YAML syntax validation failed"
	@echo "Configuration exported to /tmp/promtail-config-validate.yaml for manual review"

## pt-positions: Show positions file content
.PHONY: pt-positions
pt-positions:
	@echo "=== Promtail Positions File ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Pod: $$POD"; \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /run/promtail/positions.yaml 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /tmp/positions.yaml 2>/dev/null || \
	echo "Positions file not found"

## pt-clear-positions: Clear positions file (will re-read logs)
.PHONY: pt-clear-positions
pt-clear-positions:
	@echo "=== Clearing Promtail Positions File ==="
	@echo "WARNING: This will cause Promtail to re-read logs from current position"
	@read -p "Continue? (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
		echo "Clearing positions file in pod: $$POD"; \
		kubectl exec -n $(NAMESPACE) $$POD -- rm -f /run/promtail/positions.yaml /tmp/positions.yaml; \
		echo "Restarting pod to apply changes..."; \
		kubectl delete pod -n $(NAMESPACE) $$POD; \
		echo "Done. Promtail will start reading from current log position."; \
	else \
		echo "Operation cancelled"; \
	fi

# Loki Integration
.PHONY: pt-test-loki pt-test-log-shipping pt-check-logs-path

## pt-test-loki: Test connection to Loki
.PHONY: pt-test-loki
pt-test-loki:
	@echo "=== Testing Connection to Loki ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	LOKI_URL=$$(kubectl get cm -n $(NAMESPACE) $(RELEASE_NAME)-config -o jsonpath='{.data.promtail\.yaml}' | grep 'url:' | head -1 | awk '{print $$2}' | sed 's|/loki/api/v1/push|/ready|'); \
	echo "Loki URL: $$LOKI_URL"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- $$LOKI_URL || echo "Failed to connect to Loki"

## pt-test-log-shipping: Test log shipping to Loki
.PHONY: pt-test-log-shipping
pt-test-log-shipping:
	@echo "=== Testing Log Shipping to Loki ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Checking sent_entries metric..."; \
	SENT_ENTRIES=$$(kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics 2>/dev/null | grep "promtail_sent_entries_total" | head -1 | awk '{print $$2}'); \
	echo "Sent entries: $$SENT_ENTRIES"; \
	if [ -n "$$SENT_ENTRIES" ] && [ "$$SENT_ENTRIES" -gt 0 ]; then \
		echo "✅ Log shipping is working"; \
	else \
		echo "❌ No logs have been sent to Loki"; \
	fi

## pt-check-logs-path: Check if log paths are accessible
.PHONY: pt-check-logs-path
pt-check-logs-path:
	@echo "=== Checking Log Paths Accessibility ==="
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Pod: $$POD"; \
	echo ""; \
	echo "Checking /var/log/pods (CRI runtimes):"; \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -la /var/log/pods | head -10 || echo "Not accessible"; \
	echo ""; \
	echo "Checking /var/lib/docker/containers (Docker):"; \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -la /var/lib/docker/containers 2>/dev/null | head -10 || echo "Not accessible or doesn't exist"

# Backup & Recovery
.PHONY: pt-backup-config pt-backup-positions pt-backup-manifest pt-full-backup pt-backup-status pt-restore-config

## pt-backup-config: Backup Promtail ConfigMap
.PHONY: pt-backup-config
pt-backup-config:
	@echo "=== Backing Up Promtail ConfigMap ==="
	@mkdir -p $(BACKUP_DIR)/config-$(TIMESTAMP)
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-config -o yaml \
		> $(BACKUP_DIR)/config-$(TIMESTAMP)/configmap.yaml
	@helm get values $(RELEASE_NAME) -n $(NAMESPACE) \
		> $(BACKUP_DIR)/config-$(TIMESTAMP)/values.yaml 2>/dev/null || echo "Could not export Helm values"
	@echo "ConfigMap backup saved to: $(BACKUP_DIR)/config-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/config-$(TIMESTAMP)/

## pt-backup-positions: Backup positions file from all pods
.PHONY: pt-backup-positions
pt-backup-positions:
	@echo "=== Backing Up Promtail Positions File ==="
	@mkdir -p $(BACKUP_DIR)/positions-$(TIMESTAMP)
	@PODS=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[*].metadata.name}'); \
	for POD in $$PODS; do \
		echo "Backing up positions from pod: $$POD"; \
		kubectl exec -n $(NAMESPACE) $$POD -- cat /run/promtail/positions.yaml \
			> $(BACKUP_DIR)/positions-$(TIMESTAMP)/positions-$$POD.yaml 2>/dev/null || \
		kubectl exec -n $(NAMESPACE) $$POD -- cat /tmp/positions.yaml \
			> $(BACKUP_DIR)/positions-$(TIMESTAMP)/positions-$$POD.yaml 2>/dev/null || \
		echo "  No positions file found in $$POD"; \
	done
	@echo "Positions backup saved to: $(BACKUP_DIR)/positions-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/positions-$(TIMESTAMP)/ || echo "No positions files backed up"

## pt-backup-manifest: Backup Kubernetes manifests
.PHONY: pt-backup-manifest
pt-backup-manifest:
	@echo "=== Backing Up Kubernetes Manifests ==="
	@mkdir -p $(BACKUP_DIR)/manifest-$(TIMESTAMP)
	@helm get manifest $(RELEASE_NAME) -n $(NAMESPACE) \
		> $(BACKUP_DIR)/manifest-$(TIMESTAMP)/manifest.yaml 2>/dev/null || echo "Could not export Helm manifest"
	@kubectl get daemonset,serviceaccount,clusterrole,clusterrolebinding,service,configmap \
		-n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o yaml \
		> $(BACKUP_DIR)/manifest-$(TIMESTAMP)/resources.yaml 2>/dev/null || echo "Could not export resources"
	@echo "Manifest backup saved to: $(BACKUP_DIR)/manifest-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/manifest-$(TIMESTAMP)/

## pt-full-backup: Full backup (config + positions + manifest)
.PHONY: pt-full-backup
pt-full-backup:
	@echo "=== Full Promtail Backup ==="
	@mkdir -p $(BACKUP_DIR)/full-$(TIMESTAMP)
	@echo "1/3 Backing up ConfigMap..."
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-config -o yaml \
		> $(BACKUP_DIR)/full-$(TIMESTAMP)/configmap.yaml
	@helm get values $(RELEASE_NAME) -n $(NAMESPACE) \
		> $(BACKUP_DIR)/full-$(TIMESTAMP)/values.yaml 2>/dev/null || echo "  Could not export Helm values"
	@echo "2/3 Backing up positions file..."
	@mkdir -p $(BACKUP_DIR)/full-$(TIMESTAMP)/positions
	@PODS=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[*].metadata.name}'); \
	for POD in $$PODS; do \
		kubectl exec -n $(NAMESPACE) $$POD -- cat /run/promtail/positions.yaml \
			> $(BACKUP_DIR)/full-$(TIMESTAMP)/positions/positions-$$POD.yaml 2>/dev/null || \
		kubectl exec -n $(NAMESPACE) $$POD -- cat /tmp/positions.yaml \
			> $(BACKUP_DIR)/full-$(TIMESTAMP)/positions/positions-$$POD.yaml 2>/dev/null || true; \
	done
	@echo "3/3 Backing up Kubernetes manifests..."
	@helm get manifest $(RELEASE_NAME) -n $(NAMESPACE) \
		> $(BACKUP_DIR)/full-$(TIMESTAMP)/manifest.yaml 2>/dev/null || echo "  Could not export Helm manifest"
	@echo ""
	@echo "=== Full Backup Complete ==="
	@echo "Backup location: $(BACKUP_DIR)/full-$(TIMESTAMP)/"
	@echo "Files:"
	@ls -lh $(BACKUP_DIR)/full-$(TIMESTAMP)/ || true
	@ls -lh $(BACKUP_DIR)/full-$(TIMESTAMP)/positions/ 2>/dev/null || echo "  No positions files"

## pt-backup-status: Show backup directory status
.PHONY: pt-backup-status
pt-backup-status:
	@echo "=== Backup Directory Status ==="
	@echo "Backup directory: $(BACKUP_DIR)"
	@if [ -d "$(BACKUP_DIR)" ]; then \
		echo ""; \
		echo "Recent backups:"; \
		ls -lt $(BACKUP_DIR) | head -10; \
		echo ""; \
		echo "Disk usage:"; \
		du -sh $(BACKUP_DIR); \
	else \
		echo "Backup directory does not exist"; \
	fi

## pt-restore-config: Restore Promtail ConfigMap from backup
.PHONY: pt-restore-config
pt-restore-config:
	@if [ -z "$(BACKUP_PATH)" ]; then \
		echo "Error: BACKUP_PATH parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk pt-restore-config BACKUP_PATH=./backups/promtail/config-20250609-143022"; \
		exit 1; \
	fi
	@echo "=== Restoring Promtail ConfigMap ==="
	@echo "Backup path: $(BACKUP_PATH)"
	@if [ ! -f "$(BACKUP_PATH)/configmap.yaml" ]; then \
		echo "Error: ConfigMap backup not found at $(BACKUP_PATH)/configmap.yaml"; \
		exit 1; \
	fi
	@kubectl apply -f $(BACKUP_PATH)/configmap.yaml
	@echo "ConfigMap restored. Restarting Promtail pods..."
	@kubectl rollout restart daemonset/$(RELEASE_NAME) -n $(NAMESPACE)
	@kubectl rollout status daemonset/$(RELEASE_NAME) -n $(NAMESPACE)

# Upgrade Support
.PHONY: pt-pre-upgrade-check pt-post-upgrade-check pt-upgrade-rollback

## pt-pre-upgrade-check: Pre-upgrade validation
.PHONY: pt-pre-upgrade-check
pt-pre-upgrade-check:
	@echo "=== Promtail Pre-Upgrade Check ==="
	@echo ""
	@echo "1/5 Checking Helm release..."
	@helm list -n $(NAMESPACE) | grep $(RELEASE_NAME) || (echo "❌ Helm release not found" && exit 1)
	@echo "✅ Helm release found"
	@echo ""
	@echo "2/5 Checking DaemonSet status..."
	@DESIRED=$$(kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.status.desiredNumberScheduled}'); \
	READY=$$(kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.status.numberReady}'); \
	echo "Desired: $$DESIRED, Ready: $$READY"; \
	if [ "$$DESIRED" != "$$READY" ]; then \
		echo "❌ Not all pods are ready"; \
		exit 1; \
	fi
	@echo "✅ All pods are ready"
	@echo ""
	@echo "3/5 Checking for errors in logs..."
	@ERRORS=$$(kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=100 --since=5m 2>/dev/null | grep -i "error\|fatal" | wc -l); \
	echo "Errors found: $$ERRORS"; \
	if [ "$$ERRORS" -gt 5 ]; then \
		echo "⚠️  WARNING: Many errors found in recent logs"; \
	else \
		echo "✅ No critical errors"; \
	fi
	@echo ""
	@echo "4/5 Testing Loki connectivity..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	LOKI_URL=$$(kubectl get cm -n $(NAMESPACE) $(RELEASE_NAME)-config -o jsonpath='{.data.promtail\.yaml}' | grep 'url:' | head -1 | awk '{print $$2}' | sed 's|/loki/api/v1/push|/ready|'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- $$LOKI_URL >/dev/null 2>&1 && echo "✅ Loki is reachable" || echo "⚠️  WARNING: Loki is unreachable"
	@echo ""
	@echo "5/5 Creating pre-upgrade backup..."
	@make -f make/ops/promtail.mk pt-full-backup BACKUP_DIR=$(BACKUP_DIR)
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo "Status: ✅ Ready for upgrade"

## pt-post-upgrade-check: Post-upgrade validation
.PHONY: pt-post-upgrade-check
pt-post-upgrade-check:
	@echo "=== Promtail Post-Upgrade Validation ==="
	@echo ""
	@echo "1/5 Checking Helm release status..."
	@HELM_STATUS=$$(helm status $(RELEASE_NAME) -n $(NAMESPACE) -o json | jq -r '.info.status'); \
	if [ "$$HELM_STATUS" != "deployed" ]; then \
		echo "❌ FAIL: Helm release status is $$HELM_STATUS (expected: deployed)"; \
		exit 1; \
	fi
	@echo "✅ PASS: Helm release is deployed"
	@echo ""
	@echo "2/5 Checking DaemonSet rollout..."
	@kubectl rollout status daemonset/$(RELEASE_NAME) -n $(NAMESPACE) --timeout=5m
	@echo "✅ PASS: DaemonSet rollout complete"
	@echo ""
	@echo "3/5 Checking all pods are running..."
	@DESIRED=$$(kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.status.desiredNumberScheduled}'); \
	READY=$$(kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.status.numberReady}'); \
	echo "Desired: $$DESIRED, Ready: $$READY"; \
	if [ "$$DESIRED" != "$$READY" ]; then \
		echo "❌ FAIL: Only $$READY/$$DESIRED pods are ready"; \
		kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR); \
		exit 1; \
	fi
	@echo "✅ PASS: All $$READY pods are running"
	@echo ""
	@echo "4/5 Checking for errors in logs..."
	@ERRORS=$$(kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=100 --since=5m 2>/dev/null | grep -i "error" | wc -l); \
	echo "Errors found: $$ERRORS"; \
	if [ "$$ERRORS" -gt 5 ]; then \
		echo "⚠️  WARNING: Found $$ERRORS errors in logs (check manually)"; \
		kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=100 --since=5m | grep -i "error"; \
	else \
		echo "✅ PASS: No critical errors in recent logs"; \
	fi
	@echo ""
	@echo "5/5 Checking log shipping..."
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	SENT_ENTRIES=$$(kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics 2>/dev/null | grep "promtail_sent_entries_total" | head -1 | awk '{print $$2}'); \
	if [ -n "$$SENT_ENTRIES" ] && [ "$$SENT_ENTRIES" -gt 0 ]; then \
		echo "✅ PASS: Promtail is sending logs (sent_entries: $$SENT_ENTRIES)"; \
	else \
		echo "⚠️  WARNING: No logs sent to Loki yet"; \
	fi
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="
	@echo "Status: ✅ Upgrade successful"

## pt-upgrade-rollback: Rollback to previous Helm revision
.PHONY: pt-upgrade-rollback
pt-upgrade-rollback:
	@echo "=== Promtail Upgrade Rollback ==="
	@echo ""
	@echo "Helm history:"
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Enter revision number to rollback to (or press Enter to rollback to previous): " REVISION; \
	if [ -z "$$REVISION" ]; then \
		echo "Rolling back to previous revision..."; \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE); \
	else \
		echo "Rolling back to revision $$REVISION..."; \
		helm rollback $(RELEASE_NAME) $$REVISION -n $(NAMESPACE); \
	fi
	@echo ""
	@echo "Waiting for rollback to complete..."
	@kubectl rollout status daemonset/$(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@echo "=== Rollback Complete ==="
	@make -f make/ops/promtail.mk pt-status

# Debug & Troubleshooting
.PHONY: pt-debug pt-debug-node

## pt-debug: Show comprehensive debug information
.PHONY: pt-debug
pt-debug:
	@echo "=== Promtail Debug Information ==="
	@echo ""
	@echo "1. Helm Release:"
	@helm list -n $(NAMESPACE) | grep $(RELEASE_NAME) || echo "  Not found"
	@echo ""
	@echo "2. DaemonSet Status:"
	@kubectl get daemonset -n $(NAMESPACE) $(RELEASE_NAME)
	@echo ""
	@echo "3. Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o wide
	@echo ""
	@echo "4. Recent Events:"
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep promtail | tail -10
	@echo ""
	@echo "5. Recent Logs (last 20 lines from each pod):"
	@kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=20 --prefix
	@echo ""
	@echo "6. Loki Connection Test:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	LOKI_URL=$$(kubectl get cm -n $(NAMESPACE) $(RELEASE_NAME)-config -o jsonpath='{.data.promtail\.yaml}' | grep 'url:' | head -1 | awk '{print $$2}' | sed 's|/loki/api/v1/push|/ready|'); \
	echo "  Testing Loki at: $$LOKI_URL"; \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- $$LOKI_URL 2>&1 || echo "  Failed to connect to Loki"
	@echo ""
	@echo "7. Metrics Summary:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath="{.items[0].metadata.name}"); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:3101/metrics 2>/dev/null | \
		grep -E "promtail_sent_entries_total|promtail_dropped_entries_total|promtail_targets_active" || echo "  Could not fetch metrics"

## pt-debug-node: Debug specific node
.PHONY: pt-debug-node
pt-debug-node:
	@if [ -z "$(NODE)" ]; then \
		echo "Error: NODE parameter is required"; \
		echo "Usage: make -f make/ops/promtail.mk pt-debug-node NODE=node-name"; \
		exit 1; \
	fi
	@echo "=== Promtail Debug Information for Node: $(NODE) ==="
	@echo ""
	@echo "1. Pod on Node:"
	@POD=$$(kubectl get pod -n $(NAMESPACE) -l $(POD_SELECTOR) --field-selector spec.nodeName=$(NODE) -o jsonpath="{.items[0].metadata.name}"); \
	if [ -z "$$POD" ]; then \
		echo "  No Promtail pod found on node $(NODE)"; \
		exit 1; \
	fi; \
	echo "  Pod: $$POD"; \
	echo ""; \
	echo "2. Pod Status:"; \
	kubectl get pod -n $(NAMESPACE) $$POD -o wide; \
	echo ""; \
	echo "3. Pod Logs (last 50 lines):"; \
	kubectl logs -n $(NAMESPACE) $$POD --tail=50; \
	echo ""; \
	echo "4. Log Paths Accessibility:"; \
	echo "  /var/log/pods:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- ls /var/log/pods | head -5 || echo "  Not accessible"; \
	echo ""; \
	echo "5. Positions File:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /run/promtail/positions.yaml 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /tmp/positions.yaml 2>/dev/null || \
	echo "  Positions file not found"
