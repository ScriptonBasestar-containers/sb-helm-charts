{{/*
Expand the name of the chart.
*/}}
{{- define "prometheus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "prometheus.fullname" -}}
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
{{- define "prometheus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "prometheus.labels" -}}
helm.sh/chart: {{ include "prometheus.chart" . }}
{{ include "prometheus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "prometheus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "prometheus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "prometheus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "prometheus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the configmap to use
*/}}
{{- define "prometheus.configMapName" -}}
{{- if .Values.prometheus.existingConfigMap }}
{{- .Values.prometheus.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "prometheus.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Create the name of the headless service
*/}}
{{- define "prometheus.headlessServiceName" -}}
{{- printf "%s-headless" (include "prometheus.fullname" .) }}
{{- end }}
