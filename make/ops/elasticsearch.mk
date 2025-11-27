CHART_NAME := elasticsearch
CHART_DIR := charts/$(CHART_NAME)

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Helper function to get Elasticsearch pod name
# Usage: POD=$(POD) or defaults to first pod
define get-es-pod-name
$(shell \
	if [ -n "$(POD)" ]; then \
		echo "$(POD)"; \
	else \
		POD_NAME=$$(kubectl get pod -l app.kubernetes.io/component=elasticsearch -o jsonpath="{.items[0].metadata.name}" 2>/dev/null); \
		if [ -z "$$POD_NAME" ]; then \
			echo "ERROR: No Elasticsearch pods found. Is Elasticsearch deployed?" >&2; \
			exit 1; \
		fi; \
		echo "$$POD_NAME"; \
	fi \
)
endef

# Helper function to get Kibana pod name
define get-kibana-pod-name
$(shell \
	POD_NAME=$$(kubectl get pod -l app.kubernetes.io/component=kibana -o jsonpath="{.items[0].metadata.name}" 2>/dev/null); \
	if [ -z "$$POD_NAME" ]; then \
		echo "ERROR: No Kibana pods found. Is Kibana enabled?" >&2; \
		exit 1; \
	fi; \
	echo "$$POD_NAME"; \
)
endef

# Helper to construct auth option
define get-auth-option
$(shell \
	PASSWORD=$$(kubectl get secret -l app.kubernetes.io/component=elasticsearch -o jsonpath='{.items[0].data.elastic-password}' 2>/dev/null | base64 -d 2>/dev/null); \
	if [ -n "$$PASSWORD" ]; then \
		echo "-u elastic:$$PASSWORD"; \
	fi \
)
endef

# Elasticsearch-specific targets

.PHONY: es-get-password
es-get-password:
	@echo "=== Elasticsearch Credentials ==="
	@PASSWORD=$$(kubectl get secret -l app.kubernetes.io/component=elasticsearch -o jsonpath='{.items[0].data.elastic-password}' 2>/dev/null | base64 -d 2>/dev/null); \
	if [ -n "$$PASSWORD" ]; then \
		echo "Elastic User: elastic"; \
		echo "Password: $$PASSWORD"; \
	else \
		echo "Security is DISABLED (no password set)"; \
	fi
	@echo ""

.PHONY: es-port-forward
es-port-forward:
	@echo "Port-forwarding Elasticsearch API to localhost:9200..."
	@kubectl port-forward svc/$(CHART_NAME) 9200:9200

.PHONY: kibana-port-forward
kibana-port-forward:
	@echo "Port-forwarding Kibana to localhost:5601..."
	@kubectl port-forward svc/kibana 5601:5601

.PHONY: es-health
es-health:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Cluster Health (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cluster/health?pretty $(call get-auth-option)

.PHONY: es-cluster-status
es-cluster-status:
	@echo "=== Elasticsearch Pods ==="
	@kubectl get pods -l app.kubernetes.io/component=elasticsearch
	@echo ""
	@echo "=== Kibana Pods ==="
	@kubectl get pods -l app.kubernetes.io/component=kibana 2>/dev/null || echo "Kibana not enabled"
	@echo ""
	@echo "=== Headless Service (Cluster Discovery) ==="
	@kubectl get svc $(CHART_NAME)-headless 2>/dev/null || echo "Not in cluster mode"
	@echo ""
	@echo "=== PVCs ==="
	@kubectl get pvc -l app.kubernetes.io/component=elasticsearch
	@echo ""
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Cluster Nodes ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cat/nodes?v $(call get-auth-option)

.PHONY: es-indices
es-indices:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Indices (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cat/indices?v $(call get-auth-option)

.PHONY: es-create-index
es-create-index:
	@if [ -z "$(INDEX)" ]; then \
		echo "Error: INDEX parameter is required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-create-index INDEX=myindex [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Creating index: $(INDEX) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- curl -X PUT http://localhost:9200/$(INDEX)?pretty $(call get-auth-option)

.PHONY: es-delete-index
es-delete-index:
	@if [ -z "$(INDEX)" ]; then \
		echo "Error: INDEX parameter is required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-delete-index INDEX=myindex [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Deleting index: $(INDEX) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- curl -X DELETE http://localhost:9200/$(INDEX)?pretty $(call get-auth-option)

.PHONY: es-stats
es-stats:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Cluster Stats (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cluster/stats?pretty $(call get-auth-option)

.PHONY: es-nodes
es-nodes:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Node Info (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_nodes?pretty $(call get-auth-option)

.PHONY: es-shards
es-shards:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Shards (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cat/shards?v $(call get-auth-option)

.PHONY: es-allocation
es-allocation:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Allocation (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cat/allocation?v $(call get-auth-option)

.PHONY: es-tasks
es-tasks:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Elasticsearch Running Tasks (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_cat/tasks?v $(call get-auth-option)

.PHONY: es-version
es-version:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Elasticsearch version (pod: $$POD_NAME):"; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200 $(call get-auth-option) | grep version -A 5

.PHONY: kibana-health
kibana-health:
	@POD_NAME="$(call get-kibana-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Kibana Health (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:5601/api/status | grep -E "overall|elasticsearch"

.PHONY: es-logs
es-logs:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Tailing Elasticsearch logs (pod: $$POD_NAME)..."; \
	kubectl logs -f $$POD_NAME

.PHONY: es-logs-all
es-logs-all:
	@echo "Tailing all Elasticsearch pod logs..."
	@kubectl logs -f -l app.kubernetes.io/component=elasticsearch --all-containers=true --prefix=true

.PHONY: kibana-logs
kibana-logs:
	@POD_NAME="$(call get-kibana-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Tailing Kibana logs (pod: $$POD_NAME)..."; \
	kubectl logs -f $$POD_NAME

.PHONY: kibana-logs-all
kibana-logs-all:
	@echo "Tailing all Kibana pod logs..."
	@kubectl logs -f -l app.kubernetes.io/component=kibana --all-containers=true --prefix=true

.PHONY: es-shell
es-shell:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Opening shell in Elasticsearch pod (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- /bin/bash

.PHONY: kibana-shell
kibana-shell:
	@POD_NAME="$(call get-kibana-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Opening shell in Kibana pod (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- /bin/bash

.PHONY: es-restart
es-restart:
	@echo "Restarting Elasticsearch statefulset..."
	@kubectl rollout restart statefulset/$(CHART_NAME)
	@kubectl rollout status statefulset/$(CHART_NAME)

.PHONY: kibana-restart
kibana-restart:
	@echo "Restarting Kibana deployment..."
	@kubectl rollout restart deployment/kibana
	@kubectl rollout status deployment/kibana

.PHONY: es-scale
es-scale:
	@if [ -z "$(REPLICAS)" ]; then \
		echo "Error: REPLICAS parameter is required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-scale REPLICAS=3"; \
		exit 1; \
	fi
	@if [ $(REPLICAS) -gt 1 ] && [ $(REPLICAS) -lt 3 ]; then \
		echo "Error: Cluster mode requires at least 3 replicas for quorum"; \
		exit 1; \
	fi
	@echo "Scaling Elasticsearch to $(REPLICAS) replicas..."
	@kubectl scale statefulset $(CHART_NAME) --replicas=$(REPLICAS)

.PHONY: es-snapshot-repos
es-snapshot-repos:
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Snapshot Repositories (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_snapshot?pretty $(call get-auth-option)

.PHONY: es-create-snapshot-repo
es-create-snapshot-repo:
	@if [ -z "$(REPO)" ]; then \
		echo "Error: REPO parameter is required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-create-snapshot-repo REPO=minio BUCKET=backups ENDPOINT=http://minio:9000 ACCESS_KEY=xxx SECRET_KEY=xxx [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@if [ -z "$(BUCKET)" ] || [ -z "$(ENDPOINT)" ] || [ -z "$(ACCESS_KEY)" ] || [ -z "$(SECRET_KEY)" ]; then \
		echo "Error: BUCKET, ENDPOINT, ACCESS_KEY, and SECRET_KEY parameters are required"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Creating S3 snapshot repository: $(REPO) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- curl -X PUT "http://localhost:9200/_snapshot/$(REPO)?pretty" $(call get-auth-option) \
		-H 'Content-Type: application/json' -d'{ \
		"type": "s3", \
		"settings": { \
			"bucket": "$(BUCKET)", \
			"endpoint": "$(ENDPOINT)", \
			"access_key": "$(ACCESS_KEY)", \
			"secret_key": "$(SECRET_KEY)", \
			"path_style_access": true \
		} \
	}'

.PHONY: es-snapshots
es-snapshots:
	@if [ -z "$(REPO)" ]; then \
		echo "Error: REPO parameter is required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-snapshots REPO=minio [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Snapshots in repository: $(REPO) (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:9200/_snapshot/$(REPO)/_all?pretty $(call get-auth-option)

.PHONY: es-create-snapshot
es-create-snapshot:
	@if [ -z "$(REPO)" ] || [ -z "$(SNAPSHOT)" ]; then \
		echo "Error: REPO and SNAPSHOT parameters are required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-create-snapshot REPO=minio SNAPSHOT=snapshot_1 [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Creating snapshot: $(SNAPSHOT) in repository: $(REPO) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- curl -X PUT "http://localhost:9200/_snapshot/$(REPO)/$(SNAPSHOT)?wait_for_completion=false&pretty" $(call get-auth-option)

.PHONY: es-restore-snapshot
es-restore-snapshot:
	@if [ -z "$(REPO)" ] || [ -z "$(SNAPSHOT)" ]; then \
		echo "Error: REPO and SNAPSHOT parameters are required"; \
		echo "Usage: make -f make/ops/elasticsearch.mk es-restore-snapshot REPO=minio SNAPSHOT=snapshot_1 [POD=elasticsearch-0]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Restoring snapshot: $(SNAPSHOT) from repository: $(REPO) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- curl -X POST "http://localhost:9200/_snapshot/$(REPO)/$(SNAPSHOT)/_restore?pretty" $(call get-auth-option)

# Help from common makefile
.PHONY: help-common
help-common:
	@$(MAKE) -f make/common.mk help CHART_NAME=$(CHART_NAME) CHART_DIR=$(CHART_DIR)

# =============================================================================
# Backup & Recovery (Enhanced)
# =============================================================================

.PHONY: es-cluster-settings-backup
es-cluster-settings-backup:
	@echo "Backing up Elasticsearch cluster settings..."
	@mkdir -p tmp/elasticsearch-backups/settings
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/elasticsearch-backups/settings/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Exporting cluster settings..."; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_cluster/settings?pretty $(call get-auth-option) > "$$BACKUP_DIR/cluster-settings.json"; \
	echo "Exporting index templates..."; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_template?pretty $(call get-auth-option) > "$$BACKUP_DIR/index-templates.json"; \
	echo "Exporting ILM policies..."; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_ilm/policy?pretty $(call get-auth-option) > "$$BACKUP_DIR/ilm-policies.json" 2>/dev/null || true; \
	echo "✓ Cluster settings backup completed: $$BACKUP_DIR"

.PHONY: es-data-backup
es-data-backup:
	@echo "Backing up Elasticsearch data volumes (PVC snapshot)..."
	@echo "Note: This requires VolumeSnapshot CRD and CSI driver"
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	SNAPSHOT_NAME="elasticsearch-data-snapshot-$$TIMESTAMP"; \
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

# =============================================================================
# Upgrade Operations
# =============================================================================

.PHONY: es-pre-upgrade-check
es-pre-upgrade-check:
	@echo "=== Elasticsearch Pre-Upgrade Health Check ==="
	@echo ""
	@echo "1. Checking pod status..."
	@kubectl get pods -l app.kubernetes.io/component=elasticsearch | grep -E "Running|NAME" || echo "✗ Pods not running"
	@echo ""
	@echo "2. Checking cluster health..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	STATUS=$$(kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_cluster/health $(call get-auth-option) | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"'); \
	if [ "$$STATUS" = "green" ]; then \
		echo "✓ Cluster health: GREEN"; \
	elif [ "$$STATUS" = "yellow" ]; then \
		echo "⚠️  Cluster health: YELLOW (acceptable for single-node)"; \
	else \
		echo "✗ Cluster health: $$STATUS (not safe to upgrade)"; \
	fi
	@echo ""
	@echo "3. Checking shard allocation..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	UNASSIGNED=$$(kubectl exec $$POD_NAME -- curl -s "http://localhost:9200/_cat/shards" $(call get-auth-option) | grep UNASSIGNED | wc -l); \
	if [ $$UNASSIGNED -gt 0 ]; then \
		echo "⚠️  $$UNASSIGNED unassigned shards found"; \
	else \
		echo "✓ No unassigned shards"; \
	fi
	@echo ""
	@echo "4. Checking Elasticsearch version..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200 $(call get-auth-option) | grep version -A 3
	@echo ""
	@echo "✓ Pre-upgrade checks completed"
	@echo "⚠️  Make sure to backup before upgrading!"
	@echo "   make -f make/ops/elasticsearch.mk es-create-snapshot REPO=<repo> SNAPSHOT=pre-upgrade-$$(date +%Y%m%d-%H%M%S)"

.PHONY: es-disable-shard-allocation
es-disable-shard-allocation:
	@echo "Disabling shard allocation (prevents rebalancing during upgrade)..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -X PUT "http://localhost:9200/_cluster/settings?pretty" $(call get-auth-option) \
		-H 'Content-Type: application/json' -d'{ \
		"persistent": { \
			"cluster.routing.allocation.enable": "primaries" \
		} \
	}'
	@echo "✓ Shard allocation disabled (primaries only)"

.PHONY: es-enable-shard-allocation
es-enable-shard-allocation:
	@echo "Enabling shard allocation..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -X PUT "http://localhost:9200/_cluster/settings?pretty" $(call get-auth-option) \
		-H 'Content-Type: application/json' -d'{ \
		"persistent": { \
			"cluster.routing.allocation.enable": null \
		} \
	}'
	@echo "✓ Shard allocation enabled"

.PHONY: es-post-upgrade-check
es-post-upgrade-check:
	@echo "=== Elasticsearch Post-Upgrade Validation ==="
	@echo ""
	@echo "1. Checking pod status..."
	@kubectl get pods -l app.kubernetes.io/component=elasticsearch
	@echo ""
	@echo "2. Waiting for pods to be ready..."
	@kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/component=elasticsearch || echo "⚠️  Pods not ready"
	@echo ""
	@echo "3. Checking Elasticsearch version..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200 $(call get-auth-option) | grep version -A 3
	@echo ""
	@echo "4. Checking cluster health..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_cluster/health?pretty $(call get-auth-option)
	@echo ""
	@echo "5. Checking all nodes joined..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_cat/nodes?v $(call get-auth-option)
	@echo ""
	@echo "6. Checking shard allocation..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	UNASSIGNED=$$(kubectl exec $$POD_NAME -- curl -s "http://localhost:9200/_cat/shards" $(call get-auth-option) | grep UNASSIGNED | wc -l); \
	if [ $$UNASSIGNED -gt 0 ]; then \
		echo "⚠️  $$UNASSIGNED unassigned shards found"; \
	else \
		echo "✓ All shards assigned"; \
	fi
	@echo ""
	@echo "7. Verifying index accessibility..."
	@POD_NAME="$(call get-es-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	kubectl exec $$POD_NAME -- curl -s http://localhost:9200/_cat/indices?v $(call get-auth-option) | head -10
	@echo ""
	@echo "✓ Post-upgrade validation completed"

.PHONY: es-upgrade-rollback
es-upgrade-rollback:
	@echo "=== Elasticsearch Upgrade Rollback Procedures ==="
	@echo ""
	@echo "Option 1: Helm Rollback (Fast - reverts chart only)"
	@echo "  helm rollback elasticsearch"
	@echo "  make -f make/ops/elasticsearch.mk es-post-upgrade-check"
	@echo ""
	@echo "Option 2: Snapshot Restore (Complete - includes data)"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=0"
	@echo "  make -f make/ops/elasticsearch.mk es-restore-snapshot REPO=<repo> SNAPSHOT=<snapshot>"
	@echo "  helm rollback elasticsearch"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=<original-replicas>"
	@echo "  make -f make/ops/elasticsearch.mk es-enable-shard-allocation"
	@echo ""
	@echo "Option 3: PVC Restore (Disaster recovery)"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=0"
	@echo "  # Restore PVC from VolumeSnapshot"
	@echo "  kubectl apply -f <pvc-from-snapshot.yaml>"
	@echo "  helm rollback elasticsearch"
	@echo "  kubectl scale statefulset/$(CHART_NAME) --replicas=<original-replicas>"
	@echo ""
	@echo "⚠️  Always verify cluster health after rollback:"
	@echo "  make -f make/ops/elasticsearch.mk es-post-upgrade-check"

.PHONY: help
help: help-common
	@echo ""
	@echo "Elasticsearch specific targets:"
	@echo "  es-get-password              - Display elastic user credentials"
	@echo "  es-port-forward              - Port-forward ES API to localhost:9200"
	@echo "  kibana-port-forward          - Port-forward Kibana to localhost:5601"
	@echo ""
	@echo "Health and Status:"
	@echo "  es-health                    - Check cluster health ([POD=elasticsearch-0])"
	@echo "  es-cluster-status            - Show cluster status (pods, nodes, PVCs)"
	@echo "  es-nodes                     - Show detailed node information ([POD=elasticsearch-0])"
	@echo "  es-version                   - Show Elasticsearch version ([POD=elasticsearch-0])"
	@echo "  kibana-health                - Check Kibana health"
	@echo ""
	@echo "Index Management:"
	@echo "  es-indices                   - List all indices ([POD=elasticsearch-0])"
	@echo "  es-create-index              - Create index (INDEX=name [POD=elasticsearch-0])"
	@echo "  es-delete-index              - Delete index (INDEX=name [POD=elasticsearch-0])"
	@echo "  es-shards                    - Show shard allocation ([POD=elasticsearch-0])"
	@echo "  es-allocation                - Show disk allocation ([POD=elasticsearch-0])"
	@echo ""
	@echo "Monitoring:"
	@echo "  es-stats                     - Show cluster statistics ([POD=elasticsearch-0])"
	@echo "  es-tasks                     - Show running tasks ([POD=elasticsearch-0])"
	@echo "  es-logs                      - Tail ES logs from specific pod ([POD=elasticsearch-0])"
	@echo "  es-logs-all                  - Tail logs from all ES pods"
	@echo "  kibana-logs                  - Tail Kibana logs"
	@echo "  kibana-logs-all              - Tail logs from all Kibana pods"
	@echo ""
	@echo "Operations:"
	@echo "  es-shell                     - Open shell in ES pod ([POD=elasticsearch-0])"
	@echo "  kibana-shell                 - Open shell in Kibana pod"
	@echo "  es-restart                   - Restart Elasticsearch statefulset"
	@echo "  kibana-restart               - Restart Kibana deployment"
	@echo "  es-scale                     - Scale replicas (REPLICAS=N, min 3 for cluster)"
	@echo ""
	@echo "Snapshot/Backup (S3/MinIO):"
	@echo "  es-snapshot-repos            - List snapshot repositories ([POD=elasticsearch-0])"
	@echo "  es-create-snapshot-repo      - Create S3 snapshot repository"
	@echo "                                 (REPO=name BUCKET=name ENDPOINT=url ACCESS_KEY=xxx SECRET_KEY=xxx)"
	@echo "  es-snapshots                 - List snapshots in repository (REPO=name [POD=elasticsearch-0])"
	@echo "  es-create-snapshot           - Create snapshot (REPO=name SNAPSHOT=name [POD=elasticsearch-0])"
	@echo "  es-restore-snapshot          - Restore snapshot (REPO=name SNAPSHOT=name [POD=elasticsearch-0])"
	@echo "  es-cluster-settings-backup   - Backup cluster settings, templates, ILM policies"
	@echo "  es-data-backup               - Create PVC snapshot for data volumes"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  es-pre-upgrade-check         - Pre-upgrade health and readiness check"
	@echo "  es-disable-shard-allocation  - Disable shard allocation (before upgrade)"
	@echo "  es-enable-shard-allocation   - Enable shard allocation (after upgrade)"
	@echo "  es-post-upgrade-check        - Post-upgrade validation"
	@echo "  es-upgrade-rollback          - Display rollback procedures"
	@echo ""
	@echo "Note: Commands default to first pod. Use POD=elasticsearch-N to target specific pod."
	@echo "      Authentication is automatically handled based on security settings."
