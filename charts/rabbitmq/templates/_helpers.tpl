{{/*
Expand the name of the chart.
*/}}
{{- define "rabbitmq.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rabbitmq.fullname" -}}
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
{{- define "rabbitmq.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rabbitmq.labels" -}}
helm.sh/chart: {{ include "rabbitmq.chart" . }}
{{ include "rabbitmq.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rabbitmq.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rabbitmq.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "rabbitmq.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "rabbitmq.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "rabbitmq.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
Return the admin username
*/}}
{{- define "rabbitmq.adminUsername" -}}
{{- if .Values.rabbitmq.admin.existingSecret.enabled }}
{{- print "" }}
{{- else }}
{{- .Values.rabbitmq.admin.username }}
{{- end }}
{{- end }}

{{/*
Return the admin password secret name
*/}}
{{- define "rabbitmq.secretName" -}}
{{- if .Values.rabbitmq.admin.existingSecret.enabled }}
{{- .Values.rabbitmq.admin.existingSecret.secretName }}
{{- else }}
{{- include "rabbitmq.fullname" . }}
{{- end }}
{{- end }}

{{/*
Return the admin username secret key
*/}}
{{- define "rabbitmq.usernameKey" -}}
{{- if .Values.rabbitmq.admin.existingSecret.enabled }}
{{- .Values.rabbitmq.admin.existingSecret.usernameKey }}
{{- else }}
{{- print "username" }}
{{- end }}
{{- end }}

{{/*
Return the admin password secret key
*/}}
{{- define "rabbitmq.passwordKey" -}}
{{- if .Values.rabbitmq.admin.existingSecret.enabled }}
{{- .Values.rabbitmq.admin.existingSecret.passwordKey }}
{{- else }}
{{- print "password" }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name
*/}}
{{- define "rabbitmq.configMapName" -}}
{{- if .Values.rabbitmq.existingConfigMap }}
{{- .Values.rabbitmq.existingConfigMap }}
{{- else }}
{{- include "rabbitmq.fullname" . }}
{{- end }}
{{- end }}

{{/*
Return the PVC name
*/}}
{{- define "rabbitmq.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- include "rabbitmq.fullname" . }}
{{- end }}
{{- end }}
