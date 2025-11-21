# pgAdmin Operations Makefile
# Usage: make -f make/ops/pgadmin.mk <target>

CHART_NAME := pgadmin
NAMESPACE := default
RELEASE_NAME := pgadmin
POD_NAME := $(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

.PHONY: help
help:
	@echo "pgAdmin Operations"
	@echo ""
	@echo "Access & Credentials:"
	@echo "  pgadmin-get-password       Get admin password"
	@echo "  pgadmin-port-forward       Port forward to localhost:8080"
	@echo ""
	@echo "Server Management:"
	@echo "  pgadmin-list-servers       List configured servers"
	@echo "  pgadmin-add-server         Add server (requires SERVER_CONFIG)"
	@echo "  pgadmin-test-connection    Test PostgreSQL connection"
	@echo ""
	@echo "User Management:"
	@echo "  pgadmin-list-users         List all users"
	@echo "  pgadmin-create-user        Create user (requires EMAIL PASSWORD)"
	@echo ""
	@echo "Configuration:"
	@echo "  pgadmin-get-config         Get pgAdmin configuration"
	@echo "  pgadmin-export-servers     Export servers.json"
	@echo ""
	@echo "Database Operations:"
	@echo "  pgadmin-backup-metadata    Backup pgAdmin metadata DB"
	@echo "  pgadmin-restore-metadata   Restore metadata (requires FILE)"
	@echo ""
	@echo "Monitoring:"
	@echo "  pgadmin-health             Check health status"
	@echo "  pgadmin-version            Get pgAdmin version"
	@echo "  pgadmin-logs               View logs"
	@echo "  pgadmin-shell              Open shell"
	@echo ""
	@echo "Operations:"
	@echo "  pgadmin-restart            Restart deployment"
	@echo ""

# Access & Credentials
.PHONY: pgadmin-get-password
pgadmin-get-password:
	@echo "Admin password:"
	@kubectl get secret -n $(NAMESPACE) $(CHART_NAME) -o jsonpath='{.data.password}' | base64 -d
	@echo ""

.PHONY: pgadmin-port-forward
pgadmin-port-forward:
	@echo "Forwarding pgAdmin to http://localhost:8080"
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 8080:80

# Server Management
.PHONY: pgadmin-list-servers
pgadmin-list-servers:
	@echo "Configured servers:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -- cat /pgadmin4/servers.json 2>/dev/null || echo "No servers configured"

.PHONY: pgadmin-add-server
pgadmin-add-server:
	@echo "Adding server requires updating servers ConfigMap"
	@echo "Use: kubectl edit configmap -n $(NAMESPACE) $(CHART_NAME)-servers"

.PHONY: pgadmin-test-connection
pgadmin-test-connection:
ifndef HOST
	@echo "Error: HOST is required"
	@echo "Usage: make -f make/ops/pgadmin.mk pgadmin-test-connection HOST=postgresql.default.svc.cluster.local"
	@exit 1
endif
	@echo "Testing PostgreSQL connection to $(HOST)..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- sh -c "apt-get update -qq && apt-get install -y -qq postgresql-client > /dev/null 2>&1 && pg_isready -h $(HOST) -p $(PORT:-5432)"

# User Management
.PHONY: pgadmin-list-users
pgadmin-list-users:
	@echo "Listing pgAdmin users (requires querying SQLite DB):"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- sqlite3 /var/lib/pgadmin/pgadmin4.db "SELECT id, email, active FROM user;"

.PHONY: pgadmin-create-user
pgadmin-create-user:
ifndef EMAIL
	@echo "Error: EMAIL and PASSWORD are required"
	@echo "Usage: make -f make/ops/pgadmin.mk pgadmin-create-user EMAIL=user@example.com PASSWORD=pass"
	@exit 1
endif
	@echo "Creating user via web API is recommended"
	@echo "Use pgAdmin UI: File -> Preferences -> User Management"

# Configuration
.PHONY: pgadmin-get-config
pgadmin-get-config:
	@echo "pgAdmin configuration:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- env | grep PGADMIN_

.PHONY: pgadmin-export-servers
pgadmin-export-servers:
	@echo "Exporting servers.json..."
	@mkdir -p tmp/pgadmin-backups
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- cat /pgadmin4/servers.json > tmp/pgadmin-backups/servers.json
	@echo "Saved to: tmp/pgadmin-backups/servers.json"

# Database Operations
.PHONY: pgadmin-backup-metadata
pgadmin-backup-metadata:
	@echo "Backing up pgAdmin metadata database..."
	@mkdir -p tmp/pgadmin-backups
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- tar -czf /tmp/pgadmin-backup.tar.gz /var/lib/pgadmin
	kubectl cp $(NAMESPACE)/$(POD_NAME):/tmp/pgadmin-backup.tar.gz tmp/pgadmin-backups/pgadmin-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz
	@echo "Backup saved to: tmp/pgadmin-backups/"

.PHONY: pgadmin-restore-metadata
pgadmin-restore-metadata:
ifndef FILE
	@echo "Error: FILE is required"
	@echo "Usage: make -f make/ops/pgadmin.mk pgadmin-restore-metadata FILE=tmp/pgadmin-backups/pgadmin-backup.tar.gz"
	@exit 1
endif
	@echo "Restoring pgAdmin metadata from $(FILE)..."
	kubectl cp $(FILE) $(NAMESPACE)/$(POD_NAME):/tmp/restore.tar.gz
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- sh -c "tar -xzf /tmp/restore.tar.gz -C / && rm /tmp/restore.tar.gz"
	@echo "Restore complete. Restart pgAdmin for changes to take effect."

# Monitoring
.PHONY: pgadmin-health
pgadmin-health:
	@echo "Checking pgAdmin health..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -q -O- http://localhost:80/misc/ping

.PHONY: pgadmin-version
pgadmin-version:
	@echo "pgAdmin version:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- python3 -c "import pgadmin4; print(pgadmin4.__version__)" 2>/dev/null || echo "Unable to determine version"

.PHONY: pgadmin-logs
pgadmin-logs:
	kubectl logs -n $(NAMESPACE) $(POD_NAME) --tail=100 -f

.PHONY: pgadmin-shell
pgadmin-shell:
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- /bin/sh

# Operations
.PHONY: pgadmin-restart
pgadmin-restart:
	kubectl rollout restart -n $(NAMESPACE) deployment/$(CHART_NAME)
	kubectl rollout status -n $(NAMESPACE) deployment/$(CHART_NAME)
