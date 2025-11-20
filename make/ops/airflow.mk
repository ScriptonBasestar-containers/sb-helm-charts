CHART_NAME := airflow
CHART_DIR := charts/$(CHART_NAME)

include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

# Helper function to get webserver pod name
define get-webserver-pod-name
$(shell \
	if [ -n "$(POD)" ]; then \
		echo "$(POD)"; \
	else \
		POD_NAME=$$(kubectl get pod -l app.kubernetes.io/component=webserver -o jsonpath="{.items[0].metadata.name}" 2>/dev/null); \
		if [ -z "$$POD_NAME" ]; then \
			echo "ERROR: No webserver pods found. Is Airflow deployed?" >&2; \
			exit 1; \
		fi; \
		echo "$$POD_NAME"; \
	fi \
)
endef

# Helper function to get scheduler pod name
define get-scheduler-pod-name
$(shell \
	POD_NAME=$$(kubectl get pod -l app.kubernetes.io/component=scheduler -o jsonpath="{.items[0].metadata.name}" 2>/dev/null); \
	if [ -z "$$POD_NAME" ]; then \
		echo "ERROR: No scheduler pods found. Is Airflow deployed?" >&2; \
		exit 1; \
	fi; \
	echo "$$POD_NAME"; \
)
endef

# Airflow-specific targets

.PHONY: airflow-get-password
airflow-get-password:
	@echo "=== Airflow Admin Credentials ==="
	@SECRET_NAME=$$(kubectl get secret -l app.kubernetes.io/name=$(CHART_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$SECRET_NAME" ]; then \
		echo "No secret found. Admin password may not be set."; \
		exit 1; \
	fi; \
	PASSWORD=$$(kubectl get secret $$SECRET_NAME -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null); \
	if [ -n "$$PASSWORD" ]; then \
		echo "Username: admin"; \
		echo "Password: $$PASSWORD"; \
	else \
		echo "Admin password is not set in secret."; \
	fi
	@echo ""

.PHONY: airflow-port-forward
airflow-port-forward:
	@echo "Port-forwarding Airflow webserver to localhost:8080..."
	@kubectl port-forward svc/$(CHART_NAME)-webserver 8080:8080

.PHONY: airflow-health
airflow-health:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Airflow Health Check (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- curl -s http://localhost:8080/health | grep -E "metadatabase|scheduler"

.PHONY: airflow-version
airflow-version:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Airflow version (pod: $$POD_NAME):"; \
	kubectl exec -it $$POD_NAME -- airflow version

.PHONY: airflow-dag-list
airflow-dag-list:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Airflow DAG List (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow dags list

.PHONY: airflow-dag-trigger
airflow-dag-trigger:
	@if [ -z "$(DAG)" ]; then \
		echo "Error: DAG parameter is required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-dag-trigger DAG=example_dag [CONF='{}']"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Triggering DAG: $(DAG) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow dags trigger $(DAG) $(if $(CONF),--conf '$(CONF)',)

.PHONY: airflow-dag-pause
airflow-dag-pause:
	@if [ -z "$(DAG)" ]; then \
		echo "Error: DAG parameter is required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-dag-pause DAG=example_dag"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Pausing DAG: $(DAG) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow dags pause $(DAG)

.PHONY: airflow-dag-unpause
airflow-dag-unpause:
	@if [ -z "$(DAG)" ]; then \
		echo "Error: DAG parameter is required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-dag-unpause DAG=example_dag"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Unpausing DAG: $(DAG) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow dags unpause $(DAG)

.PHONY: airflow-dag-state
airflow-dag-state:
	@if [ -z "$(DAG)" ]; then \
		echo "Error: DAG parameter is required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-dag-state DAG=example_dag"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== DAG State: $(DAG) (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow dags state $(DAG)

.PHONY: airflow-task-list
airflow-task-list:
	@if [ -z "$(DAG)" ]; then \
		echo "Error: DAG parameter is required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-task-list DAG=example_dag"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Tasks in DAG: $(DAG) (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow tasks list $(DAG)

.PHONY: airflow-connections-list
airflow-connections-list:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Airflow Connections (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow connections list

.PHONY: airflow-connections-add
airflow-connections-add:
	@if [ -z "$(CONN_ID)" ] || [ -z "$(CONN_TYPE)" ]; then \
		echo "Error: CONN_ID and CONN_TYPE parameters are required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-connections-add CONN_ID=my_conn CONN_TYPE=postgres [CONN_URI='postgres://user:pass@host:5432/db']"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Adding connection: $(CONN_ID) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow connections add $(CONN_ID) --conn-type $(CONN_TYPE) $(if $(CONN_URI),--conn-uri '$(CONN_URI)',)

.PHONY: airflow-variables-list
airflow-variables-list:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Airflow Variables (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow variables list

.PHONY: airflow-variables-set
airflow-variables-set:
	@if [ -z "$(KEY)" ] || [ -z "$(VALUE)" ]; then \
		echo "Error: KEY and VALUE parameters are required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-variables-set KEY=my_var VALUE=my_value"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Setting variable: $(KEY)=$(VALUE) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow variables set $(KEY) '$(VALUE)'

.PHONY: airflow-db-check
airflow-db-check:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Database Check (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow db check

.PHONY: airflow-users-list
airflow-users-list:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "=== Airflow Users (pod: $$POD_NAME) ==="; \
	kubectl exec -it $$POD_NAME -- airflow users list

.PHONY: airflow-users-create
airflow-users-create:
	@if [ -z "$(USERNAME)" ] || [ -z "$(PASSWORD)" ] || [ -z "$(EMAIL)" ]; then \
		echo "Error: USERNAME, PASSWORD, and EMAIL parameters are required"; \
		echo "Usage: make -f make/ops/airflow.mk airflow-users-create USERNAME=user PASSWORD=pass EMAIL=user@example.com [ROLE=Admin]"; \
		exit 1; \
	fi
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Creating user: $(USERNAME) (pod: $$POD_NAME)"; \
	kubectl exec -it $$POD_NAME -- airflow users create \
		--username $(USERNAME) \
		--password $(PASSWORD) \
		--email $(EMAIL) \
		--role $(if $(ROLE),$(ROLE),User) \
		--firstname $(if $(FIRSTNAME),$(FIRSTNAME),User) \
		--lastname $(if $(LASTNAME),$(LASTNAME),User)

.PHONY: airflow-webserver-logs
airflow-webserver-logs:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Tailing webserver logs (pod: $$POD_NAME)..."; \
	kubectl logs -f $$POD_NAME

.PHONY: airflow-scheduler-logs
airflow-scheduler-logs:
	@POD_NAME="$(call get-scheduler-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Tailing scheduler logs (pod: $$POD_NAME)..."; \
	kubectl logs -f $$POD_NAME

.PHONY: airflow-webserver-logs-all
airflow-webserver-logs-all:
	@echo "Tailing all webserver pod logs..."
	@kubectl logs -f -l app.kubernetes.io/component=webserver --all-containers=true --prefix=true

.PHONY: airflow-scheduler-logs-all
airflow-scheduler-logs-all:
	@echo "Tailing all scheduler pod logs..."
	@kubectl logs -f -l app.kubernetes.io/component=scheduler --all-containers=true --prefix=true

.PHONY: airflow-webserver-shell
airflow-webserver-shell:
	@POD_NAME="$(call get-webserver-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Opening shell in webserver pod (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- /bin/bash

.PHONY: airflow-scheduler-shell
airflow-scheduler-shell:
	@POD_NAME="$(call get-scheduler-pod-name)"; \
	if [ -z "$$POD_NAME" ]; then exit 1; fi; \
	echo "Opening shell in scheduler pod (pod: $$POD_NAME)..."; \
	kubectl exec -it $$POD_NAME -- /bin/bash

.PHONY: airflow-webserver-restart
airflow-webserver-restart:
	@echo "Restarting webserver deployment..."
	@kubectl rollout restart deployment/$(CHART_NAME)-webserver
	@kubectl rollout status deployment/$(CHART_NAME)-webserver

.PHONY: airflow-scheduler-restart
airflow-scheduler-restart:
	@echo "Restarting scheduler deployment..."
	@kubectl rollout restart deployment/$(CHART_NAME)-scheduler
	@kubectl rollout status deployment/$(CHART_NAME)-scheduler

.PHONY: airflow-status
airflow-status:
	@echo "=== Airflow Deployment Status ==="
	@echo ""
	@echo "Webserver Pods:"
	@kubectl get pods -l app.kubernetes.io/component=webserver
	@echo ""
	@echo "Scheduler Pods:"
	@kubectl get pods -l app.kubernetes.io/component=scheduler
	@echo ""
	@echo "Triggerer Pods:"
	@kubectl get pods -l app.kubernetes.io/component=triggerer 2>/dev/null || echo "Triggerer not deployed"
	@echo ""
	@echo "Services:"
	@kubectl get svc -l app.kubernetes.io/name=$(CHART_NAME)
	@echo ""
	@echo "PVCs:"
	@kubectl get pvc -l app.kubernetes.io/name=$(CHART_NAME)

# Help from common makefile
.PHONY: help-common
help-common:
	@$(MAKE) -f make/common.mk help CHART_NAME=$(CHART_NAME) CHART_DIR=$(CHART_DIR)

.PHONY: help
help: help-common
	@echo ""
	@echo "Airflow specific targets:"
	@echo "  airflow-get-password         - Display admin credentials"
	@echo "  airflow-port-forward         - Port-forward webserver to localhost:8080"
	@echo "  airflow-health               - Check Airflow health"
	@echo "  airflow-version              - Show Airflow version"
	@echo ""
	@echo "DAG Management:"
	@echo "  airflow-dag-list             - List all DAGs"
	@echo "  airflow-dag-trigger          - Trigger a DAG (DAG=name [CONF='{}'])"
	@echo "  airflow-dag-pause            - Pause a DAG (DAG=name)"
	@echo "  airflow-dag-unpause          - Unpause a DAG (DAG=name)"
	@echo "  airflow-dag-state            - Show DAG state (DAG=name)"
	@echo "  airflow-task-list            - List tasks in DAG (DAG=name)"
	@echo ""
	@echo "Connections and Variables:"
	@echo "  airflow-connections-list     - List all connections"
	@echo "  airflow-connections-add      - Add connection (CONN_ID=name CONN_TYPE=type [CONN_URI='...'])"
	@echo "  airflow-variables-list       - List all variables"
	@echo "  airflow-variables-set        - Set variable (KEY=name VALUE=value)"
	@echo ""
	@echo "User Management:"
	@echo "  airflow-users-list           - List all users"
	@echo "  airflow-users-create         - Create user (USERNAME=name PASSWORD=pass EMAIL=email [ROLE=Admin])"
	@echo ""
	@echo "Database:"
	@echo "  airflow-db-check             - Check database connection"
	@echo ""
	@echo "Logs and Shell:"
	@echo "  airflow-webserver-logs       - Tail webserver logs"
	@echo "  airflow-scheduler-logs       - Tail scheduler logs"
	@echo "  airflow-webserver-logs-all   - Tail all webserver pod logs"
	@echo "  airflow-scheduler-logs-all   - Tail all scheduler pod logs"
	@echo "  airflow-webserver-shell      - Open shell in webserver pod"
	@echo "  airflow-scheduler-shell      - Open shell in scheduler pod"
	@echo ""
	@echo "Operations:"
	@echo "  airflow-webserver-restart    - Restart webserver deployment"
	@echo "  airflow-scheduler-restart    - Restart scheduler deployment"
	@echo "  airflow-status               - Show all Airflow resources status"
	@echo ""
	@echo "Note: Commands default to first pod. Use POD=<pod-name> to target specific pod."
