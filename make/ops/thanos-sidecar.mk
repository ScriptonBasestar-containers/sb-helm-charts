# Thanos Sidecar Operations Makefile
# Usage: make -f make/ops/thanos-sidecar.mk <target>

include make/common.mk

CHART_NAME := thanos-sidecar
CHART_DIR := charts/$(CHART_NAME)
POD_NAME ?= $(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
CONTAINER_NAME ?= thanos-sidecar
NAMESPACE ?= default
HTTP_PORT := 10902
GRPC_PORT := 10901
REPLICAS ?= 2

.PHONY: help
help:
	@echo "Thanos Sidecar Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tsd-logs                    - View Thanos Sidecar logs"
	@echo "  tsd-shell                   - Open shell in Thanos Sidecar pod"
	@echo "  tsd-port-forward            - Port forward HTTP API (10902)"
	@echo "  tsd-port-forward-grpc       - Port forward gRPC (10901)"
	@echo "  tsd-restart                 - Restart Thanos Sidecar deployment"
	@echo ""
	@echo "Health & Status:"
	@echo "  tsd-ready                   - Check /-/ready endpoint"
	@echo "  tsd-healthy                 - Check /-/healthy endpoint"
	@echo "  tsd-metrics                 - Get Thanos Sidecar metrics"
	@echo ""
	@echo "Thanos-Specific:"
	@echo "  tsd-prometheus-check        - Check Prometheus connection"
	@echo "  tsd-upload-status           - Check upload status to object storage"
	@echo ""
	@echo "Scaling:"
	@echo "  tsd-scale                   - Scale deployment (REPLICAS=2)"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  tsd-pre-upgrade-check       - Pre-upgrade validation"
	@echo "  tsd-post-upgrade-check      - Post-upgrade validation"

# === Basic Operations ===
.PHONY: tsd-logs tsd-shell tsd-port-forward tsd-port-forward-grpc tsd-restart

tsd-logs:
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tsd-shell:
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tsd-port-forward:
	@echo "Port forwarding Thanos Sidecar HTTP to localhost:$(HTTP_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(HTTP_PORT):$(HTTP_PORT)

tsd-port-forward-grpc:
	@echo "Port forwarding Thanos Sidecar gRPC to localhost:$(GRPC_PORT)..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) $(GRPC_PORT):$(GRPC_PORT)

tsd-restart:
	kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# === Health & Status ===
.PHONY: tsd-ready tsd-healthy tsd-metrics

tsd-ready:
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready && echo " Ready"

tsd-healthy:
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy && echo " Healthy"

tsd-metrics:
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics

# === Thanos-Specific Operations ===
.PHONY: tsd-prometheus-check tsd-upload-status

tsd-prometheus-check:
	@echo "Checking Prometheus connection..."
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "Prometheus connection: OK" || echo "Prometheus connection: FAILED"
	@echo "Sidecar metrics:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "thanos_sidecar_prometheus" | head -5 || echo "No Prometheus sync metrics"

tsd-upload-status:
	@echo "Checking upload status to object storage..."
	@echo "Shipper metrics:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/metrics 2>/dev/null | \
		grep -E "thanos_shipper_uploads|thanos_shipper_upload_failures|thanos_shipper_last" || \
		echo "No shipper metrics (upload may be disabled)"

# === Scaling ===
.PHONY: tsd-scale

tsd-scale:
	kubectl scale deployment/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# === Upgrade Support ===
.PHONY: tsd-pre-upgrade-check tsd-post-upgrade-check

tsd-pre-upgrade-check:
	@echo "=== Thanos Sidecar Pre-Upgrade Check ==="
	@echo "[1/4] Pod status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide
	@echo ""
	@echo "[2/4] Ready endpoint:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  OK" || echo "  FAILED"
	@echo ""
	@echo "[3/4] Healthy endpoint:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  OK" || echo "  FAILED"
	@echo ""
	@echo "[4/4] Recent errors:"
	@kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 2>/dev/null | \
		grep -ci "error" || echo "0"
	@echo ""
	@echo "=== Pre-Upgrade Check Complete ==="

tsd-post-upgrade-check:
	@echo "=== Thanos Sidecar Post-Upgrade Validation ==="
	@echo "[1/4] Pod status:"
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide
	@echo ""
	@echo "[2/4] Ready endpoint:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/ready >/dev/null 2>&1 && \
		echo "  OK" || (echo "  FAILED"; exit 1)
	@echo ""
	@echo "[3/4] Healthy endpoint:"
	@kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- \
		wget -qO- http://localhost:$(HTTP_PORT)/-/healthy >/dev/null 2>&1 && \
		echo "  OK" || (echo "  FAILED"; exit 1)
	@echo ""
	@echo "[4/4] Errors in last 5 minutes:"
	@ERROR_COUNT=$$(kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --since=5m 2>/dev/null | \
		grep -ci "error" || echo "0"); \
	if [ "$$ERROR_COUNT" -eq 0 ]; then echo "  None"; else echo "  $$ERROR_COUNT found"; fi
	@echo ""
	@echo "=== Post-Upgrade Validation Complete ==="
