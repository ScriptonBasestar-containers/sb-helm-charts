# jellyfin 차트 설정
CHART_NAME := jellyfin
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include make/common.mk

# Jellyfin 특화 타겟

.PHONY: jellyfin-shell
jellyfin-shell:
	@echo "Opening shell in Jellyfin pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/bash

.PHONY: jellyfin-logs
jellyfin-logs:
	@echo "Tailing Jellyfin logs..."
	@$(KUBECTL) logs -f $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: jellyfin-restart
jellyfin-restart:
	@echo "Restarting Jellyfin deployment..."
	@$(KUBECTL) rollout restart deployment/$(RELEASE_NAME)
	@$(KUBECTL) rollout status deployment/$(RELEASE_NAME)

.PHONY: jellyfin-port-forward
jellyfin-port-forward:
	@echo "Port forwarding Jellyfin web UI to localhost:8096..."
	@$(KUBECTL) port-forward $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") 8096:8096

.PHONY: jellyfin-get-url
jellyfin-get-url:
	@echo "Getting Jellyfin access URL..."
	@echo "Service type: $$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.spec.type}')"
	@if [ "$$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.spec.type}')" = "LoadBalancer" ]; then \
		echo "External IP: $$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"; \
		echo "URL: http://$$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8096"; \
	elif [ "$$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.spec.type}')" = "NodePort" ]; then \
		echo "Node Port: $$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.spec.ports[0].nodePort}')"; \
		echo "URL: http://<NODE_IP>:$$($(KUBECTL) get svc $(RELEASE_NAME) -o jsonpath='{.spec.ports[0].nodePort}')"; \
	else \
		echo "ClusterIP: Use 'make jellyfin-port-forward' to access locally"; \
	fi

.PHONY: jellyfin-check-gpu
jellyfin-check-gpu:
	@echo "Checking GPU configuration..."
	@echo "Hardware acceleration type: $$(helm get values $(RELEASE_NAME) -o json | jq -r '.jellyfin.hardwareAcceleration.type // "none"')"
	@if [ "$$(helm get values $(RELEASE_NAME) -o json | jq -r '.jellyfin.hardwareAcceleration.enabled')" = "true" ]; then \
		echo "GPU enabled: Yes"; \
		GPU_TYPE=$$(helm get values $(RELEASE_NAME) -o json | jq -r '.jellyfin.hardwareAcceleration.type'); \
		if [ "$$GPU_TYPE" = "intel-qsv" ] || [ "$$GPU_TYPE" = "amd-vaapi" ]; then \
			echo "Checking /dev/dri access..."; \
			$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- ls -la /dev/dri || echo "Error: /dev/dri not accessible"; \
			$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- ls -la /dev/dri/renderD* || echo "Info: No renderD* devices found"; \
		elif [ "$$GPU_TYPE" = "nvidia-nvenc" ]; then \
			echo "Checking NVIDIA GPU..."; \
			$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- nvidia-smi || echo "Error: nvidia-smi not available"; \
		fi; \
	else \
		echo "GPU enabled: No (CPU transcoding only)"; \
	fi

.PHONY: jellyfin-check-media
jellyfin-check-media:
	@echo "Checking media directories..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- df -h | grep -E "(Filesystem|/media)"

.PHONY: jellyfin-check-config
jellyfin-check-config:
	@echo "Checking Jellyfin configuration..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- ls -lah /config

.PHONY: jellyfin-check-cache
jellyfin-check-cache:
	@echo "Checking transcoding cache usage..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- du -sh /cache
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- df -h /cache

.PHONY: jellyfin-clear-cache
jellyfin-clear-cache:
	@echo "WARNING: This will clear the transcoding cache!"
	@echo "Press Ctrl+C to cancel, or Enter to continue..."
	@read confirm
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- rm -rf /cache/*
	@echo "Cache cleared"

.PHONY: jellyfin-backup-config
jellyfin-backup-config:
	@echo "Backing up Jellyfin configuration..."
	@mkdir -p tmp/jellyfin-backups
	@BACKUP_FILE="tmp/jellyfin-backups/jellyfin-config-$$(date +%Y%m%d-%H%M%S).tar.gz"; \
	$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- tar czf - /config > $$BACKUP_FILE; \
	echo "Backup completed: $$BACKUP_FILE"

.PHONY: jellyfin-restore-config
jellyfin-restore-config:
	@echo "Restoring Jellyfin configuration from file: $(FILE)"
	@if [ -z "$(FILE)" ]; then echo "Error: FILE parameter required (e.g., FILE=tmp/jellyfin-backups/backup.tar.gz)"; exit 1; fi
	@cat $(FILE) | $(KUBECTL) exec -i $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- tar xzf - -C /
	@echo "Restore completed. Restarting pod..."
	@$(KUBECTL) delete pod $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")
	@echo "Wait for pod to restart"

.PHONY: jellyfin-stats
jellyfin-stats:
	@echo "Jellyfin resource usage:"
	@$(KUBECTL) top pod -l app.kubernetes.io/name=$(CHART_NAME) || echo "Metrics server not available"

.PHONY: jellyfin-describe
jellyfin-describe:
	@echo "Describing Jellyfin pod..."
	@$(KUBECTL) describe pod $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: jellyfin-events
jellyfin-events:
	@echo "Getting Jellyfin pod events..."
	@$(KUBECTL) get events --field-selector involvedObject.name=$$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") --sort-by='.lastTimestamp'

.PHONY: jellyfin-help
jellyfin-help:
	@echo "Jellyfin Chart - Operational Commands"
	@echo ""
	@echo "Access & Debugging:"
	@echo "  make jellyfin-shell           - Open shell in Jellyfin pod"
	@echo "  make jellyfin-logs            - Tail Jellyfin logs"
	@echo "  make jellyfin-port-forward    - Port forward to localhost:8096"
	@echo "  make jellyfin-get-url         - Get access URL"
	@echo "  make jellyfin-restart         - Restart Jellyfin deployment"
	@echo ""
	@echo "GPU & Configuration:"
	@echo "  make jellyfin-check-gpu       - Check GPU configuration and access"
	@echo "  make jellyfin-check-media     - Check media directories"
	@echo "  make jellyfin-check-config    - Check configuration directory"
	@echo "  make jellyfin-check-cache     - Check transcoding cache usage"
	@echo ""
	@echo "Cache Management:"
	@echo "  make jellyfin-clear-cache     - Clear transcoding cache"
	@echo ""
	@echo "Backup & Restore:"
	@echo "  make jellyfin-backup-config   - Backup configuration to tmp/jellyfin-backups/"
	@echo "  make jellyfin-restore-config FILE=<path> - Restore configuration"
	@echo ""
	@echo "Monitoring:"
	@echo "  make jellyfin-stats           - Show resource usage"
	@echo "  make jellyfin-describe        - Describe pod"
	@echo "  make jellyfin-events          - Show pod events"
	@echo ""
	@echo "Standard Chart Operations:"
	@echo "  make lint                     - Lint chart"
	@echo "  make template                 - Generate templates"
	@echo "  make install                  - Install chart"
	@echo "  make upgrade                  - Upgrade chart"
	@echo "  make uninstall                - Uninstall chart"
