# Grafana Chart Operations

include Makefile.common.mk

CHART_NAME := grafana
CHART_DIR := charts/grafana
NAMESPACE ?= default
RELEASE_NAME ?= grafana

POD ?= $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
BACKUP_DIR ?= backups/grafana-$(shell date +%Y%m%d-%H%M%S)

.PHONY: help
help::
	@echo ""
	@echo "=========================================="
	@echo "Grafana Operations (40+ commands)"
	@echo "=========================================="
	@echo ""
	@echo "Basic Operations:"
	@echo "  grafana-status           - Show Grafana pod status"
	@echo "  grafana-shell            - Open shell in Grafana pod"
	@echo "  grafana-logs             - View Grafana logs (follow mode)"
	@echo "  grafana-logs-tail        - View last 100 lines of logs"
	@echo "  grafana-port-forward     - Port forward to localhost:3000"
	@echo "  grafana-get-url          - Get Grafana URL (if ingress enabled)"
	@echo "  grafana-restart          - Restart Grafana deployment"
	@echo "  grafana-version          - Get Grafana version"
	@echo ""
	@echo "Credentials & Access:"
	@echo "  grafana-get-password     - Get admin password"
	@echo "  grafana-reset-password PASSWORD=... - Reset admin password"
	@echo ""
	@echo "Dashboard Operations:"
	@echo "  grafana-list-dashboards  - List all dashboards"
	@echo "  grafana-export-dashboard UID=... - Export dashboard JSON"
	@echo "  grafana-import-dashboard FILE=... - Import dashboard from JSON"
	@echo "  grafana-delete-dashboard UID=... - Delete dashboard by UID"
	@echo "  grafana-backup-dashboards - Export all dashboards"
	@echo "  grafana-restore-dashboards BACKUP_DIR=... - Restore all dashboards"
	@echo ""
	@echo "Datasource Operations:"
	@echo "  grafana-list-datasources - List all datasources"
	@echo "  grafana-add-prometheus URL=... - Add Prometheus datasource"
	@echo "  grafana-add-loki URL=...       - Add Loki datasource"
	@echo "  grafana-test-datasource ID=... - Test datasource connectivity"
	@echo "  grafana-delete-datasource ID=... - Delete datasource by ID"
	@echo "  grafana-backup-datasources - Export all datasources"
	@echo "  grafana-restore-datasources BACKUP_DIR=... - Restore all datasources"
	@echo ""
	@echo "Database Operations:"
	@echo "  grafana-backup-db        - Backup Grafana SQLite database"
	@echo "  grafana-backup-db-offline - Backup database (Grafana stopped)"
	@echo "  grafana-restore-db BACKUP_FILE=... - Restore database"
	@echo "  grafana-db-integrity-check - Check database integrity"
	@echo "  grafana-db-info          - Show database information"
	@echo ""
	@echo "Plugin Operations:"
	@echo "  grafana-list-plugins     - List installed plugins"
	@echo "  grafana-install-plugin PLUGIN_ID=... - Install plugin"
	@echo "  grafana-update-plugins   - Update all plugins"
	@echo "  grafana-backup-plugins   - Backup plugin list"
	@echo ""
	@echo "Configuration Backup:"
	@echo "  grafana-backup-config    - Backup ConfigMaps"
	@echo "  grafana-backup-secrets   - Backup Secrets"
	@echo "  grafana-restore-config BACKUP_FILE=... - Restore ConfigMaps"
	@echo "  grafana-restore-secrets BACKUP_FILE=... - Restore Secrets"
	@echo ""
	@echo "PVC Snapshot Operations:"
	@echo "  grafana-backup-snapshot  - Create VolumeSnapshot of Grafana PVC"
	@echo "  grafana-list-snapshots   - List all Grafana VolumeSnapshots"
	@echo "  grafana-delete-snapshot SNAPSHOT_NAME=... - Delete VolumeSnapshot"
	@echo ""
	@echo "Comprehensive Backup/Recovery:"
	@echo "  grafana-full-backup      - Backup all components (dashboards, datasources, DB, config)"
	@echo "  grafana-pre-upgrade-check - Pre-upgrade validation and backup"
	@echo "  grafana-post-upgrade-check - Post-upgrade validation"
	@echo ""
	@echo "Health & Monitoring:"
	@echo "  grafana-health-check     - Check Grafana health endpoint"
	@echo "  grafana-metrics          - Get Grafana metrics"
	@echo ""
	@echo "API Operations:"
	@echo "  grafana-api CMD='/api/...' - Run Grafana API command"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  BACKUP_DIR=$(BACKUP_DIR)"
	@echo ""

# ============================================================================
# Basic Operations
# ============================================================================

.PHONY: grafana-status
grafana-status:
	@echo "Grafana Pod Status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "Grafana Service:"
	@kubectl get svc -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "Grafana PVC:"
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME)

.PHONY: grafana-shell
grafana-shell:
	@echo "Opening shell in Grafana pod: $(POD)"
	kubectl exec -it $(POD) -n $(NAMESPACE) -- /bin/bash

.PHONY: grafana-logs
grafana-logs:
	@echo "Viewing logs for Grafana pod: $(POD)"
	kubectl logs -f $(POD) -n $(NAMESPACE)

.PHONY: grafana-logs-tail
grafana-logs-tail:
	@echo "Last 100 lines of Grafana logs:"
	kubectl logs --tail=100 $(POD) -n $(NAMESPACE)

.PHONY: grafana-port-forward
grafana-port-forward:
	@echo "Port forwarding Grafana to localhost:3000"
	@echo "Access Grafana at: http://localhost:3000"
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 3000:80

.PHONY: grafana-get-url
grafana-get-url:
	@echo "Grafana Ingress URL:"
	@kubectl get ingress -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Ingress not configured"

.PHONY: grafana-restart
grafana-restart:
	@echo "Restarting Grafana deployment..."
	kubectl rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE)

.PHONY: grafana-version
grafana-version:
	@echo "Grafana Version:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli -v 2>/dev/null || kubectl exec $(POD) -n $(NAMESPACE) -- grafana server --version

# ============================================================================
# Credentials & Access
# ============================================================================

.PHONY: grafana-get-password
grafana-get-password:
	@echo "Grafana admin password:"
	@kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d || echo "Secret not found"
	@echo ""

.PHONY: grafana-reset-password
grafana-reset-password:
ifndef PASSWORD
	@echo "Error: PASSWORD variable required. Usage: make grafana-reset-password PASSWORD=newpass"
	@exit 1
endif
	@echo "Resetting admin password..."
	kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli admin reset-admin-password $(PASSWORD)
	@echo "Admin password reset successfully."

# ============================================================================
# Dashboard Operations
# ============================================================================

.PHONY: grafana-list-dashboards
grafana-list-dashboards:
	@echo "Listing Grafana dashboards..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/search?type=dash-db | jq '.'

.PHONY: grafana-export-dashboard
grafana-export-dashboard:
ifndef UID
	@echo "Error: UID variable required. Usage: make grafana-export-dashboard UID=dashboard-uid"
	@exit 1
endif
	@mkdir -p tmp/grafana-dashboards
	@echo "Exporting dashboard UID=$(UID)..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/dashboards/uid/$(UID) | jq '.dashboard' > tmp/grafana-dashboards/$(UID).json
	@echo "Dashboard exported to: tmp/grafana-dashboards/$(UID).json"

.PHONY: grafana-import-dashboard
grafana-import-dashboard:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make grafana-import-dashboard FILE=dashboard.json"
	@exit 1
endif
	@echo "Importing dashboard from: $(FILE)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	DASHBOARD=$$(cat $(FILE) | jq '{dashboard: ., overwrite: true}'); \
	kubectl exec -i $(POD) -n $(NAMESPACE) -- curl -s -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d "$$DASHBOARD" \
		http://localhost:3000/api/dashboards/db | jq '.'

.PHONY: grafana-delete-dashboard
grafana-delete-dashboard:
ifndef UID
	@echo "Error: UID variable required. Usage: make grafana-delete-dashboard UID=dashboard-uid"
	@exit 1
endif
	@echo "Deleting dashboard UID=$(UID)..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -X DELETE -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/dashboards/uid/$(UID) | jq '.'

.PHONY: grafana-backup-dashboards
grafana-backup-dashboards:
	@echo "Backing up all Grafana dashboards..."
	@mkdir -p $(BACKUP_DIR)/dashboards
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	DASHBOARD_UIDS=$$(kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/search?type=dash-db | jq -r '.[].uid'); \
	COUNT=0; \
	for uid in $$DASHBOARD_UIDS; do \
		echo "Exporting dashboard: $$uid"; \
		kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS \
			http://localhost:3000/api/dashboards/uid/$$uid | jq '.dashboard' > $(BACKUP_DIR)/dashboards/dashboard-$$uid.json; \
		COUNT=$$((COUNT + 1)); \
	done; \
	echo "Exported $$COUNT dashboards to $(BACKUP_DIR)/dashboards/"

.PHONY: grafana-restore-dashboards
grafana-restore-dashboards:
ifndef BACKUP_DIR
	@echo "Error: BACKUP_DIR variable required. Usage: make grafana-restore-dashboards BACKUP_DIR=backups/grafana-YYYYMMDD"
	@exit 1
endif
	@echo "Restoring dashboards from $(BACKUP_DIR)/dashboards/..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	COUNT=0; \
	for file in $(BACKUP_DIR)/dashboards/dashboard-*.json; do \
		[ -f "$$file" ] || continue; \
		DASHBOARD_UID=$$(jq -r '.uid' "$$file"); \
		echo "Importing dashboard: $$DASHBOARD_UID"; \
		DASHBOARD_JSON=$$(jq '{dashboard: ., overwrite: true}' "$$file"); \
		echo "$$DASHBOARD_JSON" | kubectl exec -i $(POD) -n $(NAMESPACE) -- curl -s -X POST -H "Content-Type: application/json" \
			-u admin:$$ADMIN_PASS \
			-d @- \
			http://localhost:3000/api/dashboards/db > /dev/null; \
		COUNT=$$((COUNT + 1)); \
	done; \
	echo "Restored $$COUNT dashboards."

# ============================================================================
# Datasource Operations
# ============================================================================

.PHONY: grafana-list-datasources
grafana-list-datasources:
	@echo "Listing Grafana datasources..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/datasources | jq '.'

.PHONY: grafana-add-prometheus
grafana-add-prometheus:
ifndef URL
	@echo "Error: URL variable required. Usage: make grafana-add-prometheus URL=http://prometheus:9090"
	@exit 1
endif
	@echo "Adding Prometheus datasource: $(URL)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d '{"name":"Prometheus","type":"prometheus","url":"$(URL)","access":"proxy","isDefault":true}' \
		http://localhost:3000/api/datasources | jq '.'

.PHONY: grafana-add-loki
grafana-add-loki:
ifndef URL
	@echo "Error: URL variable required. Usage: make grafana-add-loki URL=http://loki:3100"
	@exit 1
endif
	@echo "Adding Loki datasource: $(URL)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d '{"name":"Loki","type":"loki","url":"$(URL)","access":"proxy"}' \
		http://localhost:3000/api/datasources | jq '.'

.PHONY: grafana-test-datasource
grafana-test-datasource:
ifndef ID
	@echo "Error: ID variable required. Usage: make grafana-test-datasource ID=1"
	@exit 1
endif
	@echo "Testing datasource ID=$(ID)..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/datasources/$(ID)/health | jq '.'

.PHONY: grafana-delete-datasource
grafana-delete-datasource:
ifndef ID
	@echo "Error: ID variable required. Usage: make grafana-delete-datasource ID=1"
	@exit 1
endif
	@echo "Deleting datasource ID=$(ID)..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -X DELETE -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/datasources/$(ID) | jq '.'

.PHONY: grafana-backup-datasources
grafana-backup-datasources:
	@echo "Backing up all Grafana datasources..."
	@mkdir -p $(BACKUP_DIR)/datasources
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/datasources > $(BACKUP_DIR)/datasources/datasources.json
	@echo "Datasources backed up to $(BACKUP_DIR)/datasources/datasources.json"

.PHONY: grafana-restore-datasources
grafana-restore-datasources:
ifndef BACKUP_DIR
	@echo "Error: BACKUP_DIR variable required. Usage: make grafana-restore-datasources BACKUP_DIR=backups/grafana-YYYYMMDD"
	@exit 1
endif
	@echo "Restoring datasources from $(BACKUP_DIR)/datasources/datasources.json..."
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	cat $(BACKUP_DIR)/datasources/datasources.json | jq -c '.[]' | while read ds; do \
		echo "Restoring datasource: $$(echo $$ds | jq -r '.name')"; \
		echo "$$ds" | kubectl exec -i $(POD) -n $(NAMESPACE) -- curl -s -X POST -H "Content-Type: application/json" \
			-u admin:$$ADMIN_PASS \
			-d @- \
			http://localhost:3000/api/datasources > /dev/null; \
	done
	@echo "Datasources restored."

# ============================================================================
# Database Operations
# ============================================================================

.PHONY: grafana-backup-db
grafana-backup-db:
	@echo "Backing up Grafana SQLite database (online backup)..."
	@mkdir -p $(BACKUP_DIR)/database
	@BACKUP_FILE="grafana-db-$$(date +%Y%m%d-%H%M%S).db"; \
	echo "Creating backup: $$BACKUP_FILE"; \
	kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db ".backup /tmp/$$BACKUP_FILE" && \
	kubectl cp $(NAMESPACE)/$(POD):/tmp/$$BACKUP_FILE $(BACKUP_DIR)/database/$$BACKUP_FILE && \
	kubectl exec $(POD) -n $(NAMESPACE) -- rm /tmp/$$BACKUP_FILE && \
	echo "Database backed up to $(BACKUP_DIR)/database/$$BACKUP_FILE"

.PHONY: grafana-backup-db-offline
grafana-backup-db-offline:
	@echo "Backing up Grafana database (offline backup - requires downtime)..."
	@mkdir -p $(BACKUP_DIR)/database
	@echo "Scaling down Grafana..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=0
	@kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -n $(NAMESPACE) --timeout=60s || true
	@echo "Creating backup pod..."
	@kubectl run grafana-backup-pod -n $(NAMESPACE) --image=alpine:3.19 --restart=Never \
		--overrides='{"spec":{"containers":[{"name":"backup","image":"alpine:3.19","command":["sleep","3600"],"volumeMounts":[{"name":"grafana-data","mountPath":"/var/lib/grafana"}]}],"volumes":[{"name":"grafana-data","persistentVolumeClaim":{"claimName":"$(RELEASE_NAME)-data"}}]}}'
	@kubectl wait --for=condition=ready pod/grafana-backup-pod -n $(NAMESPACE) --timeout=60s
	@BACKUP_FILE="grafana-db-offline-$$(date +%Y%m%d-%H%M%S).db"; \
	kubectl cp $(NAMESPACE)/grafana-backup-pod:/var/lib/grafana/grafana.db $(BACKUP_DIR)/database/$$BACKUP_FILE && \
	echo "Database backed up to $(BACKUP_DIR)/database/$$BACKUP_FILE"
	@echo "Cleaning up backup pod..."
	@kubectl delete pod grafana-backup-pod -n $(NAMESPACE)
	@echo "Scaling up Grafana..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=1

.PHONY: grafana-restore-db
grafana-restore-db:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required. Usage: make grafana-restore-db BACKUP_FILE=grafana-db-YYYYMMDD.db"
	@exit 1
endif
	@echo "WARNING: This will overwrite the current Grafana database!"
	@echo "Backup file: $(BACKUP_FILE)"
	@read -p "Press Enter to continue or Ctrl+C to cancel..." dummy
	@echo "Scaling down Grafana..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=0
	@kubectl wait --for=delete pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -n $(NAMESPACE) --timeout=60s || true
	@echo "Creating restore pod..."
	@kubectl run grafana-restore-pod -n $(NAMESPACE) --image=alpine:3.19 --restart=Never \
		--overrides='{"spec":{"containers":[{"name":"restore","image":"alpine:3.19","command":["sleep","3600"],"volumeMounts":[{"name":"grafana-data","mountPath":"/var/lib/grafana"}]}],"volumes":[{"name":"grafana-data","persistentVolumeClaim":{"claimName":"$(RELEASE_NAME)-data"}}]}}'
	@kubectl wait --for=condition=ready pod/grafana-restore-pod -n $(NAMESPACE) --timeout=60s
	@echo "Backing up current database..."
	@kubectl exec grafana-restore-pod -n $(NAMESPACE) -- mv /var/lib/grafana/grafana.db /var/lib/grafana/grafana.db.old || true
	@echo "Restoring database..."
	@kubectl cp $(BACKUP_FILE) $(NAMESPACE)/grafana-restore-pod:/var/lib/grafana/grafana.db
	@kubectl exec grafana-restore-pod -n $(NAMESPACE) -- chown 472:472 /var/lib/grafana/grafana.db
	@kubectl exec grafana-restore-pod -n $(NAMESPACE) -- chmod 640 /var/lib/grafana/grafana.db
	@echo "Cleaning up restore pod..."
	@kubectl delete pod grafana-restore-pod -n $(NAMESPACE)
	@echo "Scaling up Grafana..."
	@kubectl scale deployment/$(RELEASE_NAME) -n $(NAMESPACE) --replicas=1
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -n $(NAMESPACE) --timeout=300s
	@echo "Database restored successfully."

.PHONY: grafana-db-integrity-check
grafana-db-integrity-check:
	@echo "Checking Grafana database integrity..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db "PRAGMA integrity_check;" 2>/dev/null || echo "Database integrity check failed"

.PHONY: grafana-db-info
grafana-db-info:
	@echo "Grafana Database Information:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db <<< ".tables" 2>/dev/null || echo "Unable to query database"
	@echo ""
	@echo "Dashboard count:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM dashboard;" 2>/dev/null || echo "N/A"
	@echo "Datasource count:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM data_source;" 2>/dev/null || echo "N/A"
	@echo "User count:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM user;" 2>/dev/null || echo "N/A"

# ============================================================================
# Plugin Operations
# ============================================================================

.PHONY: grafana-list-plugins
grafana-list-plugins:
	@echo "Listing installed Grafana plugins..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli plugins ls

.PHONY: grafana-install-plugin
grafana-install-plugin:
ifndef PLUGIN_ID
	@echo "Error: PLUGIN_ID variable required. Usage: make grafana-install-plugin PLUGIN_ID=grafana-piechart-panel"
	@exit 1
endif
	@echo "Installing plugin: $(PLUGIN_ID)"
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli plugins install $(PLUGIN_ID)
	@echo "Plugin installed. Restart Grafana to load the plugin:"
	@echo "  make grafana-restart"

.PHONY: grafana-update-plugins
grafana-update-plugins:
	@echo "Updating all Grafana plugins..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli plugins update-all
	@echo "Plugins updated. Restart Grafana to apply updates:"
	@echo "  make grafana-restart"

.PHONY: grafana-backup-plugins
grafana-backup-plugins:
	@echo "Backing up Grafana plugin list..."
	@mkdir -p $(BACKUP_DIR)/plugins
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli plugins ls > $(BACKUP_DIR)/plugins/plugins-list.txt
	@echo "Plugin list backed up to $(BACKUP_DIR)/plugins/plugins-list.txt"

# ============================================================================
# Configuration Backup
# ============================================================================

.PHONY: grafana-backup-config
grafana-backup-config:
	@echo "Backing up Grafana ConfigMaps..."
	@mkdir -p $(BACKUP_DIR)/config
	@kubectl get configmap -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $(BACKUP_DIR)/config/configmaps-$$(date +%Y%m%d-%H%M%S).yaml
	@echo "ConfigMaps backed up to $(BACKUP_DIR)/config/"

.PHONY: grafana-backup-secrets
grafana-backup-secrets:
	@echo "Backing up Grafana Secrets..."
	@mkdir -p $(BACKUP_DIR)/secrets
	@kubectl get secret -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $(BACKUP_DIR)/secrets/secrets-$$(date +%Y%m%d-%H%M%S).yaml
	@echo "Secrets backed up to $(BACKUP_DIR)/secrets/"
	@echo "WARNING: Secrets backup contains sensitive data. Store securely!"

.PHONY: grafana-restore-config
grafana-restore-config:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required. Usage: make grafana-restore-config BACKUP_FILE=configmaps-YYYYMMDD.yaml"
	@exit 1
endif
	@echo "Restoring ConfigMaps from $(BACKUP_FILE)..."
	@kubectl apply -f $(BACKUP_FILE)
	@echo "ConfigMaps restored. Restart Grafana to apply changes:"
	@echo "  make grafana-restart"

.PHONY: grafana-restore-secrets
grafana-restore-secrets:
ifndef BACKUP_FILE
	@echo "Error: BACKUP_FILE variable required. Usage: make grafana-restore-secrets BACKUP_FILE=secrets-YYYYMMDD.yaml"
	@exit 1
endif
	@echo "Restoring Secrets from $(BACKUP_FILE)..."
	@kubectl apply -f $(BACKUP_FILE)
	@echo "Secrets restored. Restart Grafana to apply changes:"
	@echo "  make grafana-restart"

# ============================================================================
# PVC Snapshot Operations
# ============================================================================

.PHONY: grafana-backup-snapshot
grafana-backup-snapshot:
	@echo "Creating VolumeSnapshot of Grafana PVC..."
	@SNAPSHOT_NAME="$(RELEASE_NAME)-data-snapshot-$$(date +%Y%m%d-%H%M%S)"; \
	cat <<EOF | kubectl apply -f - ; \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $$SNAPSHOT_NAME; \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-hostpath-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(RELEASE_NAME)-data; \
	EOF
	@echo "VolumeSnapshot created: $$SNAPSHOT_NAME"
	@echo "Waiting for snapshot to be ready..."
	@kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/$$SNAPSHOT_NAME -n $(NAMESPACE) --timeout=300s || echo "Snapshot creation may take longer"

.PHONY: grafana-list-snapshots
grafana-list-snapshots:
	@echo "Listing Grafana VolumeSnapshots..."
	@kubectl get volumesnapshots -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) 2>/dev/null || echo "No VolumeSnapshots found"

.PHONY: grafana-delete-snapshot
grafana-delete-snapshot:
ifndef SNAPSHOT_NAME
	@echo "Error: SNAPSHOT_NAME variable required. Usage: make grafana-delete-snapshot SNAPSHOT_NAME=grafana-data-snapshot-YYYYMMDD"
	@exit 1
endif
	@echo "Deleting VolumeSnapshot: $(SNAPSHOT_NAME)"
	@kubectl delete volumesnapshot $(SNAPSHOT_NAME) -n $(NAMESPACE)

# ============================================================================
# Comprehensive Backup/Recovery
# ============================================================================

.PHONY: grafana-full-backup
grafana-full-backup:
	@echo "=========================================="
	@echo "Grafana Full Backup"
	@echo "=========================================="
	@echo ""
	@BACKUP_DIR_FULL="backups/grafana-full-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p $$BACKUP_DIR_FULL; \
	echo "Backup directory: $$BACKUP_DIR_FULL"; \
	echo ""; \
	echo "1. Backing up dashboards..."; \
	$(MAKE) grafana-backup-dashboards BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "2. Backing up datasources..."; \
	$(MAKE) grafana-backup-datasources BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "3. Backing up database..."; \
	$(MAKE) grafana-backup-db BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "4. Backing up configuration..."; \
	$(MAKE) grafana-backup-config BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "5. Backing up secrets..."; \
	$(MAKE) grafana-backup-secrets BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "6. Backing up plugins..."; \
	$(MAKE) grafana-backup-plugins BACKUP_DIR=$$BACKUP_DIR_FULL; \
	echo ""; \
	echo "==========================================";\
	echo "Full backup completed: $$BACKUP_DIR_FULL"; \
	echo "=========================================="

.PHONY: grafana-pre-upgrade-check
grafana-pre-upgrade-check:
	@echo "=========================================="
	@echo "Grafana Pre-Upgrade Validation"
	@echo "=========================================="
	@echo ""
	@echo "1. Current Grafana version:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli -v 2>/dev/null || kubectl exec $(POD) -n $(NAMESPACE) -- grafana server --version
	@echo ""
	@echo "2. Current Helm release:"
	@helm list -n $(NAMESPACE) -o json | jq -r '.[] | select(.name=="$(RELEASE_NAME)") | "Chart: \(.chart), App Version: \(.app_version), Status: \(.status)"'
	@echo ""
	@echo "3. Dashboard count:"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/search?type=dash-db | jq '. | length'
	@echo ""
	@echo "4. Datasource count:"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/datasources | jq '. | length'
	@echo ""
	@echo "5. Installed plugins:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli plugins ls | wc -l
	@echo ""
	@echo "=========================================="
	@echo "Creating full backup before upgrade..."
	@echo "=========================================="
	@$(MAKE) grafana-full-backup

.PHONY: grafana-post-upgrade-check
grafana-post-upgrade-check:
	@echo "=========================================="
	@echo "Grafana Post-Upgrade Validation"
	@echo "=========================================="
	@echo ""
	@echo "1. Pod status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "2. New Grafana version:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli -v 2>/dev/null || kubectl exec $(POD) -n $(NAMESPACE) -- grafana server --version
	@echo ""
	@echo "3. Dashboard count:"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/search?type=dash-db | jq '. | length'
	@echo ""
	@echo "4. Datasource count:"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/datasources | jq '. | length'
	@echo ""
	@echo "5. Database integrity:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- sqlite3 /var/lib/grafana/grafana.db "PRAGMA integrity_check;" 2>/dev/null || echo "Unable to check database"
	@echo ""
	@echo "6. Health check:"
	@kubectl exec $(POD) -n $(NAMESPACE) -- curl -s http://localhost:3000/api/health | jq '.'
	@echo ""
	@echo "7. Recent logs (last 20 lines):"
	@kubectl logs --tail=20 $(POD) -n $(NAMESPACE)
	@echo ""
	@echo "=========================================="
	@echo "Post-upgrade validation completed"
	@echo "=========================================="

# ============================================================================
# Health & Monitoring
# ============================================================================

.PHONY: grafana-health-check
grafana-health-check:
	@echo "Checking Grafana health..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- curl -s http://localhost:3000/api/health | jq '.'

.PHONY: grafana-metrics
grafana-metrics:
	@echo "Fetching Grafana metrics..."
	@kubectl exec $(POD) -n $(NAMESPACE) -- curl -s http://localhost:3000/metrics | head -50
	@echo "..."
	@echo "(Showing first 50 lines. Full metrics available via /metrics endpoint)"

# ============================================================================
# API Operations
# ============================================================================

.PHONY: grafana-api
grafana-api:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make grafana-api CMD='/api/health'"
	@exit 1
endif
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000$(CMD)
