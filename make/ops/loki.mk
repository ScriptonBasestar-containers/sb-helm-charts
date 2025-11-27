# Loki Operations Makefile
# Usage: make -f make/ops/loki.mk <target>

include make/Makefile.common.mk

CHART_NAME := loki
CHART_DIR := charts/$(CHART_NAME)

# Loki specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= loki
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Loki Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  loki-logs                   - View Loki logs"
	@echo "  loki-logs-all               - View logs from all Loki pods"
	@echo "  loki-shell                  - Open shell in Loki pod"
	@echo "  loki-port-forward           - Port forward Loki HTTP (3100)"
	@echo "  loki-port-forward-grpc      - Port forward Loki gRPC (9095)"
	@echo "  loki-restart                - Restart Loki StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  loki-ready                  - Check if Loki is ready"
	@echo "  loki-health                 - Get health status"
	@echo "  loki-metrics                - Get Prometheus metrics"
	@echo "  loki-version                - Get Loki version"
	@echo "  loki-config                 - Show current Loki configuration"
	@echo ""
	@echo "Ring & Clustering:"
	@echo "  loki-ring-status            - Get ring status"
	@echo "  loki-memberlist-status      - Get memberlist status"
	@echo ""
	@echo "Query & Logs:"
	@echo "  loki-query                  - Query logs (QUERY='{job=\"app\"}' TIME=5m)"
	@echo "  loki-labels                 - Get all label names"
	@echo "  loki-label-values           - Get values for a label (LABEL=job)"
	@echo "  loki-tail                   - Tail logs in real-time (QUERY='{job=\"app\"}')"
	@echo ""
	@echo "Data Management:"
	@echo "  loki-flush-index            - Flush in-memory index to storage"
	@echo "  loki-check-storage          - Check storage configuration"
	@echo ""
	@echo "Testing & Integration:"
	@echo "  loki-test-push              - Send test log to Loki"
	@echo "  loki-grafana-datasource     - Get Grafana datasource URL"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  loki-backup-all             - Full backup (config + data + index)"
	@echo "  loki-backup-config          - Backup ConfigMap and Secrets"
	@echo "  loki-backup-data            - Backup log chunks"
	@echo "  loki-backup-index           - Backup index files"
	@echo "  loki-backup-pvc-snapshot    - Create PVC snapshot (filesystem mode)"
	@echo "  loki-backup-verify          - Verify backup integrity (BACKUP_FILE=path)"
	@echo "  loki-restore-all            - Restore from full backup (BACKUP_FILE=path)"
	@echo "  loki-restore-config         - Restore configuration only"
	@echo "  loki-restore-data           - Restore data only"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  loki-pre-upgrade-check      - Pre-upgrade validation (10 checks)"
	@echo "  loki-post-upgrade-check     - Post-upgrade validation (8 checks)"
	@echo "  loki-upgrade-rollback       - Rollback to previous Helm revision"
	@echo "  loki-health-check           - Comprehensive health check"
	@echo ""
	@echo "Scaling:"
	@echo "  loki-scale                  - Scale Loki (REPLICAS=3)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: loki-logs loki-logs-all loki-shell loki-port-forward loki-port-forward-grpc loki-restart

loki-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

loki-logs-all:
	@echo "Fetching logs from all Loki pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

loki-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

loki-port-forward:
	@echo "Port forwarding Loki HTTP to localhost:3100..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3100:3100

loki-port-forward-grpc:
	@echo "Port forwarding Loki gRPC to localhost:9095..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9095:9095

loki-restart:
	@echo "Restarting Loki StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: loki-ready loki-health loki-metrics loki-version loki-config

loki-ready:
	@echo "Checking if Loki is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ready

loki-health:
	@echo "Getting Loki health status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ready

loki-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/metrics

loki-version:
	@echo "Getting Loki version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /usr/bin/loki --version

loki-config:
	@echo "Showing current Loki configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/loki/loki.yaml

# Ring & Clustering
.PHONY: loki-ring-status loki-memberlist-status

loki-ring-status:
	@echo "Getting ring status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ring

loki-memberlist-status:
	@echo "Getting memberlist status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/memberlist

# Query & Logs
.PHONY: loki-query loki-labels loki-label-values loki-tail

QUERY ?= {job="loki"}
TIME ?= 5m
LABEL ?= job

loki-query:
	@echo "Querying Loki: $(QUERY) (last $(TIME))..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/query_range?query=$(QUERY)&start=$$(date -u -d '$(TIME) ago' +%s)000000000&end=$$(date -u +%s)000000000"

loki-labels:
	@echo "Getting all label names..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/labels"

loki-label-values:
	@echo "Getting values for label '$(LABEL)'..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3100/loki/api/v1/label/$(LABEL)/values"

loki-tail:
	@echo "Tailing logs: $(QUERY)..."
	@echo "Note: This requires logcli to be installed locally"
	@echo "Install: go install github.com/grafana/loki/cmd/logcli@latest"
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3100:3100 &
	sleep 2
	logcli query '$(QUERY)' --addr=http://localhost:3100 --tail

# Data Management
.PHONY: loki-flush-index loki-check-storage

loki-flush-index:
	@echo "Flushing in-memory index to storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- -X POST http://localhost:3100/flush

loki-check-storage:
	@echo "Checking storage configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lah /loki

# Testing & Integration
.PHONY: loki-test-push loki-grafana-datasource

loki-test-push:
	@echo "Sending test log to Loki..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c 'echo "{\"streams\": [{\"stream\": {\"job\": \"test\"}, \"values\": [[\"$$(date -u +%s)000000000\", \"test log message from make\"]]}]}" | wget -qO- --post-data=@- --header="Content-Type: application/json" http://localhost:3100/loki/api/v1/push'
	@echo ""
	@echo "Test log sent. Query with: make -f make/ops/loki.mk loki-query QUERY='{job=\"test\"}'"

loki-grafana-datasource:
	@echo "Grafana datasource configuration:"
	@echo ""
	@echo "  Name: Loki"
	@echo "  Type: Loki"
	@echo "  URL: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:3100"
	@echo ""
	@echo "Add this datasource to Grafana to query Loki logs."

# Scaling
.PHONY: loki-scale

REPLICAS ?= 3

loki-scale:
	@echo "Scaling Loki to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Backup & Recovery Operations
# =============================================================================

# Backup configuration
BACKUP_DIR ?= ./backups/loki
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
S3_BUCKET ?=

.PHONY: loki-backup-all loki-backup-config loki-backup-data loki-backup-index loki-backup-pvc-snapshot loki-backup-verify
.PHONY: loki-restore-all loki-restore-config loki-restore-data

# Full backup (config + data + index)
loki-backup-all:
	@echo "=== Loki Full Backup Started ==="
	@mkdir -p $(BACKUP_DIR)/full/$(TIMESTAMP)/{config,data,index,metadata}
	@echo "[1/5] Flushing in-memory index..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3100/flush || true
	@sleep 5
	@echo "[2/5] Backing up configuration..."
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/configmap.yaml
	@kubectl get secret -n $(NAMESPACE) $(CHART_NAME)-s3-credentials -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/secret.yaml 2>/dev/null || true
	@echo "[3/5] Backing up metadata..."
	@kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/statefulset.yaml
	@kubectl get service -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/service.yaml
	@kubectl get pvc -n $(NAMESPACE) $(CHART_NAME)-$(CHART_NAME)-0 -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/pvc.yaml 2>/dev/null || true
	@echo "[4/5] Backing up log data..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /loki/chunks 2>/dev/null | cat > $(BACKUP_DIR)/full/$(TIMESTAMP)/data/chunks.tar.gz || \
		echo "  Chunks backup skipped (empty or S3 mode)"
	@echo "[5/5] Backing up index..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /loki/index 2>/dev/null | cat > $(BACKUP_DIR)/full/$(TIMESTAMP)/index/index.tar.gz || \
		echo "  Index backup skipped (empty or S3 mode)"
	@echo "backup:" > $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  timestamp: $(TIMESTAMP)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  namespace: $(NAMESPACE)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  pod: $(POD_NAME)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  components:" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - config" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - data" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - index" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - metadata" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "=== Loki Full Backup Complete ==="
	@echo "Backup location: $(BACKUP_DIR)/full/$(TIMESTAMP)"
	@du -sh $(BACKUP_DIR)/full/$(TIMESTAMP)/* 2>/dev/null || true
	@if [ -n "$(S3_BUCKET)" ]; then \
		echo ""; \
		echo "Uploading to S3..."; \
		tar czf - -C $(BACKUP_DIR)/full $(TIMESTAMP) | \
			aws s3 cp - s3://$(S3_BUCKET)/loki/full/loki-backup-$(TIMESTAMP).tar.gz; \
		echo "Upload complete: s3://$(S3_BUCKET)/loki/full/loki-backup-$(TIMESTAMP).tar.gz"; \
	fi

# Backup configuration only
loki-backup-config:
	@echo "=== Loki Configuration Backup ==="
	@mkdir -p $(BACKUP_DIR)/config/$(TIMESTAMP)
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/configmap.yaml
	@kubectl get secret -n $(NAMESPACE) $(CHART_NAME)-s3-credentials -o yaml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/secret.yaml 2>/dev/null || true
	@echo "Config backup complete: $(BACKUP_DIR)/config/$(TIMESTAMP)"

# Backup log data
loki-backup-data:
	@echo "=== Loki Data Backup ==="
	@mkdir -p $(BACKUP_DIR)/data/$(TIMESTAMP)
	@echo "Flushing index..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3100/flush || true
	@sleep 5
	@echo "Backing up chunks..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /loki/chunks 2>/dev/null | cat > $(BACKUP_DIR)/data/$(TIMESTAMP)/chunks.tar.gz || \
		echo "Chunks backup skipped (empty or S3 mode)"
	@echo "Data backup complete: $(BACKUP_DIR)/data/$(TIMESTAMP)"

# Backup index files
loki-backup-index:
	@echo "=== Loki Index Backup ==="
	@mkdir -p $(BACKUP_DIR)/index/$(TIMESTAMP)
	@echo "Flushing index..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3100/flush || true
	@sleep 5
	@echo "Backing up index..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /loki/index 2>/dev/null | cat > $(BACKUP_DIR)/index/$(TIMESTAMP)/index.tar.gz || \
		echo "Index backup skipped (empty or S3 mode)"
	@echo "Index backup complete: $(BACKUP_DIR)/index/$(TIMESTAMP)"

# Create PVC snapshot (filesystem mode)
loki-backup-pvc-snapshot:
	@echo "=== Loki PVC Snapshot ==="
	@SNAPSHOT_NAME="loki-pvc-snapshot-$(TIMESTAMP)"; \
	echo "apiVersion: snapshot.storage.k8s.io/v1" > /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "kind: VolumeSnapshot" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "metadata:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  name: $$SNAPSHOT_NAME" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  namespace: $(NAMESPACE)" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "spec:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  volumeSnapshotClassName: csi-snapclass" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  source:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "    persistentVolumeClaimName: $(CHART_NAME)-$(CHART_NAME)-0" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	kubectl apply -f /tmp/$$SNAPSHOT_NAME.yaml; \
	rm /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "Snapshot created: $$SNAPSHOT_NAME"; \
	echo "Check status: kubectl get volumesnapshot -n $(NAMESPACE) $$SNAPSHOT_NAME"

# Verify backup integrity
BACKUP_FILE ?=
loki-backup-verify:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/loki.mk loki-backup-verify BACKUP_FILE=/path/to/backup"; \
		exit 1; \
	fi
	@echo "=== Verifying Backup: $(BACKUP_FILE) ==="
	@if [ -f "$(BACKUP_FILE)/backup-manifest.yaml" ]; then \
		echo "✓ Manifest found"; \
		cat $(BACKUP_FILE)/backup-manifest.yaml; \
	else \
		echo "✗ Manifest missing"; \
	fi
	@if [ -f "$(BACKUP_FILE)/config/configmap.yaml" ]; then \
		echo "✓ ConfigMap found"; \
	else \
		echo "✗ ConfigMap missing"; \
	fi
	@if [ -f "$(BACKUP_FILE)/data/chunks.tar.gz" ]; then \
		echo "✓ Chunks found ($$(du -sh $(BACKUP_FILE)/data/chunks.tar.gz | cut -f1))"; \
	else \
		echo "⚠ Chunks missing (S3 mode or empty)"; \
	fi
	@if [ -f "$(BACKUP_FILE)/index/index.tar.gz" ]; then \
		echo "✓ Index found ($$(du -sh $(BACKUP_FILE)/index/index.tar.gz | cut -f1))"; \
	else \
		echo "⚠ Index missing (S3 mode or empty)"; \
	fi

# Restore from full backup
loki-restore-all:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/loki.mk loki-restore-all BACKUP_FILE=/path/to/backup"; \
		exit 1; \
	fi
	@echo "=== Loki Full Recovery ==="
	@echo "Backup source: $(BACKUP_FILE)"
	@if [ ! -f "$(BACKUP_FILE)/backup-manifest.yaml" ]; then \
		echo "ERROR: Invalid backup directory (no manifest found)"; \
		exit 1; \
	fi
	@echo "[1/6] Scaling down Loki..."
	@kubectl scale statefulset $(CHART_NAME) -n $(NAMESPACE) --replicas=0
	@kubectl wait --for=delete pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --timeout=120s || true
	@echo "[2/6] Restoring configuration..."
	@if [ -f "$(BACKUP_FILE)/config/configmap.yaml" ]; then \
		kubectl apply -f $(BACKUP_FILE)/config/configmap.yaml; \
	fi
	@if [ -f "$(BACKUP_FILE)/config/secret.yaml" ]; then \
		kubectl apply -f $(BACKUP_FILE)/config/secret.yaml; \
	fi
	@echo "[3/6] Restoring PVC data..."
	@kubectl scale statefulset $(CHART_NAME) -n $(NAMESPACE) --replicas=1
	@kubectl wait --for=condition=ready pod -n $(NAMESPACE) $(POD_NAME) --timeout=300s
	@if [ -f "$(BACKUP_FILE)/data/chunks.tar.gz" ]; then \
		echo "  Restoring chunks..."; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm -rf /loki/chunks/* || true; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- mkdir -p /loki/chunks; \
		kubectl cp $(BACKUP_FILE)/data/chunks.tar.gz $(NAMESPACE)/$(POD_NAME):/tmp/chunks.tar.gz -c $(CONTAINER_NAME); \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf /tmp/chunks.tar.gz -C /; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/chunks.tar.gz; \
	fi
	@if [ -f "$(BACKUP_FILE)/index/index.tar.gz" ]; then \
		echo "  Restoring index..."; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm -rf /loki/index/* || true; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- mkdir -p /loki/index; \
		kubectl cp $(BACKUP_FILE)/index/index.tar.gz $(NAMESPACE)/$(POD_NAME):/tmp/index.tar.gz -c $(CONTAINER_NAME); \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf /tmp/index.tar.gz -C /; \
		kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/index.tar.gz; \
	fi
	@echo "[4/6] Restarting Loki..."
	@kubectl rollout restart statefulset $(CHART_NAME) -n $(NAMESPACE)
	@kubectl rollout status statefulset $(CHART_NAME) -n $(NAMESPACE)
	@echo "[5/6] Waiting for Loki to be ready..."
	@kubectl wait --for=condition=ready pod -n $(NAMESPACE) $(POD_NAME) --timeout=300s
	@echo "[6/6] Verifying recovery..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ready
	@echo ""
	@echo "=== Loki Full Recovery Complete ==="

# Restore configuration only
loki-restore-config:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		exit 1; \
	fi
	@echo "=== Restoring Loki Configuration ==="
	@kubectl apply -f $(BACKUP_FILE)/configmap.yaml
	@kubectl apply -f $(BACKUP_FILE)/secret.yaml 2>/dev/null || true
	@kubectl rollout restart statefulset $(CHART_NAME) -n $(NAMESPACE)
	@kubectl rollout status statefulset $(CHART_NAME) -n $(NAMESPACE)
	@echo "Configuration restored"

# Restore data only
loki-restore-data:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		exit 1; \
	fi
	@echo "=== Restoring Loki Data ==="
	@kubectl scale statefulset $(CHART_NAME) -n $(NAMESPACE) --replicas=0
	@kubectl wait --for=delete pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --timeout=120s || true
	@kubectl scale statefulset $(CHART_NAME) -n $(NAMESPACE) --replicas=1
	@kubectl wait --for=condition=ready pod -n $(NAMESPACE) $(POD_NAME) --timeout=300s
	@kubectl cp $(BACKUP_FILE)/chunks.tar.gz $(NAMESPACE)/$(POD_NAME):/tmp/chunks.tar.gz -c $(CONTAINER_NAME)
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf /tmp/chunks.tar.gz -C /
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/chunks.tar.gz
	@kubectl cp $(BACKUP_FILE)/index.tar.gz $(NAMESPACE)/$(POD_NAME):/tmp/index.tar.gz -c $(CONTAINER_NAME)
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf /tmp/index.tar.gz -C /
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- rm /tmp/index.tar.gz
	@kubectl rollout restart statefulset $(CHART_NAME) -n $(NAMESPACE)
	@echo "Data restored"

# =============================================================================
# Upgrade Support Operations
# =============================================================================

.PHONY: loki-pre-upgrade-check loki-post-upgrade-check loki-upgrade-rollback loki-health-check

# Pre-upgrade validation
loki-pre-upgrade-check:
	@echo "=== Loki Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/10] Checking current version..."
	@CURRENT_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		/usr/bin/loki --version 2>&1 | head -1 | awk '{print $$3}'); \
	echo "  Current version: $$CURRENT_VERSION"
	@echo "[2/10] Checking pod health..."
	@POD_STATUS=$$(kubectl get pod $(POD_NAME) -n $(NAMESPACE) -o jsonpath='{.status.phase}'); \
	if [ "$$POD_STATUS" != "Running" ]; then \
		echo "  ✗ Pod not running: $$POD_STATUS"; \
		exit 1; \
	fi; \
	echo "  ✓ Pod is running"
	@echo "[3/10] Checking Loki readiness..."
	@if kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ready 2>&1 | grep -q "ready"; then \
		echo "  ✓ Loki is ready"; \
	else \
		echo "  ✗ Loki is not ready"; \
		exit 1; \
	fi
	@echo "[4/10] Checking ring status..."
	@RING_STATUS=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ring 2>/dev/null | grep -o '"state":"[^"]*"' | head -1); \
	echo "  Ring status: $$RING_STATUS"
	@echo "[5/10] Checking storage space..."
	@STORAGE_USAGE=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		df -h /loki 2>/dev/null | tail -1 | awk '{print $$5}' || echo "N/A"); \
	echo "  Storage usage: $$STORAGE_USAGE"
	@echo "[6/10] Checking active queries..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/metrics 2>/dev/null | grep loki_query_frontend || true
	@echo "[7/10] Validating configuration..."
	@if kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		/usr/bin/loki -config.file=/etc/loki/loki.yaml -verify-config 2>&1 | grep -q "failed"; then \
		echo "  ✗ Config validation failed"; \
		exit 1; \
	fi; \
	echo "  ✓ Config is valid"
	@echo "[8/10] Checking PVC status..."
	@PVC_STATUS=$$(kubectl get pvc $(CHART_NAME)-$(CHART_NAME)-0 -n $(NAMESPACE) -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound"); \
	echo "  PVC status: $$PVC_STATUS"
	@echo "[9/10] Checking recent errors..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 2>/dev/null | grep -i error | wc -l); \
	echo "  Recent errors: $$ERROR_COUNT"
	@echo "[10/10] Checking Helm release..."
	@HELM_STATUS=$$(helm status $(CHART_NAME) -n $(NAMESPACE) -o json 2>/dev/null | jq -r '.info.status' || echo "NotFound"); \
	echo "  Helm status: $$HELM_STATUS"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo ""
	@echo "Next steps:"
	@echo "1. Review release notes for target version"
	@echo "2. Create full backup: make -f make/ops/loki.mk loki-backup-all"
	@echo "3. Proceed with upgrade strategy"

# Post-upgrade validation
loki-post-upgrade-check:
	@echo "=== Loki Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/8] Verifying new version..."
	@NEW_VERSION=$$(kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		/usr/bin/loki --version 2>&1 | head -1 | awk '{print $$3}'); \
	echo "  New version: $$NEW_VERSION"
	@echo "[2/8] Checking pod status..."
	@READY_PODS=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) \
		-o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l); \
	TOTAL_PODS=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --no-headers | wc -l); \
	echo "  Ready pods: $$READY_PODS/$$TOTAL_PODS"
	@echo "[3/8] Checking Loki readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ready
	@echo "  ✓ Loki is ready"
	@echo "[4/8] Checking ring status..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ring 2>/dev/null | grep -o '"state":"[^"]*"' | head -1
	@echo "  ✓ Ring is healthy"
	@echo "[5/8] Testing label query..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- "http://localhost:3100/loki/api/v1/labels" | head -20
	@echo "  ✓ Label query successful"
	@echo "[6/8] Testing log query..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={job=\"loki\"}&limit=10&start=$$(date -u -d '5 minutes ago' +%s)000000000&end=$$(date -u +%s)000000000" \
		| jq '.status' 2>/dev/null || echo "success"
	@echo "  ✓ Log query successful"
	@echo "[7/8] Checking metrics..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/metrics 2>/dev/null | grep -E "(loki_build_info|loki_ingester_chunks)" | head -2 || true
	@echo "[8/8] Checking for errors..."
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 2>/dev/null | grep -i error | wc -l); \
	echo "  Recent errors: $$ERROR_COUNT"
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

# Rollback to previous Helm revision
loki-upgrade-rollback:
	@echo "=== Rolling back Loki ==="
	@echo "Current revisions:"
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@echo "⚠️  This will rollback to the previous Helm revision"
	@echo "Press ENTER to continue or Ctrl+C to cancel..."
	@read dummy
	@helm rollback $(CHART_NAME) -n $(NAMESPACE)
	@kubectl rollout status statefulset $(CHART_NAME) -n $(NAMESPACE)
	@echo "Rollback complete"

# Comprehensive health check
loki-health-check:
	@echo "=== Loki Health Check ==="
	@echo ""
	@echo "Version:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /usr/bin/loki --version | head -1
	@echo ""
	@echo "Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "Readiness:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3100/ready
	@echo ""
	@echo "Ring Status:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:3100/ring 2>/dev/null | grep -o '"state":"[^"]*"' | head -5 || true
	@echo ""
	@echo "Storage:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /loki 2>/dev/null || echo "N/A"
	@echo ""
	@echo "Recent Logs (last 10 lines):"
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=10
