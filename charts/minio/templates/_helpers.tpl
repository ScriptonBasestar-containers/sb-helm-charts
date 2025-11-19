{{/*
Expand the name of the chart.
*/}}
{{- define "minio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "minio.fullname" -}}
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
{{- define "minio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "minio.labels" -}}
helm.sh/chart: {{ include "minio.chart" . }}
{{ include "minio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "minio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "minio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "minio.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "minio.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the name of the secret containing credentials
*/}}
{{- define "minio.secretName" -}}
{{- if .Values.minio.existingSecret }}
{{- .Values.minio.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "minio.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the headless service name for StatefulSet
*/}}
{{- define "minio.headlessServiceName" -}}
{{- printf "%s-headless" (include "minio.fullname" .) }}
{{- end }}

{{/*
Determine the effective deployment mode
Validates mode and returns normalized value
*/}}
{{- define "minio.effectiveMode" -}}
{{- $mode := default "standalone" .Values.minio.mode | lower | trim -}}
{{- if not (or (eq $mode "standalone") (eq $mode "distributed")) }}
{{- fail (printf "Invalid minio.mode '%s'. Must be 'standalone' or 'distributed'" $mode) }}
{{- end }}
{{- if eq $mode "distributed" }}
{{- if lt (int .Values.replicaCount) 4 }}
{{- fail "Distributed mode requires at least 4 replicas (minio.mode=distributed with replicaCount >= 4)" }}
{{- end }}
{{- if ne (mod (int .Values.replicaCount) 2) 0 }}
{{- fail "Distributed mode requires even number of replicas for erasure coding" }}
{{- end }}
{{- end }}
{{- $mode -}}
{{- end }}

{{/*
Generate MinIO server command arguments
For standalone: /data{0...N}
For distributed: http://minio-{0...N}.minio-headless.namespace.svc.cluster.local:9000/data{0...N}
*/}}
{{- define "minio.serverCommand" -}}
{{- $mode := include "minio.effectiveMode" . -}}
{{- $replicas := int .Values.replicaCount -}}
{{- $drives := int .Values.minio.drivesPerNode -}}
{{- if eq $mode "distributed" -}}
http://{{ include "minio.fullname" . }}-{0...{{ sub $replicas 1 }}}.{{ include "minio.headlessServiceName" . }}.{{ .Release.Namespace }}.svc.{{ .Values.clusterDomain }}:9000/data{0...{{ sub $drives 1 }}}
{{- else -}}
/data{0...{{ sub $drives 1 }}}
{{- end -}}
{{- end }}

{{/*
Return the configmap name
*/}}
{{- define "minio.configMapName" -}}
{{- if .Values.minio.existingConfigMap }}
{{- .Values.minio.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "minio.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Checksum annotations for config and secrets
*/}}
{{- define "minio.checksumAnnotations" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
{{- end }}
