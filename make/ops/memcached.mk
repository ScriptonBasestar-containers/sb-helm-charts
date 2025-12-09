# Makefile for memcached chart operations
# Include common targets and variables
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

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
	@echo "Backup & Recovery:"
	@echo "  make mc-backup-config  - Backup Memcached configuration"
	@echo "  make mc-backup-all     - Backup configuration + Kubernetes resources"
	@echo "  make mc-restore-config - Restore configuration from backup (FILE=<backup.yaml>)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  make mc-pre-upgrade    - Pre-upgrade validation checks"
	@echo "  make mc-post-upgrade   - Post-upgrade validation"
	@echo "  make mc-rollback       - Rollback to previous Helm release"
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

# Backup & Recovery Operations

.PHONY: mc-backup-config
mc-backup-config: ## Backup Memcached configuration
	@echo "Backing up Memcached configuration..."
	@BACKUP_FILE="memcached-config-backup-$$(date +%Y%m%d-%H%M%S).yaml"; \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME) -o yaml > $$BACKUP_FILE 2>/dev/null || true; \
	echo "Configuration backed up to: $$BACKUP_FILE"

.PHONY: mc-backup-all
mc-backup-all: ## Full backup (configuration + K8s resources)
	@echo "=== Full Memcached Backup ==="
	@echo ""
	@BACKUP_DIR="memcached-backup-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p $$BACKUP_DIR && \
	echo "[1/3] Backing up configuration..." && \
	kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME) -o yaml > $$BACKUP_DIR/config.yaml 2>/dev/null || echo "  - No ConfigMap found" && \
	echo "" && \
	echo "[2/3] Backing up Helm values..." && \
	helm get values $(RELEASE_NAME) -n $(NAMESPACE) > $$BACKUP_DIR/values.yaml && \
	echo "  ✓ Helm values saved to $$BACKUP_DIR/values.yaml" && \
	echo "" && \
	echo "[3/3] Backing up Kubernetes resources..." && \
	kubectl get all,pdb,networkpolicy -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $$BACKUP_DIR/k8s-resources.yaml && \
	echo "  ✓ Kubernetes resources saved to $$BACKUP_DIR/k8s-resources.yaml" && \
	echo "" && \
	echo "=== Backup Complete ===" && \
	echo "Backup directory: $$BACKUP_DIR"

.PHONY: mc-restore-config
mc-restore-config: ## Restore configuration from backup (FILE=<backup.yaml>)
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make mc-restore-config FILE=<backup-file.yaml>"; \
		exit 1; \
	fi
	@echo "Restoring Memcached configuration from $(FILE)..."
	@kubectl apply -f $(FILE)
	@echo ""
	@echo "Configuration restored. Restarting pods..."
	@kubectl rollout restart deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	@kubectl rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE)
	@echo "  ✓ Configuration restore complete"

# Upgrade Operations

.PHONY: mc-pre-upgrade
mc-pre-upgrade: ## Pre-upgrade validation checks
	@echo "=== Pre-Upgrade Validation ==="
	@echo ""
	@echo "[1/5] Checking current status..."
	@kubectl get deployment -n $(NAMESPACE) $(RELEASE_NAME) || (echo "  ✗ Deployment not found"; exit 1)
	@echo "  ✓ Deployment found"
	@echo ""
	@echo "[2/5] Checking pod readiness..."
	@READY=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o True | wc -l); \
	TOTAL=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[*].metadata.name}' | wc -w); \
	if [ "$$READY" -eq "$$TOTAL" ]; then \
		echo "  ✓ All $$TOTAL pods are ready"; \
	else \
		echo "  ⚠ Only $$READY/$$TOTAL pods are ready"; \
	fi
	@echo ""
	@echo "[3/5] Checking Memcached version..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c 'echo "version" | nc localhost 11211'
	@echo ""
	@echo "[4/5] Checking cache statistics..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	STATS=$$(kubectl exec -n $(NAMESPACE) $$POD -- sh -c 'echo "stats" | nc localhost 11211' 2>/dev/null); \
	ITEMS=$$(echo "$$STATS" | grep "STAT curr_items" | awk '{print $$3}'); \
	CONNS=$$(echo "$$STATS" | grep "STAT curr_connections" | awk '{print $$3}'); \
	echo "  Current items: $$ITEMS"; \
	echo "  Current connections: $$CONNS"
	@echo ""
	@echo "[5/5] Checking Helm release..."
	@helm list -n $(NAMESPACE) | grep $(RELEASE_NAME)
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="
	@echo ""
	@echo "⚠ IMPORTANT: Run backup before upgrading:"
	@echo "  make mc-backup-all"

.PHONY: mc-post-upgrade
mc-post-upgrade: ## Post-upgrade validation
	@echo "=== Post-Upgrade Validation ==="
	@echo ""
	@echo "[1/6] Checking pod status..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -n $(NAMESPACE) --timeout=300s && \
	echo "  ✓ All pods are ready"
	@echo ""
	@echo "[2/6] Checking Memcached version..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- sh -c 'echo "version" | nc localhost 11211'
	@echo ""
	@echo "[3/6] Testing cache operations..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	RESULT=$$(kubectl exec -n $(NAMESPACE) $$POD -- sh -c 'echo -e "set test 0 60 5\r\nhello\r\nget test\r\nquit\r" | nc localhost 11211'); \
	if echo "$$RESULT" | grep -q "VALUE test"; then \
		echo "  ✓ Cache set/get operations working"; \
	else \
		echo "  ✗ Cache operations failed"; \
		exit 1; \
	fi
	@echo ""
	@echo "[4/6] Checking service endpoint..."
	@kubectl get svc -n $(NAMESPACE) $(RELEASE_NAME) || exit 1
	@echo "  ✓ Service is available"
	@echo ""
	@echo "[5/6] Checking cache statistics..."
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) -o jsonpath='{.items[0].metadata.name}'); \
	STATS=$$(kubectl exec -n $(NAMESPACE) $$POD -- sh -c 'echo "stats" | nc localhost 11211' 2>/dev/null); \
	UPTIME=$$(echo "$$STATS" | grep "STAT uptime" | awk '{print $$3}'); \
	CONNS=$$(echo "$$STATS" | grep "STAT curr_connections" | awk '{print $$3}'); \
	echo "  Uptime: $$UPTIME seconds"; \
	echo "  Current connections: $$CONNS"
	@echo ""
	@echo "[6/6] Verifying resource usage..."
	@kubectl top pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/instance=$(RELEASE_NAME) 2>/dev/null || echo "  ⚠ Metrics server not available"
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="

.PHONY: mc-rollback
mc-rollback: ## Rollback to previous Helm release
	@echo "Rolling back to previous Helm release..."
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Are you sure you want to rollback? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "Waiting for rollback to complete..." && \
		kubectl rollout status deployment/$(RELEASE_NAME) -n $(NAMESPACE) && \
		echo "" && \
		echo "=== Rollback Complete ===" && \
		echo "" && \
		echo "Verify with:" && \
		echo "  make mc-post-upgrade"; \
	else \
		echo "Rollback cancelled."; \
	fi
