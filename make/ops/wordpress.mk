# ==============================================================================
# WordPress Operational Makefile
# ==============================================================================
# This Makefile provides comprehensive operational commands for WordPress management,
# including backup, restore, database operations, plugin/theme management, monitoring,
# and troubleshooting.
#
# Usage: make -f make/ops/wordpress.mk <target>
# ==============================================================================

# Chart configuration
CHART_NAME := wordpress
NAMESPACE ?= wordpress
RELEASE_NAME ?= wordpress
BACKUP_DIR ?= backups

# Kubernetes configuration
KUBECTL := kubectl
POD_SELECTOR := app.kubernetes.io/name=$(CHART_NAME)

# Helper function to get pod name
GET_POD = $(KUBECTL) get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'

# ==============================================================================
# Basic Operations
# ==============================================================================

.PHONY: wp-status
wp-status:
	@echo "==> WordPress pod status"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@$(KUBECTL) get svc -n $(NAMESPACE) -l $(POD_SELECTOR)

.PHONY: wp-version
wp-version:
	@echo "==> WordPress version"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root

.PHONY: wp-php-version
wp-php-version:
	@echo "==> PHP version"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- php -v

.PHONY: wp-logs
wp-logs:
	@echo "==> WordPress logs (last 100 lines)"
	@$(KUBECTL) logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=100

.PHONY: wp-logs-follow
wp-logs-follow:
	@echo "==> Following WordPress logs (Ctrl+C to stop)"
	@$(KUBECTL) logs -n $(NAMESPACE) -l $(POD_SELECTOR) -f

.PHONY: wp-shell
wp-shell:
	@echo "==> Accessing WordPress shell"
	@$(KUBECTL) exec -it -n $(NAMESPACE) $$($(GET_POD)) -- /bin/bash

.PHONY: wp-restart
wp-restart:
	@echo "==> Restarting WordPress deployment"
	@$(KUBECTL) rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	@$(KUBECTL) rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE)

.PHONY: wp-port-forward
wp-port-forward:
	@echo "==> Port-forwarding WordPress to localhost:8080"
	@echo "    Access WordPress at: http://localhost:8080"
	@echo "    Press Ctrl+C to stop"
	@$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 8080:80

# ==============================================================================
# Database Operations
# ==============================================================================

.PHONY: wp-db-check
wp-db-check:
	@echo "==> Testing database connectivity"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db check --allow-root

.PHONY: wp-db-version
wp-db-version:
	@echo "==> WordPress database version"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root --extra

.PHONY: wp-db-size
wp-db-size:
	@echo "==> WordPress database size"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db size --allow-root

.PHONY: wp-db-table-count
wp-db-table-count:
	@echo "==> WordPress database table count"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db query "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = DATABASE();" --allow-root

.PHONY: wp-db-list-tables
wp-db-list-tables:
	@echo "==> WordPress database tables"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db tables --allow-root

.PHONY: wp-db-shell
wp-db-shell:
	@echo "==> Accessing MySQL shell"
	@$(KUBECTL) exec -it -n $(NAMESPACE) $$($(GET_POD)) -- wp db cli --allow-root

.PHONY: wp-db-optimize
wp-db-optimize:
	@echo "==> Optimizing WordPress database"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db optimize --allow-root

.PHONY: wp-db-repair
wp-db-repair:
	@echo "==> Repairing WordPress database"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db repair --allow-root

.PHONY: wp-db-upgrade
wp-db-upgrade:
	@echo "==> Upgrading WordPress database"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core update-db --allow-root

# ==============================================================================
# WordPress Management (WP-CLI)
# ==============================================================================

.PHONY: wp-list-plugins
wp-list-plugins:
	@echo "==> Installed WordPress plugins"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin list --allow-root

.PHONY: wp-plugin-activate
wp-plugin-activate:
	@test -n "$(PLUGIN)" || (echo "Error: PLUGIN parameter required (e.g., PLUGIN=woocommerce)"; exit 1)
	@echo "==> Activating plugin: $(PLUGIN)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin activate $(PLUGIN) --allow-root

.PHONY: wp-plugin-deactivate
wp-plugin-deactivate:
	@test -n "$(PLUGIN)" || (echo "Error: PLUGIN parameter required (e.g., PLUGIN=woocommerce)"; exit 1)
	@echo "==> Deactivating plugin: $(PLUGIN)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin deactivate $(PLUGIN) --allow-root

.PHONY: wp-plugin-update
wp-plugin-update:
	@test -n "$(PLUGIN)" || (echo "Error: PLUGIN parameter required (e.g., PLUGIN=woocommerce)"; exit 1)
	@echo "==> Updating plugin: $(PLUGIN)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin update $(PLUGIN) --allow-root

.PHONY: wp-plugin-update-all
wp-plugin-update-all:
	@echo "==> Updating all WordPress plugins"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin update --all --allow-root

.PHONY: wp-list-themes
wp-list-themes:
	@echo "==> Installed WordPress themes"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp theme list --allow-root

.PHONY: wp-theme-activate
wp-theme-activate:
	@test -n "$(THEME)" || (echo "Error: THEME parameter required (e.g., THEME=twentytwentyfour)"; exit 1)
	@echo "==> Activating theme: $(THEME)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp theme activate $(THEME) --allow-root

.PHONY: wp-theme-update
wp-theme-update:
	@test -n "$(THEME)" || (echo "Error: THEME parameter required (e.g., THEME=twentytwentyfour)"; exit 1)
	@echo "==> Updating theme: $(THEME)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp theme update $(THEME) --allow-root

.PHONY: wp-theme-update-all
wp-theme-update-all:
	@echo "==> Updating all WordPress themes"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp theme update --all --allow-root

.PHONY: wp-list-users
wp-list-users:
	@echo "==> WordPress users"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp user list --allow-root

.PHONY: wp-create-user
wp-create-user:
	@test -n "$(USER)" || (echo "Error: USER parameter required"; exit 1)
	@test -n "$(EMAIL)" || (echo "Error: EMAIL parameter required"; exit 1)
	@echo "==> Creating WordPress user: $(USER)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp user create $(USER) $(EMAIL) --role=$(or $(ROLE),subscriber) --allow-root

.PHONY: wp-delete-user
wp-delete-user:
	@test -n "$(USER)" || (echo "Error: USER parameter required"; exit 1)
	@echo "==> Deleting WordPress user: $(USER)"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp user delete $(USER) --yes --allow-root

.PHONY: wp-list-posts
wp-list-posts:
	@echo "==> WordPress posts"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp post list --allow-root

.PHONY: wp-list-pages
wp-list-pages:
	@echo "==> WordPress pages"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp post list --post_type=page --allow-root

.PHONY: wp-media-regenerate
wp-media-regenerate:
	@echo "==> Regenerating WordPress media thumbnails"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp media regenerate --yes --allow-root

# ==============================================================================
# Maintenance Mode
# ==============================================================================

.PHONY: wp-enable-maintenance
wp-enable-maintenance:
	@echo "==> Enabling WordPress maintenance mode"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp maintenance-mode activate --allow-root

.PHONY: wp-disable-maintenance
wp-disable-maintenance:
	@echo "==> Disabling WordPress maintenance mode"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp maintenance-mode deactivate --allow-root

.PHONY: wp-maintenance-status
wp-maintenance-status:
	@echo "==> WordPress maintenance mode status"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp maintenance-mode status --allow-root

# ==============================================================================
# Backup Operations
# ==============================================================================

.PHONY: wp-backup-content-full
wp-backup-content-full:
	@echo "==> Creating full WordPress content backup"
	@mkdir -p $(BACKUP_DIR)
	@POD_NAME=$$($(GET_POD)); \
	TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_FILE="$(BACKUP_DIR)/wordpress-content-full-$$TIMESTAMP.tar.gz"; \
	echo "Creating tar archive in pod..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- tar czf /tmp/wordpress-content-backup.tar.gz \
		-C /var/www/html wp-content wp-config.php; \
	echo "Copying backup to local machine..."; \
	$(KUBECTL) cp $(NAMESPACE)/$$POD_NAME:/tmp/wordpress-content-backup.tar.gz $$BACKUP_FILE; \
	echo "Cleaning up temporary file in pod..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- rm /tmp/wordpress-content-backup.tar.gz; \
	echo "Backup created: $$BACKUP_FILE"; \
	ls -lh $$BACKUP_FILE

.PHONY: wp-backup-content-incremental
wp-backup-content-incremental:
	@echo "==> Creating incremental WordPress content backup"
	@mkdir -p $(BACKUP_DIR)
	@POD_NAME=$$($(GET_POD)); \
	TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR_LOCAL="$(BACKUP_DIR)/wordpress-content-incremental-$$TIMESTAMP"; \
	echo "Copying WordPress content from pod..."; \
	$(KUBECTL) cp $(NAMESPACE)/$$POD_NAME:/var/www/html/wp-content $$BACKUP_DIR_LOCAL/wp-content; \
	$(KUBECTL) cp $(NAMESPACE)/$$POD_NAME:/var/www/html/wp-config.php $$BACKUP_DIR_LOCAL/wp-config.php; \
	echo "Backup created: $$BACKUP_DIR_LOCAL"; \
	du -sh $$BACKUP_DIR_LOCAL

.PHONY: wp-backup-mysql
wp-backup-mysql:
	@echo "==> Creating MySQL database backup"
	@mkdir -p $(BACKUP_DIR)
	@POD_NAME=$$($(GET_POD)); \
	TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_FILE="$(BACKUP_DIR)/wordpress-mysql-$$TIMESTAMP.sql.gz"; \
	echo "Dumping database..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- wp db export - --allow-root | gzip > $$BACKUP_FILE; \
	echo "Backup created: $$BACKUP_FILE"; \
	ls -lh $$BACKUP_FILE

.PHONY: wp-backup-config
wp-backup-config:
	@echo "==> Backing up Kubernetes configuration"
	@mkdir -p $(BACKUP_DIR)
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	CONFIG_DIR="$(BACKUP_DIR)/wordpress-config-$$TIMESTAMP"; \
	mkdir -p $$CONFIG_DIR; \
	echo "Exporting ConfigMaps..."; \
	$(KUBECTL) get configmap -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/configmaps.yaml; \
	echo "Exporting Secrets..."; \
	$(KUBECTL) get secret -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/secrets.yaml; \
	echo "Exporting Deployment..."; \
	$(KUBECTL) get deployment -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/deployment.yaml; \
	echo "Exporting Service..."; \
	$(KUBECTL) get service -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/service.yaml; \
	echo "Exporting Ingress..."; \
	$(KUBECTL) get ingress -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/ingress.yaml 2>/dev/null || true; \
	echo "Exporting PVC..."; \
	$(KUBECTL) get pvc -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/pvc.yaml; \
	echo "Exporting ServiceAccount..."; \
	$(KUBECTL) get serviceaccount -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/serviceaccount.yaml; \
	echo "Exporting RBAC resources..."; \
	$(KUBECTL) get role -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/role.yaml 2>/dev/null || true; \
	$(KUBECTL) get rolebinding -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > $$CONFIG_DIR/rolebinding.yaml 2>/dev/null || true; \
	echo "Exporting Helm values..."; \
	helm get values $(RELEASE_NAME) -n $(NAMESPACE) > $$CONFIG_DIR/helm-values.yaml 2>/dev/null || true; \
	echo "Creating archive..."; \
	tar czf $$CONFIG_DIR.tar.gz -C $(BACKUP_DIR) wordpress-config-$$TIMESTAMP; \
	rm -rf $$CONFIG_DIR; \
	echo "Configuration backup created: $$CONFIG_DIR.tar.gz"; \
	ls -lh $$CONFIG_DIR.tar.gz

.PHONY: wp-snapshot-content
wp-snapshot-content:
	@echo "==> Creating PVC snapshot"
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	SNAPSHOT_NAME="wordpress-content-snapshot-$$TIMESTAMP"; \
	PVC_NAME=$$($(KUBECTL) get pvc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Creating VolumeSnapshot: $$SNAPSHOT_NAME for PVC: $$PVC_NAME"; \
	cat <<EOF | $(KUBECTL) apply -f -; \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $$SNAPSHOT_NAME; \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $$PVC_NAME; \
	EOF \
	echo "VolumeSnapshot created: $$SNAPSHOT_NAME"; \
	echo "Check status: kubectl get volumesnapshot $$SNAPSHOT_NAME -n $(NAMESPACE)"

.PHONY: wp-list-snapshots
wp-list-snapshots:
	@echo "==> WordPress content snapshots"
	@$(KUBECTL) get volumesnapshot -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || \
		$(KUBECTL) get volumesnapshot -n $(NAMESPACE) | grep wordpress-content || \
		echo "No snapshots found"

.PHONY: wp-full-backup
wp-full-backup:
	@echo "==> Creating full WordPress backup (content + database + config)"
	@$(MAKE) -f make/ops/wordpress.mk wp-backup-content-full
	@echo ""
	@$(MAKE) -f make/ops/wordpress.mk wp-backup-mysql
	@echo ""
	@$(MAKE) -f make/ops/wordpress.mk wp-backup-config
	@echo ""
	@echo "==> Full backup completed"
	@ls -lh $(BACKUP_DIR)/wordpress-*

# ==============================================================================
# Restore Operations
# ==============================================================================

.PHONY: wp-restore-content
wp-restore-content:
	@test -n "$(BACKUP_FILE)" || (echo "Error: BACKUP_FILE parameter required"; exit 1)
	@test -f "$(BACKUP_FILE)" || (echo "Error: Backup file not found: $(BACKUP_FILE)"; exit 1)
	@echo "==> Restoring WordPress content from: $(BACKUP_FILE)"
	@POD_NAME=$$($(GET_POD)); \
	echo "Copying backup to pod..."; \
	$(KUBECTL) cp $(BACKUP_FILE) $(NAMESPACE)/$$POD_NAME:/tmp/wordpress-content-backup.tar.gz; \
	echo "Extracting backup in pod..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- tar xzf /tmp/wordpress-content-backup.tar.gz -C /var/www/html; \
	echo "Fixing file permissions..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- chown -R www-data:www-data /var/www/html/wp-content; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- chown www-data:www-data /var/www/html/wp-config.php; \
	echo "Cleaning up temporary file..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- rm /tmp/wordpress-content-backup.tar.gz; \
	echo "Restarting WordPress..."; \
	$(KUBECTL) rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE); \
	echo "Content restore completed"

.PHONY: wp-restore-mysql
wp-restore-mysql:
	@test -n "$(BACKUP_FILE)" || (echo "Error: BACKUP_FILE parameter required"; exit 1)
	@test -f "$(BACKUP_FILE)" || (echo "Error: Backup file not found: $(BACKUP_FILE)"; exit 1)
	@echo "==> Restoring MySQL database from: $(BACKUP_FILE)"
	@POD_NAME=$$($(GET_POD)); \
	echo "Copying backup to pod..."; \
	$(KUBECTL) cp $(BACKUP_FILE) $(NAMESPACE)/$$POD_NAME:/tmp/wordpress-mysql-backup.sql.gz; \
	echo "Restoring database..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- bash -c "zcat /tmp/wordpress-mysql-backup.sql.gz | wp db import - --allow-root"; \
	echo "Cleaning up temporary file..."; \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- rm /tmp/wordpress-mysql-backup.sql.gz; \
	echo "Restarting WordPress..."; \
	$(KUBECTL) rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE); \
	echo "Database restore completed"

.PHONY: wp-restore-config
wp-restore-config:
	@test -n "$(BACKUP_FILE)" || (echo "Error: BACKUP_FILE parameter required"; exit 1)
	@test -f "$(BACKUP_FILE)" || (echo "Error: Backup file not found: $(BACKUP_FILE)"; exit 1)
	@echo "==> Restoring Kubernetes configuration from: $(BACKUP_FILE)"
	@mkdir -p /tmp/wordpress-config-restore; \
	tar xzf $(BACKUP_FILE) -C /tmp/wordpress-config-restore; \
	CONFIG_DIR=$$(ls -d /tmp/wordpress-config-restore/wordpress-config-* | head -1); \
	echo "Applying ConfigMaps..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/configmaps.yaml 2>/dev/null || true; \
	echo "Applying Secrets..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/secrets.yaml 2>/dev/null || true; \
	echo "Applying ServiceAccount..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/serviceaccount.yaml 2>/dev/null || true; \
	echo "Applying RBAC resources..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/role.yaml 2>/dev/null || true; \
	$(KUBECTL) apply -f $$CONFIG_DIR/rolebinding.yaml 2>/dev/null || true; \
	echo "Applying PVC..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/pvc.yaml 2>/dev/null || true; \
	echo "Applying Deployment..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/deployment.yaml 2>/dev/null || true; \
	echo "Applying Service..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/service.yaml 2>/dev/null || true; \
	echo "Applying Ingress..."; \
	$(KUBECTL) apply -f $$CONFIG_DIR/ingress.yaml 2>/dev/null || true; \
	echo "Cleaning up..."; \
	rm -rf /tmp/wordpress-config-restore; \
	echo "Configuration restore completed"

.PHONY: wp-restore-from-snapshot
wp-restore-from-snapshot:
	@test -n "$(SNAPSHOT_NAME)" || (echo "Error: SNAPSHOT_NAME parameter required"; exit 1)
	@echo "==> Restoring from PVC snapshot: $(SNAPSHOT_NAME)"
	@echo "Scaling down WordPress deployment..."
	@$(KUBECTL) scale deployment $(RELEASE_NAME) -n $(NAMESPACE) --replicas=0
	@echo "Waiting for pod to terminate..."
	@sleep 10
	@PVC_NAME=$$($(KUBECTL) get pvc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	STORAGE_CLASS=$$($(KUBECTL) get pvc $$PVC_NAME -n $(NAMESPACE) -o jsonpath='{.spec.storageClassName}'); \
	PVC_SIZE=$$($(KUBECTL) get pvc $$PVC_NAME -n $(NAMESPACE) -o jsonpath='{.spec.resources.requests.storage}'); \
	echo "Deleting existing PVC: $$PVC_NAME"; \
	$(KUBECTL) delete pvc $$PVC_NAME -n $(NAMESPACE); \
	echo "Creating new PVC from snapshot..."; \
	cat <<EOF | $(KUBECTL) apply -f -; \
	apiVersion: v1; \
	kind: PersistentVolumeClaim; \
	metadata:; \
	  name: $$PVC_NAME; \
	  namespace: $(NAMESPACE); \
	spec:; \
	  storageClassName: $$STORAGE_CLASS; \
	  dataSource:; \
	    name: $(SNAPSHOT_NAME); \
	    kind: VolumeSnapshot; \
	    apiGroup: snapshot.storage.k8s.io; \
	  accessModes:; \
	    - ReadWriteOnce; \
	  resources:; \
	    requests:; \
	      storage: $$PVC_SIZE; \
	EOF \
	echo "Waiting for PVC to be bound..."; \
	$(KUBECTL) wait --for=jsonpath='{.status.phase}'=Bound pvc/$$PVC_NAME -n $(NAMESPACE) --timeout=300s; \
	echo "Scaling up WordPress deployment..."; \
	$(KUBECTL) scale deployment $(RELEASE_NAME) -n $(NAMESPACE) --replicas=1; \
	echo "Waiting for pod to be ready..."; \
	$(KUBECTL) wait --for=condition=ready pod -l $(POD_SELECTOR) -n $(NAMESPACE) --timeout=300s; \
	echo "Snapshot restore completed"

.PHONY: wp-full-recovery
wp-full-recovery:
	@test -n "$(CONTENT_BACKUP)" || (echo "Error: CONTENT_BACKUP parameter required"; exit 1)
	@test -n "$(MYSQL_BACKUP)" || (echo "Error: MYSQL_BACKUP parameter required"; exit 1)
	@echo "==> Full WordPress disaster recovery"
	@echo "Step 1: Restore configuration (if CONFIG_BACKUP provided)"
	@if [ -n "$(CONFIG_BACKUP)" ]; then \
		$(MAKE) -f make/ops/wordpress.mk wp-restore-config BACKUP_FILE=$(CONFIG_BACKUP); \
	fi
	@echo ""
	@echo "Step 2: Wait for WordPress pod to be ready"
	@$(KUBECTL) wait --for=condition=ready pod -l $(POD_SELECTOR) -n $(NAMESPACE) --timeout=300s || true
	@echo ""
	@echo "Step 3: Restore WordPress content"
	@$(MAKE) -f make/ops/wordpress.mk wp-restore-content BACKUP_FILE=$(CONTENT_BACKUP)
	@echo ""
	@echo "Step 4: Restore MySQL database"
	@$(MAKE) -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=$(MYSQL_BACKUP)
	@echo ""
	@echo "Step 5: Post-recovery validation"
	@$(MAKE) -f make/ops/wordpress.mk wp-post-upgrade-check
	@echo ""
	@echo "==> Full disaster recovery completed"

# ==============================================================================
# Upgrade Operations
# ==============================================================================

.PHONY: wp-pre-upgrade-check
wp-pre-upgrade-check:
	@echo "==> WordPress Pre-Upgrade Checklist"
	@echo ""
	@echo "1. Current WordPress version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root
	@echo ""
	@echo "2. Current PHP version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- php -v | head -1
	@echo ""
	@echo "3. Database version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root --extra | grep "Database revision"
	@echo ""
	@echo "4. Database integrity:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db check --allow-root
	@echo ""
	@echo "5. Installed plugins:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin list --allow-root
	@echo ""
	@echo "6. Installed themes:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp theme list --allow-root
	@echo ""
	@echo "7. Database size:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db size --allow-root
	@echo ""
	@echo "8. Disk usage:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- df -h /var/www/html
	@echo ""
	@echo "REMINDER: Create full backup before upgrading!"
	@echo "  make -f make/ops/wordpress.mk wp-full-backup"

.PHONY: wp-post-upgrade-check
wp-post-upgrade-check:
	@echo "==> WordPress Post-Upgrade Validation"
	@echo ""
	@echo "1. WordPress version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root
	@echo ""
	@echo "2. PHP version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- php -v | head -1
	@echo ""
	@echo "3. Database version:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core version --allow-root --extra | grep "Database revision"
	@echo ""
	@echo "4. Database integrity:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db check --allow-root
	@echo ""
	@echo "5. Plugin status:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp plugin list --allow-root --status=active
	@echo ""
	@echo "6. Pod health:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "REMINDER: Manual validation required!"
	@echo "  - Login to /wp-admin"
	@echo "  - Verify posts/pages load"
	@echo "  - Test plugin functionality"
	@echo "  - Check for PHP errors in logs"

# ==============================================================================
# Monitoring & Troubleshooting
# ==============================================================================

.PHONY: wp-disk-usage
wp-disk-usage:
	@echo "==> WordPress disk usage"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- du -sh /var/www/html/*

.PHONY: wp-resource-usage
wp-resource-usage:
	@echo "==> WordPress resource usage"
	@$(KUBECTL) top pod -n $(NAMESPACE) -l $(POD_SELECTOR)

.PHONY: wp-top
wp-top:
	@echo "==> WordPress resource usage (live)"
	@$(KUBECTL) top pod -n $(NAMESPACE) -l $(POD_SELECTOR) --containers

.PHONY: wp-describe
wp-describe:
	@echo "==> WordPress pod details"
	@$(KUBECTL) describe pod -n $(NAMESPACE) -l $(POD_SELECTOR)

.PHONY: wp-health-check
wp-health-check:
	@echo "==> WordPress health checks"
	@echo "1. Pod status:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "2. Database connectivity:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp db check --allow-root
	@echo ""
	@echo "3. WordPress core files:"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp core verify-checksums --allow-root

.PHONY: wp-liveness-check
wp-liveness-check:
	@echo "==> WordPress liveness check"
	@POD_NAME=$$($(GET_POD)); \
	POD_IP=$$($(KUBECTL) get pod $$POD_NAME -n $(NAMESPACE) -o jsonpath='{.status.podIP}'); \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://$$POD_IP/wp-admin/install.php

.PHONY: wp-readiness-check
wp-readiness-check:
	@echo "==> WordPress readiness check"
	@POD_NAME=$$($(GET_POD)); \
	POD_IP=$$($(KUBECTL) get pod $$POD_NAME -n $(NAMESPACE) -o jsonpath='{.status.podIP}'); \
	$(KUBECTL) exec -n $(NAMESPACE) $$POD_NAME -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://$$POD_IP/wp-login.php

# ==============================================================================
# Cleanup Operations
# ==============================================================================

.PHONY: wp-cleanup-revisions
wp-cleanup-revisions:
	@echo "==> Deleting WordPress post revisions"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp post delete \$$(wp post list --post_type=revision --format=ids --allow-root) --allow-root

.PHONY: wp-cleanup-spam
wp-cleanup-spam:
	@echo "==> Deleting spam comments"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp comment delete \$$(wp comment list --status=spam --format=ids --allow-root) --allow-root

.PHONY: wp-cleanup-trash
wp-cleanup-trash:
	@echo "==> Emptying WordPress trash"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp post delete \$$(wp post list --post_status=trash --format=ids --allow-root) --allow-root
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp comment delete \$$(wp comment list --status=trash --format=ids --allow-root) --allow-root

.PHONY: wp-cache-flush
wp-cache-flush:
	@echo "==> Flushing WordPress cache"
	@$(KUBECTL) exec -n $(NAMESPACE) $$($(GET_POD)) -- wp cache flush --allow-root

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help:
	@echo "WordPress Operational Commands"
	@echo "==============================="
	@echo ""
	@echo "Basic Operations:"
	@echo "  wp-status                    - Show WordPress pod status"
	@echo "  wp-version                   - Show WordPress version"
	@echo "  wp-php-version               - Show PHP version"
	@echo "  wp-logs                      - View WordPress logs (last 100 lines)"
	@echo "  wp-logs-follow               - Follow WordPress logs"
	@echo "  wp-shell                     - Access WordPress shell"
	@echo "  wp-restart                   - Restart WordPress deployment"
	@echo "  wp-port-forward              - Port-forward to localhost:8080"
	@echo ""
	@echo "Database Operations:"
	@echo "  wp-db-check                  - Test database connectivity"
	@echo "  wp-db-version                - Show database schema version"
	@echo "  wp-db-size                   - Show database size"
	@echo "  wp-db-table-count            - Count database tables"
	@echo "  wp-db-list-tables            - List all database tables"
	@echo "  wp-db-shell                  - Access MySQL shell"
	@echo "  wp-db-optimize               - Optimize database tables"
	@echo "  wp-db-repair                 - Repair database tables"
	@echo "  wp-db-upgrade                - Trigger database upgrade"
	@echo ""
	@echo "WordPress Management:"
	@echo "  wp-list-plugins              - List installed plugins"
	@echo "  wp-plugin-activate           - Activate plugin (PLUGIN=name)"
	@echo "  wp-plugin-deactivate         - Deactivate plugin (PLUGIN=name)"
	@echo "  wp-plugin-update             - Update plugin (PLUGIN=name)"
	@echo "  wp-plugin-update-all         - Update all plugins"
	@echo "  wp-list-themes               - List installed themes"
	@echo "  wp-theme-activate            - Activate theme (THEME=name)"
	@echo "  wp-theme-update              - Update theme (THEME=name)"
	@echo "  wp-theme-update-all          - Update all themes"
	@echo "  wp-list-users                - List WordPress users"
	@echo "  wp-create-user               - Create user (USER=name EMAIL=email ROLE=role)"
	@echo "  wp-delete-user               - Delete user (USER=name)"
	@echo "  wp-list-posts                - List posts"
	@echo "  wp-list-pages                - List pages"
	@echo "  wp-media-regenerate          - Regenerate media thumbnails"
	@echo ""
	@echo "Maintenance Mode:"
	@echo "  wp-enable-maintenance        - Enable maintenance mode"
	@echo "  wp-disable-maintenance       - Disable maintenance mode"
	@echo "  wp-maintenance-status        - Check maintenance mode status"
	@echo ""
	@echo "Backup Operations:"
	@echo "  wp-backup-content-full       - Full content backup (tar)"
	@echo "  wp-backup-content-incremental- Incremental content backup"
	@echo "  wp-backup-mysql              - MySQL database backup"
	@echo "  wp-backup-config             - Kubernetes configuration backup"
	@echo "  wp-snapshot-content          - Create PVC snapshot"
	@echo "  wp-list-snapshots            - List PVC snapshots"
	@echo "  wp-full-backup               - Full backup (all components)"
	@echo ""
	@echo "Restore Operations:"
	@echo "  wp-restore-content           - Restore content (BACKUP_FILE=path)"
	@echo "  wp-restore-mysql             - Restore database (BACKUP_FILE=path)"
	@echo "  wp-restore-config            - Restore config (BACKUP_FILE=path)"
	@echo "  wp-restore-from-snapshot     - Restore from snapshot (SNAPSHOT_NAME=name)"
	@echo "  wp-full-recovery             - Full recovery (CONTENT_BACKUP=path MYSQL_BACKUP=path)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  wp-pre-upgrade-check         - Pre-upgrade validation"
	@echo "  wp-post-upgrade-check        - Post-upgrade validation"
	@echo ""
	@echo "Monitoring & Troubleshooting:"
	@echo "  wp-disk-usage                - Show disk usage"
	@echo "  wp-resource-usage            - Show CPU/memory usage"
	@echo "  wp-top                       - Live resource usage"
	@echo "  wp-describe                  - Show pod details"
	@echo "  wp-health-check              - Comprehensive health check"
	@echo "  wp-liveness-check            - Liveness probe check"
	@echo "  wp-readiness-check           - Readiness probe check"
	@echo ""
	@echo "Cleanup Operations:"
	@echo "  wp-cleanup-revisions         - Delete post revisions"
	@echo "  wp-cleanup-spam              - Delete spam comments"
	@echo "  wp-cleanup-trash             - Empty trash"
	@echo "  wp-cache-flush               - Flush WordPress cache"
	@echo ""
	@echo "Configuration:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  BACKUP_DIR=$(BACKUP_DIR)"
