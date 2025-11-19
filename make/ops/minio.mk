CHART_NAME := minio
CHART_DIR := charts/$(CHART_NAME)

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Helper function to get pod name
# Usage: POD=$(POD) or defaults to first pod
define get-pod-name
$(shell \
	if [ -n "$(POD)" ]; then \
		echo "$(POD)"; \
	else \
		POD_NAME=$$(kubectl get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}" 2>/dev/null); \
		if [ -z "$$POD_NAME" ]; then \
			echo "ERROR: No MinIO pods found. Is MinIO deployed?" >&2; \
			exit 1; \
		fi; \
		echo "$$POD_NAME"; \
	fi \
)
endef

# MinIO-specific targets

.PHONY: minio-get-credentials
minio-get-credentials:
	@echo "=== MinIO Credentials ==="
	@echo "Root User:"
	@kubectl get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-user}' | base64 -d
	@echo ""
	@echo "Root Password:"
	@kubectl get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-password}' | base64 -d
	@echo ""

.PHONY: minio-port-forward-api
minio-port-forward-api:
	@echo "Port-forwarding MinIO API to localhost:9000..."
	@kubectl port-forward svc/$(CHART_NAME) 9000:9000

.PHONY: minio-port-forward-console
minio-port-forward-console:
	@echo "Port-forwarding MinIO Console to localhost:9001..."
	@kubectl port-forward svc/$(CHART_NAME) 9001:9001

.PHONY: minio-mc-alias
minio-mc-alias:
	@echo "Setting up MinIO Client alias..."
	@echo "Run these commands:"
	@echo ""
	@echo "export MINIO_ROOT_USER=\$$(kubectl get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-user}' | base64 -d)"
	@echo "export MINIO_ROOT_PASSWORD=\$$(kubectl get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-password}' | base64 -d)"
	@echo "mc alias set $(CHART_NAME) http://localhost:9000 \$$MINIO_ROOT_USER \$$MINIO_ROOT_PASSWORD"
	@echo ""
	@echo "Then test with: mc admin info $(CHART_NAME)"

.PHONY: minio-create-bucket
minio-create-bucket:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-create-bucket BUCKET=mybucket [POD=minio-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Creating bucket: $(BUCKET) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- mc mb local/$(BUCKET)

.PHONY: minio-list-buckets
minio-list-buckets:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Listing MinIO buckets (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- mc ls local/

.PHONY: minio-health
minio-health:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== MinIO Health Check (pod: $$POD_NAME) ==="; \
	echo "Live:"; \
	kubectl exec -it $$POD_NAME -- wget -qO- http://localhost:9000/minio/health/live || echo "Failed"; \
	echo ""; \
	echo "Ready:"; \
	kubectl exec -it $$POD_NAME -- wget -qO- http://localhost:9000/minio/health/ready || echo "Not Ready"

.PHONY: minio-metrics
minio-metrics:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Fetching MinIO Prometheus metrics (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- wget -qO- http://localhost:9000/minio/v2/metrics/cluster

.PHONY: minio-server-info
minio-server-info:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== MinIO Server Info (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- mc admin info local

.PHONY: minio-cluster-status
minio-cluster-status:
	@echo "=== MinIO Cluster Status ==="
	@kubectl get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "=== Headless Service (Distributed Mode) ==="
	@kubectl get svc $(CHART_NAME)-headless 2>/dev/null || echo "Not in distributed mode"
	@echo ""
	@echo "=== PVCs ==="
	@kubectl get pvc -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: minio-logs
minio-logs:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Tailing MinIO logs (pod: $$POD_NAME)..."; \
	kubectl logs -f $$POD_NAME

.PHONY: minio-logs-all
minio-logs-all:
	@echo "Tailing all MinIO pod logs..."
	@kubectl logs -f -l app.kubernetes.io/name=$(CHART_NAME) --all-containers=true --prefix=true

.PHONY: minio-shell
minio-shell:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Opening shell in MinIO pod (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- /bin/sh

.PHONY: minio-scale
minio-scale:
	@if [ -z "$(REPLICAS)" ]; then \
		echo "Error: REPLICAS parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-scale REPLICAS=4"; \
		exit 1; \
	fi
	@if [ $$(( $(REPLICAS) % 2 )) -ne 0 ] && [ $(REPLICAS) -gt 1 ]; then \
		echo "Error: REPLICAS must be an even number for distributed mode"; \
		exit 1; \
	fi
	@if [ $(REPLICAS) -gt 1 ] && [ $(REPLICAS) -lt 4 ]; then \
		echo "Error: Distributed mode requires at least 4 replicas"; \
		exit 1; \
	fi
	@echo "Scaling MinIO to $(REPLICAS) replicas..."
	@kubectl scale statefulset $(CHART_NAME) --replicas=$(REPLICAS)

.PHONY: minio-restart
minio-restart:
	@echo "Restarting MinIO deployment..."
	@kubectl rollout restart statefulset/$(CHART_NAME)
	@kubectl rollout status statefulset/$(CHART_NAME)

.PHONY: minio-backup-list
minio-backup-list:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-backup-list BUCKET=mybucket [POD=minio-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Listing backups in bucket: $(BUCKET) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- mc ls local/$(BUCKET)

.PHONY: minio-disk-usage
minio-disk-usage:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== MinIO Disk Usage (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- mc admin prometheus generate local | grep minio_disk

.PHONY: minio-service-endpoint
minio-service-endpoint:
	@echo "=== MinIO Service Endpoints ==="
	@echo "API Service:"
	@kubectl get svc $(CHART_NAME) -o jsonpath='{.spec.type}{"\t"}{.spec.clusterIP}{":"}{.spec.ports[?(@.name=="api")].port}{"\n"}'
	@if [ "$$(kubectl get svc $(CHART_NAME) -o jsonpath='{.spec.type}')" = "LoadBalancer" ]; then \
		echo "External IP:"; \
		kubectl get svc $(CHART_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}{":"}{.spec.ports[?(@.name=="api")].port}{"\n"}'; \
	fi
	@echo ""
	@echo "Console Service:"
	@kubectl get svc $(CHART_NAME) -o jsonpath='{.spec.type}{"\t"}{.spec.clusterIP}{":"}{.spec.ports[?(@.name=="console")].port}{"\n"}'
	@if [ "$$(kubectl get svc $(CHART_NAME) -o jsonpath='{.spec.type}')" = "LoadBalancer" ]; then \
		echo "External IP:"; \
		kubectl get svc $(CHART_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}{":"}{.spec.ports[?(@.name=="console")].port}{"\n"}'; \
	fi

.PHONY: minio-version
minio-version:
	@POD_NAME="$(call get-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "MinIO version (pod: $$POD_NAME):"; \
	kubectl exec -it $$POD_NAME -- minio --version

# Help from common makefile
.PHONY: help-common
help-common:
	@$(MAKE) -f make/common.mk help CHART_NAME=$(CHART_NAME) CHART_DIR=$(CHART_DIR)

.PHONY: help
help: help-common
	@echo ""
	@echo "MinIO specific targets:"
	@echo "  minio-get-credentials        - Display MinIO root credentials"
	@echo "  minio-port-forward-api       - Port-forward API to localhost:9000"
	@echo "  minio-port-forward-console   - Port-forward Console to localhost:9001"
	@echo "  minio-mc-alias               - Show commands to setup mc client alias"
	@echo "  minio-create-bucket          - Create bucket (BUCKET=name [POD=minio-0])"
	@echo "  minio-list-buckets           - List all buckets ([POD=minio-0])"
	@echo "  minio-health                 - Check health endpoints ([POD=minio-0])"
	@echo "  minio-metrics                - Fetch Prometheus metrics ([POD=minio-0])"
	@echo "  minio-server-info            - Display server information ([POD=minio-0])"
	@echo "  minio-cluster-status         - Show cluster status (pods, PVCs)"
	@echo "  minio-logs                   - Tail logs from specific pod ([POD=minio-0])"
	@echo "  minio-logs-all               - Tail logs from all pods"
	@echo "  minio-shell                  - Open shell in MinIO pod ([POD=minio-0])"
	@echo "  minio-scale                  - Scale replicas (REPLICAS=N)"
	@echo "  minio-restart                - Restart MinIO statefulset"
	@echo "  minio-backup-list            - List backups (BUCKET=name [POD=minio-0])"
	@echo "  minio-disk-usage             - Show disk usage metrics ([POD=minio-0])"
	@echo "  minio-service-endpoint       - Display service endpoints"
	@echo "  minio-version                - Show MinIO version ([POD=minio-0])"
	@echo ""
	@echo "Note: Commands default to first pod. Use POD=minio-N to target specific pod."
