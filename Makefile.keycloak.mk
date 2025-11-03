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

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
