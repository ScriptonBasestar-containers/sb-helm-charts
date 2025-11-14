# 공통 변수 정의
HELM ?= helm
KIND ?= kind
KUBECTL ?= kubectl
KIND_CLUSTER_NAME ?= sb-helm-charts
KIND_CONFIG ?= kind-config.yaml

# Kubernetes 운영 변수
NAMESPACE ?= default
RELEASE_NAME ?= $(CHART_NAME)

# 차트 관련 변수 (각 차트별 Makefile에서 재정의)
CHART_NAME ?= $(error CHART_NAME is not set)
CHART_DIR ?= charts/$(CHART_NAME)

# 기본 타겟
.PHONY: all
all: lint build

# 차트 린트
.PHONY: lint
lint:
	@echo "Linting chart: $(CHART_NAME)"
	@$(HELM) lint $(CHART_DIR)

# 차트 빌드
.PHONY: build
build:
	@echo "Building chart: $(CHART_NAME)"
	@$(HELM) package $(CHART_DIR)

# 차트 템플릿 생성
.PHONY: template
template:
	@echo "Templating chart: $(CHART_NAME)"
	@$(HELM) template $(CHART_NAME) $(CHART_DIR) > $(CHART_NAME).yaml

# 차트 설치
.PHONY: install
install:
	@echo "Installing chart: $(CHART_NAME)"
	@$(HELM) install $(CHART_NAME) $(CHART_DIR)

# 차트 업그레이드
.PHONY: upgrade
upgrade:
	@echo "Upgrading chart: $(CHART_NAME)"
	@$(HELM) upgrade $(CHART_NAME) $(CHART_DIR)

# 차트 삭제
.PHONY: uninstall
uninstall:
	@echo "Uninstalling chart: $(CHART_NAME)"
	@$(HELM) uninstall $(CHART_NAME)

# 차트 의존성 업데이트
.PHONY: dependency-update
dependency-update:
	@echo "Updating dependencies for chart: $(CHART_NAME)"
	@$(HELM) dependency update $(CHART_DIR)

# 차트 의존성 빌드
.PHONY: dependency-build
dependency-build:
	@echo "Building dependencies for chart: $(CHART_NAME)"
	@$(HELM) dependency build $(CHART_DIR)

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

# 도움말
.PHONY: help
help:
	@echo "Available targets for $(CHART_NAME):"
	@echo "  all              - Run lint and build"
	@echo "  lint             - Run helm lint"
	@echo "  build            - Build chart"
	@echo "  template         - Generate template"
	@echo "  install          - Install chart"
	@echo "  upgrade          - Upgrade chart"
	@echo "  uninstall        - Uninstall chart"
	@echo "  dependency-update - Update dependencies"
	@echo "  dependency-build  - Build dependencies"
	@echo "  kind-create      - Create kind cluster"
	@echo "  kind-delete      - Delete kind cluster" 