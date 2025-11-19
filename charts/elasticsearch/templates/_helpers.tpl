{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "elasticsearch.fullname" -}}
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
{{- define "elasticsearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "elasticsearch.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "elasticsearch.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "elasticsearch.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "elasticsearch.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Headless service name for Elasticsearch cluster discovery
*/}}
{{- define "elasticsearch.headlessServiceName" -}}
{{- printf "%s-headless" (include "elasticsearch.fullname" .) }}
{{- end }}

{{/*
Secret name for Elasticsearch credentials
*/}}
{{- define "elasticsearch.secretName" -}}
{{- if .Values.elasticsearch.existingSecret }}
{{- .Values.elasticsearch.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "elasticsearch.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ConfigMap name for Elasticsearch configuration
*/}}
{{- define "elasticsearch.configMapName" -}}
{{- if .Values.elasticsearch.existingConfigMap }}
{{- .Values.elasticsearch.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "elasticsearch.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Kibana fullname
*/}}
{{- define "kibana.fullname" -}}
{{- printf "%s-kibana" (include "elasticsearch.fullname" .) }}
{{- end }}

{{/*
Kibana labels
*/}}
{{- define "kibana.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "kibana.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Kibana selector labels
*/}}
{{- define "kibana.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: kibana
{{- end }}

{{/*
Validate replica count for cluster mode
*/}}
{{- define "elasticsearch.validateReplicas" -}}
{{- $replicas := int .Values.elasticsearch.replicas -}}
{{- if and .Values.elasticsearch.clusterMode (lt $replicas 3) }}
{{- fail "Cluster mode requires at least 3 replicas for quorum" }}
{{- end }}
{{- end }}

{{/*
Get Elasticsearch URL for Kibana
*/}}
{{- define "elasticsearch.url" -}}
{{- printf "http://%s:9200" (include "elasticsearch.fullname" .) }}
{{- end }}
