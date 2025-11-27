# keycloak 차트 설정
CHART_NAME := keycloak
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# keycloak 특화 타겟
.PHONY: kc-cli
kc-cli:
	@echo "Running kcadm.sh command..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /opt/keycloak/bin/kcadm.sh $(CMD)

.PHONY: kc-export-realm
kc-export-realm:
	@echo "Exporting realm: $(REALM)"
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /opt/keycloak/bin/kc.sh export --realm=$(REALM) --dir=/tmp

.PHONY: kc-health
kc-health:
	@echo "Checking Keycloak health..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:8080/health

.PHONY: kc-metrics
kc-metrics:
	@echo "Fetching Keycloak metrics..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:8080/metrics

.PHONY: kc-cluster-status
kc-cluster-status:
	@echo "Checking Keycloak cluster status..."
	@$(KUBECTL) logs -l app.kubernetes.io/name=$(CHART_NAME) --tail=50 | grep -i "jgroups\|cluster\|member"

.PHONY: kc-backup-all-realms
kc-backup-all-realms:
	@echo "Backing up all Keycloak realms..."
	@mkdir -p tmp/keycloak-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /opt/keycloak/bin/kc.sh export --dir=/tmp/backup
	@$(KUBECTL) cp $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/tmp/backup tmp/keycloak-backups/$$(date +%Y%m%d-%H%M%S)
	@echo "Backup completed: tmp/keycloak-backups/$$(date +%Y%m%d-%H%M%S)"

.PHONY: kc-import-realm
kc-import-realm:
	@echo "Importing realm from file: $(FILE)"
	@if [ -z "$(FILE)" ]; then echo "Error: FILE parameter required"; exit 1; fi
	@$(KUBECTL) cp $(FILE) $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/tmp/import-realm.json
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /opt/keycloak/bin/kc.sh import --file=/tmp/import-realm.json
	@echo "Realm imported successfully"

.PHONY: kc-list-realms
kc-list-realms:
	@echo "Listing all realms..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:8080/admin/realms | grep -o '"realm":"[^"]*"' | cut -d'"' -f4

.PHONY: kc-pod-shell
kc-pod-shell:
	@echo "Opening shell in Keycloak pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/bash

.PHONY: kc-db-test
kc-db-test:
	@echo "Testing PostgreSQL connection..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- pg_isready -h $$($(KUBECTL) get secret $(CHART_NAME) -o jsonpath="{.data.db-host}" | base64 -d) || echo "Connection test from pod"

# === Backup & Recovery ===

.PHONY: kc-backup-restore
kc-backup-restore:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/keycloak.mk kc-backup-restore FILE=path/to/backup-dir"; exit 1; fi
	@echo "Restoring Keycloak realms from $(FILE)..."
	@$(KUBECTL) cp $(FILE) $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/tmp/restore
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /opt/keycloak/bin/kc.sh import --dir=/tmp/restore
	@echo "Restore completed successfully"

.PHONY: kc-backup-verify
kc-backup-verify:
	@if [ -z "$(DIR)" ]; then echo "Usage: make -f make/ops/keycloak.mk kc-backup-verify DIR=path/to/backup-dir"; exit 1; fi
	@echo "Verifying backup integrity: $(DIR)"
	@if [ ! -d "$(DIR)" ]; then echo "Error: Backup directory not found"; exit 1; fi
	@echo "Checking for realm JSON files..."
	@find $(DIR) -name "*.json" -type f | wc -l | xargs -I {} echo "Found {} realm files"
	@echo "Validating JSON syntax..."
	@find $(DIR) -name "*.json" -type f -exec sh -c 'jq empty {} 2>/dev/null || echo "Invalid JSON: {}"' \;
	@echo "Backup verification completed"

.PHONY: kc-db-backup
kc-db-backup:
	@echo "Creating PostgreSQL backup for Keycloak database..."
	@mkdir -p tmp/keycloak-backups/db
	@POSTGRES_POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].metadata.name}") && \
		if [ -z "$$POSTGRES_POD" ]; then \
			echo "Warning: PostgreSQL pod not found. Ensure PostgreSQL is deployed in the same namespace."; \
			exit 1; \
		fi && \
		$(KUBECTL) exec $$POSTGRES_POD -- sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dump -U postgres keycloak' > tmp/keycloak-backups/db/keycloak-db-$$(date +%Y%m%d-%H%M%S).sql
	@echo "Database backup saved to tmp/keycloak-backups/db/keycloak-db-$$(date +%Y%m%d-%H%M%S).sql"

.PHONY: kc-db-restore
kc-db-restore:
	@if [ -z "$(FILE)" ]; then echo "Usage: make -f make/ops/keycloak.mk kc-db-restore FILE=path/to/backup.sql"; exit 1; fi
	@echo "Restoring Keycloak database from $(FILE)..."
	@POSTGRES_POD=$$($(KUBECTL) get pod -l app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].metadata.name}") && \
		if [ -z "$$POSTGRES_POD" ]; then \
			echo "Error: PostgreSQL pod not found"; \
			exit 1; \
		fi && \
		cat $(FILE) | $(KUBECTL) exec -i $$POSTGRES_POD -- sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" psql -U postgres keycloak'
	@echo "Database restore completed"

.PHONY: kc-realm-migrate
kc-realm-migrate:
	@if [ -z "$(REALM)" ]; then echo "Usage: make -f make/ops/keycloak.mk kc-realm-migrate REALM=realm-name"; exit 1; fi
	@echo "Exporting realm '$(REALM)' for migration..."
	@mkdir -p tmp/keycloak-backups/migration
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		/opt/keycloak/bin/kc.sh export --realm=$(REALM) --dir=/tmp/migration --users=realm_file
	@$(KUBECTL) cp $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/tmp/migration/$(REALM)-realm.json \
		tmp/keycloak-backups/migration/$(REALM)-realm-$$(date +%Y%m%d-%H%M%S).json
	@echo "Realm exported to tmp/keycloak-backups/migration/$(REALM)-realm-$$(date +%Y%m%d-%H%M%S).json"

# === Upgrade Operations ===

.PHONY: kc-pre-upgrade-check
kc-pre-upgrade-check:
	@echo "=== Pre-Upgrade Health Check ==="
	@echo "1. Checking Keycloak health endpoints..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -sf http://localhost:9000/health/ready > /dev/null && echo "  ✓ Ready" || echo "  ✗ Not Ready"
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -sf http://localhost:9000/health/live > /dev/null && echo "  ✓ Live" || echo "  ✗ Not Live"
	@echo ""
	@echo "2. Checking database connectivity..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		pg_isready -h localhost || echo "  ⚠ Database connectivity issues detected"
	@echo ""
	@echo "3. Listing current realms..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -s http://localhost:8080/admin/realms | grep -o '"realm":"[^"]*"' | cut -d'"' -f4 || echo "  ⚠ Unable to list realms"
	@echo ""
	@echo "Pre-upgrade check completed. Review results before proceeding."

.PHONY: kc-post-upgrade-check
kc-post-upgrade-check:
	@echo "=== Post-Upgrade Validation ==="
	@echo "1. Waiting for pods to be ready..."
	@$(KUBECTL) wait --for=condition=ready pod -l app.kubernetes.io/name=$(CHART_NAME) --timeout=300s
	@echo ""
	@echo "2. Checking health endpoints..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -sf http://localhost:9000/health/ready > /dev/null && echo "  ✓ Ready" || echo "  ✗ Not Ready"
	@echo ""
	@echo "3. Verifying realm integrity..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -s http://localhost:8080/admin/realms | grep -o '"realm":"[^"]*"' | cut -d'"' -f4 || echo "  ⚠ Unable to verify realms"
	@echo ""
	@echo "Post-upgrade validation completed."

.PHONY: kc-upgrade-rollback-plan
kc-upgrade-rollback-plan:
	@echo "=== Keycloak Upgrade Rollback Plan ==="
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Pre-upgrade backup exists: tmp/keycloak-backups/"
	@echo "  2. Database backup exists: tmp/keycloak-backups/db/"
	@echo ""
	@echo "Rollback Steps:"
	@echo "  1. Scale down Keycloak:"
	@echo "     kubectl scale statefulset $(CHART_NAME) --replicas=0"
	@echo ""
	@echo "  2. Restore database:"
	@echo "     make -f make/ops/keycloak.mk kc-db-restore FILE=<backup-file>"
	@echo ""
	@echo "  3. Downgrade Helm chart:"
	@echo "     helm rollback $(CHART_NAME) <revision>"
	@echo ""
	@echo "  4. Verify rollback:"
	@echo "     make -f make/ops/keycloak.mk kc-post-upgrade-check"
	@echo ""
	@echo "Emergency Contact:"
	@echo "  - Check logs: kubectl logs -l app.kubernetes.io/name=$(CHART_NAME)"
	@echo "  - Pod shell: make -f make/ops/keycloak.mk kc-pod-shell"

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Keycloak specific targets:"
	@echo "  kc-cli              - Run kcadm.sh command (requires CMD parameter)"
	@echo "  kc-export-realm     - Export realm (requires REALM parameter)"
	@echo "  kc-health           - Check Keycloak health endpoints"
	@echo "  kc-metrics          - Fetch Prometheus metrics"
	@echo "  kc-cluster-status   - Check cluster status from logs"
	@echo ""
	@echo "Realm Management:"
	@echo "  kc-backup-all-realms - Backup all realms to tmp/keycloak-backups/"
	@echo "  kc-import-realm      - Import realm (requires FILE parameter)"
	@echo "  kc-list-realms       - List all realms"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  kc-backup-restore    - Restore realms from backup (requires FILE parameter)"
	@echo "  kc-backup-verify     - Verify backup integrity (requires DIR parameter)"
	@echo "  kc-db-backup         - Backup Keycloak PostgreSQL database"
	@echo "  kc-db-restore        - Restore database backup (requires FILE parameter)"
	@echo "  kc-realm-migrate     - Export realm for migration (requires REALM parameter)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  kc-pre-upgrade-check  - Pre-upgrade health and readiness check"
	@echo "  kc-post-upgrade-check - Post-upgrade validation"
	@echo "  kc-upgrade-rollback-plan - Display rollback procedures"
	@echo ""
	@echo "Utilities:"
	@echo "  kc-pod-shell         - Open shell in Keycloak pod"
	@echo "  kc-db-test           - Test PostgreSQL connection"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
