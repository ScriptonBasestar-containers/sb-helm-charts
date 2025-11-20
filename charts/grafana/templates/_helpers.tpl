{{/*
Expand the name of the chart.
*/}}
{{- define "grafana.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "grafana.fullname" -}}
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
{{- define "grafana.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "grafana.labels" -}}
helm.sh/chart: {{ include "grafana.chart" . }}
{{ include "grafana.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "grafana.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "grafana.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "grafana.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the secret name
*/}}
{{- define "grafana.secretName" -}}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "grafana.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name
*/}}
{{- define "grafana.configMapName" -}}
{{- if .Values.grafana.existingConfigMap }}
{{- .Values.grafana.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "grafana.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return Grafana admin password
*/}}
{{- define "grafana.adminPassword" -}}
{{- if .Values.grafana.adminPassword }}
{{- .Values.grafana.adminPassword }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Return Grafana secret key
*/}}
{{- define "grafana.secretKey" -}}
{{- if .Values.grafana.secretKey }}
{{- .Values.grafana.secretKey }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Return database connection URL
*/}}
{{- define "grafana.databaseUrl" -}}
{{- if .Values.database.external.enabled }}
{{- if eq .Values.database.external.type "postgres" }}
{{- printf "postgres://%s:%s@%s:%d/%s?sslmode=disable" .Values.database.external.username .Values.database.external.password .Values.database.external.host (int .Values.database.external.port) .Values.database.external.database }}
{{- else if eq .Values.database.external.type "mysql" }}
{{- printf "%s:%s@tcp(%s:%d)/%s" .Values.database.external.username .Values.database.external.password .Values.database.external.host (int .Values.database.external.port) .Values.database.external.database }}
{{- end }}
{{- else }}
{{- printf "sqlite3:///var/lib/grafana/grafana.db" }}
{{- end }}
{{- end }}

{{/*
Return the external URL
*/}}
{{- define "grafana.externalUrl" -}}
{{- if .Values.grafana.externalUrl }}
{{- .Values.grafana.externalUrl }}
{{- else if .Values.ingress.enabled }}
{{- if .Values.ingress.tls }}
{{- printf "https://%s" (index .Values.ingress.hosts 0) }}
{{- else }}
{{- printf "http://%s" (index .Values.ingress.hosts 0) }}
{{- end }}
{{- else }}
{{- printf "http://localhost:3000" }}
{{- end }}
{{- end }}
