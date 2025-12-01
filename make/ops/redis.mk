# redis 차트 설정
CHART_NAME := redis
CHART_DIR := charts/$(CHART_NAME)

# Redis password (optional - fetched from secret if not provided)
REDIS_PASSWORD ?= $(shell $(KUBECTL) get secret $(CHART_NAME) -o jsonpath='{.data.redis-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
REDIS_AUTH := $(if $(REDIS_PASSWORD),-a '$(REDIS_PASSWORD)',)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Redis 특화 타겟
.PHONY: redis-cli
redis-cli:
	@echo "Running redis-cli command..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) $(CMD)

.PHONY: redis-ping
redis-ping:
	@echo "Pinging Redis server..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) ping

.PHONY: redis-info
redis-info:
	@echo "Getting Redis server info..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) info

.PHONY: redis-monitor
redis-monitor:
	@echo "Monitoring Redis commands in real-time..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) monitor

.PHONY: redis-memory
redis-memory:
	@echo "Getting Redis memory info..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) info memory

.PHONY: redis-stats
redis-stats:
	@echo "Getting Redis stats..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) info stats

.PHONY: redis-clients
redis-clients:
	@echo "Listing Redis client connections..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) client list

.PHONY: redis-bgsave
redis-bgsave:
	@echo "Triggering background save..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) bgsave

.PHONY: redis-backup
redis-backup:
	@echo "Backing up Redis data..."
	@mkdir -p tmp/redis-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) bgsave
	@sleep 5
	@$(KUBECTL) cp $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/data/dump.rdb tmp/redis-backups/dump-$$(date +%Y%m%d-%H%M%S).rdb
	@echo "Backup completed: tmp/redis-backups/dump-$$(date +%Y%m%d-%H%M%S).rdb"

.PHONY: redis-restore
redis-restore:
	@echo "Restoring Redis data from file: $(FILE)"
	@if [ -z "$(FILE)" ]; then echo "Error: FILE parameter required"; exit 1; fi
	@$(KUBECTL) cp $(FILE) $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/data/dump.rdb
	@echo "Restarting Redis to load backup..."
	@$(KUBECTL) delete pod $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")
	@echo "Restore completed. Wait for pod to restart."

.PHONY: redis-flushall
redis-flushall:
	@echo "WARNING: This will delete ALL data in Redis!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) flushall
	@echo "All data flushed"

.PHONY: redis-slowlog
redis-slowlog:
	@echo "Getting Redis slow log..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) slowlog get 10

.PHONY: redis-bigkeys
redis-bigkeys:
	@echo "Finding biggest keys..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) --bigkeys

.PHONY: redis-config-get
redis-config-get:
	@echo "Getting Redis configuration: $(PARAM)"
	@if [ -z "$(PARAM)" ]; then \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) config get '*'; \
	else \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(REDIS_AUTH) config get $(PARAM); \
	fi

# Replication specific commands
.PHONY: redis-replication-info
redis-replication-info:
	@echo "Getting replication status for all Redis pods..."
	@for pod in $$($(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[*].metadata.name}'); do \
		echo ""; \
		echo "=== Pod: $$pod ==="; \
		$(KUBECTL) exec $$pod -- redis-cli $(REDIS_AUTH) info replication | grep -E "role:|connected_slaves:|master_host:|master_port:|master_link_status:"; \
	done

.PHONY: redis-master-info
redis-master-info:
	@echo "Getting master pod info..."
	@$(KUBECTL) exec $(CHART_NAME)-0 -- redis-cli $(REDIS_AUTH) info replication

.PHONY: redis-replica-lag
redis-replica-lag:
	@echo "Checking replication lag for all replicas..."
	@for pod in $$($(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v '\-0$$'); do \
		echo ""; \
		echo "=== Replica: $$pod ==="; \
		$(KUBECTL) exec $$pod -- redis-cli $(REDIS_AUTH) info replication | grep -E "master_link_status:|master_last_io_seconds_ago:|master_sync_in_progress:"; \
	done

.PHONY: redis-role
redis-role:
	@echo "Checking role of pod: $(POD)"
	@if [ -z "$(POD)" ]; then \
		echo "Error: POD parameter required (e.g., POD=redis-0)"; \
		exit 1; \
	fi
	@$(KUBECTL) exec $(POD) -- redis-cli $(REDIS_AUTH) role

.PHONY: redis-shell
redis-shell:
	@echo "Opening shell in Redis pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/sh

.PHONY: redis-logs
redis-logs:
	@echo "Tailing Redis logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: redis-metrics
redis-metrics:
	@echo "Fetching Redis metrics (if exporter is enabled)..."
	@$(KUBECTL) port-forward $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") 9121:9121 &
	@sleep 2
	@curl -s http://localhost:9121/metrics || echo "Metrics exporter not enabled or not accessible"
	@pkill -f "port-forward.*9121"

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Redis specific targets:"
	@echo "  redis-cli            - Run redis-cli command (requires CMD parameter)"
	@echo "  redis-ping           - Ping Redis server"
	@echo "  redis-info           - Get Redis server info"
	@echo "  redis-monitor        - Monitor Redis commands in real-time"
	@echo "  redis-memory         - Get Redis memory info"
	@echo "  redis-stats          - Get Redis statistics"
	@echo "  redis-clients        - List client connections"
	@echo ""
	@echo "Data Management:"
	@echo "  redis-bgsave         - Trigger background save"
	@echo "  redis-backup         - Backup Redis data to tmp/redis-backups/"
	@echo "  redis-restore        - Restore from backup (requires FILE parameter)"
	@echo "  redis-flushall       - Delete ALL data (with confirmation)"
	@echo ""
	@echo "Analysis:"
	@echo "  redis-slowlog        - Get slow query log"
	@echo "  redis-bigkeys        - Find biggest keys"
	@echo "  redis-config-get     - Get config (optional PARAM parameter)"
	@echo ""
	@echo "Replication (Master-Slave):"
	@echo "  redis-replication-info - Get replication status for all pods"
	@echo "  redis-master-info      - Get master pod replication info"
	@echo "  redis-replica-lag      - Check replication lag for all replicas"
	@echo "  redis-role             - Check role of specific pod (requires POD parameter)"
	@echo ""
	@echo "Utilities:"
	@echo "  redis-shell          - Open shell in Redis pod"
	@echo "  redis-logs           - Tail Redis logs"
	@echo "  redis-metrics        - Fetch Prometheus metrics (if enabled)"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help

# ============================================================================
# Enhanced Backup & Recovery Operations
# ============================================================================
# See docs/redis-backup-guide.md for comprehensive procedures

# Backup directory
BACKUP_DIR ?= tmp/redis-backups
BACKUP_TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# Full backup (RDB + AOF + Config)
.PHONY: redis-full-backup
redis-full-backup:
	@echo "Creating full Redis backup (RDB + AOF + Config)..."
	@mkdir -p $(BACKUP_DIR)
	@$(MAKE) -f make/ops/redis.mk redis-backup-rdb
	@$(MAKE) -f make/ops/redis.mk redis-backup-aof
	@$(MAKE) -f make/ops/redis.mk redis-backup-config
	@echo "Full backup completed: $(BACKUP_DIR)/"

# RDB snapshot backup
.PHONY: redis-backup-rdb
redis-backup-rdb:
	@echo "Creating RDB snapshot backup..."
	@mkdir -p $(BACKUP_DIR)
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Triggering BGSAVE on pod: $$POD"; \
	$(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) BGSAVE; \
	echo "Waiting for BGSAVE to complete..."; \
	sleep 3; \
	LASTSAVE=$$($(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) LASTSAVE); \
	echo "Last save timestamp: $$LASTSAVE"; \
	BACKUP_FILE="$(BACKUP_DIR)/redis-rdb-$(BACKUP_TIMESTAMP).rdb"; \
	$(KUBECTL) cp $$POD:/data/dump.rdb $$BACKUP_FILE && \
	echo "RDB backup saved: $$BACKUP_FILE"

# AOF backup
.PHONY: redis-backup-aof
redis-backup-aof:
	@echo "Creating AOF backup..."
	@mkdir -p $(BACKUP_DIR)
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Backing up AOF from pod: $$POD"; \
	BACKUP_FILE="$(BACKUP_DIR)/redis-aof-$(BACKUP_TIMESTAMP).aof"; \
	$(KUBECTL) exec $$POD -- test -f /data/appendonly.aof && \
	$(KUBECTL) cp $$POD:/data/appendonly.aof $$BACKUP_FILE && \
	echo "AOF backup saved: $$BACKUP_FILE" || \
	echo "AOF not enabled or file doesn't exist"

# Configuration backup
.PHONY: redis-backup-config
redis-backup-config:
	@echo "Backing up Redis configuration..."
	@mkdir -p $(BACKUP_DIR)
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	BACKUP_FILE="$(BACKUP_DIR)/redis-config-$(BACKUP_TIMESTAMP).conf"; \
	$(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) CONFIG GET '*' > $$BACKUP_FILE && \
	echo "Configuration backup saved: $$BACKUP_FILE"

# Kubernetes resources backup
.PHONY: redis-backup-k8s-resources
redis-backup-k8s-resources:
	@echo "Backing up Kubernetes resources..."
	@mkdir -p $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)
	@$(KUBECTL) get statefulset $(CHART_NAME) -o yaml > $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/statefulset.yaml
	@$(KUBECTL) get service $(CHART_NAME) -o yaml > $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/service.yaml
	@$(KUBECTL) get configmap -l app.kubernetes.io/name=$(CHART_NAME) -o yaml > $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/configmaps.yaml
	@$(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME) -o yaml > $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/secrets.yaml
	@$(KUBECTL) get pvc -l app.kubernetes.io/name=$(CHART_NAME) -o yaml > $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/pvcs.yaml
	@echo "Kubernetes resources backed up to: $(BACKUP_DIR)/k8s-$(BACKUP_TIMESTAMP)/"

# Create PVC snapshot (requires VolumeSnapshot CRD)
.PHONY: redis-create-pvc-snapshot
redis-create-pvc-snapshot:
	@echo "Creating VolumeSnapshot for Redis PVC..."
	@PVC=$$($(KUBECTL) get pvc -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	if [ -z "$$PVC" ]; then echo "Error: No PVC found"; exit 1; fi; \
	SNAPSHOT_NAME="redis-snapshot-$(BACKUP_TIMESTAMP)"; \
	cat <<EOF | $(KUBECTL) apply -f - ; \
apiVersion: snapshot.storage.k8s.io/v1; \
kind: VolumeSnapshot; \
metadata:; \
  name: $$SNAPSHOT_NAME; \
spec:; \
  volumeSnapshotClassName: csi-snapclass; \
  source:; \
    persistentVolumeClaimName: $$PVC; \
EOF \
	echo "VolumeSnapshot created: $$SNAPSHOT_NAME"

# Restore from RDB backup
.PHONY: redis-restore-rdb
redis-restore-rdb:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-restore-rdb BACKUP_FILE=tmp/redis-backups/redis-rdb-20250101-120000.rdb"; \
		exit 1; \
	fi
	@echo "Restoring Redis from RDB backup: $(BACKUP_FILE)"
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Stopping Redis for restore..."; \
	$(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) SHUTDOWN NOSAVE || true; \
	sleep 2; \
	echo "Copying RDB file to pod..."; \
	$(KUBECTL) cp $(BACKUP_FILE) $$POD:/data/dump.rdb; \
	echo "Restarting pod to load RDB..."; \
	$(KUBECTL) delete pod $$POD; \
	echo "Restore initiated. Wait for pod to restart and load data."

# Restore from AOF backup
.PHONY: redis-restore-aof
redis-restore-aof:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-restore-aof BACKUP_FILE=tmp/redis-backups/redis-aof-20250101-120000.aof"; \
		exit 1; \
	fi
	@echo "Restoring Redis from AOF backup: $(BACKUP_FILE)"
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	echo "Stopping Redis for restore..."; \
	$(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) SHUTDOWN NOSAVE || true; \
	sleep 2; \
	echo "Copying AOF file to pod..."; \
	$(KUBECTL) cp $(BACKUP_FILE) $$POD:/data/appendonly.aof; \
	echo "Restarting pod to load AOF..."; \
	$(KUBECTL) delete pod $$POD; \
	echo "Restore initiated. Wait for pod to restart and load data."

# Restore configuration
.PHONY: redis-restore-config
redis-restore-config:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-restore-config BACKUP_FILE=tmp/redis-backups/redis-config-20250101-120000.conf"; \
		exit 1; \
	fi
	@echo "Restoring Redis configuration from: $(BACKUP_FILE)"
	@echo "Note: This requires manual review and Helm upgrade"
	@cat $(BACKUP_FILE)

# Disaster recovery from full backup
.PHONY: redis-disaster-recovery
redis-disaster-recovery:
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "Error: BACKUP_DIR parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-disaster-recovery BACKUP_DIR=tmp/redis-backups"; \
		exit 1; \
	fi
	@echo "=== Redis Disaster Recovery Procedure ==="
	@echo "1. Checking for latest backups in $(BACKUP_DIR)..."
	@ls -lht $(BACKUP_DIR)/redis-rdb-*.rdb 2>/dev/null | head -5 || echo "No RDB backups found"
	@echo ""
	@echo "2. Ensure Redis is running..."
	@$(MAKE) -f make/ops/redis.mk redis-health || echo "Redis not healthy - starting recovery"
	@echo ""
	@echo "3. To restore from RDB backup, run:"
	@echo "   make -f make/ops/redis.mk redis-restore-rdb BACKUP_FILE=<rdb-file>"
	@echo ""
	@echo "4. After restore, verify data:"
	@echo "   make -f make/ops/redis.mk redis-dbsize"

# Restore from VolumeSnapshot
.PHONY: redis-restore-from-pvc-snapshot
redis-restore-from-pvc-snapshot:
	@if [ -z "$(SNAPSHOT_NAME)" ]; then \
		echo "Error: SNAPSHOT_NAME parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-restore-from-pvc-snapshot SNAPSHOT_NAME=redis-snapshot-20250101-120000"; \
		exit 1; \
	fi
	@echo "Restoring Redis PVC from snapshot: $(SNAPSHOT_NAME)"
	@echo "This requires scaling down StatefulSet and recreating PVC"
	@echo "Manual steps required - see docs/redis-backup-guide.md"

# Promote replica to primary (manual failover)
.PHONY: redis-promote-replica
redis-promote-replica:
	@if [ -z "$(POD)" ]; then \
		echo "Error: POD parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-promote-replica POD=redis-1"; \
		exit 1; \
	fi
	@echo "Promoting replica $(POD) to primary..."
	@$(KUBECTL) exec $(POD) -- redis-cli $(REDIS_AUTH) REPLICAOF NO ONE
	@echo "Replica promoted to primary. Verify with: make -f make/ops/redis.mk redis-role POD=$(POD)"

# Force replica re-sync
.PHONY: redis-resync-replica
redis-resync-replica:
	@if [ -z "$(POD)" ]; then \
		echo "Error: POD parameter required"; \
		echo "Usage: make -f make/ops/redis.mk redis-resync-replica POD=redis-1"; \
		exit 1; \
	fi
	@echo "Forcing re-sync for replica $(POD)..."
	@MASTER_HOST="$(CHART_NAME)-0.$(CHART_NAME)-headless.$(NAMESPACE).svc.cluster.local"; \
	$(KUBECTL) exec $(POD) -- redis-cli $(REDIS_AUTH) REPLICAOF $$MASTER_HOST 6379; \
	echo "Re-sync initiated. Monitor with: make -f make/ops/redis.mk redis-replica-lag"

# Check database size
.PHONY: redis-dbsize
redis-dbsize:
	@echo "Checking Redis database size..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) DBSIZE

# Check last RDB save
.PHONY: redis-lastsave
redis-lastsave:
	@echo "Checking last RDB save timestamp..."
	@POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"); \
	LASTSAVE=$$($(KUBECTL) exec $$POD -- redis-cli $(REDIS_AUTH) LASTSAVE); \
	CURRENT=$$(date +%s); \
	AGE=$$(($$CURRENT - $$LASTSAVE)); \
	echo "Last save: $$LASTSAVE ($$AGE seconds ago)"

# Manual RDB save (foreground)
.PHONY: redis-save
redis-save:
	@echo "Triggering foreground SAVE (blocks Redis)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) SAVE
	@echo "SAVE completed"

# AOF rewrite
.PHONY: redis-aof-rewrite
redis-aof-rewrite:
	@echo "Triggering AOF rewrite..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) BGREWRITEAOF
	@echo "AOF rewrite initiated"

# ============================================================================
# Upgrade Operations
# ============================================================================
# See docs/redis-upgrade-guide.md for comprehensive procedures

# Pre-upgrade checks
.PHONY: redis-pre-upgrade-check
redis-pre-upgrade-check:
	@echo "=== Redis Pre-Upgrade Checklist ==="
	@echo ""
	@echo "1. Current Redis Version:"
	@$(MAKE) -f make/ops/redis.mk redis-version
	@echo ""
	@echo "2. Redis Health:"
	@$(MAKE) -f make/ops/redis.mk redis-health
	@echo ""
	@echo "3. Database Size:"
	@$(MAKE) -f make/ops/redis.mk redis-dbsize
	@echo ""
	@echo "4. Replication Status:"
	@$(MAKE) -f make/ops/redis.mk redis-replication-info
	@echo ""
	@echo "5. Last RDB Save:"
	@$(MAKE) -f make/ops/redis.mk redis-lastsave
	@echo ""
	@echo "6. Memory Usage:"
	@$(KUBECTL) top pod -l app.kubernetes.io/name=$(CHART_NAME) 2>/dev/null || echo "Metrics not available"
	@echo ""
	@echo "✅ Pre-upgrade check completed"
	@echo "⚠️  NEXT STEP: Create full backup with: make -f make/ops/redis.mk redis-full-backup"

# Post-upgrade validation
.PHONY: redis-post-upgrade-check
redis-post-upgrade-check:
	@echo "=== Redis Post-Upgrade Validation ==="
	@echo ""
	@echo "1. Verify Redis Version:"
	@$(MAKE) -f make/ops/redis.mk redis-version
	@echo ""
	@echo "2. Health Check:"
	@$(MAKE) -f make/ops/redis.mk redis-health
	@echo ""
	@echo "3. Connectivity Test:"
	@$(MAKE) -f make/ops/redis.mk redis-ping
	@echo ""
	@echo "4. Database Size (data integrity):"
	@$(MAKE) -f make/ops/redis.mk redis-dbsize
	@echo ""
	@echo "5. Replication Status:"
	@$(MAKE) -f make/ops/redis.mk redis-replication-info
	@echo ""
	@echo "6. Check for errors in logs:"
	@$(KUBECTL) logs $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") --tail=50 | grep -i error || echo "No errors found"
	@echo ""
	@echo "✅ Post-upgrade validation completed"

# Quick upgrade validation
.PHONY: redis-validate-upgrade
redis-validate-upgrade:
	@echo "Quick upgrade validation..."
	@$(MAKE) -f make/ops/redis.mk redis-version
	@$(MAKE) -f make/ops/redis.mk redis-ping
	@$(MAKE) -f make/ops/redis.mk redis-dbsize

# Check replication status (for rolling upgrade)
.PHONY: redis-check-replication
redis-check-replication:
	@echo "Checking replication status for upgrade..."
	@$(MAKE) -f make/ops/redis.mk redis-replication-info
	@echo ""
	@echo "Verify that all replicas are connected and in sync before upgrading"

# Rollback via Helm
.PHONY: redis-upgrade-rollback
redis-upgrade-rollback:
	@echo "Rolling back Redis upgrade..."
	@helm history $(CHART_NAME) -n $(NAMESPACE)
	@echo ""
	@echo "To rollback, run: helm rollback $(CHART_NAME) -n $(NAMESPACE)"
	@echo "⚠️  This will revert to the previous Helm revision"

# ============================================================================
# Additional Operations
# ============================================================================

# Redis version
.PHONY: redis-version
redis-version:
	@echo "Redis version:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) INFO server | grep redis_version

# Health check
.PHONY: redis-health
redis-health:
	@echo "Checking Redis health..."
	@$(MAKE) -f make/ops/redis.mk redis-ping
	@echo "Memory:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) INFO memory | grep used_memory_human
	@echo "Clients:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) INFO clients | grep connected_clients

# Flush database (with confirmation)
.PHONY: redis-flushdb
redis-flushdb:
	@echo "⚠️  WARNING: This will delete ALL data in current database!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) FLUSHDB
	@echo "Database flushed"

# List all keys (dangerous for large databases)
.PHONY: redis-keys
redis-keys:
	@echo "Listing all keys (use with caution in production)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) KEYS '*'

# Latency monitoring
.PHONY: redis-latency
redis-latency:
	@echo "Monitoring Redis latency (run for 10 seconds)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) --latency-history

# Memory statistics
.PHONY: redis-memory-stats
redis-memory-stats:
	@echo "Redis memory statistics:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) MEMORY STATS

# Configuration (full)
.PHONY: redis-config
redis-config:
	@echo "Redis configuration:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		redis-cli $(REDIS_AUTH) CONFIG GET '*'

# Bash shell access
.PHONY: redis-bash
redis-bash:
	@echo "Opening bash shell in Redis pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/bash

# Describe pod
.PHONY: redis-describe
redis-describe:
	@echo "Describing Redis pod..."
	@$(KUBECTL) describe pod $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

# View events
.PHONY: redis-events
redis-events:
	@echo "Recent events for Redis resources..."
	@$(KUBECTL) get events --sort-by=.metadata.creationTimestamp | grep $(CHART_NAME)

# Resource usage
.PHONY: redis-top
redis-top:
	@echo "Resource usage for Redis pods..."
	@$(KUBECTL) top pod -l app.kubernetes.io/name=$(CHART_NAME)

# Port forwarding
.PHONY: redis-port-forward
redis-port-forward:
	@echo "Port forwarding Redis to localhost:6379..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME) 6379:6379

# Force failover (emergency)
.PHONY: redis-force-failover
redis-force-failover:
	@echo "⚠️  EMERGENCY FAILOVER - USE WITH CAUTION"
	@echo "This will promote redis-1 to primary"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@$(MAKE) -f make/ops/redis.mk redis-promote-replica POD=redis-1
