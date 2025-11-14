{{/*
Expand the name of the chart.
*/}}
{{- define "rustfs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rustfs.fullname" -}}
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
{{- define "rustfs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rustfs.labels" -}}
helm.sh/chart: {{ include "rustfs.chart" . }}
{{ include "rustfs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rustfs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rustfs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "rustfs.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "rustfs.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the headless service
*/}}
{{- define "rustfs.headlessServiceName" -}}
{{- printf "%s-headless" (include "rustfs.fullname" .) }}
{{- end }}

{{/*
Create the name of the secret containing RustFS credentials
*/}}
{{- define "rustfs.secretName" -}}
{{- if .Values.rustfs.existingSecret }}
{{- .Values.rustfs.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "rustfs.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Get root user from secret or values
*/}}
{{- define "rustfs.rootUser" -}}
{{- if .Values.rustfs.existingSecret }}
{{- printf "$(cat /etc/rustfs-secret/%s)" .Values.rustfs.rootUserKey }}
{{- else }}
{{- .Values.rustfs.rootUser }}
{{- end }}
{{- end }}

{{/*
Get root password from secret or values
*/}}
{{- define "rustfs.rootPassword" -}}
{{- if .Values.rustfs.existingSecret }}
{{- printf "$(cat /etc/rustfs-secret/%s)" .Values.rustfs.rootPasswordKey }}
{{- else }}
{{- .Values.rustfs.rootPassword }}
{{- end }}
{{- end }}

{{/*
Generate RustFS server command with data directories
*/}}
{{- define "rustfs.serverCommand" -}}
{{- $dataDirs := list }}
{{- if .Values.storageTiers.enabled }}
{{- range $i := until (int .Values.storageTiers.hot.dataDirs) }}
{{- $dataDirs = append $dataDirs (printf "http://{0...%d}.%s.%s.svc.cluster.local:9000/data/hot-%d" (sub (int $.Values.replicaCount) 1) (include "rustfs.headlessServiceName" $) $.Release.Namespace $i) }}
{{- end }}
{{- range $i := until (int .Values.storageTiers.cold.dataDirs) }}
{{- $dataDirs = append $dataDirs (printf "http://{0...%d}.%s.%s.svc.cluster.local:9000/data/cold-%d" (sub (int $.Values.replicaCount) 1) (include "rustfs.headlessServiceName" $) $.Release.Namespace $i) }}
{{- end }}
{{- else }}
{{- range $i := until (int .Values.rustfs.dataDirs) }}
{{- $dataDirs = append $dataDirs (printf "http://{0...%d}.%s.%s.svc.cluster.local:9000/data/rustfs%d" (sub (int $.Values.replicaCount) 1) (include "rustfs.headlessServiceName" $) $.Release.Namespace $i) }}
{{- end }}
{{- end }}
{{- join " " $dataDirs }}
{{- end }}
