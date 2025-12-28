{{/*
Expand the name of the chart.
*/}}
{{- define "thanos-compactor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "thanos-compactor.fullname" -}}
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
{{- define "thanos-compactor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "thanos-compactor.labels" -}}
helm.sh/chart: {{ include "thanos-compactor.chart" . }}
{{ include "thanos-compactor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: compactor
app.kubernetes.io/part-of: thanos
{{- end }}

{{/*
Selector labels
*/}}
{{- define "thanos-compactor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "thanos-compactor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "thanos-compactor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "thanos-compactor.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "thanos-compactor.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:v%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Return the name of the Role
*/}}
{{- define "thanos-compactor.roleName" -}}
{{- include "thanos-compactor.fullname" . -}}
{{- end }}

{{/*
Return the name of the RoleBinding
*/}}
{{- define "thanos-compactor.roleBindingName" -}}
{{- include "thanos-compactor.fullname" . -}}
{{- end }}

{{/*
Return the secret name for objstore config
*/}}
{{- define "thanos-compactor.objstoreSecretName" -}}
{{- if .Values.objstore.existingSecret }}
{{- .Values.objstore.existingSecret }}
{{- else }}
{{- include "thanos-compactor.fullname" . }}-objstore
{{- end }}
{{- end }}

{{/*
Generate objstore.yaml content
*/}}
{{- define "thanos-compactor.objstoreConfig" -}}
{{- if eq .Values.objstore.type "s3" -}}
type: S3
config:
  bucket: {{ .Values.objstore.s3.bucket | quote }}
  endpoint: {{ .Values.objstore.s3.endpoint | quote }}
  region: {{ .Values.objstore.s3.region | quote }}
  access_key: {{ .Values.objstore.s3.accessKey | quote }}
  secret_key: {{ .Values.objstore.s3.secretKey | quote }}
  insecure: {{ .Values.objstore.s3.insecure }}
{{- else if eq .Values.objstore.type "gcs" -}}
type: GCS
config:
  bucket: {{ .Values.objstore.gcs.bucket | quote }}
{{- else if eq .Values.objstore.type "azure" -}}
type: AZURE
config:
  storage_account: {{ .Values.objstore.azure.storageAccountName | quote }}
  storage_account_key: {{ .Values.objstore.azure.storageAccountKey | quote }}
  container: {{ .Values.objstore.azure.containerName | quote }}
{{- else if eq .Values.objstore.type "filesystem" -}}
type: FILESYSTEM
config:
  directory: /data/objstore
{{- end -}}
{{- end }}
