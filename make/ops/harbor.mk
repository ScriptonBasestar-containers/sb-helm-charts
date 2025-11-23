# Harbor Makefile
# Operational commands for Harbor container registry

CHART_NAME := harbor
NAMESPACE := harbor
RELEASE_NAME := harbor

.PHONY: harbor-help
harbor-help:
	@echo "Harbor Operational Commands:"
	@echo ""
	@echo "Access & Credentials:"
	@echo "  harbor-get-admin-password  - Get admin password"
	@echo "  harbor-port-forward        - Port forward to Harbor UI (8080:80)"
	@echo ""
	@echo "Component Status:"
	@echo "  harbor-status              - Show all Harbor component status"
	@echo "  harbor-core-logs           - View core component logs"
	@echo "  harbor-core-logs-all       - View all core pod logs"
	@echo "  harbor-registry-logs       - View registry component logs"
	@echo "  harbor-registry-logs-all   - View all registry pod logs"
	@echo "  harbor-core-shell          - Open shell in core pod"
	@echo "  harbor-registry-shell      - Open shell in registry pod"
	@echo ""
	@echo "Health & Monitoring:"
	@echo "  harbor-health              - Check Harbor health"
	@echo "  harbor-core-health         - Check core component health"
	@echo "  harbor-registry-health     - Check registry component health"
	@echo "  harbor-version             - Show Harbor version"
	@echo "  harbor-metrics             - Fetch Prometheus metrics"
	@echo ""
	@echo "Registry Operations:"
	@echo "  harbor-test-push           - Test image push (requires docker login)"
	@echo "  harbor-test-pull           - Test image pull"
	@echo "  harbor-catalog             - List all repositories"
	@echo "  harbor-projects            - List all projects"
	@echo "  harbor-gc                  - Trigger garbage collection"
	@echo "  harbor-gc-status           - Check garbage collection status"
	@echo ""
	@echo "Database Operations:"
	@echo "  harbor-db-test             - Test PostgreSQL connection"
	@echo "  harbor-db-migrate          - Run database migrations"
	@echo "  harbor-redis-test          - Test Redis connection"
	@echo ""
	@echo "Operations:"
	@echo "  harbor-restart             - Restart Harbor deployments"
	@echo "  harbor-scale               - Scale replicas (REPLICAS=2)"
	@echo ""

# =============================================================================
# Access & Credentials
# =============================================================================

.PHONY: harbor-get-admin-password
harbor-get-admin-password:
	@echo "Harbor Admin Password:"
	@kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || \
		kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME)-harbor -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || \
		echo "Secret not found. Check if Harbor is deployed."
	@echo ""

.PHONY: harbor-port-forward
harbor-port-forward:
	@echo "Port forwarding Harbor UI to localhost:8080..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 8080:80

# =============================================================================
# Component Status
# =============================================================================

.PHONY: harbor-status
harbor-status:
	@echo "=== Harbor Component Status ==="
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@kubectl get svc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@kubectl get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: harbor-core-logs
harbor-core-logs:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core --tail=100 -f

.PHONY: harbor-core-logs-all
harbor-core-logs-all:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core --all-containers=true

.PHONY: harbor-registry-logs
harbor-registry-logs:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=registry --tail=100 -f

.PHONY: harbor-registry-logs-all
harbor-registry-logs-all:
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=registry --all-containers=true

.PHONY: harbor-core-shell
harbor-core-shell:
	kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

.PHONY: harbor-registry-shell
harbor-registry-shell:
	kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=registry -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

# =============================================================================
# Health & Monitoring
# =============================================================================

.PHONY: harbor-health
harbor-health:
	@echo "=== Harbor Health Check ==="
	@echo "Core component:"
	@make -s harbor-core-health
	@echo ""
	@echo "Registry component:"
	@make -s harbor-registry-health

.PHONY: harbor-core-health
harbor-core-health:
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- http://localhost:8080/api/v2.0/health 2>/dev/null || echo "Core health check failed"

.PHONY: harbor-registry-health
harbor-registry-health:
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=registry -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- http://localhost:5000/v2/ 2>/dev/null || echo "Registry health check failed"

.PHONY: harbor-version
harbor-version:
	@echo "Harbor Version:"
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		harbor_core version 2>/dev/null || echo "Version command not available"

.PHONY: harbor-metrics
harbor-metrics:
	@echo "=== Harbor Metrics ==="
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- http://localhost:8080/metrics 2>/dev/null

# =============================================================================
# Registry Operations
# =============================================================================

.PHONY: harbor-test-push
harbor-test-push:
	@echo "Testing image push to Harbor..."
	@echo "Make sure you've logged in with: docker login <harbor-url>"
	@echo "This will pull busybox, tag it, and push to Harbor"
	@read -p "Enter Harbor URL (e.g., harbor.example.com): " HARBOR_URL; \
	read -p "Enter project name (e.g., library): " PROJECT; \
	docker pull busybox:latest && \
	docker tag busybox:latest $$HARBOR_URL/$$PROJECT/busybox:test && \
	docker push $$HARBOR_URL/$$PROJECT/busybox:test && \
	echo "✓ Push successful"

.PHONY: harbor-test-pull
harbor-test-pull:
	@echo "Testing image pull from Harbor..."
	@read -p "Enter Harbor URL: " HARBOR_URL; \
	read -p "Enter project name: " PROJECT; \
	docker pull $$HARBOR_URL/$$PROJECT/busybox:test && \
	echo "✓ Pull successful"

.PHONY: harbor-catalog
harbor-catalog:
	@echo "=== Harbor Repositories ==="
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- --header "Authorization: Basic $$(echo -n admin:$$(kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.data.admin-password}' | base64 --decode) | base64)" \
		http://localhost:8080/api/v2.0/repositories 2>/dev/null | jq '.' || echo "Failed to fetch catalog"

.PHONY: harbor-projects
harbor-projects:
	@echo "=== Harbor Projects ==="
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- --header "Authorization: Basic $$(echo -n admin:$$(kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.data.admin-password}' | base64 --decode) | base64)" \
		http://localhost:8080/api/v2.0/projects 2>/dev/null | jq '.' || echo "Failed to fetch projects"

.PHONY: harbor-gc
harbor-gc:
	@echo "Triggering garbage collection..."
	@echo "Note: This requires admin authentication"
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- --post-data='{"schedule":{"type":"Manual"}}' \
		--header "Content-Type: application/json" \
		--header "Authorization: Basic $$(echo -n admin:$$(kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.data.admin-password}' | base64 --decode) | base64)" \
		http://localhost:8080/api/v2.0/system/gc/schedule 2>/dev/null || echo "GC trigger failed"

.PHONY: harbor-gc-status
harbor-gc-status:
	@echo "=== Garbage Collection Status ==="
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		wget -qO- --header "Authorization: Basic $$(echo -n admin:$$(kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME) -o jsonpath='{.data.admin-password}' | base64 --decode) | base64)" \
		http://localhost:8080/api/v2.0/system/gc 2>/dev/null | jq '.' || echo "Failed to fetch GC status"

# =============================================================================
# Database Operations
# =============================================================================

.PHONY: harbor-db-test
harbor-db-test:
	@echo "Testing PostgreSQL connection..."
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		sh -c 'apk add --no-cache postgresql-client >/dev/null 2>&1; pg_isready -h $$POSTGRESQL_HOST -p $$POSTGRESQL_PORT -U $$POSTGRESQL_USERNAME' || echo "PostgreSQL connection failed"

.PHONY: harbor-db-migrate
harbor-db-migrate:
	@echo "Running database migrations..."
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		harbor_core migrate || echo "Migration failed"

.PHONY: harbor-redis-test
harbor-redis-test:
	@echo "Testing Redis connection..."
	@kubectl exec -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core -o jsonpath='{.items[0].metadata.name}') -- \
		sh -c 'apk add --no-cache redis >/dev/null 2>&1; redis-cli -h $$REDIS_HOST -p $$REDIS_PORT ping' || echo "Redis connection failed"

# =============================================================================
# Operations
# =============================================================================

.PHONY: harbor-restart
harbor-restart:
	@echo "Restarting Harbor deployments..."
	kubectl rollout restart deployment -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo "Waiting for rollout to complete..."
	kubectl rollout status deployment -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: harbor-scale
harbor-scale:
	@if [ -z "$(REPLICAS)" ]; then \
		echo "Error: REPLICAS not set. Usage: make harbor-scale REPLICAS=2"; \
		exit 1; \
	fi
	@echo "Scaling Harbor to $(REPLICAS) replicas..."
	kubectl scale deployment -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=core --replicas=$(REPLICAS)
	kubectl scale deployment -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component=registry --replicas=$(REPLICAS)
	@echo "Waiting for scale to complete..."
	kubectl rollout status deployment -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
