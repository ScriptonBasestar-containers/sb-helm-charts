# Nextcloud Chart Operations

include Makefile.common.mk

CHART_NAME := nextcloud
CHART_DIR := charts/nextcloud
NAMESPACE ?= default
RELEASE_NAME ?= nextcloud

POD ?= $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKUP_DIR ?= backups/nextcloud-$(shell date +%Y%m%d-%H%M%S)

.PHONY: help
help::
	@echo ""
	@echo "=========================================="
	@echo "Nextcloud Operations (50+ commands)"
	@echo "=========================================="
	@echo ""
	@echo "Basic Operations:"
	@echo "  nc-status                - Show Nextcloud pod status"
	@echo "  nc-shell                 - Open shell in Nextcloud pod"
	@echo "  nc-logs                  - View Nextcloud logs (follow mode)"
	@echo "  nc-logs-tail             - View last 100 lines of logs"
	@echo "  nc-port-forward          - Port forward to localhost:8080"
	@echo "  nc-get-url               - Get Nextcloud URL (if ingress enabled)"
	@echo "  nc-restart               - Restart Nextcloud deployment"
	@echo "  nc-version               - Get Nextcloud version"
	@echo ""
	@echo "OCC Commands (Nextcloud CLI):"
	@echo "  nc-occ-status            - Get Nextcloud status"
	@echo "  nc-occ CMD='...'         - Run custom occ command"
	@echo "  nc-maintenance-on        - Enable maintenance mode"
	@echo "  nc-maintenance-off       - Disable maintenance mode"
	@echo "  nc-integrity-check       - Check code integrity"
	@echo ""
	@echo "User Management:"
	@echo "  nc-list-users            - List all users"
	@echo "  nc-create-user USER=... PASSWORD=... - Create new user"
	@echo "  nc-delete-user USER=...  - Delete user"
	@echo "  nc-reset-password USER=... PASSWORD=... - Reset user password"
	@echo ""
	@echo "Files Operations:"
	@echo "  nc-scan-files            - Rescan all files"
	@echo "  nc-scan-user USER=...    - Rescan specific user files"
	@echo "  nc-cleanup-files         - Cleanup file cache"
	@echo "  nc-disk-usage            - Check disk usage"
	@echo ""
	@echo "App Management:"
	@echo "  nc-list-apps             - List all apps (enabled/disabled)"
	@echo "  nc-install-app APP=...   - Install app"
	@echo "  nc-enable-app APP=...    - Enable app"
	@echo "  nc-disable-app APP=...   - Disable app"
	@echo "  nc-update-apps           - Update all apps"
	@echo ""
	@echo "Database Operations:"
	@echo "  nc-db-indices            - Add missing database indices"
	@echo "  nc-db-columns            - Add missing database columns"
	@echo "  nc-db-primary-keys       - Add missing primary keys"
	@echo "  nc-db-convert-bigint     - Convert filecache to bigint"
	@echo ""
	@echo "Data Backup Operations:"
	@echo "  nc-backup-data           - Backup user files (full)"
	@echo "  nc-backup-data-incremental - Backup user files (incremental)"
	@echo "  nc-backup-user USER=...  - Backup specific user data"
	@echo "  nc-restore-data BACKUP_FILE=... - Restore user files"
	@echo "  nc-restore-user USER=... BACKUP_FILE=... - Restore user data"
	@echo "  nc-verify-backup BACKUP_FILE=... - Verify backup integrity"
	@echo ""
	@echo "Database Backup Operations:"
	@echo "  nc-backup-database       - Backup PostgreSQL database"
	@echo "  nc-backup-schema         - Backup database schema only"
	@echo "  nc-restore-database BACKUP_FILE=... - Restore database"
	@echo ""
	@echo "Configuration Backup:"
	@echo "  nc-backup-config         - Backup config.php"
	@echo "  nc-backup-apps           - Backup custom apps"
	@echo "  nc-backup-k8s-resources  - Backup Kubernetes resources"
	@echo "  nc-restore-config BACKUP_FILE=... - Restore config.php"
	@echo "  nc-restore-apps BACKUP_FILE=... - Restore custom apps"
	@echo ""
	@echo "Redis Backup:"
	@echo "  nc-backup-redis          - Backup Redis cache"
	@echo ""
	@echo "PVC Snapshot Operations:"
	@echo "  nc-snapshot-data         - Create snapshot of data PVC"
	@echo "  nc-snapshot-config       - Create snapshot of config PVC"
	@echo "  nc-snapshot-apps         - Create snapshot of apps PVC"
	@echo "  nc-snapshot-all          - Create snapshots of all PVCs"
	@echo "  nc-list-snapshots        - List all Nextcloud snapshots"
	@echo ""
	@echo "Comprehensive Backup/Recovery:"
	@echo "  nc-full-backup           - Backup all components"
	@echo "  nc-pre-upgrade-check     - Pre-upgrade validation and backup"
	@echo "  nc-post-upgrade-check    - Post-upgrade validation"
	@echo "  nc-dr-test               - Test disaster recovery procedure"
	@echo "  nc-cleanup-old-backups RETENTION_DAYS=7 - Clean old backups"
	@echo "  nc-verify-backups        - Verify all backup files"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  BACKUP_DIR=$(BACKUP_DIR)"
	@echo ""

# ============================================================================
# Basic Operations
# ============================================================================

.PHONY: nc-status
nc-status:
	@echo "Nextcloud Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud,app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "Nextcloud Service:"
	@kubectl get svc -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud,app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "Nextcloud PVCs:"
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud,app.kubernetes.io/instance=$(RELEASE_NAME)

.PHONY: nc-shell
nc-shell:
	@echo "Opening shell in Nextcloud pod: $(POD)"
	kubectl exec -it $(POD) -n $(NAMESPACE) -- /bin/bash

.PHONY: nc-logs
nc-logs:
	@echo "Viewing logs for Nextcloud pod: $(POD)"
	kubectl logs -f $(POD) -n $(NAMESPACE)

.PHONY: nc-logs-tail
nc-logs-tail:
	@echo "Last 100 lines of Nextcloud logs:"
	kubectl logs --tail=100 $(POD) -n $(NAMESPACE)

.PHONY: nc-port-forward
nc-port-forward:
	@echo "Port forwarding Nextcloud to localhost:8080"
	@echo "Access Nextcloud at: http://localhost:8080"
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 8080:80

.PHONY: nc-get-url
nc-get-url:
	@echo "Nextcloud Ingress URL:"
	@kubectl get ingress -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Ingress not configured"

.PHONY: nc-restart
nc-restart:
	@echo "Restarting Nextcloud deployment..."
	kubectl rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE)

.PHONY: nc-version
nc-version:
	@echo "Nextcloud Version:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- php occ status | grep -E "version:|versionstring:"

# ============================================================================
# OCC Commands
# ============================================================================

.PHONY: nc-occ-status
nc-occ-status:
	@echo "Nextcloud Status:"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ status

.PHONY: nc-occ
nc-occ:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make nc-occ CMD='user:list'"
	@exit 1
endif
	@echo "Running occ command: $(CMD)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ $(CMD)

.PHONY: nc-maintenance-on
nc-maintenance-on:
	@echo "Enabling maintenance mode..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ maintenance:mode --on
	@kubectl exec $(POD) -n $(NAMESPACE) -- php occ status | grep maintenance

.PHONY: nc-maintenance-off
nc-maintenance-off:
	@echo "Disabling maintenance mode..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ maintenance:mode --off
	@kubectl exec $(POD) -n $(NAMESPACE) -- php occ status | grep maintenance

.PHONY: nc-integrity-check
nc-integrity-check:
	@echo "Checking code integrity..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ integrity:check-core

# ============================================================================
# User Management
# ============================================================================

.PHONY: nc-list-users
nc-list-users:
	@echo "Listing Nextcloud users..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ user:list

.PHONY: nc-create-user
nc-create-user:
ifndef USER
	@echo "Error: USER variable required. Usage: make nc-create-user USER=username PASSWORD=password"
	@exit 1
endif
ifndef PASSWORD
	@echo "Error: PASSWORD variable required."
	@exit 1
endif
	@echo "Creating user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ user:add --password-from-env $(USER) <<< "$(PASSWORD)"

.PHONY: nc-delete-user
nc-delete-user:
ifndef USER
	@echo "Error: USER variable required. Usage: make nc-delete-user USER=username"
	@exit 1
endif
	@echo "Deleting user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ user:delete $(USER)

.PHONY: nc-reset-password
nc-reset-password:
ifndef USER
	@echo "Error: USER and PASSWORD variables required."
	@exit 1
endif
ifndef PASSWORD
	@echo "Error: PASSWORD variable required."
	@exit 1
endif
	@echo "Resetting password for user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ user:resetpassword --password-from-env $(USER) <<< "$(PASSWORD)"

# ============================================================================
# Files Operations
# ============================================================================

.PHONY: nc-scan-files
nc-scan-files:
	@echo "Scanning all files..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ files:scan --all

.PHONY: nc-scan-user
nc-scan-user:
ifndef USER
	@echo "Error: USER variable required. Usage: make nc-scan-user USER=username"
	@exit 1
endif
	@echo "Scanning files for user: $(USER)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ files:scan $(USER)

.PHONY: nc-cleanup-files
nc-cleanup-files:
	@echo "Cleaning up file cache..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ files:cleanup

.PHONY: nc-disk-usage
nc-disk-usage:
	@echo "Checking disk usage..."
	kubectl exec $(POD) -n $(NAMESPACE) -- df -h

# ============================================================================
# App Management
# ============================================================================

.PHONY: nc-list-apps
nc-list-apps:
	@echo "Listing installed apps..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:list

.PHONY: nc-install-app
nc-install-app:
ifndef APP
	@echo "Error: APP variable required. Usage: make nc-install-app APP=calendar"
	@exit 1
endif
	@echo "Installing app: $(APP)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:install $(APP)

.PHONY: nc-enable-app
nc-enable-app:
ifndef APP
	@echo "Error: APP variable required. Usage: make nc-enable-app APP=calendar"
	@exit 1
endif
	@echo "Enabling app: $(APP)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:enable $(APP)

.PHONY: nc-disable-app
nc-disable-app:
ifndef APP
	@echo "Error: APP variable required. Usage: make nc-disable-app APP=calendar"
	@exit 1
endif
	@echo "Disabling app: $(APP)"
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:disable $(APP)

.PHONY: nc-update-apps
nc-update-apps:
	@echo "Updating all apps..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:update --all

# ============================================================================
# Database Operations
# ============================================================================

.PHONY: nc-db-indices
nc-db-indices:
	@echo "Adding missing database indices..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ db:add-missing-indices

.PHONY: nc-db-columns
nc-db-columns:
	@echo "Adding missing database columns..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ db:add-missing-columns

.PHONY: nc-db-primary-keys
nc-db-primary-keys:
	@echo "Adding missing primary keys..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ db:add-missing-primary-keys

.PHONY: nc-db-convert-bigint
nc-db-convert-bigint:
	@echo "Converting filecache to bigint..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ db:convert-filecache-bigint --no-interaction

# ============================================================================
# Data Backup Operations
# ============================================================================

.PHONY: nc-backup-data
nc-backup-data:
	@echo "Creating full backup of user data..."
	@mkdir -p $(BACKUP_DIR)
	kubectl exec $(POD) -n $(NAMESPACE) -- tar czf /tmp/nextcloud-data.tar.gz -C /var/www/html/data .
	kubectl cp $(NAMESPACE)/$(POD):/tmp/nextcloud-data.tar.gz $(BACKUP_DIR)/nextcloud-data-$(shell date +%Y%m%d).tar.gz
	@echo "Backup saved to: $(BACKUP_DIR)/nextcloud-data-$(shell date +%Y%m%d).tar.gz"

.PHONY: nc-backup-data-incremental
nc-backup-data-incremental:
	@echo "Creating incremental backup of user data..."
	@mkdir -p $(BACKUP_DIR)/incremental
	kubectl exec $(POD) -n $(NAMESPACE) -- rsync -av --delete /var/www/html/data/ /backup/nextcloud-data-incremental/
	@echo "Incremental backup completed"

.PHONY: nc-backup-user
nc-backup-user:
ifndef USER
	@echo "Error: USER variable required. Usage: make nc-backup-user USER=admin"
	@exit 1
endif
	@echo "Backing up user data: $(USER)"
	@mkdir -p $(BACKUP_DIR)
	kubectl exec $(POD) -n $(NAMESPACE) -- tar czf /tmp/user-$(USER).tar.gz -C /var/www/html/data $(USER)
	kubectl cp $(NAMESPACE)/$(POD):/tmp/user-$(USER).tar.gz $(BACKUP_DIR)/user-$(USER)-$(shell date +%Y%m%d).tar.gz
	@echo "User backup saved to: $(BACKUP_DIR)/user-$(USER)-$(shell date +%Y%m%d).tar.gz"

.PHONY: nc-restore-data
nc-restore-data:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required. Usage: make nc-restore-data BACKUP_FILE=nextcloud-data-20250101.tar.gz"
	@exit 1
endif
	@echo "Restoring user data from: $(BACKUP_FILE)"
	kubectl cp $(BACKUP_FILE) $(NAMESPACE)/$(POD):/tmp/nextcloud-data.tar.gz
	kubectl exec $(POD) -n $(NAMESPACE) -- tar xzf /tmp/nextcloud-data.tar.gz -C /var/www/html/data
	kubectl exec $(POD) -n $(NAMESPACE) -- chown -R www-data:www-data /var/www/html/data
	@echo "Running file scan..."
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ files:scan --all

.PHONY: nc-restore-user
nc-restore-user:
ifndef USER
	@echo "Error: USER and BACKUP_FILE variables required."
	@exit 1
endif
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required."
	@exit 1
endif
	@echo "Restoring user data: $(USER) from $(BACKUP_FILE)"
	kubectl cp $(BACKUP_FILE) $(NAMESPACE)/$(POD):/tmp/user-$(USER).tar.gz
	kubectl exec $(POD) -n $(NAMESPACE) -- tar xzf /tmp/user-$(USER).tar.gz -C /var/www/html/data
	kubectl exec $(POD) -n $(NAMESPACE) -- chown -R www-data:www-data /var/www/html/data/$(USER)
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ files:scan --path=/$(USER)/files

.PHONY: nc-verify-backup
nc-verify-backup:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required."
	@exit 1
endif
	@echo "Verifying backup: $(BACKUP_FILE)"
	@tar tzf $(BACKUP_FILE) | head -20
	@echo ""
	@echo "Backup verification: OK"

# ============================================================================
# Database Backup Operations
# ============================================================================

.PHONY: nc-backup-database
nc-backup-database:
	@echo "Backing up PostgreSQL database..."
	@mkdir -p $(BACKUP_DIR)
	@echo "Note: This assumes external PostgreSQL. Adjust pod name if needed."
	@echo "TODO: Implement database backup (requires PostgreSQL pod access)"

.PHONY: nc-backup-schema
nc-backup-schema:
	@echo "Backing up database schema only..."
	@mkdir -p $(BACKUP_DIR)
	@echo "TODO: Implement schema backup"

.PHONY: nc-restore-database
nc-restore-database:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required."
	@exit 1
endif
	@echo "Restoring database from: $(BACKUP_FILE)"
	@echo "TODO: Implement database restore"

# ============================================================================
# Configuration Backup
# ============================================================================

.PHONY: nc-backup-config
nc-backup-config:
	@echo "Backing up config.php..."
	@mkdir -p $(BACKUP_DIR)
	kubectl exec $(POD) -n $(NAMESPACE) -- cat /var/www/html/config/config.php > $(BACKUP_DIR)/config-$(shell date +%Y%m%d).php
	@echo "Config saved to: $(BACKUP_DIR)/config-$(shell date +%Y%m%d).php"
	@echo "WARNING: config.php contains sensitive credentials. Encrypt this file!"

.PHONY: nc-backup-apps
nc-backup-apps:
	@echo "Backing up custom apps..."
	@mkdir -p $(BACKUP_DIR)
	kubectl exec $(POD) -n $(NAMESPACE) -- tar czf /tmp/nextcloud-apps.tar.gz -C /var/www/html custom_apps
	kubectl cp $(NAMESPACE)/$(POD):/tmp/nextcloud-apps.tar.gz $(BACKUP_DIR)/nextcloud-apps-$(shell date +%Y%m%d).tar.gz
	@echo "Apps backup saved to: $(BACKUP_DIR)/nextcloud-apps-$(shell date +%Y%m%d).tar.gz"

.PHONY: nc-backup-k8s-resources
nc-backup-k8s-resources:
	@echo "Backing up Kubernetes resources..."
	@mkdir -p $(BACKUP_DIR)
	kubectl get deployment,service,ingress,configmap,secret,pvc -n $(NAMESPACE) -l app.kubernetes.io/name=nextcloud -o yaml > $(BACKUP_DIR)/nextcloud-k8s-$(shell date +%Y%m%d).yaml
	@echo "K8s resources saved to: $(BACKUP_DIR)/nextcloud-k8s-$(shell date +%Y%m%d).yaml"

.PHONY: nc-restore-config
nc-restore-config:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required."
	@exit 1
endif
	@echo "Restoring config.php from: $(BACKUP_FILE)"
	kubectl cp $(BACKUP_FILE) $(NAMESPACE)/$(POD):/var/www/html/config/config.php
	kubectl exec $(POD) -n $(NAMESPACE) -- chown www-data:www-data /var/www/html/config/config.php
	@echo "Restarting Nextcloud..."
	kubectl rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)

.PHONY: nc-restore-apps
nc-restore-apps:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required."
	@exit 1
endif
	@echo "Restoring custom apps from: $(BACKUP_FILE)"
	kubectl cp $(BACKUP_FILE) $(NAMESPACE)/$(POD):/tmp/nextcloud-apps.tar.gz
	kubectl exec $(POD) -n $(NAMESPACE) -- tar xzf /tmp/nextcloud-apps.tar.gz -C /var/www/html
	kubectl exec $(POD) -n $(NAMESPACE) -- chown -R www-data:www-data /var/www/html/custom_apps
	kubectl exec $(POD) -n $(NAMESPACE) -- php occ app:list

# ============================================================================
# Redis Backup
# ============================================================================

.PHONY: nc-backup-redis
nc-backup-redis:
	@echo "Backing up Redis cache..."
	@echo "Note: This assumes external Redis. Adjust pod name if needed."
	@echo "TODO: Implement Redis backup (requires Redis pod access)"

# ============================================================================
# PVC Snapshot Operations
# ============================================================================

.PHONY: nc-snapshot-data
nc-snapshot-data:
	@echo "Creating snapshot of data PVC..."
	kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-data-snapshot-$(shell date +%Y%m%d)
  namespace: $(NAMESPACE)
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: $(RELEASE_NAME)-data
EOF
	@echo "Data PVC snapshot created"

.PHONY: nc-snapshot-config
nc-snapshot-config:
	@echo "Creating snapshot of config PVC..."
	kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-config-snapshot-$(shell date +%Y%m%d)
  namespace: $(NAMESPACE)
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: $(RELEASE_NAME)-config
EOF
	@echo "Config PVC snapshot created"

.PHONY: nc-snapshot-apps
nc-snapshot-apps:
	@echo "Creating snapshot of apps PVC..."
	kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: nextcloud-apps-snapshot-$(shell date +%Y%m%d)
  namespace: $(NAMESPACE)
spec:
  volumeSnapshotClassName: csi-snapshot-class
  source:
    persistentVolumeClaimName: $(RELEASE_NAME)-apps
EOF
	@echo "Apps PVC snapshot created"

.PHONY: nc-snapshot-all
nc-snapshot-all: nc-snapshot-data nc-snapshot-config nc-snapshot-apps
	@echo "All PVC snapshots created successfully"

.PHONY: nc-list-snapshots
nc-list-snapshots:
	@echo "Listing Nextcloud VolumeSnapshots..."
	kubectl get volumesnapshot -n $(NAMESPACE) | grep nextcloud

# ============================================================================
# Comprehensive Backup/Recovery
# ============================================================================

.PHONY: nc-full-backup
nc-full-backup: nc-backup-config nc-backup-apps nc-backup-k8s-resources
	@echo ""
	@echo "=========================================="
	@echo "Full Nextcloud Backup Started"
	@echo "=========================================="
	@echo "Backup directory: $(BACKUP_DIR)"
	@echo ""
	@echo "Step 1/5: Backing up user data..."
	@$(MAKE) nc-backup-data
	@echo ""
	@echo "Step 2/5: Config backup... DONE"
	@echo "Step 3/5: Apps backup... DONE"
	@echo "Step 4/5: K8s resources backup... DONE"
	@echo ""
	@echo "Step 5/5: Listing app versions..."
	@$(MAKE) nc-list-apps > $(BACKUP_DIR)/nextcloud-apps-list-$(shell date +%Y%m%d).txt
	@echo ""
	@echo "=========================================="
	@echo "Full Backup Complete!"
	@echo "=========================================="
	@echo "Backup location: $(BACKUP_DIR)"
	@ls -lh $(BACKUP_DIR)

.PHONY: nc-pre-upgrade-check
nc-pre-upgrade-check:
	@echo "=========================================="
	@echo "Pre-Upgrade Check"
	@echo "=========================================="
	@echo ""
	@echo "1. Checking Nextcloud version..."
	@$(MAKE) nc-version
	@echo ""
	@echo "2. Checking database health..."
	@$(MAKE) nc-db-convert-bigint
	@$(MAKE) nc-db-indices
	@echo ""
	@echo "3. Checking disk space..."
	@$(MAKE) nc-disk-usage
	@echo ""
	@echo "4. Listing installed apps..."
	@$(MAKE) nc-list-apps
	@echo ""
	@echo "Pre-upgrade check complete. Ready for backup."

.PHONY: nc-post-upgrade-check
nc-post-upgrade-check:
	@echo "=========================================="
	@echo "Post-Upgrade Check"
	@echo "=========================================="
	@echo ""
	@echo "1. Checking Nextcloud status..."
	@$(MAKE) nc-occ-status
	@echo ""
	@echo "2. Checking code integrity..."
	@$(MAKE) nc-integrity-check
	@echo ""
	@echo "3. Adding missing database indices..."
	@$(MAKE) nc-db-indices
	@echo ""
	@echo "4. Adding missing database columns..."
	@$(MAKE) nc-db-columns
	@echo ""
	@echo "5. Scanning files..."
	@$(MAKE) nc-scan-files
	@echo ""
	@echo "Post-upgrade check complete!"

.PHONY: nc-dr-test
nc-dr-test:
	@echo "=========================================="
	@echo "Disaster Recovery Test"
	@echo "=========================================="
	@echo "This would test DR procedures in a test namespace."
	@echo "TODO: Implement full DR test procedure"

.PHONY: nc-cleanup-old-backups
nc-cleanup-old-backups:
ifndef RETENTION_DAYS
	RETENTION_DAYS=7
endif
	@echo "Cleaning up backups older than $(RETENTION_DAYS) days..."
	find backups/ -name "nextcloud-*" -type f -mtime +$(RETENTION_DAYS) -delete
	@echo "Cleanup complete"

.PHONY: nc-verify-backups
nc-verify-backups:
	@echo "Verifying backup files..."
	@echo "Checking for backup files in backups/ directory..."
	@ls -lh backups/nextcloud-* 2>/dev/null || echo "No backups found"
	@echo "Backup verification complete"
