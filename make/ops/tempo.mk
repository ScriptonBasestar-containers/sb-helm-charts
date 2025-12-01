# Tempo Operations Makefile
# Usage: make -f make/ops/tempo.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := tempo
CHART_DIR := charts/$(CHART_NAME)

# Tempo specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= tempo
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Tempo Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tempo-logs                  - View Tempo logs"
	@echo "  tempo-logs-all              - View logs from all Tempo pods"
	@echo "  tempo-shell                 - Open shell in Tempo pod"
	@echo "  tempo-port-forward          - Port forward Tempo HTTP (3200)"
	@echo "  tempo-port-forward-otlp     - Port forward OTLP gRPC (4317)"
	@echo "  tempo-port-forward-otlp-http - Port forward OTLP HTTP (4318)"
	@echo "  tempo-port-forward-jaeger   - Port forward Jaeger Thrift (14268)"
	@echo "  tempo-port-forward-zipkin   - Port forward Zipkin (9411)"
	@echo "  tempo-restart               - Restart Tempo StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  tempo-ready                 - Check if Tempo is ready"
	@echo "  tempo-health                - Get health status"
	@echo "  tempo-metrics               - Get Prometheus metrics"
	@echo "  tempo-config                - Show current Tempo configuration"
	@echo "  tempo-status                - Get Tempo status"
	@echo ""
	@echo "Ring & Clustering:"
	@echo "  tempo-ring-status           - Get ring status"
	@echo "  tempo-memberlist-status     - Get memberlist status"
	@echo ""
	@echo "Trace Operations:"
	@echo "  tempo-search                - Search traces (SERVICE=myapp LIMIT=10)"
	@echo "  tempo-trace                 - Get trace by ID (TRACE_ID=xxx)"
	@echo "  tempo-test-trace            - Send test trace via OTLP"
	@echo ""
	@echo "Storage:"
	@echo "  tempo-check-storage         - Check storage configuration"
	@echo "  tempo-flush                 - Flush in-memory data to storage"
	@echo "  tempo-flush-wal             - Flush WAL to storage"
	@echo "  tempo-compactor-status      - Check compactor status"
	@echo "  tempo-compactor-force-run   - Trigger compactor run"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  tempo-backup-all            - Full backup (config + data + WAL)"
	@echo "  tempo-backup-config         - Backup configuration only"
	@echo "  tempo-backup-data           - Backup trace data only"
	@echo "  tempo-backup-wal            - Backup WAL only"
	@echo "  tempo-backup-pvc-snapshot   - Create PVC snapshot (local mode)"
	@echo "  tempo-backup-verify         - Verify backup integrity (BACKUP_FILE=path)"
	@echo "  tempo-restore-all           - Full restore (BACKUP_FILE=path)"
	@echo "  tempo-restore-config        - Restore configuration (BACKUP_FILE=path)"
	@echo "  tempo-restore-data          - Restore data (BACKUP_FILE=path)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  tempo-pre-upgrade-check     - Pre-upgrade validation (12 checks)"
	@echo "  tempo-post-upgrade-check    - Post-upgrade validation (10 checks)"
	@echo "  tempo-upgrade-rollback      - Rollback to previous version"
	@echo ""
	@echo "Integration:"
	@echo "  tempo-grafana-datasource    - Get Grafana datasource URL"
	@echo ""
	@echo "Scaling:"
	@echo "  tempo-scale                 - Scale Tempo (REPLICAS=3)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: tempo-logs tempo-logs-all tempo-shell tempo-port-forward tempo-port-forward-otlp tempo-port-forward-otlp-http tempo-port-forward-jaeger tempo-port-forward-zipkin tempo-restart

tempo-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tempo-logs-all:
	@echo "Fetching logs from all Tempo pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tempo-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tempo-port-forward:
	@echo "Port forwarding Tempo HTTP API to localhost:3200..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3200:3200

tempo-port-forward-otlp:
	@echo "Port forwarding OTLP gRPC to localhost:4317..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4317:4317

tempo-port-forward-otlp-http:
	@echo "Port forwarding OTLP HTTP to localhost:4318..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4318:4318

tempo-port-forward-jaeger:
	@echo "Port forwarding Jaeger Thrift to localhost:14268..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 14268:14268

tempo-port-forward-zipkin:
	@echo "Port forwarding Zipkin to localhost:9411..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9411:9411

tempo-restart:
	@echo "Restarting Tempo StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: tempo-ready tempo-health tempo-metrics tempo-config tempo-status

tempo-ready:
	@echo "Checking if Tempo is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready

tempo-health:
	@echo "Getting Tempo health status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready

tempo-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/metrics

tempo-config:
	@echo "Showing current Tempo configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/tempo/tempo.yaml

tempo-status:
	@echo "Getting Tempo status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/status

# Ring & Clustering
.PHONY: tempo-ring-status tempo-memberlist-status

tempo-ring-status:
	@echo "Getting ring status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/distributor/ring

tempo-memberlist-status:
	@echo "Getting memberlist status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/memberlist

# Trace Operations
.PHONY: tempo-search tempo-trace tempo-test-trace

SERVICE ?= myapp
LIMIT ?= 10
TRACE_ID ?=

tempo-search:
	@echo "Searching traces for service '$(SERVICE)' (limit: $(LIMIT))..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3200/api/search?q={.service.name%3D\"$(SERVICE)\"}&limit=$(LIMIT)"

tempo-trace:
	@if [ -z "$(TRACE_ID)" ]; then \
		echo "Error: TRACE_ID is required. Usage: make tempo-trace TRACE_ID=abc123"; \
		exit 1; \
	fi
	@echo "Getting trace $(TRACE_ID)..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3200/api/traces/$(TRACE_ID)"

tempo-test-trace:
	@echo "Sending test trace via OTLP HTTP..."
	@echo "Note: This requires curl to be available in the container"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c 'echo "{ \
		\"resourceSpans\": [{ \
			\"resource\": { \
				\"attributes\": [{ \
					\"key\": \"service.name\", \
					\"value\": { \"stringValue\": \"test-service\" } \
				}] \
			}, \
			\"scopeSpans\": [{ \
				\"spans\": [{ \
					\"traceId\": \"$$(cat /proc/sys/kernel/random/uuid | tr -d -)\", \
					\"spanId\": \"$$(cat /proc/sys/kernel/random/uuid | cut -c1-16 | tr -d -)\", \
					\"name\": \"test-span\", \
					\"kind\": 1, \
					\"startTimeUnixNano\": \"$$(date +%s)000000000\", \
					\"endTimeUnixNano\": \"$$(date +%s)100000000\" \
				}] \
			}] \
		}] \
	}" | wget -qO- --post-data=@- --header="Content-Type: application/json" http://localhost:4318/v1/traces' || true
	@echo ""
	@echo "If wget failed, use port-forward and curl locally:"
	@echo "  make tempo-port-forward-otlp-http &"
	@echo "  curl -X POST http://localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{...}'"

# Storage
.PHONY: tempo-check-storage tempo-flush

tempo-check-storage:
	@echo "Checking storage configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lah /var/tempo

tempo-flush:
	@echo "Flushing in-memory data to storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- -X POST http://localhost:3200/flush

# Integration
.PHONY: tempo-grafana-datasource

tempo-grafana-datasource:
	@echo "Grafana datasource configuration:"
	@echo ""
	@echo "  Name: Tempo"
	@echo "  Type: Tempo"
	@echo "  URL: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:3200"
	@echo ""
	@echo "Optional service graph configuration:"
	@echo "  Enable 'Service graph' in datasource settings"
	@echo "  Configure Prometheus datasource for metrics correlation"
	@echo "  Configure Loki datasource for logs correlation"
	@echo ""
	@echo "Trace to Logs:"
	@echo "  Datasource: Loki"
	@echo "  Tags: service.name -> job"
	@echo ""

# Scaling
.PHONY: tempo-scale

REPLICAS ?= 3

tempo-scale:
	@echo "Scaling Tempo to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# =============================================================================
# Backup & Recovery Operations
# =============================================================================
# See docs/tempo-backup-guide.md for detailed procedures
# =============================================================================

BACKUP_DIR ?= backups/tempo
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
S3_BUCKET ?=

# Full backup (all components)
.PHONY: tempo-backup-all
tempo-backup-all:
	@echo "=== Tempo Full Backup ==="
	@echo "Creating backup directories..."
	@mkdir -p $(BACKUP_DIR)/full/$(TIMESTAMP)/{config,data,wal,metadata}
	@echo "[1/6] Flushing WAL..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3200/flush || true
	@sleep 5
	@echo "[2/6] Backing up configuration..."
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-config -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/configmap.yaml
	@kubectl get secret -n $(NAMESPACE) $(CHART_NAME)-secret -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/config/secret.yaml 2>/dev/null || true
	@echo "[3/6] Backing up metadata..."
	@kubectl get statefulset -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/statefulset.yaml
	@kubectl get service -n $(NAMESPACE) $(CHART_NAME) -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/service.yaml
	@kubectl get pvc -n $(NAMESPACE) $(CHART_NAME)-data-$(CHART_NAME)-0 -o yaml > \
		$(BACKUP_DIR)/full/$(TIMESTAMP)/metadata/pvc.yaml 2>/dev/null || true
	@echo "[4/6] Backing up trace data (blocks)..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /var/tempo/blocks 2>/dev/null | cat > $(BACKUP_DIR)/full/$(TIMESTAMP)/data/blocks.tar.gz || \
		echo "  Blocks backup skipped (empty or S3 mode)"
	@echo "[5/6] Backing up WAL..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /var/tempo/wal 2>/dev/null | cat > $(BACKUP_DIR)/full/$(TIMESTAMP)/wal/wal.tar.gz || \
		echo "  WAL backup skipped (empty or S3 mode)"
	@echo "[6/6] Creating manifest..."
	@echo "backup:" > $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  timestamp: $(TIMESTAMP)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  namespace: $(NAMESPACE)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  pod: $(POD_NAME)" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "  components:" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - config" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - data" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - wal" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "    - metadata" >> $(BACKUP_DIR)/full/$(TIMESTAMP)/backup-manifest.yaml
	@echo "=== Tempo Full Backup Complete ==="
	@echo "Backup location: $(BACKUP_DIR)/full/$(TIMESTAMP)"
	@du -sh $(BACKUP_DIR)/full/$(TIMESTAMP)/* 2>/dev/null || true
	@if [ -n "$(S3_BUCKET)" ]; then \
		echo ""; \
		echo "Uploading to S3..."; \
		tar czf - -C $(BACKUP_DIR)/full $(TIMESTAMP) | \
			aws s3 cp - s3://$(S3_BUCKET)/tempo/full/tempo-backup-$(TIMESTAMP).tar.gz; \
		echo "Upload complete: s3://$(S3_BUCKET)/tempo/full/tempo-backup-$(TIMESTAMP).tar.gz"; \
	fi

# Backup configuration only
.PHONY: tempo-backup-config
tempo-backup-config:
	@echo "=== Tempo Configuration Backup ==="
	@mkdir -p $(BACKUP_DIR)/config/$(TIMESTAMP)
	@kubectl get configmap -n $(NAMESPACE) $(CHART_NAME)-config -o yaml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/configmap.yaml
	@kubectl get secret -n $(NAMESPACE) $(CHART_NAME)-secret -o yaml > \
		$(BACKUP_DIR)/config/$(TIMESTAMP)/secret.yaml 2>/dev/null || true
	@echo "Config backup complete: $(BACKUP_DIR)/config/$(TIMESTAMP)"

# Backup trace data (blocks)
.PHONY: tempo-backup-data
tempo-backup-data:
	@echo "=== Tempo Trace Data Backup ==="
	@mkdir -p $(BACKUP_DIR)/data/$(TIMESTAMP)
	@echo "Flushing WAL..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3200/flush || true
	@sleep 5
	@echo "Backing up blocks..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /var/tempo/blocks 2>/dev/null | cat > $(BACKUP_DIR)/data/$(TIMESTAMP)/blocks.tar.gz || \
		echo "Blocks backup skipped (empty or S3 mode)"
	@echo "Data backup complete: $(BACKUP_DIR)/data/$(TIMESTAMP)"

# Backup WAL only
.PHONY: tempo-backup-wal
tempo-backup-wal:
	@echo "=== Tempo WAL Backup ==="
	@mkdir -p $(BACKUP_DIR)/wal/$(TIMESTAMP)
	@echo "Flushing WAL..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3200/flush || true
	@sleep 5
	@echo "Backing up WAL..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		tar czf - /var/tempo/wal 2>/dev/null | cat > $(BACKUP_DIR)/wal/$(TIMESTAMP)/wal.tar.gz || \
		echo "WAL backup skipped (empty or S3 mode)"
	@echo "WAL backup complete: $(BACKUP_DIR)/wal/$(TIMESTAMP)"

# Flush WAL to storage
.PHONY: tempo-flush-wal
tempo-flush-wal:
	@echo "Flushing WAL to storage..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- -X POST http://localhost:3200/flush
	@echo "WAL flushed successfully"

# Create PVC snapshot (local storage mode)
.PHONY: tempo-backup-pvc-snapshot
tempo-backup-pvc-snapshot:
	@echo "=== Tempo PVC Snapshot ==="
	@SNAPSHOT_NAME="tempo-pvc-snapshot-$(TIMESTAMP)"; \
	echo "apiVersion: snapshot.storage.k8s.io/v1" > /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "kind: VolumeSnapshot" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "metadata:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  name: $$SNAPSHOT_NAME" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  namespace: $(NAMESPACE)" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "spec:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  volumeSnapshotClassName: csi-snapclass" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "  source:" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "    persistentVolumeClaimName: $(CHART_NAME)-data-$(CHART_NAME)-0" >> /tmp/$$SNAPSHOT_NAME.yaml; \
	kubectl apply -f /tmp/$$SNAPSHOT_NAME.yaml; \
	rm /tmp/$$SNAPSHOT_NAME.yaml; \
	echo "Snapshot created: $$SNAPSHOT_NAME"; \
	echo "Check status: kubectl get volumesnapshot -n $(NAMESPACE) $$SNAPSHOT_NAME"

# Verify backup integrity
BACKUP_FILE ?=
.PHONY: tempo-backup-verify
tempo-backup-verify:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/tempo.mk tempo-backup-verify BACKUP_FILE=/path/to/backup"; \
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
	@if [ -f "$(BACKUP_FILE)/data/blocks.tar.gz" ]; then \
		echo "✓ Blocks found ($$(du -sh $(BACKUP_FILE)/data/blocks.tar.gz | cut -f1))"; \
	else \
		echo "⚠ Blocks missing (S3 mode or empty)"; \
	fi
	@if [ -f "$(BACKUP_FILE)/wal/wal.tar.gz" ]; then \
		echo "✓ WAL found ($$(du -sh $(BACKUP_FILE)/wal/wal.tar.gz | cut -f1))"; \
	else \
		echo "⚠ WAL missing (S3 mode or empty)"; \
	fi

# Recovery operations
.PHONY: tempo-restore-all tempo-restore-config tempo-restore-data

# Full restore
tempo-restore-all:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		echo "Usage: make -f make/ops/tempo.mk tempo-restore-all BACKUP_FILE=/path/to/backup"; \
		exit 1; \
	fi
	@echo "=== Tempo Full Restore ==="
	@echo "WARNING: This will replace current configuration and data!"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Restore cancelled"; \
		exit 1; \
	fi
	@echo "[1/3] Restoring configuration..."
	@kubectl apply -f $(BACKUP_FILE)/config/configmap.yaml
	@kubectl apply -f $(BACKUP_FILE)/config/secret.yaml 2>/dev/null || true
	@echo "[2/3] Restoring trace data..."
	@cat $(BACKUP_FILE)/data/blocks.tar.gz | kubectl exec -i -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf - -C / || true
	@echo "[3/3] Restoring WAL..."
	@cat $(BACKUP_FILE)/wal/wal.tar.gz | kubectl exec -i -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf - -C / || true
	@echo "Restarting Tempo..."
	@kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@echo "=== Tempo Restore Complete ==="

# Restore configuration only
tempo-restore-config:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		exit 1; \
	fi
	@echo "=== Restoring Tempo Configuration ==="
	@kubectl apply -f $(BACKUP_FILE)/config/configmap.yaml
	@kubectl apply -f $(BACKUP_FILE)/config/secret.yaml 2>/dev/null || true
	@kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@echo "Configuration restored"

# Restore data only
tempo-restore-data:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE not specified"; \
		exit 1; \
	fi
	@echo "=== Restoring Tempo Data ==="
	@cat $(BACKUP_FILE)/data/blocks.tar.gz | kubectl exec -i -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf - -C / || true
	@cat $(BACKUP_FILE)/wal/wal.tar.gz | kubectl exec -i -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- tar xzf - -C / || true
	@kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@echo "Data restored"

# =============================================================================
# Upgrade Operations
# =============================================================================
# See docs/tempo-upgrade-guide.md for detailed procedures
# =============================================================================

# Pre-upgrade checks
.PHONY: tempo-pre-upgrade-check
tempo-pre-upgrade-check:
	@echo "=== Tempo Pre-Upgrade Checklist ==="
	@echo ""
	@echo "[1/12] Checking Tempo pods..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) | grep Running || \
		(echo "✗ Not all pods running" && exit 1)
	@echo "✓ All pods running"
	@echo ""
	@echo "[2/12] Checking readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready || \
		(echo "✗ Tempo not ready" && exit 1)
	@echo "✓ Tempo ready"
	@echo ""
	@echo "[3/12] Checking WAL status..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lh /var/tempo/wal 2>/dev/null || true
	@echo "✓ WAL checked"
	@echo ""
	@echo "[4/12] Checking trace ingestion..."
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i "spans received" || true
	@echo "✓ Ingestion checked"
	@echo ""
	@echo "[5/12] Checking compactor..."
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 | grep -i compactor || true
	@echo "✓ Compactor checked"
	@echo ""
	@echo "[6/12] Checking storage backend..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/tempo/tempo.yaml | grep -A5 "storage:" || true
	@echo "✓ Storage checked"
	@echo ""
	@echo "[7/12] Checking PVC status..."
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) || true
	@echo "✓ PVC checked"
	@echo ""
	@echo "[8/12] Checking resource usage..."
	@kubectl top pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) || echo "Metrics server not available"
	@echo ""
	@echo "[9/12] Checking recent errors..."
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i error || echo "No recent errors"
	@echo ""
	@echo "[10/12] Checking OTLP receiver..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- netstat -ln | grep 4317 || echo "OTLP gRPC port check skipped"
	@echo "✓ OTLP receiver checked"
	@echo ""
	@echo "[11/12] Checking distributor ring..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/distributor/ring || true
	@echo "✓ Ring checked"
	@echo ""
	@echo "[12/12] Checking backup status..."
	@if [ -d "$(BACKUP_DIR)/full" ]; then \
		echo "Latest backup: $$(ls -t $(BACKUP_DIR)/full | head -1)"; \
	else \
		echo "⚠ No backups found - create one before upgrading!"; \
	fi
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo "Recommendations:"
	@echo "  1. Create backup: make -f make/ops/tempo.mk tempo-backup-all"
	@echo "  2. Flush WAL: make -f make/ops/tempo.mk tempo-flush-wal"
	@echo "  3. Review release notes"
	@echo "  4. Test upgrade in staging first"

# Post-upgrade validation
.PHONY: tempo-post-upgrade-check
tempo-post-upgrade-check:
	@echo "=== Tempo Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/10] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "[2/10] Checking readiness..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready
	@echo "✓ Tempo ready"
	@echo ""
	@echo "[3/10] Checking version..."
	@kubectl get deployment/$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo ""
	@echo "[4/10] Checking OTLP receivers..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- netstat -ln | grep -E "(4317|4318)" || echo "OTLP ports check skipped"
	@echo "✓ Receivers checked"
	@echo ""
	@echo "[5/10] Sending test trace..."
	@make -f make/ops/tempo.mk tempo-test-trace || true
	@echo ""
	@echo "[6/10] Checking compactor..."
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=50 | grep -i compactor || echo "Compactor logs not found"
	@echo ""
	@echo "[7/10] Checking for errors..."
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 | grep -i error || echo "No errors found"
	@echo ""
	@echo "[8/10] Checking resource usage..."
	@kubectl top pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) || echo "Metrics server not available"
	@echo ""
	@echo "[9/10] Checking Grafana datasource..."
	@echo "Test querying traces in Grafana"
	@echo ""
	@echo "[10/10] Checking distributor ring..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/distributor/ring || true
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="
	@echo "If all checks passed, upgrade is successful!"

# Upgrade rollback
.PHONY: tempo-upgrade-rollback
tempo-upgrade-rollback:
	@echo "=== Rolling back Tempo upgrade ==="
	@echo "WARNING: This will rollback to the previous Helm release"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Rollback cancelled"; \
		exit 1; \
	fi
	@helm rollback $(CHART_NAME) -n $(NAMESPACE)
	@kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
	@echo "Rollback complete - running post-upgrade checks..."
	@make -f make/ops/tempo.mk tempo-post-upgrade-check

# Compactor operations
.PHONY: tempo-compactor-status tempo-compactor-force-run

tempo-compactor-status:
	@echo "Checking compactor status..."
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 | grep -i compactor

tempo-compactor-force-run:
	@echo "Triggering compactor run..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- -X POST http://localhost:3200/compact
