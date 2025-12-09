# Jellyfin Chart Operational Commands
#
# This Makefile provides day-2 operational commands for Jellyfin deployments.

include make/common.mk

CHART_NAME := jellyfin
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)

# Backup directory
BACKUP_DIR := tmp/jellyfin-backups
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# ========================================
# Access & Debugging
# ========================================

## jellyfin-port-forward: Port forward Jellyfin web UI to localhost:8096
.PHONY: jellyfin-port-forward
jellyfin-port-forward:
	@echo "Forwarding Jellyfin web UI to http://localhost:8096..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 8096:8096

## jellyfin-get-url: Get Jellyfin web UI URL
.PHONY: jellyfin-get-url
jellyfin-get-url:
	@echo "=== Jellyfin Web UI URL ==="
	@INGRESS=$$(kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.spec.rules[0].host}' 2>/dev/null); \
	if [ -n "$$INGRESS" ]; then \
		echo "https://$$INGRESS"; \
	else \
		echo "No ingress found. Use 'make jellyfin-port-forward' for localhost access."; \
	fi

## jellyfin-logs: View Jellyfin logs
.PHONY: jellyfin-logs
jellyfin-logs:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME) --tail=100

## jellyfin-shell: Open shell in Jellyfin container
.PHONY: jellyfin-shell
jellyfin-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/bash

## jellyfin-restart: Restart Jellyfin deployment
.PHONY: jellyfin-restart
jellyfin-restart:
	@echo "Restarting Jellyfin..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)

## jellyfin-describe: Describe Jellyfin pod
.PHONY: jellyfin-describe
jellyfin-describe:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## jellyfin-events: Show Jellyfin pod events
.PHONY: jellyfin-events
jellyfin-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## jellyfin-stats: Show resource usage statistics
.PHONY: jellyfin-stats
jellyfin-stats:
	@echo "=== Jellyfin Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# GPU & Hardware Acceleration
# ========================================

## jellyfin-check-gpu: Verify GPU access and hardware acceleration configuration
.PHONY: jellyfin-check-gpu
jellyfin-check-gpu:
	@echo "=== Jellyfin GPU Configuration ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	HW_TYPE=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="JELLYFIN_HW_ACCEL_TYPE")].value}'); \
	echo "Hardware acceleration type: $$HW_TYPE"; \
	if [ "$$HW_TYPE" = "intel-qsv" ] || [ "$$HW_TYPE" = "amd-vaapi" ]; then \
		echo "GPU enabled: Yes"; \
		echo "/dev/dri:"; \
		kubectl exec -n $(NAMESPACE) $$POD -- ls -la /dev/dri 2>/dev/null || echo "  /dev/dri not found"; \
	elif [ "$$HW_TYPE" = "nvidia-nvenc" ]; then \
		echo "GPU enabled: Yes"; \
		kubectl exec -n $(NAMESPACE) $$POD -- nvidia-smi 2>/dev/null || echo "  nvidia-smi not available"; \
	else \
		echo "GPU enabled: No"; \
	fi

# ========================================
# Storage & Media
# ========================================

## jellyfin-check-config: Check configuration directory
.PHONY: jellyfin-check-config
jellyfin-check-config:
	@echo "=== Jellyfin Configuration Directory ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "du -sh /config && ls -lah /config | head -20"

## jellyfin-check-cache: Check transcoding cache usage
.PHONY: jellyfin-check-cache
jellyfin-check-cache:
	@echo "=== Jellyfin Transcoding Cache ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "du -sh /cache && ls -lah /cache | head -20" 2>/dev/null || echo "Cache directory not found"

## jellyfin-check-media: Check media directories
.PHONY: jellyfin-check-media
jellyfin-check-media:
	@echo "=== Jellyfin Media Directories ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "df -h | grep media || echo 'No media mounts found'" && \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -lah /media 2>/dev/null || echo "No /media directory"

## jellyfin-clear-cache: Clear transcoding cache (WARNING: destroys in-progress transcodes)
.PHONY: jellyfin-clear-cache
jellyfin-clear-cache:
	@echo "WARNING: This will delete all transcoding cache files."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /cache/*; \
		echo "Transcoding cache cleared"; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Database Operations (SQLite)
# ========================================

## jellyfin-db-check: Check SQLite database integrity
.PHONY: jellyfin-db-check
jellyfin-db-check:
	@echo "=== Checking SQLite Database Integrity ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sqlite3 /config/data/library.db "PRAGMA integrity_check;" 2>/dev/null || echo "Database not found or error"

## jellyfin-db-vacuum: Vacuum SQLite database to reclaim space
.PHONY: jellyfin-db-vacuum
jellyfin-db-vacuum:
	@echo "=== Vacuuming SQLite Database ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Before:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /config/data/library.db; \
	kubectl exec -n $(NAMESPACE) $$POD -- sqlite3 /config/data/library.db "VACUUM;"; \
	echo "After:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /config/data/library.db

## jellyfin-db-analyze: Analyze SQLite database for query optimization
.PHONY: jellyfin-db-analyze
jellyfin-db-analyze:
	@echo "=== Analyzing SQLite Database ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sqlite3 /config/data/library.db "ANALYZE;"
	@echo "Database analyzed successfully"

## jellyfin-db-stats: Show database size and table counts
.PHONY: jellyfin-db-stats
jellyfin-db-stats:
	@echo "=== SQLite Database Statistics ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Database size:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /config/data/library.db; \
	echo "Table counts:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sqlite3 /config/data/library.db "SELECT name, COUNT(*) FROM sqlite_master WHERE type='table' GROUP BY name;" 2>/dev/null || echo "Unable to query database"

# ========================================
# Plugin Management
# ========================================

## jellyfin-list-plugins: Show all installed plugins
.PHONY: jellyfin-list-plugins
jellyfin-list-plugins:
	@echo "=== Installed Jellyfin Plugins ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- ls -lah /config/plugins 2>/dev/null || echo "No plugins installed"

## jellyfin-check-plugins: Check plugin versions and compatibility
.PHONY: jellyfin-check-plugins
jellyfin-check-plugins:
	@echo "=== Jellyfin Plugin Versions ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- find /config/plugins -name "*.dll" -o -name "meta.json" 2>/dev/null || echo "No plugin metadata found"

## jellyfin-plugin-compatibility: Check plugin compatibility for target Jellyfin version
.PHONY: jellyfin-plugin-compatibility
jellyfin-plugin-compatibility:
	@if [ -z "$(TARGET_VERSION)" ]; then \
		echo "Error: TARGET_VERSION is required"; \
		echo "Usage: make jellyfin-plugin-compatibility TARGET_VERSION=10.11.0"; \
		exit 1; \
	fi
	@echo "=== Checking Plugin Compatibility for Jellyfin $(TARGET_VERSION) ==="
	@echo "Manual check required:"
	@echo "1. Visit https://jellyfin.org/docs/general/server/plugins/"
	@echo "2. Check each installed plugin's supported versions"
	@echo "3. Update incompatible plugins before upgrading"
	@echo ""
	@echo "Installed plugins:"
	@make -f make/ops/jellyfin.mk jellyfin-list-plugins

# ========================================
# Transcoding Operations
# ========================================

## jellyfin-active-transcodes: Monitor active transcoding sessions
.PHONY: jellyfin-active-transcodes
jellyfin-active-transcodes:
	@echo "=== Active Transcoding Sessions ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- ps aux | grep ffmpeg || echo "No active transcodes"

# ========================================
# Backup & Recovery
# ========================================

## jellyfin-backup-config: Backup Jellyfin configuration directory
.PHONY: jellyfin-backup-config
jellyfin-backup-config:
	@echo "=== Backing Up Jellyfin Configuration ==="
	@mkdir -p $(BACKUP_DIR)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- tar czf - /config | cat > $(BACKUP_DIR)/config-$(TIMESTAMP).tar.gz
	@echo "Backup saved to: $(BACKUP_DIR)/config-$(TIMESTAMP).tar.gz"
	@ls -lh $(BACKUP_DIR)/config-$(TIMESTAMP).tar.gz

## jellyfin-backup-database: Backup SQLite database only
.PHONY: jellyfin-backup-database
jellyfin-backup-database:
	@echo "=== Backing Up SQLite Database ==="
	@mkdir -p $(BACKUP_DIR)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sqlite3 /config/data/library.db ".backup /tmp/library-$(TIMESTAMP).db"; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/library-$(TIMESTAMP).db $(BACKUP_DIR)/library-db-$(TIMESTAMP).db; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm /tmp/library-$(TIMESTAMP).db
	@echo "Database backup saved to: $(BACKUP_DIR)/library-db-$(TIMESTAMP).db"
	@ls -lh $(BACKUP_DIR)/library-db-$(TIMESTAMP).db

## jellyfin-full-backup: Full backup (config + database + settings)
.PHONY: jellyfin-full-backup
jellyfin-full-backup: jellyfin-backup-config
	@echo "Full backup completed"

## jellyfin-backup-status: Show all available backups
.PHONY: jellyfin-backup-status
jellyfin-backup-status:
	@echo "=== Available Jellyfin Backups ==="
	@ls -lht $(BACKUP_DIR)/ 2>/dev/null || echo "No backups found"

## jellyfin-restore-config: Restore configuration from backup (requires FILE parameter)
.PHONY: jellyfin-restore-config
jellyfin-restore-config:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make jellyfin-restore-config FILE=tmp/jellyfin-backups/config-20250109-143022.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current Jellyfin configuration."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		cat $(FILE) | kubectl exec -i -n $(NAMESPACE) $$POD -- tar xzf - -C /; \
		echo "Configuration restored from: $(FILE)"; \
		echo "Restarting Jellyfin..."; \
		make -f make/ops/jellyfin.mk jellyfin-restart; \
	else \
		echo "Cancelled"; \
	fi

## jellyfin-restore-database: Restore SQLite database from backup (requires FILE parameter)
.PHONY: jellyfin-restore-database
jellyfin-restore-database:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make jellyfin-restore-database FILE=tmp/jellyfin-backups/library-db-20250109-143022.db"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current Jellyfin database."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl cp -n $(NAMESPACE) $(FILE) $$POD:/config/data/library.db; \
		echo "Database restored from: $(FILE)"; \
		echo "Restarting Jellyfin..."; \
		make -f make/ops/jellyfin.mk jellyfin-restart; \
	else \
		echo "Cancelled"; \
	fi

## jellyfin-check-libraries: Verify media libraries are loaded
.PHONY: jellyfin-check-libraries
jellyfin-check-libraries:
	@echo "=== Jellyfin Media Libraries ==="
	@echo "Check libraries via Web UI: Dashboard → Libraries"
	@echo "Or use Jellyfin API:"
	@make -f make/ops/jellyfin.mk jellyfin-get-url

# ========================================
# Upgrade Support
# ========================================

## jellyfin-pre-upgrade-check: Pre-upgrade validation checklist
.PHONY: jellyfin-pre-upgrade-check
jellyfin-pre-upgrade-check:
	@echo "=== Jellyfin Pre-Upgrade Checklist ==="
	@echo "1. Current version:"
	@kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "2. Pod health:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "3. Storage usage:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /config /cache 2>/dev/null || echo "Unable to check storage"
	@echo ""
	@echo "4. Database integrity:"
	@make -f make/ops/jellyfin.mk jellyfin-db-check
	@echo ""
	@echo "5. Installed plugins:"
	@make -f make/ops/jellyfin.mk jellyfin-list-plugins
	@echo ""
	@echo "✅ Pre-upgrade checks complete. Don't forget to:"
	@echo "   - Backup: make jellyfin-full-backup"
	@echo "   - Check plugin compatibility for target version"
	@echo "   - Review release notes: https://github.com/jellyfin/jellyfin/releases"

## jellyfin-post-upgrade-check: Post-upgrade validation
.PHONY: jellyfin-post-upgrade-check
jellyfin-post-upgrade-check:
	@echo "=== Jellyfin Post-Upgrade Validation ==="
	@echo "1. Pod status:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "2. New version:"
	@kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "3. Check for errors in logs:"
	@kubectl logs -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME) --tail=50 | grep -i error || echo "No errors found"
	@echo ""
	@echo "4. Database integrity:"
	@make -f make/ops/jellyfin.mk jellyfin-db-check
	@echo ""
	@echo "5. GPU acceleration (if enabled):"
	@make -f make/ops/jellyfin.mk jellyfin-check-gpu
	@echo ""
	@echo "6. Web UI access:"
	@make -f make/ops/jellyfin.mk jellyfin-get-url
	@echo ""
	@echo "✅ Post-upgrade checks complete. Manual validation required:"
	@echo "   - Test video playback"
	@echo "   - Verify all libraries visible"
	@echo "   - Check plugin compatibility"

## jellyfin-upgrade-rollback: Rollback to previous Helm revision
.PHONY: jellyfin-upgrade-rollback
jellyfin-upgrade-rollback:
	@echo "=== Rolling Back Jellyfin Upgrade ==="
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Rollback to previous revision? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE); \
		kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME); \
		echo "Rollback complete"; \
		make -f make/ops/jellyfin.mk jellyfin-stats; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Help
# ========================================

## jellyfin-help: Show all available Jellyfin commands
.PHONY: jellyfin-help
jellyfin-help:
	@echo "=== Jellyfin Operational Commands ==="
	@echo ""
	@echo "Access & Debugging:"
	@echo "  jellyfin-port-forward        Port forward web UI to localhost:8096"
	@echo "  jellyfin-get-url             Get Jellyfin web UI URL"
	@echo "  jellyfin-logs                View Jellyfin logs"
	@echo "  jellyfin-shell               Open shell in Jellyfin container"
	@echo "  jellyfin-restart             Restart Jellyfin deployment"
	@echo "  jellyfin-describe            Describe Jellyfin pod"
	@echo "  jellyfin-events              Show pod events"
	@echo "  jellyfin-stats               Show resource usage statistics"
	@echo ""
	@echo "GPU & Hardware Acceleration:"
	@echo "  jellyfin-check-gpu           Verify GPU access and configuration"
	@echo ""
	@echo "Storage & Media:"
	@echo "  jellyfin-check-config        Check configuration directory"
	@echo "  jellyfin-check-cache         Check transcoding cache usage"
	@echo "  jellyfin-check-media         Check media directories"
	@echo "  jellyfin-clear-cache         Clear transcoding cache"
	@echo ""
	@echo "Database Operations (SQLite):"
	@echo "  jellyfin-db-check            Check database integrity"
	@echo "  jellyfin-db-vacuum           Vacuum database to reclaim space"
	@echo "  jellyfin-db-analyze          Analyze database for optimization"
	@echo "  jellyfin-db-stats            Show database size and statistics"
	@echo ""
	@echo "Plugin Management:"
	@echo "  jellyfin-list-plugins        Show installed plugins"
	@echo "  jellyfin-check-plugins       Check plugin versions"
	@echo "  jellyfin-plugin-compatibility TARGET_VERSION=X.X.X"
	@echo ""
	@echo "Transcoding Operations:"
	@echo "  jellyfin-active-transcodes   Monitor active transcoding sessions"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  jellyfin-backup-config       Backup configuration directory"
	@echo "  jellyfin-backup-database     Backup SQLite database"
	@echo "  jellyfin-full-backup         Full backup (config + database)"
	@echo "  jellyfin-backup-status       Show all backups"
	@echo "  jellyfin-restore-config FILE=path"
	@echo "  jellyfin-restore-database FILE=path"
	@echo "  jellyfin-check-libraries     Verify media libraries"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  jellyfin-pre-upgrade-check   Pre-upgrade validation"
	@echo "  jellyfin-post-upgrade-check  Post-upgrade validation"
	@echo "  jellyfin-upgrade-rollback    Rollback to previous revision"
	@echo ""
	@echo "Usage examples:"
	@echo "  make -f make/ops/jellyfin.mk jellyfin-port-forward"
	@echo "  make -f make/ops/jellyfin.mk jellyfin-backup-config"
	@echo "  make -f make/ops/jellyfin.mk jellyfin-restore-config FILE=tmp/jellyfin-backups/config-20250109.tar.gz"
