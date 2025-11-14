# Vaultwarden Chart Operational Commands
#
# This Makefile provides day-2 operational commands for Vaultwarden deployments.

include make/common.mk

CHART_NAME := vaultwarden
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)

# ========================================
# Access & Debugging
# ========================================

## vw-port-forward: Port forward Vaultwarden web UI to localhost:8080
.PHONY: vw-port-forward
vw-port-forward:
	@echo "Forwarding Vaultwarden web UI to http://localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 8080:80

## vw-logs: View Vaultwarden logs
.PHONY: vw-logs
vw-logs:
	@WORKLOAD_TYPE=$$(kubectl get deployment,statefulset -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].kind}' 2>/dev/null | tr '[:upper:]' '[:lower:]'); \
	if [ -z "$$WORKLOAD_TYPE" ]; then \
		echo "Error: No deployment or statefulset found"; exit 1; \
	fi; \
	kubectl logs -f -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME)-$(CHART_NAME) --tail=100

## vw-shell: Open shell in Vaultwarden container
.PHONY: vw-shell
vw-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## vw-restart: Restart Vaultwarden deployment
.PHONY: vw-restart
vw-restart:
	@WORKLOAD_TYPE=$$(kubectl get deployment,statefulset -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].kind}' 2>/dev/null | tr '[:upper:]' '[:lower:]'); \
	if [ -z "$$WORKLOAD_TYPE" ]; then \
		echo "Error: No deployment or statefulset found"; exit 1; \
	fi; \
	kubectl rollout restart -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME)-$(CHART_NAME) && \
	kubectl rollout status -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME)-$(CHART_NAME)

## vw-describe: Describe Vaultwarden pod
.PHONY: vw-describe
vw-describe:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## vw-events: Show Vaultwarden pod events
.PHONY: vw-events
vw-events:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl get events -n $(NAMESPACE) --field-selector involvedObject.name=$$POD --sort-by='.lastTimestamp'

## vw-stats: Show resource usage statistics
.PHONY: vw-stats
vw-stats:
	@echo "=== Vaultwarden Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# Admin Panel
# ========================================

## vw-get-admin-token: Retrieve admin panel token
.PHONY: vw-get-admin-token
vw-get-admin-token:
	@echo "Admin Token:"
	@kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.admin-token}' 2>/dev/null | base64 -d || echo "Admin token not set"
	@echo ""

## vw-admin: Open admin panel (requires port-forward in another terminal)
.PHONY: vw-admin
vw-admin:
	@echo "Opening admin panel at http://localhost:8080/admin"
	@echo "Retrieve admin token with: make vw-get-admin-token"
	@open http://localhost:8080/admin 2>/dev/null || xdg-open http://localhost:8080/admin 2>/dev/null || echo "Please open http://localhost:8080/admin in your browser"

# ========================================
# Database Operations
# ========================================

## vw-backup-db: Backup SQLite database to tmp/vaultwarden-backups/
.PHONY: vw-backup-db
vw-backup-db:
	@echo "Backing up Vaultwarden database..."
	@mkdir -p tmp/vaultwarden-backups
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	BACKUP_FILE="tmp/vaultwarden-backups/db-$$(date +%Y%m%d-%H%M%S).sqlite3"; \
	kubectl exec -n $(NAMESPACE) $$POD -- test -f /data/db.sqlite3 && \
	kubectl cp $(NAMESPACE)/$$POD:/data/db.sqlite3 $$BACKUP_FILE && \
	echo "Database backed up to $$BACKUP_FILE" || \
	echo "Error: SQLite database not found (are you using PostgreSQL/MySQL mode?)"

## vw-restore-db: Restore SQLite database from backup (requires FILE=path/to/backup.sqlite3)
.PHONY: vw-restore-db
vw-restore-db:
ifndef FILE
	@echo "Error: FILE parameter required"
	@echo "Usage: make vw-restore-db FILE=tmp/vaultwarden-backups/db.sqlite3"
	@exit 1
endif
	@echo "Restoring database from $(FILE)..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl cp $(FILE) $(NAMESPACE)/$$POD:/data/db.sqlite3 && \
	echo "Database restored successfully"

## vw-db-test: Test database connection (PostgreSQL/MySQL mode)
.PHONY: vw-db-test
vw-db-test:
	@echo "Testing database connection..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_URL=$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.database-url}' 2>/dev/null | base64 -d); \
	if [ -z "$$DB_URL" ]; then \
		echo "Error: External database not configured (running in SQLite mode)"; \
		exit 1; \
	fi; \
	if echo "$$DB_URL" | grep -q "^postgresql://"; then \
		DB_HOST=$$(echo "$$DB_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
		DB_PORT=$$(echo "$$DB_URL" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p'); \
		DB_USER=$$(echo "$$DB_URL" | sed -n 's/postgresql:\/\/\([^:]*\):.*/\1/p'); \
		kubectl exec -n $(NAMESPACE) $$POD -- sh -c "PGPASSWORD=\$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.database-password}' | base64 -d) pg_isready -h $$DB_HOST -p $$DB_PORT -U $$DB_USER" && \
		echo "PostgreSQL connection successful"; \
	elif echo "$$DB_URL" | grep -q "^mysql://"; then \
		DB_HOST=$$(echo "$$DB_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
		DB_PORT=$$(echo "$$DB_URL" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p'); \
		DB_USER=$$(echo "$$DB_URL" | sed -n 's/mysql:\/\/\([^:]*\):.*/\1/p'); \
		kubectl exec -n $(NAMESPACE) $$POD -- sh -c "MYSQL_PWD=\$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.database-password}' | base64 -d) mysqladmin ping -h $$DB_HOST -P $$DB_PORT -u $$DB_USER --silent" && \
		echo "MySQL connection successful"; \
	fi

# ========================================
# Configuration
# ========================================

## vw-get-config: Show current configuration
.PHONY: vw-get-config
vw-get-config:
	@echo "=== Vaultwarden Configuration ==="
	@echo ""
	@echo "Workload Type:"
	@kubectl get deployment,statefulset -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].kind}' 2>/dev/null || echo "Unknown"
	@echo ""
	@echo ""
	@echo "Database Mode:"
	@DB_URL=$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.database-url}' 2>/dev/null | base64 -d); \
	if [ -z "$$DB_URL" ]; then \
		echo "SQLite (embedded)"; \
	elif echo "$$DB_URL" | grep -q "^postgresql://"; then \
		echo "PostgreSQL (external)"; \
	elif echo "$$DB_URL" | grep -q "^mysql://"; then \
		echo "MySQL (external)"; \
	fi
	@echo ""
	@echo "Domain:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep '^DOMAIN=' | cut -d= -f2- || echo "Not set"
	@echo ""
	@echo "SMTP Enabled:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep -q '^SMTP_HOST=' && echo "Yes" || echo "No"
	@echo ""
	@echo "WebSocket Enabled:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep '^WEBSOCKET_ENABLED=' | cut -d= -f2- || echo "Unknown"

## vw-get-smtp-password: Retrieve SMTP password
.PHONY: vw-get-smtp-password
vw-get-smtp-password:
	@echo "SMTP Password:"
	@kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.smtp-password}' 2>/dev/null | base64 -d || echo "Not configured"
	@echo ""

# ========================================
# Helm Operations (using common.mk)
# ========================================

## help: Display this help message
.PHONY: help
help:
	@echo "Vaultwarden Chart - Operational Commands"
	@echo ""
	@echo "Access & Debugging:"
	@echo "  make vw-port-forward       - Port forward web UI to localhost:8080"
	@echo "  make vw-logs               - View application logs"
	@echo "  make vw-shell              - Open shell in container"
	@echo "  make vw-restart            - Restart deployment"
	@echo "  make vw-describe           - Describe pod"
	@echo "  make vw-events             - Show pod events"
	@echo "  make vw-stats              - Show resource usage"
	@echo ""
	@echo "Admin Panel:"
	@echo "  make vw-get-admin-token    - Retrieve admin panel token"
	@echo "  make vw-admin              - Open admin panel"
	@echo ""
	@echo "Database Operations:"
	@echo "  make vw-backup-db          - Backup SQLite database"
	@echo "  make vw-restore-db FILE=<path> - Restore SQLite database"
	@echo "  make vw-db-test            - Test database connection (PostgreSQL/MySQL)"
	@echo ""
	@echo "Configuration:"
	@echo "  make vw-get-config         - Show current configuration"
	@echo "  make vw-get-smtp-password  - Retrieve SMTP password"
	@echo ""
	@echo "Helm Operations:"
	@echo "  make lint                  - Lint chart"
	@echo "  make build                 - Build/package chart"
	@echo "  make template              - Generate templates"
	@echo "  make install               - Install chart"
	@echo "  make upgrade               - Upgrade chart"
	@echo "  make uninstall             - Uninstall chart"
	@echo ""
	@echo "Environment Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
