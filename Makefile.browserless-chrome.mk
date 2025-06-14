# browserless-chrome 차트 설정
CHART_NAME := browserless-chrome
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include Makefile.common.mk

# browserless-chrome 특화 타겟
.PHONY: browserless-health
browserless-health:
	@echo "Checking browserless-chrome health..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/health

.PHONY: browserless-metrics
browserless-metrics:
	@echo "Getting browserless-chrome metrics..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/metrics

.PHONY: browserless-debug
browserless-debug:
	@echo "Getting browserless-chrome debug info..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/debug

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Browserless Chrome specific targets:"
	@echo "  browserless-health  - Check browserless-chrome health status"
	@echo "  browserless-metrics - Get browserless-chrome metrics"
	@echo "  browserless-debug   - Get browserless-chrome debug information"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help 