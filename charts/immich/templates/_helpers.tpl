{{/*
Expand the name of the chart.
*/}}
{{- define "immich.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "immich.fullname" -}}
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
{{- define "immich.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "immich.labels" -}}
helm.sh/chart: {{ include "immich.chart" . }}
{{ include "immich.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "immich.selectorLabels" -}}
app.kubernetes.io/name: {{ include "immich.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Server component labels
*/}}
{{- define "immich.server.labels" -}}
{{ include "immich.labels" . }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Server selector labels
*/}}
{{- define "immich.server.selectorLabels" -}}
{{ include "immich.selectorLabels" . }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Machine Learning component labels
*/}}
{{- define "immich.ml.labels" -}}
{{ include "immich.labels" . }}
app.kubernetes.io/component: machine-learning
{{- end }}

{{/*
Machine Learning selector labels
*/}}
{{- define "immich.ml.selectorLabels" -}}
{{ include "immich.selectorLabels" . }}
app.kubernetes.io/component: machine-learning
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "immich.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "immich.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PostgreSQL host URL
*/}}
{{- define "immich.postgresql.host" -}}
{{- if .Values.postgresql.external.enabled }}
{{- .Values.postgresql.external.host }}
{{- else }}
{{- fail "PostgreSQL external host is required" }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection URL
*/}}
{{- define "immich.postgresql.url" -}}
{{- $host := include "immich.postgresql.host" . -}}
{{- $port := .Values.postgresql.external.port -}}
{{- $db := .Values.postgresql.external.database -}}
{{- $user := .Values.postgresql.external.username -}}
{{- $password := .Values.postgresql.external.password -}}
{{- $sslmode := .Values.postgresql.external.sslmode -}}
{{- printf "postgresql://%s:%s@%s:%d/%s?sslmode=%s" $user $password $host ($port | int) $db $sslmode }}
{{- end }}

{{/*
Redis host URL
*/}}
{{- define "immich.redis.host" -}}
{{- if .Values.redis.external.enabled }}
{{- .Values.redis.external.host }}
{{- else }}
{{- fail "Redis external host is required" }}
{{- end }}
{{- end }}

{{/*
Redis connection URL
*/}}
{{- define "immich.redis.url" -}}
{{- $host := include "immich.redis.host" . -}}
{{- $port := .Values.redis.external.port -}}
{{- $db := .Values.redis.external.database -}}
{{- if .Values.redis.external.password }}
{{- $password := .Values.redis.external.password -}}
{{- printf "ioredis://:%s@%s:%d/%d" $password $host ($port | int) ($db | int) }}
{{- else }}
{{- printf "ioredis://%s:%d/%d" $host ($port | int) ($db | int) }}
{{- end }}
{{- end }}

{{/*
Machine Learning image with acceleration suffix
*/}}
{{- define "immich.ml.image" -}}
{{- $repo := .Values.immich.machineLearning.image.repository -}}
{{- $tag := .Values.immich.machineLearning.image.tag | default .Chart.AppVersion -}}
{{- $accel := .Values.immich.machineLearning.acceleration -}}
{{- if and (ne $accel "none") (ne $accel "") }}
{{- printf "%s:%s-%s" $repo $tag $accel }}
{{- else }}
{{- printf "%s:%s" $repo $tag }}
{{- end }}
{{- end }}

{{/*
Validate configuration
*/}}
{{- define "immich.validateConfig" -}}
{{- if not .Values.postgresql.external.enabled }}
  {{- fail "External PostgreSQL is required. Set postgresql.external.enabled=true and configure connection details." }}
{{- end }}
{{- if not .Values.postgresql.external.host }}
  {{- fail "PostgreSQL host is required. Set postgresql.external.host." }}
{{- end }}
{{- if not .Values.postgresql.external.password }}
  {{- fail "PostgreSQL password is required. Set postgresql.external.password." }}
{{- end }}
{{- if not .Values.redis.external.enabled }}
  {{- fail "External Redis is required. Set redis.external.enabled=true and configure connection details." }}
{{- end }}
{{- if not .Values.redis.external.host }}
  {{- fail "Redis host is required. Set redis.external.host." }}
{{- end }}
{{- end }}

{{/*
PVC name for library
*/}}
{{- define "immich.library.pvcName" -}}
{{- if .Values.persistence.library.existingClaim }}
{{- .Values.persistence.library.existingClaim }}
{{- else }}
{{- printf "%s-library" (include "immich.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name for ML model cache
*/}}
{{- define "immich.ml.pvcName" -}}
{{- printf "%s-ml-cache" (include "immich.fullname" .) }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "immich.roleName" -}}
{{- printf "%s-role" (include "immich.fullname" .) }}
{{- end }}

{{- define "immich.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "immich.fullname" .) }}
{{- end }}
