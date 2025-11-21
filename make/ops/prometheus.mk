# Prometheus Operations Makefile
# Usage: make -f make/ops/prometheus.mk <target>

include make/Makefile.common.mk

CHART_NAME := prometheus
CHART_DIR := charts/$(CHART_NAME)

# Prometheus specific variables
POD_NAME ?= $(CHART_NAME)-0
CONTAINER_NAME ?= prometheus
NAMESPACE ?= default

.PHONY: help
help:
	@echo "Prometheus Operations"
	@echo ""
	@echo "Basic Operations:"
	@echo "  prom-logs                   - View Prometheus logs"
	@echo "  prom-logs-all               - View logs from all Prometheus pods"
	@echo "  prom-shell                  - Open shell in Prometheus pod"
	@echo "  prom-port-forward           - Port forward Prometheus (9090)"
	@echo "  prom-restart                - Restart Prometheus StatefulSet"
	@echo ""
	@echo "Health & Status:"
	@echo "  prom-ready                  - Check if Prometheus is ready"
	@echo "  prom-healthy                - Check if Prometheus is healthy"
	@echo "  prom-version                - Get Prometheus version"
	@echo "  prom-config                 - Show current Prometheus configuration"
	@echo "  prom-config-check           - Validate Prometheus configuration"
	@echo "  prom-flags                  - Show Prometheus runtime flags"
	@echo "  prom-runtime-info           - Show runtime information"
	@echo ""
	@echo "Targets & Service Discovery:"
	@echo "  prom-targets                - List all scrape targets"
	@echo "  prom-targets-active         - List only active targets"
	@echo "  prom-sd                     - Show service discovery status"
	@echo ""
	@echo "Metrics & Queries:"
	@echo "  prom-query                  - Execute PromQL query (QUERY='up')"
	@echo "  prom-query-range            - Execute range query (QUERY='up' START='-1h' END='now' STEP='15s')"
	@echo "  prom-labels                 - List all label names"
	@echo "  prom-label-values           - Get values for a label (LABEL=job)"
	@echo "  prom-series                 - List all time series (MATCH='{job=\"prometheus\"}')"
	@echo "  prom-metrics                - Get Prometheus own metrics"
	@echo ""
	@echo "TSDB & Storage:"
	@echo "  prom-tsdb-status            - Get TSDB status"
	@echo "  prom-tsdb-snapshot          - Create TSDB snapshot (requires admin API)"
	@echo "  prom-check-storage          - Check storage usage"
	@echo ""
	@echo "Configuration Reload:"
	@echo "  prom-reload                 - Reload configuration (requires --web.enable-lifecycle)"
	@echo ""
	@echo "Rules & Alerts:"
	@echo "  prom-rules                  - List all recording/alerting rules"
	@echo "  prom-alerts                 - Show active alerts"
	@echo ""
	@echo "Testing:"
	@echo "  prom-test-query             - Run sample queries to verify Prometheus"
	@echo ""
	@echo "Scaling:"
	@echo "  prom-scale                  - Scale Prometheus (REPLICAS=2)"
	@echo ""
	@echo "Common Makefile Targets:"
	@echo "  lint                        - Lint the chart"
	@echo "  build                       - Package the chart"
	@echo "  install                     - Install the chart"
	@echo "  upgrade                     - Upgrade the chart"
	@echo "  uninstall                   - Uninstall the chart"
	@echo ""

# Basic Operations
.PHONY: prom-logs prom-logs-all prom-shell prom-port-forward prom-restart

prom-logs:
	@echo "Fetching logs from $(POD_NAME)..."
	kubectl logs -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) --tail=100 -f

prom-logs-all:
	@echo "Fetching logs from all Prometheus pods..."
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(CHART_NAME) -c $(CONTAINER_NAME) --tail=50

prom-shell:
	@echo "Opening shell in $(POD_NAME)..."
	kubectl exec -it -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- /bin/sh

prom-port-forward:
	@echo "Port forwarding Prometheus to localhost:9090..."
	kubectl port-forward -n $(NAMESPACE) svc/$(CHART_NAME) 9090:9090

prom-restart:
	@echo "Restarting Prometheus StatefulSet..."
	kubectl rollout restart statefulset/$(CHART_NAME) -n $(NAMESPACE)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)

# Health & Status
.PHONY: prom-ready prom-healthy prom-version prom-config prom-config-check prom-flags prom-runtime-info

prom-ready:
	@echo "Checking if Prometheus is ready..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/-/ready

prom-healthy:
	@echo "Checking if Prometheus is healthy..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/-/healthy

prom-version:
	@echo "Getting Prometheus version..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- prometheus --version

prom-config:
	@echo "Showing current Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- cat /etc/prometheus/prometheus.yml

prom-config-check:
	@echo "Validating Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- promtool check config /etc/prometheus/prometheus.yml

prom-flags:
	@echo "Showing Prometheus runtime flags..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/flags | grep -o '"[^"]*":"[^"]*"' | sed 's/"//g' | column -t -s ':'

prom-runtime-info:
	@echo "Showing runtime information..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/runtimeinfo

# Targets & Service Discovery
.PHONY: prom-targets prom-targets-active prom-sd

prom-targets:
	@echo "Listing all scrape targets..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/targets

prom-targets-active:
	@echo "Listing only active targets..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- 'http://localhost:9090/api/v1/targets?state=active'

prom-sd:
	@echo "Showing service discovery status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/service-discovery

# Metrics & Queries
.PHONY: prom-query prom-query-range prom-labels prom-label-values prom-series prom-metrics

QUERY ?= up
START ?= -1h
END ?= now
STEP ?= 15s
LABEL ?= job
MATCH ?= {job="prometheus"}

prom-query:
	@echo "Executing query: $(QUERY)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=$$(echo '$(QUERY)' | sed 's/ /%20/g')"

prom-query-range:
	@echo "Executing range query: $(QUERY) from $(START) to $(END) step $(STEP)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- sh -c "wget -qO- 'http://localhost:9090/api/v1/query_range?query=$(QUERY)&start=$$(date -d '$(START)' +%s)&end=$$(date -d '$(END)' +%s)&step=$(STEP)'"

prom-labels:
	@echo "Listing all label names..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/labels

prom-label-values:
	@echo "Getting values for label '$(LABEL)'..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/label/$(LABEL)/values

prom-series:
	@echo "Listing time series matching: $(MATCH)"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/series?match[]=$(MATCH)"

prom-metrics:
	@echo "Fetching Prometheus own metrics..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/metrics

# TSDB & Storage
.PHONY: prom-tsdb-status prom-tsdb-snapshot prom-check-storage

prom-tsdb-status:
	@echo "Getting TSDB status..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/status/tsdb

prom-tsdb-snapshot:
	@echo "Creating TSDB snapshot (requires admin API)..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot

prom-check-storage:
	@echo "Checking storage usage..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- df -h /prometheus

# Configuration Reload
.PHONY: prom-reload

prom-reload:
	@echo "Reloading Prometheus configuration..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- --post-data='' http://localhost:9090/-/reload

# Rules & Alerts
.PHONY: prom-rules prom-alerts

prom-rules:
	@echo "Listing all recording/alerting rules..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/rules

prom-alerts:
	@echo "Showing active alerts..."
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- http://localhost:9090/api/v1/alerts

# Testing
.PHONY: prom-test-query

prom-test-query:
	@echo "Running sample queries..."
	@echo ""
	@echo "1. Check if Prometheus is scraping itself:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"prometheus\"}"
	@echo ""
	@echo "2. Count all time series:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=count(up)"
	@echo ""
	@echo "3. Show scrape duration:"
	kubectl exec -n $(NAMESPACE) $(POD_NAME) -c $(CONTAINER_NAME) -- wget -qO- "http://localhost:9090/api/v1/query?query=scrape_duration_seconds"

# Scaling
.PHONY: prom-scale

REPLICAS ?= 2

prom-scale:
	@echo "Scaling Prometheus to $(REPLICAS) replicas..."
	kubectl scale statefulset/$(CHART_NAME) -n $(NAMESPACE) --replicas=$(REPLICAS)
	kubectl rollout status statefulset/$(CHART_NAME) -n $(NAMESPACE)
