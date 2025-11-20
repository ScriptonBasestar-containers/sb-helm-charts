# mlflow chart configuration
CHART_NAME := mlflow
CHART_DIR := charts/$(CHART_NAME)

# Common Makefile
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# MLflow-specific targets

.PHONY: mlflow-shell
mlflow-shell:
	@echo "Opening MLflow shell..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- bash

.PHONY: mlflow-logs
mlflow-logs:
	@echo "Viewing MLflow logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: mlflow-port-forward
mlflow-port-forward:
	@echo "Port-forwarding MLflow to localhost:5000..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME) 5000:5000

.PHONY: mlflow-restart
mlflow-restart:
	@echo "Restarting MLflow deployment..."
	@$(KUBECTL) rollout restart deployment/$(CHART_NAME)
	@$(KUBECTL) rollout status deployment/$(CHART_NAME)

.PHONY: mlflow-scale
mlflow-scale:
	@if [ -z "$(REPLICAS)" ]; then echo "Usage: make -f make/ops/mlflow.mk mlflow-scale REPLICAS=2"; exit 1; fi
	@echo "Scaling MLflow to $(REPLICAS) replicas..."
	@$(KUBECTL) scale deployment/$(CHART_NAME) --replicas=$(REPLICAS)

.PHONY: help
help:
	@echo "MLflow Chart Operations:"
	@echo ""
	@echo "  mlflow-shell         - Open shell in MLflow pod"
	@echo "  mlflow-logs          - View logs"
	@echo "  mlflow-port-forward  - Port forward to localhost:5000"
	@echo "  mlflow-restart       - Restart deployment"
	@echo "  mlflow-scale REPLICAS=<n> - Scale replicas"
