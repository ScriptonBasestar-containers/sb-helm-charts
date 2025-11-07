{{/*
Expand the name of the chart.
*/}}
{{- define "keycloak.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keycloak.fullname" -}}
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
{{- define "keycloak.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keycloak.labels" -}}
helm.sh/chart: {{ include "keycloak.chart" . }}
{{ include "keycloak.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "keycloak.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keycloak.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the PostgreSQL connection string
PostgreSQL JDBC Driver SSL Parameters:
- ssl=true: Enable SSL connection
- sslfactory: SSL implementation class
  * org.postgresql.ssl.NonValidatingFactory: SSL without certificate validation
  * org.postgresql.ssl.DefaultJavaSSLFactory: Use Java's default SSL (with validation)
- sslmode: SSL mode (JDBC 42.2.5+) - verify-ca, verify-full
- sslrootcert: Path to CA certificate for verification
- sslcert/sslkey: Client certificate for mutual TLS
*/}}
{{- define "keycloak.postgresql.jdbcUrl" -}}
{{- if .Values.postgresql.external.enabled }}
{{- $baseUrl := printf "jdbc:postgresql://%s:%v/%s" .Values.postgresql.external.host (.Values.postgresql.external.port | int) .Values.postgresql.external.database }}
{{- if .Values.postgresql.external.ssl.enabled }}
  {{- $sslParams := "" }}
  {{- if eq .Values.postgresql.external.ssl.mode "disable" }}
    {{- /* No SSL parameters */ -}}
  {{- else if eq .Values.postgresql.external.ssl.mode "require" }}
    {{- /* SSL without certificate validation */ -}}
    {{- $sslParams = "?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory" }}
  {{- else if or (eq .Values.postgresql.external.ssl.mode "verify-ca") (eq .Values.postgresql.external.ssl.mode "verify-full") }}
    {{- if .Values.postgresql.external.ssl.certificateSecret }}
      {{- /* SSL with certificate validation */ -}}
      {{- $sslParams = printf "?ssl=true&sslmode=%s&sslrootcert=/opt/keycloak/conf/db-ssl/%s" .Values.postgresql.external.ssl.mode .Values.postgresql.external.ssl.rootCertKey }}
      {{- if .Values.postgresql.external.ssl.clientCertKey }}
        {{- /* Mutual TLS with client certificate */ -}}
        {{- $sslParams = printf "%s&sslcert=/opt/keycloak/conf/db-ssl/%s&sslkey=/opt/keycloak/conf/db-ssl/%s" $sslParams .Values.postgresql.external.ssl.clientCertKey .Values.postgresql.external.ssl.clientKeyKey }}
      {{- end }}
    {{- else }}
      {{- /* Fallback to non-validating factory if no certificate provided */ -}}
      {{- $sslParams = "?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory" }}
    {{- end }}
  {{- else }}
    {{- /* Default: enable SSL with non-validating factory */ -}}
    {{- $sslParams = "?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory" }}
  {{- end }}
  {{- printf "%s%s" $baseUrl $sslParams }}
{{- else }}
  {{- $baseUrl }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get PostgreSQL username
*/}}
{{- define "keycloak.postgresql.username" -}}
{{- if and .Values.postgresql.external.existingSecret.enabled .Values.postgresql.external.existingSecret.secretName }}
{{- /* Use existing secret */ -}}
{{- else }}
{{- .Values.postgresql.external.username }}
{{- end }}
{{- end }}

{{/*
Get PostgreSQL password
*/}}
{{- define "keycloak.postgresql.password" -}}
{{- if and .Values.postgresql.external.existingSecret.enabled .Values.postgresql.external.existingSecret.secretName }}
{{- /* Use existing secret */ -}}
{{- else }}
{{- .Values.postgresql.external.password }}
{{- end }}
{{- end }}

{{/*
Get PostgreSQL database name
*/}}
{{- define "keycloak.postgresql.database" -}}
{{- if and .Values.postgresql.external.existingSecret.enabled .Values.postgresql.external.existingSecret.secretName }}
{{- /* Use existing secret */ -}}
{{- else }}
{{- .Values.postgresql.external.database }}
{{- end }}
{{- end }}

{{/*
Get Keycloak admin username
*/}}
{{- define "keycloak.admin.username" -}}
{{- if and .Values.keycloak.admin.existingSecret.enabled .Values.keycloak.admin.existingSecret.secretName }}
{{- /* Use existing secret */ -}}
{{- else }}
{{- .Values.keycloak.admin.username }}
{{- end }}
{{- end }}

{{/*
Get Keycloak admin password
*/}}
{{- define "keycloak.admin.password" -}}
{{- if and .Values.keycloak.admin.existingSecret.enabled .Values.keycloak.admin.existingSecret.secretName }}
{{- /* Use existing secret */ -}}
{{- else }}
{{- .Values.keycloak.admin.password }}
{{- end }}
{{- end }}

{{/*
Headless service name for clustering
*/}}
{{- define "keycloak.headlessServiceName" -}}
{{- printf "%s-headless" (include "keycloak.fullname" .) }}
{{- end }}
