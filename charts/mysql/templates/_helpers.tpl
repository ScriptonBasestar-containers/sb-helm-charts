{{- define "mysql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mysql.fullname" -}}
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

{{- define "mysql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mysql.labels" -}}
helm.sh/chart: {{ include "mysql.chart" . }}
{{ include "mysql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mysql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mysql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mysql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "mysql.secretName" -}}
{{- if .Values.mysql.existingSecret }}
{{- .Values.mysql.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "mysql.fullname" .) }}
{{- end }}
{{- end }}

{{- define "mysql.configMapName" -}}
{{- if .Values.mysql.existingConfigMap }}
{{- .Values.mysql.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "mysql.fullname" .) }}
{{- end }}
{{- end }}

{{- define "mysql.headlessServiceName" -}}
{{- printf "%s-headless" (include "mysql.fullname" .) }}
{{- end }}

{{- define "mysql.primaryServiceName" -}}
{{- include "mysql.fullname" . }}
{{- end }}

{{- define "mysql.password" -}}
{{- if .Values.mysql.password }}
{{- .Values.mysql.password }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}

{{- define "mysql.replicationPassword" -}}
{{- if .Values.mysql.replication.password }}
{{- .Values.mysql.replication.password }}
{{- else }}
{{- randAlphaNum 16 }}
{{- end }}
{{- end }}
