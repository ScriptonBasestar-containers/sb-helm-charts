{{/*
Expand the name of the chart.
*/}}
{{- define "thanos-query.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "thanos-query.fullname" -}}
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
{{- define "thanos-query.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "thanos-query.labels" -}}
helm.sh/chart: {{ include "thanos-query.chart" . }}
{{ include "thanos-query.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: query
app.kubernetes.io/part-of: thanos
{{- end }}

{{/*
Selector labels
*/}}
{{- define "thanos-query.selectorLabels" -}}
app.kubernetes.io/name: {{ include "thanos-query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "thanos-query.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "thanos-query.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "thanos-query.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:v%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Return the name of the Role
*/}}
{{- define "thanos-query.roleName" -}}
{{- include "thanos-query.fullname" . -}}
{{- end }}

{{/*
Return the name of the RoleBinding
*/}}
{{- define "thanos-query.roleBindingName" -}}
{{- include "thanos-query.fullname" . -}}
{{- end }}

{{/*
Build the store flags for Thanos Query
*/}}
{{- define "thanos-query.storeFlags" -}}
{{- range .Values.thanos.stores }}
- --store={{ . }}
{{- end }}
{{- range .Values.thanos.endpoints }}
- --endpoint={{ . }}
{{- end }}
{{- range .Values.thanos.storeSDFiles }}
- --store.sd-files={{ . }}
{{- end }}
{{- end }}

{{/*
Build the replica label flags
*/}}
{{- define "thanos-query.replicaLabelFlags" -}}
{{- range .Values.thanos.query.replicaLabels }}
- --query.replica-label={{ . }}
{{- end }}
{{- end }}
