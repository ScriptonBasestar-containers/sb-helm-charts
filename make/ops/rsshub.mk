# rsshub 차트 설정
CHART_NAME := rsshub
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# rsshub 특화 타겟
.PHONY: rsshub-check
rsshub-check:
	@echo "Checking RSSHub routes..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- npm run list

.PHONY: rsshub-cache-clear
rsshub-cache-clear:
	@echo "Clearing RSSHub cache..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- rm -rf /root/.cache

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "RSSHub specific targets:"
	@echo "  rsshub-check      - Check available RSSHub routes"
	@echo "  rsshub-cache-clear - Clear RSSHub cache"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
