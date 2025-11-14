# RustFS Helm Chart Makefile
# Usage: make -f Makefile.rustfs.mk <target>

# Variables
HELM ?= helm
KUBECTL ?= kubectl
CHART_NAME := rustfs
CHART_DIR := charts/$(CHART_NAME)
NAMESPACE ?= rustfs
RELEASE_NAME ?= rustfs
VALUES_FILE ?= values.yaml

# Detect values file variant (homeserver or startup)
ifeq ($(ENV),homeserver)
	VALUES_FILE := values-homeserver.yaml
else ifeq ($(ENV),startup)
	VALUES_FILE := values-startup.yaml
endif

# Pod selector
POD := $(shell $(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

.PHONY: all
all: lint template

# Lint chart
.PHONY: lint
lint:
	@echo "Linting $(CHART_NAME) chart..."
	$(HELM) lint $(CHART_DIR)

# Build/package chart
.PHONY: build
build:
	@echo "Building $(CHART_NAME) chart..."
	$(HELM) package $(CHART_DIR)

# Generate templates
.PHONY: template
template:
	@echo "Generating templates for $(CHART_NAME)..."
	$(HELM) template $(RELEASE_NAME) $(CHART_DIR) -f $(CHART_DIR)/$(VALUES_FILE) > $(CHART_NAME).yaml

# Install chart
.PHONY: install
install:
	@echo "Installing $(CHART_NAME) chart..."
	$(HELM) install $(RELEASE_NAME) $(CHART_DIR) \
		-f $(CHART_DIR)/$(VALUES_FILE) \
		--namespace $(NAMESPACE) \
		--create-namespace

# Install with homeserver config
.PHONY: install-homeserver
install-homeserver:
	@echo "Installing $(CHART_NAME) for home server..."
	$(HELM) install $(RELEASE_NAME) $(CHART_DIR) \
		-f $(CHART_DIR)/values-homeserver.yaml \
		--namespace $(NAMESPACE) \
		--create-namespace

# Install with startup config
.PHONY: install-startup
install-startup:
	@echo "Installing $(CHART_NAME) for startup/production..."
	$(HELM) install $(RELEASE_NAME) $(CHART_DIR) \
		-f $(CHART_DIR)/values-startup.yaml \
		--namespace $(NAMESPACE) \
		--create-namespace

# Upgrade chart
.PHONY: upgrade
upgrade:
	@echo "Upgrading $(CHART_NAME) chart..."
	$(HELM) upgrade $(RELEASE_NAME) $(CHART_DIR) \
		-f $(CHART_DIR)/$(VALUES_FILE) \
		--namespace $(NAMESPACE)

# Uninstall chart
.PHONY: uninstall
uninstall:
	@echo "Uninstalling $(CHART_NAME) chart..."
	$(HELM) uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)

# Get release status
.PHONY: status
status:
	@echo "Getting $(CHART_NAME) release status..."
	$(HELM) status $(RELEASE_NAME) --namespace $(NAMESPACE)

#
# RustFS Operational Commands
#

# Get RustFS credentials
.PHONY: rustfs-get-credentials
rustfs-get-credentials:
	@echo "RustFS Credentials:"
	@echo "==================="
	@echo -n "Root User: "
	@$(KUBECTL) get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath='{.data.root-user}' | base64 -d && echo
	@echo -n "Root Password: "
	@$(KUBECTL) get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath='{.data.root-password}' | base64 -d && echo

# Port forward API endpoint
.PHONY: rustfs-port-forward-api
rustfs-port-forward-api:
	@echo "Port forwarding RustFS API (S3) to localhost:9000..."
	@$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 9000:9000

# Port forward Console endpoint
.PHONY: rustfs-port-forward-console
rustfs-port-forward-console:
	@echo "Port forwarding RustFS Console to localhost:9001..."
	@$(KUBECTL) port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME) 9001:9001

# Open shell in RustFS pod
.PHONY: rustfs-shell
rustfs-shell:
	@echo "Opening shell in RustFS pod: $(POD)..."
	@$(KUBECTL) exec -it $(POD) -n $(NAMESPACE) -- /bin/sh

# View RustFS logs
.PHONY: rustfs-logs
rustfs-logs:
	@echo "Viewing logs for RustFS pod: $(POD)..."
	@$(KUBECTL) logs -f $(POD) -n $(NAMESPACE)

# Get RustFS pod status
.PHONY: rustfs-pods
rustfs-pods:
	@echo "Getting RustFS pods..."
	@$(KUBECTL) get pods -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

# Get RustFS StatefulSet status
.PHONY: rustfs-statefulset
rustfs-statefulset:
	@echo "Getting RustFS StatefulSet..."
	@$(KUBECTL) get statefulset $(RELEASE_NAME) -n $(NAMESPACE)

# Get RustFS PVCs
.PHONY: rustfs-pvcs
rustfs-pvcs:
	@echo "Getting RustFS PVCs..."
	@$(KUBECTL) get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

# Get RustFS services
.PHONY: rustfs-services
rustfs-services:
	@echo "Getting RustFS services..."
	@$(KUBECTL) get svc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

# Get RustFS ingress
.PHONY: rustfs-ingress
rustfs-ingress:
	@echo "Getting RustFS ingress..."
	@$(KUBECTL) get ingress -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME)

# Check RustFS health
.PHONY: rustfs-health
rustfs-health:
	@echo "Checking RustFS health..."
	@$(KUBECTL) exec $(POD) -n $(NAMESPACE) -- wget -q -O- http://localhost:9000/rustfs/health/live || echo "Health check failed"

# Get RustFS version
.PHONY: rustfs-version
rustfs-version:
	@echo "Getting RustFS version..."
	@$(KUBECTL) exec $(POD) -n $(NAMESPACE) -- rustfs --version 2>/dev/null || echo "Version check not supported"

# Test S3 API with mc (MinIO Client)
# Requires mc installed: https://min.io/docs/minio/linux/reference/minio-mc.html
.PHONY: rustfs-test-s3
rustfs-test-s3:
	@echo "Testing S3 API with MinIO Client..."
	@echo "Note: Requires 'mc' (MinIO Client) installed"
	@echo "Setting up mc alias..."
	@ROOT_USER=$$($(KUBECTL) get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath='{.data.root-user}' | base64 -d); \
	ROOT_PASSWORD=$$($(KUBECTL) get secret $(RELEASE_NAME)-secret -n $(NAMESPACE) -o jsonpath='{.data.root-password}' | base64 -d); \
	mc alias set rustfs-test http://localhost:9000 $$ROOT_USER $$ROOT_PASSWORD || true; \
	echo "Creating test bucket..."; \
	mc mb rustfs-test/testbucket || true; \
	echo "Listing buckets..."; \
	mc ls rustfs-test

# Restart RustFS StatefulSet
.PHONY: rustfs-restart
rustfs-restart:
	@echo "Restarting RustFS StatefulSet..."
	@$(KUBECTL) rollout restart statefulset $(RELEASE_NAME) -n $(NAMESPACE)
	@$(KUBECTL) rollout status statefulset $(RELEASE_NAME) -n $(NAMESPACE)

# Scale RustFS replicas
.PHONY: rustfs-scale
rustfs-scale:
	@if [ -z "$(REPLICAS)" ]; then \
		echo "Error: REPLICAS not set. Usage: make -f Makefile.rustfs.mk rustfs-scale REPLICAS=4"; \
		exit 1; \
	fi
	@echo "Scaling RustFS to $(REPLICAS) replicas..."
	@$(KUBECTL) scale statefulset $(RELEASE_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)

# Get RustFS metrics (if metrics enabled)
.PHONY: rustfs-metrics
rustfs-metrics:
	@echo "Getting RustFS metrics..."
	@$(KUBECTL) exec $(POD) -n $(NAMESPACE) -- wget -q -O- http://localhost:9000/metrics || echo "Metrics not available"

# Backup RustFS data (PVC snapshot)
.PHONY: rustfs-backup
rustfs-backup:
	@echo "Creating PVC snapshots for backup..."
	@echo "Note: Requires VolumeSnapshot CRD and snapshot controller"
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	for pvc in $$($(KUBECTL) get pvc -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[*].metadata.name}'); do \
		echo "Creating snapshot: $$pvc-snapshot-$$TIMESTAMP"; \
		cat <<EOF | $(KUBECTL) apply -f - ; \
		apiVersion: snapshot.storage.k8s.io/v1 ; \
		kind: VolumeSnapshot ; \
		metadata: ; \
		  name: $$pvc-snapshot-$$TIMESTAMP ; \
		  namespace: $(NAMESPACE) ; \
		spec: ; \
		  volumeSnapshotClassName: csi-snapclass ; \
		  source: ; \
		    persistentVolumeClaimName: $$pvc ; \
		EOF \
	done

# Show all RustFS resources
.PHONY: rustfs-all
rustfs-all:
	@echo "All RustFS resources:"
	@echo "====================="
	@echo ""
	@$(MAKE) -f Makefile.rustfs.mk rustfs-pods
	@echo ""
	@$(MAKE) -f Makefile.rustfs.mk rustfs-statefulset
	@echo ""
	@$(MAKE) -f Makefile.rustfs.mk rustfs-services
	@echo ""
	@$(MAKE) -f Makefile.rustfs.mk rustfs-pvcs

# Help
.PHONY: help
help:
	@echo "RustFS Helm Chart Makefile"
	@echo "============================"
	@echo ""
	@echo "Chart Management:"
	@echo "  lint                     - Lint the chart"
	@echo "  build                    - Package the chart"
	@echo "  template                 - Generate templates"
	@echo "  install                  - Install chart (default values)"
	@echo "  install-homeserver       - Install with homeserver config"
	@echo "  install-startup          - Install with startup/production config"
	@echo "  upgrade                  - Upgrade existing installation"
	@echo "  uninstall                - Uninstall chart"
	@echo "  status                   - Get release status"
	@echo ""
	@echo "RustFS Operations:"
	@echo "  rustfs-get-credentials   - Get admin username/password"
	@echo "  rustfs-port-forward-api  - Port forward S3 API (9000)"
	@echo "  rustfs-port-forward-console - Port forward Web Console (9001)"
	@echo "  rustfs-shell             - Open shell in RustFS pod"
	@echo "  rustfs-logs              - View RustFS logs"
	@echo "  rustfs-health            - Check RustFS health"
	@echo "  rustfs-version           - Get RustFS version"
	@echo "  rustfs-test-s3           - Test S3 API with MinIO Client"
	@echo "  rustfs-restart           - Restart StatefulSet"
	@echo "  rustfs-scale             - Scale replicas (REPLICAS=N)"
	@echo "  rustfs-metrics           - Get metrics endpoint"
	@echo "  rustfs-backup            - Backup PVCs (requires VolumeSnapshot)"
	@echo ""
	@echo "Resource Inspection:"
	@echo "  rustfs-pods              - Get pod status"
	@echo "  rustfs-statefulset       - Get StatefulSet status"
	@echo "  rustfs-pvcs              - Get PVCs"
	@echo "  rustfs-services          - Get services"
	@echo "  rustfs-ingress           - Get ingress"
	@echo "  rustfs-all               - Show all resources"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  VALUES_FILE=$(VALUES_FILE)"
	@echo "  ENV={default|homeserver|startup}"
	@echo ""
	@echo "Examples:"
	@echo "  make -f Makefile.rustfs.mk install-homeserver"
	@echo "  make -f Makefile.rustfs.mk rustfs-port-forward-console"
	@echo "  make -f Makefile.rustfs.mk rustfs-scale REPLICAS=4"
