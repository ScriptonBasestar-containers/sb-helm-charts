{{/*
Expand the name of the chart.
*/}}
{{- define "vaultwarden.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vaultwarden.fullname" -}}
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
{{- define "vaultwarden.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vaultwarden.labels" -}}
helm.sh/chart: {{ include "vaultwarden.chart" . }}
{{ include "vaultwarden.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vaultwarden.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vaultwarden.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vaultwarden.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vaultwarden.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Determine workload type (StatefulSet or Deployment)
SQLite mode → StatefulSet (needs stable storage)
PostgreSQL/MySQL mode → Deployment (stateless)
*/}}
{{- define "vaultwarden.workloadType" -}}
{{- if eq .Values.workloadType "auto" }}
  {{- if .Values.sqlite.enabled }}
    {{- print "StatefulSet" }}
  {{- else if or .Values.postgresql.enabled .Values.mysql.enabled }}
    {{- print "Deployment" }}
  {{- else }}
    {{- print "StatefulSet" }}
  {{- end }}
{{- else }}
  {{- .Values.workloadType }}
{{- end }}
{{- end }}

{{/*
Database URL construction
*/}}
{{- define "vaultwarden.databaseUrl" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "postgresql://%s:%s@%s:%d/%s" .Values.postgresql.external.username .Values.postgresql.external.password .Values.postgresql.external.host (.Values.postgresql.external.port | int) .Values.postgresql.external.database }}
{{- else if .Values.mysql.enabled }}
{{- printf "mysql://%s:%s@%s:%d/%s" .Values.mysql.external.username .Values.mysql.external.password .Values.mysql.external.host (.Values.mysql.external.port | int) .Values.mysql.external.database }}
{{- else }}
{{- print "/data/db.sqlite3" }}
{{- end }}
{{- end }}

{{/*
Validate configuration
*/}}
{{- define "vaultwarden.validateConfig" -}}
{{- if and .Values.postgresql.enabled .Values.mysql.enabled }}
  {{- fail "Cannot enable both PostgreSQL and MySQL backends" }}
{{- end }}
{{- if and .Values.postgresql.enabled (not .Values.postgresql.external.password) }}
  {{- fail "PostgreSQL password is required when postgresql.enabled=true" }}
{{- end }}
{{- if and .Values.mysql.enabled (not .Values.mysql.external.password) }}
  {{- fail "MySQL password is required when mysql.enabled=true" }}
{{- end }}
{{- if and .Values.vaultwarden.smtp.enabled (not .Values.vaultwarden.smtp.host) }}
  {{- fail "SMTP host is required when smtp.enabled=true" }}
{{- end }}
{{- end }}

{{/*
PVC name for data directory (StatefulSet mode)
*/}}
{{- define "vaultwarden.dataVolumeName" -}}
{{- if .Values.persistence.data.existingClaim }}
{{- .Values.persistence.data.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "vaultwarden.fullname" .) }}
{{- end }}
{{- end }}

{{/*
RBAC names
*/}}
{{- define "vaultwarden.roleName" -}}
{{- printf "%s-role" (include "vaultwarden.fullname" .) }}
{{- end }}

{{- define "vaultwarden.roleBindingName" -}}
{{- printf "%s-rolebinding" (include "vaultwarden.fullname" .) }}
{{- end }}
