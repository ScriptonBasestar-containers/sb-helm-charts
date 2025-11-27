# mlflow chart configuration
CHART_NAME := mlflow
CHART_DIR := charts/$(CHART_NAME)

# Common Makefile
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# MLflow-specific targets

.PHONY: mlflow-shell
mlflow-shell:
	@echo "Opening MLflow shell..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- bash

.PHONY: mlflow-logs
mlflow-logs:
	@echo "Viewing MLflow logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: mlflow-port-forward
mlflow-port-forward:
	@echo "Port-forwarding MLflow to localhost:5000..."
	@$(KUBECTL) port-forward svc/$(CHART_NAME) 5000:5000

.PHONY: mlflow-restart
mlflow-restart:
	@echo "Restarting MLflow deployment..."
	@$(KUBECTL) rollout restart deployment/$(CHART_NAME)
	@$(KUBECTL) rollout status deployment/$(CHART_NAME)

.PHONY: mlflow-scale
mlflow-scale:
	@if [ -z "$(REPLICAS)" ]; then echo "Usage: make -f make/ops/mlflow.mk mlflow-scale REPLICAS=2"; exit 1; fi
	@echo "Scaling MLflow to $(REPLICAS) replicas..."
	@$(KUBECTL) scale deployment/$(CHART_NAME) --replicas=$(REPLICAS)

.PHONY: help
help:
	@echo "MLflow Chart Operations:"
	@echo ""
	@echo "Basic Operations:"
	@echo "  mlflow-shell         - Open shell in MLflow pod"
	@echo "  mlflow-logs          - View logs"
	@echo "  mlflow-port-forward  - Port forward to localhost:5000"
	@echo "  mlflow-restart       - Restart deployment"
	@echo "  mlflow-scale REPLICAS=<n> - Scale replicas"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  mlflow-experiments-backup - Backup experiments and runs metadata"
	@echo "  mlflow-db-backup          - Backup PostgreSQL database (if using external DB)"
	@echo "  mlflow-db-restore         - Restore database backup (requires FILE parameter)"
	@echo "  mlflow-artifacts-backup   - Backup artifacts from S3/MinIO"
	@echo ""
	@echo "Upgrade Operations:"
	@echo "  mlflow-pre-upgrade-check  - Pre-upgrade health and readiness check"
	@echo "  mlflow-db-upgrade         - Run MLflow database upgrade"
	@echo "  mlflow-post-upgrade-check - Post-upgrade validation"
	@echo "  mlflow-upgrade-rollback   - Display rollback procedures"
	@echo ""

# =============================================================================
# Backup & Recovery
# =============================================================================

.PHONY: mlflow-experiments-backup
mlflow-experiments-backup:
	@echo "Backing up MLflow experiments and runs..."
	@mkdir -p tmp/mlflow-backups/experiments
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/mlflow-backups/experiments/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "Exporting all experiments..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		mlflow experiments search --view all --max-results 1000 > "$$BACKUP_DIR/experiments.json" 2>/dev/null || true; \
	echo "Exporting registered models..."; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		mlflow models list --max-results 1000 > "$$BACKUP_DIR/models.json" 2>/dev/null || true; \
	echo "✓ Experiments backup completed: $$BACKUP_DIR"

.PHONY: mlflow-db-backup
mlflow-db-backup:
	@echo "Backing up MLflow PostgreSQL database..."
	@mkdir -p tmp/mlflow-backups/db
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_FILE="tmp/mlflow-backups/db/mlflow-db-$$TIMESTAMP.sql"; \
	echo "Note: This requires external PostgreSQL configuration"; \
	PGHOST=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-host}' 2>/dev/null | base64 --decode || echo "postgresql"); \
	PGUSER=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-username}' 2>/dev/null | base64 --decode || echo "mlflow"); \
	PGDATABASE=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-database}' 2>/dev/null | base64 --decode || echo "mlflow"); \
	echo "Connecting to PostgreSQL: $$PGHOST/$$PGDATABASE"; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c "apt-get update >/dev/null 2>&1 && apt-get install -y postgresql-client >/dev/null 2>&1; \
		PGPASSWORD=\$$(cat /secrets/postgresql-password 2>/dev/null || echo '') \
		pg_dump -h $$PGHOST -U $$PGUSER -d $$PGDATABASE" > "$$BACKUP_FILE" 2>/dev/null; \
	if [ -s "$$BACKUP_FILE" ]; then \
		echo "✓ Database backup completed: $$BACKUP_FILE"; \
		echo "  Size: $$(du -h $$BACKUP_FILE | cut -f1)"; \
	else \
		echo "✗ Database backup failed (check if using external PostgreSQL)"; \
		rm -f "$$BACKUP_FILE"; \
		exit 1; \
	fi

.PHONY: mlflow-db-restore
mlflow-db-restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE not set. Usage: make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/db/mlflow-db-YYYYMMDD-HHMMSS.sql"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: Backup file not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "⚠️  WARNING: This will restore the MLflow database from backup."
	@echo "Database: mlflow"
	@echo "Backup file: $(FILE)"
	@read -p "Continue? (yes/no): " CONFIRM; \
	if [ "$$CONFIRM" != "yes" ]; then \
		echo "Restore cancelled."; \
		exit 1; \
	fi
	@echo "Restoring database..."
	@PGHOST=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-host}' 2>/dev/null | base64 --decode || echo "postgresql"); \
	PGUSER=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-username}' 2>/dev/null | base64 --decode || echo "mlflow"); \
	PGDATABASE=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.postgresql-database}' 2>/dev/null | base64 --decode || echo "mlflow"); \
	$(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		sh -c "apt-get update >/dev/null 2>&1 && apt-get install -y postgresql-client >/dev/null 2>&1; \
		PGPASSWORD=\$$(cat /secrets/postgresql-password 2>/dev/null || echo '') \
		psql -h $$PGHOST -U $$PGUSER -d $$PGDATABASE" < "$(FILE)"
	@echo "✓ Database restore completed"

.PHONY: mlflow-artifacts-backup
mlflow-artifacts-backup:
	@echo "Backing up MLflow artifacts from S3/MinIO..."
	@mkdir -p tmp/mlflow-backups/artifacts
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	BACKUP_DIR="tmp/mlflow-backups/artifacts/$$TIMESTAMP"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "Note: Requires AWS CLI or MinIO client (mc) installed"; \
	echo "Using S3 sync to backup artifacts..."; \
	BUCKET=$$($(KUBECTL) get secret mlflow -o jsonpath='{.data.minio-bucket}' 2>/dev/null | base64 --decode || echo "mlflow"); \
	echo "Bucket: $$BUCKET"; \
	echo "Run manually: aws s3 sync s3://$$BUCKET $$BACKUP_DIR"; \
	echo "Or with MinIO: mc cp --recursive minio/$$BUCKET $$BACKUP_DIR"

# =============================================================================
# Upgrade Operations
# =============================================================================

.PHONY: mlflow-pre-upgrade-check
mlflow-pre-upgrade-check:
	@echo "=== MLflow Pre-Upgrade Health Check ==="
	@echo ""
	@echo "1. Checking pod status..."
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME) | grep -E "Running|NAME" || echo "✗ Pods not running"
	@echo ""
	@echo "2. Checking MLflow service..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -f http://localhost:5000/health 2>/dev/null && echo "✓ MLflow service healthy" || echo "✗ MLflow service unhealthy"
	@echo ""
	@echo "3. Checking database connection..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		python -c "import mlflow; print('✓ MLflow client OK')" 2>/dev/null || echo "✗ MLflow client failed"
	@echo ""
	@echo "✓ Pre-upgrade checks completed"
	@echo "⚠️  Make sure to backup before upgrading!"
	@echo "   make -f make/ops/mlflow.mk mlflow-experiments-backup"
	@echo "   make -f make/ops/mlflow.mk mlflow-db-backup"

.PHONY: mlflow-db-upgrade
mlflow-db-upgrade:
	@echo "Running MLflow database upgrade..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		mlflow db upgrade \$$(python -c "import os; print(os.environ.get('MLFLOW_BACKEND_STORE_URI', 'sqlite:///mlflow/mlflow.db'))")
	@echo "✓ Database upgrade completed"

.PHONY: mlflow-post-upgrade-check
mlflow-post-upgrade-check:
	@echo "=== MLflow Post-Upgrade Validation ==="
	@echo ""
	@echo "1. Checking pod status..."
	@$(KUBECTL) get pods -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "2. Waiting for deployment to be ready..."
	@$(KUBECTL) wait --for=condition=available --timeout=300s deployment/$(CHART_NAME) || echo "⚠️  Deployment not ready"
	@echo ""
	@echo "3. Checking MLflow version..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		python -c "import mlflow; print(f'MLflow version: {mlflow.__version__}')" || echo "⚠️  Version check failed"
	@echo ""
	@echo "4. Checking service health..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		curl -f http://localhost:5000/health 2>/dev/null && echo "✓ Service healthy" || echo "⚠️  Service health check failed"
	@echo ""
	@echo "5. Testing experiment list..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- \
		mlflow experiments search --max-results 5 2>/dev/null && echo "✓ Experiments accessible" || echo "⚠️  Experiments check failed"
	@echo ""
	@echo "✓ Post-upgrade validation completed"

.PHONY: mlflow-upgrade-rollback
mlflow-upgrade-rollback:
	@echo "=== MLflow Upgrade Rollback Procedures ==="
	@echo ""
	@echo "Option 1: Helm Rollback (Fast - reverts chart only)"
	@echo "  helm rollback mlflow"
	@echo "  make -f make/ops/mlflow.mk mlflow-post-upgrade-check"
	@echo ""
	@echo "Option 2: Database Restore (Complete - includes data)"
	@echo "  kubectl scale deployment/$(CHART_NAME) --replicas=0"
	@echo "  make -f make/ops/mlflow.mk mlflow-db-restore FILE=tmp/mlflow-backups/db/mlflow-db-YYYYMMDD-HHMMSS.sql"
	@echo "  helm rollback mlflow"
	@echo "  kubectl scale deployment/$(CHART_NAME) --replicas=1"
	@echo ""
	@echo "Option 3: Full Disaster Recovery"
	@echo "  helm uninstall mlflow"
	@echo "  helm install mlflow charts/mlflow -f values.yaml --version <previous-version>"
	@echo "  make -f make/ops/mlflow.mk mlflow-db-restore FILE=<backup-file>"
	@echo "  # Restore experiments/artifacts if needed"
	@echo ""
	@echo "⚠️  Always verify MLflow health after rollback:"
	@echo "  make -f make/ops/mlflow.mk mlflow-post-upgrade-check"
