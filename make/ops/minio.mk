# MinIO Chart Operational Commands
#
# This Makefile provides day-2 operational commands for MinIO deployments.

include make/common.mk

CHART_NAME := minio
CHART_DIR := charts/$(CHART_NAME)

# Kubernetes resource selectors
APP_LABEL := app.kubernetes.io/name=$(CHART_NAME)
POD_SELECTOR := $(APP_LABEL),app.kubernetes.io/instance=$(RELEASE_NAME)

# Backup directory
BACKUP_DIR := tmp/minio-backups
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# MinIO client alias
MC_ALIAS := minio-primary

# ========================================
# Access & Debugging
# ========================================

## minio-port-forward: Port forward MinIO API and Console to localhost
.PHONY: minio-port-forward
minio-port-forward:
	@echo "Forwarding MinIO API to http://localhost:9000..."
	@echo "Forwarding MinIO Console to http://localhost:9001..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 9000:9000 9001:9001

## minio-port-forward-api: Port forward MinIO API only to localhost:9000
.PHONY: minio-port-forward-api
minio-port-forward-api:
	@echo "Forwarding MinIO API to http://localhost:9000..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 9000:9000

## minio-port-forward-console: Port forward MinIO Console only to localhost:9001
.PHONY: minio-port-forward-console
minio-port-forward-console:
	@echo "Forwarding MinIO Console to http://localhost:9001..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 9001:9001

## minio-get-url: Get MinIO API and Console URLs
.PHONY: minio-get-url
minio-get-url:
	@echo "=== MinIO URLs ==="
	@API_INGRESS=$$(kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME)-api -o jsonpath='{.spec.rules[0].host}' 2>/dev/null); \
	CONSOLE_INGRESS=$$(kubectl get ingress -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME)-console -o jsonpath='{.spec.rules[0].host}' 2>/dev/null); \
	if [ -n "$$API_INGRESS" ]; then \
		echo "API URL: https://$$API_INGRESS"; \
	else \
		echo "API URL: No ingress found. Use 'make -f make/ops/minio.mk minio-port-forward-api'"; \
	fi; \
	if [ -n "$$CONSOLE_INGRESS" ]; then \
		echo "Console URL: https://$$CONSOLE_INGRESS"; \
	else \
		echo "Console URL: No ingress found. Use 'make -f make/ops/minio.mk minio-port-forward-console'"; \
	fi

## minio-logs: View MinIO logs
.PHONY: minio-logs
minio-logs:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl logs -f -n $(NAMESPACE) $$POD --tail=100

## minio-logs-all: View logs from all MinIO pods
.PHONY: minio-logs-all
minio-logs-all:
	@kubectl logs -f -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=50 --max-log-requests=10

## minio-shell: Open shell in MinIO container
.PHONY: minio-shell
minio-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## minio-mc-shell: Open shell with mc (MinIO Client) pre-configured
.PHONY: minio-mc-shell
minio-mc-shell:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	echo "MinIO Client (mc) shell - use 'mc --help' for commands"; \
	kubectl exec -it -n $(NAMESPACE) $$POD -- /bin/sh

## minio-restart: Restart MinIO StatefulSet
.PHONY: minio-restart
minio-restart:
	@echo "Restarting MinIO..."
	@kubectl rollout restart -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME)
	@echo "Waiting for rollout to complete..."
	@kubectl rollout status -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME)

## minio-describe: Describe MinIO pod
.PHONY: minio-describe
minio-describe:
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl describe pod -n $(NAMESPACE) $$POD

## minio-events: Show MinIO pod events
.PHONY: minio-events
minio-events:
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | grep $(CHART_NAME)

## minio-stats: Show resource usage statistics
.PHONY: minio-stats
minio-stats:
	@echo "=== MinIO Resource Usage ==="
	@kubectl top pod -n $(NAMESPACE) -l $(POD_SELECTOR) 2>/dev/null || echo "Metrics server not available"

## minio-cluster-status: Show MinIO cluster status
.PHONY: minio-cluster-status
minio-cluster-status:
	@echo "=== MinIO Cluster Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin info $(MC_ALIAS) 2>/dev/null || \
	echo "Unable to get cluster info. Configure mc alias first: mc alias set $(MC_ALIAS) http://localhost:9000 <access-key> <secret-key>"

# ========================================
# Bucket Operations
# ========================================

## minio-list-buckets: List all buckets
.PHONY: minio-list-buckets
minio-list-buckets:
	@echo "=== MinIO Buckets ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc ls $(MC_ALIAS) 2>/dev/null || \
	echo "Unable to list buckets. Configure mc alias first: mc alias set $(MC_ALIAS) http://localhost:9000 <access-key> <secret-key>"

## minio-bucket-info: Get bucket information (requires BUCKET parameter)
.PHONY: minio-bucket-info
minio-bucket-info:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-bucket-info BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "=== Bucket: $(BUCKET) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc du $(MC_ALIAS)/$(BUCKET) 2>/dev/null || echo "Unable to get bucket info"

## minio-create-bucket: Create a new bucket (requires BUCKET parameter)
.PHONY: minio-create-bucket
minio-create-bucket:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-create-bucket BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "Creating bucket: $(BUCKET)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc mb $(MC_ALIAS)/$(BUCKET)

## minio-delete-bucket: Delete a bucket (requires BUCKET parameter)
.PHONY: minio-delete-bucket
minio-delete-bucket:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-delete-bucket BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "WARNING: This will delete bucket '$(BUCKET)' and all its contents."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		kubectl exec -n $(NAMESPACE) $$POD -- mc rb --force $(MC_ALIAS)/$(BUCKET); \
	else \
		echo "Cancelled"; \
	fi

## minio-bucket-policy: Get bucket policy (requires BUCKET parameter)
.PHONY: minio-bucket-policy
minio-bucket-policy:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-bucket-policy BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "=== Bucket Policy: $(BUCKET) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc policy get $(MC_ALIAS)/$(BUCKET)

## minio-set-bucket-policy: Set bucket policy (requires BUCKET and POLICY parameters)
.PHONY: minio-set-bucket-policy
minio-set-bucket-policy:
	@if [ -z "$(BUCKET)" ] || [ -z "$(POLICY)" ]; then \
		echo "Error: BUCKET and POLICY parameters are required"; \
		echo "Usage: make -f make/ops/minio.mk minio-set-bucket-policy BUCKET=my-bucket POLICY=download"; \
		echo "Policies: none, download, upload, public"; \
		exit 1; \
	fi
	@echo "Setting bucket policy: $(BUCKET) -> $(POLICY)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc policy set $(POLICY) $(MC_ALIAS)/$(BUCKET)

## minio-bucket-versioning: Get bucket versioning status (requires BUCKET parameter)
.PHONY: minio-bucket-versioning
minio-bucket-versioning:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-bucket-versioning BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "=== Bucket Versioning: $(BUCKET) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc version info $(MC_ALIAS)/$(BUCKET)

## minio-enable-versioning: Enable bucket versioning (requires BUCKET parameter)
.PHONY: minio-enable-versioning
minio-enable-versioning:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-enable-versioning BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "Enabling versioning for bucket: $(BUCKET)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc version enable $(MC_ALIAS)/$(BUCKET)

## minio-bucket-lifecycle: Get bucket lifecycle configuration (requires BUCKET parameter)
.PHONY: minio-bucket-lifecycle
minio-bucket-lifecycle:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-bucket-lifecycle BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "=== Bucket Lifecycle: $(BUCKET) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc ilm ls $(MC_ALIAS)/$(BUCKET)

# ========================================
# IAM Management
# ========================================

## minio-list-users: List all IAM users
.PHONY: minio-list-users
minio-list-users:
	@echo "=== MinIO Users ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user list $(MC_ALIAS)

## minio-create-user: Create IAM user (requires USER and PASSWORD parameters)
.PHONY: minio-create-user
minio-create-user:
	@if [ -z "$(USER)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "Error: USER and PASSWORD parameters are required"; \
		echo "Usage: make -f make/ops/minio.mk minio-create-user USER=myuser PASSWORD=mypassword"; \
		exit 1; \
	fi
	@echo "Creating user: $(USER)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user add $(MC_ALIAS) $(USER) $(PASSWORD)

## minio-delete-user: Delete IAM user (requires USER parameter)
.PHONY: minio-delete-user
minio-delete-user:
	@if [ -z "$(USER)" ]; then \
		echo "Error: USER parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-delete-user USER=myuser"; \
		exit 1; \
	fi
	@echo "Deleting user: $(USER)"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user remove $(MC_ALIAS) $(USER)

## minio-list-policies: List all IAM policies
.PHONY: minio-list-policies
minio-list-policies:
	@echo "=== MinIO Policies ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin policy list $(MC_ALIAS)

## minio-user-policy: Get user policy (requires USER parameter)
.PHONY: minio-user-policy
minio-user-policy:
	@if [ -z "$(USER)" ]; then \
		echo "Error: USER parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-user-policy USER=myuser"; \
		exit 1; \
	fi
	@echo "=== User Policy: $(USER) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user info $(MC_ALIAS) $(USER)

## minio-attach-policy: Attach policy to user (requires USER and POLICY parameters)
.PHONY: minio-attach-policy
minio-attach-policy:
	@if [ -z "$(USER)" ] || [ -z "$(POLICY)" ]; then \
		echo "Error: USER and POLICY parameters are required"; \
		echo "Usage: make -f make/ops/minio.mk minio-attach-policy USER=myuser POLICY=readwrite"; \
		echo "Common policies: readonly, readwrite, diagnostics, consoleAdmin"; \
		exit 1; \
	fi
	@echo "Attaching policy '$(POLICY)' to user '$(USER)'"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin policy attach $(MC_ALIAS) $(POLICY) --user $(USER)

## minio-list-service-accounts: List all service accounts
.PHONY: minio-list-service-accounts
minio-list-service-accounts:
	@echo "=== MinIO Service Accounts ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user svcacct ls $(MC_ALIAS)

# ========================================
# Replication Management
# ========================================

## minio-replication-status: Check bucket replication status (requires BUCKET parameter)
.PHONY: minio-replication-status
minio-replication-status:
	@if [ -z "$(BUCKET)" ]; then \
		echo "Error: BUCKET parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-replication-status BUCKET=my-bucket"; \
		exit 1; \
	fi
	@echo "=== Replication Status: $(BUCKET) ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc replicate status $(MC_ALIAS)/$(BUCKET)

## minio-site-replication-status: Check site replication status
.PHONY: minio-site-replication-status
minio-site-replication-status:
	@echo "=== Site Replication Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin replicate status $(MC_ALIAS)

# ========================================
# Monitoring & Health
# ========================================

## minio-health-live: Check MinIO liveness
.PHONY: minio-health-live
minio-health-live:
	@echo "=== MinIO Liveness Check ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9000/minio/health/live

## minio-health-ready: Check MinIO readiness
.PHONY: minio-health-ready
minio-health-ready:
	@echo "=== MinIO Readiness Check ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9000/minio/health/ready

## minio-server-info: Get MinIO server information
.PHONY: minio-server-info
minio-server-info:
	@echo "=== MinIO Server Information ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin info $(MC_ALIAS)

## minio-disk-usage: Check disk usage
.PHONY: minio-disk-usage
minio-disk-usage:
	@echo "=== MinIO Disk Usage ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- df -h /data 2>/dev/null || echo "Unable to check disk usage"

## minio-prometheus-metrics: Get Prometheus metrics
.PHONY: minio-prometheus-metrics
minio-prometheus-metrics:
	@echo "=== MinIO Prometheus Metrics ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- wget -qO- http://localhost:9000/minio/v2/metrics/cluster

## minio-audit-logs: View audit logs
.PHONY: minio-audit-logs
minio-audit-logs:
	@echo "=== MinIO Audit Logs ==="
	@kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=50 | grep -i audit || echo "No audit logs found"

# ========================================
# Storage Maintenance
# ========================================

## minio-storage-class: Check storage class information
.PHONY: minio-storage-class
minio-storage-class:
	@echo "=== MinIO Storage Class ==="
	@kubectl get pvc -n $(NAMESPACE) -l $(APP_LABEL) -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.storageClassName}{"\t"}{.spec.resources.requests.storage}{"\t"}{.status.phase}{"\n"}{end}' | column -t

## minio-pvc-status: Check PVC status
.PHONY: minio-pvc-status
minio-pvc-status:
	@echo "=== MinIO PVC Status ==="
	@kubectl get pvc -n $(NAMESPACE) -l $(APP_LABEL)

## minio-heal: Run MinIO healing (self-healing for erasure coded data)
.PHONY: minio-heal
minio-heal:
	@echo "=== MinIO Healing ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin heal $(MC_ALIAS)

## minio-decommission-status: Check decommissioning status
.PHONY: minio-decommission-status
minio-decommission-status:
	@echo "=== MinIO Decommissioning Status ==="
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin decommission status $(MC_ALIAS)

# ========================================
# Backup & Recovery
# ========================================

## minio-backup-buckets: Backup all buckets using mc mirror
.PHONY: minio-backup-buckets
minio-backup-buckets:
	@echo "=== Backing Up MinIO Buckets ==="
	@mkdir -p $(BACKUP_DIR)/buckets-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	BUCKETS=$$(kubectl exec -n $(NAMESPACE) $$POD -- mc ls $(MC_ALIAS) 2>/dev/null | awk '{print $$NF}' | tr -d '/'); \
	for bucket in $$BUCKETS; do \
		echo "Backing up bucket: $$bucket"; \
		kubectl exec -n $(NAMESPACE) $$POD -- mc mirror $(MC_ALIAS)/$$bucket /tmp/backup/$$bucket; \
		kubectl cp -n $(NAMESPACE) $$POD:/tmp/backup/$$bucket $(BACKUP_DIR)/buckets-$(TIMESTAMP)/$$bucket; \
		kubectl exec -n $(NAMESPACE) $$POD -- rm -rf /tmp/backup/$$bucket; \
	done
	@echo "Buckets backed up to: $(BACKUP_DIR)/buckets-$(TIMESTAMP)/"

## minio-backup-config: Backup MinIO configuration
.PHONY: minio-backup-config
minio-backup-config:
	@echo "=== Backing Up MinIO Configuration ==="
	@mkdir -p $(BACKUP_DIR)/config-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin config export $(MC_ALIAS) > $(BACKUP_DIR)/config-$(TIMESTAMP)/minio-config.json 2>/dev/null || echo "Unable to export config"
	@kubectl get configmap -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $(BACKUP_DIR)/config-$(TIMESTAMP)/configmap.yaml 2>/dev/null || echo "No ConfigMap found"
	@kubectl get secret -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $(BACKUP_DIR)/config-$(TIMESTAMP)/secret.yaml 2>/dev/null || echo "No Secret found"
	@echo "Configuration backed up to: $(BACKUP_DIR)/config-$(TIMESTAMP)/"

## minio-backup-iam: Backup IAM policies and users
.PHONY: minio-backup-iam
minio-backup-iam:
	@echo "=== Backing Up MinIO IAM ==="
	@mkdir -p $(BACKUP_DIR)/iam-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin user list $(MC_ALIAS) > $(BACKUP_DIR)/iam-$(TIMESTAMP)/users.txt 2>/dev/null || echo "Unable to list users"; \
	kubectl exec -n $(NAMESPACE) $$POD -- mc admin policy list $(MC_ALIAS) > $(BACKUP_DIR)/iam-$(TIMESTAMP)/policies.txt 2>/dev/null || echo "Unable to list policies"
	@echo "IAM backed up to: $(BACKUP_DIR)/iam-$(TIMESTAMP)/"

## minio-backup-metadata: Backup bucket metadata (policies, versioning, lifecycle)
.PHONY: minio-backup-metadata
minio-backup-metadata:
	@echo "=== Backing Up Bucket Metadata ==="
	@mkdir -p $(BACKUP_DIR)/metadata-$(TIMESTAMP)
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	BUCKETS=$$(kubectl exec -n $(NAMESPACE) $$POD -- mc ls $(MC_ALIAS) 2>/dev/null | awk '{print $$NF}' | tr -d '/'); \
	for bucket in $$BUCKETS; do \
		echo "Backing up metadata for bucket: $$bucket"; \
		mkdir -p $(BACKUP_DIR)/metadata-$(TIMESTAMP)/$$bucket; \
		kubectl exec -n $(NAMESPACE) $$POD -- mc policy get $(MC_ALIAS)/$$bucket > $(BACKUP_DIR)/metadata-$(TIMESTAMP)/$$bucket/policy.json 2>/dev/null || echo "{}"; \
		kubectl exec -n $(NAMESPACE) $$POD -- mc version info $(MC_ALIAS)/$$bucket > $(BACKUP_DIR)/metadata-$(TIMESTAMP)/$$bucket/versioning.txt 2>/dev/null || echo "Not configured"; \
		kubectl exec -n $(NAMESPACE) $$POD -- mc ilm ls $(MC_ALIAS)/$$bucket > $(BACKUP_DIR)/metadata-$(TIMESTAMP)/$$bucket/lifecycle.txt 2>/dev/null || echo "Not configured"; \
	done
	@echo "Metadata backed up to: $(BACKUP_DIR)/metadata-$(TIMESTAMP)/"

## minio-full-backup: Full backup (buckets, config, IAM, metadata)
.PHONY: minio-full-backup
minio-full-backup:
	@echo "=== Full MinIO Backup ==="
	@make -f make/ops/minio.mk minio-backup-buckets
	@make -f make/ops/minio.mk minio-backup-config
	@make -f make/ops/minio.mk minio-backup-iam
	@make -f make/ops/minio.mk minio-backup-metadata
	@echo "Full backup completed: $(BACKUP_DIR)/*-$(TIMESTAMP)/"

## minio-backup-status: Show all available backups
.PHONY: minio-backup-status
minio-backup-status:
	@echo "=== Available MinIO Backups ==="
	@ls -lht $(BACKUP_DIR)/ 2>/dev/null || echo "No backups found"

## minio-restore-config: Restore configuration from backup (requires FILE parameter)
.PHONY: minio-restore-config
minio-restore-config:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make -f make/ops/minio.mk minio-restore-config FILE=tmp/minio-backups/config-20250109-143022/minio-config.json"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "WARNING: This will replace the current MinIO configuration."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
		cat $(FILE) | kubectl exec -i -n $(NAMESPACE) $$POD -- mc admin config import $(MC_ALIAS); \
		echo "Configuration restored from: $(FILE)"; \
		echo "Restarting MinIO..."; \
		make -f make/ops/minio.mk minio-restart; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Upgrade Support
# ========================================

## minio-pre-upgrade-check: Pre-upgrade validation checklist
.PHONY: minio-pre-upgrade-check
minio-pre-upgrade-check:
	@echo "=== MinIO Pre-Upgrade Checklist ==="
	@echo "1. Current version:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl get statefulset $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "2. Pod health:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "3. Cluster status:"
	@make -f make/ops/minio.mk minio-cluster-status
	@echo ""
	@echo "4. Storage usage:"
	@make -f make/ops/minio.mk minio-disk-usage
	@echo ""
	@echo "5. PVC status:"
	@make -f make/ops/minio.mk minio-pvc-status
	@echo ""
	@echo "6. Distributed mode check:"
	@kubectl get statefulset $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.replicas}'
	@echo " replicas"
	@echo ""
	@echo "✅ Pre-upgrade checks complete. Don't forget to:"
	@echo "   - Backup: make -f make/ops/minio.mk minio-full-backup"
	@echo "   - Review release notes: https://github.com/minio/minio/releases"
	@echo "   - Check upgrade strategy: Rolling (distributed) or In-Place (standalone)"

## minio-post-upgrade-check: Post-upgrade validation
.PHONY: minio-post-upgrade-check
minio-post-upgrade-check:
	@echo "=== MinIO Post-Upgrade Validation ==="
	@echo "1. Pod status:"
	@kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR)
	@echo ""
	@echo "2. New version:"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l $(POD_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	kubectl get statefulset $(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "3. Check for errors in logs:"
	@kubectl logs -n $(NAMESPACE) -l $(POD_SELECTOR) --tail=50 | grep -i error || echo "No errors found"
	@echo ""
	@echo "4. Cluster health:"
	@make -f make/ops/minio.mk minio-health-ready
	@echo ""
	@echo "5. Server info:"
	@make -f make/ops/minio.mk minio-server-info
	@echo ""
	@echo "6. Bucket count:"
	@make -f make/ops/minio.mk minio-list-buckets
	@echo ""
	@echo "7. API access:"
	@make -f make/ops/minio.mk minio-get-url
	@echo ""
	@echo "✅ Post-upgrade checks complete. Manual validation required:"
	@echo "   - Test bucket operations (upload/download)"
	@echo "   - Verify IAM policies"
	@echo "   - Check replication status"
	@echo "   - Verify Console access"

## minio-upgrade-rollback: Rollback to previous Helm revision
.PHONY: minio-upgrade-rollback
minio-upgrade-rollback:
	@echo "=== Rolling Back MinIO Upgrade ==="
	@helm history $(RELEASE_NAME) -n $(NAMESPACE)
	@echo ""
	@read -p "Rollback to previous revision? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm rollback $(RELEASE_NAME) -n $(NAMESPACE); \
		kubectl rollout status -n $(NAMESPACE) statefulset/$(RELEASE_NAME)-$(CHART_NAME); \
		echo "Rollback complete"; \
		make -f make/ops/minio.mk minio-cluster-status; \
	else \
		echo "Cancelled"; \
	fi

# ========================================
# Help
# ========================================

## minio-help: Show all available MinIO commands
.PHONY: minio-help
minio-help:
	@echo "=== MinIO Operational Commands ==="
	@echo ""
	@echo "Access & Debugging:"
	@echo "  minio-port-forward              Port forward API and Console to localhost"
	@echo "  minio-port-forward-api          Port forward API only to localhost:9000"
	@echo "  minio-port-forward-console      Port forward Console only to localhost:9001"
	@echo "  minio-get-url                   Get MinIO API and Console URLs"
	@echo "  minio-logs                      View MinIO logs"
	@echo "  minio-logs-all                  View logs from all MinIO pods"
	@echo "  minio-shell                     Open shell in MinIO container"
	@echo "  minio-mc-shell                  Open shell with mc (MinIO Client)"
	@echo "  minio-restart                   Restart MinIO StatefulSet"
	@echo "  minio-describe                  Describe MinIO pod"
	@echo "  minio-events                    Show pod events"
	@echo "  minio-stats                     Show resource usage statistics"
	@echo "  minio-cluster-status            Show MinIO cluster status"
	@echo ""
	@echo "Bucket Operations:"
	@echo "  minio-list-buckets              List all buckets"
	@echo "  minio-bucket-info BUCKET=name   Get bucket information"
	@echo "  minio-create-bucket BUCKET=name Create a new bucket"
	@echo "  minio-delete-bucket BUCKET=name Delete a bucket"
	@echo "  minio-bucket-policy BUCKET=name Get bucket policy"
	@echo "  minio-set-bucket-policy BUCKET=name POLICY=policy Set bucket policy"
	@echo "  minio-bucket-versioning BUCKET=name Get bucket versioning status"
	@echo "  minio-enable-versioning BUCKET=name Enable bucket versioning"
	@echo "  minio-bucket-lifecycle BUCKET=name Get bucket lifecycle configuration"
	@echo ""
	@echo "IAM Management:"
	@echo "  minio-list-users                List all IAM users"
	@echo "  minio-create-user USER=name PASSWORD=pass Create IAM user"
	@echo "  minio-delete-user USER=name     Delete IAM user"
	@echo "  minio-list-policies             List all IAM policies"
	@echo "  minio-user-policy USER=name     Get user policy"
	@echo "  minio-attach-policy USER=name POLICY=policy Attach policy to user"
	@echo "  minio-list-service-accounts     List all service accounts"
	@echo ""
	@echo "Replication Management:"
	@echo "  minio-replication-status BUCKET=name Check bucket replication status"
	@echo "  minio-site-replication-status   Check site replication status"
	@echo ""
	@echo "Monitoring & Health:"
	@echo "  minio-health-live               Check MinIO liveness"
	@echo "  minio-health-ready              Check MinIO readiness"
	@echo "  minio-server-info               Get MinIO server information"
	@echo "  minio-disk-usage                Check disk usage"
	@echo "  minio-prometheus-metrics        Get Prometheus metrics"
	@echo "  minio-audit-logs                View audit logs"
	@echo ""
	@echo "Storage Maintenance:"
	@echo "  minio-storage-class             Check storage class information"
	@echo "  minio-pvc-status                Check PVC status"
	@echo "  minio-heal                      Run MinIO healing"
	@echo "  minio-decommission-status       Check decommissioning status"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  minio-backup-buckets            Backup all buckets"
	@echo "  minio-backup-config             Backup MinIO configuration"
	@echo "  minio-backup-iam                Backup IAM policies and users"
	@echo "  minio-backup-metadata           Backup bucket metadata"
	@echo "  minio-full-backup               Full backup (all components)"
	@echo "  minio-backup-status             Show all backups"
	@echo "  minio-restore-config FILE=path  Restore configuration"
	@echo ""
	@echo "Upgrade Support:"
	@echo "  minio-pre-upgrade-check         Pre-upgrade validation"
	@echo "  minio-post-upgrade-check        Post-upgrade validation"
	@echo "  minio-upgrade-rollback          Rollback to previous revision"
	@echo ""
	@echo "Usage examples:"
	@echo "  make -f make/ops/minio.mk minio-port-forward"
	@echo "  make -f make/ops/minio.mk minio-create-bucket BUCKET=my-bucket"
	@echo "  make -f make/ops/minio.mk minio-backup-buckets"
	@echo "  make -f make/ops/minio.mk minio-create-user USER=alice PASSWORD=secret123"
