# Makefile for RabbitMQ Helm Chart
# Provides chart management and operational commands

CHART_NAME := rabbitmq
CHART_DIR := charts/$(CHART_NAME)

# Default namespace and release name
NAMESPACE ?= default
RELEASE_NAME ?= my-rabbitmq

# Backup configuration
BACKUP_DIR ?= ./backups/rabbitmq
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# Pod selector
POD_SELECTOR := app.kubernetes.io/name=rabbitmq

# Include common targets (lint, build, install, upgrade, uninstall, etc.)
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# ==============================================================================
# Access & Debugging
# ==============================================================================

## rmq-shell: Open interactive shell in RabbitMQ pod
.PHONY: rmq-shell
rmq-shell:
	@echo "=== Opening Shell in RabbitMQ Pod ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/bash

## rmq-logs: Tail RabbitMQ logs
.PHONY: rmq-logs
rmq-logs:
	@echo "=== Tailing RabbitMQ Logs ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl logs -f -n $(NAMESPACE) $$POD

## rmq-get-credentials: Retrieve admin credentials from secret
.PHONY: rmq-get-credentials
rmq-get-credentials:
	@echo "=== Admin Credentials ==="
	@SECRET=$$(kubectl get secret -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo -n "Username: "; \
	kubectl get secret -n $(NAMESPACE) $$SECRET -o jsonpath='{.data.username}' | base64 --decode; \
	echo ""; \
	echo -n "Password: "; \
	kubectl get secret -n $(NAMESPACE) $$SECRET -o jsonpath='{.data.password}' | base64 --decode; \
	echo ""

## rmq-port-forward: Port-forward Management UI to localhost:15672
.PHONY: rmq-port-forward
rmq-port-forward:
	@echo "=== Port-Forwarding Management UI ==="
	@echo "Access UI at: http://localhost:15672"
	@echo "Press Ctrl+C to stop port-forwarding"
	@SVC=$$(kubectl get svc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(NAMESPACE) svc/$$SVC 15672:15672

## rmq-port-forward-amqp: Port-forward AMQP to localhost:5672
.PHONY: rmq-port-forward-amqp
rmq-port-forward-amqp:
	@echo "=== Port-Forwarding AMQP ==="
	@echo "AMQP connection: amqp://localhost:5672"
	@echo "Press Ctrl+C to stop port-forwarding"
	@SVC=$$(kubectl get svc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(NAMESPACE) svc/$$SVC 5672:5672

## rmq-port-forward-metrics: Port-forward Prometheus metrics to localhost:15692
.PHONY: rmq-port-forward-metrics
rmq-port-forward-metrics:
	@echo "=== Port-Forwarding Prometheus Metrics ==="
	@echo "Metrics endpoint: http://localhost:15692/metrics"
	@echo "Press Ctrl+C to stop port-forwarding"
	@SVC=$$(kubectl get svc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n $(NAMESPACE) svc/$$SVC 15692:15692

## rmq-restart: Restart RabbitMQ deployment
.PHONY: rmq-restart
rmq-restart:
	@echo "=== Restarting RabbitMQ Deployment ==="
	@kubectl rollout restart deployment -n $(NAMESPACE) -l $(POD_SELECTOR)
	@kubectl rollout status deployment -n $(NAMESPACE) -l $(POD_SELECTOR)

## rmq-describe: Describe RabbitMQ resources
.PHONY: rmq-describe
rmq-describe:
	@echo "=== Describing RabbitMQ Deployment ==="
	@kubectl describe deployment -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "=== Describing RabbitMQ Pods ==="
	@kubectl describe pod -n $(NAMESPACE) -l $(POD_SELECTOR)

## rmq-events: Show recent Kubernetes events for RabbitMQ
.PHONY: rmq-events
rmq-events:
	@echo "=== Recent Events ==="
	@kubectl get events -n $(NAMESPACE) --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | \
	grep rabbitmq || echo "No recent events"

# ==============================================================================
# Server Status & Monitoring
# ==============================================================================

## rmq-status: Show cluster status
.PHONY: rmq-status
rmq-status:
	@echo "=== RabbitMQ Cluster Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl cluster_status

## rmq-node-health: Check node health
.PHONY: rmq-node-health
rmq-node-health:
	@echo "=== RabbitMQ Node Health Check ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl node_health_check

## rmq-ping: Ping RabbitMQ node
.PHONY: rmq-ping
rmq-ping:
	@echo "=== Pinging RabbitMQ Node ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-diagnostics ping

## rmq-alarms: Check alarm status
.PHONY: rmq-alarms
rmq-alarms:
	@echo "=== RabbitMQ Alarm Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl alarm_status

## rmq-metrics: Fetch Prometheus metrics
.PHONY: rmq-metrics
rmq-metrics:
	@echo "=== Fetching Prometheus Metrics ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- curl -s http://localhost:15692/metrics

## rmq-memory: Show memory usage
.PHONY: rmq-memory
rmq-memory:
	@echo "=== RabbitMQ Memory Usage ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl status | grep -A 10 "Memory"

# ==============================================================================
# Queue Operations
# ==============================================================================

## rmq-list-queues: List all queues with details
.PHONY: rmq-list-queues
rmq-list-queues:
	@echo "=== Listing RabbitMQ Queues ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_queues name messages consumers memory

## rmq-list-exchanges: List all exchanges
.PHONY: rmq-list-exchanges
rmq-list-exchanges:
	@echo "=== Listing RabbitMQ Exchanges ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_exchanges

## rmq-list-bindings: List all bindings
.PHONY: rmq-list-bindings
rmq-list-bindings:
	@echo "=== Listing RabbitMQ Bindings ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_bindings

## rmq-purge-queue: Purge queue (requires QUEUE variable)
.PHONY: rmq-purge-queue
rmq-purge-queue:
	@if [ -z "$(QUEUE)" ]; then \
		echo "Error: QUEUE variable is required"; \
		echo "Usage: make rmq-purge-queue QUEUE=my-queue"; \
		exit 1; \
	fi
	@echo "=== Purging Queue: $(QUEUE) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl purge_queue $(QUEUE)

## rmq-delete-queue: Delete queue (requires QUEUE variable)
.PHONY: rmq-delete-queue
rmq-delete-queue:
	@if [ -z "$(QUEUE)" ]; then \
		echo "Error: QUEUE variable is required"; \
		echo "Usage: make rmq-delete-queue QUEUE=my-queue"; \
		exit 1; \
	fi
	@echo "=== Deleting Queue: $(QUEUE) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl delete_queue $(QUEUE)

# ==============================================================================
# Connection Operations
# ==============================================================================

## rmq-list-connections: List all connections
.PHONY: rmq-list-connections
rmq-list-connections:
	@echo "=== Listing RabbitMQ Connections ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_connections

## rmq-list-channels: List all channels
.PHONY: rmq-list-channels
rmq-list-channels:
	@echo "=== Listing RabbitMQ Channels ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_channels

## rmq-list-consumers: List all consumers
.PHONY: rmq-list-consumers
rmq-list-consumers:
	@echo "=== Listing RabbitMQ Consumers ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_consumers

# ==============================================================================
# User Management
# ==============================================================================

## rmq-list-users: List all users
.PHONY: rmq-list-users
rmq-list-users:
	@echo "=== Listing RabbitMQ Users ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_users

## rmq-add-user: Add user (requires USER and PASSWORD variables)
.PHONY: rmq-add-user
rmq-add-user:
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "Error: USER and PASSWORD variables are required"; \
		echo "Usage: make rmq-add-user USER=myuser PASSWORD=mypassword"; \
		exit 1; \
	fi
	@echo "=== Adding User: $(USER) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl add_user $(USER) $(PASSWORD)

## rmq-delete-user: Delete user (requires USER variable)
.PHONY: rmq-delete-user
rmq-delete-user:
	@if [ -z "$(USER)" ]; then \
		echo "Error: USER variable is required"; \
		echo "Usage: make rmq-delete-user USER=myuser"; \
		exit 1; \
	fi
	@echo "=== Deleting User: $(USER) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl delete_user $(USER)

## rmq-change-password: Change user password (requires USER and PASSWORD variables)
.PHONY: rmq-change-password
rmq-change-password:
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "Error: USER and PASSWORD variables are required"; \
		echo "Usage: make rmq-change-password USER=myuser PASSWORD=newpassword"; \
		exit 1; \
	fi
	@echo "=== Changing Password for User: $(USER) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl change_password $(USER) $(PASSWORD)

## rmq-set-user-tags: Set user tags (requires USER and TAGS variables)
.PHONY: rmq-set-user-tags
rmq-set-user-tags:
	@if [ -z "$(USER)" ] || [ -z "$(TAGS)" ]; then \
		echo "Error: USER and TAGS variables are required"; \
		echo "Usage: make rmq-set-user-tags USER=myuser TAGS=administrator"; \
		exit 1; \
	fi
	@echo "=== Setting Tags for User $(USER): $(TAGS) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl set_user_tags $(USER) $(TAGS)

# ==============================================================================
# Virtual Host Management
# ==============================================================================

## rmq-list-vhosts: List all virtual hosts
.PHONY: rmq-list-vhosts
rmq-list-vhosts:
	@echo "=== Listing Virtual Hosts ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_vhosts

## rmq-add-vhost: Add virtual host (requires VHOST variable)
.PHONY: rmq-add-vhost
rmq-add-vhost:
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required"; \
		echo "Usage: make rmq-add-vhost VHOST=/my-vhost"; \
		exit 1; \
	fi
	@echo "=== Adding Virtual Host: $(VHOST) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl add_vhost $(VHOST)

## rmq-delete-vhost: Delete virtual host (requires VHOST variable)
.PHONY: rmq-delete-vhost
rmq-delete-vhost:
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required"; \
		echo "Usage: make rmq-delete-vhost VHOST=/my-vhost"; \
		exit 1; \
	fi
	@echo "=== Deleting Virtual Host: $(VHOST) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl delete_vhost $(VHOST)

## rmq-list-permissions: List permissions for vhost (requires VHOST variable)
.PHONY: rmq-list-permissions
rmq-list-permissions:
	@if [ -z "$(VHOST)" ]; then \
		echo "Error: VHOST variable is required"; \
		echo "Usage: make rmq-list-permissions VHOST=/"; \
		exit 1; \
	fi
	@echo "=== Listing Permissions for Vhost: $(VHOST) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_permissions -p $(VHOST)

## rmq-set-permissions: Set user permissions (requires VHOST, USER variables; optional CONF, WRITE, READ)
.PHONY: rmq-set-permissions
rmq-set-permissions:
	@if [ -z "$(VHOST)" ] || [ -z "$(USER)" ]; then \
		echo "Error: VHOST and USER variables are required"; \
		echo "Usage: make rmq-set-permissions VHOST=/ USER=myuser [CONF='.*' WRITE='.*' READ='.*']"; \
		exit 1; \
	fi
	@CONF_PERM=$${CONF:-".*"}; \
	WRITE_PERM=$${WRITE:-".*"}; \
	READ_PERM=$${READ:-".*"}; \
	echo "=== Setting Permissions for User $(USER) on Vhost $(VHOST) ==="; \
	POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl set_permissions -p $(VHOST) $(USER) "$$CONF_PERM" "$$WRITE_PERM" "$$READ_PERM"

# ==============================================================================
# Plugin Management
# ==============================================================================

## rmq-list-plugins: List all plugins
.PHONY: rmq-list-plugins
rmq-list-plugins:
	@echo "=== Listing RabbitMQ Plugins ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-plugins list

## rmq-list-enabled-plugins: List enabled plugins only
.PHONY: rmq-list-enabled-plugins
rmq-list-enabled-plugins:
	@echo "=== Listing Enabled Plugins ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-plugins list -E

## rmq-enable-plugin: Enable plugin (requires PLUGIN variable)
.PHONY: rmq-enable-plugin
rmq-enable-plugin:
	@if [ -z "$(PLUGIN)" ]; then \
		echo "Error: PLUGIN variable is required"; \
		echo "Usage: make rmq-enable-plugin PLUGIN=rabbitmq_stream"; \
		exit 1; \
	fi
	@echo "=== Enabling Plugin: $(PLUGIN) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-plugins enable $(PLUGIN)

## rmq-disable-plugin: Disable plugin (requires PLUGIN variable)
.PHONY: rmq-disable-plugin
rmq-disable-plugin:
	@if [ -z "$(PLUGIN)" ]; then \
		echo "Error: PLUGIN variable is required"; \
		echo "Usage: make rmq-disable-plugin PLUGIN=rabbitmq_stream"; \
		exit 1; \
	fi
	@echo "=== Disabling Plugin: $(PLUGIN) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-plugins disable $(PLUGIN)

# ==============================================================================
# Policy Management
# ==============================================================================

## rmq-list-policies: List all policies
.PHONY: rmq-list-policies
rmq-list-policies:
	@echo "=== Listing RabbitMQ Policies ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_policies

## rmq-set-policy-ha: Set HA policy for queues matching pattern (requires PATTERN variable)
.PHONY: rmq-set-policy-ha
rmq-set-policy-ha:
	@if [ -z "$(PATTERN)" ]; then \
		echo "Error: PATTERN variable is required"; \
		echo "Usage: make rmq-set-policy-ha PATTERN='^ha\\.'"; \
		exit 1; \
	fi
	@echo "=== Setting HA Policy for Pattern: $(PATTERN) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl set_policy ha-all "$(PATTERN)" '{"ha-mode":"all"}' --apply-to queues

# ==============================================================================
# Backup & Recovery
# ==============================================================================

## rmq-backup-definitions: Backup RabbitMQ definitions (exchanges, queues, bindings, users, policies)
.PHONY: rmq-backup-definitions
rmq-backup-definitions:
	@echo "=== Backing Up RabbitMQ Definitions ==="
	@mkdir -p $(BACKUP_DIR)/definitions-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- curl -u guest:guest \
		http://localhost:15672/api/definitions \
		-o /tmp/definitions.json; \
	kubectl cp -n $(NAMESPACE) $$POD:/tmp/definitions.json \
		$(BACKUP_DIR)/definitions-$(TIMESTAMP)/definitions.json; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm /tmp/definitions.json
	@echo "Definitions backup saved to: $(BACKUP_DIR)/definitions-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/definitions-$(TIMESTAMP)/

## rmq-backup-config: Backup RabbitMQ configuration (ConfigMaps, Secrets, Helm values)
.PHONY: rmq-backup-config
rmq-backup-config:
	@echo "=== Backing Up RabbitMQ Configuration ==="
	@mkdir -p $(BACKUP_DIR)/config-$(TIMESTAMP)
	@kubectl get configmap -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > \
		$(BACKUP_DIR)/config-$(TIMESTAMP)/configmap.yaml
	@kubectl get secret -n $(NAMESPACE) -l $(POD_SELECTOR) -o yaml > \
		$(BACKUP_DIR)/config-$(TIMESTAMP)/secret.yaml
	@helm get values -n $(NAMESPACE) $(RELEASE_NAME) > \
		$(BACKUP_DIR)/config-$(TIMESTAMP)/helm-values.yaml || true
	@echo "Configuration backup saved to: $(BACKUP_DIR)/config-$(TIMESTAMP)/"
	@ls -lh $(BACKUP_DIR)/config-$(TIMESTAMP)/

## rmq-snapshot-create: Create VolumeSnapshot of RabbitMQ PVC
.PHONY: rmq-snapshot-create
rmq-snapshot-create:
	@echo "=== Creating VolumeSnapshot ==="
	@PVC=$$(kubectl get pvc -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	cat <<EOF | kubectl apply -f - ; \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: rabbitmq-snapshot-$(TIMESTAMP); \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $$PVC; \
	EOF
	@echo "VolumeSnapshot created: rabbitmq-snapshot-$(TIMESTAMP)"

## rmq-full-backup: Full backup (definitions + configuration + snapshot)
.PHONY: rmq-full-backup
rmq-full-backup: rmq-backup-definitions rmq-backup-config rmq-snapshot-create
	@echo "=== Full Backup Complete ==="
	@echo "Backup location: $(BACKUP_DIR)/"
	@echo "Timestamp: $(TIMESTAMP)"

## rmq-restore-definitions: Restore definitions from backup (requires BACKUP_FILE variable)
.PHONY: rmq-restore-definitions
rmq-restore-definitions:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE variable is required"; \
		echo "Usage: make rmq-restore-definitions BACKUP_FILE=/path/to/definitions.json"; \
		exit 1; \
	fi
	@echo "=== Restoring Definitions from $(BACKUP_FILE) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl cp $(BACKUP_FILE) -n $(NAMESPACE) $$POD:/tmp/definitions.json; \
	kubectl exec -n $(NAMESPACE) $$POD -- curl -u guest:guest \
		-X POST http://localhost:15672/api/definitions \
		-H "Content-Type: application/json" \
		-d @/tmp/definitions.json; \
	kubectl exec -n $(NAMESPACE) $$POD -- rm /tmp/definitions.json
	@echo "Definitions restored successfully"

## rmq-backup-status: Show backup status and list backups
.PHONY: rmq-backup-status
rmq-backup-status:
	@echo "=== Backup Status ==="
	@echo "Backup directory: $(BACKUP_DIR)"
	@if [ -d "$(BACKUP_DIR)" ]; then \
		echo "Recent backups:"; \
		ls -lht $(BACKUP_DIR) | head -10; \
	else \
		echo "No backups found"; \
	fi
	@echo ""
	@echo "VolumeSnapshots:"
	@kubectl get volumesnapshot -n $(NAMESPACE) | grep rabbitmq || echo "No snapshots found"

# ==============================================================================
# Upgrade Support
# ==============================================================================

## rmq-pre-upgrade-check: Pre-upgrade validation checks
.PHONY: rmq-pre-upgrade-check
rmq-pre-upgrade-check:
	@echo "=== Pre-Upgrade Validation ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "1. Current Version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl version; \
	echo ""; \
	echo "2. Node Health:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl node_health_check; \
	echo ""; \
	echo "3. Alarm Status:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl alarm_status; \
	echo ""; \
	echo "4. Queue Count:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_queues --quiet | wc -l; \
	echo ""; \
	echo "5. User Count:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_users --quiet | wc -l; \
	echo ""; \
	echo "✓ Pre-upgrade validation complete"

## rmq-post-upgrade-check: Post-upgrade validation checks
.PHONY: rmq-post-upgrade-check
rmq-post-upgrade-check:
	@echo "=== Post-Upgrade Validation ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "1. New Version:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl version; \
	echo ""; \
	echo "2. Node Health:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl node_health_check; \
	echo ""; \
	echo "3. Alarm Status:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl alarm_status; \
	echo ""; \
	echo "4. Queues:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_queues; \
	echo ""; \
	echo "5. Users:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmqctl list_users; \
	echo ""; \
	echo "6. Enabled Plugins:"; \
	kubectl exec -n $(NAMESPACE) $$POD -- rabbitmq-plugins list -E; \
	echo ""; \
	echo "✓ Post-upgrade validation complete"

## rmq-upgrade-rollback: Rollback to previous Helm revision
.PHONY: rmq-upgrade-rollback
rmq-upgrade-rollback:
	@echo "=== Rolling Back RabbitMQ Upgrade ==="
	@helm rollback -n $(NAMESPACE) $(RELEASE_NAME)
	@kubectl rollout status deployment -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo "✓ Rollback complete"

# ==============================================================================
# Help
# ==============================================================================

.PHONY: help
help:
	@echo ""
	@echo "RabbitMQ Helm Chart Operational Commands"
	@echo ""
	@echo "Access & Debugging:"
	@echo "  rmq-shell                  - Open interactive shell in RabbitMQ pod"
	@echo "  rmq-logs                   - Tail RabbitMQ logs"
	@echo "  rmq-get-credentials        - Retrieve admin credentials from secret"
	@echo "  rmq-port-forward           - Port-forward Management UI to localhost:15672"
	@echo "  rmq-port-forward-amqp      - Port-forward AMQP to localhost:5672"
	@echo "  rmq-port-forward-metrics   - Port-forward Prometheus metrics to localhost:15692"
	@echo "  rmq-restart                - Restart RabbitMQ deployment"
	@echo "  rmq-describe               - Describe RabbitMQ resources"
	@echo "  rmq-events                 - Show recent Kubernetes events"
	@echo ""
	@echo "Server Status & Monitoring:"
	@echo "  rmq-status                 - Show cluster status"
	@echo "  rmq-node-health            - Check node health"
	@echo "  rmq-ping                   - Ping RabbitMQ node"
	@echo "  rmq-alarms                 - Check alarm status"
	@echo "  rmq-metrics                - Fetch Prometheus metrics"
	@echo "  rmq-memory                 - Show memory usage"
	@echo ""
	@echo "Queue Operations:"
	@echo "  rmq-list-queues            - List all queues with details"
	@echo "  rmq-list-exchanges         - List all exchanges"
	@echo "  rmq-list-bindings          - List all bindings"
	@echo "  rmq-purge-queue            - Purge queue (QUEUE=name)"
	@echo "  rmq-delete-queue           - Delete queue (QUEUE=name)"
	@echo ""
	@echo "Connection Operations:"
	@echo "  rmq-list-connections       - List all connections"
	@echo "  rmq-list-channels          - List all channels"
	@echo "  rmq-list-consumers         - List all consumers"
	@echo ""
	@echo "User Management:"
	@echo "  rmq-list-users             - List all users"
	@echo "  rmq-add-user               - Add user (USER=name PASSWORD=pass)"
	@echo "  rmq-delete-user            - Delete user (USER=name)"
	@echo "  rmq-change-password        - Change user password (USER=name PASSWORD=newpass)"
	@echo "  rmq-set-user-tags          - Set user tags (USER=name TAGS=administrator)"
	@echo ""
	@echo "Virtual Host Management:"
	@echo "  rmq-list-vhosts            - List all virtual hosts"
	@echo "  rmq-add-vhost              - Add vhost (VHOST=/name)"
	@echo "  rmq-delete-vhost           - Delete vhost (VHOST=/name)"
	@echo "  rmq-list-permissions       - List permissions (VHOST=/)"
	@echo "  rmq-set-permissions        - Set permissions (VHOST=/ USER=name)"
	@echo ""
	@echo "Plugin Management:"
	@echo "  rmq-list-plugins           - List all plugins"
	@echo "  rmq-list-enabled-plugins   - List enabled plugins only"
	@echo "  rmq-enable-plugin          - Enable plugin (PLUGIN=name)"
	@echo "  rmq-disable-plugin         - Disable plugin (PLUGIN=name)"
	@echo ""
	@echo "Policy Management:"
	@echo "  rmq-list-policies          - List all policies"
	@echo "  rmq-set-policy-ha          - Set HA policy (PATTERN='^ha\\.')"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  rmq-backup-definitions     - Backup definitions (exchanges, queues, users)"
	@echo "  rmq-backup-config          - Backup configuration (ConfigMaps, Secrets)"
	@echo "  rmq-snapshot-create        - Create VolumeSnapshot of PVC"
	@echo "  rmq-full-backup            - Full backup (all components)"
	@echo "  rmq-restore-definitions    - Restore definitions (BACKUP_FILE=path)"
	@echo "  rmq-backup-status          - Show backup status and list backups"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  rmq-pre-upgrade-check      - Pre-upgrade validation checks"
	@echo "  rmq-post-upgrade-check     - Post-upgrade validation checks"
	@echo "  rmq-upgrade-rollback       - Rollback to previous Helm revision"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE     - Kubernetes namespace (default: default)"
	@echo "  RELEASE_NAME  - Helm release name (default: my-rabbitmq)"
	@echo "  BACKUP_DIR    - Backup directory (default: ./backups/rabbitmq)"
	@echo ""

.DEFAULT_GOAL := help
