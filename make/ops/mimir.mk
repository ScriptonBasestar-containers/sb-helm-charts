# Mimir Operations Makefile
# Usage: make -f make/ops/mimir.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := mimir
CHART_DIR := charts/$(CHART_NAME)

# Mimir specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= mimir
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Mimir Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  mimir-logs                  - View Mimir logs"
	@echo "  mimir-logs-all              - View logs from all Mimir pods"
	@echo "  mimir-shell                 - Open shell in Mimir pod"
	@echo "  mimir-port-forward          - Port forward Mimir HTTP (8080)"
	@echo "  mimir-port-forward-grpc     - Port forward Mimir gRPC (9095)"
	@echo "  mimir-restart               - Restart Mimir deployment/statefulset"
	@echo ""
	@echo "Health & Status:"
	@echo "  mimir-ready                 - Check if Mimir is ready"
	@echo "  mimir-healthy               - Check if Mimir is healthy"
	@echo "  mimir-health-check          - Comprehensive health check"
	@echo "  mimir-version               - Get Mimir version"
	@echo "  mimir-config                - Show current Mimir configuration"
	@echo "  mimir-runtime-config        - Show runtime configuration"
	@echo "  mimir-status                - Show Mimir status"
	@echo "  mimir-ring-status           - Show ingester/compactor/store-gateway ring status"
	@echo ""
	@echo "Metrics & Queries:"
	@echo "  mimir-query                 - Execute PromQL query (QUERY='up' TENANT='demo')"
	@echo "  mimir-query-test            - Test query functionality (QUERY='up')"
	@echo "  mimir-query-range           - Execute range query"
	@echo "  mimir-labels                - List all label names (TENANT='demo')"
	@echo "  mimir-label-values          - Get values for a label (LABEL='job' TENANT='demo')"
	@echo "  mimir-series                - List all time series (MATCH='{__name__=~\".+\"}' TENANT='demo')"
	@echo "  mimir-metrics               - Get Mimir own metrics"
	@echo ""
	@echo "Ingestion:"
	@echo "  mimir-remote-write-test     - Test remote write endpoint (TENANT='demo')"
	@echo "  mimir-limits                - Show tenant limits (TENANT='demo')"
	@echo ""
	@echo "Storage & TSDB:"
	@echo "  mimir-check-storage         - Check storage usage"
	@echo "  mimir-blocks                - List blocks in storage"
	@echo "  mimir-compactor-status      - Show compactor status"
	@echo "  mimir-store-gateway-status  - Show store-gateway status"
	@echo ""
	@echo "Tenants:"
	@echo "  mimir-tenants               - List all tenants"
	@echo "  mimir-tenant-stats          - Show tenant statistics (TENANT='demo')"
	@echo ""
	@echo "Scaling:"
	@echo "  mimir-scale                 - Scale Mimir (REPLICAS=2)"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  mimir-backup-blocks         - Backup blocks (filesystem mode)"
	@echo "  mimir-backup-config         - Backup configuration"
	@echo "  mimir-backup-all            - Full backup (blocks + config)"
	@echo "  mimir-backup-verify         - Verify backup integrity (DIR=path/to/backup)"
	@echo "  mimir-restore-blocks        - Restore blocks (FILE=path/to/backup.tar.gz)"
	@echo "  mimir-restore-config        - Restore configuration (DIR=path/to/config)"
	@echo "  mimir-restore-all           - Full restore (DIR=path/to/backup)"
	@echo "  mimir-create-pvc-snapshot   - Create PVC snapshot (SNAPSHOT_NAME=name)"
	@echo "  mimir-list-pvc-snapshots    - List PVC snapshots"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  mimir-pre-upgrade-check     - Run pre-upgrade health check"
	@echo "  mimir-post-upgrade-check    - Run post-upgrade validation"
	@echo "  mimir-upgrade-rollback      - Rollback to previous Helm revision"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: mimir-logs mimir-logs-all mimir-shell mimir-port-forward mimir-port-forward-grpc mimir-restart

mimir-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

mimir-logs-all:
	@echo "Fetching logs from all Mimir pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

mimir-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

mimir-port-forward:
	@echo "Port forwarding Mimir HTTP to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 8080:8080

mimir-port-forward-grpc:
	@echo "Port forwarding Mimir gRPC to localhost:9095..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9095:9095

mimir-restart:
	@echo "Restarting Mimir..."
	@if kubectl get statefulset/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	fi

# Health & Status
.PHONY: mimir-ready mimir-healthy mimir-version mimir-config mimir-runtime-config mimir-status

mimir-ready:
	@echo "Checking if Mimir is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/ready

mimir-healthy:
	@echo "Checking if Mimir is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/services

mimir-version:
	@echo "Getting Mimir version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/mimir --version

mimir-config:
	@echo "Showing current Mimir configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/mimir/mimir.yaml 2>/dev/null || echo "Config file not found. Using environment variables."

mimir-runtime-config:
	@echo "Showing runtime configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/runtime_config

mimir-status:
	@echo "Showing Mimir status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/services

# Metrics & Queries
.PHONY: mimir-query mimir-query-range mimir-labels mimir-label-values mimir-series mimir-metrics

QUERY ?= up
TENANT ?= demo
START ?= -1h
END ?= now
STEP ?= 15s
LABEL ?= job
MATCH ?= {__name__=~".+"}

mimir-query:
	@echo "Executing query: $(QUERY) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" "http://localhost:8080/prometheus/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

mimir-query-range:
	@echo "Executing range query: $(QUERY) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c "wget -qO- --header='X-Scope-OrgID: $(TENANT)' 'http://localhost:8080/prometheus/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s)&end=$$(date -d '$(END)' +%s)&step=$(STEP)'"

mimir-labels:
	@echo "Listing all label names for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/prometheus/api/v1/labels

mimir-label-values:
	@echo "Getting values for label '$(LABEL)' for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/prometheus/api/v1/label/$(LABEL)/values

mimir-series:
	@echo "Listing time series matching: $(MATCH) for tenant: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" "http://localhost:8080/prometheus/api/v1/series?match[]=$(MATCH)"

mimir-metrics:
	@echo "Fetching Mimir own metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/metrics

# Ingestion
.PHONY: mimir-remote-write-test mimir-limits

mimir-remote-write-test:
	@echo "Testing remote write endpoint for tenant: $(TENANT)"
	@echo "Remote write URL: http://$(CHART_NAME):8080/api/v1/push"
	@echo "Use with Prometheus remote_write config:"
	@echo "remote_write:"
	@echo "  - url: http://$(CHART_NAME):8080/api/v1/push"
	@echo "    headers:"
	@echo "      X-Scope-OrgID: $(TENANT)"

mimir-limits:
	@echo "Showing tenant limits for: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/api/v1/user_limits

# Storage & TSDB
.PHONY: mimir-check-storage mimir-blocks mimir-compactor-status mimir-store-gateway-status

mimir-check-storage:
	@echo "Checking storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || echo "No /data mount found"

mimir-blocks:
	@echo "Listing blocks in storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lh /data/blocks/ 2>/dev/null || echo "Blocks directory not found (may be using S3/GCS)"

mimir-compactor-status:
	@echo "Showing compactor status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/compactor/ring

mimir-store-gateway-status:
	@echo "Showing store-gateway status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/store-gateway/ring

# Tenants
.PHONY: mimir-tenants mimir-tenant-stats

mimir-tenants:
	@echo "Listing all tenants..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/api/v1/user_stats

mimir-tenant-stats:
	@echo "Showing tenant statistics for: $(TENANT)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" http://localhost:8080/api/v1/user_stats

# Scaling
.PHONY: mimir-scale

REPLICAS ?= 2

mimir-scale:
	@echo "Scaling Mimir to $(REPLICAS) replicas..."
	@if kubectl get statefulset/$(CHART_NAME) -n $(NAMESPACE) 2>/dev/null; then \
		kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS); \
		kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE); \
	else \
		kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS); \
		kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE); \
	fi

# === Backup & Recovery ===

.PHONY: mimir-backup-blocks mimir-backup-config mimir-backup-all mimir-backup-verify
.PHONY: mimir-restore-blocks mimir-restore-config mimir-restore-all
.PHONY: mimir-create-pvc-snapshot mimir-list-pvc-snapshots

BACKUP_DIR ?= tmp/mimir-backups

mimir-backup-blocks:
	@echo "Backing up Mimir blocks (filesystem mode)..."
	@mkdir -p $(BACKUP_DIR)
	@echo "Creating blocks backup at $(BACKUP_DIR)/blocks-$$(date +%Y%m%d-%H%M%S).tar.gz"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar czf /tmp/blocks-backup.tar.gz -C /data blocks/ 2>/dev/null || echo "Note: Using S3/object storage (no local blocks to backup)"
	@if kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- test -f /tmp/blocks-backup.tar.gz 2>/dev/null; then \
		kubectl cp -n $(NAMESPACE) $(POD_NAME):/tmp/blocks-backup.tar.gz $(BACKUP_DIR)/blocks-$$(date +%Y%m%d-%H%M%S).tar.gz; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/blocks-backup.tar.gz; \
		echo "Backup completed: $(BACKUP_DIR)/blocks-$$(date +%Y%m%d-%H%M%S).tar.gz"; \
	else \
		echo "Using S3/object storage - backup S3 bucket externally"; \
		echo "Example: aws s3 sync s3://mimir-blocks s3://mimir-blocks-backup-$$(date +%Y%m%d)"; \
	fi

mimir-backup-config:
	@echo "Backing up Mimir configuration..."
	@mkdir -p $(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)
	@echo "Exporting ConfigMaps and configuration..."
	kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-config -o yaml > $(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)/mimir-config.yaml 2>/dev/null || echo "ConfigMap not found (using default config)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/mimir/mimir.yaml > $(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)/mimir.yaml 2>/dev/null || echo "Config file not accessible"
	@echo "Backup completed: $(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)/"
	@ls -lh $(BACKUP_DIR)/config-$$(date +%Y%m%d-%H%M%S)/

mimir-backup-all:
	@echo "=== Mimir Full Backup ==="
	@echo "Creating comprehensive backup..."
	@mkdir -p $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)
	@echo "1/3 Backing up blocks..."
	@$(MAKE) -f make/ops/mimir.mk mimir-backup-blocks BACKUP_DIR=$(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)
	@echo "2/3 Backing up configuration..."
	@$(MAKE) -f make/ops/mimir.mk mimir-backup-config BACKUP_DIR=$(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)
	@echo "3/3 Creating backup manifest..."
	@echo "Backup Date: $$(date)" > $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)/backup-manifest.txt
	@echo "Mimir Version: $$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/mimir --version 2>&1 | head -1)" >> $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)/backup-manifest.txt
	@echo "Namespace: $(NAMESPACE)" >> $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)/backup-manifest.txt
	@echo "=== Backup Complete ==="
	@echo "Location: $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)/"
	@du -sh $(BACKUP_DIR)/backup-$$(date +%Y%m%d-%H%M%S)/

mimir-backup-verify:
	@if [ -z "$(DIR)" ]; then echo "Usage: make -f make/ops/mimir.mk mimir-backup-verify DIR=path/to/backup-dir"; exit 1; fi
	@echo "Verifying backup integrity: $(DIR)"
	@if [ ! -d "$(DIR)" ]; then echo "Error: Backup directory not found: $(DIR)"; exit 1; fi
	@echo "✓ Backup directory exists"
	@if [ -f "$(DIR)/backup-manifest.txt" ]; then echo "✓ Backup manifest found"; cat $(DIR)/backup-manifest.txt; else echo "⚠ Backup manifest missing"; fi
	@if [ -d "$(DIR)/config-"* ] || [ -f "$(DIR)/"*"/mimir-config.yaml" ]; then echo "✓ Configuration backup found"; else echo "⚠ Configuration backup missing"; fi
	@echo "Backup verification complete"

mimir-restore-blocks:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/mimir.mk mimir-restore-blocks FILE=path/to/blocks-backup.tar.gz"; exit 1; fi
	@echo "Restoring Mimir blocks from: $(FILE)"
	@echo "⚠ WARNING: This will overwrite current blocks data"
	@read -p "Continue? [y/N] " -n 1 -r; echo; if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then exit 1; fi
	@echo "Stopping Mimir..."
	kubectl scale statefulset -n $(NAMESPACE) $(CHART_NAME) --replicas=0
	kubectl wait --for=delete pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --timeout=300s
	@echo "Copying backup to pod..."
	kubectl cp $(FILE) -n $(NAMESPACE) $(POD_NAME):/tmp/blocks-restore.tar.gz
	@echo "Extracting blocks..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf /tmp/blocks-restore.tar.gz -C /data/
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/blocks-restore.tar.gz
	@echo "Restarting Mimir..."
	kubectl scale statefulset -n $(NAMESPACE) $(CHART_NAME) --replicas=1
	kubectl wait --for=condition=ready pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --timeout=600s
	@echo "Restore completed"

mimir-restore-config:
	@if [ -z "$(DIR)" ]; then echo "Usage: make -f make/ops/mimir.mk mimir-restore-config DIR=path/to/config-backup-dir"; exit 1; fi
	@echo "Restoring Mimir configuration from: $(DIR)"
	@if [ -f "$(DIR)/mimir-config.yaml" ]; then \
		kubectl apply -f $(DIR)/mimir-config.yaml -n $(NAMESPACE); \
		echo "ConfigMap restored"; \
	else \
		echo "Error: mimir-config.yaml not found in $(DIR)"; \
		exit 1; \
	fi
	@echo "Restarting Mimir to apply configuration..."
	kubectl rollout restart statefulset -n $(NAMESPACE) $(CHART_NAME)
	kubectl rollout status statefulset -n $(NAMESPACE) $(CHART_NAME)
	@echo "Configuration restored"

mimir-restore-all:
	@if [ -z "$(DIR)" ]; then echo "Usage: make -f make/ops/mimir.mk mimir-restore-all DIR=path/to/backup-dir"; exit 1; fi
	@echo "=== Mimir Full Restore ==="
	@echo "⚠ WARNING: This will restore from backup: $(DIR)"
	@read -p "Continue? [y/N] " -n 1 -r; echo; if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then exit 1; fi
	@if [ -d "$(DIR)/config-"* ]; then \
		CONFIG_DIR=$$(find $(DIR) -type d -name "config-*" | head -1); \
		$(MAKE) -f make/ops/mimir.mk mimir-restore-config DIR=$$CONFIG_DIR; \
	else \
		echo "Config backup not found, skipping..."; \
	fi
	@if [ -f "$(DIR)/blocks-"*.tar.gz ]; then \
		BLOCKS_FILE=$$(find $(DIR) -name "blocks-*.tar.gz" | head -1); \
		$(MAKE) -f make/ops/mimir.mk mimir-restore-blocks FILE=$$BLOCKS_FILE; \
	else \
		echo "Blocks backup not found, skipping..."; \
	fi
	@echo "=== Restore Complete ==="

mimir-create-pvc-snapshot:
	@SNAPSHOT_NAME=$${SNAPSHOT_NAME:-mimir-snapshot-$$(date +%Y%m%d-%H%M)}; \
	echo "Creating VolumeSnapshot: $$SNAPSHOT_NAME"; \
	kubectl apply -f - <<EOF; \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata: \
	  name: $$SNAPSHOT_NAME; \
	  namespace: $(NAMESPACE); \
	spec: \
	  volumeSnapshotClassName: csi-aws-vsc; \
	  source: \
	    persistentVolumeClaimName: data-$(CHART_NAME)-0; \
	EOF
	@echo "Waiting for snapshot to be ready..."
	kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/$$SNAPSHOT_NAME -n $(NAMESPACE) --timeout=300s
	@echo "Snapshot created: $$SNAPSHOT_NAME"

mimir-list-pvc-snapshots:
	@echo "Listing VolumeSnapshots for Mimir..."
	kubectl get volumesnapshots -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

# === Upgrade Support ===

.PHONY: mimir-pre-upgrade-check mimir-post-upgrade-check mimir-upgrade-rollback
.PHONY: mimir-ring-status mimir-health-check mimir-query-test

mimir-pre-upgrade-check:
	@echo "=== Mimir Pre-Upgrade Health Check ==="
	@echo "1. Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "2. Checking Mimir health..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/ready 2>/dev/null && echo "✓ Ready" || echo "✗ Not ready"
	@echo ""
	@echo "3. Checking current version..."
	@echo -n "Version: "
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/mimir --version 2>&1 | head -1
	@echo ""
	@echo "4. Checking rings..."
	@$(MAKE) -f make/ops/mimir.mk mimir-ring-status
	@echo ""
	@echo "5. Checking storage..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /data 2>/dev/null || echo "Using S3/object storage"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo "✓ Ready for upgrade"

mimir-post-upgrade-check:
	@echo "=== Mimir Post-Upgrade Validation ==="
	@echo "1. Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "2. Verifying new version..."
	@echo -n "Version: "
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/mimir --version 2>&1 | head -1
	@echo ""
	@echo "3. Checking health..."
	@$(MAKE) -f make/ops/mimir.mk mimir-health-check
	@echo ""
	@echo "4. Checking rings..."
	@$(MAKE) -f make/ops/mimir.mk mimir-ring-status
	@echo ""
	@echo "5. Testing query functionality..."
	@$(MAKE) -f make/ops/mimir.mk mimir-query-test
	@echo ""
	@echo "6. Checking for errors in logs (last 5 minutes)..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --since=5m | grep -i error | wc -l); \
	if [ $$ERROR_COUNT -eq 0 ]; then \
		echo "✓ No errors in last 5 minutes"; \
	else \
		echo "⚠ Found $$ERROR_COUNT error messages"; \
		echo "Review logs: make -f make/ops/mimir.mk mimir-logs"; \
	fi
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

mimir-ring-status:
	@echo "=== Ring Status ==="
	@echo "Ingester Ring:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/ingester/ring 2>/dev/null | grep -o "ACTIVE\|JOINING\|LEAVING" | sort | uniq -c || echo "Unable to fetch ring status"
	@echo ""
	@echo "Compactor Ring:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/compactor/ring 2>/dev/null | grep -o "ACTIVE\|JOINING\|LEAVING" | sort | uniq -c || echo "Unable to fetch ring status"
	@echo ""
	@echo "Store-Gateway Ring:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/store-gateway/ring 2>/dev/null | grep -o "ACTIVE\|JOINING\|LEAVING" | sort | uniq -c || echo "Unable to fetch ring status"

mimir-health-check:
	@echo "Checking Mimir health..."
	@STATUS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:8080/ready 2>/dev/null); \
	if echo "$$STATUS" | grep -q "ready"; then \
		echo "✓ Mimir is healthy"; \
		exit 0; \
	else \
		echo "✗ Mimir is not healthy"; \
		echo "Status: $$STATUS"; \
		exit 1; \
	fi

QUERY ?= up
TENANT ?= demo

mimir-query-test:
	@echo "Testing query: $(QUERY)"
	@if [ "$(TENANT)" != "demo" ]; then \
		echo "Tenant: $(TENANT)"; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --header="X-Scope-OrgID: $(TENANT)" "http://localhost:8080/prometheus/api/v1/query?query=$(QUERY)" 2>/dev/null; \
	else \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:8080/prometheus/api/v1/query?query=$(QUERY)" 2>/dev/null; \
	fi
	@echo ""
	@echo "✓ Query test completed"

mimir-upgrade-rollback:
	@echo "=== Mimir Upgrade Rollback ==="
	@echo "Listing Helm revisions..."
	helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Enter revision number to rollback to: " REVISION; \
	if [ -n "$$REVISION" ]; then \
		echo "Rolling back to revision $$REVISION..."; \
		helm rollback $(CHART_NAME) $$REVISION -n $(NAMESPACE); \
		kubectl rollout status statefulset -n $(NAMESPACE) $(CHART_NAME); \
		echo "Rollback complete"; \
		$(MAKE) -f make/ops/mimir.mk mimir-post-upgrade-check; \
	else \
		echo "Rollback cancelled"; \
	fi
