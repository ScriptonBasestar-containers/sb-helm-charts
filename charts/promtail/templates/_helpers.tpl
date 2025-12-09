{{/*
Expand the name of the chart.
*/}}
{{- define "promtail.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "promtail.fullname" -}}
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
{{- define "promtail.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "promtail.labels" -}}
helm.sh/chart: {{ include "promtail.chart" . }}
{{ include "promtail.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "promtail.selectorLabels" -}}
app.kubernetes.io/name: {{ include "promtail.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "promtail.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "promtail.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the configmap to use
*/}}
{{- define "promtail.configMapName" -}}
{{- if .Values.promtail.existingConfigMap }}
{{- .Values.promtail.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "promtail.fullname" .) }}
{{- end }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "promtail.clusterRoleName" -}}
{{- printf "%s-clusterrole" (include "promtail.fullname" .) }}
{{- end }}

{{- define "promtail.clusterRoleBindingName" -}}
{{- printf "%s-clusterrolebinding" (include "promtail.fullname" .) }}
{{- end }}
