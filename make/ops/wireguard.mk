# wireguard 차트 설정
CHART_NAME := wireguard
CHART_DIR := charts/$(CHART_NAME)

# 공통 Makefile 포함
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# WireGuard 특화 타겟
.PHONY: wg-show
wg-show:
	@echo "Showing WireGuard status..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- wg show

.PHONY: wg-get-peer
wg-get-peer:
	@echo "Getting peer configuration: $(PEER)"
	@if [ -z "$(PEER)" ]; then echo "Error: PEER parameter required (e.g., PEER=peer1)"; exit 1; fi
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- cat /config/$(PEER)/$(PEER).conf

.PHONY: wg-list-peers
wg-list-peers:
	@echo "Listing all peer directories..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- ls -la /config/peer* 2>/dev/null || echo "No peer directories found (check if auto mode is enabled)"

.PHONY: wg-qr
wg-qr:
	@echo "Displaying QR code for peer: $(PEER)"
	@if [ -z "$(PEER)" ]; then echo "Error: PEER parameter required (e.g., PEER=peer1)"; exit 1; fi
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- sh -c "cat /config/$(PEER)/$(PEER).png 2>/dev/null | base64" || echo "QR code not found (check if auto mode is enabled)"

.PHONY: wg-config
wg-config:
	@echo "Showing current WireGuard configuration..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- cat /config/wg0.conf

.PHONY: wg-pubkey
wg-pubkey:
	@echo "Getting server public key..."
	@$(KUBECTL) exec $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- wg show wg0 public-key 2>/dev/null || echo "WireGuard interface not found"

.PHONY: wg-restart
wg-restart:
	@echo "Restarting WireGuard (rolling out new deployment)..."
	@$(KUBECTL) rollout restart deployment/$$($(KUBECTL) get deployment -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: wg-logs
wg-logs:
	@echo "Tailing WireGuard logs..."
	@$(KUBECTL) logs -f deployment/$$($(KUBECTL) get deployment -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}")

.PHONY: wg-shell
wg-shell:
	@echo "Opening shell in WireGuard pod..."
	@$(KUBECTL) exec -it $$($(KUBECTL) get pod -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath="{.items[0].metadata.name}") -- /bin/bash

.PHONY: wg-endpoint
wg-endpoint:
	@echo "Getting WireGuard service endpoint..."
	@echo "Service type: $$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.spec.type}')"
	@if [ "$$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.spec.type}')" = "LoadBalancer" ]; then \
		echo "LoadBalancer IP: $$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"; \
	elif [ "$$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.spec.type}')" = "NodePort" ]; then \
		echo "NodePort: $$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.spec.ports[0].nodePort}')"; \
		echo "Use with any node IP"; \
	else \
		echo "ClusterIP: $$($(KUBECTL) get svc $(CHART_NAME) -o jsonpath='{.spec.clusterIP}')"; \
	fi

# 도움말 확장
.PHONY: help
help: help-common
	@echo ""
	@echo "WireGuard specific targets:"
	@echo "  wg-show          - Show WireGuard interface status (wg show)"
	@echo "  wg-get-peer      - Get peer configuration file (usage: make wg-get-peer PEER=peer1)"
	@echo "  wg-list-peers    - List all peer directories"
	@echo "  wg-qr            - Display QR code for peer (usage: make wg-qr PEER=peer1)"
	@echo "  wg-config        - Show current wg0.conf configuration"
	@echo "  wg-pubkey        - Get server public key"
	@echo "  wg-restart       - Restart WireGuard (rollout deployment)"
	@echo "  wg-logs          - Tail WireGuard logs"
	@echo "  wg-shell         - Open shell in WireGuard pod"
	@echo "  wg-endpoint      - Get service endpoint (LoadBalancer IP or NodePort)"

# 기존 도움말을 위한 별칭
.PHONY: help-common
help-common:
	@$(MAKE) -f Makefile.common.mk help
