# Makefile for memcached chart operations
# Include common targets and variables
include Makefile.common.mk

CHART_NAME := memcached
CHART_DIR := charts/$(CHART_NAME)

# Override the default help to include memcached-specific commands
.PHONY: help
help:
	@echo "Memcached Chart Operations:"
	@echo "  make lint              - Lint the memcached chart"
	@echo "  make build             - Build/package the memcached chart"
	@echo "  make template          - Generate templates for the memcached chart"
	@echo "  make install           - Install the memcached chart"
	@echo "  make upgrade           - Upgrade the memcached chart"
	@echo "  make uninstall         - Uninstall the memcached chart"
	@echo ""
	@echo "Memcached Operations:"
	@echo "  make mc-stats          - Show memcached statistics"
	@echo "  make mc-flush          - Flush all data from memcached"
	@echo "  make mc-version        - Show memcached version"
	@echo "  make mc-settings       - Show memcached settings"
	@echo "  make mc-slabs          - Show memcached slab statistics"
	@echo "  make mc-items          - Show memcached item statistics"
	@echo "  make mc-logs           - Show memcached logs"
	@echo "  make mc-shell          - Open shell in memcached pod"
	@echo "  make mc-port-forward   - Port forward to memcached (11211:11211)"
	@echo ""
	@echo "Variables:"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  NAMESPACE=$(NAMESPACE)"

# Memcached-specific operations

.PHONY: mc-stats
mc-stats: ## Show memcached statistics
	@echo "Fetching memcached statistics..."
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "stats" | nc localhost 11211'

.PHONY: mc-flush
mc-flush: ## Flush all data from memcached (WARNING: This will clear all cached data)
	@echo "⚠️  WARNING: This will flush all data from memcached!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "flush_all" | nc localhost 11211'
	@echo "All memcached data flushed."

.PHONY: mc-version
mc-version: ## Show memcached version
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "version" | nc localhost 11211'

.PHONY: mc-settings
mc-settings: ## Show memcached settings
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "stats settings" | nc localhost 11211'

.PHONY: mc-slabs
mc-slabs: ## Show memcached slab statistics
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "stats slabs" | nc localhost 11211'

.PHONY: mc-items
mc-items: ## Show memcached item statistics
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD_NAME -- sh -c 'echo "stats items" | nc localhost 11211'

.PHONY: mc-logs
mc-logs: ## Show memcached logs
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl logs -n $(NAMESPACE) $$POD_NAME --tail=100 -f

.PHONY: mc-shell
mc-shell: ## Open shell in memcached pod
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) -it $$POD_NAME -- /bin/sh

.PHONY: mc-port-forward
mc-port-forward: ## Port forward to memcached (11211:11211)
	@POD_NAME=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	echo "Port forwarding to $$POD_NAME:11211..."; \
	echo "Connect to localhost:11211"; \
	kubectl port-forward -n $(NAMESPACE) $$POD_NAME 11211:11211
