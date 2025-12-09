# Uptime Kuma Chart Operational Commands
#
# This Makefile provides day-2 operational commands for Uptime Kuma deployments.

include make/common.mk

CHART_NAME := uptime-kuma
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)

# Backup directory
BACKUP_DIR := tmp/uptime-kuma-backups
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# ========================================
# Access & Debugging
# ========================================

## uk-port-forward: Port forward Uptime Kuma web UI to localhost:3001
.PHONY: uk-port-forward
uk-port-forward:
	@echo "Forwarding Uptime Kuma web UI to http://localhost:3001..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 3001:3001

## uk-get-url: Get Uptime Kuma web UI URL
.PHONY: uk-get-url
uk-get-url:
	@echo "=== Uptime Kuma Web UI URL ==="
	@INGRESS=$$(kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.spec.rules[0].host}' 2>/dev/null); \
	if [ -n "$$INGRESS" ]; then \
		echo "https://$$INGRESS"; \
	else \
		echo "No ingress found. Use 'make -f make/ops/uptime-kuma.mk uk-port-forward' for localhost access."; \
	fi

## uk-logs: View Uptime Kuma logs
.PHONY: uk-logs
uk-logs:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME) --tail=100

## uk-shell: Open shell in Uptime Kuma container
.PHONY: uk-shell
uk-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## uk-restart: Restart Uptime Kuma deployment
.PHONY: uk-restart
uk-restart:
	@echo "Restarting Uptime Kuma..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)

## uk-describe: Describe Uptime Kuma pod
.PHONY: uk-describe
uk-describe:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## uk-events: Show Uptime Kuma pod events
.PHONY: uk-events
uk-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## uk-stats: Show resource usage statistics
.PHONY: uk-stats
uk-stats:
	@echo "=== Uptime Kuma Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# Database Operations (SQLite)
# ========================================

## uk-db-check: Check SQLite database integrity
.PHONY: uk-db-check
uk-db-check:
	@echo "=== Checking SQLite Database Integrity ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'PRAGMA integrity_check;'" 2>/dev/null || echo "Database not found or error"

## uk-db-vacuum: Vacuum SQLite database to reclaim space
.PHONY: uk-db-vacuum
uk-db-vacuum:
	@echo "=== Vacuuming SQLite Database ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Before:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /app/data/kuma.db; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'VACUUM;'"; \
	echo "After:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /app/data/kuma.db

## uk-db-analyze: Analyze SQLite database for query optimization
.PHONY: uk-db-analyze
uk-db-analyze:
	@echo "=== Analyzing SQLite Database ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'ANALYZE;'"
	@echo "Database analyzed successfully"

## uk-db-stats: Show database size and table counts
.PHONY: uk-db-stats
uk-db-stats:
	@echo "=== SQLite Database Statistics ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Database size:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /app/data/kuma.db; \
	echo "Table counts:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db \"SELECT name FROM sqlite_master WHERE type='table';\"" 2>/dev/null || echo "Unable to query database"

## uk-db-mariadb-check: Check MariaDB database connection (if enabled)
.PHONY: uk-db-mariadb-check
uk-db-mariadb-check:
	@echo "=== Checking MariaDB Database Connection ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_TYPE=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_TYPE")].value}'); \
	if [ "$$DB_TYPE" = "mariadb" ]; then \
		DB_HOST=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_HOST")].value}'); \
		DB_PORT=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_PORT")].value}'); \
		DB_NAME=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_NAME")].value}'); \
		echo "Database Type: MariaDB"; \
		echo "Host: $$DB_HOST"; \
		echo "Port: $$DB_PORT"; \
		echo "Database: $$DB_NAME"; \
		kubectl exec -n $(NAMESPACE) $$POD -- sh -c "node server/modules/database.js" 2>/dev/null || echo "Unable to check connection"; \
	else \
		echo "Database Type: SQLite (no MariaDB configured)"; \
	fi

# ========================================
# Monitor Management
# ========================================

## uk-check-monitors: Check monitor status and counts
.PHONY: uk-check-monitors
uk-check-monitors:
	@echo "=== Uptime Kuma Monitor Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Total monitors:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT COUNT(*) FROM monitor;'" 2>/dev/null || echo "Unable to query database"; \
	echo "Active monitors:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT COUNT(*) FROM monitor WHERE active=1;'" 2>/dev/null || echo "Unable to query database"; \
	echo "Monitor types:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT type, COUNT(*) FROM monitor GROUP BY type;'" 2>/dev/null || echo "Unable to query database"

## uk-list-monitors: List all configured monitors
.PHONY: uk-list-monitors
uk-list-monitors:
	@echo "=== Uptime Kuma Monitors ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT id, name, type, url, active FROM monitor;'" 2>/dev/null || echo "Unable to query database"

## uk-monitor-performance: Check monitor performance metrics
.PHONY: uk-monitor-performance
uk-monitor-performance:
	@echo "=== Uptime Kuma Monitor Performance ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Recent heartbeats (last 24 hours):"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db \"SELECT COUNT(*) FROM heartbeat WHERE time > datetime('now', '-1 day');\"" 2>/dev/null || echo "Unable to query database"; \
	echo "Average ping time (ms):"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT AVG(ping) FROM heartbeat WHERE ping IS NOT NULL;'" 2>/dev/null || echo "Unable to query database"

# ========================================
# Notification Management
# ========================================

## uk-test-notifications: Test notification configurations
.PHONY: uk-test-notifications
uk-test-notifications:
	@echo "=== Uptime Kuma Notification Test ==="
	@echo "Notification testing must be performed via the Web UI:"
	@echo "1. Go to Settings → Notifications"
	@echo "2. Click 'Test' button for each notification"
	@make -f make/ops/uptime-kuma.mk uk-get-url

## uk-check-notifications: Check notification configurations
.PHONY: uk-check-notifications
uk-check-notifications:
	@echo "=== Uptime Kuma Notification Configurations ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Total notifications configured:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT COUNT(*) FROM notification;'" 2>/dev/null || echo "Unable to query database"; \
	echo "Notification types:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT type, COUNT(*) FROM notification GROUP BY type;'" 2>/dev/null || echo "Unable to query database"

## uk-notification-logs: View recent notification logs
.PHONY: uk-notification-logs
uk-notification-logs:
	@echo "=== Uptime Kuma Notification Logs ==="
	@echo "Checking application logs for notification events..."
	@kubectl logs -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME) --tail=100 | grep -i "notif" || echo "No notification logs found"

# ========================================
# Status Page Management
# ========================================

## uk-list-status-pages: List all status pages
.PHONY: uk-list-status-pages
uk-list-status-pages:
	@echo "=== Uptime Kuma Status Pages ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Total status pages:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT COUNT(*) FROM status_page;'" 2>/dev/null || echo "Unable to query database"; \
	echo "Status page details:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT id, slug, title, published FROM status_page;'" 2>/dev/null || echo "Unable to query database"

## uk-status-page-performance: Check status page performance
.PHONY: uk-status-page-performance
uk-status-page-performance:
	@echo "=== Uptime Kuma Status Page Performance ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Monitor counts per status page:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db 'SELECT status_page_id, COUNT(*) FROM monitor_status_page GROUP BY status_page_id;'" 2>/dev/null || echo "Unable to query database"

# ========================================
# Storage & Configuration
# ========================================

## uk-check-data: Check data directory
.PHONY: uk-check-data
uk-check-data:
	@echo "=== Uptime Kuma Data Directory ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "du -sh /app/data && ls -lah /app/data | head -20"

## uk-check-config: Check configuration
.PHONY: uk-check-config
uk-check-config:
	@echo "=== Uptime Kuma Configuration ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Database type:"; \
	kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_TYPE")].value}' || echo "SQLite (default)"; \
	echo ""; \
	echo "Port:"; \
	kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_PORT")].value}' || echo "3001 (default)"; \
	echo ""

# ========================================
# Backup & Recovery
# ========================================

## uk-backup-data: Backup Uptime Kuma data directory
.PHONY: uk-backup-data
uk-backup-data:
	@echo "=== Backing Up Uptime Kuma Data Directory ==="
	@mkdir -p $(BACKUP_DIR)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- tar czf - /app/data | cat > $(BACKUP_DIR)/data-$(TIMESTAMP).tar.gz
	@echo "Backup saved to: $(BACKUP_DIR)/data-$(TIMESTAMP).tar.gz"
	@ls -lh $(BACKUP_DIR)/data-$(TIMESTAMP).tar.gz

## uk-backup-database: Backup SQLite database only
.PHONY: uk-backup-database
uk-backup-database:
	@echo "=== Backing Up SQLite Database ==="
	@mkdir -p $(BACKUP_DIR)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "sqlite3 /app/data/kuma.db \".backup /tmp/kuma-$(TIMESTAMP).db\""; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/kuma-$(TIMESTAMP).db $(BACKUP_DIR)/kuma-db-$(TIMESTAMP).db; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm /tmp/kuma-$(TIMESTAMP).db
	@echo "Database backup saved to: $(BACKUP_DIR)/kuma-db-$(TIMESTAMP).db"
	@ls -lh $(BACKUP_DIR)/kuma-db-$(TIMESTAMP).db

## uk-backup-mariadb: Backup MariaDB database (if enabled)
.PHONY: uk-backup-mariadb
uk-backup-mariadb:
	@echo "=== Backing Up MariaDB Database ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_TYPE=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_TYPE")].value}'); \
	if [ "$$DB_TYPE" = "mariadb" ]; then \
		mkdir -p $(BACKUP_DIR); \
		DB_HOST=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_HOST")].value}'); \
		DB_PORT=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_PORT")].value}'); \
		DB_NAME=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_NAME")].value}'); \
		DB_USER=$$(kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPTIME_KUMA_DB_USERNAME")].value}'); \
		kubectl exec -n $(NAMESPACE) $$POD -- sh -c "mysqldump -h $$DB_HOST -P $$DB_PORT -u $$DB_USER -p $$DB_NAME" > $(BACKUP_DIR)/mariadb-$(TIMESTAMP).sql; \
		echo "MariaDB backup saved to: $(BACKUP_DIR)/mariadb-$(TIMESTAMP).sql"; \
		ls -lh $(BACKUP_DIR)/mariadb-$(TIMESTAMP).sql; \
	else \
		echo "MariaDB not configured (using SQLite)"; \
	fi

## uk-full-backup: Full backup (data directory including database)
.PHONY: uk-full-backup
uk-full-backup: uk-backup-data
	@echo "Full backup completed"

## uk-backup-status: Show all available backups
.PHONY: uk-backup-status
uk-backup-status:
	@echo "=== Available Uptime Kuma Backups ==="
	@ls -lht $(BACKUP_DIR)/ 2>/dev/null || echo "No backups found"

## uk-restore-data: Restore data directory from backup (requires FILE parameter)
.PHONY: uk-restore-data
uk-restore-data:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/uptime-kuma.mk uk-restore-data FILE=tmp/uptime-kuma-backups/data-20250109-143022.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current Uptime Kuma data directory."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		cat $(FILE) | kubectl exec -i -n $(NAMESPACE) $$POD -- tar xzf - -C /; \
		echo "Data directory restored from: $(FILE)"; \
		echo "Restarting Uptime Kuma..."; \
		make -f make/ops/uptime-kuma.mk uk-restart; \
	else \
		echo "Cancelled"; \
	fi

## uk-restore-database: Restore SQLite database from backup (requires FILE parameter)
.PHONY: uk-restore-database
uk-restore-database:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/uptime-kuma.mk uk-restore-database FILE=tmp/uptime-kuma-backups/kuma-db-20250109-143022.db"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current Uptime Kuma database."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl cp -n $(NAMESPACE) $(FILE) $$POD:/app/data/kuma.db; \
		echo "Database restored from: $(FILE)"; \
		echo "Restarting Uptime Kuma..."; \
		make -f make/ops/uptime-kuma.mk uk-restart; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Upgrade Support
# ========================================

## uk-pre-upgrade-check: Pre-upgrade validation checklist
.PHONY: uk-pre-upgrade-check
uk-pre-upgrade-check:
	@echo "=== Uptime Kuma Pre-Upgrade Checklist ==="
	@echo "1. Current version:"
	@kubectl get deployment $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "2. Pod health:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "3. Storage usage:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /app/data 2>/dev/null || echo "Unable to check storage"
	@echo ""
	@echo "4. Database integrity:"
	@make -f make/ops/uptime-kuma.mk uk-db-check
	@echo ""
	@echo "5. Monitor count:"
	@make -f make/ops/uptime-kuma.mk uk-check-monitors
	@echo ""
	@echo "✅ Pre-upgrade checks complete. Don't forget to:"
	@echo "   - Backup: make -f make/ops/uptime-kuma.mk uk-full-backup"
	@echo "   - Review release notes: https://github.com/louislam/uptime-kuma/releases"

## uk-post-upgrade-check: Post-upgrade validation
.PHONY: uk-post-upgrade-check
uk-post-upgrade-check:
	@echo "=== Uptime Kuma Post-Upgrade Validation ==="
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
	@make -f make/ops/uptime-kuma.mk uk-db-check
	@echo ""
	@echo "5. Monitor count:"
	@make -f make/ops/uptime-kuma.mk uk-check-monitors
	@echo ""
	@echo "6. Web UI access:"
	@make -f make/ops/uptime-kuma.mk uk-get-url
	@echo ""
	@echo "✅ Post-upgrade checks complete. Manual validation required:"
	@echo "   - Test monitor checks"
	@echo "   - Verify all monitors running"
	@echo "   - Test notifications"
	@echo "   - Check status pages"

## uk-upgrade-rollback: Rollback to previous Helm revision
.PHONY: uk-upgrade-rollback
uk-upgrade-rollback:
	@echo "=== Rolling Back Uptime Kuma Upgrade ==="
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Rollback to previous revision? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE); \
		kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME); \
		echo "Rollback complete"; \
		make -f make/ops/uptime-kuma.mk uk-stats; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Help
# ========================================

## uk-help: Show all available Uptime Kuma commands
.PHONY: uk-help
uk-help:
	@echo "=== Uptime Kuma Operational Commands ==="
	@echo ""
	@echo "Access & Debugging:"
	@echo "  uk-port-forward              Port forward web UI to localhost:3001"
	@echo "  uk-get-url                   Get Uptime Kuma web UI URL"
	@echo "  uk-logs                      View Uptime Kuma logs"
	@echo "  uk-shell                     Open shell in Uptime Kuma container"
	@echo "  uk-restart                   Restart Uptime Kuma deployment"
	@echo "  uk-describe                  Describe Uptime Kuma pod"
	@echo "  uk-events                    Show pod events"
	@echo "  uk-stats                     Show resource usage statistics"
	@echo ""
	@echo "Database Operations (SQLite):"
	@echo "  uk-db-check                  Check database integrity"
	@echo "  uk-db-vacuum                 Vacuum database to reclaim space"
	@echo "  uk-db-analyze                Analyze database for optimization"
	@echo "  uk-db-stats                  Show database size and statistics"
	@echo "  uk-db-mariadb-check          Check MariaDB connection (if enabled)"
	@echo ""
	@echo "Monitor Management:"
	@echo "  uk-check-monitors            Check monitor status and counts"
	@echo "  uk-list-monitors             List all configured monitors"
	@echo "  uk-monitor-performance       Check monitor performance metrics"
	@echo ""
	@echo "Notification Management:"
	@echo "  uk-test-notifications        Test notification configurations"
	@echo "  uk-check-notifications       Check notification configurations"
	@echo "  uk-notification-logs         View recent notification logs"
	@echo ""
	@echo "Status Page Management:"
	@echo "  uk-list-status-pages         List all status pages"
	@echo "  uk-status-page-performance   Check status page performance"
	@echo ""
	@echo "Storage & Configuration:"
	@echo "  uk-check-data                Check data directory"
	@echo "  uk-check-config              Check configuration"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  uk-backup-data               Backup data directory"
	@echo "  uk-backup-database           Backup SQLite database"
	@echo "  uk-backup-mariadb            Backup MariaDB database (if enabled)"
	@echo "  uk-full-backup               Full backup (data + database)"
	@echo "  uk-backup-status             Show all backups"
	@echo "  uk-restore-data FILE=path    Restore data directory"
	@echo "  uk-restore-database FILE=path Restore SQLite database"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  uk-pre-upgrade-check         Pre-upgrade validation"
	@echo "  uk-post-upgrade-check        Post-upgrade validation"
	@echo "  uk-upgrade-rollback          Rollback to previous revision"
	@echo ""
	@echo "Usage examples:"
	@echo "  make -f make/ops/uptime-kuma.mk uk-port-forward"
	@echo "  make -f make/ops/uptime-kuma.mk uk-backup-data"
	@echo "  make -f make/ops/uptime-kuma.mk uk-restore-database FILE=tmp/uptime-kuma-backups/kuma-db-20250109.db"
