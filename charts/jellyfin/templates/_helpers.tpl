{{/*
Expand the name of the chart.
*/}}
{{- define "jellyfin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "jellyfin.fullname" -}}
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
{{- define "jellyfin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "jellyfin.labels" -}}
helm.sh/chart: {{ include "jellyfin.chart" . }}
{{ include "jellyfin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "jellyfin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jellyfin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "jellyfin.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "jellyfin.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Merged resources with GPU support
*/}}
{{- define "jellyfin.resources" -}}
{{- $resources := .Values.resources | deepCopy -}}
{{- if and .Values.jellyfin.hardwareAcceleration.enabled (eq .Values.jellyfin.hardwareAcceleration.type "nvidia-nvenc") -}}
{{- if not $resources.limits -}}
{{- $_ := set $resources "limits" dict -}}
{{- end -}}
{{- $_ := set $resources.limits "nvidia.com/gpu" "1" -}}
{{- end -}}
{{- toYaml $resources -}}
{{- end -}}

{{/*
Merged podSecurityContext with GPU supplemental groups
*/}}
{{- define "jellyfin.podSecurityContext" -}}
{{- $ctx := .Values.podSecurityContext | deepCopy -}}
{{- if and .Values.jellyfin.hardwareAcceleration.enabled (eq .Values.jellyfin.hardwareAcceleration.type "intel-qsv") -}}
{{- $groups := list 44 109 -}}
{{- if $ctx.supplementalGroups -}}
{{- $groups = concat $ctx.supplementalGroups $groups | uniq -}}
{{- end -}}
{{- $_ := set $ctx "supplementalGroups" $groups -}}
{{- end -}}
{{- toYaml $ctx -}}
{{- end -}}
