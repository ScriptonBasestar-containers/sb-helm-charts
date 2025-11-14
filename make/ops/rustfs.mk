# rustfs 차트 설정
CHART_NAME := rustfs
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# RustFS 특화 타겟
.PHONY: rustfs-get-credentials
rustfs-get-credentials:
	@echo "=== RustFS Credentials ==="
	@echo ""
	@echo "Root User:"
	@$(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-user}' | base64 -d
	@echo ""
	@echo "Root Password:"
	@$(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-password}' | base64 -d
	@echo ""

.PHONY: rustfs-port-forward-api
rustfs-port-forward-api:
	@echo "Port-forwarding RustFS API (S3) to localhost:9000..."
	@$(KUBECTL) port-forward svc/$$($(KUBECTL) get svc -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component!=headless -o jsonpath='{.items[0].metadata.name}') 9000:9000

.PHONY: rustfs-port-forward-console
rustfs-port-forward-console:
	@echo "Port-forwarding RustFS Console to localhost:9001..."
	@$(KUBECTL) port-forward svc/$$($(KUBECTL) get svc -l app.kubernetes.io/name=$(CHART_NAME),app.kubernetes.io/component!=headless -o jsonpath='{.items[0].metadata.name}') 9001:9001

.PHONY: rustfs-test-s3
rustfs-test-s3:
	@echo "Testing S3 API with MinIO Client (mc)..."
	@echo "Checking if 'mc' is installed..."
	@which mc > /dev/null || (echo "Error: MinIO Client 'mc' not found. Install from: https://min.io/docs/minio/linux/reference/minio-mc.html" && exit 1)
	@echo "Configuring mc alias 'rustfs'..."
	@mc alias set rustfs http://localhost:9000 $$($(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-user}' | base64 -d) $$($(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].data.root-password}' | base64 -d)
	@echo "Testing connection..."
	@mc admin info rustfs
	@echo "Listing buckets..."
	@mc ls rustfs

.PHONY: rustfs-health
rustfs-health:
	@echo "Checking RustFS health status..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:9000/rustfs/health/live || echo "Liveness check failed"
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:9000/rustfs/health/ready || echo "Readiness check failed"

.PHONY: rustfs-metrics
rustfs-metrics:
	@echo "Fetching RustFS metrics..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- curl -s http://localhost:9000/metrics || echo "Metrics endpoint not accessible"

.PHONY: rustfs-logs
rustfs-logs:
	@echo "Tailing RustFS logs (pod 0)..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: rustfs-logs-all
rustfs-logs-all:
	@echo "Tailing logs from all RustFS pods..."
	@$(KUBECTL) logs -f -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: rustfs-shell
rustfs-shell:
	@echo "Opening shell in RustFS pod 0..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/sh

.PHONY: rustfs-scale
rustfs-scale:
	@echo "Scaling RustFS StatefulSet to $(REPLICAS) replicas..."
	@if [ -z "$(REPLICAS)" ]; then echo "Error: REPLICAS parameter required"; exit 1; fi
	@$(KUBECTL) scale statefulset $$($(KUBECTL) get statefulset -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}') --replicas=$(REPLICAS)
	@echo "Waiting for pods to be ready..."
	@$(KUBECTL) wait --for=condition=ready pod -l app.kubernetes.io/name=$(CHART_NAME) --timeout=300s

.PHONY: rustfs-status
rustfs-status:
	@echo "=== RustFS StatefulSet Status ==="
	@$(KUBECTL) get statefulset -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "=== RustFS Pods ==="
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "=== RustFS PVCs ==="
	@$(KUBECTL) get pvc -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: rustfs-all
rustfs-all:
	@echo "=== All RustFS Resources ==="
	@echo ""
	@echo "StatefulSet:"
	@$(KUBECTL) get statefulset -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "Pods:"
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "Services:"
	@$(KUBECTL) get svc -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "PVCs:"
	@$(KUBECTL) get pvc -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "Secrets:"
	@$(KUBECTL) get secret -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: rustfs-backup
rustfs-backup:
	@echo "Creating VolumeSnapshot for RustFS data..."
	@echo "WARNING: This requires VolumeSnapshot CRD and CSI driver support"
	@if [ -z "$(SNAPSHOT_CLASS)" ]; then echo "Error: SNAPSHOT_CLASS parameter required"; exit 1; fi
	@cat <<EOF | $(KUBECTL) apply -f -
	apiVersion: snapshot.storage.k8s.io/v1
	kind: VolumeSnapshot
	metadata:
	  name: rustfs-snapshot-$$(date +%Y%m%d-%H%M%S)
	spec:
	  volumeSnapshotClassName: $(SNAPSHOT_CLASS)
	  source:
	    persistentVolumeClaimName: data-rustfs-0
	EOF
	@echo "Snapshot created. List snapshots with: kubectl get volumesnapshot"

.PHONY: rustfs-restart
rustfs-restart:
	@echo "Restarting RustFS StatefulSet..."
	@$(KUBECTL) rollout restart statefulset/$$($(KUBECTL) get statefulset -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}')
	@echo "Waiting for rollout to complete..."
	@$(KUBECTL) rollout status statefulset/$$($(KUBECTL) get statefulset -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}')

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "RustFS specific targets:"
	@echo "  rustfs-get-credentials       - Get RustFS root credentials"
	@echo "  rustfs-port-forward-api      - Port-forward S3 API to localhost:9000"
	@echo "  rustfs-port-forward-console  - Port-forward Console to localhost:9001"
	@echo "  rustfs-test-s3               - Test S3 API with MinIO Client (requires 'mc')"
	@echo ""
	@echo "Health & Monitoring:"
	@echo "  rustfs-health                - Check health endpoints"
	@echo "  rustfs-metrics               - Fetch Prometheus metrics"
	@echo "  rustfs-status                - Show StatefulSet, Pods, and PVCs status"
	@echo "  rustfs-all                   - Show all RustFS resources"
	@echo ""
	@echo "Operations:"
	@echo "  rustfs-scale                 - Scale StatefulSet (requires REPLICAS parameter)"
	@echo "  rustfs-restart               - Restart StatefulSet (rolling update)"
	@echo "  rustfs-backup                - Create VolumeSnapshot (requires SNAPSHOT_CLASS)"
	@echo ""
	@echo "Utilities:"
	@echo "  rustfs-logs                  - Tail logs from pod 0"
	@echo "  rustfs-logs-all              - Tail logs from all pods"
	@echo "  rustfs-shell                 - Open shell in pod 0"
	@echo ""
	@echo "Examples:"
	@echo "  make -f make/ops/rustfs.mk rustfs-get-credentials"
	@echo "  make -f make/ops/rustfs.mk rustfs-scale REPLICAS=4"
	@echo "  make -f make/ops/rustfs.mk rustfs-backup SNAPSHOT_CLASS=csi-hostpath-snapclass"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f make/common.mk help
