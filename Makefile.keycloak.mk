# keycloak 차트 설정
CHART_NAME := keycloak
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include Makefile.common.mk

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
	@echo "Utilities:"
	@echo "  kc-pod-shell         - Open shell in Keycloak pod"
	@echo "  kc-db-test           - Test PostgreSQL connection"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
