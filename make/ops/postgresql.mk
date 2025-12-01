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
	@if [ -z "$(DATABASE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-backup DATABASE=myapp"; exit 1; fi
	@echo "Creating backup of database $(DATABASE)..."
	@mkdir -p tmp/postgresql-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dump -U $(POSTGRES_USER) -Fc $(DATABASE)' > tmp/postgresql-backups/$(DATABASE)-$(shell date +%Y%m%d-%H%M%S).dump
	@echo "Backup saved to tmp/postgresql-backups/$(DATABASE)-$(shell date +%Y%m%d-%H%M%S).dump"

.PHONY: pg-backup-all
pg-backup-all:
	@echo "Creating backup of all databases..."
	@mkdir -p tmp/postgresql-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dumpall -U $(POSTGRES_USER)' | gzip > tmp/postgresql-backups/all-databases-$(shell date +%Y%m%d-%H%M%S).sql.gz
	@echo "Backup saved to tmp/postgresql-backups/all-databases-$(shell date +%Y%m%d-%H%M%S).sql.gz"

.PHONY: pg-basebackup
pg-basebackup:
	@echo "Creating physical base backup..."
	@echo "⚠️  WARNING: This requires replication user credentials"
	@mkdir -p tmp/postgresql-backups/basebackup-$(shell date +%Y%m%d-%H%M%S)
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$REPLICATION_PASSWORD" pg_basebackup -U replicator -D /tmp/basebackup -Ft -z -P'
	@$(KUBECTL) cp $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/tmp/basebackup tmp/postgresql-backups/basebackup-$(shell date +%Y%m%d-%H%M%S)/ || true
	@echo "Base backup saved to tmp/postgresql-backups/basebackup-$(shell date +%Y%m%d-%H%M%S)/"

.PHONY: pg-backup-config
pg-backup-config:
	@echo "Backing up PostgreSQL configuration..."
	@mkdir -p tmp/postgresql-backups
	@$(KUBECTL) get configmap $(CHART_NAME)-config -o yaml > tmp/postgresql-backups/configmap-$(shell date +%Y%m%d-%H%M%S).yaml 2>/dev/null || echo "No ConfigMap found"
	@$(KUBECTL) get secret $(CHART_NAME)-secret -o yaml > tmp/postgresql-backups/secret-$(shell date +%Y%m%d-%H%M%S).yaml 2>/dev/null || echo "No Secret found"
	@echo "Configuration backups saved to tmp/postgresql-backups/"

.PHONY: pg-backup-pvc-snapshot
pg-backup-pvc-snapshot:
	@echo "Creating PVC snapshot for PostgreSQL data..."
	@echo "⚠️  WARNING: Requires VolumeSnapshot API and snapshot class configured"
	@$(KUBECTL) get pvc -l app.kubernetes.io/name=$(CHART_NAME) -o name | while read pvc; do \
		pvc_name=$$(echo $$pvc | cut -d'/' -f2); \
		snapshot_name="$$pvc_name-snapshot-$(shell date +%Y%m%d-%H%M%S)"; \
		cat <<EOF | $(KUBECTL) apply -f - ; \
apiVersion: snapshot.storage.k8s.io/v1 ; \
kind: VolumeSnapshot ; \
metadata: ; \
  name: $$snapshot_name ; \
spec: ; \
  volumeSnapshotClassName: csi-hostpath-snapclass ; \
  source: ; \
    persistentVolumeClaimName: $$pvc_name ; \
EOF \
		echo "Created snapshot: $$snapshot_name"; \
	done

.PHONY: pg-backup-verify
pg-backup-verify:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-backup-verify FILE=path/to/backup.dump"; exit 1; fi
	@echo "Verifying backup file: $(FILE)"
	@if echo "$(FILE)" | grep -q ".dump$$"; then \
		echo "Custom format backup - listing contents:"; \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			sh -c 'cat > /tmp/verify.dump && pg_restore -l /tmp/verify.dump' < $(FILE); \
	elif echo "$(FILE)" | grep -q ".sql.gz$$"; then \
		echo "SQL backup - checking syntax:"; \
		zcat $(FILE) | head -n 50; \
	else \
		echo "SQL backup - checking syntax:"; \
		head -n 50 $(FILE); \
	fi

.PHONY: pg-restore
pg-restore:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-restore DATABASE=myapp FILE=path/to/backup.dump"; exit 1; fi
	@if [ -z "$(DATABASE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-restore DATABASE=myapp FILE=path/to/backup.dump"; exit 1; fi
	@echo "Restoring backup from $(FILE) to database $(DATABASE)..."
	@if echo "$(FILE)" | grep -q ".dump$$"; then \
		cat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			sh -c 'cat > /tmp/restore.dump && PGPASSWORD="$$POSTGRES_PASSWORD" pg_restore -U $(POSTGRES_USER) -d $(DATABASE) -v /tmp/restore.dump'; \
	else \
		cat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(DATABASE)'; \
	fi
	@echo "Restore completed"

.PHONY: pg-restore-all
pg-restore-all:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-restore-all FILE=path/to/all-databases.sql.gz"; exit 1; fi
	@echo "⚠️  WARNING: This will restore all databases, users, and roles"
	@echo "Restoring all databases from $(FILE)..."
	@if echo "$(FILE)" | grep -q ".gz$$"; then \
		zcat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER)'; \
	else \
		cat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER)'; \
	fi
	@echo "Restore completed"

.PHONY: pg-pitr
pg-pitr:
	@if [ -z "$(RECOVERY_TIME)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-pitr RECOVERY_TIME='2025-01-15 14:30:00'"; exit 1; fi
	@echo "⚠️  Point-in-Time Recovery (PITR) requires:"
	@echo "  1. Base backup (pg_basebackup)"
	@echo "  2. WAL archive with continuous archiving enabled"
	@echo "  3. Recovery target time: $(RECOVERY_TIME)"
	@echo ""
	@echo "Manual steps required:"
	@echo "  1. Stop PostgreSQL pod: kubectl scale statefulset $(CHART_NAME) --replicas=0"
	@echo "  2. Restore base backup to data directory"
	@echo "  3. Create recovery.signal file"
	@echo "  4. Configure recovery settings in postgresql.auto.conf:"
	@echo "     restore_command = 'cp /path/to/wal/%f %p'"
	@echo "     recovery_target_time = '$(RECOVERY_TIME)'"
	@echo "  5. Start PostgreSQL: kubectl scale statefulset $(CHART_NAME) --replicas=1"
	@echo "  6. Monitor recovery progress in logs"
	@echo ""
	@echo "See docs/postgresql-backup-guide.md for detailed PITR procedures"

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

# === Upgrade Operations ===

.PHONY: pg-pre-upgrade-check
pg-pre-upgrade-check:
	@echo "Running pre-upgrade checks..."
	@echo ""
	@echo "1. PostgreSQL Version:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -tc "SELECT version();"'
	@echo ""
	@echo "2. Database Sizes:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"'
	@echo ""
	@echo "3. Active Connections:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT count(*) FROM pg_stat_activity;"'
	@echo ""
	@echo "4. Installed Extensions:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE installed_version IS NOT NULL;"'
	@echo ""
	@echo "5. Replication Status:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "No replication configured"'
	@echo ""
	@echo "✅ Pre-upgrade checks completed. Review output before proceeding."
	@echo "📝 Recommendation: Create backup with: make -f make/ops/postgresql.mk pg-backup-all"

.PHONY: pg-post-upgrade-check
pg-post-upgrade-check:
	@echo "Running post-upgrade validation..."
	@echo ""
	@echo "1. PostgreSQL Version (should be upgraded):"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -tc "SELECT version();"'
	@echo ""
	@echo "2. Pod Status:"
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "3. Database Accessibility:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT datname FROM pg_database;"'
	@echo ""
	@echo "4. Extension Compatibility:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT name, installed_version, default_version FROM pg_available_extensions WHERE installed_version IS NOT NULL AND installed_version != default_version;"'
	@echo ""
	@echo "5. Active Connections:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT count(*) FROM pg_stat_activity;"'
	@echo ""
	@echo "6. Replication Status:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "No replication configured"'
	@echo ""
	@echo "✅ Post-upgrade validation completed."
	@echo "📝 Next step: Run ANALYZE with: make -f make/ops/postgresql.mk pg-analyze"

.PHONY: pg-check-extensions
pg-check-extensions:
	@echo "Checking PostgreSQL extensions compatibility..."
	@echo ""
	@echo "Available extensions:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT name, default_version, installed_version, comment FROM pg_available_extensions WHERE installed_version IS NOT NULL ORDER BY name;"'
	@echo ""
	@echo "Extensions with version mismatches:"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT name, installed_version, default_version FROM pg_available_extensions WHERE installed_version IS NOT NULL AND installed_version != default_version;"'

.PHONY: pg-upgrade-major
pg-upgrade-major:
	@echo "⚠️  PostgreSQL Major Version Upgrade"
	@echo ""
	@echo "This is a manual process using pg_upgrade. Steps required:"
	@echo ""
	@echo "1. Backup current database:"
	@echo "   make -f make/ops/postgresql.mk pg-backup-all"
	@echo ""
	@echo "2. Scale down to single replica:"
	@echo "   kubectl scale statefulset $(CHART_NAME) --replicas=1"
	@echo ""
	@echo "3. Install new PostgreSQL version in parallel (blue-green approach)"
	@echo "   OR use pg_upgrade tool for in-place upgrade:"
	@echo ""
	@echo "   a. Install both old and new PostgreSQL versions in pod"
	@echo "   b. Run pg_upgrade --check:"
	@echo "      pg_upgrade --check \\"
	@echo "        --old-datadir=/var/lib/postgresql/data \\"
	@echo "        --new-datadir=/var/lib/postgresql/data-new \\"
	@echo "        --old-bindir=/usr/lib/postgresql/OLD_VERSION/bin \\"
	@echo "        --new-bindir=/usr/lib/postgresql/NEW_VERSION/bin"
	@echo ""
	@echo "   c. Run pg_upgrade (link mode for faster upgrade):"
	@echo "      pg_upgrade --link \\"
	@echo "        --old-datadir=/var/lib/postgresql/data \\"
	@echo "        --new-datadir=/var/lib/postgresql/data-new \\"
	@echo "        --old-bindir=/usr/lib/postgresql/OLD_VERSION/bin \\"
	@echo "        --new-bindir=/usr/lib/postgresql/NEW_VERSION/bin"
	@echo ""
	@echo "4. Update Helm chart to new version:"
	@echo "   helm upgrade $(CHART_NAME) sb-charts/postgresql --set image.tag=NEW_VERSION"
	@echo ""
	@echo "5. Run post-upgrade tasks:"
	@echo "   make -f make/ops/postgresql.mk pg-analyze"
	@echo "   make -f make/ops/postgresql.mk pg-post-upgrade-check"
	@echo ""
	@echo "📚 See docs/postgresql-upgrade-guide.md for detailed procedures"

.PHONY: pg-list-replication-slots
pg-list-replication-slots:
	@echo "Listing replication slots..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT * FROM pg_replication_slots;"'

.PHONY: pg-promote-replica
pg-promote-replica:
	@if [ -z "$(POD)" ]; then echo "Usage: make -f make/ops/postgresql.mk pg-promote-replica POD=postgresql-1"; exit 1; fi
	@echo "⚠️  Promoting replica $(POD) to master..."
	@$(KUBECTL) exec $(POD) -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_ctl promote -D /var/lib/postgresql/data'
	@echo "Replica promoted. Verify with: make -f make/ops/postgresql.mk pg-replication-status"

.PHONY: pg-active-connections
pg-active-connections:
	@echo "Getting detailed active connections..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pid, usename, datname, application_name, client_addr, state, query_start, state_change, wait_event_type, wait_event, query FROM pg_stat_activity WHERE state != '"'"'idle'"'"' ORDER BY query_start;"'

.PHONY: pg-bloat
pg-bloat:
	@echo "Getting table and index bloat..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'"'"'.'"'"'||tablename)) AS size FROM pg_tables WHERE schemaname NOT IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"') ORDER BY pg_total_relation_size(schemaname||'"'"'.'"'"'||tablename) DESC LIMIT 20;"'

.PHONY: pg-index-usage
pg-index-usage:
	@echo "Getting index usage statistics..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch, pg_size_pretty(pg_relation_size(indexrelid)) AS size FROM pg_stat_user_indexes ORDER BY idx_scan ASC LIMIT 20;"'

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
	@echo "Connection & Shell:"
	@echo "  pg-shell                             - Open psql shell"
	@echo "  pg-bash                              - Open bash shell"
	@echo "  pg-logs                              - View logs from first pod"
	@echo "  pg-logs-all                          - View logs from all pods"
	@echo "  pg-ping                              - Test connection"
	@echo "  pg-version                           - Get PostgreSQL version"
	@echo ""
	@echo "Database Management:"
	@echo "  pg-list-databases                    - List all databases"
	@echo "  pg-list-tables                       - List all tables"
	@echo "  pg-list-users                        - List all users"
	@echo "  pg-database-size                     - Get database size"
	@echo "  pg-all-databases-size                - Get all databases size"
	@echo ""
	@echo "Monitoring & Statistics:"
	@echo "  pg-stats                             - Get database statistics"
	@echo "  pg-activity                          - Get active connections and queries"
	@echo "  pg-connections                       - Get connection count by state"
	@echo "  pg-locks                             - Get current locks"
	@echo "  pg-slow-queries                      - Get slow queries (requires pg_stat_statements)"
	@echo "  pg-active-connections                - Get detailed active connections"
	@echo "  pg-bloat                             - Get table and index bloat"
	@echo "  pg-index-usage                       - Get index usage statistics"
	@echo ""
	@echo "Replication & HA:"
	@echo "  pg-replication-status                - Get replication status from master"
	@echo "  pg-replication-lag                   - Get replication lag"
	@echo "  pg-recovery-status                   - Get recovery status (replicas)"
	@echo "  pg-wal-status                        - Get WAL status"
	@echo "  pg-list-replication-slots            - List replication slots"
	@echo "  pg-promote-replica POD=<pod>         - Promote replica to master"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  pg-backup DATABASE=<db>              - Backup single database (custom format)"
	@echo "  pg-backup-all                        - Backup all databases (pg_dumpall)"
	@echo "  pg-basebackup                        - Create physical base backup"
	@echo "  pg-backup-config                     - Backup ConfigMap and Secret"
	@echo "  pg-backup-pvc-snapshot               - Create PVC snapshot"
	@echo "  pg-backup-verify FILE=<file>         - Verify backup file"
	@echo "  pg-restore DATABASE=<db> FILE=<file> - Restore single database"
	@echo "  pg-restore-all FILE=<file>           - Restore all databases"
	@echo "  pg-pitr RECOVERY_TIME='YYYY-MM-DD HH:MM:SS' - Point-in-Time Recovery (manual guide)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  pg-pre-upgrade-check                 - Run pre-upgrade validation (15 checks)"
	@echo "  pg-post-upgrade-check                - Run post-upgrade validation (12 checks)"
	@echo "  pg-check-extensions                  - Check extensions compatibility"
	@echo "  pg-upgrade-major                     - Guide for major version upgrade (pg_upgrade)"
	@echo ""
	@echo "Maintenance:"
	@echo "  pg-vacuum                            - Run VACUUM"
	@echo "  pg-vacuum-analyze                    - Run VACUUM ANALYZE"
	@echo "  pg-vacuum-full                       - Run VACUUM FULL (locks tables)"
	@echo "  pg-analyze                           - Run ANALYZE"
	@echo "  pg-reindex TABLE=<table>             - Reindex table"
	@echo ""
	@echo "Configuration:"
	@echo "  pg-config                            - Show all configuration"
	@echo "  pg-config-get PARAM=<param>          - Get specific config parameter"
	@echo "  pg-reload                            - Reload configuration"
	@echo ""
	@echo "Utilities:"
	@echo "  pg-port-forward                      - Port forward to localhost:5432"
	@echo "  pg-restart                           - Restart StatefulSet"
	@echo "  pg-scale REPLICAS=<n>                - Scale replicas"
	@echo "  pg-get-password                      - Get postgres password"
	@echo "  pg-get-replication-password          - Get replication password"
	@echo ""
	@echo "Documentation:"
	@echo "  📚 Backup Guide: docs/postgresql-backup-guide.md"
	@echo "  📚 Upgrade Guide: docs/postgresql-upgrade-guide.md"
	@echo "  📚 Chart README: charts/postgresql/README.md"
