# Immich Chart Operational Commands
#
# This Makefile provides day-2 operational commands for Immich deployments.

include make/common.mk

CHART_NAME := immich
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)
SERVER_SELECTOR := $(POD_SELECTOR),app.kubernetes.io/component=server
ML_SELECTOR := $(POD_SELECTOR),app.kubernetes.io/component=machine-learning

# ========================================
# Access & Debugging
# ========================================

## immich-port-forward: Port forward Immich web UI to localhost:2283
.PHONY: immich-port-forward
immich-port-forward:
	@echo "Forwarding Immich web UI to http://localhost:2283..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 2283:2283

## immich-logs-server: View Immich server logs
.PHONY: immich-logs-server
immich-logs-server:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server --tail=100

## immich-logs-ml: View Machine Learning service logs
.PHONY: immich-logs-ml
immich-logs-ml:
	@kubectl logs -f -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml --tail=100

## immich-shell-server: Open shell in server container
.PHONY: immich-shell-server
immich-shell-server:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## immich-shell-ml: Open shell in ML container
.PHONY: immich-shell-ml
immich-shell-ml:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## immich-restart: Restart all Immich deployments
.PHONY: immich-restart
immich-restart:
	@echo "Restarting Immich server..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server
	@echo "Restarting Machine Learning service..."
	@kubectl rollout restart -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-server
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-$(CHART_NAME)-ml

## immich-describe: Describe all Immich pods
.PHONY: immich-describe
immich-describe:
	@echo "=== Server Pod ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD
	@echo ""
	@echo "=== Machine Learning Pod ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## immich-events: Show all Immich pod events
.PHONY: immich-events
immich-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## immich-stats: Show resource usage statistics
.PHONY: immich-stats
immich-stats:
	@echo "=== Immich Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

# ========================================
# Database & Storage
# ========================================

## immich-check-db: Test PostgreSQL connection
.PHONY: immich-check-db
immich-check-db:
	@echo "Testing PostgreSQL connection..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	DB_HOST=$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.db-url}' | base64 -d | sed -n 's/.*@\([^:]*\):.*/\1/p'); \
	DB_USER=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep DB_USERNAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c "PGPASSWORD=\$$(kubectl get secret $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.data.db-password}' | base64 -d) pg_isready -h \$$DB_HOST -U \$$DB_USER" && \
	echo "PostgreSQL connection successful"

## immich-check-redis: Test Redis connection
.PHONY: immich-check-redis
immich-check-redis:
	@echo "Testing Redis connection..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	REDIS_HOST=$$(kubectl exec -n $(NAMESPACE) $$POD -- env | grep REDIS_HOSTNAME | cut -d= -f2); \
	kubectl exec -n $(NAMESPACE) $$POD -- redis-cli -h $$REDIS_HOST ping && \
	echo "Redis connection successful"

## immich-check-storage: Check library storage usage
.PHONY: immich-check-storage
immich-check-storage:
	@echo "=== Library Storage Usage ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data

## immich-check-ml-cache: Check ML model cache
.PHONY: immich-check-ml-cache
immich-check-ml-cache:
	@echo "=== ML Model Cache ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(ML_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- du -sh /cache 2>/dev/null || echo "Model cache not mounted"

# ========================================
# Configuration
# ========================================

## immich-get-config: Show current configuration
.PHONY: immich-get-config
immich-get-config:
	@echo "=== Immich Configuration ==="
	@echo ""
	@echo "Services:"
	@kubectl get deployment -n $(NAMESPACE) -l $(APP_LABEL) -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas
	@echo ""
	@echo "PostgreSQL:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep -E "^DB_"
	@echo ""
	@echo "Redis:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- env | grep -E "^REDIS_"

## immich-get-version: Show Immich version
.PHONY: immich-get-version
immich-get-version:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(SERVER_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:2283/api/server-info/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4

# ========================================
# Helm Operations
# ========================================

## help: Display this help message
.PHONY: help
help:
	@echo "Immich Chart - Operational Commands"
	@echo ""
	@echo "Access & Debugging:"
	@echo "  make immich-port-forward    - Port forward web UI to localhost:2283"
	@echo "  make immich-logs-server     - View server logs"
	@echo "  make immich-logs-ml         - View ML service logs"
	@echo "  make immich-shell-server    - Open server shell"
	@echo "  make immich-shell-ml        - Open ML shell"
	@echo "  make immich-restart         - Restart all deployments"
	@echo "  make immich-describe        - Describe all pods"
	@echo "  make immich-events          - Show pod events"
	@echo "  make immich-stats           - Show resource usage"
	@echo ""
	@echo "Database & Storage:"
	@echo "  make immich-check-db        - Test PostgreSQL connection"
	@echo "  make immich-check-redis     - Test Redis connection"
	@echo "  make immich-check-storage   - Check library storage usage"
	@echo "  make immich-check-ml-cache  - Check ML model cache"
	@echo ""
	@echo "Configuration:"
	@echo "  make immich-get-config      - Show current configuration"
	@echo "  make immich-get-version     - Show Immich version"
	@echo ""
	@echo "Helm Operations:"
	@echo "  make lint                   - Lint chart"
	@echo "  make build                  - Build/package chart"
	@echo "  make template               - Generate templates"
	@echo "  make install                - Install chart"
	@echo "  make upgrade                - Upgrade chart"
	@echo "  make uninstall              - Uninstall chart"
	@echo ""
	@echo "Environment Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
