{{/*
Expand the name of the chart.
*/}}
{{- define "mongodb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mongodb.fullname" -}}
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
{{- define "mongodb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongodb.labels" -}}
helm.sh/chart: {{ include "mongodb.chart" . }}
{{ include "mongodb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mongodb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mongodb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mongodb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mongodb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the primary service name
*/}}
{{- define "mongodb.primaryServiceName" -}}
{{- printf "%s" (include "mongodb.fullname" .) }}
{{- end }}

{{/*
Return the headless service name
*/}}
{{- define "mongodb.headlessServiceName" -}}
{{- printf "%s-headless" (include "mongodb.fullname" .) }}
{{- end }}

{{/*
Return the secret name
*/}}
{{- define "mongodb.secretName" -}}
{{- if .Values.mongodb.existingSecret }}
{{- .Values.mongodb.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "mongodb.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name
*/}}
{{- define "mongodb.configMapName" -}}
{{- if .Values.mongodb.existingConfigMap }}
{{- .Values.mongodb.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "mongodb.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return MongoDB root password
*/}}
{{- define "mongodb.rootPassword" -}}
{{- if .Values.mongodb.rootPassword }}
{{- .Values.mongodb.rootPassword }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{/*
Return MongoDB replica set key
*/}}
{{- define "mongodb.replicaSetKey" -}}
{{- if .Values.mongodb.replicaSet.key }}
{{- .Values.mongodb.replicaSet.key }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Return MongoDB replica set name
*/}}
{{- define "mongodb.replicaSetName" -}}
{{- .Values.mongodb.replicaSet.name | default "rs0" }}
{{- end }}

{{/*
Return MongoDB replica set members list
*/}}
{{- define "mongodb.replicaSetMembers" -}}
{{- $replicas := int .Values.replicaCount }}
{{- $fullname := include "mongodb.fullname" . }}
{{- $headlessService := include "mongodb.headlessServiceName" . }}
{{- $namespace := .Release.Namespace }}
{{- $members := list }}
{{- range $i := until $replicas }}
{{- $members = append $members (printf "%s-%d.%s.%s.svc.cluster.local:27017" $fullname $i $headlessService $namespace) }}
{{- end }}
{{- join "," $members }}
{{- end }}

{{/*
Return the MongoDB connection URI
*/}}
{{- define "mongodb.connectionUri" -}}
{{- if .Values.mongodb.replicaSet.enabled }}
{{- printf "mongodb://%s/%s?replicaSet=%s" (include "mongodb.replicaSetMembers" .) .Values.mongodb.database (include "mongodb.replicaSetName" .) }}
{{- else }}
{{- printf "mongodb://%s.%s.svc.cluster.local:27017/%s" (include "mongodb.primaryServiceName" .) .Release.Namespace .Values.mongodb.database }}
{{- end }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "mongodb.roleName" -}}
{{- printf "%s-role" (include "mongodb.fullname" .) }}
{{- end }}

{{- define "mongodb.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "mongodb.fullname" .) }}
{{- end }}
