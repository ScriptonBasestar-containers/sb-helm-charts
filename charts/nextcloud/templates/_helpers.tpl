{{/*
Expand the name of the chart.
*/}}
{{- define "nextcloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nextcloud.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
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
Create a default fully qualified redis app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "nextcloud.redis.fullname" -}}
# {{- printf "%s-redis" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- printf .Values.externalRedis.host .Release.Name | trunc 63 | trimSuffix "-" -}}
# {{- printf "external-redis" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nextcloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create image name that is used in the deployment
*/}}
{{- define "nextcloud.image" -}}
{{- printf "%s/%s:%s" .Values.image.nextcloud.registry .Values.image.nextcloud.repository .Values.image.nextcloud.tag -}}
{{- end -}}

{{- define "nextcloud.ingress.apiVersion" -}}
{{- if semverCompare "<1.14-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "extensions/v1beta1" -}}
{{- else if semverCompare "<1.19-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "networking.k8s.io/v1beta1" -}}
{{- else -}}
{{- print "networking.k8s.io/v1" -}}
{{- end }}
{{- end -}}

{{/*
Create environment variables used to configure the nextcloud container as well as the cron sidecar container.
*/}}
{{- define "nextcloud.env" -}}
  {{- if eq .Values.externalDatabase.type "postgresql" }}
- name: POSTGRES_HOST
  value: {{ .Values.externalDatabase.host | quote }}
- name: POSTGRES_DB
  value: {{ .Values.externalDatabase.database | quote }}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.externalDatabase.existingSecret.secretName | default (printf "%s-db" .Release.Name) }}
      key: {{ .Values.externalDatabase.existingSecret.usernameKey }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.externalDatabase.existingSecret.secretName | default (printf "%s-db" .Release.Name) }}
      key: {{ .Values.externalDatabase.existingSecret.passwordKey }}
  {{- else if eq .Values.externalDatabase.type "mysql" }}
- name: MYSQL_HOST
  value: {{ .Values.externalDatabase.host | quote }}
- name: MYSQL_DATABASE
  value: {{ .Values.externalDatabase.database | quote }}
- name: MYSQL_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.externalDatabase.existingSecret.secretName | default (printf "%s-db" .Release.Name) }}
      key: {{ .Values.externalDatabase.existingSecret.usernameKey }}
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.externalDatabase.existingSecret.secretName | default (printf "%s-db" .Release.Name) }}
      key: {{ .Values.externalDatabase.existingSecret.passwordKey }}
  {{- end }}
- name: NEXTCLOUD_ADMIN_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.nextcloud.existingSecret.secretName | default (include "nextcloud.fullname" .) }}
      key: {{ .Values.nextcloud.existingSecret.usernameKey }}
- name: NEXTCLOUD_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.nextcloud.existingSecret.secretName | default (include "nextcloud.fullname" .) }}
      key: {{ .Values.nextcloud.existingSecret.passwordKey }}
- name: NEXTCLOUD_TRUSTED_DOMAINS
  value: {{ .Values.nextcloud.host }}
{{- if ne (int .Values.nextcloud.update) 0 }}
- name: NEXTCLOUD_UPDATE
  value: {{ .Values.nextcloud.update | quote }}
{{- end }}
- name: NEXTCLOUD_DATA_DIR
  value: {{ .Values.persistence.nextcloudData.mountPath | quote }}
{{- if .Values.nextcloud.mail.enabled }}
- name: SMTP_HOST
  value: {{ .Values.nextcloud.mail.smtp.host | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.nextcloud.existingSecret.secretName | default (include "nextcloud.fullname" .) }}
      key: {{ .Values.nextcloud.existingSecret.smtpHostKey }}
- name: SMTP_NAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.nextcloud.existingSecret.secretName | default (include "nextcloud.fullname" .) }}
      key: {{ .Values.nextcloud.existingSecret.smtpUsernameKey }}
- name: SMTP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.nextcloud.existingSecret.secretName | default (include "nextcloud.fullname" .) }}
      key: {{ .Values.nextcloud.existingSecret.smtpPasswordKey }}
{{- end }}
- name: REDIS_HOST
  value: {{ .Values.externalRedis.host | quote }}
- name: REDIS_HOST_PORT
  value: {{ .Values.externalRedis.port | quote }}
{{- if .Values.externalRedis.auth.enabled }}
- name: REDIS_HOST_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.externalRedis.auth.existingSecret.secretName | default (printf "%s-redis" .Release.Name) }}
      key: {{ .Values.externalRedis.auth.existingSecret.existingSecretPasswordKey }}
{{- end }}
- name: NEXTCLOUD_PATH_CUSTOM_APPS
  value: {{ .Values.persistence.nextcloudCustomApps.mountPath | quote }}
- name: NEXTCLOUD_PATH_THEMES
  value: {{ .Values.persistence.nextcloudThemes.mountPath | quote }}
- name: NEXTCLOUD_PATH_DATA
  value: {{ .Values.persistence.nextcloudData.mountPath | quote }}
{{- if .Values.nextcloud.extraEnv }}
{{ toYaml .Values.nextcloud.extraEnv }}
{{- end }}
{{- end -}}

{{/*
Create volume mounts for the nextcloud container as well as the cron sidecar container.
*/}}
{{- define "nextcloud.volumeMounts" -}}
- name: nextcloud-config
  mountPath: /var/www/html/config/
{{/*
files >>>
*/}}
- name: vol-config-files
# - name: vol-config-files-apcu
  mountPath: /var/www/html/config/apcu.config.php
  subPath: apcu.config.php
- name: vol-config-files
# - name: vol-config-files-autoconfig
  mountPath: /var/www/html/config/auto.config.php
  subPath: auto.config.php
- name: vol-config-files
# - name: vol-config-files-dir-apps
  mountPath: /var/www/html/config/dir-apps.config.php
  subPath: dir-apps.config.php
- name: vol-config-files
# - name: vol-config-files-dir-data
  mountPath: /var/www/html/config/dir-data.config.php
  subPath: dir-data.config.php
- name: vol-config-files
# - name: vol-config-files-dir-themes
  mountPath: /var/www/html/config/dir-themes.config.php
  subPath: dir-themes.config.php
- name: vol-config-files
# - name: vol-config-files-redis
  mountPath: /var/www/html/config/redis.config.php
  subPath: redis.config.php
- name: vol-config-files
# - name: vol-config-files-reverse-proxy
  mountPath: /var/www/html/config/reverse-proxy.config.php
  subPath: reverse-proxy.config.php
- name: vol-config-files
# - name: vol-config-files-s3
  mountPath: /var/www/html/config/s3.config.php
  subPath: s3.config.php
- name: vol-config-files
# - name: vol-config-files-smtp
  mountPath: /var/www/html/config/smtp.config.php
  subPath: smtp.config.php
- name: vol-config-files
# - name: vol-config-files-swift
  mountPath: /var/www/html/config/swift.config.php
  subPath: swift.config.php
- name: vol-config-files
# - name: vol-config-files-upgrade-disable-web
  mountPath: /var/www/html/config/upgrade-disable-web.config.php
  subPath: upgrade-disable-web.config.php
{{/*
files <<<
*/}}
- name: nextcloud-custom-apps
  mountPath: {{ .Values.persistence.nextcloudCustomApps.mountPath | default "/nextcloud/custom_apps" }}
  {{/*
  subPath: {{ ternary "custom_apps" (printf "%s/custom_apps" .Values.nextcloud.persistence.subPath) (empty .Values.nextcloud.persistence.subPath) }}
  */}}
- name: nextcloud-data
  mountPath: {{ .Values.persistence.nextcloudData.mountPath | default "/nextcloud/data" }}
  {{/*
  subPath: {{ ternary "data" (printf "%s/data" .Values.persistence.nextcloudData.subPath) (empty .Values.persistence.nextcloudData.subPath) }}
  */}}
- name: nextcloud-themes
  mountPath: {{ .Values.persistence.nextcloudThemes.mountPath | default "/nextcloud/themes" }}
  {{/*
  subPath: {{ ternary "themes" (printf "%s/themes" .Values.nextcloud.persistence.subPath) (empty .Values.nextcloud.persistence.subPath) }}
  */}}
{{- if .Values.nextcloud.extraVolumeMounts }}
{{ toYaml .Values.nextcloud.extraVolumeMounts }}
{{- end }}
{{- end -}}
