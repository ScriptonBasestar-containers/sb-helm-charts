# phpMyAdmin Operations Makefile

CHART_NAME := phpmyadmin
NAMESPACE := default
RELEASE_NAME := phpmyadmin
POD_NAME := $(shell kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

.PHONY: help
help:
	@echo "phpMyAdmin Operations"
	@echo ""
	@echo "Access:"
	@echo "  phpmyadmin-port-forward    Port forward to localhost:8080"
	@echo ""
	@echo "Operations:"
	@echo "  phpmyadmin-logs            View logs"
	@echo "  phpmyadmin-shell           Open shell"
	@echo "  phpmyadmin-restart         Restart deployment"
	@echo ""

.PHONY: phpmyadmin-port-forward
phpmyadmin-port-forward:
	@echo "Forwarding phpMyAdmin to http://localhost:8080"
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 8080:80

.PHONY: phpmyadmin-logs
phpmyadmin-logs:
	kubectl logs -n $(NAMESPACE) $(POD_NAME) --tail=100 -f

.PHONY: phpmyadmin-shell
phpmyadmin-shell:
	kubectl exec -n $(NAMESPACE) -it $(POD_NAME) -- /bin/sh

.PHONY: phpmyadmin-restart
phpmyadmin-restart:
	kubectl rollout restart -n $(NAMESPACE) deployment/$(CHART_NAME)
	kubectl rollout status -n $(NAMESPACE) deployment/$(CHART_NAME)
