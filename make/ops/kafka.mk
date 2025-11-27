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

# =============================================================================
# Backup & Recovery
# =============================================================================

.PHONY: kafka-topics-backup
kafka-topics-backup:
	@echo "Backing up Kafka topic metadata..."
	@mkdir -p tmp/kafka-backups/topics
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/kafka-backups/topics/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "Exporting all topics metadata..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --describe --bootstrap-server localhost:9092 > "$$BACKUP_DIR/topics-metadata.txt"; \
	echo "✓ Topics backup completed: $$BACKUP_DIR"

.PHONY: kafka-configs-backup
kafka-configs-backup:
	@echo "Backing up Kafka broker configurations..."
	@mkdir -p tmp/kafka-backups/configs
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/kafka-backups/configs/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "Exporting broker configs..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-configs.sh --describe --entity-type brokers --all --bootstrap-server localhost:9092 > "$$BACKUP_DIR/broker-configs.txt" 2>/dev/null || true; \
	echo "Exporting topic configs..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-configs.sh --describe --entity-type topics --all --bootstrap-server localhost:9092 > "$$BACKUP_DIR/topic-configs.txt" 2>/dev/null || true; \
	echo "✓ Configs backup completed: $$BACKUP_DIR"

.PHONY: kafka-consumer-offsets-backup
kafka-consumer-offsets-backup:
	@echo "Backing up consumer group offsets..."
	@mkdir -p tmp/kafka-backups/offsets
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/kafka-backups/offsets/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "Exporting consumer groups..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-consumer-groups.sh --list --bootstrap-server localhost:9092 > "$$BACKUP_DIR/consumer-groups-list.txt"; \
	for GROUP in $$(cat "$$BACKUP_DIR/consumer-groups-list.txt"); do \
		echo "Exporting offsets for group: $$GROUP"; \
		$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
			kafka-consumer-groups.sh --describe --group $$GROUP --bootstrap-server localhost:9092 > "$$BACKUP_DIR/offsets-$$GROUP.txt" 2>/dev/null || true; \
	done; \
	echo "✓ Consumer offsets backup completed: $$BACKUP_DIR"

.PHONY: kafka-data-backup
kafka-data-backup:
	@echo "Backing up Kafka data volumes (PVC snapshot)..."
	@echo "Note: This requires VolumeSnapshot CRD and CSI driver"
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	SNAPSHOT_NAME="kafka-data-snapshot-$$TIMESTAMP"; \
	echo "Creating snapshot for PVC: $(CHART_NAME)-data-0"; \
	kubectl create -f - <<EOF; \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $$SNAPSHOT_NAME; \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(CHART_NAME)-data-0; \
	EOF \
	echo "✓ Snapshot created: $$SNAPSHOT_NAME"; \
	echo "  Verify with: kubectl get volumesnapshot -n $(NAMESPACE) $$SNAPSHOT_NAME"

.PHONY: kafka-full-backup
kafka-full-backup:
	@echo "=== Kafka Full Backup ==="
	@echo "Starting comprehensive backup..."
	@echo ""
	@echo "1. Backing up topic metadata..."
	@make -f make/ops/kafka.mk kafka-topics-backup
	@echo ""
	@echo "2. Backing up configurations..."
	@make -f make/ops/kafka.mk kafka-configs-backup
	@echo ""
	@echo "3. Backing up consumer offsets..."
	@make -f make/ops/kafka.mk kafka-consumer-offsets-backup
	@echo ""
	@echo "4. Creating PVC snapshot..."
	@echo "   Run manually: make -f make/ops/kafka.mk kafka-data-backup"
	@echo ""
	@echo "✓ Full backup completed (except PVC snapshot)"

# =============================================================================
# Upgrade Operations
# =============================================================================

.PHONY: kafka-pre-upgrade-check
kafka-pre-upgrade-check:
	@echo "=== Kafka Pre-Upgrade Health Check ==="
	@echo ""
	@echo "1. Checking pod status..."
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME) | grep -E "Running|NAME" || echo "✗ Pods not running"
	@echo ""
	@echo "2. Checking broker connectivity..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1 && echo "✓ Brokers reachable" || echo "✗ Brokers unreachable"
	@echo ""
	@echo "3. Checking cluster metadata..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-metadata.sh --snapshot /tmp/kafka-logs/__cluster_metadata-0/00000000000000000000.log 2>/dev/null | head -10 || echo "⚠️  Metadata check skipped (KRaft mode)"
	@echo ""
	@echo "4. Checking under-replicated partitions..."
	@UNDER_REPLICATED=$$($(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --describe --bootstrap-server localhost:9092 --under-replicated-partitions 2>/dev/null | wc -l); \
	if [ $$UNDER_REPLICATED -gt 0 ]; then \
		echo "⚠️  $$UNDER_REPLICATED under-replicated partitions found"; \
	else \
		echo "✓ No under-replicated partitions"; \
	fi
	@echo ""
	@echo "✓ Pre-upgrade checks completed"
	@echo "⚠️  Make sure to backup before upgrading!"
	@echo "   make -f make/ops/kafka.mk kafka-full-backup"

.PHONY: kafka-post-upgrade-check
kafka-post-upgrade-check:
	@echo "=== Kafka Post-Upgrade Validation ==="
	@echo ""
	@echo "1. Checking pod status..."
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "2. Waiting for StatefulSet to be ready..."
	@$(KUBECTL) wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=$(CHART_NAME) || echo "⚠️  Pods not ready"
	@echo ""
	@echo "3. Checking Kafka version..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | head -1 || echo "⚠️  Version check failed"
	@echo ""
	@echo "4. Verifying broker cluster..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | grep -o '^[0-9].*:9092' && echo "✓ Brokers online" || echo "✗ Broker check failed"
	@echo ""
	@echo "5. Testing topic list..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --list --bootstrap-server localhost:9092 >/dev/null 2>&1 && echo "✓ Topics accessible" || echo "⚠️  Topics check failed"
	@echo ""
	@echo "6. Checking under-replicated partitions..."
	@UNDER_REPLICATED=$$($(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		kafka-topics.sh --describe --bootstrap-server localhost:9092 --under-replicated-partitions 2>/dev/null | wc -l); \
	if [ $$UNDER_REPLICATED -gt 0 ]; then \
		echo "⚠️  $$UNDER_REPLICATED under-replicated partitions found"; \
	else \
		echo "✓ No under-replicated partitions"; \
	fi
	@echo ""
	@echo "✓ Post-upgrade validation completed"

.PHONY: kafka-upgrade-rollback
kafka-upgrade-rollback:
	@echo "=== Kafka Upgrade Rollback Procedures ==="
	@echo ""
	@echo "Option 1: Helm Rollback (Fast - reverts chart only)"
	@echo "  helm rollback kafka"
	@echo "  make -f make/ops/kafka.mk kafka-post-upgrade-check"
	@echo ""
	@echo "Option 2: PVC Restore (Complete - includes data)"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=0"
	@echo "  # Restore PVC from VolumeSnapshot"
	@echo "  kubectl apply -f <pvc-from-snapshot.yaml>"
	@echo "  helm rollback kafka"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=<original-replicas>"
	@echo ""
	@echo "Option 3: Full Disaster Recovery"
	@echo "  helm uninstall kafka"
	@echo "  helm install kafka charts/kafka -f values.yaml --version <previous-version>"
	@echo "  # Restore PVC from snapshot"
	@echo "  # Restore topic metadata and consumer offsets if needed"
	@echo ""
	@echo "⚠️  Always verify cluster health after rollback:"
	@echo "  make -f make/ops/kafka.mk kafka-post-upgrade-check"

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
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  kafka-topics-backup                    - Backup topic metadata"
	@echo "  kafka-configs-backup                   - Backup broker and topic configurations"
	@echo "  kafka-consumer-offsets-backup          - Backup consumer group offsets"
	@echo "  kafka-data-backup                      - Create PVC snapshot for data volumes"
	@echo "  kafka-full-backup                      - Full backup (metadata + configs + offsets)"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  kafka-pre-upgrade-check                - Pre-upgrade health and readiness check"
	@echo "  kafka-post-upgrade-check               - Post-upgrade validation"
	@echo "  kafka-upgrade-rollback                 - Display rollback procedures"
	@echo ""
