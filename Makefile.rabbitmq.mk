# Makefile for RabbitMQ Helm Chart
# Provides chart management and operational commands

CHART_NAME := rabbitmq
CHART_DIR := charts/$(CHART_NAME)

# Include common targets (lint, build, install, upgrade, uninstall, etc.)
include Makefile.common.mk

# ==============================================================================
# RabbitMQ Operational Commands
# ==============================================================================

.PHONY: rmq-status
rmq-status: ## Show RabbitMQ cluster status
	@echo "==> Checking RabbitMQ cluster status..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl cluster_status

.PHONY: rmq-node-health
rmq-node-health: ## Check RabbitMQ node health
	@echo "==> Checking RabbitMQ node health..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmq-diagnostics status

.PHONY: rmq-ping
rmq-ping: ## Ping RabbitMQ node
	@echo "==> Pinging RabbitMQ node..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmq-diagnostics ping

.PHONY: rmq-list-queues
rmq-list-queues: ## List all queues
	@echo "==> Listing RabbitMQ queues..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_queues

.PHONY: rmq-list-exchanges
rmq-list-exchanges: ## List all exchanges
	@echo "==> Listing RabbitMQ exchanges..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_exchanges

.PHONY: rmq-list-bindings
rmq-list-bindings: ## List all bindings
	@echo "==> Listing RabbitMQ bindings..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_bindings

.PHONY: rmq-list-connections
rmq-list-connections: ## List all connections
	@echo "==> Listing RabbitMQ connections..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_connections

.PHONY: rmq-list-channels
rmq-list-channels: ## List all channels
	@echo "==> Listing RabbitMQ channels..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_channels

.PHONY: rmq-list-consumers
rmq-list-consumers: ## List all consumers
	@echo "==> Listing RabbitMQ consumers..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_consumers

.PHONY: rmq-list-users
rmq-list-users: ## List all users
	@echo "==> Listing RabbitMQ users..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_users

.PHONY: rmq-list-vhosts
rmq-list-vhosts: ## List all virtual hosts
	@echo "==> Listing RabbitMQ virtual hosts..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_vhosts

.PHONY: rmq-list-permissions
rmq-list-permissions: ## List all permissions (requires VHOST variable)
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required. Usage: make rmq-list-permissions VHOST=/"; \
		exit 1; \
	fi
	@echo "==> Listing permissions for vhost: $(VHOST)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl list_permissions -p $(VHOST)

.PHONY: rmq-add-user
rmq-add-user: ## Add user (requires USER and PASSWORD variables)
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "Error: USER and PASSWORD variables are required."; \
		echo "Usage: make rmq-add-user USER=myuser PASSWORD=mypassword"; \
		exit 1; \
	fi
	@echo "==> Adding user: $(USER)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl add_user $(USER) $(PASSWORD)

.PHONY: rmq-delete-user
rmq-delete-user: ## Delete user (requires USER variable)
	@if [ -z "$(USER)" ]; then \
		echo "Error: USER variable is required. Usage: make rmq-delete-user USER=myuser"; \
		exit 1; \
	fi
	@echo "==> Deleting user: $(USER)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl delete_user $(USER)

.PHONY: rmq-set-user-tags
rmq-set-user-tags: ## Set user tags (requires USER and TAGS variables)
	@if [ -z "$(USER)" ] || [ -z "$(TAGS)" ]; then \
		echo "Error: USER and TAGS variables are required."; \
		echo "Usage: make rmq-set-user-tags USER=myuser TAGS=administrator"; \
		exit 1; \
	fi
	@echo "==> Setting tags for user $(USER): $(TAGS)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl set_user_tags $(USER) $(TAGS)

.PHONY: rmq-set-permissions
rmq-set-permissions: ## Set user permissions (requires VHOST, USER, CONF, WRITE, READ variables)
	@if [ -z "$(VHOST)" ] || [ -z "$(USER)" ]; then \
		echo "Error: VHOST and USER variables are required."; \
		echo "Usage: make rmq-set-permissions VHOST=/ USER=myuser CONF='.*' WRITE='.*' READ='.*'"; \
		exit 1; \
	fi
	@CONF_PERM=$${CONF:-".*"}; \
	WRITE_PERM=$${WRITE:-".*"}; \
	READ_PERM=$${READ:-".*"}; \
	echo "==> Setting permissions for user $(USER) on vhost $(VHOST)..."; \
	kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- \
		rabbitmqctl set_permissions -p $(VHOST) $(USER) "$$CONF_PERM" "$$WRITE_PERM" "$$READ_PERM"

.PHONY: rmq-add-vhost
rmq-add-vhost: ## Add virtual host (requires VHOST variable)
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required. Usage: make rmq-add-vhost VHOST=/my-vhost"; \
		exit 1; \
	fi
	@echo "==> Adding virtual host: $(VHOST)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl add_vhost $(VHOST)

.PHONY: rmq-delete-vhost
rmq-delete-vhost: ## Delete virtual host (requires VHOST variable)
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required. Usage: make rmq-delete-vhost VHOST=/my-vhost"; \
		exit 1; \
	fi
	@echo "==> Deleting virtual host: $(VHOST)..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- rabbitmqctl delete_vhost $(VHOST)

.PHONY: rmq-shell
rmq-shell: ## Open shell in RabbitMQ pod
	@echo "==> Opening shell in RabbitMQ pod..."
	@kubectl exec -it $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- /bin/bash

.PHONY: rmq-logs
rmq-logs: ## Tail RabbitMQ logs
	@echo "==> Tailing RabbitMQ logs..."
	@kubectl logs -f $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}")

.PHONY: rmq-get-credentials
rmq-get-credentials: ## Get admin credentials from secret
	@echo "==> Retrieving admin credentials..."
	@echo -n "Username: "
	@kubectl get secret $$(kubectl get secret -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -o jsonpath="{.data.username}" | base64 --decode
	@echo ""
	@echo -n "Password: "
	@kubectl get secret $$(kubectl get secret -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -o jsonpath="{.data.password}" | base64 --decode
	@echo ""

.PHONY: rmq-port-forward-ui
rmq-port-forward-ui: ## Port-forward Management UI to localhost:15672
	@echo "==> Port-forwarding Management UI to http://localhost:15672"
	@echo "==> Use Ctrl+C to stop port-forwarding"
	@kubectl port-forward svc/$$(kubectl get svc -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") 15672:15672

.PHONY: rmq-port-forward-amqp
rmq-port-forward-amqp: ## Port-forward AMQP to localhost:5672
	@echo "==> Port-forwarding AMQP to localhost:5672"
	@echo "==> Use Ctrl+C to stop port-forwarding"
	@kubectl port-forward svc/$$(kubectl get svc -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") 5672:5672

.PHONY: rmq-port-forward-metrics
rmq-port-forward-metrics: ## Port-forward Prometheus metrics to localhost:15692
	@echo "==> Port-forwarding Prometheus metrics to http://localhost:15692/metrics"
	@echo "==> Use Ctrl+C to stop port-forwarding"
	@kubectl port-forward svc/$$(kubectl get svc -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") 15692:15692

.PHONY: rmq-metrics
rmq-metrics: ## Fetch Prometheus metrics
	@echo "==> Fetching Prometheus metrics..."
	@kubectl exec $$(kubectl get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:15692/metrics

.PHONY: rmq-restart
rmq-restart: ## Restart RabbitMQ deployment
	@echo "==> Restarting RabbitMQ deployment..."
	@kubectl rollout restart deployment/$$(kubectl get deployment -l app.kubernetes.io/name=rabbitmq -o jsonpath="{.items[0].metadata.name}")

.PHONY: rmq-describe
rmq-describe: ## Describe RabbitMQ resources
	@echo "==> Describing RabbitMQ deployment..."
	@kubectl describe deployment -l app.kubernetes.io/name=rabbitmq
	@echo ""
	@echo "==> Describing RabbitMQ pods..."
	@kubectl describe pod -l app.kubernetes.io/name=rabbitmq

# ==============================================================================
# Help
# ==============================================================================

# ==============================================================================
# Help Targets
# ==============================================================================

.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk CHART_NAME=$(CHART_NAME) help

.PHONY: help
help: help-common
	@echo ""
	@echo "RabbitMQ Operational Commands:"
	@echo "  rmq-status               - Show cluster status"
	@echo "  rmq-node-health          - Check node health"
	@echo "  rmq-ping                 - Ping RabbitMQ node"
	@echo "  rmq-list-queues          - List all queues"
	@echo "  rmq-list-exchanges       - List all exchanges"
	@echo "  rmq-list-bindings        - List all bindings"
	@echo "  rmq-list-connections     - List all connections"
	@echo "  rmq-list-channels        - List all channels"
	@echo "  rmq-list-consumers       - List all consumers"
	@echo "  rmq-list-users           - List all users"
	@echo "  rmq-list-vhosts          - List all virtual hosts"
	@echo "  rmq-list-permissions     - List permissions (requires VHOST=/)"
	@echo ""
	@echo "User Management:"
	@echo "  rmq-add-user             - Add user (requires USER=user PASSWORD=pass)"
	@echo "  rmq-delete-user          - Delete user (requires USER=user)"
	@echo "  rmq-set-user-tags        - Set user tags (requires USER=user TAGS=administrator)"
	@echo "  rmq-set-permissions      - Set permissions (requires VHOST=/ USER=user)"
	@echo ""
	@echo "Virtual Host Management:"
	@echo "  rmq-add-vhost            - Add vhost (requires VHOST=/my-vhost)"
	@echo "  rmq-delete-vhost         - Delete vhost (requires VHOST=/my-vhost)"
	@echo ""
	@echo "Access & Monitoring:"
	@echo "  rmq-get-credentials      - Get admin credentials"
	@echo "  rmq-port-forward-ui      - Port-forward Management UI (localhost:15672)"
	@echo "  rmq-port-forward-amqp    - Port-forward AMQP (localhost:5672)"
	@echo "  rmq-port-forward-metrics - Port-forward Prometheus metrics (localhost:15692)"
	@echo "  rmq-metrics              - Fetch Prometheus metrics"
	@echo ""
	@echo "Maintenance:"
	@echo "  rmq-shell                - Open shell in RabbitMQ pod"
	@echo "  rmq-logs                 - Tail RabbitMQ logs"
	@echo "  rmq-restart              - Restart RabbitMQ deployment"
	@echo "  rmq-describe             - Describe RabbitMQ resources"
	@echo ""

.DEFAULT_GOAL := help
