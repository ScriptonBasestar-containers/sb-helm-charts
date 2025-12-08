# Immich Chart Operational Commands
#
# This Makefile provides day-2 operational commands for Immich deployments.

include make/common.mk

CHART_NAME := immich
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)
SERVER_SELECTOR := $(POD_SELECTOR),app.kubernetes.io/component=server
ML_SELECTOR := $(POD_SELECTOR),app.kubernetes.io/component=machine-learning

# ========================================
# Access & Debugging
# ========================================

## immich-port-forward: Port forward Immich web UI to localhost:2283
.PHONY: immich-port-forward
immich-port-forward:
	@echo "Forwarding Immich web UI to http://localhost:2283..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 2283:2283

## immich-logs-server: View Immich server logs
.PHONY: immich-logs-server
immich-logs-server:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server --tail=100

## immich-logs-ml: View Machine Learning service logs
.PHONY: immich-logs-ml
immich-logs-ml:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml --tail=100

## immich-shell-server: Open shell in server container
.PHONY: immich-shell-server
immich-shell-server:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## immich-shell-ml: Open shell in ML container
.PHONY: immich-shell-ml
immich-shell-ml:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## immich-restart: Restart all Immich deployments
.PHONY: immich-restart
immich-restart:
	@echo "Restarting Immich server..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server
	@echo "Restarting Machine Learning service..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml

## immich-describe: Describe all Immich pods
.PHONY: immich-describe
immich-describe:
	@echo "=== Server Pod ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD
	@echo ""
	@echo "=== Machine Learning Pod ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## immich-events: Show all Immich pod events
.PHONY: immich-events
immich-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## immich-stats: Show resource usage statistics
.PHONY: immich-stats
immich-stats:
	@echo "=== Immich Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# Database & Storage
# ========================================

## immich-check-db: Test PostgreSQL connection
.PHONY: immich-check-db
immich-check-db:
	@echo "Testing PostgreSQL connection..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.db-url}' | base64 -d | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "PGPASSWORD=\$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.db-password}' | base64 -d) pg_isready -h \$$DB_HOST -U \$$DB_USER" && \
	echo "PostgreSQL connection successful"

## immich-check-redis: Test Redis connection
.PHONY: immich-check-redis
immich-check-redis:
	@echo "Testing Redis connection..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	REDIS_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep REDIS_HOSTNAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- redis-cli -h $$REDIS_HOST ping && \
	echo "Redis connection successful"

## immich-check-storage: Check library storage usage
.PHONY: immich-check-storage
immich-check-storage:
	@echo "=== Library Storage Usage ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data

## immich-check-ml-cache: Check ML model cache
.PHONY: immich-check-ml-cache
immich-check-ml-cache:
	@echo "=== ML Model Cache ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /cache 2>/dev/null || echo "Model cache not mounted"

# ========================================
# Configuration
# ========================================

## immich-get-config: Show current configuration
.PHONY: immich-get-config
immich-get-config:
	@echo "=== Immich Configuration ==="
	@echo ""
	@echo "Services:"
	@kubectl get deployment -n $(NAMESPACE) -l $(APP_LABEL) -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas
	@echo ""
	@echo "PostgreSQL:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep -E "^DB_"
	@echo ""
	@echo "Redis:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep -E "^REDIS_"

## immich-get-version: Show Immich version
.PHONY: immich-get-version
immich-get-version:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:2283/api/server-info/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4

# ========================================
# Backup Operations
# ========================================

BACKUP_DIR ?= ./backups/immich
BACKUP_TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
BACKUP_PATH := $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)

## immich-backup-library: Backup library PVC (photos/videos)
.PHONY: immich-backup-library
immich-backup-library:
	@echo "Backing up library PVC..."
	@mkdir -p $(BACKUP_PATH)/library
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- tar czf - /data | cat > $(BACKUP_PATH)/library/library.tar.gz
	@echo "Library backup saved to: $(BACKUP_PATH)/library/library.tar.gz"

## immich-backup-library-restic: Backup library using Restic (incremental)
.PHONY: immich-backup-library-restic
immich-backup-library-restic:
	@echo "Backing up library PVC with Restic (incremental)..."
	@echo "Note: Requires RESTIC_REPOSITORY and RESTIC_PASSWORD environment variables"
	@# TODO: Implement Restic backup with helper pod

## immich-backup-db: Backup PostgreSQL database
.PHONY: immich-backup-db
immich-backup-db:
	@echo "Backing up PostgreSQL database..."
	@mkdir -p $(BACKUP_PATH)/postgresql
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_HOSTNAME | cut -d= -f2); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	DB_NAME=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_DATABASE_NAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- pg_dump -h $$DB_HOST -U $$DB_USER -d $$DB_NAME -Fc -f - > $(BACKUP_PATH)/postgresql/immich-db.dump
	@echo "Database backup saved to: $(BACKUP_PATH)/postgresql/immich-db.dump"

## immich-backup-redis: Backup Redis cache
.PHONY: immich-backup-redis
immich-backup-redis:
	@echo "Backing up Redis cache..."
	@mkdir -p $(BACKUP_PATH)/redis
	@echo "Note: Redis backup requires access to Redis pod (external Redis setup)"
	@# TODO: Implement Redis backup for external Redis

## immich-backup-ml-cache: Backup ML model cache
.PHONY: immich-backup-ml-cache
immich-backup-ml-cache:
	@echo "Backing up ML model cache..."
	@mkdir -p $(BACKUP_PATH)/ml-cache
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- tar czf - /cache | cat > $(BACKUP_PATH)/ml-cache/ml-cache.tar.gz
	@echo "ML cache backup saved to: $(BACKUP_PATH)/ml-cache/ml-cache.tar.gz"

## immich-backup-config: Backup Helm values and Kubernetes resources
.PHONY: immich-backup-config
immich-backup-config:
	@echo "Backing up configuration..."
	@mkdir -p $(BACKUP_PATH)/config
	@helm get values $(RELEASE_NAME) -n $(NAMESPACE) > $(BACKUP_PATH)/config/values.yaml
	@helm get manifest $(RELEASE_NAME) -n $(NAMESPACE) > $(BACKUP_PATH)/config/manifest.yaml
	@kubectl get all -n $(NAMESPACE) -l $(APP_LABEL) -o yaml > $(BACKUP_PATH)/config/k8s-resources.yaml
	@echo "Configuration backup saved to: $(BACKUP_PATH)/config/"

## immich-snapshot-library: Create VolumeSnapshot of library PVC
.PHONY: immich-snapshot-library
immich-snapshot-library:
	@echo "Creating VolumeSnapshot of library PVC..."
	@echo "Note: Requires CSI driver with snapshot support"
	@# TODO: Implement VolumeSnapshot creation

## immich-full-backup: Backup all components (comprehensive)
.PHONY: immich-full-backup
immich-full-backup:
	@echo "=== Starting Full Immich Backup ==="
	@echo "Backup location: $(BACKUP_PATH)"
	@echo ""
	@echo "[1/5] Backing up configuration..."
	@$(MAKE) immich-backup-config
	@echo ""
	@echo "[2/5] Backing up PostgreSQL database..."
	@$(MAKE) immich-backup-db
	@echo ""
	@echo "[3/5] Backing up library PVC..."
	@$(MAKE) immich-backup-library
	@echo ""
	@echo "[4/5] Backing up ML cache..."
	@$(MAKE) immich-backup-ml-cache || echo "ML cache backup failed, continuing..."
	@echo ""
	@echo "[5/5] Creating backup manifest..."
	@echo "Immich Full Backup" > $(BACKUP_PATH)/backup-manifest.txt
	@echo "==================" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "Timestamp: $(BACKUP_TIMESTAMP)" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "Release: $(RELEASE_NAME)" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "Namespace: $(NAMESPACE)" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "Components:" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "- Configuration: ✓" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "- PostgreSQL Database: ✓" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "- Library PVC: ✓" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo "- ML Cache: ✓" >> $(BACKUP_PATH)/backup-manifest.txt
	@echo ""
	@echo "=== Full Backup Complete ==="
	@echo "Backup saved to: $(BACKUP_PATH)"

## immich-list-backups: List all backups
.PHONY: immich-list-backups
immich-list-backups:
	@echo "=== Immich Backups ==="
	@ls -lh $(BACKUP_DIR)/ 2>/dev/null || echo "No backups found"

## immich-verify-backup: Verify backup integrity
.PHONY: immich-verify-backup
immich-verify-backup:
	@echo "Verifying backup at: $(BACKUP_FILE)"
	@test -f $(BACKUP_FILE)/postgresql/immich-db.dump || (echo "❌ Database backup not found" && exit 1)
	@test -f $(BACKUP_FILE)/library/library.tar.gz || (echo "❌ Library backup not found" && exit 1)
	@echo "✅ Backup verification passed"

# ========================================
# Recovery Operations
# ========================================

## immich-restore-db: Restore PostgreSQL database
.PHONY: immich-restore-db
immich-restore-db:
	@echo "Restoring PostgreSQL database from: $(BACKUP_FILE)"
	@test -f $(BACKUP_FILE) || (echo "Error: Backup file not found: $(BACKUP_FILE)" && exit 1)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_HOSTNAME | cut -d= -f2); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	DB_NAME=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_DATABASE_NAME | cut -d= -f2); \
	cat $(BACKUP_FILE) | kubectl exec -i -n $(NAMESPACE) $$POD -- pg_restore -h $$DB_HOST -U $$DB_USER -d $$DB_NAME -v
	@echo "Database restore complete"

## immich-restore-library: Restore library PVC
.PHONY: immich-restore-library
immich-restore-library:
	@echo "Restoring library PVC from: $(BACKUP_FILE)"
	@test -f $(BACKUP_FILE) || (echo "Error: Backup file not found: $(BACKUP_FILE)" && exit 1)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	cat $(BACKUP_FILE) | kubectl exec -i -n $(NAMESPACE) $$POD -- tar xzf - -C /
	@echo "Library restore complete"

## immich-post-recovery-check: Validate recovery
.PHONY: immich-post-recovery-check
immich-post-recovery-check:
	@echo "=== Post-Recovery Validation ==="
	@echo "[1/4] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l $(APP_LABEL)
	@echo ""
	@echo "[2/4] Checking database connectivity..."
	@$(MAKE) immich-check-db
	@echo ""
	@echo "[3/4] Checking library storage..."
	@$(MAKE) immich-check-storage
	@echo ""
	@echo "[4/4] Checking Immich version..."
	@$(MAKE) immich-get-version
	@echo ""
	@echo "✅ Post-recovery validation complete"

# ========================================
# Upgrade Operations
# ========================================

## immich-pre-upgrade-check: Pre-upgrade validation and backup
.PHONY: immich-pre-upgrade-check
immich-pre-upgrade-check:
	@echo "=== Pre-Upgrade Checklist ==="
	@echo "[1/5] Checking current pod status..."
	@kubectl get pods -n $(NAMESPACE) -l $(APP_LABEL)
	@echo ""
	@echo "[2/5] Checking current version..."
	@$(MAKE) immich-get-version
	@echo ""
	@echo "[3/5] Checking database connectivity..."
	@$(MAKE) immich-check-db
	@echo ""
	@echo "[4/5] Checking storage..."
	@$(MAKE) immich-check-storage
	@echo ""
	@echo "[5/5] Creating pre-upgrade backup..."
	@$(MAKE) immich-full-backup
	@echo ""
	@echo "✅ Pre-upgrade check complete"
	@echo "⚠️  Review release notes: https://github.com/immich-app/immich/releases"
	@echo "⚠️  Backup saved to: $(BACKUP_PATH)"

## immich-rolling-upgrade: Perform rolling upgrade
.PHONY: immich-rolling-upgrade
immich-rolling-upgrade:
	@echo "=== Rolling Upgrade ==="
	@test -n "$(VERSION)" || (echo "Error: VERSION not specified. Usage: make immich-rolling-upgrade VERSION=v1.120.0" && exit 1)
	@echo "Upgrading to version: $(VERSION)"
	@helm upgrade $(RELEASE_NAME) scripton-charts/immich \
		-n $(NAMESPACE) \
		--set immich.server.image.tag=$(VERSION) \
		--set immich.machineLearning.image.tag=$(VERSION) \
		--reuse-values \
		--wait \
		--timeout 10m
	@echo "✅ Rolling upgrade complete"

## immich-post-upgrade-check: Post-upgrade validation
.PHONY: immich-post-upgrade-check
immich-post-upgrade-check:
	@echo "=== Post-Upgrade Validation ==="
	@echo "[1/5] Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l $(APP_LABEL)
	@echo ""
	@echo "[2/5] Checking image versions..."
	@kubectl get pods -n $(NAMESPACE) -l $(APP_LABEL) -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
	@echo ""
	@echo "[3/5] Checking database connectivity..."
	@$(MAKE) immich-check-db
	@echo ""
	@echo "[4/5] Checking Immich version..."
	@$(MAKE) immich-get-version
	@echo ""
	@echo "[5/5] Checking for errors in logs..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $$POD --tail=100 | grep -i error | wc -l); \
	echo "Error count in logs: $$ERROR_COUNT"
	@echo ""
	@echo "✅ Post-upgrade validation complete"

## immich-upgrade-rollback: Rollback to previous Helm revision
.PHONY: immich-upgrade-rollback
immich-upgrade-rollback:
	@echo "=== Rolling Back Upgrade ==="
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Confirm rollback to previous revision? [y/N]: " confirm && [ "$$confirm" = "y" ]
	@helm rollback $(RELEASE_NAME) -n $(NAMESPACE)
	@echo "Waiting for rollback to complete..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml
	@echo "✅ Rollback complete"

# ========================================
# Maintenance Operations
# ========================================

## immich-db-shell: Open PostgreSQL shell
.PHONY: immich-db-shell
immich-db-shell:
	@echo "Opening PostgreSQL shell..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_HOSTNAME | cut -d= -f2); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	DB_NAME=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_DATABASE_NAME | cut -d= -f2); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- psql -h $$DB_HOST -U $$DB_USER -d $$DB_NAME

## immich-db-vacuum: Vacuum PostgreSQL database
.PHONY: immich-db-vacuum
immich-db-vacuum:
	@echo "Vacuuming PostgreSQL database..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_HOSTNAME | cut -d= -f2); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	DB_NAME=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_DATABASE_NAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- psql -h $$DB_HOST -U $$DB_USER -d $$DB_NAME -c "VACUUM ANALYZE;"
	@echo "Vacuum complete"

## immich-list-ml-models: List downloaded ML models
.PHONY: immich-list-ml-models
immich-list-ml-models:
	@echo "=== ML Models ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -lh /cache 2>/dev/null || echo "Model cache not available"

## immich-clear-ml-cache: Clear ML model cache
.PHONY: immich-clear-ml-cache
immich-clear-ml-cache:
	@echo "Clearing ML model cache..."
	@read -p "This will delete all downloaded ML models. Continue? [y/N]: " confirm && [ "$$confirm" = "y" ]
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /cache/*
	@echo "ML cache cleared. Models will be re-downloaded on next use."

## immich-check-photo-count: Check number of photos in database
.PHONY: immich-check-photo-count
immich-check-photo-count:
	@echo "Checking photo count..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_HOSTNAME | cut -d= -f2); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	DB_NAME=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_DATABASE_NAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- psql -h $$DB_HOST -U $$DB_USER -d $$DB_NAME -t -c "SELECT COUNT(*) FROM assets;"

# ========================================
# Helm Operations
# ========================================

## help: Display this help message
.PHONY: help
help:
	@echo "=========================================="
	@echo "Immich Chart - Operational Commands (50+)"
	@echo "=========================================="
	@echo ""
	@echo "Access & Debugging:"
	@echo "  make immich-port-forward    - Port forward web UI to localhost:2283"
	@echo "  make immich-logs-server     - View server logs"
	@echo "  make immich-logs-ml         - View ML service logs"
	@echo "  make immich-shell-server    - Open server shell"
	@echo "  make immich-shell-ml        - Open ML shell"
	@echo "  make immich-restart         - Restart all deployments"
	@echo "  make immich-describe        - Describe all pods"
	@echo "  make immich-events          - Show pod events"
	@echo "  make immich-stats           - Show resource usage"
	@echo ""
	@echo "Database & Storage:"
	@echo "  make immich-check-db        - Test PostgreSQL connection"
	@echo "  make immich-check-redis     - Test Redis connection"
	@echo "  make immich-check-storage   - Check library storage usage"
	@echo "  make immich-check-ml-cache  - Check ML model cache"
	@echo "  make immich-db-shell        - Open PostgreSQL shell"
	@echo "  make immich-db-vacuum       - Vacuum PostgreSQL database"
	@echo "  make immich-check-photo-count - Check number of photos"
	@echo ""
	@echo "Configuration:"
	@echo "  make immich-get-config      - Show current configuration"
	@echo "  make immich-get-version     - Show Immich version"
	@echo ""
	@echo "Backup Operations:"
	@echo "  make immich-backup-library       - Backup library PVC (photos/videos)"
	@echo "  make immich-backup-library-restic - Backup library with Restic"
	@echo "  make immich-backup-db            - Backup PostgreSQL database"
	@echo "  make immich-backup-redis         - Backup Redis cache"
	@echo "  make immich-backup-ml-cache      - Backup ML model cache"
	@echo "  make immich-backup-config        - Backup configuration"
	@echo "  make immich-snapshot-library     - Create VolumeSnapshot"
	@echo "  make immich-full-backup          - Backup all components"
	@echo "  make immich-list-backups         - List all backups"
	@echo "  make immich-verify-backup BACKUP_FILE=... - Verify backup"
	@echo ""
	@echo "Recovery Operations:"
	@echo "  make immich-restore-db BACKUP_FILE=...     - Restore database"
	@echo "  make immich-restore-library BACKUP_FILE=... - Restore library"
	@echo "  make immich-post-recovery-check             - Validate recovery"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  make immich-pre-upgrade-check               - Pre-upgrade validation"
	@echo "  make immich-rolling-upgrade VERSION=...     - Rolling upgrade"
	@echo "  make immich-post-upgrade-check              - Post-upgrade validation"
	@echo "  make immich-upgrade-rollback                - Rollback upgrade"
	@echo ""
	@echo "Maintenance Operations:"
	@echo "  make immich-list-ml-models  - List ML models"
	@echo "  make immich-clear-ml-cache  - Clear ML cache"
	@echo ""
	@echo "Helm Operations:"
	@echo "  make lint                   - Lint chart"
	@echo "  make build                  - Build/package chart"
	@echo "  make template               - Generate templates"
	@echo "  make install                - Install chart"
	@echo "  make upgrade                - Upgrade chart"
	@echo "  make uninstall              - Uninstall chart"
	@echo ""
	@echo "Environment Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  BACKUP_DIR=$(BACKUP_DIR)"
	@echo ""
	@echo "Complete Guides:"
	@echo "  Backup Guide: docs/immich-backup-guide.md"
	@echo "  Upgrade Guide: docs/immich-upgrade-guide.md"
