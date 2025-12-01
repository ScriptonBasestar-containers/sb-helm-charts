{{/*
Expand the name of the chart.
*/}}
{{- define "tempo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tempo.fullname" -}}
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
{{- define "tempo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tempo.labels" -}}
helm.sh/chart: {{ include "tempo.chart" . }}
{{ include "tempo.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tempo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tempo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "tempo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "tempo.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the secret name
*/}}
{{- define "tempo.secretName" -}}
{{- if .Values.tempo.existingSecret }}
{{- .Values.tempo.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "tempo.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name
*/}}
{{- define "tempo.configMapName" -}}
{{- if .Values.tempo.existingConfigMap }}
{{- .Values.tempo.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "tempo.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the image name
*/}}
{{- define "tempo.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Return the Role name
*/}}
{{- define "tempo.roleName" -}}
{{- printf "%s-role" (include "tempo.fullname" .) }}
{{- end }}

{{/*
Return the RoleBinding name
*/}}
{{- define "tempo.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "tempo.fullname" .) }}
{{- end }}
