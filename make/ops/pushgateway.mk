# Pushgateway Operations Makefile
CHART_NAME := pushgateway
NAMESPACE := default
POD_NAME := $(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

.PHONY: help
help:
	@echo "Pushgateway Operations"
	@echo ""
	@echo "Access:"
	@echo "  pushgateway-port-forward     Port forward to localhost:9091"
	@echo ""
	@echo "Metrics Management:"
	@echo "  pushgateway-metrics          Get all metrics"
	@echo "  pushgateway-delete-group     Delete metrics group (requires JOB)"
	@echo ""
	@echo "Operations:"
	@echo "  pushgateway-health           Check health"
	@echo "  pushgateway-logs             View logs"
	@echo "  pushgateway-shell            Open shell"
	@echo "  pushgateway-restart          Restart deployment"
	@echo ""

.PHONY: pushgateway-port-forward
pushgateway-port-forward:
	@echo "Forwarding Pushgateway to http://localhost:9091"
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9091:9091

.PHONY: pushgateway-metrics
pushgateway-metrics:
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:9091/metrics

.PHONY: pushgateway-delete-group
pushgateway-delete-group:
ifndef JOB
	@echo "Error: JOB is required"
	@echo "Usage: make -f make/ops/pushgateway.mk pushgateway-delete-group JOB=batch_job"
	@exit 1
endif
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- --method=DELETE http://localhost:9091/metrics/job/$(JOB)

.PHONY: pushgateway-health
pushgateway-health:
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -- wget -qO- http://localhost:9091/-/healthy

.PHONY: pushgateway-logs
pushgateway-logs:
	kubectl logs -n $(NAMESPACE) $(POD_NAME) --tail=100 -f

.PHONY: pushgateway-shell
pushgateway-shell:
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- /bin/sh

.PHONY: pushgateway-restart
pushgateway-restart:
	kubectl rollout restart -n $(NAMESPACE) deployment/$(CHART_NAME)
	kubectl rollout status -n $(NAMESPACE) deployment/$(CHART_NAME)
