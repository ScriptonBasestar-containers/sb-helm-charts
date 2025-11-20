# MongoDB Chart Operations
# Operational commands for MongoDB Helm chart management

include Makefile.common.mk

CHART_NAME := mongodb
CHART_DIR := charts/mongodb
NAMESPACE ?= default
RELEASE_NAME ?= mongodb

# Default pod selection
POD ?= $(RELEASE_NAME)-0

################################################################################
# Help
################################################################################

.PHONY: help
help::
	@echo ""
	@echo "MongoDB Operations:"
	@echo "  mongo-shell              - Open mongosh shell"
	@echo "  mongo-bash               - Open bash shell in MongoDB pod"
	@echo "  mongo-logs               - View MongoDB logs"
	@echo "  mongo-port-forward       - Port forward to localhost:27017"
	@echo ""
	@echo "Database Operations:"
	@echo "  mongo-backup             - Backup all databases to tmp/mongodb-backups/"
	@echo "  mongo-restore FILE=...   - Restore from backup file"
	@echo "  mongo-list-dbs           - List all databases"
	@echo "  mongo-list-collections DB=... - List collections in database"
	@echo "  mongo-db-stats DB=...    - Show database statistics"
	@echo ""
	@echo "Replica Set Operations:"
	@echo "  mongo-rs-status          - Get replica set status"
	@echo "  mongo-rs-config          - Get replica set configuration"
	@echo "  mongo-rs-initiate        - Manually initialize replica set"
	@echo "  mongo-rs-add-member HOST=... - Add member to replica set"
	@echo "  mongo-rs-remove-member HOST=... - Remove member from replica set"
	@echo "  mongo-rs-stepdown        - Step down primary (trigger election)"
	@echo ""
	@echo "User Management:"
	@echo "  mongo-create-user DB=... USER=... PASSWORD=... ROLE=... - Create user"
	@echo "  mongo-list-users DB=...  - List users in database"
	@echo "  mongo-drop-user DB=... USER=... - Drop user"
	@echo "  mongo-grant-role DB=... USER=... ROLE=... - Grant role to user"
	@echo ""
	@echo "Performance & Monitoring:"
	@echo "  mongo-server-status      - Show server status"
	@echo "  mongo-db-profiling DB=... - Show profiling data"
	@echo "  mongo-current-ops        - Show current operations"
	@echo "  mongo-top                - Show collection usage statistics"
	@echo "  mongo-stats              - Show server statistics"
	@echo ""
	@echo "Maintenance:"
	@echo "  mongo-compact DB=... COLLECTION=... - Compact collection"
	@echo "  mongo-reindex DB=... COLLECTION=... - Rebuild indexes"
	@echo "  mongo-validate DB=... COLLECTION=... - Validate collection"
	@echo "  mongo-repair             - Repair database (requires downtime)"
	@echo ""
	@echo "CLI & Debug:"
	@echo "  mongo-cli CMD='...'      - Run mongosh command"
	@echo "  mongo-version            - Show MongoDB version"
	@echo "  mongo-ping               - Ping MongoDB server"
	@echo "  mongo-restart            - Restart MongoDB StatefulSet"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)   - Kubernetes namespace"
	@echo "  RELEASE_NAME=$(RELEASE_NAME) - Helm release name"
	@echo "  POD=$(POD)               - Pod name for operations"

################################################################################
# Basic Operations
################################################################################

.PHONY: mongo-shell
mongo-shell:
	@echo "Opening mongosh shell in pod: $(POD)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec -it $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD

.PHONY: mongo-bash
mongo-bash:
	@echo "Opening bash shell in pod: $(POD)"
	kubectl exec -it $(POD) -n $(NAMESPACE) -- bash

.PHONY: mongo-logs
mongo-logs:
	@echo "Viewing logs for pod: $(POD)"
	kubectl logs -f $(POD) -n $(NAMESPACE)

.PHONY: mongo-port-forward
mongo-port-forward:
	@echo "Port forwarding MongoDB to localhost:27017"
	@echo "Connect with: mongosh mongodb://127.0.0.1:27017 --username root --password <password>"
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 27017:27017

################################################################################
# Database Operations
################################################################################

.PHONY: mongo-backup
mongo-backup:
	@echo "Backing up all MongoDB databases..."
	@mkdir -p tmp/mongodb-backups
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	BACKUP_FILE="tmp/mongodb-backups/mongodb-backup-$$(date +%Y%m%d-%H%M%S)"; \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongodump --username root --password $$MONGODB_ROOT_PASSWORD --archive | cat > $$BACKUP_FILE && \
	gzip $$BACKUP_FILE && \
	echo "Backup saved to: $$BACKUP_FILE.gz"

.PHONY: mongo-restore
mongo-restore:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make mongo-restore FILE=path/to/backup.gz"
	@exit 1
endif
	@echo "Restoring MongoDB from: $(FILE)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	if [[ "$(FILE)" == *.gz ]]; then \
		gunzip -c $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- mongorestore --username root --password $$MONGODB_ROOT_PASSWORD --archive; \
	else \
		cat $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- mongorestore --username root --password $$MONGODB_ROOT_PASSWORD --archive; \
	fi
	@echo "Restore completed"

.PHONY: mongo-list-dbs
mongo-list-dbs:
	@echo "Listing all databases..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.adminCommand('listDatabases')"

.PHONY: mongo-list-collections
mongo-list-collections:
ifndef DB
	@echo "Error: DB variable required. Usage: make mongo-list-collections DB=mydb"
	@exit 1
endif
	@echo "Listing collections in database: $(DB)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.getCollectionNames()"

.PHONY: mongo-db-stats
mongo-db-stats:
ifndef DB
	@echo "Error: DB variable required. Usage: make mongo-db-stats DB=mydb"
	@exit 1
endif
	@echo "Getting statistics for database: $(DB)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.stats()"

################################################################################
# Replica Set Operations
################################################################################

.PHONY: mongo-rs-status
mongo-rs-status:
	@echo "Getting replica set status..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.status()"

.PHONY: mongo-rs-config
mongo-rs-config:
	@echo "Getting replica set configuration..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.conf()"

.PHONY: mongo-rs-initiate
mongo-rs-initiate:
	@echo "Initiating replica set..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.initiate()"

.PHONY: mongo-rs-add-member
mongo-rs-add-member:
ifndef HOST
	@echo "Error: HOST variable required. Usage: make mongo-rs-add-member HOST=mongodb-3:27017"
	@exit 1
endif
	@echo "Adding member to replica set: $(HOST)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.add('$(HOST)')"

.PHONY: mongo-rs-remove-member
mongo-rs-remove-member:
ifndef HOST
	@echo "Error: HOST variable required. Usage: make mongo-rs-remove-member HOST=mongodb-3:27017"
	@exit 1
endif
	@echo "Removing member from replica set: $(HOST)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.remove('$(HOST)')"

.PHONY: mongo-rs-stepdown
mongo-rs-stepdown:
	@echo "Stepping down primary..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "rs.stepDown()"

################################################################################
# User Management
################################################################################

.PHONY: mongo-create-user
mongo-create-user:
ifndef DB
	@echo "Error: DB, USER, PASSWORD, and ROLE variables required."
	@echo "Usage: make mongo-create-user DB=mydb USER=myuser PASSWORD=mypass ROLE=readWrite"
	@exit 1
endif
ifndef USER
	@echo "Error: USER variable required."
	@exit 1
endif
ifndef PASSWORD
	@echo "Error: PASSWORD variable required."
	@exit 1
endif
ifndef ROLE
	@echo "Error: ROLE variable required."
	@exit 1
endif
	@echo "Creating user $(USER) in database $(DB) with role $(ROLE)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval \
		"db.createUser({user: '$(USER)', pwd: '$(PASSWORD)', roles: [{role: '$(ROLE)', db: '$(DB)'}]})"

.PHONY: mongo-list-users
mongo-list-users:
ifndef DB
	@echo "Error: DB variable required. Usage: make mongo-list-users DB=mydb"
	@exit 1
endif
	@echo "Listing users in database: $(DB)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.getUsers()"

.PHONY: mongo-drop-user
mongo-drop-user:
ifndef DB
	@echo "Error: DB and USER variables required."
	@echo "Usage: make mongo-drop-user DB=mydb USER=myuser"
	@exit 1
endif
ifndef USER
	@echo "Error: USER variable required."
	@exit 1
endif
	@echo "Dropping user $(USER) from database $(DB)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.dropUser('$(USER)')"

.PHONY: mongo-grant-role
mongo-grant-role:
ifndef DB
	@echo "Error: DB, USER, and ROLE variables required."
	@echo "Usage: make mongo-grant-role DB=mydb USER=myuser ROLE=readWrite"
	@exit 1
endif
ifndef USER
	@echo "Error: USER variable required."
	@exit 1
endif
ifndef ROLE
	@echo "Error: ROLE variable required."
	@exit 1
endif
	@echo "Granting role $(ROLE) to user $(USER) on database $(DB)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval \
		"db.grantRolesToUser('$(USER)', [{role: '$(ROLE)', db: '$(DB)'}])"

################################################################################
# Performance & Monitoring
################################################################################

.PHONY: mongo-server-status
mongo-server-status:
	@echo "Getting server status..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.serverStatus()"

.PHONY: mongo-db-profiling
mongo-db-profiling:
ifndef DB
	@echo "Error: DB variable required. Usage: make mongo-db-profiling DB=mydb"
	@exit 1
endif
	@echo "Getting profiling data for database: $(DB)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.system.profile.find().limit(10).sort({ts:-1}).pretty()"

.PHONY: mongo-current-ops
mongo-current-ops:
	@echo "Showing current operations..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.currentOp()"

.PHONY: mongo-top
mongo-top:
	@echo "Showing collection usage statistics..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.adminCommand('top')"

.PHONY: mongo-stats
mongo-stats:
	@echo "Getting server statistics..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.stats()"

################################################################################
# Maintenance
################################################################################

.PHONY: mongo-compact
mongo-compact:
ifndef DB
	@echo "Error: DB and COLLECTION variables required."
	@echo "Usage: make mongo-compact DB=mydb COLLECTION=mycollection"
	@exit 1
endif
ifndef COLLECTION
	@echo "Error: COLLECTION variable required."
	@exit 1
endif
	@echo "Compacting collection $(COLLECTION) in database $(DB)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.$(COLLECTION).compact()"

.PHONY: mongo-reindex
mongo-reindex:
ifndef DB
	@echo "Error: DB and COLLECTION variables required."
	@echo "Usage: make mongo-reindex DB=mydb COLLECTION=mycollection"
	@exit 1
endif
ifndef COLLECTION
	@echo "Error: COLLECTION variable required."
	@exit 1
endif
	@echo "Reindexing collection $(COLLECTION) in database $(DB)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.$(COLLECTION).reIndex()"

.PHONY: mongo-validate
mongo-validate:
ifndef DB
	@echo "Error: DB and COLLECTION variables required."
	@echo "Usage: make mongo-validate DB=mydb COLLECTION=mycollection"
	@exit 1
endif
ifndef COLLECTION
	@echo "Error: COLLECTION variable required."
	@exit 1
endif
	@echo "Validating collection $(COLLECTION) in database $(DB)..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh $(DB) --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.$(COLLECTION).validate()"

.PHONY: mongo-repair
mongo-repair:
	@echo "WARNING: This will require downtime. Continue? (Ctrl+C to cancel)"
	@read -p "Press Enter to continue..."
	@echo "Repairing database..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.repairDatabase()"

################################################################################
# CLI & Debug
################################################################################

.PHONY: mongo-cli
mongo-cli:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make mongo-cli CMD='db.version()'"
	@exit 1
endif
	@echo "Running MongoDB command: $(CMD)"
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval '$(CMD)'

.PHONY: mongo-version
mongo-version:
	@echo "Getting MongoDB version..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.version()"

.PHONY: mongo-ping
mongo-ping:
	@echo "Pinging MongoDB server..."
	@MONGODB_ROOT_PASSWORD=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.mongodb-root-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- mongosh --username root --password $$MONGODB_ROOT_PASSWORD --quiet --eval "db.adminCommand('ping')"

.PHONY: mongo-restart
mongo-restart:
	@echo "Restarting MongoDB StatefulSet..."
	kubectl rollout restart statefulset/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(RELEASE_NAME) -n $(NAMESPACE)
