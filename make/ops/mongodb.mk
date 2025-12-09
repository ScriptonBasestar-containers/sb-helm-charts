# MongoDB Chart Operational Commands
#
# This Makefile provides day-2 operational commands for MongoDB deployments.

include make/common.mk

CHART_NAME := mongodb
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)

# Backup directory
BACKUP_DIR := tmp/mongodb-backups
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# ========================================
# Access & Debugging
# ========================================

## mongo-port-forward: Port forward MongoDB to localhost:27017
.PHONY: mongo-port-forward
mongo-port-forward:
	@echo "Forwarding MongoDB to mongodb://localhost:27017..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 27017:27017

## mongo-get-connection-string: Get MongoDB connection string
.PHONY: mongo-get-connection-string
mongo-get-connection-string:
	@echo "=== MongoDB Connection String ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.getMongo()"

## mongo-logs: View MongoDB logs
.PHONY: mongo-logs
mongo-logs:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl logs -f -n $(NAMESPACE) $$POD --tail=100

## mongo-logs-all: View logs from all MongoDB pods
.PHONY: mongo-logs-all
mongo-logs-all:
	@kubectl logs -f -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=50 --max-log-requests=10

## mongo-shell: Open MongoDB shell
.PHONY: mongo-shell
mongo-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "MongoDB Shell - use 'exit' to quit"; \
	kubectl exec -it -n $(NAMESPACE) $$POD -- mongo

## mongo-restart: Restart MongoDB StatefulSet
.PHONY: mongo-restart
mongo-restart:
	@echo "Restarting MongoDB..."
	@kubectl rollout restart -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME)
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME)

## mongo-describe: Describe MongoDB pod
.PHONY: mongo-describe
mongo-describe:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## mongo-events: Show MongoDB pod events
.PHONY: mongo-events
mongo-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## mongo-stats: Show resource usage statistics
.PHONY: mongo-stats
mongo-stats:
	@echo "=== MongoDB Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# Server Status & Monitoring
# ========================================

## mongo-server-status: Get MongoDB server status
.PHONY: mongo-server-status
mongo-server-status:
	@echo "=== MongoDB Server Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.serverStatus()"

## mongo-replica-status: Get replica set status
.PHONY: mongo-replica-status
mongo-replica-status:
	@echo "=== Replica Set Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "rs.status()" 2>/dev/null || echo "Not a replica set"

## mongo-disk-usage: Check disk usage
.PHONY: mongo-disk-usage
mongo-disk-usage:
	@echo "=== MongoDB Disk Usage ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data/db 2>/dev/null || echo "Unable to check disk usage"

## mongo-current-ops: Show current operations
.PHONY: mongo-current-ops
mongo-current-ops:
	@echo "=== Current MongoDB Operations ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.currentOp()"

## mongo-slow-queries: Show slow queries
.PHONY: mongo-slow-queries
mongo-slow-queries:
	@echo "=== Slow Queries (> 100ms) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.system.profile.find({millis: {\$$gt: 100}}).limit(10).pretty()"

## mongo-check-config: Check MongoDB configuration
.PHONY: mongo-check-config
mongo-check-config:
	@echo "=== MongoDB Configuration ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /etc/mongod.conf 2>/dev/null || echo "Configuration file not found"

# ========================================
# Database Operations
# ========================================

## mongo-list-databases: List all databases
.PHONY: mongo-list-databases
mongo-list-databases:
	@echo "=== MongoDB Databases ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand('listDatabases')"

## mongo-list-collections: List collections in database (requires DB parameter)
.PHONY: mongo-list-collections
mongo-list-collections:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-list-collections DB=myapp"; \
		exit 1; \
	fi
	@echo "=== Collections in Database: $(DB) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --quiet --eval "db.getCollectionNames()"

## mongo-db-size: Get database size (requires DB parameter)
.PHONY: mongo-db-size
mongo-db-size:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-db-size DB=myapp"; \
		exit 1; \
	fi
	@echo "=== Database Size: $(DB) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --quiet --eval "db.stats()"

## mongo-db-stats: Get database statistics (requires DB parameter)
.PHONY: mongo-db-stats
mongo-db-stats:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-db-stats DB=myapp"; \
		exit 1; \
	fi
	@echo "=== Database Statistics: $(DB) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --quiet --eval "db.stats()"

## mongo-collection-stats: Get collection statistics (requires DB and COLLECTION parameters)
.PHONY: mongo-collection-stats
mongo-collection-stats:
	@if [ -z "$(DB)" ] || [ -z "$(COLLECTION)" ]; then \
		echo "Error: DB and COLLECTION parameters are required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-collection-stats DB=myapp COLLECTION=users"; \
		exit 1; \
	fi
	@echo "=== Collection Statistics: $(DB).$(COLLECTION) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --quiet --eval "db.$(COLLECTION).stats()"

## mongo-drop-database: Drop database (requires DB parameter, DANGEROUS)
.PHONY: mongo-drop-database
mongo-drop-database:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-drop-database DB=testdb"; \
		exit 1; \
	fi
	@echo "WARNING: This will permanently delete database '$(DB)' and all its data."
	@read -p "Are you sure? Type 'yes' to confirm: " -r; \
	echo; \
	if [ "$$REPLY" = "yes" ]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval "db.dropDatabase()"; \
		echo "Database $(DB) dropped"; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Index Management
# ========================================

## mongo-list-indexes: List indexes (requires DB and COLLECTION parameters)
.PHONY: mongo-list-indexes
mongo-list-indexes:
	@if [ -z "$(DB)" ] || [ -z "$(COLLECTION)" ]; then \
		echo "Error: DB and COLLECTION parameters are required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-list-indexes DB=myapp COLLECTION=users"; \
		exit 1; \
	fi
	@echo "=== Indexes for $(DB).$(COLLECTION) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --quiet --eval "db.$(COLLECTION).getIndexes()"

## mongo-create-index: Create index (requires DB, COLLECTION, FIELD parameters)
.PHONY: mongo-create-index
mongo-create-index:
	@if [ -z "$(DB)" ] || [ -z "$(COLLECTION)" ] || [ -z "$(FIELD)" ]; then \
		echo "Error: DB, COLLECTION, and FIELD parameters are required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-create-index DB=myapp COLLECTION=users FIELD=email"; \
		exit 1; \
	fi
	@echo "Creating index on $(DB).$(COLLECTION).$(FIELD)..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval "db.$(COLLECTION).createIndex({$(FIELD): 1})"

## mongo-rebuild-indexes: Rebuild all indexes for database (requires DB parameter)
.PHONY: mongo-rebuild-indexes
mongo-rebuild-indexes:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-rebuild-indexes DB=myapp"; \
		exit 1; \
	fi
	@echo "Rebuilding indexes for database: $(DB)..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval "db.getCollectionNames().forEach(function(col) { db[col].reIndex(); })"

# ========================================
# User Management
# ========================================

## mongo-list-users: List all users
.PHONY: mongo-list-users
mongo-list-users:
	@echo "=== MongoDB Users ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo admin --quiet --eval "db.getUsers()"

## mongo-create-user: Create user (requires USER, PASSWORD, DB, ROLE parameters)
.PHONY: mongo-create-user
mongo-create-user:
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ] || [ -z "$(DB)" ] || [ -z "$(ROLE)" ]; then \
		echo "Error: USER, PASSWORD, DB, and ROLE parameters are required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-create-user USER=myuser PASSWORD=mypass DB=myapp ROLE=readWrite"; \
		echo "Common roles: read, readWrite, dbAdmin, userAdmin, dbOwner"; \
		exit 1; \
	fi
	@echo "Creating user: $(USER) with role $(ROLE) on database $(DB)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval \
		"db.createUser({user: '$(USER)', pwd: '$(PASSWORD)', roles: [{role: '$(ROLE)', db: '$(DB)'}]})"

## mongo-delete-user: Delete user (requires USER parameter)
.PHONY: mongo-delete-user
mongo-delete-user:
	@if [ -z "$(USER)" ]; then \
		echo "Error: USER parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-delete-user USER=myuser"; \
		exit 1; \
	fi
	@echo "Deleting user: $(USER)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo admin --eval "db.dropUser('$(USER)')"

## mongo-change-password: Change user password (requires USER and PASSWORD parameters)
.PHONY: mongo-change-password
mongo-change-password:
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "Error: USER and PASSWORD parameters are required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-change-password USER=myuser PASSWORD=newpass"; \
		exit 1; \
	fi
	@echo "Changing password for user: $(USER)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo admin --eval "db.changeUserPassword('$(USER)', '$(PASSWORD)')"

# ========================================
# Replica Set Operations
# ========================================

## mongo-stepdown: Step down primary (force primary election)
.PHONY: mongo-stepdown
mongo-stepdown:
	@echo "=== Stepping Down Primary ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --eval "rs.stepDown(60)" 2>/dev/null || echo "Not a replica set or not primary"

## mongo-replica-reconfig: Reconfigure replica set
.PHONY: mongo-replica-reconfig
mongo-replica-reconfig:
	@echo "=== Reconfiguring Replica Set ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --eval "cfg = rs.conf(); rs.reconfig(cfg, {force: true})" 2>/dev/null || echo "Not a replica set"

## mongo-replication-lag: Check replication lag
.PHONY: mongo-replication-lag
mongo-replication-lag:
	@echo "=== Replication Lag ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "rs.printSecondaryReplicationInfo()" 2>/dev/null || echo "Not a replica set"

## mongo-replica-config: Show replica set configuration
.PHONY: mongo-replica-config
mongo-replica-config:
	@echo "=== Replica Set Configuration ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "rs.conf()" 2>/dev/null || echo "Not a replica set"

# ========================================
# Maintenance Operations
# ========================================

## mongo-compact: Compact database to reclaim space (requires DB parameter)
.PHONY: mongo-compact
mongo-compact:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-compact DB=myapp"; \
		exit 1; \
	fi
	@echo "Compacting database: $(DB)..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval "db.getCollectionNames().forEach(function(col) { db.runCommand({compact: col}); })"

## mongo-repair: Repair database (requires DB parameter, USE WITH CAUTION)
.PHONY: mongo-repair
mongo-repair:
	@if [ -z "$(DB)" ]; then \
		echo "Error: DB parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-repair DB=myapp"; \
		exit 1; \
	fi
	@echo "WARNING: Database repair can take a long time and may cause data loss."
	@read -p "Are you sure? Type 'yes' to confirm: " -r; \
	echo; \
	if [ "$$REPLY" = "yes" ]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl exec -n $(NAMESPACE) $$POD -- mongo $(DB) --eval "db.repairDatabase()"; \
	else \
		echo "Cancelled"; \
	fi

## mongo-validate: Validate MongoDB setup
.PHONY: mongo-validate
mongo-validate:
	@echo "=== MongoDB Validation ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "1. MongoDB version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --version; \
	echo "2. Pod status:"; \
	kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR); \
	echo "3. Disk usage:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data/db 2>/dev/null || echo "Unable to check"; \
	echo "4. Database list:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand('listDatabases')"

# ========================================
# Backup & Recovery
# ========================================

## mongo-backup-database: Backup database using mongodump
.PHONY: mongo-backup-database
mongo-backup-database:
	@echo "=== Backing Up MongoDB Database ==="
	@mkdir -p $(BACKUP_DIR)/database-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongodump --gzip --out=/tmp/backup; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/backup $(BACKUP_DIR)/database-$(TIMESTAMP)/; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /tmp/backup
	@echo "Database backup saved to: $(BACKUP_DIR)/database-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/database-$(TIMESTAMP)/

## mongo-backup-oplog: Backup oplog for point-in-time recovery (replica sets)
.PHONY: mongo-backup-oplog
mongo-backup-oplog:
	@echo "=== Backing Up MongoDB Oplog ==="
	@mkdir -p $(BACKUP_DIR)/oplog-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongodump --oplog --gzip --out=/tmp/oplog-backup 2>/dev/null || echo "Oplog backup requires replica set"; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/oplog-backup $(BACKUP_DIR)/oplog-$(TIMESTAMP)/ 2>/dev/null || echo "Skipping copy"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /tmp/oplog-backup 2>/dev/null || true
	@echo "Oplog backup saved to: $(BACKUP_DIR)/oplog-$(TIMESTAMP)/"

## mongo-backup-config: Backup MongoDB configuration
.PHONY: mongo-backup-config
mongo-backup-config:
	@echo "=== Backing Up MongoDB Configuration ==="
	@mkdir -p $(BACKUP_DIR)/config-$(TIMESTAMP)
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME)-config -o yaml > $(BACKUP_DIR)/config-$(TIMESTAMP)/configmap.yaml 2>/dev/null || echo "No ConfigMap found"
	@kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME)-secret -o yaml > $(BACKUP_DIR)/config-$(TIMESTAMP)/secret.yaml 2>/dev/null || echo "No Secret found"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- cat /etc/mongod.conf > $(BACKUP_DIR)/config-$(TIMESTAMP)/mongod.conf 2>/dev/null || echo "No config file"
	@echo "Configuration backed up to: $(BACKUP_DIR)/config-$(TIMESTAMP)/"

## mongo-backup-users: Backup users and roles
.PHONY: mongo-backup-users
mongo-backup-users:
	@echo "=== Backing Up MongoDB Users ==="
	@mkdir -p $(BACKUP_DIR)/users-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mongodump --db=admin --collection=system.users --collection=system.roles --gzip --out=/tmp/users-backup; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/users-backup $(BACKUP_DIR)/users-$(TIMESTAMP)/; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /tmp/users-backup
	@echo "Users backed up to: $(BACKUP_DIR)/users-$(TIMESTAMP)/"

## mongo-full-backup: Full backup (database, oplog, config, users)
.PHONY: mongo-full-backup
mongo-full-backup:
	@echo "=== Full MongoDB Backup ==="
	@make -f make/ops/mongodb.mk mongo-backup-database
	@make -f make/ops/mongodb.mk mongo-backup-oplog
	@make -f make/ops/mongodb.mk mongo-backup-config
	@make -f make/ops/mongodb.mk mongo-backup-users
	@echo "Full backup completed: $(BACKUP_DIR)/*-$(TIMESTAMP)/"

## mongo-backup-status: Show all available backups
.PHONY: mongo-backup-status
mongo-backup-status:
	@echo "=== Available MongoDB Backups ==="
	@ls -lht $(BACKUP_DIR)/ 2>/dev/null || echo "No backups found"

## mongo-restore-database: Restore database from backup (requires FILE parameter)
.PHONY: mongo-restore-database
mongo-restore-database:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/mongodb.mk mongo-restore-database FILE=tmp/mongodb-backups/database-20250109-143022/"; \
		exit 1; \
	fi
	@if [ ! -d "$(FILE)" ]; then \
		echo "Error: Backup directory not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current MongoDB databases."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl cp $(FILE) $$POD:/tmp/restore/; \
		kubectl exec -n $(NAMESPACE) $$POD -- mongorestore --drop --gzip /tmp/restore/; \
		kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /tmp/restore/; \
		echo "Database restored from: $(FILE)"; \
	else \
		echo "Cancelled"; \
	fi

## mongo-snapshot-create: Create PVC snapshot
.PHONY: mongo-snapshot-create
mongo-snapshot-create:
	@echo "=== Creating VolumeSnapshot ==="
	@cat <<EOF | kubectl apply -f -
	apiVersion: snapshot.storage.k8s.io/v1
	kind: VolumeSnapshot
	metadata:
	  name: mongodb-snapshot-$(TIMESTAMP)
	  namespace: $(NAMESPACE)
	spec:
	  volumeSnapshotClassName: csi-snapclass
	  source:
	    persistentVolumeClaimName: data-$(RELEASE_NAME)-$(CHART_NAME)-0
	EOF
	@echo "Snapshot created: mongodb-snapshot-$(TIMESTAMP)"

# ========================================
# Upgrade Support
# ========================================

## mongo-pre-upgrade-check: Pre-upgrade validation checklist
.PHONY: mongo-pre-upgrade-check
mongo-pre-upgrade-check:
	@echo "=== MongoDB Pre-Upgrade Checklist ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "1. Current version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --version; \
	echo ""; \
	echo "2. Pod health:"; \
	kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR); \
	echo ""; \
	echo "3. Feature Compatibility Version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"; \
	echo ""; \
	echo "4. Disk usage:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data/db 2>/dev/null || echo "Unable to check"; \
	echo ""; \
	echo "5. Database list:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand('listDatabases')"; \
	echo ""; \
	echo "✅ Pre-upgrade checks complete. Don't forget to:"; \
	echo "   - Backup: make -f make/ops/mongodb.mk mongo-full-backup"; \
	echo "   - Review release notes: https://docs.mongodb.com/manual/release-notes/"

## mongo-post-upgrade-check: Post-upgrade validation
.PHONY: mongo-post-upgrade-check
mongo-post-upgrade-check:
	@echo "=== MongoDB Post-Upgrade Validation ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "1. Pod status:"; \
	kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR); \
	echo ""; \
	echo "2. New version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --version; \
	echo ""; \
	echo "3. Feature Compatibility Version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"; \
	echo ""; \
	echo "4. Check for errors in logs:"; \
	kubectl logs -n $(NAMESPACE) $$POD --tail=50 | grep -i error || echo "No errors found"; \
	echo ""; \
	echo "5. Database connectivity:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "db.adminCommand('ping')"; \
	echo ""; \
	echo "6. Replica set status (if applicable):"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mongo --quiet --eval "rs.status().ok" 2>/dev/null || echo "Not a replica set"; \
	echo ""; \
	echo "✅ Post-upgrade checks complete. Manual validation required:"; \
	echo "   - Test application connectivity"; \
	echo "   - Verify database operations"; \
	echo "   - Check performance metrics"

## mongo-upgrade-rollback: Rollback to previous Helm revision
.PHONY: mongo-upgrade-rollback
mongo-upgrade-rollback:
	@echo "=== Rolling Back MongoDB Upgrade ==="
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Rollback to previous revision? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE); \
		kubectl rollout status -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME); \
		echo "Rollback complete"; \
		make -f make/ops/mongodb.mk mongo-server-status; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Help
# ========================================

## mongo-help: Show all available MongoDB commands
.PHONY: mongo-help
mongo-help:
	@echo "=== MongoDB Operational Commands ==="
	@echo ""
	@echo "Access & Debugging:"
	@echo "  mongo-port-forward              Port forward to localhost:27017"
	@echo "  mongo-get-connection-string     Get MongoDB connection string"
	@echo "  mongo-logs                      View MongoDB logs"
	@echo "  mongo-logs-all                  View logs from all MongoDB pods"
	@echo "  mongo-shell                     Open MongoDB shell"
	@echo "  mongo-restart                   Restart MongoDB StatefulSet"
	@echo "  mongo-describe                  Describe MongoDB pod"
	@echo "  mongo-events                    Show pod events"
	@echo "  mongo-stats                     Show resource usage"
	@echo ""
	@echo "Server Status & Monitoring:"
	@echo "  mongo-server-status             Get MongoDB server status"
	@echo "  mongo-replica-status            Get replica set status"
	@echo "  mongo-disk-usage                Check disk usage"
	@echo "  mongo-current-ops               Show current operations"
	@echo "  mongo-slow-queries              Show slow queries"
	@echo "  mongo-check-config              Check MongoDB configuration"
	@echo ""
	@echo "Database Operations:"
	@echo "  mongo-list-databases            List all databases"
	@echo "  mongo-list-collections DB=name  List collections in database"
	@echo "  mongo-db-size DB=name           Get database size"
	@echo "  mongo-db-stats DB=name          Get database statistics"
	@echo "  mongo-collection-stats DB=name COLLECTION=name Get collection stats"
	@echo "  mongo-drop-database DB=name     Drop database (DANGEROUS)"
	@echo ""
	@echo "Index Management:"
	@echo "  mongo-list-indexes DB=name COLLECTION=name List indexes"
	@echo "  mongo-create-index DB=name COLLECTION=name FIELD=name Create index"
	@echo "  mongo-rebuild-indexes DB=name   Rebuild all indexes"
	@echo ""
	@echo "User Management:"
	@echo "  mongo-list-users                List all users"
	@echo "  mongo-create-user USER=name PASSWORD=pass DB=name ROLE=role Create user"
	@echo "  mongo-delete-user USER=name     Delete user"
	@echo "  mongo-change-password USER=name PASSWORD=pass Change password"
	@echo ""
	@echo "Replica Set Operations:"
	@echo "  mongo-stepdown                  Step down primary"
	@echo "  mongo-replica-reconfig          Reconfigure replica set"
	@echo "  mongo-replication-lag           Check replication lag"
	@echo "  mongo-replica-config            Show replica set configuration"
	@echo ""
	@echo "Maintenance Operations:"
	@echo "  mongo-compact DB=name           Compact database"
	@echo "  mongo-repair DB=name            Repair database (USE WITH CAUTION)"
	@echo "  mongo-validate                  Validate MongoDB setup"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  mongo-backup-database           Backup database"
	@echo "  mongo-backup-oplog              Backup oplog (replica sets)"
	@echo "  mongo-backup-config             Backup configuration"
	@echo "  mongo-backup-users              Backup users and roles"
	@echo "  mongo-full-backup               Full backup (all components)"
	@echo "  mongo-backup-status             Show all backups"
	@echo "  mongo-restore-database FILE=path Restore database"
	@echo "  mongo-snapshot-create           Create PVC snapshot"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  mongo-pre-upgrade-check         Pre-upgrade validation"
	@echo "  mongo-post-upgrade-check        Post-upgrade validation"
	@echo "  mongo-upgrade-rollback          Rollback to previous revision"
	@echo ""
	@echo "Usage examples:"
	@echo "  make -f make/ops/mongodb.mk mongo-port-forward"
	@echo "  make -f make/ops/mongodb.mk mongo-list-databases"
	@echo "  make -f make/ops/mongodb.mk mongo-create-user USER=alice PASSWORD=secret123 DB=myapp ROLE=readWrite"
	@echo "  make -f make/ops/mongodb.mk mongo-backup-database"
