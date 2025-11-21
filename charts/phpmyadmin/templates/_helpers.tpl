{{/*
Expand the name of the chart.
*/}}
{{- define "phpmyadmin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "phpmyadmin.fullname" -}}
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
{{- define "phpmyadmin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "phpmyadmin.labels" -}}
helm.sh/chart: {{ include "phpmyadmin.chart" . }}
{{ include "phpmyadmin.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "phpmyadmin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "phpmyadmin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "phpmyadmin.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "phpmyadmin.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate blowfish secret
*/}}
{{- define "phpmyadmin.blowfishSecret" -}}
{{- if .Values.phpmyadmin.blowfishSecret }}
{{- .Values.phpmyadmin.blowfishSecret }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate servers configuration
*/}}
{{- define "phpmyadmin.serversConfig" -}}
<?php
{{- if .Values.phpmyadmin.servers.enabled }}
{{- range $index, $server := .Values.phpmyadmin.servers.config }}
$i++;
$cfg['Servers'][$i]['host'] = '{{ $server.host }}';
$cfg['Servers'][$i]['port'] = {{ $server.port | default 3306 }};
$cfg['Servers'][$i]['verbose'] = '{{ $server.verbose | default $server.host }}';
$cfg['Servers'][$i]['auth_type'] = 'cookie';
{{- if $server.ssl }}
$cfg['Servers'][$i]['ssl'] = true;
$cfg['Servers'][$i]['ssl_verify'] = false;
{{- end }}
{{- end }}
{{- else if .Values.phpmyadmin.arbitraryServerConnection }}
$cfg['AllowArbitraryServer'] = {{ .Values.phpmyadmin.allowArbitraryServer }};
{{- else }}
$i++;
$cfg['Servers'][$i]['host'] = '{{ .Values.phpmyadmin.host }}';
$cfg['Servers'][$i]['port'] = {{ .Values.phpmyadmin.port }};
$cfg['Servers'][$i]['auth_type'] = 'cookie';
{{- end }}

// Upload/Import settings
$cfg['UploadDir'] = '/var/www/html/upload';
$cfg['SaveDir'] = '/var/www/html/save';
$cfg['TempDir'] = '/tmp';

{{- if .Values.phpmyadmin.hideDatabases }}
// Hide databases
$cfg['Servers'][$i]['hide_db'] = '^({{ join "|" .Values.phpmyadmin.hideDatabases }})$';
{{- end }}

{{- if .Values.phpmyadmin.configurationStorage.enabled }}
// Configuration storage
$cfg['Servers'][$i]['pmadb'] = '{{ .Values.phpmyadmin.configurationStorage.database }}';
$cfg['Servers'][$i]['bookmarktable'] = 'pma__bookmark';
$cfg['Servers'][$i]['relation'] = 'pma__relation';
$cfg['Servers'][$i]['table_info'] = 'pma__table_info';
$cfg['Servers'][$i]['table_coords'] = 'pma__table_coords';
$cfg['Servers'][$i]['pdf_pages'] = 'pma__pdf_pages';
$cfg['Servers'][$i]['column_info'] = 'pma__column_info';
$cfg['Servers'][$i]['history'] = 'pma__history';
$cfg['Servers'][$i]['recent'] = 'pma__recent';
$cfg['Servers'][$i]['favorite'] = 'pma__favorite';
$cfg['Servers'][$i]['users'] = 'pma__users';
$cfg['Servers'][$i]['usergroups'] = 'pma__usergroups';
$cfg['Servers'][$i]['navigationhiding'] = 'pma__navigationhiding';
$cfg['Servers'][$i]['savedsearches'] = 'pma__savedsearches';
$cfg['Servers'][$i]['central_columns'] = 'pma__central_columns';
$cfg['Servers'][$i]['designer_settings'] = 'pma__designer_settings';
$cfg['Servers'][$i]['export_templates'] = 'pma__export_templates';
{{- end }}
{{- end }}
