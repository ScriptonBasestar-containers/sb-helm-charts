# Grafana Chart Operations

include Makefile.common.mk

CHART_NAME := grafana
CHART_DIR := charts/grafana
NAMESPACE ?= default
RELEASE_NAME ?= grafana

POD ?= $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

.PHONY: help
help::
	@echo ""
	@echo "Grafana Operations:"
	@echo "  grafana-shell            - Open shell in Grafana pod"
	@echo "  grafana-logs             - View Grafana logs"
	@echo "  grafana-port-forward     - Port forward to localhost:3000"
	@echo ""
	@echo "Credentials & Access:"
	@echo "  grafana-get-password     - Get admin password"
	@echo "  grafana-reset-password PASSWORD=... - Reset admin password"
	@echo ""
	@echo "Data Sources:"
	@echo "  grafana-list-datasources - List all data sources"
	@echo "  grafana-add-prometheus URL=... - Add Prometheus data source"
	@echo "  grafana-add-loki URL=...       - Add Loki data source"
	@echo ""
	@echo "Dashboards:"
	@echo "  grafana-list-dashboards  - List all dashboards"
	@echo "  grafana-export-dashboard UID=... - Export dashboard JSON"
	@echo "  grafana-import-dashboard FILE=... - Import dashboard from JSON"
	@echo ""
	@echo "Database:"
	@echo "  grafana-db-backup        - Backup Grafana database"
	@echo "  grafana-db-restore FILE=... - Restore database"
	@echo ""
	@echo "Operations:"
	@echo "  grafana-restart          - Restart Grafana deployment"
	@echo "  grafana-api CMD='...'    - Run Grafana API command"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"

.PHONY: grafana-shell
grafana-shell:
	@echo "Opening shell in Grafana pod: $(POD)"
	kubectl exec -it $(POD) -n $(NAMESPACE) -- /bin/bash

.PHONY: grafana-logs
grafana-logs:
	@echo "Viewing logs for Grafana pod: $(POD)"
	kubectl logs -f $(POD) -n $(NAMESPACE)

.PHONY: grafana-port-forward
grafana-port-forward:
	@echo "Port forwarding Grafana to localhost:3000"
	@echo "Access Grafana at: http://localhost:3000"
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 3000:80

.PHONY: grafana-get-password
grafana-get-password:
	@echo "Grafana admin password:"
	@kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d
	@echo ""

.PHONY: grafana-reset-password
grafana-reset-password:
ifndef PASSWORD
	@echo "Error: PASSWORD variable required. Usage: make grafana-reset-password PASSWORD=newpass"
	@exit 1
endif
	@echo "Resetting admin password..."
	kubectl exec $(POD) -n $(NAMESPACE) -- grafana-cli admin reset-admin-password $(PASSWORD)

.PHONY: grafana-list-datasources
grafana-list-datasources:
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/datasources

.PHONY: grafana-add-prometheus
grafana-add-prometheus:
ifndef URL
	@echo "Error: URL variable required. Usage: make grafana-add-prometheus URL=http://prometheus:9090"
	@exit 1
endif
	@echo "Adding Prometheus data source: $(URL)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d '{"name":"Prometheus","type":"prometheus","url":"$(URL)","access":"proxy","isDefault":true}' \
		http://localhost:3000/api/datasources

.PHONY: grafana-add-loki
grafana-add-loki:
ifndef URL
	@echo "Error: URL variable required. Usage: make grafana-add-loki URL=http://loki:3100"
	@exit 1
endif
	@echo "Adding Loki data source: $(URL)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d '{"name":"Loki","type":"loki","url":"$(URL)","access":"proxy"}' \
		http://localhost:3000/api/datasources

.PHONY: grafana-list-dashboards
grafana-list-dashboards:
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000/api/search

.PHONY: grafana-export-dashboard
grafana-export-dashboard:
ifndef UID
	@echo "Error: UID variable required. Usage: make grafana-export-dashboard UID=dashboard-uid"
	@exit 1
endif
	@mkdir -p tmp/grafana-dashboards
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS \
		http://localhost:3000/api/dashboards/uid/$(UID) > tmp/grafana-dashboards/$(UID).json
	@echo "Dashboard exported to: tmp/grafana-dashboards/$(UID).json"

.PHONY: grafana-import-dashboard
grafana-import-dashboard:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make grafana-import-dashboard FILE=dashboard.json"
	@exit 1
endif
	@echo "Importing dashboard from: $(FILE)"
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	DASHBOARD=$$(cat $(FILE) | jq '{dashboard: .dashboard, overwrite: true}'); \
	kubectl exec -i $(POD) -n $(NAMESPACE) -- curl -X POST -H "Content-Type: application/json" \
		-u admin:$$ADMIN_PASS \
		-d "$$DASHBOARD" \
		http://localhost:3000/api/dashboards/db

.PHONY: grafana-db-backup
grafana-db-backup:
	@echo "Backing up Grafana database..."
	@mkdir -p tmp/grafana-backups
	@kubectl exec $(POD) -n $(NAMESPACE) -- tar czf - /var/lib/grafana/grafana.db > tmp/grafana-backups/grafana-db-$$(date +%Y%m%d-%H%M%S).tar.gz
	@echo "Backup saved to: tmp/grafana-backups/"

.PHONY: grafana-db-restore
grafana-db-restore:
ifndef FILE
	@echo "Error: FILE variable required. Usage: make grafana-db-restore FILE=backup.tar.gz"
	@exit 1
endif
	@echo "Restoring Grafana database from: $(FILE)"
	@echo "WARNING: This will overwrite the current database. Continue? (Ctrl+C to cancel)"
	@read -p "Press Enter to continue..."
	cat $(FILE) | kubectl exec -i $(POD) -n $(NAMESPACE) -- tar xzf - -C /
	@echo "Restore completed. Restarting Grafana..."
	@$(MAKE) grafana-restart

.PHONY: grafana-restart
grafana-restart:
	@echo "Restarting Grafana deployment..."
	kubectl rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE)

.PHONY: grafana-api
grafana-api:
ifndef CMD
	@echo "Error: CMD variable required. Usage: make grafana-api CMD='/api/health'"
	@exit 1
endif
	@ADMIN_PASS=$$(kubectl get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath="{.data.admin-password}" | base64 -d); \
	kubectl exec $(POD) -n $(NAMESPACE) -- curl -s -u admin:$$ADMIN_PASS http://localhost:3000$(CMD)
