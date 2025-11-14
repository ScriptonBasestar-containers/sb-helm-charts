# redis 차트 설정
CHART_NAME := redis
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Redis 특화 타겟
.PHONY: redis-cli
redis-cli:
	@echo "Running redis-cli command..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli $(CMD)

.PHONY: redis-ping
redis-ping:
	@echo "Pinging Redis server..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli ping

.PHONY: redis-info
redis-info:
	@echo "Getting Redis server info..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli info

.PHONY: redis-monitor
redis-monitor:
	@echo "Monitoring Redis commands in real-time..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli monitor

.PHONY: redis-memory
redis-memory:
	@echo "Getting Redis memory info..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli info memory

.PHONY: redis-stats
redis-stats:
	@echo "Getting Redis stats..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli info stats

.PHONY: redis-clients
redis-clients:
	@echo "Listing Redis client connections..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli client list

.PHONY: redis-bgsave
redis-bgsave:
	@echo "Triggering background save..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli bgsave

.PHONY: redis-backup
redis-backup:
	@echo "Backing up Redis data..."
	@mkdir -p tmp/redis-backups
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli bgsave
	@sleep 5
	@$(KUBECTL) cp $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/data/dump.rdb tmp/redis-backups/dump-$$(date +%Y%m%d-%H%M%S).rdb
	@echo "Backup completed: tmp/redis-backups/dump-$$(date +%Y%m%d-%H%M%S).rdb"

.PHONY: redis-restore
redis-restore:
	@echo "Restoring Redis data from file: $(FILE)"
	@if [ -z "$(FILE)" ]; then echo "Error: FILE parameter required"; exit 1; fi
	@$(KUBECTL) cp $(FILE) $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}"):/data/dump.rdb
	@echo "Restarting Redis to load backup..."
	@$(KUBECTL) delete pod $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")
	@echo "Restore completed. Wait for pod to restart."

.PHONY: redis-flushall
redis-flushall:
	@echo "WARNING: This will delete ALL data in Redis!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli flushall
	@echo "All data flushed"

.PHONY: redis-slowlog
redis-slowlog:
	@echo "Getting Redis slow log..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli slowlog get 10

.PHONY: redis-bigkeys
redis-bigkeys:
	@echo "Finding biggest keys..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli --bigkeys

.PHONY: redis-config-get
redis-config-get:
	@echo "Getting Redis configuration: $(PARAM)"
	@if [ -z "$(PARAM)" ]; then \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli config get '*'; \
	else \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- redis-cli config get $(PARAM); \
	fi

.PHONY: redis-shell
redis-shell:
	@echo "Opening shell in Redis pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/sh

.PHONY: redis-logs
redis-logs:
	@echo "Tailing Redis logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: redis-metrics
redis-metrics:
	@echo "Fetching Redis metrics (if exporter is enabled)..."
	@$(KUBECTL) port-forward $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") 9121:9121 &
	@sleep 2
	@curl -s http://localhost:9121/metrics || echo "Metrics exporter not enabled or not accessible"
	@pkill -f "port-forward.*9121"

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Redis specific targets:"
	@echo "  redis-cli            - Run redis-cli command (requires CMD parameter)"
	@echo "  redis-ping           - Ping Redis server"
	@echo "  redis-info           - Get Redis server info"
	@echo "  redis-monitor        - Monitor Redis commands in real-time"
	@echo "  redis-memory         - Get Redis memory info"
	@echo "  redis-stats          - Get Redis statistics"
	@echo "  redis-clients        - List client connections"
	@echo ""
	@echo "Data Management:"
	@echo "  redis-bgsave         - Trigger background save"
	@echo "  redis-backup         - Backup Redis data to tmp/redis-backups/"
	@echo "  redis-restore        - Restore from backup (requires FILE parameter)"
	@echo "  redis-flushall       - Delete ALL data (with confirmation)"
	@echo ""
	@echo "Analysis:"
	@echo "  redis-slowlog        - Get slow query log"
	@echo "  redis-bigkeys        - Find biggest keys"
	@echo "  redis-config-get     - Get config (optional PARAM parameter)"
	@echo ""
	@echo "Utilities:"
	@echo "  redis-shell          - Open shell in Redis pod"
	@echo "  redis-logs           - Tail Redis logs"
	@echo "  redis-metrics        - Fetch Prometheus metrics (if enabled)"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
