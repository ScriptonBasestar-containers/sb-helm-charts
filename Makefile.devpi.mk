# devpi 차트 설정
CHART_NAME := devpi
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include Makefile.common.mk

# devpi 특화 타겟
.PHONY: devpi-init
devpi-init:
	@echo "Initializing devpi server..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- devpi-init --serverdir /app/data

.PHONY: devpi-create-user
devpi-create-user:
	@echo "Creating devpi user..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- devpi use http://localhost:3141
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- devpi login $(USERNAME) --password=$(PASSWORD)
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- devpi index $(USERNAME)/dev create bases=root/pypi

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Devpi specific targets:"
	@echo "  devpi-init        - Initialize devpi server"
	@echo "  devpi-create-user - Create a new devpi user (requires USERNAME and PASSWORD)"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
