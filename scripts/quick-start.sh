#!/bin/bash
# quick-start.sh: Common deployment scenarios for sb-helm-charts
# Usage: ./quick-start.sh [scenario] [namespace]
# Examples:
#   ./quick-start.sh monitoring prod-monitoring
#   ./quick-start.sh mlops mlops
#   ./quick-start.sh --list

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helm repository
HELM_REPO_NAME="sb-charts"
HELM_REPO_URL="https://scriptonbasestar-container.github.io/sb-helm-charts"

# Print functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    if ! command -v helm &> /dev/null; then
        error "Helm is not installed. Please install Helm 3.8+"
    fi

    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl"
    fi

    # Check kubectl connection
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Check your kubeconfig"
    fi

    success "All prerequisites met"
}

# Setup Helm repository
setup_helm_repo() {
    info "Setting up Helm repository..."

    if helm repo list | grep -q "${HELM_REPO_NAME}"; then
        helm repo update "${HELM_REPO_NAME}"
    else
        helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}"
    fi

    success "Helm repository configured"
}

# Create namespace if not exists
create_namespace() {
    local ns="$1"
    if ! kubectl get namespace "${ns}" &> /dev/null; then
        info "Creating namespace: ${ns}"
        kubectl create namespace "${ns}"
    else
        info "Namespace ${ns} already exists"
    fi
}

# Install chart with values file
install_chart() {
    local chart="$1"
    local release="$2"
    local namespace="$3"
    local values_file="${4:-}"

    info "Installing ${chart} as ${release}..."

    local cmd="helm install ${release} ${HELM_REPO_NAME}/${chart} -n ${namespace}"

    if [[ -n "${values_file}" && -f "${values_file}" ]]; then
        cmd="${cmd} -f ${values_file}"
    fi

    if eval "${cmd}"; then
        success "Installed ${release}"
    else
        error "Failed to install ${release}"
    fi
}

# Wait for pods to be ready
wait_for_pods() {
    local namespace="$1"
    local timeout="${2:-300}"

    info "Waiting for pods in ${namespace} to be ready (timeout: ${timeout}s)..."
    kubectl wait --for=condition=ready pod --all -n "${namespace}" --timeout="${timeout}s" || true
}

# Scenario: Full Monitoring Stack
deploy_monitoring() {
    local namespace="${1:-monitoring}"
    local examples_dir="$(dirname "$0")/../examples/full-monitoring-stack"

    info "Deploying Full Monitoring Stack to namespace: ${namespace}"
    echo "Components: Prometheus, Loki, Grafana, Alertmanager, Promtail, Node Exporter, Kube State Metrics, Blackbox Exporter, Pushgateway"
    echo ""

    create_namespace "${namespace}"

    # Order matters for dependencies
    local charts=(
        "prometheus:prometheus"
        "loki:loki"
        "alertmanager:alertmanager"
        "node-exporter:node-exporter"
        "kube-state-metrics:kube-state-metrics"
        "blackbox-exporter:blackbox-exporter"
        "promtail:promtail"
        "pushgateway:pushgateway"
        "grafana:grafana"
    )

    for entry in "${charts[@]}"; do
        local chart="${entry%%:*}"
        local release="${entry##*:}"
        local values_file="${examples_dir}/values-${chart}.yaml"

        if [[ -f "${values_file}" ]]; then
            install_chart "${chart}" "${release}" "${namespace}" "${values_file}"
        else
            install_chart "${chart}" "${release}" "${namespace}"
        fi
    done

    wait_for_pods "${namespace}"

    echo ""
    success "Monitoring stack deployed!"
    echo ""
    echo "Access Grafana:"
    echo "  kubectl port-forward -n ${namespace} svc/grafana 3000:80"
    echo "  Password: kubectl get secret -n ${namespace} grafana -o jsonpath='{.data.admin-password}' | base64 -d"
    echo ""
    echo "Access Prometheus:"
    echo "  kubectl port-forward -n ${namespace} svc/prometheus 9090:9090"
}

# Scenario: MLOps Stack
deploy_mlops() {
    local namespace="${1:-mlops}"
    local examples_dir="$(dirname "$0")/../examples/mlops-stack"

    info "Deploying MLOps Stack to namespace: ${namespace}"
    echo "Components: MinIO (S3 storage), PostgreSQL (metadata), MLflow (tracking)"
    echo ""

    create_namespace "${namespace}"

    # Order: Storage -> Database -> MLflow
    local charts=(
        "minio:minio"
        "postgresql:postgresql"
        "mlflow:mlflow"
    )

    for entry in "${charts[@]}"; do
        local chart="${entry%%:*}"
        local release="${entry##*:}"
        local values_file="${examples_dir}/values-${chart}.yaml"

        if [[ -f "${values_file}" ]]; then
            install_chart "${chart}" "${release}" "${namespace}" "${values_file}"
        else
            install_chart "${chart}" "${release}" "${namespace}"
        fi
    done

    wait_for_pods "${namespace}"

    echo ""
    success "MLOps stack deployed!"
    echo ""
    echo "Access MLflow UI:"
    echo "  kubectl port-forward -n ${namespace} svc/mlflow 5000:5000"
    echo ""
    echo "Access MinIO Console:"
    echo "  kubectl port-forward -n ${namespace} svc/minio 9001:9001"
}

# Scenario: Database Stack (PostgreSQL + pgAdmin + Redis)
deploy_database() {
    local namespace="${1:-database}"

    info "Deploying Database Stack to namespace: ${namespace}"
    echo "Components: PostgreSQL, pgAdmin, Redis"
    echo ""

    create_namespace "${namespace}"

    local charts=(
        "postgresql:postgresql"
        "redis:redis"
        "pgadmin:pgadmin"
    )

    for entry in "${charts[@]}"; do
        local chart="${entry%%:*}"
        local release="${entry##*:}"
        install_chart "${chart}" "${release}" "${namespace}"
    done

    wait_for_pods "${namespace}"

    echo ""
    success "Database stack deployed!"
    echo ""
    echo "Access pgAdmin:"
    echo "  kubectl port-forward -n ${namespace} svc/pgadmin 8080:80"
}

# Scenario: Nextcloud Production
deploy_nextcloud() {
    local namespace="${1:-nextcloud}"
    local examples_dir="$(dirname "$0")/../examples/nextcloud-production"

    info "Deploying Nextcloud (Production) to namespace: ${namespace}"
    echo "Components: PostgreSQL, Redis, Nextcloud"
    echo ""

    create_namespace "${namespace}"

    # External deps first
    install_chart "postgresql" "postgresql" "${namespace}"
    install_chart "redis" "redis" "${namespace}"

    # Wait for deps
    sleep 10
    wait_for_pods "${namespace}" 180

    # Then Nextcloud
    local values_file="${examples_dir}/values-nextcloud.yaml"
    if [[ -f "${values_file}" ]]; then
        install_chart "nextcloud" "nextcloud" "${namespace}" "${values_file}"
    else
        install_chart "nextcloud" "nextcloud" "${namespace}"
    fi

    wait_for_pods "${namespace}"

    echo ""
    success "Nextcloud deployed!"
    echo ""
    echo "Access Nextcloud:"
    echo "  kubectl port-forward -n ${namespace} svc/nextcloud 8080:80"
}

# Scenario: WordPress Homeserver
deploy_wordpress() {
    local namespace="${1:-wordpress}"
    local examples_dir="$(dirname "$0")/../examples/wordpress-homeserver"

    info "Deploying WordPress (Homeserver) to namespace: ${namespace}"
    echo "Components: MySQL, WordPress"
    echo ""

    create_namespace "${namespace}"

    # MySQL first
    install_chart "mysql" "mysql" "${namespace}"

    # Wait for MySQL
    sleep 10
    wait_for_pods "${namespace}" 180

    # Then WordPress
    local values_file="${examples_dir}/values-wordpress.yaml"
    if [[ -f "${values_file}" ]]; then
        install_chart "wordpress" "wordpress" "${namespace}" "${values_file}"
    else
        install_chart "wordpress" "wordpress" "${namespace}"
    fi

    wait_for_pods "${namespace}"

    echo ""
    success "WordPress deployed!"
    echo ""
    echo "Access WordPress:"
    echo "  kubectl port-forward -n ${namespace} svc/wordpress 8080:80"
}

# Scenario: Message Queue Stack
deploy_messaging() {
    local namespace="${1:-messaging}"

    info "Deploying Message Queue Stack to namespace: ${namespace}"
    echo "Components: RabbitMQ, Kafka"
    echo ""

    create_namespace "${namespace}"

    local charts=(
        "rabbitmq:rabbitmq"
        "kafka:kafka"
    )

    for entry in "${charts[@]}"; do
        local chart="${entry%%:*}"
        local release="${entry##*:}"
        install_chart "${chart}" "${release}" "${namespace}"
    done

    wait_for_pods "${namespace}"

    echo ""
    success "Message queue stack deployed!"
    echo ""
    echo "Access RabbitMQ Management:"
    echo "  kubectl port-forward -n ${namespace} svc/rabbitmq 15672:15672"
}

# Show available scenarios
show_scenarios() {
    echo "ScriptonBasestar Helm Charts - Quick Start"
    echo ""
    echo "Available scenarios:"
    echo ""
    echo "  monitoring    Full observability stack (Prometheus, Loki, Grafana, etc.)"
    echo "  mlops         Machine learning operations (MLflow, MinIO, PostgreSQL)"
    echo "  database      Database stack (PostgreSQL, Redis, pgAdmin)"
    echo "  nextcloud     Nextcloud production setup (with PostgreSQL, Redis)"
    echo "  wordpress     WordPress homeserver setup (with MySQL)"
    echo "  messaging     Message queue stack (RabbitMQ, Kafka)"
    echo ""
    echo "Usage:"
    echo "  $0 <scenario> [namespace]"
    echo ""
    echo "Examples:"
    echo "  $0 monitoring                    # Deploy to 'monitoring' namespace"
    echo "  $0 monitoring prod-monitoring    # Deploy to 'prod-monitoring' namespace"
    echo "  $0 mlops                         # Deploy to 'mlops' namespace"
    echo ""
    echo "Options:"
    echo "  --list, -l    Show this help"
    echo "  --help, -h    Show this help"
}

# Main
main() {
    local scenario="${1:-}"
    local namespace="${2:-}"

    case "${scenario}" in
        --list|-l|--help|-h|"")
            show_scenarios
            exit 0
            ;;
        monitoring)
            check_prerequisites
            setup_helm_repo
            deploy_monitoring "${namespace:-monitoring}"
            ;;
        mlops)
            check_prerequisites
            setup_helm_repo
            deploy_mlops "${namespace:-mlops}"
            ;;
        database)
            check_prerequisites
            setup_helm_repo
            deploy_database "${namespace:-database}"
            ;;
        nextcloud)
            check_prerequisites
            setup_helm_repo
            deploy_nextcloud "${namespace:-nextcloud}"
            ;;
        wordpress)
            check_prerequisites
            setup_helm_repo
            deploy_wordpress "${namespace:-wordpress}"
            ;;
        messaging)
            check_prerequisites
            setup_helm_repo
            deploy_messaging "${namespace:-messaging}"
            ;;
        *)
            error "Unknown scenario: ${scenario}. Use --list to see available scenarios."
            ;;
    esac
}

main "$@"
