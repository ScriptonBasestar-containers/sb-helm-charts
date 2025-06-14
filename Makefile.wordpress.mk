# wordpress 차트 설정
CHART_NAME := wordpress
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include Makefile.common.mk

# wordpress 특화 타겟
.PHONY: wp-cli
wp-cli:
	@echo "Running wp-cli command..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- wp $(CMD)

.PHONY: wp-install
wp-install:
	@echo "Installing WordPress..."
	@$(MAKE) -f Makefile.wordpress.mk wp-cli CMD="core install --url=$(URL) --title=$(TITLE) --admin_user=$(ADMIN_USER) --admin_password=$(ADMIN_PASSWORD) --admin_email=$(ADMIN_EMAIL)"

.PHONY: wp-update
wp-update:
	@echo "Updating WordPress..."
	@$(MAKE) -f Makefile.wordpress.mk wp-cli CMD="core update"
	@$(MAKE) -f Makefile.wordpress.mk wp-cli CMD="plugin update --all"
	@$(MAKE) -f Makefile.wordpress.mk wp-cli CMD="theme update --all"

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "WordPress specific targets:"
	@echo "  wp-cli           - Run wp-cli command (requires CMD parameter)"
	@echo "  wp-install       - Install WordPress (requires URL, TITLE, ADMIN_USER, ADMIN_PASSWORD, ADMIN_EMAIL)"
	@echo "  wp-update        - Update WordPress core, plugins, and themes"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
