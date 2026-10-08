{{/*
Helpers du chart. Tous les workloads (Deployment, CronJob, Job) construisent
leur pod via "tilleuls.podTemplate" : toute évolution du pod se fait ici, une seule fois.
*/}}

{{/* ───────────────────────── Noms et labels ───────────────────────── */}}

{{- define "tilleuls.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Préfixe de toutes les ressources : le nom de la release (ou fullnameOverride).
Le nom du chart n'y figure pas : `helm install monclient …` donne monclient-app,
monclient-worker, monclient-cnpg… quel que soit le nom du chart.
*/}}
{{- define "tilleuls.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Nom d'une ressource liée à un composant : <fullname>-<suffixe>. Paramètres : root, suffix. */}}
{{- define "tilleuls.resourceName" -}}
{{- printf "%s-%s" (include "tilleuls.fullname" .root) .suffix | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tilleuls.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tilleuls.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tilleuls.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tilleuls.labels" -}}
helm.sh/chart: {{ include "tilleuls.chart" . }}
{{ include "tilleuls.selectorLabels" . }}
app.kubernetes.io/version: {{ include "tilleuls.imageTag" (dict "root" . "image" dict) | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Labels d'un composant. Paramètres : root, component. */}}
{{- define "tilleuls.componentLabels" -}}
{{ include "tilleuls.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "tilleuls.componentSelectorLabels" -}}
{{ include "tilleuls.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Bloc metadata.annotations commun. Paramètres : root, annotations (optionnel). */}}
{{- define "tilleuls.annotations" -}}
{{- $all := merge (deepCopy (.annotations | default dict)) (deepCopy (.root.Values.commonAnnotations | default dict)) }}
{{- with $all }}
annotations:
  {{- tpl (toYaml .) $.root | nindent 2 }}
{{- end }}
{{- end }}

{{- define "tilleuls.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "tilleuls.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* ───────────────────────── Utilitaires ───────────────────────── */}}

{{/* Rend une valeur (chaîne ou structure) en passant par tpl. Paramètres : value, root. */}}
{{- define "tilleuls.render" -}}
{{- if kindIs "string" .value }}
{{- tpl .value .root }}
{{- else }}
{{- tpl (toYaml .value) .root }}
{{- end }}
{{- end }}

{{/* "true" si le workload `name` est ciblé par la liste `workloads` (vide = tous). */}}
{{- define "tilleuls.appliesTo" -}}
{{- if or (empty .workloads) (has .name .workloads) }}true{{ end }}
{{- end }}

{{/*
Fusion d'un workload avec `defaults` : les clés de premier niveau du workload
remplacent celles de `defaults` (pas de fusion profonde). Renvoie du YAML.
Paramètres : root, spec.
*/}}
{{- define "tilleuls.workload" -}}
{{- $w := deepCopy (.root.Values.defaults | default dict) }}
{{- range $k, $v := .spec }}
{{- $_ := set $w $k $v }}
{{- end }}
{{- toYaml $w }}
{{- end }}

{{/* Nom complet d'un sous-chart, calculé comme le fait le sous-chart. Paramètres : root, chart. */}}
{{- define "tilleuls.subchartFullname" -}}
{{- $sub := index .root.Values .chart | default dict }}
{{- if $sub.fullnameOverride }}
{{- $sub.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .chart $sub.nameOverride }}
{{- if contains $name .root.Release.Name }}
{{- .root.Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .root.Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* ───────────────────────── Image ───────────────────────── */}}

{{/* Tag effectif. Paramètres : root, image (surcharge du workload). */}}
{{- define "tilleuls.imageTag" -}}
{{- $img := merge (deepCopy (.image | default dict)) (deepCopy .root.Values.image) }}
{{- $img.tag | default .root.Chart.AppVersion | toString }}
{{- end }}

{{/* Référence complète de l'image. Paramètres : root, image. */}}
{{- define "tilleuls.image" -}}
{{- $img := merge (deepCopy (.image | default dict)) (deepCopy .root.Values.image) }}
{{- if $img.digest }}
{{- printf "%s@%s" $img.repository $img.digest }}
{{- else }}
{{- printf "%s:%s" $img.repository (include "tilleuls.imageTag" .) }}
{{- end }}
{{- end }}

{{- define "tilleuls.imagePullPolicy" -}}
{{- $img := merge (deepCopy (.image | default dict)) (deepCopy .root.Values.image) }}
{{- $img.pullPolicy | default "IfNotPresent" }}
{{- end }}

{{/* ───────────────────────── Environnement ───────────────────────── */}}

{{/*
Variables injectées automatiquement par les dépendances activées (liste ordonnée).
Une variable déjà définie dans `env` (global ou workload) n'est pas injectée.
Paramètres : root, userEnv (map fusionnée).
*/}}
{{- define "tilleuls.autoEnv" -}}
{{- $root := .root }}
{{- $userEnv := .userEnv }}
{{- $v := $root.Values }}
{{- $entries := list }}
{{- with $v.addons.cnpg }}
{{- if and .enabled .injectEnv.enabled }}
{{- $cluster := include "tilleuls.subchartFullname" (dict "root" $root "chart" "cnpg") }}
{{- $secret := printf "%s-app" $cluster }}
{{- $host := ternary (printf "%s-pooler-%s" $cluster .injectEnv.pooler) (printf "%s-rw" $cluster) (not (empty .injectEnv.pooler)) }}
{{- $db := dig "cluster" "initdb" "database" "app" ($v.cnpg | default dict) }}
{{- $entries = append $entries (dict "name" "DATABASE_USER" "valueFrom" (dict "secretKeyRef" (dict "name" $secret "key" "username"))) }}
{{- $entries = append $entries (dict "name" "DATABASE_PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" $secret "key" "password"))) }}
{{- $entries = append $entries (dict "name" .injectEnv.name "value" (printf "postgresql://$(DATABASE_USER):$(DATABASE_PASSWORD)@%s:5432/%s%s" $host $db (.injectEnv.query | default ""))) }}
{{- end }}
{{- end }}
{{- with $v.addons.valkey }}
{{- if and .enabled .injectEnv.enabled }}
{{- $entries = append $entries (dict "name" .injectEnv.name "value" (printf "redis://%s:6379" (include "tilleuls.subchartFullname" (dict "root" $root "chart" "valkey")))) }}
{{- end }}
{{- end }}
{{- with $v.addons.mercure }}
{{- if and .enabled .injectEnv.enabled }}
{{- $name := include "tilleuls.subchartFullname" (dict "root" $root "chart" "mercure") }}
{{- $secret := (index $v "mercure" | default dict).existingSecret | default $name }}
{{- $entries = append $entries (dict "name" .injectEnv.urlName "value" (printf "http://%s/.well-known/mercure" $name)) }}
{{- $entries = append $entries (dict "name" .injectEnv.jwtSecretName "valueFrom" (dict "secretKeyRef" (dict "name" $secret "key" "publisher-jwt-key"))) }}
{{- end }}
{{- end }}
{{- with $v.addons.meilisearch }}
{{- if and .enabled .injectEnv.enabled }}
{{- $entries = append $entries (dict "name" .injectEnv.name "value" (printf "http://%s:7700" (include "tilleuls.subchartFullname" (dict "root" $root "chart" "meilisearch")))) }}
{{- end }}
{{- end }}
{{- with $v.addons.maildev }}
{{- if and .enabled .injectEnv.enabled }}
{{- $entries = append $entries (dict "name" .injectEnv.name "value" (printf "smtp://%s:1025" (include "tilleuls.subchartFullname" (dict "root" $root "chart" "maildev")))) }}
{{- end }}
{{- end }}
{{- range $entries }}
{{- if not (hasKey $userEnv .name) }}
- {{ toYaml . | nindent 2 | trim }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Liste `env` complète d'un conteneur : variables auto, puis map `env` (globale
fusionnée avec celle du workload, `null` supprime une clé), puis `extraEnv`.
Paramètres : root, w.
*/}}
{{- define "tilleuls.env" -}}
{{- $root := .root }}
{{- $env := deepCopy ($root.Values.env | default dict) }}
{{- range $k, $val := (.w.env | default dict) }}
{{- if kindIs "invalid" $val }}
{{- $_ := unset $env $k }}
{{- else }}
{{- $_ := set $env $k $val }}
{{- end }}
{{- end }}
{{- include "tilleuls.autoEnv" (dict "root" $root "userEnv" $env) }}
{{- range $k, $val := $env }}
{{- if kindIs "map" $val }}
- name: {{ $k }}
  {{- tpl (toYaml $val) $root | nindent 2 }}
{{- else if not (kindIs "invalid" $val) }}
- name: {{ $k }}
  value: {{ tpl (toString $val) $root | quote }}
{{- end }}
{{- end }}
{{- with $root.Values.extraEnv }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- with .w.extraEnv }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{/* Liste `envFrom` complète. Paramètres : root, w. */}}
{{- define "tilleuls.envFrom" -}}
{{- $root := .root }}
{{- if $root.Values.secretEnv }}
- secretRef:
    name: {{ include "tilleuls.resourceName" (dict "root" $root "suffix" "env") }}
{{- end }}
{{- range $root.Values.existingSecrets }}
- secretRef:
    name: {{ tpl . $root }}
{{- end }}
{{- with $root.Values.envFrom }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- with .w.envFrom }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{/* ───────────────────────── Volumes ───────────────────────── */}}

{{/* Paramètres : root, name (workload), w. */}}
{{- define "tilleuls.volumes" -}}
{{- $root := .root }}
{{- $name := .name }}
{{- $files := false }}
{{- range $key, $f := $root.Values.configFiles }}
{{- if include "tilleuls.appliesTo" (dict "name" $name "workloads" $f.workloads) }}{{ $files = true }}{{ end }}
{{- end }}
{{- if $files }}
- name: config-files
  configMap:
    name: {{ include "tilleuls.resourceName" (dict "root" $root "suffix" "files") }}
{{- end }}
{{- range $key, $p := $root.Values.persistence }}
{{- if and $p.enabled (include "tilleuls.appliesTo" (dict "name" $name "workloads" $p.workloads)) }}
- name: data-{{ $key }}
  persistentVolumeClaim:
    claimName: {{ $p.existingClaim | default (include "tilleuls.resourceName" (dict "root" $root "suffix" $key)) }}
{{- end }}
{{- end }}
{{- with .w.volumes }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{/* Paramètres : root, name (workload), w. */}}
{{- define "tilleuls.volumeMounts" -}}
{{- $root := .root }}
{{- $name := .name }}
{{- range $key, $f := $root.Values.configFiles }}
{{- if include "tilleuls.appliesTo" (dict "name" $name "workloads" $f.workloads) }}
- name: config-files
  mountPath: {{ $f.mountPath }}
  subPath: {{ $key }}
  readOnly: true
{{- end }}
{{- end }}
{{- range $key, $p := $root.Values.persistence }}
{{- if and $p.enabled (include "tilleuls.appliesTo" (dict "name" $name "workloads" $p.workloads)) }}
- name: data-{{ $key }}
  mountPath: {{ $p.mountPath }}
  {{- with $p.subPath }}
  subPath: {{ . }}
  {{- end }}
{{- end }}
{{- end }}
{{- with .w.volumeMounts }}
{{ tpl (toYaml .) $root }}
{{- end }}
{{- end }}

{{/* ───────────────────────── Pod ───────────────────────── */}}

{{/*
Template de pod commun à tous les workloads.
Paramètres : root, name (clé du workload), w (workload fusionné), restartPolicy (optionnel).
*/}}
{{- define "tilleuls.podTemplate" -}}
{{- $root := .root }}
{{- $w := .w }}
{{- $ctx := dict "root" $root "name" .name "w" $w }}
metadata:
  labels:
    {{- include "tilleuls.componentSelectorLabels" (dict "root" $root "component" .name) | nindent 4 }}
    {{- with $root.Values.commonLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with $w.podLabels }}
    {{- tpl (toYaml .) $root | nindent 4 }}
    {{- end }}
  annotations:
    checksum/secret-env: {{ toJson $root.Values.secretEnv | sha256sum }}
    checksum/config-files: {{ toJson $root.Values.configFiles | sha256sum }}
    {{- with $w.podAnnotations }}
    {{- tpl (toYaml .) $root | nindent 4 }}
    {{- end }}
spec:
  serviceAccountName: {{ include "tilleuls.serviceAccountName" $root }}
  automountServiceAccountToken: {{ $root.Values.serviceAccount.automount }}
  {{- with $root.Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .restartPolicy }}
  restartPolicy: {{ . }}
  {{- end }}
  {{- with $w.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $w.terminationGracePeriodSeconds }}
  terminationGracePeriodSeconds: {{ . }}
  {{- end }}
  {{- with $w.priorityClassName }}
  priorityClassName: {{ . }}
  {{- end }}
  {{- with $w.hostAliases }}
  hostAliases:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $w.dnsConfig }}
  dnsConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $w.initContainers }}
  initContainers:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ .name }}
      image: {{ include "tilleuls.image" (dict "root" $root "image" $w.image) }}
      imagePullPolicy: {{ include "tilleuls.imagePullPolicy" (dict "root" $root "image" $w.image) }}
      {{- with $w.command }}
      command:
        {{- tpl (toYaml .) $root | nindent 8 }}
      {{- end }}
      {{- with $w.args }}
      args:
        {{- tpl (toYaml .) $root | nindent 8 }}
      {{- end }}
      {{- with $w.workingDir }}
      workingDir: {{ . }}
      {{- end }}
      {{- with $w.ports }}
      ports:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (include "tilleuls.env" $ctx | trim) }}
      env:
        {{- . | nindent 8 }}
      {{- end }}
      {{- with (include "tilleuls.envFrom" $ctx | trim) }}
      envFrom:
        {{- . | nindent 8 }}
      {{- end }}
      {{- range $probe := list "livenessProbe" "readinessProbe" "startupProbe" }}
      {{- with (index $w $probe) }}
      {{ $probe }}:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- with $w.lifecycle }}
      lifecycle:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $w.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $w.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (include "tilleuls.volumeMounts" $ctx | trim) }}
      volumeMounts:
        {{- . | nindent 8 }}
      {{- end }}
    {{- with $w.sidecars }}
    {{- tpl (toYaml .) $root | nindent 4 }}
    {{- end }}
  {{- with (include "tilleuls.volumes" $ctx | trim) }}
  volumes:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with $w.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $w.affinity }}
  affinity:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
  {{- with $w.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $w.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- tpl (toYaml .) $root | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
Spec d'un Job (partagée entre Job et CronJob.jobTemplate).
Paramètres : root, name, w.
*/}}
{{- define "tilleuls.jobSpec" -}}
{{- $w := .w }}
{{- if hasKey $w "backoffLimit" }}
backoffLimit: {{ $w.backoffLimit }}
{{- end }}
{{- with $w.activeDeadlineSeconds }}
activeDeadlineSeconds: {{ . }}
{{- end }}
{{- if hasKey $w "ttlSecondsAfterFinished" }}
ttlSecondsAfterFinished: {{ $w.ttlSecondsAfterFinished }}
{{- end }}
template:
  {{- include "tilleuls.podTemplate" (dict "root" .root "name" .name "w" $w "restartPolicy" ($w.restartPolicy | default "Never")) | nindent 2 }}
{{- end }}

{{/* Ports d'un Service : `service.ports` ou, à défaut, un port par containerPort. Paramètres : w. */}}
{{- define "tilleuls.servicePorts" -}}
{{- if .w.service.ports }}
{{- range .w.service.ports }}
- name: {{ .name }}
  port: {{ .port }}
  targetPort: {{ .targetPort | default .name }}
  protocol: {{ .protocol | default "TCP" }}
  {{- with .nodePort }}
  nodePort: {{ . }}
  {{- end }}
{{- end }}
{{- else }}
{{- range .w.ports }}
- name: {{ .name }}
  port: {{ .containerPort }}
  targetPort: {{ .name }}
  protocol: {{ .protocol | default "TCP" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "tilleuls.basicAuthName" -}}
{{- include "tilleuls.resourceName" (dict "root" . "suffix" "basicauth") }}
{{- end }}

{{- define "tilleuls.noIndexName" -}}
{{- include "tilleuls.resourceName" (dict "root" . "suffix" "noindex") }}
{{- end }}
