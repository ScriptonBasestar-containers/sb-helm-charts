{{/*
overrided name of the chart.
*/}}
{{- define "nextcloud.name" -}}
  {{- if .Values.nameOverride -}}
      {{- .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- $name := default .Chart.Name .Values.nameOverride -}}
    {{- if contains $name .Release.Name -}}
      {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
      {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
chart name.
*/}}
{{- define "nextcloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
selector label
*/}}
{{- define "nextcloud.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nextcloud.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
full label
*/}}
{{- define "nextcloud.labels" -}}
helm.sh/chart: {{ include "nextcloud.chart" . }}
{{ include "nextcloud.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ default .Chart.AppVersion $.Values.image.nextcloud.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nextcloud
{{- end }}

{{/*
Create the name of the notifications bots slack service account to use
*/}}
{{- define "nextcloud.serviceAccountName" -}}
{{- if .Values.rbac.serviceAccount.create -}}
  {{ if .Values.rbac.serviceAccount.name }}
    {{ printf "%s-%s" (include "nextcloud.name" .) "serviceaccount" }}
  {{ else }}
    {{ default "default" .Values.rbac.serviceAccount.name }}
  {{ end }}
{{- else -}}
    {{ default "default" .Values.rbac.serviceAccount.name }}
{{- end -}}
{{- end -}}
