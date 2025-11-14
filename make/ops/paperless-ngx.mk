# Paperless-ngx 차트 운영 명령어

include make/common.mk

CHART_NAME := paperless-ngx
CHART_DIR := charts/$(CHART_NAME)

.PHONY: help
help:
	@echo "Paperless-ngx Chart Operations:"
	@echo "  paperless-logs         - View Paperless-ngx logs"
	@echo "  paperless-shell        - Open shell in Paperless-ngx pod"
	@echo "  paperless-port-forward - Port forward to localhost:8000"
	@echo ""
	@echo "  paperless-check-db     - Test PostgreSQL connection"
	@echo "  paperless-check-redis  - Test Redis connection"
	@echo "  paperless-check-storage - Check storage usage"
	@echo ""
	@echo "  paperless-migrate      - Run database migrations"
	@echo "  paperless-create-superuser - Create admin user"
	@echo "  paperless-document-exporter - Export all documents"
	@echo ""
	@echo "  paperless-consume-list - List consume directory"
	@echo "  paperless-process-status - Check document processing status"
	@echo "  paperless-restart      - Restart Paperless-ngx deployment"
	@echo ""
	@echo "Common targets:"
	@$(MAKE) -s -f make/common.mk help

# 기본 운영 명령어
.PHONY: paperless-logs
paperless-logs:
	@echo "Viewing Paperless-ngx logs..."
	$(KUBECTL) logs -f deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

.PHONY: paperless-shell
paperless-shell:
	@echo "Opening shell in Paperless-ngx pod..."
	$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- /bin/bash

.PHONY: paperless-port-forward
paperless-port-forward:
	@echo "Port forwarding to localhost:8000..."
	@echo "Visit http://localhost:8000"
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 8000:8000

# 헬스 체크
.PHONY: paperless-check-db
paperless-check-db:
	@echo "Testing PostgreSQL connection..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py dbshell --command "SELECT version();"

.PHONY: paperless-check-redis
paperless-check-redis:
	@echo "Testing Redis connection..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'echo "PING" | redis-cli -h $$PAPERLESS_REDIS_HOST'

.PHONY: paperless-check-storage
paperless-check-storage:
	@echo "Checking storage usage..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		df -h | grep -E "Filesystem|/usr/src/paperless"

# 데이터베이스 관리
.PHONY: paperless-migrate
paperless-migrate:
	@echo "Running database migrations..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py migrate

.PHONY: paperless-create-superuser
paperless-create-superuser:
	@echo "Creating superuser (interactive)..."
	$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py createsuperuser

# 문서 관리
.PHONY: paperless-document-exporter
paperless-document-exporter:
	@echo "Exporting all documents to /usr/src/paperless/export/..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_exporter /usr/src/paperless/export/

.PHONY: paperless-consume-list
paperless-consume-list:
	@echo "Listing files in consume directory..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		ls -lh /usr/src/paperless/consume/

.PHONY: paperless-process-status
paperless-process-status:
	@echo "Checking document processing status..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_sanity_checker

# 운영
.PHONY: paperless-restart
paperless-restart:
	@echo "Restarting Paperless-ngx deployment..."
	$(KUBECTL) rollout restart deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)
	$(KUBECTL) rollout status deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

# 차트 기본 명령어
.PHONY: lint
lint:
	@$(MAKE) -s -f make/common.mk lint

.PHONY: build
build:
	@$(MAKE) -s -f make/common.mk build

.PHONY: template
template:
	@$(MAKE) -s -f make/common.mk template

.PHONY: install
install:
	@$(MAKE) -s -f make/common.mk install

.PHONY: upgrade
upgrade:
	@$(MAKE) -s -f make/common.mk upgrade

.PHONY: uninstall
uninstall:
	@$(MAKE) -s -f make/common.mk uninstall
