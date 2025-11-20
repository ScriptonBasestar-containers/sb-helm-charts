{{/*
Expand the name of the chart.
*/}}
{{- define "harbor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "harbor.fullname" -}}
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
{{- define "harbor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "harbor.labels" -}}
helm.sh/chart: {{ include "harbor.chart" . }}
{{ include "harbor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "harbor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "harbor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels
*/}}
{{- define "harbor.componentLabels" -}}
{{- $component := . -}}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "harbor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "harbor.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the secret name
*/}}
{{- define "harbor.secretName" -}}
{{- if .Values.harbor.existingSecret }}
{{- .Values.harbor.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "harbor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name
*/}}
{{- define "harbor.configMapName" -}}
{{- if .Values.harbor.existingConfigMap }}
{{- .Values.harbor.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "harbor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return Harbor admin password
*/}}
{{- define "harbor.adminPassword" -}}
{{- if .Values.harbor.adminPassword }}
{{- .Values.harbor.adminPassword }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Return Harbor secret key
*/}}
{{- define "harbor.secretKey" -}}
{{- if .Values.harbor.secretKey }}
{{- .Values.harbor.secretKey }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Return the PostgreSQL connection string
*/}}
{{- define "harbor.postgresql.connection" -}}
{{- printf "postgres://%s:%s@%s:%d/%s?sslmode=disable" .Values.postgresql.external.username .Values.postgresql.external.password .Values.postgresql.external.host (int .Values.postgresql.external.port) .Values.postgresql.external.database }}
{{- end }}

{{/*
Return the Redis connection URL
*/}}
{{- define "harbor.redis.url" -}}
{{- if .Values.redis.external.password }}
{{- printf "redis://:%s@%s:%d/0" .Values.redis.external.password .Values.redis.external.host (int .Values.redis.external.port) }}
{{- else }}
{{- printf "redis://%s:%d/0" .Values.redis.external.host (int .Values.redis.external.port) }}
{{- end }}
{{- end }}

{{/*
Return the external URL
*/}}
{{- define "harbor.externalURL" -}}
{{- if .Values.harbor.externalURL }}
{{- .Values.harbor.externalURL }}
{{- else }}
{{- printf "https://%s" (index .Values.ingress.hosts 0) }}
{{- end }}
{{- end }}

{{/*
Component service names
*/}}
{{- define "harbor.core" -}}
{{- printf "%s-core" (include "harbor.fullname" .) }}
{{- end }}

{{- define "harbor.portal" -}}
{{- printf "%s-portal" (include "harbor.fullname" .) }}
{{- end }}

{{- define "harbor.registry" -}}
{{- printf "%s-registry" (include "harbor.fullname" .) }}
{{- end }}

{{- define "harbor.jobservice" -}}
{{- printf "%s-jobservice" (include "harbor.fullname" .) }}
{{- end }}
