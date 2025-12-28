{{/*
Expand the name of the chart.
*/}}
{{- define "thanos-query-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "thanos-query-frontend.fullname" -}}
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
{{- define "thanos-query-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "thanos-query-frontend.labels" -}}
helm.sh/chart: {{ include "thanos-query-frontend.chart" . }}
{{ include "thanos-query-frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: query-frontend
app.kubernetes.io/part-of: thanos
{{- end }}

{{/*
Selector labels
*/}}
{{- define "thanos-query-frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "thanos-query-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "thanos-query-frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "thanos-query-frontend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "thanos-query-frontend.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:v%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Return the name of the Role
*/}}
{{- define "thanos-query-frontend.roleName" -}}
{{- include "thanos-query-frontend.fullname" . -}}
{{- end }}

{{/*
Return the name of the RoleBinding
*/}}
{{- define "thanos-query-frontend.roleBindingName" -}}
{{- include "thanos-query-frontend.fullname" . -}}
{{- end }}

{{/*
Build the cache configuration flags
*/}}
{{- define "thanos-query-frontend.cacheFlags" -}}
{{- if .Values.thanos.queryFrontend.cache.enabled }}
{{- if eq .Values.thanos.queryFrontend.cache.type "in-memory" }}
- --query-range.response-cache-config=
    type: IN-MEMORY
    config:
      max_size: {{ .Values.thanos.queryFrontend.cache.inMemory.maxSize | quote }}
      max_size_items: {{ .Values.thanos.queryFrontend.cache.inMemory.maxItems }}
      validity: 0s
{{- else if eq .Values.thanos.queryFrontend.cache.type "memcached" }}
- --query-range.response-cache-config=
    type: MEMCACHED
    config:
      addresses: {{ .Values.thanos.queryFrontend.cache.memcached.addresses | toJson }}
      timeout: {{ .Values.thanos.queryFrontend.cache.memcached.timeout | quote }}
      max_idle_connections: {{ .Values.thanos.queryFrontend.cache.memcached.maxIdleConnections }}
{{- end }}
{{- end }}
{{- end }}
