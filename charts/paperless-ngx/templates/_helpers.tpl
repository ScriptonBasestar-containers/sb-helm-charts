{{/*
Expand the name of the chart.
*/}}
{{- define "paperless-ngx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "paperless-ngx.fullname" -}}
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
{{- define "paperless-ngx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "paperless-ngx.labels" -}}
helm.sh/chart: {{ include "paperless-ngx.chart" . }}
{{ include "paperless-ngx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "paperless-ngx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "paperless-ngx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "paperless-ngx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "paperless-ngx.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PostgreSQL host
*/}}
{{- define "paperless-ngx.postgresql.host" -}}
{{- if .Values.postgresql.external.enabled }}
{{- .Values.postgresql.external.host }}
{{- else }}
{{- fail "External PostgreSQL is required. Set postgresql.external.enabled=true and configure host." }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection string
*/}}
{{- define "paperless-ngx.postgresql.url" -}}
{{- $host := include "paperless-ngx.postgresql.host" . }}
{{- $port := .Values.postgresql.external.port }}
{{- $db := .Values.postgresql.external.database }}
{{- $user := .Values.postgresql.external.username }}
{{- $password := .Values.postgresql.external.password }}
{{- $sslMode := .Values.postgresql.external.sslMode }}
{{- printf "postgresql://%s:%s@%s:%d/%s?sslmode=%s" $user $password $host (int $port) $db $sslMode }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "paperless-ngx.redis.host" -}}
{{- if .Values.redis.external.enabled }}
{{- .Values.redis.external.host }}
{{- else }}
{{- fail "External Redis is required. Set redis.external.enabled=true and configure host." }}
{{- end }}
{{- end }}

{{/*
Redis URL
*/}}
{{- define "paperless-ngx.redis.url" -}}
{{- $host := include "paperless-ngx.redis.host" . }}
{{- $port := .Values.redis.external.port }}
{{- $password := .Values.redis.external.password }}
{{- $db := .Values.redis.external.database }}
{{- if $password }}
{{- printf "redis://:%s@%s:%d/%d" $password $host (int $port) (int $db) }}
{{- else }}
{{- printf "redis://%s:%d/%d" $host (int $port) (int $db) }}
{{- end }}
{{- end }}

{{/*
Validate required configuration
*/}}
{{- define "paperless-ngx.validateConfig" -}}
{{- if not .Values.paperless.adminPassword }}
  {{- fail "Admin password is required. Set paperless.adminPassword." }}
{{- end }}
{{- if not .Values.paperless.secretKey }}
  {{- fail "Secret key is required. Set paperless.secretKey (generate with: openssl rand -base64 32)." }}
{{- end }}
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
  {{- fail "External Redis is required. Set redis.external.enabled=true and configure host." }}
{{- end }}
{{- if not .Values.redis.external.host }}
  {{- fail "Redis host is required. Set redis.external.host." }}
{{- end }}
{{- end }}

{{/*
PVC name for consume
*/}}
{{- define "paperless-ngx.consume.pvcName" -}}
{{- if .Values.persistence.consume.existingClaim }}
{{- .Values.persistence.consume.existingClaim }}
{{- else }}
{{- printf "%s-consume" (include "paperless-ngx.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name for data
*/}}
{{- define "paperless-ngx.data.pvcName" -}}
{{- if .Values.persistence.data.existingClaim }}
{{- .Values.persistence.data.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "paperless-ngx.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name for media
*/}}
{{- define "paperless-ngx.media.pvcName" -}}
{{- if .Values.persistence.media.existingClaim }}
{{- .Values.persistence.media.existingClaim }}
{{- else }}
{{- printf "%s-media" (include "paperless-ngx.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name for export
*/}}
{{- define "paperless-ngx.export.pvcName" -}}
{{- if .Values.persistence.export.existingClaim }}
{{- .Values.persistence.export.existingClaim }}
{{- else }}
{{- printf "%s-export" (include "paperless-ngx.fullname" .) }}
{{- end }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "paperless-ngx.roleName" -}}
{{- printf "%s-role" (include "paperless-ngx.fullname" .) }}
{{- end }}

{{- define "paperless-ngx.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "paperless-ngx.fullname" .) }}
{{- end }}
