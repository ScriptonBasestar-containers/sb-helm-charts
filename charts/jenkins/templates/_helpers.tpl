{{/*
Expand the name of the chart.
*/}}
{{- define "jenkins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "jenkins.fullname" -}}
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
{{- define "jenkins.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "jenkins.labels" -}}
helm.sh/chart: {{ include "jenkins.chart" . }}
{{ include "jenkins.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "jenkins.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jenkins.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "jenkins.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "jenkins.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Admin secret name
*/}}
{{- define "jenkins.adminSecretName" -}}
{{- if .Values.controller.admin.existingSecret }}
{{- .Values.controller.admin.existingSecret }}
{{- else }}
{{- include "jenkins.fullname" . }}
{{- end }}
{{- end }}

{{/*
Admin password
*/}}
{{- define "jenkins.adminPassword" -}}
{{- if .Values.controller.admin.password }}
{{- .Values.controller.admin.password }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
JCasC ConfigMap name
*/}}
{{- define "jenkins.jcascConfigMapName" -}}
{{- printf "%s-jcasc" (include "jenkins.fullname" .) }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "jenkins.roleName" -}}
{{- printf "%s-role" (include "jenkins.fullname" .) }}
{{- end }}

{{- define "jenkins.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "jenkins.fullname" .) }}
{{- end }}
