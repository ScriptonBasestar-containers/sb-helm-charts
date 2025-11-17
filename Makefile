# 변수 정의
HELM ?= helm
KIND ?= kind
KUBECTL ?= kubectl
CHART_DIRS := $(shell find charts -mindepth 1 -maxdepth 1 -type d)
CHART_NAMES := $(notdir $(CHART_DIRS))
KIND_CLUSTER_NAME ?= sb-helm-charts
KIND_CONFIG ?= kind-config.yaml

# 기본 타겟
.PHONY: all
all:
	@echo "Please specify a chart name or use 'all-charts' target"

# 모든 차트 처리
.PHONY: all-charts
all-charts:
	@for chart in $(CHART_NAMES); do \
		echo "Processing chart: $$chart"; \
		$(MAKE) -f Makefile.$$chart.mk all; \
	done

# 각 차트별 타겟
.PHONY: $(CHART_NAMES)
$(CHART_NAMES):
	@echo "Processing chart: $@"
	@$(MAKE) -f Makefile.$@.mk all

# kind 클러스터 생성
.PHONY: kind-create
kind-create:
	@echo "Creating kind cluster: $(KIND_CLUSTER_NAME)"
	@$(KIND) create cluster --name $(KIND_CLUSTER_NAME) --config $(KIND_CONFIG)

# kind 클러스터 삭제
.PHONY: kind-delete
kind-delete:
	@echo "Deleting kind cluster: $(KIND_CLUSTER_NAME)"
	@$(KIND) delete cluster --name $(KIND_CLUSTER_NAME)

# gh-pages 원격 추적 브랜치 숨기기
.PHONY: git-hide-gh-pages
git-hide-gh-pages:
	@echo "Hiding gh-pages remote tracking branch from local git log"
	@git branch -r -D origin/gh-pages 2>/dev/null || echo "origin/gh-pages already hidden"

# gh-pages 원격 추적 브랜치 다시 가져오기
.PHONY: git-show-gh-pages
git-show-gh-pages:
	@echo "Fetching gh-pages remote tracking branch"
	@git fetch origin gh-pages:refs/remotes/origin/gh-pages

# 모든 차트 린트
.PHONY: lint
lint:
	@for chart in $(CHART_DIRS); do \
		echo "Linting chart: $$(basename $$chart)"; \
		$(HELM) lint $$chart; \
	done

# 차트 메타데이터 검증
.PHONY: validate-metadata
validate-metadata:
	@echo "Validating chart metadata consistency..."
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "Error: python3 is required for metadata validation"; \
		exit 1; \
	fi; \
	if ! python3 -c "import yaml" >/dev/null 2>&1; then \
		echo "Error: PyYAML is required. Install with: pip install pyyaml"; \
		exit 1; \
	fi; \
	python3 scripts/validate-chart-metadata.py

# 차트 메타데이터에서 Chart.yaml keywords 동기화
.PHONY: sync-keywords
sync-keywords:
	@echo "Syncing Chart.yaml keywords from charts-metadata.yaml..."
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "Error: python3 is required"; \
		exit 1; \
	fi; \
	if ! python3 -c "import yaml" >/dev/null 2>&1; then \
		echo "Error: PyYAML is required. Install with: pip install -r scripts/requirements.txt"; \
		exit 1; \
	fi; \
	python3 scripts/sync-chart-keywords.py

# 차트 메타데이터에서 Chart.yaml keywords 동기화 (dry-run)
.PHONY: sync-keywords-dry-run
sync-keywords-dry-run:
	@echo "Previewing Chart.yaml keywords sync..."
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "Error: python3 is required"; \
		exit 1; \
	fi; \
	if ! python3 -c "import yaml" >/dev/null 2>&1; then \
		echo "Error: PyYAML is required. Install with: pip install -r scripts/requirements.txt"; \
		exit 1; \
	fi; \
	python3 scripts/sync-chart-keywords.py --dry-run

# 모든 차트 빌드
.PHONY: build
build:
	@for chart in $(CHART_DIRS); do \
		echo "Building chart: $$(basename $$chart)"; \
		$(HELM) package $$chart; \
	done

# 모든 차트 템플릿 생성
.PHONY: template
template:
	@for chart in $(CHART_DIRS); do \
		echo "Templating chart: $$(basename $$chart)"; \
		$(HELM) template $$(basename $$chart) $$chart > $$(basename $$chart).yaml; \
	done

# 모든 차트 설치
.PHONY: install
install:
	@for chart in $(CHART_DIRS); do \
		echo "Installing chart: $$(basename $$chart)"; \
		$(HELM) install $$(basename $$chart) $$chart; \
	done

# 모든 차트 업그레이드
.PHONY: upgrade
upgrade:
	@for chart in $(CHART_DIRS); do \
		echo "Upgrading chart: $$(basename $$chart)"; \
		$(HELM) upgrade $$(basename $$chart) $$chart; \
	done

# 모든 차트 삭제
.PHONY: uninstall
uninstall:
	@for chart in $(CHART_DIRS); do \
		echo "Uninstalling chart: $$(basename $$chart)"; \
		$(HELM) uninstall $$(basename $$chart); \
	done

# 차트 의존성 업데이트
.PHONY: dependency-update
dependency-update:
	@for chart in $(CHART_DIRS); do \
		echo "Updating dependencies for chart: $$(basename $$chart)"; \
		$(HELM) dependency update $$chart; \
	done

# 차트 의존성 빌드
.PHONY: dependency-build
dependency-build:
	@for chart in $(CHART_DIRS); do \
		echo "Building dependencies for chart: $$(basename $$chart)"; \
		$(HELM) dependency build $$chart; \
	done

# 시나리오 기반 배포 타겟
.PHONY: install-home install-startup install-prod
install-home:
	@if [ -z "$(CHART)" ]; then \
		echo "Error: CHART variable is required"; \
		echo "Usage: make install-home CHART=<chart-name>"; \
		exit 1; \
	fi; \
	if [ ! -f "charts/$(CHART)/values-home-single.yaml" ]; then \
		echo "Error: values-home-single.yaml not found for chart $(CHART)"; \
		exit 1; \
	fi; \
	echo "Installing $(CHART) with home-single scenario"; \
	$(HELM) install $(CHART)-home charts/$(CHART) -f charts/$(CHART)/values-home-single.yaml

install-startup:
	@if [ -z "$(CHART)" ]; then \
		echo "Error: CHART variable is required"; \
		echo "Usage: make install-startup CHART=<chart-name>"; \
		exit 1; \
	fi; \
	if [ ! -f "charts/$(CHART)/values-startup-single.yaml" ]; then \
		echo "Error: values-startup-single.yaml not found for chart $(CHART)"; \
		exit 1; \
	fi; \
	echo "Installing $(CHART) with startup-single scenario"; \
	$(HELM) install $(CHART)-startup charts/$(CHART) -f charts/$(CHART)/values-startup-single.yaml

install-prod:
	@if [ -z "$(CHART)" ]; then \
		echo "Error: CHART variable is required"; \
		echo "Usage: make install-prod CHART=<chart-name>"; \
		exit 1; \
	fi; \
	if [ ! -f "charts/$(CHART)/values-prod-master-replica.yaml" ]; then \
		echo "Error: values-prod-master-replica.yaml not found for chart $(CHART)"; \
		exit 1; \
	fi; \
	echo "Installing $(CHART) with prod-master-replica scenario"; \
	$(HELM) install $(CHART)-prod charts/$(CHART) -f charts/$(CHART)/values-prod-master-replica.yaml

# 시나리오 파일 검증
.PHONY: validate-scenarios
validate-scenarios:
	@echo "Validating scenario files for all charts..."
	@for chart in $(CHART_DIRS); do \
		chart_name=$$(basename $$chart); \
		echo "Validating $$chart_name scenarios..."; \
		for scenario in home-single startup-single prod-master-replica; do \
			values_file="$$chart/values-$$scenario.yaml"; \
			if [ -f "$$values_file" ]; then \
				echo "  Linting $$scenario scenario..."; \
				$(HELM) lint $$chart -f $$values_file || exit 1; \
				echo "  Template validation for $$scenario..."; \
				$(HELM) template $$chart_name $$chart -f $$values_file --validate > /dev/null || exit 1; \
			fi; \
		done; \
	done
	@echo "All scenario files validated successfully!"

# 시나리오 파일 목록
.PHONY: list-scenarios
list-scenarios:
	@echo "Available scenario files:"
	@for chart in $(CHART_DIRS); do \
		chart_name=$$(basename $$chart); \
		echo ""; \
		echo "Chart: $$chart_name"; \
		for scenario in home-single startup-single prod-master-replica; do \
			values_file="$$chart/values-$$scenario.yaml"; \
			if [ -f "$$values_file" ]; then \
				echo "  ✓ $$scenario"; \
			else \
				echo "  ✗ $$scenario (missing)"; \
			fi; \
		done; \
	done

# 도움말
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all-charts       - Process all charts"
	@echo "  lint             - Run helm lint for all charts"
	@echo "  validate-metadata - Validate chart metadata consistency"
	@echo "  sync-keywords    - Sync Chart.yaml keywords from charts-metadata.yaml"
	@echo "  sync-keywords-dry-run - Preview keyword sync changes"
	@echo "  build            - Build all charts"
	@echo "  template         - Generate template for all charts"
	@echo "  install          - Install all charts"
	@echo "  upgrade          - Upgrade all charts"
	@echo "  uninstall        - Uninstall all charts"
	@echo "  dependency-update - Update dependencies for all charts"
	@echo "  dependency-build  - Build dependencies for all charts"
	@echo ""
	@echo "Scenario-based deployment:"
	@echo "  install-home     - Install chart with home-single scenario"
	@echo "                     Usage: make install-home CHART=<chart-name>"
	@echo "  install-startup  - Install chart with startup-single scenario"
	@echo "                     Usage: make install-startup CHART=<chart-name>"
	@echo "  install-prod     - Install chart with prod-master-replica scenario"
	@echo "                     Usage: make install-prod CHART=<chart-name>"
	@echo "  validate-scenarios - Validate all scenario files with helm lint/template"
	@echo "  list-scenarios   - List available scenario files for all charts"
	@echo ""
	@echo "Kind cluster management:"
	@echo "  kind-create      - Create kind cluster"
	@echo "  kind-delete      - Delete kind cluster"
	@echo ""
	@echo "Git utilities:"
	@echo "  git-hide-gh-pages - Hide gh-pages from local git log"
	@echo "  git-show-gh-pages - Show gh-pages in local git log"
	@echo ""
	@echo "Individual chart targets:"
	@for chart in $(CHART_NAMES); do \
		echo "  $$chart          - Process chart: $$chart"; \
		echo "                     (use 'make -f Makefile.$$chart.mk help' for more options)"; \
	done
