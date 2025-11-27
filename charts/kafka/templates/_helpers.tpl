{{/*
Expand the name of the chart.
*/}}
{{- define "kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kafka.fullname" -}}
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
{{- define "kafka.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kafka.labels" -}}
helm.sh/chart: {{ include "kafka.chart" . }}
{{ include "kafka.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kafka.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kafka.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret name for Kafka credentials
*/}}
{{- define "kafka.secretName" -}}
{{- if .Values.kafka.existingSecret }}
{{- .Values.kafka.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "kafka.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ConfigMap name for Kafka configuration
*/}}
{{- define "kafka.configMapName" -}}
{{- if .Values.kafka.existingConfigMap }}
{{- .Values.kafka.existingConfigMap }}
{{- else }}
{{- printf "%s-config" (include "kafka.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Headless service name (for StatefulSet)
*/}}
{{- define "kafka.headlessServiceName" -}}
{{- printf "%s-headless" (include "kafka.fullname" .) }}
{{- end }}

{{/*
Kafka UI service name
*/}}
{{- define "kafka.uiServiceName" -}}
{{- printf "%s-ui" (include "kafka.fullname" .) }}
{{- end }}

{{/*
Kafka UI fullname
*/}}
{{- define "kafka.uiFullname" -}}
{{- printf "%s-ui" (include "kafka.fullname" .) }}
{{- end }}

{{/*
Generate Kafka cluster ID for KRaft mode
This uses a deterministic hash based on release name and namespace
to ensure the same cluster ID across Helm upgrades
*/}}
{{- define "kafka.clusterId" -}}
{{- if .Values.kafka.clusterId }}
{{- .Values.kafka.clusterId }}
{{- else }}
{{- $seed := printf "%s-%s" .Release.Name .Release.Namespace }}
{{- $seed | sha256sum | trunc 22 }}
{{- end }}
{{- end }}

{{/*
Kafka broker list (comma-separated)
Used by Kafka UI and other clients
*/}}
{{- define "kafka.brokerList" -}}
{{- $fullname := include "kafka.fullname" . -}}
{{- $headlessService := include "kafka.headlessServiceName" . -}}
{{- $namespace := .Release.Namespace -}}
{{- $replicas := int .Values.replicaCount -}}
{{- $brokers := list -}}
{{- range $i := until $replicas -}}
{{- $brokers = append $brokers (printf "%s-%d.%s.%s.svc.cluster.local:9092" $fullname $i $headlessService $namespace) -}}
{{- end -}}
{{- join "," $brokers -}}
{{- end }}

{{/*
Kafka SASL JAAS config
*/}}
{{- define "kafka.saslJaasConfig" -}}
{{- if .Values.kafka.sasl.enabled }}
org.apache.kafka.common.security.plain.PlainLoginModule required username="{{ .Values.kafka.sasl.username }}" password="{{ .Values.kafka.sasl.password }}";
{{- else }}
{{- end }}
{{- end }}

{{/*
RBAC role name
*/}}
{{- define "kafka.roleName" -}}
{{- printf "%s" (include "kafka.fullname" .) }}
{{- end }}

{{/*
RBAC role binding name
*/}}
{{- define "kafka.roleBindingName" -}}
{{- printf "%s" (include "kafka.fullname" .) }}
{{- end }}
