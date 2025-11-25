#!/bin/bash
# generate-chart.sh: Generate a new Helm chart with standard structure
# Usage: ./generate-chart.sh <chart-name> [app-version] [--type=application|infrastructure]
# Examples:
#   ./generate-chart.sh myapp 1.0.0
#   ./generate-chart.sh mydb 8.0.0 --type=infrastructure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parse arguments
CHART_NAME=""
APP_VERSION="1.0.0"
CHART_TYPE="application"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type=*)
            CHART_TYPE="${1#*=}"
            shift
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [[ -z "$CHART_NAME" ]]; then
                CHART_NAME="$1"
            else
                APP_VERSION="$1"
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CHART_NAME" ]]; then
    echo "Usage: $0 <chart-name> [app-version] [--type=application|infrastructure]"
    echo ""
    echo "Examples:"
    echo "  $0 myapp 1.0.0"
    echo "  $0 mydb 8.0.0 --type=infrastructure"
    exit 1
fi

if [[ ! "$CHART_TYPE" =~ ^(application|infrastructure)$ ]]; then
    error "Invalid chart type: $CHART_TYPE. Must be 'application' or 'infrastructure'"
fi

# Script directory and chart path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CHART_DIR="${REPO_ROOT}/charts/${CHART_NAME}"

# Check if chart already exists
if [[ -d "$CHART_DIR" ]]; then
    error "Chart directory already exists: $CHART_DIR"
fi

info "Creating chart: $CHART_NAME (type: $CHART_TYPE, appVersion: $APP_VERSION)"

# Create directory structure
mkdir -p "${CHART_DIR}/templates/tests"

# Generate Chart.yaml
cat > "${CHART_DIR}/Chart.yaml" << EOF
apiVersion: v2
name: ${CHART_NAME}
description: A Helm chart for ${CHART_NAME}
type: ${CHART_TYPE}

# Artifact Hub metadata
annotations:
  artifacthub.io/license: BSD-3-Clause
  artifacthub.io/changes: |
    - kind: added
      description: Initial chart release
  artifacthub.io/prerelease: "true"
  artifacthub.io/recommendations: |
    - url: https://github.com/scriptonbasestar-container/sb-helm-charts/blob/master/docs/CHART_DEVELOPMENT_GUIDE.md
      description: Chart Development Guide
  artifacthub.io/links: |
    - name: Chart Source
      url: https://github.com/scriptonbasestar-container/sb-helm-charts/tree/master/charts/${CHART_NAME}

# Project URLs
home: https://github.com/scriptonbasestar-container/sb-helm-charts
# icon: https://example.com/icon.png
sources:
  - https://github.com/scriptonbasestar-container/sb-helm-charts

# Keywords for discoverability
keywords:
  - ${CHART_NAME}

# Maintainers
maintainers:
  - name: archmagece
    email: archmagece@users.noreply.github.com

version: 0.1.0
appVersion: "${APP_VERSION}"
EOF

# Generate values.yaml
cat > "${CHART_DIR}/values.yaml" << EOF
# Default values for ${CHART_NAME}

replicaCount: 1

image:
  repository: ${CHART_NAME}
  pullPolicy: IfNotPresent
  # Overrides the image tag whose default is the chart appVersion.
  tag: ""

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

# ${CHART_NAME} configuration
${CHART_NAME}:
  # Add application-specific configuration here
  config: {}

# External database configuration (if applicable)
# postgresql:
#   external:
#     enabled: false
#     host: ""
#     port: 5432
#     database: "${CHART_NAME}"
#     username: "${CHART_NAME}"
#     password: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsNonRoot: true

securityContext:
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: false
  allowPrivilegeEscalation: false

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: ""
  annotations: {}
    # kubernetes.io/ingress.class: nginx
    # kubernetes.io/tls-acme: "true"
  hosts:
    - host: ${CHART_NAME}.local
      paths:
        - path: /
          pathType: Prefix
  tls: []
  #  - secretName: ${CHART_NAME}-tls
  #    hosts:
  #      - ${CHART_NAME}.local

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

persistence:
  enabled: true
  storageClass: ""
  accessMode: ReadWriteOnce
  size: 1Gi
  annotations: {}

livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  # targetMemoryUtilizationPercentage: 80

podDisruptionBudget:
  enabled: false
  minAvailable: 1
  # maxUnavailable: 1

serviceMonitor:
  enabled: false
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  labels: {}

networkPolicy:
  enabled: false

nodeSelector: {}

tolerations: []

affinity: {}
EOF

# Generate _helpers.tpl
cat > "${CHART_DIR}/templates/_helpers.tpl" << 'EOF'
{{/*
Expand the name of the chart.
*/}}
{{- define "CHART_NAME.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "CHART_NAME.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "CHART_NAME.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "CHART_NAME.labels" -}}
helm.sh/chart: {{ include "CHART_NAME.chart" . }}
{{ include "CHART_NAME.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "CHART_NAME.selectorLabels" -}}
app.kubernetes.io/name: {{ include "CHART_NAME.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "CHART_NAME.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "CHART_NAME.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
EOF

# Replace CHART_NAME placeholder in helpers
sed -i "s/CHART_NAME/${CHART_NAME}/g" "${CHART_DIR}/templates/_helpers.tpl"

# Generate deployment.yaml
cat > "${CHART_DIR}/templates/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "${CHART_NAME}.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "${CHART_NAME}.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "${CHART_NAME}.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- if .Values.persistence.enabled }}
          volumeMounts:
            - name: data
              mountPath: /data
          {{- end }}
      {{- if .Values.persistence.enabled }}
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ include "${CHART_NAME}.fullname" . }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
EOF

# Generate service.yaml
cat > "${CHART_DIR}/templates/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "${CHART_NAME}.selectorLabels" . | nindent 4 }}
EOF

# Generate serviceaccount.yaml
cat > "${CHART_DIR}/templates/serviceaccount.yaml" << EOF
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "${CHART_NAME}.serviceAccountName" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
EOF

# Generate ingress.yaml
cat > "${CHART_DIR}/templates/ingress.yaml" << EOF
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "${CHART_NAME}.fullname" \$ }}
                port:
                  number: {{ \$.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
EOF

# Generate pvc.yaml
cat > "${CHART_DIR}/templates/pvc.yaml" << EOF
{{- if .Values.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
  {{- with .Values.persistence.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  accessModes:
    - {{ .Values.persistence.accessMode }}
  {{- if .Values.persistence.storageClass }}
  storageClassName: {{ .Values.persistence.storageClass }}
  {{- end }}
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
{{- end }}
EOF

# Generate hpa.yaml
cat > "${CHART_DIR}/templates/hpa.yaml" << EOF
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "${CHART_NAME}.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
EOF

# Generate poddisruptionbudget.yaml
cat > "${CHART_DIR}/templates/poddisruptionbudget.yaml" << EOF
{{- if .Values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  {{- if .Values.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.podDisruptionBudget.minAvailable }}
  {{- end }}
  {{- if .Values.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.podDisruptionBudget.maxUnavailable }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "${CHART_NAME}.selectorLabels" . | nindent 6 }}
{{- end }}
EOF

# Generate servicemonitor.yaml
cat > "${CHART_DIR}/templates/servicemonitor.yaml" << EOF
{{- if .Values.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
    {{- with .Values.serviceMonitor.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  endpoints:
    - port: http
      path: {{ .Values.serviceMonitor.path }}
      interval: {{ .Values.serviceMonitor.interval }}
      scrapeTimeout: {{ .Values.serviceMonitor.scrapeTimeout }}
  selector:
    matchLabels:
      {{- include "${CHART_NAME}.selectorLabels" . | nindent 6 }}
{{- end }}
EOF

# Generate networkpolicy.yaml
cat > "${CHART_DIR}/templates/networkpolicy.yaml" << EOF
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "${CHART_NAME}.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 80
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
{{- end }}
EOF

# Generate NOTES.txt
cat > "${CHART_DIR}/templates/NOTES.txt" << EOF
1. Get the application URL by running these commands:
{{- if .Values.ingress.enabled }}
{{- range \$host := .Values.ingress.hosts }}
  {{- range .paths }}
  http{{ if \$.Values.ingress.tls }}s{{ end }}://{{ \$host.host }}{{ .path }}
  {{- end }}
{{- end }}
{{- else if contains "NodePort" .Values.service.type }}
  export NODE_PORT=\$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "${CHART_NAME}.fullname" . }})
  export NODE_IP=\$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://\$NODE_IP:\$NODE_PORT
{{- else if contains "LoadBalancer" .Values.service.type }}
     NOTE: It may take a few minutes for the LoadBalancer IP to be available.
           You can watch the status of by running 'kubectl get --namespace {{ .Release.Namespace }} svc -w {{ include "${CHART_NAME}.fullname" . }}'
  export SERVICE_IP=\$(kubectl get svc --namespace {{ .Release.Namespace }} {{ include "${CHART_NAME}.fullname" . }} --template "{{"{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}"}}")
  echo http://\$SERVICE_IP:{{ .Values.service.port }}
{{- else if contains "ClusterIP" .Values.service.type }}
  export POD_NAME=\$(kubectl get pods --namespace {{ .Release.Namespace }} -l "app.kubernetes.io/name={{ include "${CHART_NAME}.name" . }},app.kubernetes.io/instance={{ .Release.Name }}" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=\$(kubectl get pod --namespace {{ .Release.Namespace }} \$POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace {{ .Release.Namespace }} port-forward \$POD_NAME 8080:\$CONTAINER_PORT
{{- end }}
EOF

# Generate test file
cat > "${CHART_DIR}/templates/tests/test-connection.yaml" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "${CHART_NAME}.fullname" . }}-test-connection"
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ include "${CHART_NAME}.fullname" . }}:{{ .Values.service.port }}']
  restartPolicy: Never
EOF

# Generate values-example.yaml
cat > "${CHART_DIR}/values-example.yaml" << EOF
# Example values for production deployment

replicaCount: 1

image:
  repository: ${CHART_NAME}
  tag: "${APP_VERSION}"

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi

persistence:
  enabled: true
  size: 10Gi

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: ${CHART_NAME}.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: ${CHART_NAME}-tls
      hosts:
        - ${CHART_NAME}.example.com
EOF

# Validate the generated chart
info "Validating generated chart..."
if helm lint "${CHART_DIR}" > /dev/null 2>&1; then
    success "Chart validation passed"
else
    warn "Chart validation has warnings (this is expected for a new chart)"
    helm lint "${CHART_DIR}" 2>&1 | head -20
fi

# Summary
success "Chart '${CHART_NAME}' created successfully at ${CHART_DIR}"
echo ""
echo "Generated files:"
find "${CHART_DIR}" -type f | sort | while read -r f; do
    echo "  - ${f#${CHART_DIR}/}"
done
echo ""
echo "Next steps:"
echo "  1. Update Chart.yaml with proper description, icon, and keywords"
echo "  2. Customize values.yaml for your application"
echo "  3. Modify templates as needed for your application"
echo "  4. Add chart to charts-metadata.yaml:"
echo "     make validate-metadata"
echo "     make sync-keywords"
echo "  5. Run: helm lint charts/${CHART_NAME}"
echo "  6. Test: helm template ${CHART_NAME} charts/${CHART_NAME}"
echo ""
