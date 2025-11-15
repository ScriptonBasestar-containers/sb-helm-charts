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

# 도움말
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all-charts       - Process all charts"
	@echo "  lint             - Run helm lint for all charts"
	@echo "  build            - Build all charts"
	@echo "  template         - Generate template for all charts"
	@echo "  install          - Install all charts"
	@echo "  upgrade          - Upgrade all charts"
	@echo "  uninstall        - Uninstall all charts"
	@echo "  dependency-update - Update dependencies for all charts"
	@echo "  dependency-build  - Build dependencies for all charts"
	@echo "  kind-create      - Create kind cluster"
	@echo "  kind-delete      - Delete kind cluster"
	@echo "  git-hide-gh-pages - Hide gh-pages from local git log"
	@echo "  git-show-gh-pages - Show gh-pages in local git log"
	@echo ""
	@echo "Individual chart targets:"
	@for chart in $(CHART_NAMES); do \
		echo "  $$chart          - Process chart: $$chart"; \
		echo "                     (use 'make -f Makefile.$$chart.mk help' for more options)"; \
	done
