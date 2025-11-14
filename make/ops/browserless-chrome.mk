# browserless-chrome 차트 설정
CHART_NAME := browserless-chrome
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# browserless-chrome 특화 타겟

# Health and Status
.PHONY: bc-health
bc-health:
	@echo "Checking browserless-chrome health..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/

.PHONY: bc-metrics
bc-metrics:
	@echo "Getting browserless-chrome metrics..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/metrics

.PHONY: bc-config
bc-config:
	@echo "Getting browserless-chrome configuration..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/config

.PHONY: bc-pressure
bc-pressure:
	@echo "Getting browserless-chrome pressure stats..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/pressure

# Session Management
.PHONY: bc-sessions
bc-sessions:
	@echo "Listing active browser sessions..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/sessions

.PHONY: bc-workspace
bc-workspace:
	@echo "Getting workspace information..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:3000/workspace

# Debugging and Testing
.PHONY: bc-screenshot
bc-screenshot:
	@echo "Testing screenshot capability..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -s -X POST http://localhost:3000/screenshot \
		-H "Content-Type: application/json" \
		-d '{"url": "https://example.com"}' > /dev/null && echo "Screenshot test successful"

.PHONY: bc-pdf
bc-pdf:
	@echo "Testing PDF generation capability..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -s -X POST http://localhost:3000/pdf \
		-H "Content-Type: application/json" \
		-d '{"url": "https://example.com"}' > /dev/null && echo "PDF test successful"

# Operations
.PHONY: bc-shell
bc-shell:
	@echo "Opening shell in browserless-chrome pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/sh

.PHONY: bc-logs
bc-logs:
	@echo "Showing browserless-chrome logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: bc-restart
bc-restart:
	@echo "Restarting browserless-chrome deployment..."
	@$(KUBECTL) rollout restart deployment/$(CHART_NAME)
	@$(KUBECTL) rollout status deployment/$(CHART_NAME)

.PHONY: bc-port-forward
bc-port-forward:
	@echo "Port-forwarding browserless-chrome service to localhost:3000..."
	@$(KUBECTL) port-forward service/$(CHART_NAME) 3000:3000

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "Browserless Chrome specific targets:"
	@echo ""
	@echo "Health and Status:"
	@echo "  bc-health           - Check browserless-chrome health status"
	@echo "  bc-metrics          - Get Prometheus metrics"
	@echo "  bc-config           - Get current configuration"
	@echo "  bc-pressure         - Get resource pressure statistics"
	@echo ""
	@echo "Session Management:"
	@echo "  bc-sessions         - List active browser sessions"
	@echo "  bc-workspace        - Get workspace information"
	@echo ""
	@echo "Debugging and Testing:"
	@echo "  bc-screenshot       - Test screenshot generation capability"
	@echo "  bc-pdf              - Test PDF generation capability"
	@echo ""
	@echo "Operations:"
	@echo "  bc-shell            - Open shell in browserless-chrome pod"
	@echo "  bc-logs             - Show browserless-chrome logs"
	@echo "  bc-restart          - Restart browserless-chrome deployment"
	@echo "  bc-port-forward     - Port-forward service to localhost:3000"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help 