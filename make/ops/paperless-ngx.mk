# Paperless-ngx Chart Operations

include make/common.mk

CHART_NAME := paperless-ngx
CHART_DIR := charts/$(CHART_NAME)

# Default backup directory (override with environment variable)
BACKUP_DIR ?= /tmp/backups/paperless-ngx
BACKUP_TIMESTAMP ?= $(shell date +%Y%m%d_%H%M%S)

.PHONY: help
help:
	@echo "════════════════════════════════════════════════════════════════"
	@echo "  Paperless-ngx Chart Operations"
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "📋 Basic Operations:"
	@echo "  paperless-info            - Pod information"
	@echo "  paperless-describe        - Detailed pod description"
	@echo "  paperless-logs            - View logs"
	@echo "  paperless-logs-follow     - Follow logs in real-time"
	@echo "  paperless-shell           - Open shell in pod"
	@echo "  paperless-port-forward    - Port forward to localhost:8000"
	@echo "  paperless-restart         - Restart deployment"
	@echo "  paperless-events          - Get pod events"
	@echo ""
	@echo "🗄️  Database Operations:"
	@echo "  paperless-check-db        - Database connectivity check"
	@echo "  paperless-db-shell        - PostgreSQL shell (psql)"
	@echo "  paperless-migrate         - Run database migrations"
	@echo "  paperless-db-stats        - Database statistics"
	@echo "  paperless-document-count  - Count documents"
	@echo "  paperless-db-size         - Database size"
	@echo "  paperless-db-vacuum       - Vacuum database"
	@echo ""
	@echo "🔴 Redis Operations:"
	@echo "  paperless-check-redis     - Redis connectivity check"
	@echo "  paperless-redis-cli       - Redis CLI"
	@echo "  paperless-redis-info      - Redis info"
	@echo "  paperless-redis-flushdb   - Clear Redis cache"
	@echo "  paperless-redis-monitor   - Monitor Redis commands"
	@echo ""
	@echo "📄 Document Management:"
	@echo "  paperless-consume-list    - List consume directory"
	@echo "  paperless-process-status  - Document processing status"
	@echo "  paperless-document-exporter - Export all documents"
	@echo "  paperless-reindex         - Rebuild search index"
	@echo "  paperless-create-classifier - Create document classifier"
	@echo "  paperless-ocr-redo        - Re-run OCR on documents"
	@echo ""
	@echo "👤 User Management:"
	@echo "  paperless-create-superuser - Create admin user"
	@echo "  paperless-list-users      - List all users"
	@echo "  paperless-change-password - Change user password"
	@echo "  paperless-create-api-token - Create API token"
	@echo ""
	@echo "💾 Storage Operations:"
	@echo "  paperless-check-storage   - Check storage usage"
	@echo "  paperless-consume-size    - Consume directory size"
	@echo "  paperless-data-size       - Data directory size"
	@echo "  paperless-media-size      - Media directory size"
	@echo "  paperless-export-size     - Export directory size"
	@echo "  paperless-total-storage   - Total storage usage"
	@echo "  paperless-pvc-status      - PVC status"
	@echo ""
	@echo "💾 Backup Operations:"
	@echo "  paperless-full-backup     - Full backup (all components)"
	@echo "  paperless-backup-documents - Backup documents (PVCs)"
	@echo "  paperless-backup-database - Backup PostgreSQL database"
	@echo "  paperless-backup-helm-values - Backup Helm values"
	@echo "  paperless-backup-k8s-resources - Backup K8s resources"
	@echo "  paperless-create-pvc-snapshots - Create PVC snapshots"
	@echo "  paperless-backup-documents-s3 - Backup documents to S3"
	@echo ""
	@echo "♻️  Restore Operations:"
	@echo "  paperless-restore-documents BACKUP_DATE=<date> - Restore documents"
	@echo "  paperless-restore-database BACKUP_DATE=<date> - Restore database"
	@echo "  paperless-restore-helm-values BACKUP_DATE=<date> - Restore Helm values"
	@echo "  paperless-full-recovery BACKUP_DATE=<date> - Full disaster recovery"
	@echo ""
	@echo "🚀 Upgrade Operations:"
	@echo "  paperless-pre-upgrade-check - Pre-upgrade validation"
	@echo "  paperless-check-latest-version - Check latest version"
	@echo "  paperless-upgrade-rolling VERSION=<ver> - Rolling upgrade"
	@echo "  paperless-upgrade-maintenance VERSION=<ver> - Maintenance mode upgrade"
	@echo "  paperless-upgrade-blue-green VERSION=<ver> - Blue-green deployment"
	@echo "  paperless-post-upgrade-check - Post-upgrade validation"
	@echo "  paperless-upgrade-rollback - Rollback upgrade"
	@echo ""
	@echo "🔍 Monitoring & Troubleshooting:"
	@echo "  paperless-health-check    - Health checks"
	@echo "  paperless-top             - Resource usage"
	@echo "  paperless-test-connectivity - Network connectivity tests"
	@echo "  paperless-test-ocr        - OCR test"
	@echo "  paperless-check-settings  - Application settings"
	@echo "  paperless-django-check    - Django system check"
	@echo ""
	@echo "🧹 Cleanup Operations:"
	@echo "  paperless-cleanup-consume - Clean old consume files"
	@echo "  paperless-cleanup-export  - Clean export directory"
	@echo "  paperless-cleanup-thumbnails - Clean thumbnails"
	@echo "  paperless-db-cleanup      - Database cleanup"
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Common targets:"
	@$(MAKE) -s -f make/common.mk help

# ════════════════════════════════════════════════════════════════
# 📋 Basic Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-info
paperless-info:
	@echo "📋 Paperless-ngx Pod Information:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o wide

.PHONY: paperless-describe
paperless-describe:
	@echo "📋 Paperless-ngx Pod Description:"
	@$(KUBECTL) describe pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: paperless-logs
paperless-logs:
	@echo "📋 Viewing Paperless-ngx logs..."
	@$(KUBECTL) logs deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) --tail=100

.PHONY: paperless-logs-follow
paperless-logs-follow:
	@echo "📋 Following Paperless-ngx logs (Ctrl+C to exit)..."
	@$(KUBECTL) logs -f deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

.PHONY: paperless-shell
paperless-shell:
	@echo "📋 Opening shell in Paperless-ngx pod..."
	@$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- /bin/bash

.PHONY: paperless-port-forward
paperless-port-forward:
	@echo "📋 Port forwarding to localhost:8000..."
	@echo "   Visit http://localhost:8000"
	@echo "   Press Ctrl+C to stop"
	@$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-$(CHART_NAME) 8000:8000

.PHONY: paperless-restart
paperless-restart:
	@echo "📋 Restarting Paperless-ngx deployment..."
	@$(KUBECTL) rollout restart deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)
	@$(KUBECTL) rollout status deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)

.PHONY: paperless-events
paperless-events:
	@echo "📋 Paperless-ngx Pod Events:"
	@$(KUBECTL) get events -n $(NAMESPACE) --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | grep $(CHART_NAME)

# ════════════════════════════════════════════════════════════════
# 🗄️  Database Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-check-db
paperless-check-db:
	@echo "🗄️  Testing PostgreSQL connection..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "SELECT version();"'

.PHONY: paperless-db-shell
paperless-db-shell:
	@echo "🗄️  Opening PostgreSQL shell..."
	@$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME'

.PHONY: paperless-migrate
paperless-migrate:
	@echo "🗄️  Running database migrations..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py migrate --noinput

.PHONY: paperless-db-stats
paperless-db-stats:
	@echo "🗄️  Database Statistics:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "SELECT schemaname, tablename, n_live_tup, n_dead_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;"'

.PHONY: paperless-document-count
paperless-document-count:
	@echo "🗄️  Document Count:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -t -c "SELECT COUNT(*) FROM documents_document;"'

.PHONY: paperless-db-size
paperless-db-size:
	@echo "🗄️  Database Size:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "SELECT pg_size_pretty(pg_database_size(current_database()));"'

.PHONY: paperless-db-vacuum
paperless-db-vacuum:
	@echo "🗄️  Vacuuming database (this may take a while)..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "VACUUM ANALYZE;"'

# ════════════════════════════════════════════════════════════════
# 🔴 Redis Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-check-redis
paperless-check-redis:
	@echo "🔴 Testing Redis connection..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'redis-cli -h $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f1) \
		-p $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f2) \
		-a $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f1 | cut -d: -f2) PING'

.PHONY: paperless-redis-cli
paperless-redis-cli:
	@echo "🔴 Opening Redis CLI..."
	@$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'redis-cli -h $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f1) \
		-p $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f2) \
		-a $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f1 | cut -d: -f2)'

.PHONY: paperless-redis-info
paperless-redis-info:
	@echo "🔴 Redis Info:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'redis-cli -h $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f1) \
		-p $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f2) \
		-a $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f1 | cut -d: -f2) INFO server'

.PHONY: paperless-redis-flushdb
paperless-redis-flushdb:
	@echo "🔴 WARNING: This will clear all Redis cache data!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'redis-cli -h $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f1) \
		-p $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f2) \
		-a $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f1 | cut -d: -f2) FLUSHDB'
	@echo "✓ Redis cache cleared"

.PHONY: paperless-redis-monitor
paperless-redis-monitor:
	@echo "🔴 Monitoring Redis commands (Ctrl+C to exit)..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'redis-cli -h $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f1) \
		-p $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f2 | cut -d/ -f1 | cut -d: -f2) \
		-a $$(echo $$PAPERLESS_REDIS | sed "s|redis://||" | cut -d@ -f1 | cut -d: -f2) MONITOR'

# ════════════════════════════════════════════════════════════════
# 📄 Document Management
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-consume-list
paperless-consume-list:
	@echo "📄 Files in consume directory:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		ls -lh /usr/src/paperless/consume/

.PHONY: paperless-process-status
paperless-process-status:
	@echo "📄 Document processing status:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_sanity_checker

.PHONY: paperless-document-exporter
paperless-document-exporter:
	@echo "📄 Exporting all documents to /usr/src/paperless/export/..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_exporter /usr/src/paperless/export/

.PHONY: paperless-reindex
paperless-reindex:
	@echo "📄 Rebuilding search index (this may take a while)..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_index reindex

.PHONY: paperless-create-classifier
paperless-create-classifier:
	@echo "📄 Creating document classifier..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_create_classifier

.PHONY: paperless-ocr-redo
paperless-ocr-redo:
	@echo "📄 Re-running OCR on all documents (this may take a very long time)..."
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_ocr_redo

# ════════════════════════════════════════════════════════════════
# 👤 User Management
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-create-superuser
paperless-create-superuser:
	@echo "👤 Creating superuser (interactive)..."
	@$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py createsuperuser

.PHONY: paperless-list-users
paperless-list-users:
	@echo "👤 Users:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "SELECT id, username, email, is_superuser, is_active, date_joined FROM auth_user;"'

.PHONY: paperless-change-password
paperless-change-password:
	@echo "👤 Change user password (interactive)..."
	@echo "   Enter username:"
	@read username; \
	$(KUBECTL) exec -it deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py changepassword $$username

.PHONY: paperless-create-api-token
paperless-create-api-token:
	@echo "👤 Create API token (interactive)..."
	@echo "   Enter username:"
	@read username; \
	$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py manage_superuser --create-token $$username

# ════════════════════════════════════════════════════════════════
# 💾 Storage Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-check-storage
paperless-check-storage:
	@echo "💾 Storage usage:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		df -h | grep -E "Filesystem|/usr/src/paperless"

.PHONY: paperless-consume-size
paperless-consume-size:
	@echo "💾 Consume directory size:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		du -sh /usr/src/paperless/consume/

.PHONY: paperless-data-size
paperless-data-size:
	@echo "💾 Data directory size:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		du -sh /usr/src/paperless/data/

.PHONY: paperless-media-size
paperless-media-size:
	@echo "💾 Media directory size:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		du -sh /usr/src/paperless/media/

.PHONY: paperless-export-size
paperless-export-size:
	@echo "💾 Export directory size:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		du -sh /usr/src/paperless/export/

.PHONY: paperless-total-storage
paperless-total-storage:
	@echo "💾 Total storage usage by directory:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		du -sh /usr/src/paperless/*/

.PHONY: paperless-pvc-status
paperless-pvc-status:
	@echo "💾 PVC Status:"
	@$(KUBECTL) get pvc -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME)

# ════════════════════════════════════════════════════════════════
# 💾 Backup Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-full-backup
paperless-full-backup:
	@echo "💾 Starting full backup..."
	@echo "   Backup directory: $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)"
	@mkdir -p $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)
	@$(MAKE) -s paperless-backup-documents
	@$(MAKE) -s paperless-backup-database
	@$(MAKE) -s paperless-backup-helm-values
	@$(MAKE) -s paperless-backup-k8s-resources
	@echo "✓ Full backup completed: $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)"

.PHONY: paperless-backup-documents
paperless-backup-documents:
	@echo "💾 Backing up documents (PVCs)..."
	@mkdir -p $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)
	@echo "   Backing up consume directory..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		tar czf - /usr/src/paperless/consume > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/consume.tar.gz
	@echo "   Backing up data directory..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		tar czf - /usr/src/paperless/data > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/data.tar.gz
	@echo "   Backing up media directory..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		tar czf - /usr/src/paperless/media > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/media.tar.gz
	@echo "   Backing up export directory..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		tar czf - /usr/src/paperless/export > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/export.tar.gz
	@echo "✓ Documents backed up to $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/"

.PHONY: paperless-backup-database
paperless-backup-database:
	@echo "💾 Backing up PostgreSQL database..."
	@mkdir -p $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS pg_dump -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME --format=custom --compress=9' \
		> $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/paperless-db.dump
	@echo "✓ Database backed up to $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/paperless-db.dump"

.PHONY: paperless-backup-helm-values
paperless-backup-helm-values:
	@echo "💾 Backing up Helm values..."
	@mkdir -p $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)
	@helm get values -n $(NAMESPACE) $(RELEASE_NAME) > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/helm-values.yaml
	@echo "✓ Helm values backed up to $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/helm-values.yaml"

.PHONY: paperless-backup-k8s-resources
paperless-backup-k8s-resources:
	@echo "💾 Backing up Kubernetes resources..."
	@mkdir -p $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)
	@$(KUBECTL) get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/deployment.yaml
	@$(KUBECTL) get service -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o yaml > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/service.yaml
	@$(KUBECTL) get configmap -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/configmaps.yaml
	@$(KUBECTL) get secret -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/secrets.yaml
	@$(KUBECTL) get pvc -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME) -o yaml > $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/pvcs.yaml
	@echo "✓ Kubernetes resources backed up to $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/"

.PHONY: paperless-create-pvc-snapshots
paperless-create-pvc-snapshots:
	@echo "💾 Creating PVC snapshots..."
	@echo "   Creating snapshot for consume PVC..."
	@cat <<EOF | $(KUBECTL) apply -f - \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $(RELEASE_NAME)-consume-snapshot-$(BACKUP_TIMESTAMP); \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(RELEASE_NAME)-consume; \
	EOF
	@echo "   Creating snapshot for data PVC..."
	@cat <<EOF | $(KUBECTL) apply -f - \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $(RELEASE_NAME)-data-snapshot-$(BACKUP_TIMESTAMP); \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(RELEASE_NAME)-data; \
	EOF
	@echo "   Creating snapshot for media PVC..."
	@cat <<EOF | $(KUBECTL) apply -f - \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $(RELEASE_NAME)-media-snapshot-$(BACKUP_TIMESTAMP); \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(RELEASE_NAME)-media; \
	EOF
	@echo "   Creating snapshot for export PVC..."
	@cat <<EOF | $(KUBECTL) apply -f - \
	apiVersion: snapshot.storage.k8s.io/v1; \
	kind: VolumeSnapshot; \
	metadata:; \
	  name: $(RELEASE_NAME)-export-snapshot-$(BACKUP_TIMESTAMP); \
	  namespace: $(NAMESPACE); \
	spec:; \
	  volumeSnapshotClassName: csi-snapclass; \
	  source:; \
	    persistentVolumeClaimName: $(RELEASE_NAME)-export; \
	EOF
	@echo "✓ PVC snapshots created. Verify with: kubectl get volumesnapshot -n $(NAMESPACE)"

.PHONY: paperless-backup-documents-s3
paperless-backup-documents-s3:
	@echo "💾 Backing up documents to S3..."
	@echo "   Note: Requires AWS CLI or MinIO client (mc) configured"
	@echo "   Uploading consume.tar.gz..."
	@aws s3 cp $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/consume.tar.gz s3://backups/paperless-ngx/$(BACKUP_TIMESTAMP)/
	@echo "   Uploading data.tar.gz..."
	@aws s3 cp $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/data.tar.gz s3://backups/paperless-ngx/$(BACKUP_TIMESTAMP)/
	@echo "   Uploading media.tar.gz..."
	@aws s3 cp $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/media.tar.gz s3://backups/paperless-ngx/$(BACKUP_TIMESTAMP)/
	@echo "   Uploading export.tar.gz..."
	@aws s3 cp $(BACKUP_DIR)/$(BACKUP_TIMESTAMP)/export.tar.gz s3://backups/paperless-ngx/$(BACKUP_TIMESTAMP)/
	@echo "✓ Documents backed up to S3"

# ════════════════════════════════════════════════════════════════
# ♻️  Restore Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-restore-documents
paperless-restore-documents:
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "❌ Error: BACKUP_DATE not specified"; \
		echo "   Usage: make paperless-restore-documents BACKUP_DATE=20241208_100000"; \
		exit 1; \
	fi
	@echo "♻️  Restoring documents from backup: $(BACKUP_DATE)"
	@echo "   ⚠️  WARNING: This will replace current documents!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@echo "   Restoring consume directory..."
	@cat $(BACKUP_DIR)/$(BACKUP_DATE)/consume.tar.gz | \
		$(KUBECTL) exec -i deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tar xzf - -C /
	@echo "   Restoring data directory..."
	@cat $(BACKUP_DIR)/$(BACKUP_DATE)/data.tar.gz | \
		$(KUBECTL) exec -i deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tar xzf - -C /
	@echo "   Restoring media directory..."
	@cat $(BACKUP_DIR)/$(BACKUP_DATE)/media.tar.gz | \
		$(KUBECTL) exec -i deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tar xzf - -C /
	@echo "   Restoring export directory..."
	@cat $(BACKUP_DIR)/$(BACKUP_DATE)/export.tar.gz | \
		$(KUBECTL) exec -i deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tar xzf - -C /
	@echo "   Fixing permissions..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- chown -R 1000:1000 /usr/src/paperless
	@echo "✓ Documents restored. Restarting pod..."
	@$(MAKE) -s paperless-restart

.PHONY: paperless-restore-database
paperless-restore-database:
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "❌ Error: BACKUP_DATE not specified"; \
		echo "   Usage: make paperless-restore-database BACKUP_DATE=20241208_100000"; \
		exit 1; \
	fi
	@echo "♻️  Restoring database from backup: $(BACKUP_DATE)"
	@echo "   ⚠️  WARNING: This will replace current database!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@echo "   Scaling down Paperless-ngx..."
	@$(KUBECTL) scale deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) --replicas=0
	@echo "   Restoring database..."
	@cat $(BACKUP_DIR)/$(BACKUP_DATE)/paperless-db.dump | \
		$(KUBECTL) exec -i deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS pg_restore -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME --clean --if-exists --no-owner --no-privileges'
	@echo "   Scaling up Paperless-ngx..."
	@$(KUBECTL) scale deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) --replicas=1
	@$(KUBECTL) wait pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --for=condition=Ready --timeout=300s
	@echo "✓ Database restored"

.PHONY: paperless-restore-helm-values
paperless-restore-helm-values:
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "❌ Error: BACKUP_DATE not specified"; \
		echo "   Usage: make paperless-restore-helm-values BACKUP_DATE=20241208_100000"; \
		exit 1; \
	fi
	@echo "♻️  Restoring Helm values from backup: $(BACKUP_DATE)"
	@helm upgrade --install $(RELEASE_NAME) ./charts/$(CHART_NAME) \
		-n $(NAMESPACE) \
		-f $(BACKUP_DIR)/$(BACKUP_DATE)/helm-values.yaml
	@echo "✓ Helm values restored"

.PHONY: paperless-full-recovery
paperless-full-recovery:
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "❌ Error: BACKUP_DATE not specified"; \
		echo "   Usage: make paperless-full-recovery BACKUP_DATE=20241208_100000"; \
		exit 1; \
	fi
	@echo "♻️  Full disaster recovery from backup: $(BACKUP_DATE)"
	@echo "   This will restore: documents, database, and Helm configuration"
	@echo "   ⚠️  WARNING: This is a destructive operation!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@$(MAKE) -s paperless-restore-helm-values BACKUP_DATE=$(BACKUP_DATE)
	@$(MAKE) -s paperless-restore-database BACKUP_DATE=$(BACKUP_DATE)
	@$(MAKE) -s paperless-restore-documents BACKUP_DATE=$(BACKUP_DATE)
	@echo "✓ Full recovery completed"

# ════════════════════════════════════════════════════════════════
# 🚀 Upgrade Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-pre-upgrade-check
paperless-pre-upgrade-check:
	@echo "🚀 Pre-upgrade validation..."
	@echo ""
	@echo "📋 Pod Status:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "💾 PVC Status:"
	@$(KUBECTL) get pvc -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME)
	@echo ""
	@echo "🗄️  Database Connectivity:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'PGPASSWORD=$$PAPERLESS_DBPASS psql -h $$PAPERLESS_DBHOST -p $$PAPERLESS_DBPORT -U $$PAPERLESS_DBUSER -d $$PAPERLESS_DBNAME -c "SELECT version();"' || echo "❌ Database check failed"
	@echo ""
	@echo "🔴 Redis Connectivity:"
	@$(MAKE) -s paperless-check-redis || echo "❌ Redis check failed"
	@echo ""
	@echo "📄 Document Count:"
	@$(MAKE) -s paperless-document-count
	@echo ""
	@echo "✓ Pre-upgrade check completed"

.PHONY: paperless-check-latest-version
paperless-check-latest-version:
	@echo "🚀 Checking for latest version..."
	@echo "Current version:"
	@$(KUBECTL) get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo "Latest chart version:"
	@helm search repo scripton-charts/$(CHART_NAME) --versions | head -5

.PHONY: paperless-upgrade-rolling
paperless-upgrade-rolling:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ Error: VERSION not specified"; \
		echo "   Usage: make paperless-upgrade-rolling VERSION=2.15.0"; \
		exit 1; \
	fi
	@echo "🚀 Rolling upgrade to version $(VERSION)..."
	@echo "   Step 1: Full backup"
	@$(MAKE) -s paperless-full-backup
	@echo "   Step 2: Updating chart repository"
	@helm repo update scripton-charts
	@echo "   Step 3: Performing rolling upgrade"
	@helm upgrade $(RELEASE_NAME) scripton-charts/$(CHART_NAME) \
		-n $(NAMESPACE) \
		--set image.tag=$(VERSION) \
		--reuse-values \
		--wait --timeout 10m
	@echo "   Step 4: Verifying upgrade"
	@$(KUBECTL) rollout status deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)
	@echo "✓ Rolling upgrade completed to version $(VERSION)"

.PHONY: paperless-upgrade-maintenance
paperless-upgrade-maintenance:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ Error: VERSION not specified"; \
		echo "   Usage: make paperless-upgrade-maintenance VERSION=3.0.0"; \
		exit 1; \
	fi
	@echo "🚀 Maintenance mode upgrade to version $(VERSION)..."
	@echo "   Step 1: Full backup"
	@$(MAKE) -s paperless-full-backup
	@echo "   Step 2: Scaling down to 0 (enter maintenance mode)"
	@$(KUBECTL) scale deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) --replicas=0
	@echo "   Step 3: Final database backup (while app is down)"
	@$(MAKE) -s paperless-backup-database
	@echo "   Step 4: Performing upgrade"
	@helm upgrade $(RELEASE_NAME) scripton-charts/$(CHART_NAME) \
		-n $(NAMESPACE) \
		--set image.tag=$(VERSION) \
		--reuse-values \
		--wait --timeout 15m
	@echo "   Step 5: Waiting for pod to be ready"
	@$(KUBECTL) wait pod -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) --for=condition=Ready --timeout=900s
	@echo "✓ Maintenance mode upgrade completed to version $(VERSION)"

.PHONY: paperless-upgrade-blue-green
paperless-upgrade-blue-green:
	@echo "🚀 Blue-green deployment upgrade..."
	@echo "   This is a complex multi-step procedure."
	@echo "   See upgrade guide for detailed instructions:"
	@echo "   docs/paperless-ngx-upgrade-guide.md#blue-green-deployment"

.PHONY: paperless-post-upgrade-check
paperless-post-upgrade-check:
	@echo "🚀 Post-upgrade validation..."
	@echo ""
	@echo "📋 Pod Status:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "🔍 Image Version:"
	@$(KUBECTL) get deployment -n $(NAMESPACE) $(RELEASE_NAME)-$(CHART_NAME) -o jsonpath='{.spec.template.spec.containers[0].image}'
	@echo ""
	@echo ""
	@echo "📝 Recent Logs (check for errors):"
	@$(KUBECTL) logs deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) --tail=50
	@echo ""
	@echo "🗄️  Database Connectivity:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- python manage.py check
	@echo ""
	@echo "📄 Document Count:"
	@$(MAKE) -s paperless-document-count
	@echo ""
	@echo "✓ Post-upgrade check completed"

.PHONY: paperless-upgrade-rollback
paperless-upgrade-rollback:
	@echo "🚀 Rolling back Helm release..."
	@helm rollback -n $(NAMESPACE) $(RELEASE_NAME)
	@echo "   Waiting for rollout to complete..."
	@$(KUBECTL) rollout status deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE)
	@echo "✓ Rollback completed"

# ════════════════════════════════════════════════════════════════
# 🔍 Monitoring & Troubleshooting
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-health-check
paperless-health-check:
	@echo "🔍 Health checks..."
	@echo ""
	@echo "📋 Pod Health:"
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "🗄️  Database:"
	@$(MAKE) -s paperless-check-db || echo "❌ Database check failed"
	@echo ""
	@echo "🔴 Redis:"
	@$(MAKE) -s paperless-check-redis || echo "❌ Redis check failed"
	@echo ""
	@echo "💾 Storage:"
	@$(MAKE) -s paperless-check-storage
	@echo ""
	@echo "✓ Health check completed"

.PHONY: paperless-top
paperless-top:
	@echo "🔍 Resource usage:"
	@$(KUBECTL) top pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

.PHONY: paperless-test-connectivity
paperless-test-connectivity:
	@echo "🔍 Network connectivity tests..."
	@echo ""
	@echo "Database connectivity:"
	@$(MAKE) -s paperless-check-db
	@echo ""
	@echo "Redis connectivity:"
	@$(MAKE) -s paperless-check-redis
	@echo ""
	@echo "External connectivity (DNS):"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- nslookup google.com

.PHONY: paperless-test-ocr
paperless-test-ocr:
	@echo "🔍 OCR test..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tesseract --version
	@echo ""
	@echo "Available OCR languages:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- tesseract --list-langs

.PHONY: paperless-check-settings
paperless-check-settings:
	@echo "🔍 Application settings:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- env | grep PAPERLESS_

.PHONY: paperless-django-check
paperless-django-check:
	@echo "🔍 Django system check:"
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- python manage.py check

# ════════════════════════════════════════════════════════════════
# 🧹 Cleanup Operations
# ════════════════════════════════════════════════════════════════

.PHONY: paperless-cleanup-consume
paperless-cleanup-consume:
	@echo "🧹 Cleaning old files from consume directory..."
	@echo "   ⚠️  WARNING: This will delete all files in consume directory!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		sh -c 'find /usr/src/paperless/consume -type f -mtime +7 -delete'
	@echo "✓ Consume directory cleaned"

.PHONY: paperless-cleanup-export
paperless-cleanup-export:
	@echo "🧹 Cleaning export directory..."
	@echo "   ⚠️  WARNING: This will delete all files in export directory!"
	@echo "   Press Ctrl+C to cancel, or Enter to continue..."
	@read dummy
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		rm -rf /usr/src/paperless/export/*
	@echo "✓ Export directory cleaned"

.PHONY: paperless-cleanup-thumbnails
paperless-cleanup-thumbnails:
	@echo "🧹 Cleaning thumbnails (will be regenerated)..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		rm -rf /usr/src/paperless/media/documents/thumbnails/*
	@echo "✓ Thumbnails cleaned"

.PHONY: paperless-db-cleanup
paperless-db-cleanup:
	@echo "🧹 Database cleanup (removing orphaned records)..."
	@echo "   This may take a while..."
	@$(KUBECTL) exec deployment/$(RELEASE_NAME)-$(CHART_NAME) -n $(NAMESPACE) -- \
		python manage.py document_sanity_checker --fix
	@echo "✓ Database cleanup completed"

# ════════════════════════════════════════════════════════════════
# Chart basic operations
# ════════════════════════════════════════════════════════════════

.PHONY: lint
lint:
	@$(MAKE) -s -f make/common.mk lint

.PHONY: build
build:
	@$(MAKE) -s -f make/common.mk build

.PHONY: template
template:
	@$(MAKE) -s -f make/common.mk template

.PHONY: install
install:
	@$(MAKE) -s -f make/common.mk install

.PHONY: upgrade
upgrade:
	@$(MAKE) -s -f make/common.mk upgrade

.PHONY: uninstall
uninstall:
	@$(MAKE) -s -f make/common.mk uninstall
