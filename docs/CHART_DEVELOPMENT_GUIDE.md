# Helm Chart Development Guide

This document defines the standard patterns and structures used across all charts in the sb-helm-charts repository. Use this as a reference when creating new charts or modifying existing ones.

## Chart Classification

Charts are classified into three categories based on their complexity and dependencies:

### 1. Standalone Services (No External Dependencies)
Services that don't require external databases.

**Examples:** redis, memcached, wireguard, browserless-chrome

**Characteristics:**
- No `postgresql`/`mysql`/`redis` external configuration blocks
- Self-contained data storage (in-memory or PVC)
- Simpler configuration management

### 2. Database-Dependent Services
Services that require external PostgreSQL, MySQL, or Redis.

**Examples:** keycloak, nextcloud, wordpress, devpi

**Characteristics:**
- Must have `postgresql.enabled: false` or `mysql.enabled: false`
- Must have `postgresql.external` or `mysql.external` configuration block
- InitContainers for database health checks
- Database connection validation in NOTES.txt

### 3. Message Brokers & Middleware
Specialized services with unique networking or clustering requirements.

**Examples:** rabbitmq

**Characteristics:**
- May expose multiple ports (AMQP, management UI, metrics)
- Often include clustering configuration
- May have specialized health check commands

## Standard Values.yaml Structure

All charts MUST follow this structure in order:

```yaml
# 1. Application-specific Configuration Block
{appname}:
  # Application-specific settings
  adminUser: ""
  adminPassword: ""
  config: |
    # Full configuration file content
  existingSecret: ""
  existingConfigMap: ""

# 2. External Dependencies (ALWAYS disabled)
postgresql:
  enabled: false  # MANDATORY: never use subcharts
  external:
    enabled: false
    host: ""
    port: 5432
    database: ""
    username: ""
    password: ""  # REQUIRED field - deployment fails if empty
    # Optional SSL/TLS configuration
    ssl:
      enabled: false
      mode: "require"  # disable, require, verify-ca, verify-full

mysql:
  enabled: false
  external:
    enabled: false
    host: ""
    port: 3306
    database: ""
    username: ""
    password: ""

redis:
  enabled: false
  external:
    enabled: false
    host: ""
    port: 6379
    database: 0
    password: ""

# 3. Persistence Configuration
persistence:
  enabled: true
  storageClass: ""
  size: "10Gi"
  accessMode: ReadWriteOnce
  existingClaim: ""
  reclaimPolicy: Retain  # Retain or Delete
  mountPath: /data  # Application-specific

# 4. Kubernetes Resources - Standard Section
replicaCount: 1

strategy:
  type: RollingUpdate  # or Recreate for PVC with single replica
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0

image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

# 5. Service Account
serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

# 6. Pod Configuration
podAnnotations: {}
podLabels: {}

podSecurityContext:
  fsGroup: 1000  # Application-specific UID/GID
  runAsUser: 1000
  runAsNonRoot: true

securityContext:
  capabilities:
    drop:
      - ALL
    add: []  # NET_ADMIN, SYS_MODULE, etc. if needed
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false

# 7. Service Configuration
service:
  type: ClusterIP  # ClusterIP, NodePort, LoadBalancer
  port: 8080
  targetPort: 8080  # or named port
  protocol: TCP  # TCP or UDP
  annotations: {}
  # NodePort-specific
  nodePort: ""
  # LoadBalancer-specific
  loadBalancerIP: ""
  loadBalancerSourceRanges: []

# 8. Ingress Configuration (optional, but include if applicable)
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: Prefix
  tls: []

# 9. Resources
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 128Mi

# 10. Health Probes
livenessProbe:
  enabled: true
  httpGet:  # or tcpSocket, exec
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1

readinessProbe:
  enabled: true
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

startupProbe:
  enabled: true
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5  # 5초로 변경 - 빠른 시작 감지
  timeoutSeconds: 5
  failureThreshold: 30  # 총 150초 (5초 * 30회) 대기
  successThreshold: 1

# 11. Autoscaling
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

# 12. Pod Disruption Budget
podDisruptionBudget:
  enabled: false
  minAvailable: 1
  # maxUnavailable: 1  # Use either minAvailable or maxUnavailable

# 13. Network Policy
networkPolicy:
  enabled: false
  ingress:
    - from:
      - podSelector: {}
      - namespaceSelector: {}
  egress:
    - to:
      - podSelector: {}

# 14. Monitoring
monitoring:
  enabled: false
  serviceMonitor:
    enabled: false
    interval: 30s
    scrapeTimeout: 10s
    labels: {}
    path: /metrics

# Optional: Metrics exporter sidecar
metrics:
  enabled: false
  image:
    repository: ""
    tag: ""
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
  port: 9121

# 15. Scheduling
nodeSelector: {}
tolerations: []
affinity: {}
priorityClassName: ""
topologySpreadConstraints: []

# 16. Extensibility
extraEnv: []
extraEnvFrom: []
extraVolumes: []
extraVolumeMounts: []
initContainers: []
lifecycle: {}
```

## Template Files Structure

### Required Templates

All charts MUST include these templates:

1. **_helpers.tpl** - Helper functions
2. **serviceaccount.yaml** - Service account
3. **service.yaml** - Kubernetes Service
4. **deployment.yaml** OR **statefulset.yaml** - Workload

### Recommended Templates

Include these for production-ready charts:

5. **configmap.yaml** - Configuration files
6. **secret.yaml** - Sensitive data
7. **pvc.yaml** - Persistent storage (if not using volumeClaimTemplates)
8. **NOTES.txt** - Post-install instructions

### Optional Templates

Include based on requirements:

9. **ingress.yaml** - HTTP(S) routing
10. **hpa.yaml** - Auto-scaling
11. **poddisruptionbudget.yaml** - Availability guarantees
12. **networkpolicy.yaml** - Network restrictions
13. **servicemonitor.yaml** - Prometheus metrics
14. **tests/** - Helm test resources

## Standard Helper Functions (_helpers.tpl)

Every chart MUST implement these helpers:

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "{chart}.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "{chart}.fullname" -}}
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
{{- define "{chart}.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "{chart}.labels" -}}
helm.sh/chart: {{ include "{chart}.chart" . }}
{{ include "{chart}.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "{chart}.selectorLabels" -}}
app.kubernetes.io/name: {{ include "{chart}.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "{chart}.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "{chart}.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

### Application-Specific Helpers

Add helpers for complex logic:

```yaml
{{/*
Database JDBC URL construction (for PostgreSQL-dependent charts)
*/}}
{{- define "{chart}.postgresql.jdbcUrl" -}}
{{- if .Values.postgresql.external.ssl.enabled }}
jdbc:postgresql://{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}?ssl=true&sslmode={{ .Values.postgresql.external.ssl.mode }}
{{- else }}
jdbc:postgresql://{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- end }}
{{- end }}

{{/*
Get password from secret or value
*/}}
{{- define "{chart}.password" -}}
{{- if .Values.{app}.existingSecret }}
{{- printf "valueFrom:\n  secretKeyRef:\n    name: %s\n    key: %s" .Values.{app}.existingSecret .Values.{app}.secretKeyName | nindent 2 }}
{{- else }}
{{- .Values.{app}.password | quote }}
{{- end }}
{{- end }}
```

## Deployment vs StatefulSet Decision Matrix

| Criteria | Use Deployment | Use StatefulSet |
|----------|----------------|-----------------|
| **Storage** | No storage or external storage | Local persistent storage per pod |
| **Identity** | Pods are interchangeable | Pods need stable network identity |
| **Scaling** | Scale up/down freely | Ordered scaling required |
| **Clustering** | No inter-pod communication | Cluster with pod-to-pod communication |
| **Examples** | wordpress, nextcloud, memcached, wireguard | redis (if clustering), keycloak (clustering) |

### StatefulSet Pattern

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "{chart}.fullname" . }}
spec:
  serviceName: {{ include "{chart}.fullname" . }}  # Headless service name
  replicas: {{ .Values.replicaCount }}
  podManagementPolicy: OrderedReady  # or Parallel
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      {{- include "{chart}.selectorLabels" . | nindent 6 }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: {{ .Values.persistence.storageClass | quote }}
        resources:
          requests:
            storage: {{ .Values.persistence.size | quote }}
```

### Deployment Pattern

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "{chart}.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: {{ .Values.strategy.type }}
    {{- if eq .Values.strategy.type "RollingUpdate" }}
    rollingUpdate:
      maxSurge: {{ .Values.strategy.rollingUpdate.maxSurge }}
      maxUnavailable: {{ .Values.strategy.rollingUpdate.maxUnavailable }}
    {{- end }}
  selector:
    matchLabels:
      {{- include "{chart}.selectorLabels" . | nindent 6 }}
  template:
    # ... pod template
```

## ConfigMap Pattern for Configuration Files

**CRITICAL:** Follow "configuration files over environment variables" philosophy.

### Full Configuration File Mount

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "{chart}.fullname" . }}
data:
  redis.conf: |
    {{- .Values.redis.config | nindent 4 }}

  # Or multiple files
  app.conf: |
    {{- .Values.app.config | nindent 4 }}

  nginx.conf: |
    {{- .Values.nginx.config | nindent 4 }}
```

### Volume Mount in Pod

```yaml
volumes:
  - name: config
    {{- if .Values.redis.existingConfigMap }}
    configMap:
      name: {{ .Values.redis.existingConfigMap }}
    {{- else }}
    configMap:
      name: {{ include "{chart}.fullname" . }}
    {{- end }}

volumeMounts:
  - name: config
    mountPath: /etc/redis/redis.conf
    subPath: redis.conf
    readOnly: true
```

## Secret Management Pattern

### Password/Credential Storage

```yaml
{{- if not .Values.{app}.existingSecret }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "{chart}.fullname" . }}
type: Opaque
data:
  {{- if .Values.{app}.password }}
  {{ .Values.{app}.secretKeyName }}: {{ .Values.{app}.password | b64enc | quote }}
  {{- end }}
{{- end }}
```

### Using Secret in Pod

```yaml
env:
  - name: APP_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ default (include "{chart}.fullname" .) .Values.{app}.existingSecret }}
        key: {{ .Values.{app}.secretKeyName }}
```

## InitContainer Patterns

### Database Health Check (Required for DB-dependent charts)

```yaml
initContainers:
  {{- if .Values.postgresql.external.enabled }}
  - name: wait-for-db
    image: postgres:16-alpine
    command:
      - sh
      - -c
      - |
        until pg_isready -h {{ .Values.postgresql.external.host }} \
                         -p {{ .Values.postgresql.external.port }} \
                         -U {{ .Values.postgresql.external.username }}; do
          echo "Waiting for PostgreSQL..."
          sleep 2
        done
    env:
      - name: PGPASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "{chart}.fullname" . }}-db
            key: password
  {{- end }}
```

### Configuration Preparation

```yaml
initContainers:
  - name: config-init
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    command:
      - sh
      - -c
      - |
        cp /tmp/config/app.conf /etc/app/app.conf
        # Perform any config transformations
        sed -i "s/PASSWORD/$APP_PASSWORD/g" /etc/app/app.conf
    volumeMounts:
      - name: config-template
        mountPath: /tmp/config
      - name: config
        mountPath: /etc/app
```

## Health Probe Patterns

### HTTP Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
    scheme: HTTP
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1
```

### TCP Probe

```yaml
livenessProbe:
  tcpSocket:
    port: {{ .Values.service.port }}
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
```

### Exec Probe

```yaml
livenessProbe:
  exec:
    command:
      - sh
      - -c
      - "redis-cli ping"
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Probe Timing Guidelines

| Probe Type | initialDelaySeconds | periodSeconds | failureThreshold |
|------------|---------------------|---------------|------------------|
| **Startup** | 5-10 | 5-10 | 20-30 |
| **Liveness** | 30 | 10 | 3-6 |
| **Readiness** | 5-10 | 5-10 | 3 |

## Service Patterns

### Standard ClusterIP Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "{chart}.fullname" . }}
  labels:
    {{- include "{chart}.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: {{ .Values.service.protocol }}
      name: {{ .Values.service.portName | default "http" }}
  selector:
    {{- include "{chart}.selectorLabels" . | nindent 4 }}
```

### Headless Service (for StatefulSet)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "{chart}.fullname" . }}-headless
spec:
  clusterIP: None  # Headless
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector:
    {{- include "{chart}.selectorLabels" . | nindent 4 }}
```

### Multi-Port Service

```yaml
spec:
  ports:
    - port: 5672
      targetPort: amqp
      protocol: TCP
      name: amqp
    - port: 15672
      targetPort: management
      protocol: TCP
      name: management
    - port: 15692
      targetPort: metrics
      protocol: TCP
      name: metrics
```

## NOTES.txt Template

Provide clear post-installation instructions:

```text
1. Get the application URL by running these commands:
{{- if .Values.ingress.enabled }}
  http{{ if $.Values.ingress.tls }}s{{ end }}://{{ (index .Values.ingress.hosts 0).host }}{{ (index (index .Values.ingress.hosts 0).paths 0).path }}
{{- else if contains "NodePort" .Values.service.type }}
  export NODE_PORT=$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "{chart}.fullname" . }})
  export NODE_IP=$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
{{- else if contains "LoadBalancer" .Values.service.type }}
  NOTE: It may take a few minutes for the LoadBalancer IP to be available.
  export SERVICE_IP=$(kubectl get svc --namespace {{ .Release.Namespace }} {{ include "{chart}.fullname" . }} --template "{{"{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}"}}")
  echo http://$SERVICE_IP:{{ .Values.service.port }}
{{- else if contains "ClusterIP" .Values.service.type }}
  export POD_NAME=$(kubectl get pods --namespace {{ .Release.Namespace }} -l "app.kubernetes.io/name={{ include "{chart}.name" . }},app.kubernetes.io/instance={{ .Release.Name }}" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace {{ .Release.Namespace }} port-forward $POD_NAME 8080:{{ .Values.service.port }}
  echo "Visit http://127.0.0.1:8080"
{{- end }}

2. Get the admin credentials:
  echo Username: {{ .Values.{app}.adminUser }}
  echo Password: $(kubectl get secret --namespace {{ .Release.Namespace }} {{ include "{chart}.fullname" . }} -o jsonpath="{.data.{app}-password}" | base64 -d)

{{- if and .Values.postgresql.enabled (not .Values.postgresql.external.enabled) }}
WARNING: PostgreSQL subchart is disabled. You must configure an external PostgreSQL database.
{{- end }}

{{- if .Values.postgresql.external.enabled }}
3. External PostgreSQL database:
  Host: {{ .Values.postgresql.external.host }}
  Database: {{ .Values.postgresql.external.database }}
{{- end }}

For more information, visit: https://github.com/scriptonbasestar-container/sb-helm-charts
```

## Chart.yaml Standard Fields

```yaml
apiVersion: v2
name: {chart-name}
description: Short description of the chart
type: application
version: 0.1.0  # Chart version (SemVer)
appVersion: "1.0.0"  # Application version
home: https://github.com/scriptonbasestar-container/sb-helm-charts
sources:
  - https://github.com/scriptonbasestar-container/sb-helm-charts
  - https://github.com/upstream/repository  # Upstream application repo
maintainers:
  - name: ScriptonBasestar
    email: archmagece@gmail.com
keywords:
  - keyword1
  - keyword2
annotations:
  category: Infrastructure
license: BSD-3-Clause  # Chart license
```

## Values Validation Pattern

Add validation for critical fields:

```yaml
{{- if and .Values.postgresql.external.enabled (not .Values.postgresql.external.password) }}
{{- fail "postgresql.external.password is required when using external PostgreSQL" }}
{{- end }}

{{- if and .Values.ingress.enabled (not .Values.ingress.hosts) }}
{{- fail "ingress.hosts is required when ingress is enabled" }}
{{- end }}
```

## Conditional Resource Creation

```yaml
{{- if .Values.{feature}.enabled }}
apiVersion: v1
kind: ConfigMap
# ...
{{- end }}
```

## Common Annotations Pattern

### Pod Annotations for Config/Secret Changes

```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

This triggers pod restart when ConfigMap or Secret changes.

## NetworkPolicy Pattern

```yaml
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "{chart}.fullname" . }}
spec:
  podSelector:
    matchLabels:
      {{- include "{chart}.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    {{- toYaml .Values.networkPolicy.ingress | nindent 4 }}
  egress:
    {{- toYaml .Values.networkPolicy.egress | nindent 4 }}
{{- end }}
```

## ServiceMonitor Pattern (Prometheus Operator)

```yaml
{{- if and .Values.monitoring.enabled .Values.monitoring.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "{chart}.fullname" . }}
  labels:
    {{- include "{chart}.labels" . | nindent 4 }}
    {{- with .Values.monitoring.serviceMonitor.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "{chart}.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: metrics
      path: {{ .Values.monitoring.serviceMonitor.path }}
      interval: {{ .Values.monitoring.serviceMonitor.interval }}
      scrapeTimeout: {{ .Values.monitoring.serviceMonitor.scrapeTimeout }}
{{- end }}
```

## Chart Testing Pattern

Create `templates/tests/test-connection.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "{chart}.fullname" . }}-test-connection"
  labels:
    {{- include "{chart}.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ include "{chart}.fullname" . }}:{{ .Values.service.port }}']
  restartPolicy: Never
```

## Advanced Patterns

This section documents advanced patterns found in production charts that go beyond the standard patterns.

### Multi-Port Service Pattern

**When to use:** Message brokers, clustered applications, services with separate management/metrics ports

**Examples:** rabbitmq (AMQP + management + metrics), keycloak (HTTP + management + clustering)

#### Values.yaml Configuration

```yaml
service:
  type: ClusterIP
  # Multi-port configuration
  ports:
    - name: amqp
      port: 5672
      targetPort: 5672
      protocol: TCP
    - name: management
      port: 15672
      targetPort: 15672
      protocol: TCP
    - name: metrics
      port: 15692
      targetPort: 15692
      protocol: TCP
  annotations: {}
```

#### Template Implementation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "{chart}.fullname" . }}
spec:
  type: {{ .Values.service.type }}
  ports:
    {{- range .Values.service.ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
      {{- if and (eq $.Values.service.type "NodePort") .nodePort }}
      nodePort: {{ .nodePort }}
      {{- end }}
    {{- end }}
  selector:
    {{- include "{chart}.selectorLabels" . | nindent 4 }}
```

#### Container Port Declaration

```yaml
ports:
  {{- range .Values.service.ports }}
  - name: {{ .name }}
    containerPort: {{ .targetPort }}
    protocol: {{ .protocol | default "TCP" }}
  {{- end }}
```

**Reference Implementation:** [charts/rabbitmq](../charts/rabbitmq/), [charts/keycloak](../charts/keycloak/)

---

### SSL/TLS External Database Connection

**When to use:** Production environments requiring encrypted database connections

**Example:** keycloak (PostgreSQL with SSL/TLS, mutual TLS support)

#### Values.yaml Configuration

```yaml
postgresql:
  enabled: false
  external:
    enabled: true
    host: "postgres.example.com"
    port: 5432
    database: "myapp"
    username: "myapp_user"
    password: ""  # Required

    # SSL/TLS configuration
    ssl:
      enabled: false

      # SSL modes:
      # - disable: No SSL connection (default)
      # - require: SSL without certificate validation
      # - verify-ca: Verify CA certificate (requires certificateSecret)
      # - verify-full: Verify CA + hostname match (requires certificateSecret)
      mode: "require"

      # Certificate secret for verify-ca/verify-full modes
      # Secret must contain CA certificate
      certificateSecret: ""
      rootCertKey: "ca.crt"  # Key in secret containing CA cert

      # Mutual TLS (mTLS) - optional
      # If provided, client certificate authentication is used
      clientCertKey: ""  # e.g., "tls.crt" - client certificate
      clientKeyKey: ""   # e.g., "tls.key" - client private key
```

#### Helper Function for JDBC URL Construction

```yaml
{{/*
PostgreSQL JDBC URL with SSL support
*/}}
{{- define "myapp.postgresql.jdbcUrl" -}}
{{- $ssl := .Values.postgresql.external.ssl -}}
{{- $baseUrl := printf "jdbc:postgresql://%s:%d/%s" .Values.postgresql.external.host (int .Values.postgresql.external.port) .Values.postgresql.external.database -}}
{{- if and $ssl $ssl.enabled -}}
  {{- if or (eq $ssl.mode "verify-ca") (eq $ssl.mode "verify-full") -}}
    {{- printf "%s?sslmode=%s&sslrootcert=/etc/postgresql/certs/%s" $baseUrl $ssl.mode $ssl.rootCertKey -}}
    {{- if and $ssl.clientCertKey $ssl.clientKeyKey -}}
      {{- printf "&sslcert=/etc/postgresql/certs/%s&sslkey=/etc/postgresql/certs/%s" $ssl.clientCertKey $ssl.clientKeyKey -}}
    {{- end -}}
  {{- else if eq $ssl.mode "require" -}}
    {{- printf "%s?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory" $baseUrl -}}
  {{- else -}}
    {{- $baseUrl -}}
  {{- end -}}
{{- else -}}
  {{- $baseUrl -}}
{{- end -}}
{{- end -}}
```

#### Volume Mount for Certificates

```yaml
{{- if and .Values.postgresql.external.ssl.enabled .Values.postgresql.external.ssl.certificateSecret }}
volumes:
  - name: postgresql-certs
    secret:
      secretName: {{ .Values.postgresql.external.ssl.certificateSecret }}
      defaultMode: 0400

volumeMounts:
  - name: postgresql-certs
    mountPath: /etc/postgresql/certs
    readOnly: true
{{- end }}
```

#### InitContainer Health Check with SSL

```yaml
initContainers:
  - name: wait-for-db
    image: postgres:16-alpine
    command:
      - sh
      - -c
      - |
        {{- if .Values.postgresql.external.ssl.enabled }}
        export PGSSLMODE={{ .Values.postgresql.external.ssl.mode }}
        {{- if .Values.postgresql.external.ssl.certificateSecret }}
        export PGSSLROOTCERT=/etc/postgresql/certs/{{ .Values.postgresql.external.ssl.rootCertKey }}
        {{- end }}
        {{- end }}
        until pg_isready -h {{ .Values.postgresql.external.host }} \
                         -p {{ .Values.postgresql.external.port }} \
                         -U {{ .Values.postgresql.external.username }}; do
          echo "Waiting for PostgreSQL..."
          sleep 2
        done
    env:
      - name: PGPASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "myapp.fullname" . }}-db
            key: password
    {{- if and .Values.postgresql.external.ssl.enabled .Values.postgresql.external.ssl.certificateSecret }}
    volumeMounts:
      - name: postgresql-certs
        mountPath: /etc/postgresql/certs
        readOnly: true
    {{- end }}
```

**Important Notes:**
- PostgreSQL JDBC driver uses different SSL parameters than psql CLI
- `require` mode uses `sslfactory=org.postgresql.ssl.NonValidatingFactory`
- `verify-ca`/`verify-full` modes require certificate files mounted in pod
- Client certificates (mTLS) must have empty default values to avoid always being included

**Reference Implementation:** [charts/keycloak](../charts/keycloak/)

---

### Metrics Exporter Sidecar Pattern

**When to use:** Applications without native Prometheus support that need metrics exported

**Example:** redis (redis_exporter sidecar)

#### Values.yaml Configuration

```yaml
# Main application metrics toggle
metrics:
  enabled: false

  # Exporter sidecar configuration
  image:
    repository: oliver006/redis_exporter
    tag: v1.55.0-alpine
    pullPolicy: IfNotPresent

  # Exporter resources (separate from main container)
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

  # Metrics port
  port: 9121

  # Exporter-specific configuration (optional)
  extraArgs: []
  # Example:
  # extraArgs:
  #   - "--redis.password-file=/secrets/redis-password"
```

#### Deployment Template with Sidecar

```yaml
spec:
  template:
    spec:
      containers:
        # Main application container
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - name: redis
              containerPort: 6379
          resources:
            {{- toYaml .Values.resources | nindent 12 }}

        # Metrics exporter sidecar
        {{- if .Values.metrics.enabled }}
        - name: metrics-exporter
          image: "{{ .Values.metrics.image.repository }}:{{ .Values.metrics.image.tag }}"
          imagePullPolicy: {{ .Values.metrics.image.pullPolicy }}
          ports:
            - name: metrics
              containerPort: {{ .Values.metrics.port }}
              protocol: TCP
          env:
            - name: REDIS_ADDR
              value: "localhost:6379"
            {{- if .Values.redis.password }}
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "redis.fullname" . }}
                  key: {{ .Values.redis.secretKeyName }}
            {{- end }}
          resources:
            {{- toYaml .Values.metrics.resources | nindent 12 }}
          {{- with .Values.metrics.extraArgs }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
        {{- end }}
```

#### Service with Metrics Port

```yaml
spec:
  ports:
    - name: redis
      port: {{ .Values.service.port }}
      targetPort: redis
    {{- if .Values.metrics.enabled }}
    - name: metrics
      port: {{ .Values.metrics.port }}
      targetPort: metrics
      protocol: TCP
    {{- end }}
```

#### ServiceMonitor for Prometheus Operator

```yaml
{{- if and .Values.metrics.enabled .Values.monitoring.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "redis.fullname" . }}
spec:
  selector:
    matchLabels:
      {{- include "redis.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: metrics
      path: /metrics
      interval: {{ .Values.monitoring.serviceMonitor.interval }}
{{- end }}
```

**Common Exporters:**
- Redis: `oliver006/redis_exporter`
- PostgreSQL: `prometheuscommunity/postgres_exporter`
- MySQL: `prom/mysqld-exporter`
- Memcached: `prom/memcached-exporter`
- MongoDB: `percona/mongodb_exporter`

**Reference Implementation:** [charts/redis](../charts/redis/)

---

### Multiple PVC Pattern

**When to use:** Applications with separate data/config/logs/apps storage requirements

**Example:** nextcloud (data, config, apps volumes), wordpress (content, uploads, themes)

#### Values.yaml Configuration

```yaml
persistence:
  enabled: true

  # Main data volume
  data:
    enabled: true
    storageClass: ""
    size: 8Gi
    accessMode: ReadWriteOnce
    mountPath: /var/www/html/data
    existingClaim: ""

  # Configuration volume
  config:
    enabled: true
    storageClass: ""
    size: 1Gi
    accessMode: ReadWriteOnce
    mountPath: /var/www/html/config
    existingClaim: ""

  # Custom apps/extensions volume (optional)
  apps:
    enabled: false
    storageClass: ""
    size: 2Gi
    accessMode: ReadWriteOnce
    mountPath: /var/www/html/custom_apps
    existingClaim: ""
```

#### PVC Template (Create Multiple PVCs)

```yaml
{{- if .Values.persistence.enabled }}
{{- range $name, $config := (dict "data" .Values.persistence.data "config" .Values.persistence.config "apps" .Values.persistence.apps) }}
{{- if $config.enabled }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "nextcloud.fullname" $ }}-{{ $name }}
  labels:
    {{- include "nextcloud.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $name }}
spec:
  accessModes:
    - {{ $config.accessMode }}
  {{- if $config.storageClass }}
  storageClassName: {{ $config.storageClass }}
  {{- end }}
  resources:
    requests:
      storage: {{ $config.size }}
{{- end }}
{{- end }}
{{- end }}
```

#### Volume Mounts in Deployment

```yaml
volumes:
  {{- if .Values.persistence.enabled }}
  {{- if .Values.persistence.data.enabled }}
  - name: data
    persistentVolumeClaim:
      claimName: {{ .Values.persistence.data.existingClaim | default (printf "%s-data" (include "nextcloud.fullname" .)) }}
  {{- end }}
  {{- if .Values.persistence.config.enabled }}
  - name: config
    persistentVolumeClaim:
      claimName: {{ .Values.persistence.config.existingClaim | default (printf "%s-config" (include "nextcloud.fullname" .)) }}
  {{- end }}
  {{- if .Values.persistence.apps.enabled }}
  - name: apps
    persistentVolumeClaim:
      claimName: {{ .Values.persistence.apps.existingClaim | default (printf "%s-apps" (include "nextcloud.fullname" .)) }}
  {{- end }}
  {{- end }}

volumeMounts:
  {{- if .Values.persistence.enabled }}
  {{- if .Values.persistence.data.enabled }}
  - name: data
    mountPath: {{ .Values.persistence.data.mountPath }}
  {{- end }}
  {{- if .Values.persistence.config.enabled }}
  - name: config
    mountPath: {{ .Values.persistence.config.mountPath }}
  {{- end }}
  {{- if .Values.persistence.apps.enabled }}
  - name: apps
    mountPath: {{ .Values.persistence.apps.mountPath }}
  {{- end }}
  {{- end }}
```

**When to Use:**
- **Single PVC:** Redis, Memcached, simple stateful apps
- **Multiple PVCs:** Nextcloud (data/config/apps), WordPress (content/uploads/themes), complex apps needing separation

**Benefits:**
- Independent backup/restore per volume type
- Different storage classes per volume (SSD for config, HDD for data)
- Separate retention policies
- Easier to migrate specific data types

**Reference Implementation:** [charts/nextcloud](../charts/nextcloud/)

---

### Special Security Capabilities Pattern

**When to use:** Network services (VPN), services requiring kernel module access, privileged operations

**Example:** wireguard (NET_ADMIN, SYS_MODULE, sysctls for IP forwarding)

#### Values.yaml Configuration

```yaml
# Pod security context with sysctls
podSecurityContext:
  # Required sysctls for IP forwarding and routing
  sysctls:
    - name: net.ipv4.ip_forward
      value: "1"
    - name: net.ipv4.conf.all.src_valid_mark
      value: "1"
  # Standard security
  fsGroup: 1000
  runAsNonRoot: false  # May need root for NET_ADMIN

# Container security context with specific capabilities
securityContext:
  capabilities:
    drop:
      - ALL
    add:
      # Required: Network interface management (create/configure wg0)
      - NET_ADMIN
      # Optional: Load kernel modules (only if wireguard module not pre-loaded)
      - SYS_MODULE
  # Avoid full privileged mode - use specific capabilities instead
  privileged: false
  allowPrivilegeEscalation: true  # Required for NET_ADMIN
```

#### Deployment Template

```yaml
spec:
  template:
    spec:
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
```

#### Common Capability Use Cases

| Capability | Use Case | Example |
|------------|----------|---------|
| `NET_ADMIN` | Network interface management, routing tables | WireGuard VPN, network proxies |
| `SYS_MODULE` | Load kernel modules | WireGuard (if module not pre-loaded) |
| `SYS_TIME` | System time modification | NTP servers, time synchronization |
| `CHOWN` | Change file ownership | Init containers, permission fixers |
| `DAC_OVERRIDE` | Bypass file permissions | Backup tools, file synchronization |
| `SETUID`/`SETGID` | Change user/group ID | sudo-like operations |
| `NET_BIND_SERVICE` | Bind to ports < 1024 | Web servers running as non-root |

**⚠️ Security Warning:**

```yaml
# NEVER use privileged: true unless absolutely necessary
# ❌ WRONG
securityContext:
  privileged: true

# ✅ CORRECT - Use specific capabilities
securityContext:
  privileged: false
  capabilities:
    add:
      - NET_ADMIN
      - SYS_MODULE
```

**Pod Sysctls for Network Configuration:**

```yaml
# Common sysctls for network services
podSecurityContext:
  sysctls:
    # IP forwarding (required for VPN, routing)
    - name: net.ipv4.ip_forward
      value: "1"

    # Source route verification
    - name: net.ipv4.conf.all.src_valid_mark
      value: "1"

    # TCP congestion control (performance tuning)
    - name: net.ipv4.tcp_congestion_control
      value: "bbr"

    # Maximum connections (high-traffic services)
    - name: net.core.somaxconn
      value: "65535"
```

**Kubernetes RBAC Requirement:**

For pods using `sysctls`, the PodSecurityPolicy or SecurityContext must allow unsafe sysctls:

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: wireguard-psp
spec:
  allowedUnsafeSysctls:
    - net.ipv4.ip_forward
    - net.ipv4.conf.all.src_valid_mark
  requiredDropCapabilities:
    - ALL
  allowedCapabilities:
    - NET_ADMIN
    - SYS_MODULE
```

**Reference Implementation:** [charts/wireguard](../charts/wireguard/)

---

### Configuration Mode Pattern

**When to use:** Supporting both manual (config file) and auto (environment variables) configuration

**Example:** wireguard (manual wg0.conf vs auto-generation)

#### Values.yaml Configuration

```yaml
wireguard:
  # Configuration mode: "manual" or "auto"
  # - manual: Use serverConfig (wg0.conf file) - RECOMMENDED
  # - auto: Use environment variables for auto-generation
  mode: "manual"

  # Manual mode: Direct wg0.conf configuration
  # Preferred method - follows "config files over environment variables" philosophy
  serverConfig: ""
  # Example:
  # serverConfig: |
  #   [Interface]
  #   Address = 10.13.13.1/24
  #   ListenPort = 51820
  #   PrivateKey = SERVER_PRIVATE_KEY_HERE
  #   PostUp = iptables -A FORWARD -i %i -j ACCEPT
  #   PostDown = iptables -D FORWARD -i %i -j ACCEPT
  #
  #   [Peer]
  #   PublicKey = PEER1_PUBLIC_KEY_HERE
  #   AllowedIPs = 10.13.13.2/32

  # Server private key (stored in Secret)
  # Required in manual mode
  privateKey: ""

  # Auto mode: Environment variable configuration
  # Convenient but uses environment variables instead of config files
  auto:
    # Public URL or IP for VPN server (required in auto mode)
    serverUrl: ""
    # WireGuard listen port
    serverPort: 51820
    # Number of peers to generate automatically
    peers: 5
    # Internal subnet for VPN network
    internalSubnet: "10.13.13.0"
    # DNS for peers ("auto" or specific IP)
    peerDns: "auto"
    # Allowed IPs for peers (full tunnel vs split tunnel)
    allowedIPs: "0.0.0.0/0, ::/0"
```

#### ConfigMap with Mode Selection

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "wireguard.fullname" . }}
data:
  {{- if eq .Values.wireguard.mode "manual" }}
  wg0.conf: |
    {{- .Values.wireguard.serverConfig | nindent 4 }}
  {{- end }}
```

#### Deployment with Mode-Specific Environment Variables

```yaml
env:
  # Auto mode environment variables
  {{- if eq .Values.wireguard.mode "auto" }}
  - name: SERVERURL
    value: {{ .Values.wireguard.auto.serverUrl | quote }}
  - name: SERVERPORT
    value: {{ .Values.wireguard.auto.serverPort | quote }}
  - name: PEERS
    value: {{ .Values.wireguard.auto.peers | quote }}
  - name: INTERNAL_SUBNET
    value: {{ .Values.wireguard.auto.internalSubnet | quote }}
  - name: PEERDNS
    value: {{ .Values.wireguard.auto.peerDns | quote }}
  - name: ALLOWEDIPS
    value: {{ .Values.wireguard.auto.allowedIPs | quote }}
  {{- end }}

volumeMounts:
  {{- if eq .Values.wireguard.mode "manual" }}
  - name: config
    mountPath: /config/wg0.conf
    subPath: wg0.conf
    readOnly: true
  {{- end }}
```

**When to Use Each Mode:**

| Mode | Best For | Advantages | Disadvantages |
|------|----------|------------|---------------|
| **Manual** | Production, version control | Full control, reproducible, no magic | Requires manual peer management |
| **Auto** | Quick setup, testing, demos | Fast setup, automatic peer generation | Less control, harder to debug |

**Trade-offs:**
- **Config Files (Manual):** Better for production, easier to version control, follows project philosophy
- **Environment Variables (Auto):** Faster initial setup, but harder to manage at scale

**Reference Implementation:** [charts/wireguard](../charts/wireguard/)

---

### Checksum Annotations for Automatic Restarts

**When to use:** Always, for any application using ConfigMap or Secret

**Why:** Kubernetes doesn't automatically restart pods when ConfigMap/Secret changes. Adding checksum annotations forces pod restart.

#### Template Implementation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
spec:
  template:
    metadata:
      annotations:
        # Generate checksum from ConfigMap - pod restarts if ConfigMap changes
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}

        # Generate checksum from Secret - pod restarts if Secret changes
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}

        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
```

#### How It Works

1. Helm calculates SHA256 hash of ConfigMap/Secret contents
2. Hash is added as pod annotation
3. If ConfigMap/Secret changes, hash changes
4. Changed annotation triggers rolling update

#### Multiple ConfigMaps/Secrets

```yaml
annotations:
  checksum/config-app: {{ include (print $.Template.BasePath "/configmap-app.yaml") . | sha256sum }}
  checksum/config-nginx: {{ include (print $.Template.BasePath "/configmap-nginx.yaml") . | sha256sum }}
  checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
  checksum/secret-db: {{ include (print $.Template.BasePath "/secret-db.yaml") . | sha256sum }}
```

**Alternative Approaches:**

1. **Reloader Operator** (third-party):
   ```yaml
   annotations:
     reloader.stakater.com/auto: "true"
   ```

2. **ConfigMap/Secret as Environment Variables** (NOT RECOMMENDED):
   - Automatic updates, but violates "config files over env vars" philosophy
   - Only works for simple key-value configs

**Best Practice:** Always use checksum annotations for production charts

**Reference Implementation:** [charts/keycloak](../charts/keycloak/), [charts/redis](../charts/redis/)

---

## Anti-Patterns to Avoid

### ❌ Don't Use Subcharts for Databases

```yaml
# WRONG
dependencies:
  - name: postgresql
    version: 12.x.x
    repository: https://charts.bitnami.com/bitnami
```

```yaml
# CORRECT
postgresql:
  enabled: false
  external:
    enabled: true
    host: "postgres.example.com"
```

### ❌ Don't Override Environment Variables Instead of Config Files

```yaml
# WRONG - Complex env var mappings
env:
  - name: REDIS_MAXMEMORY
    value: "256mb"
  - name: REDIS_MAXMEMORY_POLICY
    value: "allkeys-lru"
```

```yaml
# CORRECT - Use config file
redis:
  config: |
    maxmemory 256mb
    maxmemory-policy allkeys-lru
```

### ❌ Don't Create Multiple ConfigMaps for Single Config File

```yaml
# WRONG
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-2
```

```yaml
# CORRECT - Single ConfigMap with multiple files
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "chart.fullname" . }}
data:
  app.conf: |
    {{ .Values.app.config | nindent 4 }}
  nginx.conf: |
    {{ .Values.nginx.config | nindent 4 }}
```

### ❌ Don't Use Default Values for Sensitive Data

```yaml
# WRONG
postgresql:
  external:
    password: "changeme"  # Never set default passwords
```

```yaml
# CORRECT
postgresql:
  external:
    password: ""  # Empty - deployment will fail if not provided
```

## Resource Naming Conventions

- **ServiceAccount:** `{release-name}-{chart-name}`
- **Secret:** `{release-name}-{chart-name}` or `{release-name}-{chart-name}-{purpose}`
- **ConfigMap:** `{release-name}-{chart-name}` or `{release-name}-{chart-name}-{purpose}`
- **PVC:** `{release-name}-{chart-name}-data` or `data-{release-name}-{chart-name}-0` (StatefulSet)
- **Service:** `{release-name}-{chart-name}` (main), `{release-name}-{chart-name}-headless` (StatefulSet)
- **Ingress:** `{release-name}-{chart-name}`

All names should:
- Be lowercase
- Use hyphens for separation
- Be ≤63 characters
- Use `include "{chart}.fullname"` helper

## Dependency Order for Template Rendering

Helm renders templates alphabetically, but some resources should be created before others:

1. **Namespace** (if creating)
2. **ServiceAccount, RBAC**
3. **Secret, ConfigMap**
4. **PVC** (before Deployment/StatefulSet)
5. **Service** (especially headless, before StatefulSet)
6. **Deployment/StatefulSet**
7. **HPA, PDB**
8. **Ingress**
9. **NetworkPolicy**
10. **ServiceMonitor**

Use `helm.sh/hook: pre-install` if strict ordering is needed.

## Chart Versioning Policy

- **Chart version** (`version`): Follows SemVer, incremented on chart changes
  - MAJOR: Breaking changes (removed values, renamed templates)
  - MINOR: New features (new values, new templates)
  - PATCH: Bug fixes, documentation updates

- **App version** (`appVersion`): Matches upstream Docker image version
  - Update when changing `image.tag` default value
  - Use semantic version format when possible

## Documentation Requirements

Every chart MUST include:

1. **README.md** with:
   - Application description
   - Prerequisites (external databases, etc.)
   - Installation instructions
   - Configuration parameters table
   - Examples

2. **values.yaml** with:
   - Inline comments for all fields
   - Example values commented out
   - Clear section headers

3. **NOTES.txt** with:
   - Access instructions
   - Credential retrieval commands
   - Next steps

4. **values-example.yaml** (optional but recommended):
   - Production-ready configuration examples
   - Multiple scenarios (basic, HA, etc.)

## Makefile Integration

Each chart should have:

1. **Makefile.{chart}.mk** with:
   - Standard targets from `Makefile.common.mk`
   - Application-specific operational commands
   - Help documentation

Example operational commands:
- Database operations: `{app}-db-test`, `{app}-backup`, `{app}-restore`
- Application CLI: `{app}-cli CMD="..."`
- Status checks: `{app}-status`, `{app}-logs`
- Port forwarding: `{app}-port-forward`

## Summary Checklist for New Charts

When creating a new chart, ensure:

- [ ] Chart follows standard directory structure
- [ ] `values.yaml` follows section ordering
- [ ] External dependencies are marked `enabled: false`
- [ ] All standard helpers are implemented in `_helpers.tpl`
- [ ] ConfigMap uses full config files (not env vars)
- [ ] Secrets support `existingSecret` pattern
- [ ] Health probes are configured appropriately
- [ ] InitContainer checks database health (if applicable)
- [ ] NOTES.txt provides clear access instructions
- [ ] Chart.yaml includes all standard fields
- [ ] README.md documents all configuration options
- [ ] Makefile.{chart}.mk exists with operational commands
- [ ] ServiceAccount is created by default
- [ ] Pod security context drops all capabilities
- [ ] Resources have limits and requests
- [ ] PVC reclaim policy is `Retain` for production
- [ ] Deployment/StatefulSet choice is appropriate
- [ ] Template includes checksum annotations for config/secret changes
