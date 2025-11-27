# Prometheus Operations Makefile
# Usage: make -f make/ops/prometheus.mk <target>

include make/Makefile.common.mk

CHART_NAME := prometheus
CHART_DIR := charts/$(CHART_NAME)

# Prometheus specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= prometheus
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Prometheus Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  prom-logs                   - View Prometheus logs"
	@echo "  prom-logs-all               - View logs from all Prometheus pods"
	@echo "  prom-shell                  - Open shell in Prometheus pod"
	@echo "  prom-port-forward           - Port forward Prometheus (9090)"
	@echo "  prom-restart                - Restart Prometheus StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  prom-ready                  - Check if Prometheus is ready"
	@echo "  prom-healthy                - Check if Prometheus is healthy"
	@echo "  prom-version                - Get Prometheus version"
	@echo "  prom-config                 - Show current Prometheus configuration"
	@echo "  prom-config-check           - Validate Prometheus configuration"
	@echo "  prom-flags                  - Show Prometheus runtime flags"
	@echo "  prom-runtime-info           - Show runtime information"
	@echo ""
	@echo "Targets & Service Discovery:"
	@echo "  prom-targets                - List all scrape targets"
	@echo "  prom-targets-active         - List only active targets"
	@echo "  prom-sd                     - Show service discovery status"
	@echo ""
	@echo "Metrics & Queries:"
	@echo "  prom-query                  - Execute PromQL query (QUERY='up')"
	@echo "  prom-query-range            - Execute range query (QUERY='up' START='-1h' END='now' STEP='15s')"
	@echo "  prom-labels                 - List all label names"
	@echo "  prom-label-values           - Get values for a label (LABEL=job)"
	@echo "  prom-series                 - List all time series (MATCH='{job=\"prometheus\"}')"
	@echo "  prom-metrics                - Get Prometheus own metrics"
	@echo ""
	@echo "TSDB & Storage:"
	@echo "  prom-tsdb-status            - Get TSDB status"
	@echo "  prom-tsdb-snapshot          - Create TSDB snapshot (requires admin API)"
	@echo "  prom-check-storage          - Check storage usage"
	@echo ""
	@echo "Configuration Reload:"
	@echo "  prom-reload                 - Reload configuration (requires --web.enable-lifecycle)"
	@echo ""
	@echo "Rules & Alerts:"
	@echo "  prom-rules                  - List all recording/alerting rules"
	@echo "  prom-alerts                 - Show active alerts"
	@echo ""
	@echo "Testing:"
	@echo "  prom-test-query             - Run sample queries to verify Prometheus"
	@echo ""
	@echo "Scaling:"
	@echo "  prom-scale                  - Scale Prometheus (REPLICAS=2)"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  prom-backup-tsdb            - Backup TSDB snapshot"
	@echo "  prom-backup-config          - Backup configuration"
	@echo "  prom-backup-rules           - Backup recording/alerting rules"
	@echo "  prom-backup-all             - Full backup (TSDB + config + rules)"
	@echo "  prom-backup-verify          - Verify backup integrity (BACKUP_FILE=<path>)"
	@echo "  prom-restore-config         - Restore configuration (BACKUP_FILE=<path>)"
	@echo "  prom-restore-tsdb           - Restore TSDB snapshot (BACKUP_FILE=<path>)"
	@echo "  prom-restore-all            - Full restore (BACKUP_FILE=<path>)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  prom-pre-upgrade-check      - Pre-upgrade validation (10 checks)"
	@echo "  prom-post-upgrade-check     - Post-upgrade validation (8 checks)"
	@echo "  prom-health-check           - Quick health check"
	@echo "  prom-upgrade-rollback       - Rollback to previous Helm revision"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: prom-logs prom-logs-all prom-shell prom-port-forward prom-restart

prom-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

prom-logs-all:
	@echo "Fetching logs from all Prometheus pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

prom-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

prom-port-forward:
	@echo "Port forwarding Prometheus to localhost:9090..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9090:9090

prom-restart:
	@echo "Restarting Prometheus StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: prom-ready prom-healthy prom-version prom-config prom-config-check prom-flags prom-runtime-info

prom-ready:
	@echo "Checking if Prometheus is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/-/ready

prom-healthy:
	@echo "Checking if Prometheus is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/-/healthy

prom-version:
	@echo "Getting Prometheus version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- prometheus --version

prom-config:
	@echo "Showing current Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/prometheus/prometheus.yml

prom-config-check:
	@echo "Validating Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- promtool check config /etc/prometheus/prometheus.yml

prom-flags:
	@echo "Showing Prometheus runtime flags..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/flags | grep -o '"[^"]*":"[^"]*"' | sed 's/"//g' | column -t -s ':'

prom-runtime-info:
	@echo "Showing runtime information..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/runtimeinfo

# Targets & Service Discovery
.PHONY: prom-targets prom-targets-active prom-sd

prom-targets:
	@echo "Listing all scrape targets..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/targets

prom-targets-active:
	@echo "Listing only active targets..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- 'http://localhost:9090/api/v1/targets?state=active'

prom-sd:
	@echo "Showing service discovery status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/service-discovery

# Metrics & Queries
.PHONY: prom-query prom-query-range prom-labels prom-label-values prom-series prom-metrics

QUERY ?= up
START ?= -1h
END ?= now
STEP ?= 15s
LABEL ?= job
MATCH ?= {job="prometheus"}

prom-query:
	@echo "Executing query: $(QUERY)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

prom-query-range:
	@echo "Executing range query: $(QUERY) from $(START) to $(END) step $(STEP)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c "wget -qO- 'http://localhost:9090/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s)&end=$$(date -d '$(END)' +%s)&step=$(STEP)'"

prom-labels:
	@echo "Listing all label names..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/labels

prom-label-values:
	@echo "Getting values for label '$(LABEL)'..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/label/$(LABEL)/values

prom-series:
	@echo "Listing time series matching: $(MATCH)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/series?match[]=$(MATCH)"

prom-metrics:
	@echo "Fetching Prometheus own metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/metrics

# TSDB & Storage
.PHONY: prom-tsdb-status prom-tsdb-snapshot prom-check-storage

prom-tsdb-status:
	@echo "Getting TSDB status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/tsdb

prom-tsdb-snapshot:
	@echo "Creating TSDB snapshot (requires admin API)..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot

prom-check-storage:
	@echo "Checking storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /prometheus

# Configuration Reload
.PHONY: prom-reload

prom-reload:
	@echo "Reloading Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --post-data='' http://localhost:9090/-/reload

# Rules & Alerts
.PHONY: prom-rules prom-alerts

prom-rules:
	@echo "Listing all recording/alerting rules..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/rules

prom-alerts:
	@echo "Showing active alerts..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/alerts

# Testing
.PHONY: prom-test-query

prom-test-query:
	@echo "Running sample queries..."
	@echo ""
	@echo "1. Check if Prometheus is scraping itself:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"prometheus\"}"
	@echo ""
	@echo "2. Count all time series:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=count(up)"
	@echo ""
	@echo "3. Show scrape duration:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=scrape_duration_seconds"

# Scaling
.PHONY: prom-scale

REPLICAS ?= 2

prom-scale:
	@echo "Scaling Prometheus to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Backup & Recovery Operations
# =============================================================================

BACKUP_DIR ?= ./backups/prometheus
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
S3_BUCKET ?=

.PHONY: prom-backup-tsdb prom-backup-config prom-backup-rules prom-backup-all prom-backup-verify prom-restore-config prom-restore-tsdb prom-restore-all

# Backup TSDB snapshot
prom-backup-tsdb:
	@echo "=== Prometheus TSDB Snapshot Backup ==="
	@mkdir -p $(BACKUP_DIR)/tsdb/$(TIMESTAMP)
	@echo "Creating TSDB snapshot..."
	@SNAPSHOT_JSON=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot 2>/dev/null); \
	SNAPSHOT_NAME=$$(echo $$SNAPSHOT_JSON | grep -o '"name":"[^"]*"' | cut -d'"' -f4); \
	if [ -z "$$SNAPSHOT_NAME" ]; then \
		echo "Error: Failed to create snapshot"; \
		exit 1; \
	fi; \
	echo "Snapshot created: $$SNAPSHOT_NAME"; \
	echo "Copying snapshot from pod..."; \
	kubectl cp $(NAMESPACE)/$(POD_NAME):/prometheus/snapshots/$$SNAPSHOT_NAME \
		$(BACKUP_DIR)/tsdb/$(TIMESTAMP)/snapshot -c $(CONTAINER_NAME); \
	echo "Creating metadata..."; \
	echo "{\"snapshot_name\":\"$$SNAPSHOT_NAME\",\"timestamp\":\"$(TIMESTAMP)\",\"namespace\":\"$(NAMESPACE)\",\"pod\":\"$(POD_NAME)\"}" > \
		$(BACKUP_DIR)/tsdb/$(TIMESTAMP)/metadata.json; \
	echo "Compressing backup..."; \
	cd $(BACKUP_DIR)/tsdb && tar -czf $(TIMESTAMP).tar.gz $(TIMESTAMP)/ && rm -rf $(TIMESTAMP)/; \
	echo "Cleaning up snapshot in pod..."; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		rm -rf /prometheus/snapshots/$$SNAPSHOT_NAME; \
	echo "TSDB backup completed: $(BACKUP_DIR)/tsdb/$(TIMESTAMP).tar.gz"

# Backup configuration
prom-backup-config:
	@echo "=== Prometheus Configuration Backup ==="
	@mkdir -p $(BACKUP_DIR)/config/$(TIMESTAMP)
	@echo "Backing up ConfigMap..."
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-server -o yaml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/configmap.yaml
	@echo "Backing up runtime configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		cat /etc/prometheus/prometheus.yml > $(BACKUP_DIR)/config/$(TIMESTAMP)/prometheus.yml
	@echo "Validating configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		promtool check config /etc/prometheus/prometheus.yml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/validation.txt 2>&1 || true
	@echo "Creating metadata..."
	@echo "{\"timestamp\":\"$(TIMESTAMP)\",\"namespace\":\"$(NAMESPACE)\",\"release\":\"$(CHART_NAME)\"}" > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/metadata.json
	@echo "Compressing backup..."
	@cd $(BACKUP_DIR)/config && tar -czf $(TIMESTAMP).tar.gz $(TIMESTAMP)/ && rm -rf $(TIMESTAMP)/
	@echo "Configuration backup completed: $(BACKUP_DIR)/config/$(TIMESTAMP).tar.gz"

# Backup rules
prom-backup-rules:
	@echo "=== Prometheus Rules Backup ==="
	@mkdir -p $(BACKUP_DIR)/rules/$(TIMESTAMP)
	@echo "Backing up rules ConfigMap..."
	@if kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-rules &>/dev/null; then \
		kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-rules -o yaml > \
			$(BACKUP_DIR)/rules/$(TIMESTAMP)/rules-configmap.yaml; \
	else \
		echo "No rules ConfigMap found"; \
	fi
	@echo "Exporting loaded rules..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/rules > \
		$(BACKUP_DIR)/rules/$(TIMESTAMP)/loaded-rules.json
	@echo "Creating metadata..."
	@echo "{\"timestamp\":\"$(TIMESTAMP)\",\"namespace\":\"$(NAMESPACE)\",\"release\":\"$(CHART_NAME)\"}" > \
		$(BACKUP_DIR)/rules/$(TIMESTAMP)/metadata.json
	@echo "Compressing backup..."
	@cd $(BACKUP_DIR)/rules && tar -czf $(TIMESTAMP).tar.gz $(TIMESTAMP)/ && rm -rf $(TIMESTAMP)/
	@echo "Rules backup completed: $(BACKUP_DIR)/rules/$(TIMESTAMP).tar.gz"

# Full backup (TSDB + config + rules)
prom-backup-all:
	@echo "=== Prometheus Full Backup Started ==="
	@echo "Timestamp: $(TIMESTAMP)"
	@mkdir -p $(BACKUP_DIR)/full/$(TIMESTAMP)/{tsdb,config,rules,metadata}
	@echo ""
	@echo "[1/5] Creating TSDB snapshot..."
	@SNAPSHOT_JSON=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot 2>/dev/null); \
	SNAPSHOT_NAME=$$(echo $$SNAPSHOT_JSON | grep -o '"name":"[^"]*"' | cut -d'"' -f4); \
	if [ -n "$$SNAPSHOT_NAME" ]; then \
		echo "  Snapshot created: $$SNAPSHOT_NAME"; \
		kubectl cp $(NAMESPACE)/$(POD_NAME):/prometheus/snapshots/$$SNAPSHOT_NAME \
			$(BACKUP_DIR)/full/$(TIMESTAMP)/tsdb/snapshot -c $(CONTAINER_NAME); \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
			rm -rf /prometheus/snapshots/$$SNAPSHOT_NAME; \
		echo "  TSDB snapshot backed up"; \
	else \
		echo "  Warning: TSDB snapshot failed, continuing..."; \
	fi
	@echo ""
	@echo "[2/5] Backing up configuration..."
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-server -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/configmap.yaml
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		cat /etc/prometheus/prometheus.yml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/prometheus.yml
	@echo "  Configuration backed up"
	@echo ""
	@echo "[3/5] Backing up rules..."
	@if kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-rules &>/dev/null; then \
		kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-rules -o yaml > \
			$(BACKUP_DIR)/full/$(TIMESTAMP)/rules/rules-configmap.yaml; \
	fi
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/rules > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/rules/loaded-rules.json
	@echo "  Rules backed up"
	@echo ""
	@echo "[4/5] Creating metadata..."
	@PROM_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		prometheus --version 2>&1 | head -1 | awk '{print $$3}'); \
	echo "{\"timestamp\":\"$(TIMESTAMP)\",\"namespace\":\"$(NAMESPACE)\",\"release\":\"$(CHART_NAME)\",\"pod\":\"$(POD_NAME)\",\"prometheus_version\":\"$$PROM_VERSION\"}" > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/backup-info.json
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/status/tsdb > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/tsdb-status.json
	@echo "  Metadata created"
	@echo ""
	@echo "[5/5] Compressing backup..."
	@cd $(BACKUP_DIR)/full && tar -czf $(TIMESTAMP).tar.gz $(TIMESTAMP)/ && rm -rf $(TIMESTAMP)/
	@BACKUP_SIZE=$$(du -h $(BACKUP_DIR)/full/$(TIMESTAMP).tar.gz | cut -f1); \
	echo "  Backup compressed: $$BACKUP_SIZE"
	@echo ""
	@echo "=== Prometheus Full Backup Completed ==="
	@echo "Location: $(BACKUP_DIR)/full/$(TIMESTAMP).tar.gz"
	@echo "Timestamp: $(TIMESTAMP)"

# Verify backup integrity
prom-backup-verify:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/prometheus.mk prom-backup-verify BACKUP_FILE=<path>"; \
		exit 1; \
	fi
	@echo "=== Verifying Backup: $(BACKUP_FILE) ==="
	@echo "Extracting backup..."
	@mkdir -p /tmp/prom-verify-$$$$
	@tar -xzf $(BACKUP_FILE) -C /tmp/prom-verify-$$$$ 2>/dev/null || \
		(echo "Error: Failed to extract backup"; rm -rf /tmp/prom-verify-$$$$; exit 1)
	@echo "Checking backup structure..."
	@if [ ! -f /tmp/prom-verify-$$$$/*/metadata/backup-info.json ]; then \
		echo "Error: Missing metadata/backup-info.json"; \
		rm -rf /tmp/prom-verify-$$$$; \
		exit 1; \
	fi
	@if [ ! -f /tmp/prom-verify-$$$$/*/config/prometheus.yml ]; then \
		echo "Error: Missing config/prometheus.yml"; \
		rm -rf /tmp/prom-verify-$$$$; \
		exit 1; \
	fi
	@echo "✓ Backup structure is valid"
	@echo ""
	@echo "Backup metadata:"
	@cat /tmp/prom-verify-$$$$/*/metadata/backup-info.json | grep -o '"[^"]*":"[^"]*"' | sed 's/"//g'
	@rm -rf /tmp/prom-verify-$$$$
	@echo ""
	@echo "✓ Backup verification completed"

# Restore configuration
prom-restore-config:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/prometheus.mk prom-restore-config BACKUP_FILE=<path>"; \
		exit 1; \
	fi
	@echo "=== Restoring Prometheus Configuration ==="
	@echo "Extracting backup..."
	@mkdir -p /tmp/prom-restore-$$$$
	@tar -xzf $(BACKUP_FILE) -C /tmp/prom-restore-$$$$
	@CONFIGMAP=$$(find /tmp/prom-restore-$$$$ -name "configmap.yaml" | head -1); \
	if [ -z "$$CONFIGMAP" ]; then \
		echo "Error: No configmap.yaml found in backup"; \
		rm -rf /tmp/prom-restore-$$$$; \
		exit 1; \
	fi; \
	echo "Backing up current configuration..."; \
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-server -o yaml > \
		current-config-backup-$$(date +%Y%m%d-%H%M%S).yaml; \
	echo "Restoring configuration..."; \
	kubectl apply -f $$CONFIGMAP; \
	echo "Reloading Prometheus..."; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- --post-data='' http://localhost:9090/-/reload; \
	sleep 5; \
	echo "Verifying configuration..."; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		promtool check config /etc/prometheus/prometheus.yml
	@rm -rf /tmp/prom-restore-$$$$
	@echo "Configuration restoration completed"

# Restore TSDB snapshot
prom-restore-tsdb:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/prometheus.mk prom-restore-tsdb BACKUP_FILE=<path>"; \
		exit 1; \
	fi
	@echo "=== Restoring Prometheus TSDB Snapshot ==="
	@echo "WARNING: This will stop Prometheus and restore data!"
	@read -p "Continue? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Restoration cancelled"; \
		exit 0; \
	fi
	@echo "Extracting backup..."
	@mkdir -p /tmp/prom-restore-$$$$
	@tar -xzf $(BACKUP_FILE) -C /tmp/prom-restore-$$$$
	@SNAPSHOT_DIR=$$(find /tmp/prom-restore-$$$$ -type d -name "snapshot" | head -1); \
	if [ -z "$$SNAPSHOT_DIR" ]; then \
		echo "Error: No snapshot directory found in backup"; \
		rm -rf /tmp/prom-restore-$$$$; \
		exit 1; \
	fi; \
	echo "Stopping Prometheus..."; \
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=0; \
	kubectl wait --for=delete pod/$(POD_NAME) -n $(NAMESPACE) --timeout=120s; \
	echo "Creating restore helper pod..."; \
	kubectl run prometheus-restore-helper -n $(NAMESPACE) --image=busybox \
		--overrides='{"spec":{"containers":[{"name":"restore","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/prometheus"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"prometheus-$(CHART_NAME)-0"}}]}}' \
		--restart=Never; \
	kubectl wait --for=condition=Ready pod/prometheus-restore-helper -n $(NAMESPACE) --timeout=120s; \
	echo "Restoring snapshot data..."; \
	kubectl exec -n $(NAMESPACE) prometheus-restore-helper -- rm -rf /prometheus/*; \
	kubectl cp $$SNAPSHOT_DIR prometheus-restore-helper:/prometheus/data -n $(NAMESPACE); \
	echo "Cleaning up helper pod..."; \
	kubectl delete pod/prometheus-restore-helper -n $(NAMESPACE); \
	echo "Restarting Prometheus..."; \
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=1; \
	kubectl wait --for=condition=Ready pod/$(POD_NAME) -n $(NAMESPACE) --timeout=300s; \
	sleep 10; \
	echo "Verifying restoration..."; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/-/healthy
	@rm -rf /tmp/prom-restore-$$$$
	@echo "TSDB restoration completed"

# Restore full backup
prom-restore-all:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/prometheus.mk prom-restore-all BACKUP_FILE=<path>"; \
		exit 1; \
	fi
	@echo "=== Full Prometheus Restore ==="
	@echo "This will restore configuration, rules, and TSDB data"
	@echo "Restoring configuration..."
	@$(MAKE) -f make/ops/prometheus.mk prom-restore-config BACKUP_FILE=$(BACKUP_FILE)
	@echo ""
	@echo "Restoring TSDB data..."
	@$(MAKE) -f make/ops/prometheus.mk prom-restore-tsdb BACKUP_FILE=$(BACKUP_FILE)
	@echo ""
	@echo "Full restoration completed"

# =============================================================================
# Upgrade Support Operations
# =============================================================================

.PHONY: prom-pre-upgrade-check prom-post-upgrade-check prom-health-check prom-upgrade-rollback

# Pre-upgrade validation
prom-pre-upgrade-check:
	@echo "=== Prometheus Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/10] Checking current version..."
	@CURRENT_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		prometheus --version 2>&1 | head -1 | awk '{print $$3}'); \
	echo "  Current version: $$CURRENT_VERSION"
	@echo ""
	@echo "[2/10] Checking pod health..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS ✓"
	@echo ""
	@echo "[3/10] Checking if Prometheus is ready..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/-/ready >/dev/null 2>&1 && \
		echo "  Prometheus is ready ✓" || \
		(echo "  ERROR: Prometheus is not ready"; exit 1)
	@echo ""
	@echo "[4/10] Checking TSDB status..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/status/tsdb >/dev/null 2>&1 && \
		echo "  TSDB status: OK ✓" || \
		echo "  WARNING: TSDB status check failed"
	@echo ""
	@echo "[5/10] Checking active targets..."
	@ACTIVE_TARGETS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null | \
		grep -o '"job":"[^"]*"' | wc -l); \
	echo "  Active targets: $$ACTIVE_TARGETS"
	@echo ""
	@echo "[6/10] Checking storage usage..."
	@STORAGE_USED=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /prometheus 2>/dev/null | tail -1 | awk '{print $$5}'); \
	echo "  Storage used: $$STORAGE_USED"; \
	if [ -n "$$STORAGE_USED" ]; then \
		USAGE=$$(echo $$STORAGE_USED | sed 's/%//'); \
		if [ $$USAGE -gt 90 ]; then \
			echo "  WARNING: Storage usage above 90%"; \
		fi; \
	fi
	@echo ""
	@echo "[7/10] Validating configuration..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		promtool check config /etc/prometheus/prometheus.yml >/dev/null 2>&1 && \
		echo "  Configuration is valid ✓" || \
		(echo "  ERROR: Configuration validation failed"; exit 1)
	@echo ""
	@echo "[8/10] Checking PVC status..."
	@PVC_STATUS=$$(kubectl get pvc -n $(NAMESPACE) prometheus-$(CHART_NAME)-0 \
		-o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound"); \
	echo "  PVC status: $$PVC_STATUS"
	@echo ""
	@echo "[9/10] Checking for active alerts..."
	@ACTIVE_ALERTS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null | \
		grep -o '"state":"firing"' | wc -l); \
	echo "  Active firing alerts: $$ACTIVE_ALERTS"; \
	if [ $$ACTIVE_ALERTS -gt 0 ]; then \
		echo "  WARNING: There are active firing alerts"; \
	fi
	@echo ""
	@echo "[10/10] Checking WAL status..."
	@WAL_SIZE=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		du -sh /prometheus/wal 2>/dev/null | cut -f1 || echo "Unknown"); \
	echo "  WAL size: $$WAL_SIZE"
	@echo ""
	@echo "=== Pre-Upgrade Check Completed ==="
	@echo ""
	@echo "Next Steps:"
	@echo "  1. Create backup: make -f make/ops/prometheus.mk prom-backup-all"
	@echo "  2. Review release notes for target version"
	@echo "  3. Proceed with upgrade strategy"

# Post-upgrade validation
prom-post-upgrade-check:
	@echo "=== Prometheus Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/8] Checking pod status..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ERROR: Pod is not running (status: $$POD_STATUS)"; \
		exit 1; \
	fi; \
	echo "  Pod status: $$POD_STATUS ✓"
	@echo ""
	@echo "[2/8] Verifying new version..."
	@NEW_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		prometheus --version 2>&1 | head -1 | awk '{print $$3}'); \
	echo "  New version: $$NEW_VERSION ✓"
	@echo ""
	@echo "[3/8] Checking ready endpoint..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/-/ready >/dev/null 2>&1 && \
		echo "  Ready endpoint: OK ✓" || \
		(echo "  ERROR: Prometheus is not ready"; exit 1)
	@echo ""
	@echo "[4/8] Checking TSDB status..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/status/tsdb >/dev/null 2>&1 && \
		echo "  TSDB status: OK ✓" || \
		echo "  WARNING: TSDB status check failed"
	@echo ""
	@echo "[5/8] Verifying active targets..."
	@ACTIVE_TARGETS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null | \
		grep -o '"job":"[^"]*"' | wc -l); \
	echo "  Active targets: $$ACTIVE_TARGETS"; \
	if [ $$ACTIVE_TARGETS -eq 0 ]; then \
		echo "  WARNING: No active targets found!"; \
	fi
	@echo ""
	@echo "[6/8] Testing query execution..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- "http://localhost:9090/api/v1/query?query=up" >/dev/null 2>&1 && \
		echo "  Query execution: OK ✓" || \
		(echo "  ERROR: Query execution failed"; exit 1)
	@echo ""
	@echo "[7/8] Checking loaded rules..."
	@RULES_COUNT=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/api/v1/rules 2>/dev/null | \
		grep -o '"groups":\[' | wc -l); \
	echo "  Rules loaded: OK ✓"
	@echo ""
	@echo "[8/8] Checking for errors in logs..."
	@kubectl logs $(POD_NAME) -n $(NAMESPACE) -c $(CONTAINER_NAME) --tail=50 | \
		grep -i "error\|fatal" && echo "  WARNING: Errors found in logs" || \
		echo "  No errors found in recent logs ✓"
	@echo ""
	@echo "=== Post-Upgrade Validation Completed ==="

# Health check (lightweight validation)
prom-health-check:
	@echo "=== Prometheus Health Check ==="
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/-/healthy >/dev/null 2>&1 && \
		echo "✓ Prometheus is healthy" || \
		(echo "✗ Prometheus is unhealthy"; exit 1)
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:9090/-/ready >/dev/null 2>&1 && \
		echo "✓ Prometheus is ready" || \
		(echo "✗ Prometheus is not ready"; exit 1)

# Rollback to previous Helm revision
prom-upgrade-rollback:
	@echo "=== Prometheus Upgrade Rollback ==="
	@echo "Listing release history..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@PREVIOUS_REVISION=$$(helm history $(CHART_NAME) -n $(NAMESPACE) -o json 2>/dev/null | \
		grep -o '"revision":[0-9]*' | tail -2 | head -1 | cut -d':' -f2); \
	if [ -z "$$PREVIOUS_REVISION" ]; then \
		echo "Error: Could not determine previous revision"; \
		exit 1; \
	fi; \
	echo "Rolling back to revision: $$PREVIOUS_REVISION"; \
	read -p "Continue with rollback? (yes/no): " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Rollback cancelled"; \
		exit 0; \
	fi; \
	helm rollback $(CHART_NAME) $$PREVIOUS_REVISION -n $(NAMESPACE) --wait; \
	echo "Verifying rollback..."; \
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	echo ""; \
	echo "Rollback completed. Current version:"; \
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- prometheus --version | head -1
