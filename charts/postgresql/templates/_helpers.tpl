{{/*
Expand the name of the chart.
*/}}
{{- define "postgresql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "postgresql.fullname" -}}
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
{{- define "postgresql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "postgresql.labels" -}}
helm.sh/chart: {{ include "postgresql.chart" . }}
{{ include "postgresql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "postgresql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "postgresql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for PostgreSQL credentials
*/}}
{{- define "postgresql.secretName" -}}
{{- if .Values.postgresql.existingSecret }}
{{- .Values.postgresql.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "postgresql.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ConfigMap name for PostgreSQL configuration
*/}}
{{- define "postgresql.configMapName" -}}
{{- if .Values.postgresql.existingConfigMap }}
{{- .Values.postgresql.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "postgresql.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Headless service name (for replication)
*/}}
{{- define "postgresql.headlessServiceName" -}}
{{- printf "%s-headless" (include "postgresql.fullname" .) }}
{{- end }}

{{/*
Primary service name
*/}}
{{- define "postgresql.primaryServiceName" -}}
{{- include "postgresql.fullname" . }}
{{- end }}

{{/*
Get PostgreSQL password
*/}}
{{- define "postgresql.password" -}}
{{- if .Values.postgresql.password }}
{{- .Values.postgresql.password }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Get replication password
*/}}
{{- define "postgresql.replicationPassword" -}}
{{- if .Values.postgresql.replication.password }}
{{- .Values.postgresql.replication.password }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}
