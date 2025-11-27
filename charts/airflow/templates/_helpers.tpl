{{/*
Expand the name of the chart.
*/}}
{{- define "airflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "airflow.fullname" -}}
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
{{- define "airflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "airflow.labels" -}}
helm.sh/chart: {{ include "airflow.chart" . }}
{{ include "airflow.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "airflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "airflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels
*/}}
{{- define "airflow.componentLabels" -}}
{{ include "airflow.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component-specific selector labels
*/}}
{{- define "airflow.componentSelectorLabels" -}}
{{ include "airflow.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "airflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "airflow.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for Airflow credentials
*/}}
{{- define "airflow.secretName" -}}
{{- if .Values.airflow.existingSecret }}
{{- .Values.airflow.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "airflow.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ConfigMap name for Airflow configuration
*/}}
{{- define "airflow.configMapName" -}}
{{- if .Values.airflow.existingConfigMap }}
{{- .Values.airflow.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "airflow.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection URL
*/}}
{{- define "airflow.postgresql.url" -}}
{{- if .Values.postgresql.external.enabled -}}
postgresql://{{ .Values.postgresql.external.username }}:{{ .Values.postgresql.external.password }}@{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- else -}}
postgresql://airflow:airflow@{{ include "airflow.fullname" . }}-postgresql:5432/airflow
{{- end -}}
{{- end }}

{{/*
Webserver URL (for Airflow connections and callbacks)
*/}}
{{- define "airflow.webserver.url" -}}
{{- if .Values.ingress.enabled -}}
{{- if .Values.ingress.tls -}}
https://{{ (index .Values.ingress.hosts 0).host }}
{{- else -}}
http://{{ (index .Values.ingress.hosts 0).host }}
{{- end -}}
{{- else -}}
http://{{ include "airflow.fullname" . }}-webserver:8080
{{- end -}}
{{- end }}

{{/*
Fernet key - generate if not provided
*/}}
{{- define "airflow.fernetKey" -}}
{{- if .Values.airflow.fernetKey }}
{{- .Values.airflow.fernetKey }}
{{- else }}
{{- randAlphaNum 32 | b64enc }}
{{- end }}
{{- end }}

{{/*
Webserver secret key - generate if not provided
*/}}
{{- define "airflow.webserverSecretKey" -}}
{{- if .Values.airflow.webserverSecretKey }}
{{- .Values.airflow.webserverSecretKey }}
{{- else }}
{{- randAlphaNum 32 | b64enc }}
{{- end }}
{{- end }}

{{/*
Create the name of the RBAC role to use
*/}}
{{- define "airflow.roleName" -}}
{{- printf "%s" (include "airflow.fullname" .) }}
{{- end }}

{{/*
Create the name of the RBAC role binding to use
*/}}
{{- define "airflow.roleBindingName" -}}
{{- printf "%s" (include "airflow.fullname" .) }}
{{- end }}
