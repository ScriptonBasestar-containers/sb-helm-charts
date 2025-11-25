# Tempo Operations Makefile
# Usage: make -f make/ops/tempo.mk <target>

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

CHART_NAME := tempo
CHART_DIR := charts/$(CHART_NAME)

# Tempo specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= tempo
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Tempo Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  tempo-logs                  - View Tempo logs"
	@echo "  tempo-logs-all              - View logs from all Tempo pods"
	@echo "  tempo-shell                 - Open shell in Tempo pod"
	@echo "  tempo-port-forward          - Port forward Tempo HTTP (3200)"
	@echo "  tempo-port-forward-otlp     - Port forward OTLP gRPC (4317)"
	@echo "  tempo-port-forward-otlp-http - Port forward OTLP HTTP (4318)"
	@echo "  tempo-port-forward-jaeger   - Port forward Jaeger Thrift (14268)"
	@echo "  tempo-port-forward-zipkin   - Port forward Zipkin (9411)"
	@echo "  tempo-restart               - Restart Tempo StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  tempo-ready                 - Check if Tempo is ready"
	@echo "  tempo-health                - Get health status"
	@echo "  tempo-metrics               - Get Prometheus metrics"
	@echo "  tempo-config                - Show current Tempo configuration"
	@echo "  tempo-status                - Get Tempo status"
	@echo ""
	@echo "Ring & Clustering:"
	@echo "  tempo-ring-status           - Get ring status"
	@echo "  tempo-memberlist-status     - Get memberlist status"
	@echo ""
	@echo "Trace Operations:"
	@echo "  tempo-search                - Search traces (SERVICE=myapp LIMIT=10)"
	@echo "  tempo-trace                 - Get trace by ID (TRACE_ID=xxx)"
	@echo "  tempo-test-trace            - Send test trace via OTLP"
	@echo ""
	@echo "Storage:"
	@echo "  tempo-check-storage         - Check storage configuration"
	@echo "  tempo-flush                 - Flush in-memory data to storage"
	@echo ""
	@echo "Integration:"
	@echo "  tempo-grafana-datasource    - Get Grafana datasource URL"
	@echo ""
	@echo "Scaling:"
	@echo "  tempo-scale                 - Scale Tempo (REPLICAS=3)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: tempo-logs tempo-logs-all tempo-shell tempo-port-forward tempo-port-forward-otlp tempo-port-forward-otlp-http tempo-port-forward-jaeger tempo-port-forward-zipkin tempo-restart

tempo-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

tempo-logs-all:
	@echo "Fetching logs from all Tempo pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

tempo-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

tempo-port-forward:
	@echo "Port forwarding Tempo HTTP API to localhost:3200..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 3200:3200

tempo-port-forward-otlp:
	@echo "Port forwarding OTLP gRPC to localhost:4317..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4317:4317

tempo-port-forward-otlp-http:
	@echo "Port forwarding OTLP HTTP to localhost:4318..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 4318:4318

tempo-port-forward-jaeger:
	@echo "Port forwarding Jaeger Thrift to localhost:14268..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 14268:14268

tempo-port-forward-zipkin:
	@echo "Port forwarding Zipkin to localhost:9411..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9411:9411

tempo-restart:
	@echo "Restarting Tempo StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: tempo-ready tempo-health tempo-metrics tempo-config tempo-status

tempo-ready:
	@echo "Checking if Tempo is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready

tempo-health:
	@echo "Getting Tempo health status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/ready

tempo-metrics:
	@echo "Fetching Prometheus metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/metrics

tempo-config:
	@echo "Showing current Tempo configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/tempo/tempo.yaml

tempo-status:
	@echo "Getting Tempo status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/status

# Ring & Clustering
.PHONY: tempo-ring-status tempo-memberlist-status

tempo-ring-status:
	@echo "Getting ring status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/distributor/ring

tempo-memberlist-status:
	@echo "Getting memberlist status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:3200/memberlist

# Trace Operations
.PHONY: tempo-search tempo-trace tempo-test-trace

SERVICE ?= myapp
LIMIT ?= 10
TRACE_ID ?=

tempo-search:
	@echo "Searching traces for service '$(SERVICE)' (limit: $(LIMIT))..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3200/api/search?q={.service.name%3D\"$(SERVICE)\"}&limit=$(LIMIT)"

tempo-trace:
	@if [ -z "$(TRACE_ID)" ]; then \
		echo "Error: TRACE_ID is required. Usage: make tempo-trace TRACE_ID=abc123"; \
		exit 1; \
	fi
	@echo "Getting trace $(TRACE_ID)..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:3200/api/traces/$(TRACE_ID)"

tempo-test-trace:
	@echo "Sending test trace via OTLP HTTP..."
	@echo "Note: This requires curl to be available in the container"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c 'echo "{ \
		\"resourceSpans\": [{ \
			\"resource\": { \
				\"attributes\": [{ \
					\"key\": \"service.name\", \
					\"value\": { \"stringValue\": \"test-service\" } \
				}] \
			}, \
			\"scopeSpans\": [{ \
				\"spans\": [{ \
					\"traceId\": \"$$(cat /proc/sys/kernel/random/uuid | tr -d -)\", \
					\"spanId\": \"$$(cat /proc/sys/kernel/random/uuid | cut -c1-16 | tr -d -)\", \
					\"name\": \"test-span\", \
					\"kind\": 1, \
					\"startTimeUnixNano\": \"$$(date +%s)000000000\", \
					\"endTimeUnixNano\": \"$$(date +%s)100000000\" \
				}] \
			}] \
		}] \
	}" | wget -qO- --post-data=@- --header="Content-Type: application/json" http://localhost:4318/v1/traces' || true
	@echo ""
	@echo "If wget failed, use port-forward and curl locally:"
	@echo "  make tempo-port-forward-otlp-http &"
	@echo "  curl -X POST http://localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{...}'"

# Storage
.PHONY: tempo-check-storage tempo-flush

tempo-check-storage:
	@echo "Checking storage configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- ls -lah /var/tempo

tempo-flush:
	@echo "Flushing in-memory data to storage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- -X POST http://localhost:3200/flush

# Integration
.PHONY: tempo-grafana-datasource

tempo-grafana-datasource:
	@echo "Grafana datasource configuration:"
	@echo ""
	@echo "  Name: Tempo"
	@echo "  Type: Tempo"
	@echo "  URL: http://$(CHART_NAME).$(NAMESPACE).svc.cluster.local:3200"
	@echo ""
	@echo "Optional service graph configuration:"
	@echo "  Enable 'Service graph' in datasource settings"
	@echo "  Configure Prometheus datasource for metrics correlation"
	@echo "  Configure Loki datasource for logs correlation"
	@echo ""
	@echo "Trace to Logs:"
	@echo "  Datasource: Loki"
	@echo "  Tags: service.name -> job"
	@echo ""

# Scaling
.PHONY: tempo-scale

REPLICAS ?= 3

tempo-scale:
	@echo "Scaling Tempo to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
