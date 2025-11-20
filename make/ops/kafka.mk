# kafka chart configuration
CHART_NAME := kafka
CHART_DIR := charts/$(CHART_NAME)

# Common Makefile
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Kafka-specific targets

# === Connection and Shell ===

.PHONY: kafka-shell
kafka-shell:
	@echo "Opening Kafka broker shell..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- bash

.PHONY: kafka-logs
kafka-logs:
	@echo "Viewing Kafka logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: kafka-logs-all
kafka-logs-all:
	@echo "Viewing logs from all Kafka brokers..."
	@$(KUBECTL) logs -l app.kubernetes.io/name=$(CHART_NAME) --all-containers=true --prefix=true

# === Topic Management ===

.PHONY: kafka-topics-list
kafka-topics-list:
	@echo "Listing Kafka topics..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --list --bootstrap-server localhost:9092

.PHONY: kafka-topic-create
kafka-topic-create:
	@if [ -z "$(TOPIC)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-topic-create TOPIC=my-topic PARTITIONS=3 REPLICATION=2"; exit 1; fi
	@echo "Creating topic $(TOPIC)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --create --topic $(TOPIC) \
		--bootstrap-server localhost:9092 \
		--partitions $(or $(PARTITIONS),1) \
		--replication-factor $(or $(REPLICATION),1)

.PHONY: kafka-topic-describe
kafka-topic-describe:
	@if [ -z "$(TOPIC)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-topic-describe TOPIC=my-topic"; exit 1; fi
	@echo "Describing topic $(TOPIC)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --describe --topic $(TOPIC) --bootstrap-server localhost:9092

.PHONY: kafka-topic-delete
kafka-topic-delete:
	@if [ -z "$(TOPIC)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-topic-delete TOPIC=my-topic"; exit 1; fi
	@echo "Deleting topic $(TOPIC)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --delete --topic $(TOPIC) --bootstrap-server localhost:9092

# === Consumer Groups ===

.PHONY: kafka-consumer-groups-list
kafka-consumer-groups-list:
	@echo "Listing consumer groups..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-consumer-groups.sh --list --bootstrap-server localhost:9092

.PHONY: kafka-consumer-group-describe
kafka-consumer-group-describe:
	@if [ -z "$(GROUP)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-consumer-group-describe GROUP=my-group"; exit 1; fi
	@echo "Describing consumer group $(GROUP)..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-consumer-groups.sh --describe --group $(GROUP) --bootstrap-server localhost:9092

# === Producer/Consumer Test ===

.PHONY: kafka-produce
kafka-produce:
	@if [ -z "$(TOPIC)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-produce TOPIC=my-topic"; exit 1; fi
	@echo "Starting producer for topic $(TOPIC). Type messages and press Ctrl+C to exit."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-console-producer.sh --topic $(TOPIC) --bootstrap-server localhost:9092

.PHONY: kafka-consume
kafka-consume:
	@if [ -z "$(TOPIC)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-consume TOPIC=my-topic"; exit 1; fi
	@echo "Starting consumer for topic $(TOPIC) from beginning..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-console-consumer.sh --topic $(TOPIC) --from-beginning --bootstrap-server localhost:9092

# === Broker Information ===

.PHONY: kafka-broker-list
kafka-broker-list:
	@echo "Listing Kafka brokers..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | grep -o '^[0-9].*:9092'

.PHONY: kafka-cluster-id
kafka-cluster-id:
	@echo "Getting cluster ID..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-cluster.sh cluster-id --bootstrap-server localhost:9092

# === Kafka UI ===

.PHONY: kafka-ui-port-forward
kafka-ui-port-forward:
	@echo "Port-forwarding Kafka UI to localhost:8080..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME)-ui 8080:8080

# === Utilities ===

.PHONY: kafka-port-forward
kafka-port-forward:
	@echo "Port-forwarding Kafka to localhost:9092..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME) 9092:9092

.PHONY: kafka-restart
kafka-restart:
	@echo "Restarting Kafka StatefulSet..."
	@$(KUBECTL) rollout restart statefulset/$(CHART_NAME)
	@$(KUBECTL) rollout status statefulset/$(CHART_NAME)

.PHONY: kafka-scale
kafka-scale:
	@if [ -z "$(REPLICAS)" ]; then echo "Usage: make -f make/ops/kafka.mk kafka-scale REPLICAS=3"; exit 1; fi
	@echo "Scaling Kafka to $(REPLICAS) brokers..."
	@echo "WARNING: Scaling Kafka requires updating controllerQuorumVoters in values!"
	@$(KUBECTL) scale statefulset/$(CHART_NAME) --replicas=$(REPLICAS)
	@$(KUBECTL) rollout status statefulset/$(CHART_NAME)

# === Help ===

.PHONY: help
help:
	@echo "Kafka Chart Operations:"
	@echo ""
	@echo "Connection:"
	@echo "  kafka-shell                            - Open Kafka broker shell"
	@echo "  kafka-logs                             - View logs from first broker"
	@echo "  kafka-logs-all                         - View logs from all brokers"
	@echo ""
	@echo "Topic Management:"
	@echo "  kafka-topics-list                      - List all topics"
	@echo "  kafka-topic-create TOPIC=<name>        - Create topic (optional: PARTITIONS=3 REPLICATION=2)"
	@echo "  kafka-topic-describe TOPIC=<name>      - Describe topic"
	@echo "  kafka-topic-delete TOPIC=<name>        - Delete topic"
	@echo ""
	@echo "Consumer Groups:"
	@echo "  kafka-consumer-groups-list             - List consumer groups"
	@echo "  kafka-consumer-group-describe GROUP=<name> - Describe consumer group"
	@echo ""
	@echo "Producer/Consumer:"
	@echo "  kafka-produce TOPIC=<name>             - Start interactive producer"
	@echo "  kafka-consume TOPIC=<name>             - Start consumer from beginning"
	@echo ""
	@echo "Broker Information:"
	@echo "  kafka-broker-list                      - List brokers"
	@echo "  kafka-cluster-id                       - Get cluster ID"
	@echo ""
	@echo "Kafka UI:"
	@echo "  kafka-ui-port-forward                  - Port forward UI to localhost:8080"
	@echo ""
	@echo "Utilities:"
	@echo "  kafka-port-forward                     - Port forward to localhost:9092"
	@echo "  kafka-restart                          - Restart StatefulSet"
	@echo "  kafka-scale REPLICAS=<n>               - Scale brokers (requires values update!)"
