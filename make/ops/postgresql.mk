# postgresql chart configuration
CHART_NAME := postgresql
CHART_DIR := charts/$(CHART_NAME)

# PostgreSQL credentials (fetched from secret)
POSTGRES_PASSWORD ?= $(shell $(KUBECTL) get secret $(CHART_NAME)-secret -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
POSTGRES_USER ?= postgres
POSTGRES_DB ?= postgres

# Common Makefile
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# PostgreSQL-specific targets

# === Connection and Shell ===

.PHONY: pg-shell
pg-shell:
	@echo "Opening psql shell..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)'

.PHONY: pg-bash
pg-bash:
	@echo "Opening bash shell..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- bash

.PHONY: pg-logs
pg-logs:
	@echo "Viewing PostgreSQL logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: pg-logs-all
pg-logs-all:
	@echo "Viewing logs from all PostgreSQL pods..."
	@$(KUBECTL) logs -l app.kubernetes.io/name=$(CHART_NAME) --all-containers=true --prefix=true

# === Connection Test ===

.PHONY: pg-ping
pg-ping:
	@echo "Testing PostgreSQL connection..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		pg_isready -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: pg-version
pg-version:
	@echo "Getting PostgreSQL version..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT version();"'

# === Database Management ===

.PHONY: pg-list-databases
pg-list-databases:
	@echo "Listing all databases..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "\l"'

.PHONY: pg-list-tables
pg-list-tables:
	@echo "Listing all tables in database $(POSTGRES_DB)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "\dt"'

.PHONY: pg-list-users
pg-list-users:
	@echo "Listing all users..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "\du"'

.PHONY: pg-database-size
pg-database-size:
	@echo "Getting database size for $(POSTGRES_DB)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pg_size_pretty(pg_database_size('"'"'$(POSTGRES_DB)'"'"'));"'

.PHONY: pg-all-databases-size
pg-all-databases-size:
	@echo "Getting size of all databases..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"'

# === Statistics and Monitoring ===

.PHONY: pg-stats
pg-stats:
	@echo "Getting PostgreSQL statistics..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_stat_database WHERE datname = '"'"'$(POSTGRES_DB)'"'"';"'

.PHONY: pg-activity
pg-activity:
	@echo "Getting active connections and queries..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pid, usename, application_name, client_addr, state, query FROM pg_stat_activity WHERE state != '"'"'idle'"'"';"'

.PHONY: pg-connections
pg-connections:
	@echo "Getting connection count..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT count(*) as connections, state FROM pg_stat_activity GROUP BY state;"'

.PHONY: pg-locks
pg-locks:
	@echo "Getting current locks..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_locks WHERE NOT granted;"'

.PHONY: pg-slow-queries
pg-slow-queries:
	@echo "Getting slow queries (requires pg_stat_statements)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT query, calls, total_exec_time, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;" 2>/dev/null || echo "pg_stat_statements extension not enabled"'

# === Replication Management ===

.PHONY: pg-replication-status
pg-replication-status:
	@echo "Getting replication status from master..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "Not a replication master or no replicas connected"'

.PHONY: pg-replication-lag
pg-replication-lag:
	@echo "Getting replication lag..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME),role=master -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state, CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT END AS lag_seconds FROM pg_stat_replication;" 2>/dev/null || echo "No replication info available"'

.PHONY: pg-recovery-status
pg-recovery-status:
	@echo "Getting recovery status (for replicas)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[1].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pg_is_in_recovery();" 2>/dev/null || echo "Only one pod running or pod index 1 not found"'

.PHONY: pg-wal-status
pg-wal-status:
	@echo "Getting WAL status..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_stat_wal;" 2>/dev/null || echo "pg_stat_wal not available (PostgreSQL 14+)"'

# === Backup and Restore ===

.PHONY: pg-backup
pg-backup:
	@echo "Creating backup of database $(POSTGRES_DB)..."
	@mkdir -p tmp/postgresql-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dump -U $(POSTGRES_USER) $(POSTGRES_DB)' > tmp/postgresql-backups/$(POSTGRES_DB)-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "Backup saved to tmp/postgresql-backups/$(POSTGRES_DB)-$(shell date +%Y%m%d-%H%M%S).sql"

.PHONY: pg-backup-all
pg-backup-all:
	@echo "Creating backup of all databases..."
	@mkdir -p tmp/postgresql-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dumpall -U $(POSTGRES_USER)' > tmp/postgresql-backups/all-databases-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "Backup saved to tmp/postgresql-backups/all-databases-$(shell date +%Y%m%d-%H%M%S).sql"

.PHONY: pg-restore
pg-restore:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-restore FILE=path/to/backup.sql"; exit 1; fi
	@echo "Restoring backup from $(FILE)..."
	@cat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) $(POSTGRES_DB)'
	@echo "Restore completed"

# === Maintenance ===

.PHONY: pg-vacuum
pg-vacuum:
	@echo "Running VACUUM on database $(POSTGRES_DB)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "VACUUM VERBOSE;"'

.PHONY: pg-vacuum-analyze
pg-vacuum-analyze:
	@echo "Running VACUUM ANALYZE on database $(POSTGRES_DB)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "VACUUM ANALYZE VERBOSE;"'

.PHONY: pg-vacuum-full
pg-vacuum-full:
	@echo "Running VACUUM FULL on database $(POSTGRES_DB) (WARNING: locks tables)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "VACUUM FULL VERBOSE;"'

.PHONY: pg-analyze
pg-analyze:
	@echo "Running ANALYZE on database $(POSTGRES_DB)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "ANALYZE VERBOSE;"'

.PHONY: pg-reindex
pg-reindex:
	@if [ -z "$(TABLE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-reindex TABLE=table_name"; exit 1; fi
	@echo "Reindexing table $(TABLE)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "REINDEX TABLE $(TABLE);"'

# === Configuration ===

.PHONY: pg-config
pg-config:
	@echo "Getting PostgreSQL configuration..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SHOW ALL;"'

.PHONY: pg-config-get
pg-config-get:
	@if [ -z "$(PARAM)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-config-get PARAM=max_connections"; exit 1; fi
	@echo "Getting configuration parameter $(PARAM)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SHOW $(PARAM);"'

.PHONY: pg-reload
pg-reload:
	@echo "Reloading PostgreSQL configuration..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pg_reload_conf();"'

# === Utilities ===

.PHONY: pg-port-forward
pg-port-forward:
	@echo "Port-forwarding PostgreSQL to localhost:5432..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME) 5432:5432

.PHONY: pg-restart
pg-restart:
	@echo "Restarting PostgreSQL StatefulSet..."
	@$(KUBECTL) rollout restart statefulset/$(CHART_NAME)
	@$(KUBECTL) rollout status statefulset/$(CHART_NAME)

.PHONY: pg-scale
pg-scale:
	@if [ -z "$(REPLICAS)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-scale REPLICAS=2"; exit 1; fi
	@echo "Scaling PostgreSQL to $(REPLICAS) replicas..."
	@$(KUBECTL) scale statefulset/$(CHART_NAME) --replicas=$(REPLICAS)
	@$(KUBECTL) rollout status statefulset/$(CHART_NAME)

.PHONY: pg-get-password
pg-get-password:
	@echo "PostgreSQL password:"
	@$(KUBECTL) get secret $(CHART_NAME)-secret -o jsonpath='{.data.postgres-password}' | base64 -d
	@echo ""

.PHONY: pg-get-replication-password
pg-get-replication-password:
	@echo "Replication password:"
	@$(KUBECTL) get secret $(CHART_NAME)-secret -o jsonpath='{.data.replication-password}' | base64 -d 2>/dev/null || echo "Replication password not set"
	@echo ""

# === Help ===

.PHONY: help
help:
	@echo "PostgreSQL Chart Operations:"
	@echo ""
	@echo "Connection:"
	@echo "  pg-shell                    - Open psql shell"
	@echo "  pg-bash                     - Open bash shell"
	@echo "  pg-logs                     - View logs from first pod"
	@echo "  pg-logs-all                 - View logs from all pods"
	@echo "  pg-ping                     - Test connection"
	@echo "  pg-version                  - Get PostgreSQL version"
	@echo ""
	@echo "Database Management:"
	@echo "  pg-list-databases           - List all databases"
	@echo "  pg-list-tables              - List all tables"
	@echo "  pg-list-users               - List all users"
	@echo "  pg-database-size            - Get database size"
	@echo "  pg-all-databases-size       - Get all databases size"
	@echo ""
	@echo "Monitoring:"
	@echo "  pg-stats                    - Get database statistics"
	@echo "  pg-activity                 - Get active connections"
	@echo "  pg-connections              - Get connection count"
	@echo "  pg-locks                    - Get current locks"
	@echo "  pg-slow-queries             - Get slow queries"
	@echo ""
	@echo "Replication:"
	@echo "  pg-replication-status       - Get replication status"
	@echo "  pg-replication-lag          - Get replication lag"
	@echo "  pg-recovery-status          - Get recovery status"
	@echo "  pg-wal-status               - Get WAL status"
	@echo ""
	@echo "Backup/Restore:"
	@echo "  pg-backup                   - Backup database"
	@echo "  pg-backup-all               - Backup all databases"
	@echo "  pg-restore FILE=<file>      - Restore from backup"
	@echo ""
	@echo "Maintenance:"
	@echo "  pg-vacuum                   - Run VACUUM"
	@echo "  pg-vacuum-analyze           - Run VACUUM ANALYZE"
	@echo "  pg-vacuum-full              - Run VACUUM FULL"
	@echo "  pg-analyze                  - Run ANALYZE"
	@echo "  pg-reindex TABLE=<table>    - Reindex table"
	@echo ""
	@echo "Configuration:"
	@echo "  pg-config                   - Show all config"
	@echo "  pg-config-get PARAM=<param> - Get specific config"
	@echo "  pg-reload                   - Reload configuration"
	@echo ""
	@echo "Utilities:"
	@echo "  pg-port-forward             - Port forward to localhost:5432"
	@echo "  pg-restart                  - Restart StatefulSet"
	@echo "  pg-scale REPLICAS=<n>       - Scale replicas"
	@echo "  pg-get-password             - Get postgres password"
	@echo "  pg-get-replication-password - Get replication password"
