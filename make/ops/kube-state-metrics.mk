# Kube State Metrics Operations Makefile
# Usage: make -f make/ops/kube-state-metrics.mk <target>

include make/Makefile.common.mk

CHART_NAME := kube-state-metrics
CHART_DIR := charts/$(CHART_NAME)

# Kube State Metrics specific variables
NAMESPACE ?= default
POD_NAME := $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

.PHONY: help
help:
	@echo "Kube State Metrics Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  ksm-logs                     - View logs from kube-state-metrics pod"
	@echo "  ksm-shell                    - Open shell in kube-state-metrics pod"
	@echo "  ksm-restart                  - Restart kube-state-metrics Deployment"
	@echo ""
	@echo "Health & Status:"
	@echo "  ksm-status                   - Show Deployment and pods status"
	@echo "  ksm-version                  - Get kube-state-metrics version"
	@echo "  ksm-health                   - Check health endpoint"
	@echo ""
	@echo "Metrics Queries:"
	@echo "  ksm-metrics                  - Fetch all metrics"
	@echo "  ksm-pod-metrics              - Fetch pod metrics"
	@echo "  ksm-deployment-metrics       - Fetch deployment metrics"
	@echo "  ksm-node-metrics             - Fetch node metrics"
	@echo "  ksm-service-metrics          - Fetch service metrics"
	@echo "  ksm-pv-metrics               - Fetch persistent volume metrics"
	@echo "  ksm-pvc-metrics              - Fetch PVC metrics"
	@echo "  ksm-namespace-metrics        - Fetch namespace metrics"
	@echo ""
	@echo "Resource Status:"
	@echo "  ksm-pod-status               - Check pod status metrics"
	@echo "  ksm-deployment-status        - Check deployment status metrics"
	@echo "  ksm-node-status              - Check node status metrics"
	@echo ""
	@echo "Port Forward:"
	@echo "  ksm-port-forward             - Port forward to localhost:8080"
	@echo "  ksm-port-forward-telemetry   - Port forward telemetry to localhost:8081"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                         - Lint the chart"
	@echo "  build                        - Package the chart"
	@echo "  install                      - Install the chart"
	@echo "  upgrade                      - Upgrade the chart"
	@echo "  uninstall                    - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: ksm-logs ksm-shell ksm-restart

ksm-logs:
	@echo "Fetching logs from kube-state-metrics pod..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --tail=100 -f

ksm-shell:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Opening shell in kube-state-metrics pod $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -- /bin/sh

ksm-restart:
	@echo "Restarting kube-state-metrics Deployment..."
	kubectl rollout restart deployment/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status deployment/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: ksm-status ksm-version ksm-health

ksm-status:
	@echo "Deployment status:"
	kubectl get deployment -n $(NAMESPACE) $(CHART_NAME)
	@echo ""
	@echo "Pods:"
	kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

ksm-version:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Getting kube-state-metrics version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- /kube-state-metrics --version 2>&1 | head -1

ksm-health:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Checking health endpoint..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/healthz

# Metrics Queries
.PHONY: ksm-metrics ksm-pod-metrics ksm-deployment-metrics ksm-node-metrics ksm-service-metrics ksm-pv-metrics ksm-pvc-metrics ksm-namespace-metrics

ksm-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching all metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics

ksm-pod-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching pod metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_pod_"

ksm-deployment-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching deployment metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_deployment_"

ksm-node-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching node metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_node_"

ksm-service-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching service metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_service_"

ksm-pv-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching persistent volume metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_persistentvolume_"

ksm-pvc-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching PVC metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_persistentvolumeclaim_"

ksm-namespace-metrics:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Fetching namespace metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "^kube_namespace_"

# Resource Status
.PHONY: ksm-pod-status ksm-deployment-status ksm-node-status

ksm-pod-status:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Pod status metrics:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "kube_pod_status_phase"

ksm-deployment-status:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Deployment status metrics:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "kube_deployment_status_replicas"

ksm-node-status:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Node status metrics:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:8080/metrics | grep "kube_node_status_condition"

# Port Forward
.PHONY: ksm-port-forward ksm-port-forward-telemetry

ksm-port-forward:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Port forwarding kube-state-metrics to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) $(POD_NAME) 8080:8080

ksm-port-forward-telemetry:
	@if [ -z "$(POD_NAME)" ]; then \
		echo "Error: No kube-state-metrics pod found"; \
		exit 1; \
	fi
	@echo "Port forwarding kube-state-metrics telemetry to localhost:8081..."
	kubectl port-forward -n $(NAMESPACE) $(POD_NAME) 8081:8081
