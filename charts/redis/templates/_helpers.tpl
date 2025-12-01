{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redis.fullname" -}}
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
{{- define "redis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.chart" . }}
{{ include "redis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get Redis password
*/}}
{{- define "redis.password" -}}
{{- if .Values.redis.password }}
{{- .Values.redis.password }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "redis.roleName" -}}
{{- printf "%s-role" (include "redis.fullname" .) }}
{{- end }}

{{- define "redis.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "redis.fullname" .) }}
{{- end }}

{{/*
Determine deployment mode with backward compatibility.
Supported modes: standalone, replica.
Sentinel/cluster are not implemented and fail fast to avoid silent misconfigurations.
*/}}
{{- define "redis.effectiveMode" -}}
{{- $mode := default "" .Values.mode | lower | trim -}}
{{- if and (not $mode) .Values.replication.enabled -}}
  {{- $mode = "replica" -}}
{{- else if not $mode -}}
  {{- $mode = "standalone" -}}
{{- end -}}
{{- if eq $mode "standalone" }}
  {{- if .Values.replication.enabled }}
    {{- fail "mode=standalone conflicts with replication.enabled=true. Remove replication.enabled or set mode=replica." }}
  {{- end }}
{{- end }}
{{- if or (eq $mode "sentinel") (eq $mode "cluster") }}
  {{- fail (printf "redis.mode=%s is not implemented in this chart. Supported modes: standalone, replica. See values-prod-sentinel.yaml / values-prod-cluster.yaml for alternatives." $mode) }}
{{- end }}
{{- if and (ne $mode "standalone") (ne $mode "replica") }}
  {{- fail (printf "Unsupported redis.mode=%s. Valid modes: standalone, replica." $mode) }}
{{- end }}
{{- $mode -}}
{{- end }}

{{/* Boolean helpers for template readability */}}
{{- define "redis.isReplicaMode" -}}
{{- eq (include "redis.effectiveMode" .) "replica" -}}
{{- end }}

{{/*
Validate value combinations early.
*/}}
{{- define "redis.validateValues" -}}
{{- $mode := include "redis.effectiveMode" . -}}
{{- if eq $mode "replica" }}
  {{- $replicas := int (default 0 .Values.replication.replicas) -}}
  {{- if lt $replicas 0 }}
    {{- fail "replication.replicas must be >= 0 when mode=replica (0 = master only, keeps replica-ready wiring)" }}
  {{- end -}}
{{- end -}}
{{- end }}
