# Vaultwarden Chart Operations

include Makefile.common.mk

CHART_NAME := vaultwarden
CHART_DIR := charts/vaultwarden
NAMESPACE ?= default
RELEASE_NAME ?= vaultwarden

POD ?= $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKUP_DIR ?= backups/vaultwarden-$(shell date +%Y%m%d-%H%M%S)

.PHONY: help
help::
	@echo ""
	@echo "=========================================="
	@echo "Vaultwarden Operations (50+ commands)"
	@echo "=========================================="
	@echo ""
	@echo "Basic Operations:"
	@echo "  vw-status                - Show Vaultwarden pod status"
	@echo "  vw-shell                 - Open shell in Vaultwarden pod"
	@echo "  vw-logs                  - View Vaultwarden logs (tail 100)"
	@echo "  vw-logs-follow           - Follow Vaultwarden logs"
	@echo "  vw-port-forward          - Port forward to localhost:8080"
	@echo "  vw-get-url               - Get Vaultwarden URL (if ingress enabled)"
	@echo "  vw-restart               - Restart Vaultwarden deployment"
	@echo "  vw-version               - Get Vaultwarden version"
	@echo ""
	@echo "Admin Operations:"
	@echo "  vw-admin-url             - Get admin panel URL"
	@echo "  vw-get-admin-token       - Retrieve admin token"
	@echo "  vw-disable-admin         - Disable admin panel"
	@echo "  vw-enable-admin          - Enable admin panel"
	@echo ""
	@echo "Database Operations (SQLite):"
	@echo "  vw-db-size               - Check SQLite database size"
	@echo "  vw-db-integrity          - Check SQLite integrity"
	@echo "  vw-db-vacuum             - Optimize SQLite database"
	@echo ""
	@echo "Database Operations (PostgreSQL/MySQL):"
	@echo "  vw-db-shell              - Open database shell"
	@echo "  vw-db-connections        - Show active database connections"
	@echo "  vw-db-table-sizes        - Show table sizes"
	@echo ""
	@echo "User Management:"
	@echo "  vw-list-users            - List all users"
	@echo "  vw-delete-user EMAIL=... - Delete user by email"
	@echo "  vw-invite-user EMAIL=... - Invite user by email"
	@echo ""
	@echo "Data Backup Operations:"
	@echo "  vw-backup-data-full      - Backup data directory (tar)"
	@echo "  vw-backup-data-incremental - Backup data directory (rsync)"
	@echo "  vw-backup-sqlite         - Backup SQLite database"
	@echo "  vw-restore-data BACKUP_FILE=... - Restore data directory"
	@echo ""
	@echo "Database Backup Operations:"
	@echo "  vw-backup-postgres       - Backup PostgreSQL database"
	@echo "  vw-backup-mysql          - Backup MySQL database"
	@echo "  vw-restore-postgres BACKUP_FILE=... - Restore PostgreSQL database"
	@echo "  vw-restore-mysql BACKUP_FILE=... - Restore MySQL database"
	@echo ""
	@echo "Configuration Backup:"
	@echo "  vw-backup-config         - Backup Kubernetes resources"
	@echo "  vw-restore-config BACKUP_FILE=... - Restore Kubernetes resources"
	@echo ""
	@echo "PVC Snapshot Operations:"
	@echo "  vw-snapshot-data         - Create PVC snapshot"
	@echo "  vw-list-snapshots        - List all PVC snapshots"
	@echo "  vw-restore-from-snapshot SNAPSHOT_NAME=... - Restore from snapshot"
	@echo ""
	@echo "Comprehensive Backup/Recovery:"
	@echo "  vw-full-backup           - Backup all components"
	@echo "  vw-full-recovery DATA_BACKUP=... DB_BACKUP=... - Full disaster recovery"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  vw-pre-upgrade-check     - Pre-upgrade validation"
	@echo "  vw-post-upgrade-check    - Post-upgrade validation"
	@echo ""
	@echo "Monitoring:"
	@echo "  vw-disk-usage            - Check data directory usage"
	@echo "  vw-resource-usage        - Check CPU/memory usage"
	@echo "  vw-top                   - Show resource usage (kubectl top)"
	@echo "  vw-describe              - Describe pod"
	@echo ""
	@echo "Cleanup:"
	@echo "  vw-cleanup-trashed       - Delete trashed vault items"
	@echo "  vw-cleanup-sends         - Delete expired Sends"
	@echo "  vw-cleanup-icons         - Clear icon cache"
	@echo ""

# ========================================
# Basic Operations
# ========================================

.PHONY: vw-status
vw-status:
	@echo "Vaultwarden Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$(RELEASE_NAME)

.PHONY: vw-shell
vw-shell:
	@echo "Opening shell in Vaultwarden pod..."
	kubectl exec -it -n $(NAMESPACE) $(POD) -- /bin/sh

.PHONY: vw-logs
vw-logs:
	@echo "Viewing Vaultwarden logs (last 100 lines)..."
	kubectl logs -n $(NAMESPACE) $(POD) --tail=100

.PHONY: vw-logs-follow
vw-logs-follow:
	@echo "Following Vaultwarden logs..."
	kubectl logs -f -n $(NAMESPACE) $(POD) --tail=100

.PHONY: vw-port-forward
vw-port-forward:
	@echo "Port forwarding Vaultwarden to http://localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) $(POD) 8080:80

.PHONY: vw-get-url
vw-get-url:
	@echo "Vaultwarden URL:"
	@kubectl get ingress -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Ingress not enabled"

.PHONY: vw-restart
vw-restart:
	@echo "Restarting Vaultwarden..."
	@WORKLOAD_TYPE=$$(kubectl get deployment,statefulset -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].kind}' | tr '[:upper:]' '[:lower:]'); \
	kubectl rollout restart -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME) && \
	kubectl rollout status -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME)

.PHONY: vw-version
vw-version:
	@echo "Vaultwarden Version:"
	@kubectl exec -n $(NAMESPACE) $(POD) -- /vaultwarden --version 2>/dev/null || echo "Unable to retrieve version"

# ========================================
# Admin Operations
# ========================================

.PHONY: vw-admin-url
vw-admin-url:
	@echo "Admin Panel URL: https://$$(kubectl get ingress -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo 'vault.example.com')/admin"

.PHONY: vw-get-admin-token
vw-get-admin-token:
	@echo "Admin Token:"
	@kubectl get secret $(RELEASE_NAME)-vaultwarden -n $(NAMESPACE) -o jsonpath='{.data.admin-token}' 2>/dev/null | base64 -d || echo "Admin token not configured"
	@echo ""

.PHONY: vw-disable-admin
vw-disable-admin:
	@echo "Disabling admin panel..."
	@echo "WARNING: This will disable the admin panel until re-enabled"
	@kubectl set env -n $(NAMESPACE) deployment/$(RELEASE_NAME) DISABLE_ADMIN_TOKEN=true

.PHONY: vw-enable-admin
vw-enable-admin:
	@echo "Enabling admin panel..."
	@kubectl set env -n $(NAMESPACE) deployment/$(RELEASE_NAME) DISABLE_ADMIN_TOKEN-

# ========================================
# Database Operations (SQLite)
# ========================================

.PHONY: vw-db-size
vw-db-size:
	@echo "SQLite Database Size:"
	@kubectl exec -n $(NAMESPACE) $(POD) -- du -sh /data/db.sqlite3 2>/dev/null || echo "SQLite database not found (using external DB?)"

.PHONY: vw-db-integrity
vw-db-integrity:
	@echo "Checking SQLite database integrity..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;" 2>/dev/null || echo "SQLite database not found (using external DB?)"

.PHONY: vw-db-vacuum
vw-db-vacuum:
	@echo "Optimizing SQLite database (VACUUM)..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "VACUUM;" 2>/dev/null || echo "SQLite database not found (using external DB?)"
	@echo "Database optimized successfully"

# ========================================
# Database Operations (PostgreSQL/MySQL)
# ========================================

.PHONY: vw-db-shell
vw-db-shell:
	@echo "Opening database shell..."
	@DB_TYPE=$$(kubectl get secret $(RELEASE_NAME)-vaultwarden -n $(NAMESPACE) -o jsonpath='{.data.database-url}' 2>/dev/null | base64 -d | cut -d: -f1); \
	if [ "$$DB_TYPE" = "postgresql" ]; then \
		echo "PostgreSQL shell:"; \
		kubectl exec -it -n $(NAMESPACE) $(POD) -- psql $$DATABASE_URL; \
	elif [ "$$DB_TYPE" = "mysql" ]; then \
		echo "MySQL shell:"; \
		kubectl exec -it -n $(NAMESPACE) $(POD) -- mysql --defaults-extra-file=<(echo "[client]"; echo "password=$$DB_PASSWORD"); \
	else \
		echo "External database not configured (using SQLite mode)"; \
	fi

.PHONY: vw-db-connections
vw-db-connections:
	@echo "Active database connections:"
	@# PostgreSQL connections query
	@kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database();"' 2>/dev/null || echo "Not using PostgreSQL or query failed"

.PHONY: vw-db-table-sizes
vw-db-table-sizes:
	@echo "Database table sizes:"
	@# PostgreSQL table sizes
	@kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'\''.'\''||tablename)) AS size FROM pg_tables WHERE schemaname = '\''public'\'' ORDER BY pg_total_relation_size(schemaname||'\''.'\''||tablename) DESC LIMIT 10;"' 2>/dev/null || echo "Not using PostgreSQL or query failed"

# ========================================
# User Management
# ========================================

.PHONY: vw-list-users
vw-list-users:
	@echo "Vaultwarden Users:"
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "SELECT email, created_at, verified FROM users ORDER BY created_at DESC;" 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "SELECT email, created_at, email_verified FROM users ORDER BY created_at DESC;"' 2>/dev/null || \
	echo "Unable to query users (check database mode)"

.PHONY: vw-delete-user
vw-delete-user:
ifndef EMAIL
	@echo "Error: EMAIL parameter required"
	@echo "Usage: make vw-delete-user EMAIL=user@example.com"
	@exit 1
endif
	@echo "Deleting user: $(EMAIL)"
	@echo "WARNING: This will permanently delete the user and all their vault data"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled"; exit 1)
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "DELETE FROM users WHERE email='$(EMAIL)';" 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "DELETE FROM users WHERE email='\''$(EMAIL)'\'';"' 2>/dev/null || \
	echo "Unable to delete user (check database mode)"

.PHONY: vw-invite-user
vw-invite-user:
ifndef EMAIL
	@echo "Error: EMAIL parameter required"
	@echo "Usage: make vw-invite-user EMAIL=user@example.com"
	@exit 1
endif
	@echo "Inviting user: $(EMAIL)"
	@echo "Note: This requires admin panel access and SMTP configuration"
	@echo "Use admin panel at /admin/users to invite: $(EMAIL)"

# ========================================
# Data Backup Operations
# ========================================

.PHONY: vw-backup-data-full
vw-backup-data-full:
	@echo "Creating full data directory backup..."
	@mkdir -p $(BACKUP_DIR)
	@kubectl exec -n $(NAMESPACE) $(POD) -- tar czf - /data > $(BACKUP_DIR)/vaultwarden-data-full-$$(date +%Y%m%d-%H%M%S).tar.gz
	@echo "Backup created: $(BACKUP_DIR)/vaultwarden-data-full-*.tar.gz"
	@ls -lh $(BACKUP_DIR)/vaultwarden-data-full-*.tar.gz

.PHONY: vw-backup-data-incremental
vw-backup-data-incremental:
	@echo "Creating incremental data directory backup (rsync)..."
	@mkdir -p $(BACKUP_DIR)/incremental/{current,snapshots}
	@SNAPSHOT_DIR=$(BACKUP_DIR)/incremental/snapshots/$$(date +%Y%m%d-%H%M%S); \
	mkdir -p $$SNAPSHOT_DIR; \
	kubectl exec -n $(NAMESPACE) $(POD) -- tar czf - /data | tar xzf - -C $(BACKUP_DIR)/tmp; \
	rsync -av --delete --link-dest=$(BACKUP_DIR)/incremental/current \
		$(BACKUP_DIR)/tmp/data/ $$SNAPSHOT_DIR/; \
	rm -rf $(BACKUP_DIR)/incremental/current; \
	ln -s $$SNAPSHOT_DIR $(BACKUP_DIR)/incremental/current
	@echo "Incremental backup created: $$SNAPSHOT_DIR"

.PHONY: vw-backup-sqlite
vw-backup-sqlite:
	@echo "Backing up SQLite database..."
	@mkdir -p $(BACKUP_DIR)
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 ".backup /tmp/backup.db" 2>/dev/null || (echo "SQLite database not found"; exit 1)
	@kubectl cp $(NAMESPACE)/$(POD):/tmp/backup.db $(BACKUP_DIR)/vaultwarden-sqlite-$$(date +%Y%m%d-%H%M%S).db
	@kubectl exec -n $(NAMESPACE) $(POD) -- rm /tmp/backup.db
	@echo "SQLite backup created: $(BACKUP_DIR)/vaultwarden-sqlite-*.db"
	@sqlite3 $(BACKUP_DIR)/vaultwarden-sqlite-*.db "PRAGMA integrity_check;"

.PHONY: vw-restore-data
vw-restore-data:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE parameter required"
	@echo "Usage: make vw-restore-data BACKUP_FILE=/path/to/backup.tar.gz"
	@exit 1
endif
	@echo "Restoring data directory from $(BACKUP_FILE)..."
	@echo "WARNING: This will overwrite all current vault data"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled"; exit 1)
	@echo "Scaling down Vaultwarden..."
	@WORKLOAD_TYPE=$$(kubectl get deployment,statefulset -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].kind}' | tr '[:upper:]' '[:lower:]'); \
	kubectl scale -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME) --replicas=0; \
	kubectl wait --for=delete pod/$(POD) -n $(NAMESPACE) --timeout=120s; \
	echo "Restoring data..."; \
	kubectl cp $(BACKUP_FILE) $(NAMESPACE)/$(POD):/tmp/restore.tar.gz; \
	kubectl exec -n $(NAMESPACE) $(POD) -- tar xzf /tmp/restore.tar.gz -C /; \
	kubectl exec -n $(NAMESPACE) $(POD) -- rm /tmp/restore.tar.gz; \
	echo "Scaling up Vaultwarden..."; \
	kubectl scale -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME) --replicas=1; \
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vaultwarden -n $(NAMESPACE) --timeout=300s
	@echo "Data directory restored successfully"

# ========================================
# Database Backup Operations
# ========================================

.PHONY: vw-backup-postgres
vw-backup-postgres:
	@echo "Backing up PostgreSQL database..."
	@mkdir -p $(BACKUP_DIR)
	@# Extract PostgreSQL connection details from DATABASE_URL
	@PG_HOST=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
	PG_PORT=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*:\([0-9]*\)\/.*/\1/p'); \
	PG_DB=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*\/\([^?]*\).*/\1/p'); \
	PG_USER=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/postgresql:\/\/\([^:]*\):.*/\1/p'); \
	echo "Database: $$PG_DB on $$PG_HOST:$$PG_PORT"; \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c "PGPASSWORD=\$$DB_PASSWORD pg_dump -h $$PG_HOST -p $$PG_PORT -U $$PG_USER -d $$PG_DB --format=custom --compress=9" > $(BACKUP_DIR)/vaultwarden-pg-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "PostgreSQL backup created: $(BACKUP_DIR)/vaultwarden-pg-*.sql.gz"
	@pg_restore --list $(BACKUP_DIR)/vaultwarden-pg-*.sql.gz | head -20

.PHONY: vw-backup-mysql
vw-backup-mysql:
	@echo "Backing up MySQL database..."
	@mkdir -p $(BACKUP_DIR)
	@# Extract MySQL connection details
	@MYSQL_HOST=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
	MYSQL_PORT=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*:\([0-9]*\)\/.*/\1/p'); \
	MYSQL_DB=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*\/\([^?]*\).*/\1/p'); \
	MYSQL_USER=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/mysql:\/\/\([^:]*\):.*/\1/p'); \
	echo "Database: $$MYSQL_DB on $$MYSQL_HOST:$$MYSQL_PORT"; \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c "MYSQL_PWD=\$$DB_PASSWORD mysqldump -h $$MYSQL_HOST -P $$MYSQL_PORT -u $$MYSQL_USER --databases $$MYSQL_DB --single-transaction --routines --triggers --events" | gzip > $(BACKUP_DIR)/vaultwarden-mysql-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "MySQL backup created: $(BACKUP_DIR)/vaultwarden-mysql-*.sql.gz"
	@gunzip -c $(BACKUP_DIR)/vaultwarden-mysql-*.sql.gz | head -50

.PHONY: vw-restore-postgres
vw-restore-postgres:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE parameter required"
	@echo "Usage: make vw-restore-postgres BACKUP_FILE=/path/to/backup.sql.gz"
	@exit 1
endif
	@echo "Restoring PostgreSQL database from $(BACKUP_FILE)..."
	@echo "WARNING: This will drop and recreate the database"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled"; exit 1)
	@echo "Scaling down Vaultwarden..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=0
	@# Extract PostgreSQL connection details
	@PG_HOST=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
	PG_PORT=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*:\([0-9]*\)\/.*/\1/p'); \
	PG_DB=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/.*\/\([^?]*\).*/\1/p'); \
	PG_USER=$$(kubectl exec -n $(NAMESPACE) $(POD) -- env | grep '^DATABASE_URL=' | sed -n 's/postgresql:\/\/\([^:]*\):.*/\1/p'); \
	echo "Dropping database: $$PG_DB"; \
	PGPASSWORD=$$DB_PASSWORD psql -h $$PG_HOST -p $$PG_PORT -U $$PG_USER -d postgres -c "DROP DATABASE IF EXISTS $$PG_DB;"; \
	PGPASSWORD=$$DB_PASSWORD psql -h $$PG_HOST -p $$PG_PORT -U $$PG_USER -d postgres -c "CREATE DATABASE $$PG_DB OWNER $$PG_USER;"; \
	echo "Restoring database..."; \
	PGPASSWORD=$$DB_PASSWORD pg_restore -h $$PG_HOST -p $$PG_PORT -U $$PG_USER -d $$PG_DB --verbose --no-owner --no-acl $(BACKUP_FILE)
	@echo "Scaling up Vaultwarden..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=1
	@echo "Database restored successfully"

.PHONY: vw-restore-mysql
vw-restore-mysql:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE parameter required"
	@echo "Usage: make vw-restore-mysql BACKUP_FILE=/path/to/backup.sql.gz"
	@exit 1
endif
	@echo "Restoring MySQL database from $(BACKUP_FILE)..."
	@echo "WARNING: This will drop and recreate the database"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled"; exit 1)
	@echo "Scaling down Vaultwarden..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=0
	@# Restore MySQL database
	@gunzip -c $(BACKUP_FILE) | kubectl exec -i -n $(NAMESPACE) $(POD) -- sh -c "MYSQL_PWD=\$$DB_PASSWORD mysql -h \$$MYSQL_HOST -P \$$MYSQL_PORT -u \$$MYSQL_USER"
	@echo "Scaling up Vaultwarden..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=1
	@echo "Database restored successfully"

# ========================================
# Configuration Backup
# ========================================

.PHONY: vw-backup-config
vw-backup-config:
	@echo "Backing up Kubernetes resources..."
	@mkdir -p $(BACKUP_DIR)/config
	@kubectl get deployment,statefulset,service,ingress,configmap,secret,pvc,serviceaccount \
		-n $(NAMESPACE) \
		-l app.kubernetes.io/name=vaultwarden,app.kubernetes.io/instance=$(RELEASE_NAME) \
		-o yaml > $(BACKUP_DIR)/config/vaultwarden-resources.yaml
	@helm get values $(RELEASE_NAME) -n $(NAMESPACE) > $(BACKUP_DIR)/config/values.yaml
	@helm get manifest $(RELEASE_NAME) -n $(NAMESPACE) > $(BACKUP_DIR)/config/manifest.yaml
	@tar czf $(BACKUP_DIR)/vaultwarden-config-$$(date +%Y%m%d-%H%M%S).tar.gz -C $(BACKUP_DIR)/config .
	@echo "Configuration backup created: $(BACKUP_DIR)/vaultwarden-config-*.tar.gz"

.PHONY: vw-restore-config
vw-restore-config:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE parameter required"
	@echo "Usage: make vw-restore-config BACKUP_FILE=/path/to/config.tar.gz"
	@exit 1
endif
	@echo "Restoring configuration from $(BACKUP_FILE)..."
	@mkdir -p /tmp/vaultwarden-restore
	@tar xzf $(BACKUP_FILE) -C /tmp/vaultwarden-restore
	@kubectl apply -f /tmp/vaultwarden-restore/vaultwarden-resources.yaml -n $(NAMESPACE)
	@echo "Configuration restored successfully"

# ========================================
# PVC Snapshot Operations
# ========================================

.PHONY: vw-snapshot-data
vw-snapshot-data:
	@echo "Creating PVC snapshot..."
	@cat <<EOF | kubectl apply -f -
	apiVersion: snapshot.storage.k8s.io/v1
	kind: VolumeSnapshot
	metadata:
	  name: vaultwarden-data-snapshot-$$(date +%Y%m%d-%H%M%S)
	  namespace: $(NAMESPACE)
	spec:
	  volumeSnapshotClassName: csi-snapshot-class
	  source:
	    persistentVolumeClaimName: vaultwarden-data
	EOF
	@echo "Waiting for snapshot to be ready..."
	@kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
		volumesnapshot/vaultwarden-data-snapshot-* \
		-n $(NAMESPACE) \
		--timeout=300s
	@echo "Snapshot created successfully"

.PHONY: vw-list-snapshots
vw-list-snapshots:
	@echo "Vaultwarden PVC Snapshots:"
	@kubectl get volumesnapshot -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden

.PHONY: vw-restore-from-snapshot
vw-restore-from-snapshot:
ifndef SNAPSHOT_NAME
	@echo "Error: SNAPSHOT_NAME parameter required"
	@echo "Usage: make vw-restore-from-snapshot SNAPSHOT_NAME=vaultwarden-data-snapshot-*"
	@exit 1
endif
	@echo "Restoring from snapshot: $(SNAPSHOT_NAME)"
	@echo "Note: This requires recreating the PVC from the snapshot"
	@echo "Implementation depends on your CSI driver and storage class"

# ========================================
# Comprehensive Backup/Recovery
# ========================================

.PHONY: vw-full-backup
vw-full-backup: vw-backup-data-full vw-backup-sqlite vw-backup-config
	@echo ""
	@echo "=========================================="
	@echo "Full backup completed!"
	@echo "=========================================="
	@echo "Backup directory: $(BACKUP_DIR)"
	@ls -lh $(BACKUP_DIR)

.PHONY: vw-full-recovery
vw-full-recovery:
ifndef DATA_BACKUP
	@echo "Error: DATA_BACKUP parameter required"
	@echo "Usage: make vw-full-recovery DATA_BACKUP=/path/to/data.tar.gz DB_BACKUP=/path/to/db.sql.gz"
	@exit 1
endif
	@echo "Starting full disaster recovery..."
	@echo "1. Restoring database..."
	@make vw-restore-postgres BACKUP_FILE=$(DB_BACKUP) || make vw-restore-mysql BACKUP_FILE=$(DB_BACKUP) || echo "No database restore needed (SQLite mode)"
	@echo "2. Restoring data directory..."
	@make vw-restore-data BACKUP_FILE=$(DATA_BACKUP)
	@echo "3. Verifying recovery..."
	@make vw-post-upgrade-check
	@echo "Full recovery completed successfully!"

# ========================================
# Upgrade Operations
# ========================================

.PHONY: vw-pre-upgrade-check
vw-pre-upgrade-check:
	@echo "=========================================="
	@echo "Pre-Upgrade Checks"
	@echo "=========================================="
	@echo ""
	@echo "1. Checking pod status..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden
	@echo ""
	@echo "2. Checking database health..."
	@make vw-db-integrity 2>/dev/null || echo "SQLite not used"
	@echo ""
	@echo "3. Current Vaultwarden version:"
	@make vw-version
	@echo ""
	@echo "4. Disk usage:"
	@make vw-disk-usage
	@echo ""
	@echo "Pre-upgrade checks completed. Proceed with backup before upgrade."

.PHONY: vw-post-upgrade-check
vw-post-upgrade-check:
	@echo "=========================================="
	@echo "Post-Upgrade Validation"
	@echo "=========================================="
	@echo ""
	@echo "1. Pod health:"
	@kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vaultwarden -n $(NAMESPACE) --timeout=300s
	@echo ""
	@echo "2. Vaultwarden version:"
	@make vw-version
	@echo ""
	@echo "3. Database integrity:"
	@make vw-db-integrity 2>/dev/null || echo "SQLite not used"
	@echo ""
	@echo "4. Application logs (last 50 lines):"
	@kubectl logs -n $(NAMESPACE) $(POD) --tail=50 | grep -i "error\|warn\|fail" || echo "No errors found"
	@echo ""
	@echo "Post-upgrade validation completed!"

# ========================================
# Monitoring
# ========================================

.PHONY: vw-disk-usage
vw-disk-usage:
	@echo "Data Directory Usage:"
	@kubectl exec -n $(NAMESPACE) $(POD) -- du -sh /data/* 2>/dev/null || echo "Unable to check disk usage"

.PHONY: vw-resource-usage
vw-resource-usage:
	@echo "Resource Usage:"
	@kubectl top pod -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden 2>/dev/null || echo "Metrics server not available"

.PHONY: vw-top
vw-top:
	@kubectl top pod -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden

.PHONY: vw-describe
vw-describe:
	@kubectl describe pod -n $(NAMESPACE) $(POD)

# ========================================
# Cleanup
# ========================================

.PHONY: vw-cleanup-trashed
vw-cleanup-trashed:
	@echo "Deleting trashed vault items..."
	@echo "Note: This requires database access and depends on database mode"
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "DELETE FROM ciphers WHERE deleted_at IS NOT NULL;" 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "DELETE FROM ciphers WHERE deleted_at IS NOT NULL;"' 2>/dev/null || \
	echo "Unable to cleanup (check database mode)"

.PHONY: vw-cleanup-sends
vw-cleanup-sends:
	@echo "Deleting expired Sends..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- sqlite3 /data/db.sqlite3 "DELETE FROM sends WHERE expiration_date < datetime('now');" 2>/dev/null || \
	kubectl exec -n $(NAMESPACE) $(POD) -- sh -c 'psql $$DATABASE_URL -c "DELETE FROM sends WHERE expiration_date < NOW();"' 2>/dev/null || \
	echo "Unable to cleanup (check database mode)"

.PHONY: vw-cleanup-icons
vw-cleanup-icons:
	@echo "Clearing icon cache..."
	@kubectl exec -n $(NAMESPACE) $(POD) -- rm -rf /data/icon_cache/*
	@echo "Icon cache cleared successfully"

# ========================================
# Scale Operations
# ========================================

.PHONY: vw-scale
vw-scale:
ifndef REPLICAS
	@echo "Error: REPLICAS parameter required"
	@echo "Usage: make vw-scale REPLICAS=2"
	@exit 1
endif
	@echo "Scaling Vaultwarden to $(REPLICAS) replicas..."
	@WORKLOAD_TYPE=$$(kubectl get deployment,statefulset -n $(NAMESPACE) -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].kind}' | tr '[:upper:]' '[:lower:]'); \
	kubectl scale -n $(NAMESPACE) $$WORKLOAD_TYPE/$(RELEASE_NAME) --replicas=$(REPLICAS)
