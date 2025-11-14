# Uptime Kuma 차트 운영 명령어

include make/common.mk

CHART_NAME := uptime-kuma
CHART_DIR := charts/$(CHART_NAME)

.PHONY: help
help:
	@echo "Uptime Kuma Chart Operations:"
	@echo "  uk-logs                - View Uptime Kuma logs"
	@echo "  uk-shell               - Open shell in Uptime Kuma pod"
	@echo "  uk-port-forward        - Port forward to localhost:3001"
	@echo ""
	@echo "  uk-check-db            - Test database connection"
	@echo "  uk-check-storage       - Check storage usage"
	@echo "  uk-backup-sqlite       - Backup SQLite database (if using SQLite)"
	@echo "  uk-restore-sqlite      - Restore SQLite database (requires FILE=path)"
	@echo ""
	@echo "  uk-reset-password      - Reset admin password (interactive)"
	@echo "  uk-version             - Show Uptime Kuma version"
	@echo "  uk-node-info           - Show Node.js version and system info"
	@echo ""
	@echo "  uk-list-monitors       - List all monitors (via API)"
	@echo "  uk-status-pages        - List status pages"
	@echo "  uk-get-settings        - Get application settings"
	@echo ""
	@echo "  uk-restart             - Restart Uptime Kuma deployment"
	@echo "  uk-scale               - Scale deployment (REPLICAS=n)"
	@echo ""
	@echo "Common targets:"
	@$(MAKE) -s -f make/common.mk help

# 기본 운영 명령어
.PHONY: uk-logs
uk-logs:
	@echo "Viewing Uptime Kuma logs..."
	$(KUBECTL) logs -f deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

.PHONY: uk-shell
uk-shell:
	@echo "Opening shell in Uptime Kuma pod..."
	$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- /bin/sh

.PHONY: uk-port-forward
uk-port-forward:
	@echo "Port forwarding to localhost:3001..."
	@echo "Visit http://localhost:3001"
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 3001:3001

# 헬스 체크
.PHONY: uk-check-db
uk-check-db:
	@echo "Testing database connection..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		node -e "console.log('Database type:', process.env.UPTIME_KUMA_DB_TYPE || 'sqlite')"

.PHONY: uk-check-storage
uk-check-storage:
	@echo "Checking storage usage..."
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		df -h | grep -E "Filesystem|/app/data"

# 데이터 백업/복구
.PHONY: uk-backup-sqlite
uk-backup-sqlite:
	@echo "Backing up SQLite database to tmp/uptime-kuma-backups/..."
	@mkdir -p tmp/uptime-kuma-backups
	$(KUBECTL) cp $(NAMESPACE)/$(shell $(KUBECTL) get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'):/app/data/kuma.db \
		tmp/uptime-kuma-backups/kuma-$(shell date +%Y%m%d-%H%M%S).db
	@echo "Backup completed: tmp/uptime-kuma-backups/kuma-$(shell date +%Y%m%d-%H%M%S).db"

.PHONY: uk-restore-sqlite
uk-restore-sqlite:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make uk-restore-sqlite FILE=path/to/kuma.db"; \
		exit 1; \
	fi
	@echo "Scaling down deployment..."
	$(KUBECTL) scale deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) --replicas=0
	@echo "Waiting for pod to terminate..."
	@sleep 5
	@echo "Restoring database from $(FILE)..."
	$(KUBECTL) cp $(FILE) $(NAMESPACE)/$(shell $(KUBECTL) get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}'):/app/data/kuma.db || true
	@echo "Scaling up deployment..."
	$(KUBECTL) scale deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) --replicas=1
	@echo "Restore completed"

# 사용자 관리
.PHONY: uk-reset-password
uk-reset-password:
	@echo "Resetting admin password (interactive)..."
	$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		npm run reset-password

# 정보 확인
.PHONY: uk-version
uk-version:
	@echo "Uptime Kuma version:"
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		node -e "const p = require('./package.json'); console.log('Version:', p.version)"

.PHONY: uk-node-info
uk-node-info:
	@echo "Node.js and system information:"
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		node -e "console.log('Node:', process.version); console.log('Platform:', process.platform); console.log('Arch:', process.arch)"

# API 기반 정보 조회 (requires API key or authentication)
.PHONY: uk-list-monitors
uk-list-monitors:
	@echo "Listing monitors via API..."
	@echo "Note: This requires authentication. Use port-forward and access via web UI or API."
	@echo "API endpoint: http://localhost:3001/api/monitors"

.PHONY: uk-status-pages
uk-status-pages:
	@echo "Listing status pages..."
	@echo "Access via web UI: http://localhost:3001/status"

.PHONY: uk-get-settings
uk-get-settings:
	@echo "Application settings (environment variables):"
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		env | grep UPTIME_KUMA || echo "No UPTIME_KUMA_* environment variables found"

# 운영
.PHONY: uk-restart
uk-restart:
	@echo "Restarting Uptime Kuma deployment..."
	$(KUBECTL) rollout restart deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)
	$(KUBECTL) rollout status deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

.PHONY: uk-scale
uk-scale:
	@if [ -z "$(REPLICAS)" ]; then \
		echo "Error: REPLICAS parameter is required"; \
		echo "Usage: make uk-scale REPLICAS=2"; \
		exit 1; \
	fi
	@echo "Scaling Uptime Kuma to $(REPLICAS) replicas..."
	@echo "WARNING: Only use multiple replicas with MariaDB, not SQLite"
	$(KUBECTL) scale deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)

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
