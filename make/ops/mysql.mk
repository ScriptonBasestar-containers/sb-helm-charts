# MySQL Chart Operations
# Operational commands for MySQL Helm chart management

include Makefile.common.mk

CHART_NAME := mysql
CHART_DIR := charts/mysql
NAMESPACE ?= default
RELEASE_NAME ?= mysql

# Default pod selection
POD ?= $(RELEASE_NAME)-0

################################################################################
# Help
################################################################################

.PHONY: help
help::
	@echo ""
	@echo "MySQL Operations:"
	@echo "  mysql-shell              - Open shell in MySQL pod"
	@echo "  mysql-logs               - View MySQL logs"
	@echo "  mysql-port-forward       - Port forward to localhost:3306"
	@echo ""
	@echo "Database Operations:"
	@echo "  mysql-backup             - Backup all databases to tmp/mysql-backups/"
	@echo "  mysql-restore FILE=...   - Restore from backup file"
	@echo "  mysql-create-db DB=...   - Create new database"
	@echo "  mysql-list-dbs           - List all databases"
	@echo "  mysql-db-size            - Show database sizes"
	@echo ""
	@echo "User Management:"
	@echo "  mysql-create-user USER=... PASSWORD=... - Create new user"
	@echo "  mysql-grant-privileges USER=... DB=...  - Grant all privileges on database"
	@echo "  mysql-list-users         - List all users"
	@echo "  mysql-show-grants USER=... - Show user privileges"
	@echo ""
	@echo "Replication (Master-Replica):"
	@echo "  mysql-replication-info   - Get replication status for all pods"
	@echo "  mysql-master-status      - Get master status (binary log position)"
	@echo "  mysql-replica-status     - Get replica status (lag, position)"
	@echo "  mysql-replica-lag        - Check replication lag"
	@echo ""
	@echo "Performance & Monitoring:"
	@echo "  mysql-status             - Show server status"
	@echo "  mysql-processlist        - Show running processes"
	@echo "  mysql-variables          - Show server variables"
	@echo "  mysql-innodb-status      - Show InnoDB engine status"
	@echo "  mysql-slow-queries       - Show slow query log"
	@echo ""
	@echo "Maintenance:"
	@echo "  mysql-optimize DB=...    - Optimize all tables in database"
	@echo "  mysql-check DB=...       - Check all tables in database"
	@echo "  mysql-repair DB=...      - Repair all tables in database"
	@echo "  mysql-analyze DB=...     - Analyze all tables in database"
	@echo ""
	@echo "CLI & Debug:"
	@echo "  mysql-cli CMD='...'      - Run mysql command"
	@echo "  mysql-admin CMD='...'    - Run mysqladmin command"
	@echo "  mysql-ping               - Ping MySQL server"
	@echo "  mysql-version            - Show MySQL version"
	@echo "  mysql-restart            - Restart MySQL deployment"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)   - Kubernetes namespace"
	@echo "  RELEASE_NAME=$(RELEASE_NAME) - Helm release name"
	@echo "  POD=$(POD)               - Pod name for operations"

################################################################################
# Basic Operations
################################################################################

.PHONY: mysql-shell
mysql-shell:
	@echo "Opening shell in MySQL pod: $(POD)"
	kubectl exec -it $(POD) -n $(NAMESPACE) -- bash

.PHONY: mysql-logs
mysql-logs:
	@echo "Viewing logs for MySQL pod: $(POD)"
	kubectl logs -f $(POD) -n $(NAMESPACE)

.PHONY: mysql-port-forward
mysql-port-forward:
	@echo "Port forwarding MySQL to localhost:3306"
	@echo "Connect with: mysql -h 127.0.0.1 -u root -p"
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 3306:3306

################################################################################
# Database Operations
################################################################################

.PHONY: mysql-backup
mysql-backup:
	@echo "Backing up all MySQL databases..."
	@mkdir -p tmp/mysql-backups
	@BACKUP_FILE="tmp/mysql-backups/mysql-backup-$$(date +%Y%m%d-%H%M%S).sql.gz"; \
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqldump -uroot -p\$$MYSQL_ROOT_PASSWORD --all-databases --single-transaction --quick --lock-tables=false" \
		| gzip > $$BACKUP_FILE && \
	echo "Backup saved to: $$BACKUP_FILE"

.PHONY: mysql-restore
mysql-restore:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make mysql-restore FILE=path/to/backup.sql.gz"
	@exit 1
endif
	@echo "Restoring MySQL from: $(FILE)"
	@if [[ "$(FILE)" == *.gz ]]; then \
		gunzip -c $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD; \
	else \
		kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD < $(FILE); \
	fi
	@echo "Restore completed"

.PHONY: mysql-create-db
mysql-create-db:
ifndef DB
	@echo "Error: DB variable required. Usage: make mysql-create-db DB=mydb"
	@exit 1
endif
	@echo "Creating database: $(DB)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'CREATE DATABASE IF NOT EXISTS $(DB);'"

.PHONY: mysql-list-dbs
mysql-list-dbs:
	@echo "Listing all databases..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW DATABASES;'"

.PHONY: mysql-db-size
mysql-db-size:
	@echo "Database sizes..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SELECT table_schema AS Database_Name, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS Size_MB FROM information_schema.TABLES GROUP BY table_schema ORDER BY Size_MB DESC;'"

################################################################################
# User Management
################################################################################

.PHONY: mysql-create-user
mysql-create-user:
ifndef USER
	@echo "Error: USER and PASSWORD variables required."
	@echo "Usage: make mysql-create-user USER=myuser PASSWORD=mypass"
	@exit 1
endif
ifndef PASSWORD
	@echo "Error: PASSWORD variable required."
	@exit 1
endif
	@echo "Creating user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"CREATE USER IF NOT EXISTS '$(USER)'@'%' IDENTIFIED BY '$(PASSWORD)';\""

.PHONY: mysql-grant-privileges
mysql-grant-privileges:
ifndef USER
	@echo "Error: USER and DB variables required."
	@echo "Usage: make mysql-grant-privileges USER=myuser DB=mydb"
	@exit 1
endif
ifndef DB
	@echo "Error: DB variable required."
	@exit 1
endif
	@echo "Granting privileges to $(USER) on $(DB)..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"GRANT ALL PRIVILEGES ON $(DB).* TO '$(USER)'@'%'; FLUSH PRIVILEGES;\""

.PHONY: mysql-list-users
mysql-list-users:
	@echo "Listing all users..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SELECT user, host FROM mysql.user;'"

.PHONY: mysql-show-grants
mysql-show-grants:
ifndef USER
	@echo "Error: USER variable required. Usage: make mysql-show-grants USER=myuser"
	@exit 1
endif
	@echo "Showing grants for user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SHOW GRANTS FOR '$(USER)'@'%';\""

################################################################################
# Replication
################################################################################

.PHONY: mysql-replication-info
mysql-replication-info:
	@echo "Checking replication status for all MySQL pods..."
	@for pod in $$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=mysql -o name | cut -d'/' -f2); do \
		echo ""; \
		echo "=== Pod: $$pod ==="; \
		kubectl exec $$pod -n $(NAMESPACE) -- bash -c \
			"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW SLAVE STATUS\G' 2>/dev/null || echo 'Not configured as replica'"; \
	done

.PHONY: mysql-master-status
mysql-master-status:
	@echo "Getting master status from: $(POD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW MASTER STATUS;'"

.PHONY: mysql-replica-status
mysql-replica-status:
	@echo "Getting replica status from: $(POD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW SLAVE STATUS\G'"

.PHONY: mysql-replica-lag
mysql-replica-lag:
	@echo "Checking replication lag for all replicas..."
	@for pod in $$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=mysql -o name | cut -d'/' -f2 | grep -v '\-0$$'); do \
		echo ""; \
		echo "=== Replica: $$pod ==="; \
		kubectl exec $$pod -n $(NAMESPACE) -- bash -c \
			"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT CASE WHEN Seconds_Behind_Master IS NULL THEN 'Not Replicating' ELSE CONCAT(Seconds_Behind_Master, ' seconds') END AS Replication_Lag FROM (SHOW SLAVE STATUS) AS status;\"" 2>/dev/null || echo "Error checking lag"; \
	done

################################################################################
# Performance & Monitoring
################################################################################

.PHONY: mysql-status
mysql-status:
	@echo "Getting MySQL server status..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW STATUS;'"

.PHONY: mysql-processlist
mysql-processlist:
	@echo "Showing running processes..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW FULL PROCESSLIST;'"

.PHONY: mysql-variables
mysql-variables:
	@echo "Showing server variables..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW VARIABLES;'"

.PHONY: mysql-innodb-status
mysql-innodb-status:
	@echo "Showing InnoDB engine status..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW ENGINE INNODB STATUS\G'"

.PHONY: mysql-slow-queries
mysql-slow-queries:
	@echo "Showing slow query log from: $(POD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"cat /var/log/mysql/slow.log 2>/dev/null || echo 'Slow query log not found or not enabled'"

################################################################################
# Maintenance
################################################################################

.PHONY: mysql-optimize
mysql-optimize:
ifndef DB
	@echo "Error: DB variable required. Usage: make mysql-optimize DB=mydb"
	@exit 1
endif
	@echo "Optimizing all tables in database: $(DB)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqlcheck -uroot -p\$$MYSQL_ROOT_PASSWORD --optimize $(DB)"

.PHONY: mysql-check
mysql-check:
ifndef DB
	@echo "Error: DB variable required. Usage: make mysql-check DB=mydb"
	@exit 1
endif
	@echo "Checking all tables in database: $(DB)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqlcheck -uroot -p\$$MYSQL_ROOT_PASSWORD --check $(DB)"

.PHONY: mysql-repair
mysql-repair:
ifndef DB
	@echo "Error: DB variable required. Usage: make mysql-repair DB=mydb"
	@exit 1
endif
	@echo "Repairing all tables in database: $(DB)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqlcheck -uroot -p\$$MYSQL_ROOT_PASSWORD --repair $(DB)"

.PHONY: mysql-analyze
mysql-analyze:
ifndef DB
	@echo "Error: DB variable required. Usage: make mysql-analyze DB=mydb"
	@exit 1
endif
	@echo "Analyzing all tables in database: $(DB)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqlcheck -uroot -p\$$MYSQL_ROOT_PASSWORD --analyze $(DB)"

################################################################################
# CLI & Debug
################################################################################

.PHONY: mysql-cli
mysql-cli:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make mysql-cli CMD='SELECT VERSION();'"
	@exit 1
endif
	@echo "Running MySQL command: $(CMD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e '$(CMD)'"

.PHONY: mysql-admin
mysql-admin:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make mysql-admin CMD=ping"
	@exit 1
endif
	@echo "Running mysqladmin command: $(CMD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqladmin -uroot -p\$$MYSQL_ROOT_PASSWORD $(CMD)"

.PHONY: mysql-ping
mysql-ping:
	@echo "Pinging MySQL server..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqladmin -uroot -p\$$MYSQL_ROOT_PASSWORD ping"

.PHONY: mysql-version
mysql-version:
	@echo "Getting MySQL version..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SELECT VERSION();'"

################################################################################
# Enhanced Backup & Recovery Operations
################################################################################

.PHONY: mysql-backup-all
mysql-backup-all:
	@echo "Backing up all MySQL databases with binary log position..."
	@mkdir -p tmp/mysql-backups
	@BACKUP_FILE="tmp/mysql-backups/mysql-all-$$(date +%Y%m%d-%H%M%S).sql.gz"; \
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqldump -uroot -p\$$MYSQL_ROOT_PASSWORD \
			--all-databases \
			--single-transaction \
			--master-data=2 \
			--flush-logs \
			--routines \
			--triggers \
			--events \
			--quick" | gzip > $$BACKUP_FILE && \
	echo "Backup saved to: $$BACKUP_FILE"

.PHONY: mysql-backup-single
mysql-backup-single:
ifndef DATABASE
	@echo "Error: DATABASE variable required. Usage: make mysql-backup-single DATABASE=myapp"
	@exit 1
endif
	@echo "Backing up database: $(DATABASE)"
	@mkdir -p tmp/mysql-backups
	@BACKUP_FILE="tmp/mysql-backups/$(DATABASE)-$$(date +%Y%m%d-%H%M%S).sql.gz"; \
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqldump -uroot -p\$$MYSQL_ROOT_PASSWORD \
			--single-transaction \
			--routines \
			--triggers \
			--events \
			$(DATABASE)" | gzip > $$BACKUP_FILE && \
	echo "Backup saved to: $$BACKUP_FILE"

.PHONY: mysql-backup-config
mysql-backup-config:
	@echo "Backing up MySQL configuration..."
	@mkdir -p tmp/mysql-backups
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-config -o yaml > tmp/mysql-backups/configmap-$$(date +%Y%m%d-%H%M%S).yaml 2>/dev/null || echo "No ConfigMap found"
	@kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME)-secret -o yaml > tmp/mysql-backups/secret-$$(date +%Y%m%d-%H%M%S).yaml 2>/dev/null || echo "No Secret found"
	@echo "Configuration backups saved to tmp/mysql-backups/"

.PHONY: mysql-show-binlogs
mysql-show-binlogs:
	@echo "Listing binary logs..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW BINARY LOGS;'"

.PHONY: mysql-flush-logs
mysql-flush-logs:
	@echo "Flushing and rotating binary logs..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'FLUSH LOGS;'"

.PHONY: mysql-archive-binlogs
mysql-archive-binlogs:
	@echo "Archiving binary logs to tmp/mysql-backups/binlogs/"
	@mkdir -p tmp/mysql-backups/binlogs
	@echo "Note: This is a placeholder. Implement S3/MinIO archiving for production."
	@echo "See docs/mysql-backup-guide.md for detailed archiving procedures."

.PHONY: mysql-purge-binlogs
mysql-purge-binlogs:
ifndef BEFORE
	@echo "Error: BEFORE variable required."
	@echo "Usage: make mysql-purge-binlogs BEFORE='2025-01-01'"
	@exit 1
endif
	@echo "⚠️  WARNING: This will permanently delete binary logs before $(BEFORE)"
	@echo "Purging binary logs before: $(BEFORE)"
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"PURGE BINARY LOGS BEFORE '$(BEFORE)';\""

.PHONY: mysql-backup-pvc-snapshot
mysql-backup-pvc-snapshot:
	@echo "Creating PVC snapshot for MySQL data..."
	@echo "⚠️  WARNING: Requires VolumeSnapshot API and snapshot class configured"
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=mysql -o name | while read pvc; do \
		pvc_name=$$(echo $$pvc | cut -d'/' -f2); \
		snapshot_name="$$pvc_name-snapshot-$$(date +%Y%m%d-%H%M%S)"; \
		cat <<EOF | kubectl apply -f - ; \
apiVersion: snapshot.storage.k8s.io/v1 ; \
kind: VolumeSnapshot ; \
metadata: ; \
  name: $$snapshot_name ; \
  namespace: $(NAMESPACE) ; \
spec: ; \
  volumeSnapshotClassName: csi-hostpath-snapclass ; \
  source: ; \
    persistentVolumeClaimName: $$pvc_name ; \
EOF \
		echo "Created snapshot: $$snapshot_name"; \
	done

.PHONY: mysql-backup-verify
mysql-backup-verify:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make mysql-backup-verify FILE=path/to/backup.sql.gz"
	@exit 1
endif
	@echo "Verifying backup file: $(FILE)"
	@if [[ "$(FILE)" == *.gz ]]; then \
		echo "Compressed SQL backup - checking first 50 lines:"; \
		zcat $(FILE) | head -n 50; \
	else \
		echo "SQL backup - checking first 50 lines:"; \
		head -n 50 $(FILE); \
	fi

.PHONY: mysql-restore-all
mysql-restore-all:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make mysql-restore-all FILE=path/to/backup.sql.gz"
	@exit 1
endif
	@echo "⚠️  WARNING: This will restore all databases"
	@echo "Restoring all databases from: $(FILE)"
	@if [[ "$(FILE)" == *.gz ]]; then \
		zcat $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD; \
	else \
		kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD < $(FILE); \
	fi
	@echo "Restore completed"

.PHONY: mysql-restore-single
mysql-restore-single:
ifndef DATABASE
	@echo "Error: DATABASE and FILE variables required."
	@echo "Usage: make mysql-restore-single DATABASE=myapp FILE=path/to/backup.sql.gz"
	@exit 1
endif
ifndef FILE
	@echo "Error: FILE variable required."
	@exit 1
endif
	@echo "Restoring database $(DATABASE) from: $(FILE)"
	@if [[ "$(FILE)" == *.gz ]]; then \
		zcat $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD $(DATABASE); \
	else \
		kubectl exec -i $(POD) -n $(NAMESPACE) -- \
			mysql -uroot -p$$MYSQL_ROOT_PASSWORD $(DATABASE) < $(FILE); \
	fi
	@echo "Restore completed"

.PHONY: mysql-pitr
mysql-pitr:
ifndef RECOVERY_TIME
	@echo "Error: RECOVERY_TIME variable required."
	@echo "Usage: make mysql-pitr RECOVERY_TIME='2025-01-15 14:30:00'"
	@exit 1
endif
	@echo "⚠️  Point-in-Time Recovery (PITR) requires:"
	@echo "  1. Base backup (full backup)"
	@echo "  2. Binary logs with all transactions"
	@echo "  3. Recovery target time: $(RECOVERY_TIME)"
	@echo ""
	@echo "Manual steps required:"
	@echo "  1. Restore base backup"
	@echo "  2. Apply binary logs up to recovery time"
	@echo "  3. Verify data integrity"
	@echo ""
	@echo "See docs/mysql-backup-guide.md for detailed PITR procedures"

################################################################################
# Upgrade Operations
################################################################################

.PHONY: mysql-pre-upgrade-check
mysql-pre-upgrade-check:
	@echo "Running pre-upgrade checks..."
	@echo ""
	@echo "1. MySQL Version:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SELECT VERSION();'"
	@echo ""
	@echo "2. Database Sizes:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.TABLES GROUP BY table_schema ORDER BY Size_MB DESC;\""
	@echo ""
	@echo "3. Active Connections:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT COUNT(*) AS active_connections FROM information_schema.processlist WHERE command != 'Sleep';\""
	@echo ""
	@echo "4. Replication Status:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW SLAVE STATUS\G' 2>/dev/null || echo 'No replication configured'"
	@echo ""
	@echo "5. Binary Log Status:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW BINARY LOGS;' 2>/dev/null || echo 'Binary logging not enabled'"
	@echo ""
	@echo "✅ Pre-upgrade checks completed. Review output before proceeding."
	@echo "📝 Recommendation: Create backup with: make mysql-backup-all"

.PHONY: mysql-post-upgrade-check
mysql-post-upgrade-check:
	@echo "Running post-upgrade validation..."
	@echo ""
	@echo "1. MySQL Version (should be upgraded):"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SELECT VERSION();'"
	@echo ""
	@echo "2. Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=mysql
	@echo ""
	@echo "3. Database Accessibility:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW DATABASES;'"
	@echo ""
	@echo "4. Replication Status:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW SLAVE STATUS\G' 2>/dev/null || echo 'No replication configured'"
	@echo ""
	@echo "5. Connection Test:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqladmin -uroot -p\$$MYSQL_ROOT_PASSWORD ping"
	@echo ""
	@echo "✅ Post-upgrade validation completed."
	@echo "📝 Next step: Run ANALYZE with: make mysql-analyze-tables"

.PHONY: mysql-analyze-tables
mysql-analyze-tables:
	@echo "Analyzing all tables in all databases..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysqlcheck -uroot -p\$$MYSQL_ROOT_PASSWORD --all-databases --analyze"

.PHONY: mysql-connections
mysql-connections:
	@echo "Getting active connections..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT user, host, db, command, time, state FROM information_schema.processlist WHERE command != 'Sleep' ORDER BY time DESC;\""

.PHONY: mysql-database-size
mysql-database-size:
	@echo "Getting database sizes..."
	kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB' FROM information_schema.TABLES GROUP BY table_schema ORDER BY Size_MB DESC;\""

.PHONY: mysql-replication-status
mysql-replication-status:
	@echo "Getting comprehensive replication status..."
	@echo ""
	@echo "=== Master Status ==="
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW MASTER STATUS;'" 2>/dev/null || echo "Not a master or binary logging disabled"
	@echo ""
	@echo "=== Replica Status ==="
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'SHOW SLAVE STATUS\G'" 2>/dev/null || echo "Not a replica"

.PHONY: mysql-replication-lag
mysql-replication-lag:
	@echo "Checking replication lag..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e \"SELECT CASE WHEN Seconds_Behind_Master IS NULL THEN 'Not Replicating' WHEN Seconds_Behind_Master = 0 THEN 'No Lag (Up to date)' ELSE CONCAT(Seconds_Behind_Master, ' seconds behind') END AS Replication_Status FROM (SHOW SLAVE STATUS) AS status;\" 2>/dev/null" || echo "No replication configured"

.PHONY: mysql-promote-replica
mysql-promote-replica:
ifndef POD
	@echo "Error: POD variable required. Usage: make mysql-promote-replica POD=mysql-1"
	@exit 1
endif
	@echo "⚠️  Promoting replica $(POD) to master..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- bash -c \
		"mysql -uroot -p\$$MYSQL_ROOT_PASSWORD -e 'STOP SLAVE; RESET SLAVE ALL;'"
	@echo "Replica promoted. Verify with: make mysql-replication-status POD=$(POD)"

.PHONY: mysql-restart
mysql-restart:
	@echo "Restarting MySQL StatefulSet..."
	kubectl rollout restart statefulset/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(RELEASE_NAME) -n $(NAMESPACE)
