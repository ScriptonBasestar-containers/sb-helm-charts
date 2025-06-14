# nextcloud 차트 설정
CHART_NAME := nextcloud
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include Makefile.common.mk

# nextcloud 특화 타겟
.PHONY: nextcloud-init
nextcloud-init:
	@echo "Initializing nextcloud..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- occ maintenance:install

.PHONY: nextcloud-setup
nextcloud-setup:
	@echo "Setting up nextcloud..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- occ maintenance:repair

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Nextcloud specific targets:"
	@echo "  nextcloud-init   - Initialize nextcloud installation"
	@echo "  nextcloud-setup  - Run nextcloud maintenance and repair"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
