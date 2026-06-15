{{/*
Expand the name of the chart.
*/}}
{{- define "quickwit.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "quickwit.fullname" -}}
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
{{- define "quickwit.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Custom labels
*/}}
{{- define "quickwit.additionalLabels" -}}
{{- if .Values.additionalLabels }}
{{ toYaml .Values.additionalLabels }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "quickwit.labels" -}}
helm.sh/chart: {{ include "quickwit.chart" . }}
{{ include "quickwit.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- include "quickwit.additionalLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "quickwit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "quickwit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Searcher Selector labels
*/}}
{{- define "quickwit.searcher.selectorLabels" -}}
{{ include "quickwit.selectorLabels" . }}
app.kubernetes.io/component: searcher
{{- end }}

{{/*
Janitor Selector labels
*/}}
{{- define "quickwit.janitor.selectorLabels" -}}
{{ include "quickwit.selectorLabels" . }}
app.kubernetes.io/component: janitor
{{- end }}

{{/*
Metastore Selector labels
*/}}
{{- define "quickwit.metastore.selectorLabels" -}}
{{ include "quickwit.selectorLabels" . }}
app.kubernetes.io/component: metastore
{{- end }}

{{/*
Control Plane Selector labels
*/}}
{{- define "quickwit.control_plane.selectorLabels" -}}
{{ include "quickwit.selectorLabels" . }}
app.kubernetes.io/component: control-plane
{{- end }}

{{/*
Indexer Selector labels
*/}}
{{- define "quickwit.indexer.selectorLabels" -}}
{{ include "quickwit.selectorLabels" . }}
app.kubernetes.io/component: indexer
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "quickwit.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "quickwit.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Quickwit ports
*/}}
{{- define "quickwit.ports" -}}
- name: rest
  containerPort: 7280
  protocol: TCP
- name: grpc
  containerPort: 7281
  protocol: TCP
- name: discovery
  containerPort: 7282
  protocol: UDP
{{- end }}


{{/*
Quickwit environment
*/}}
{{- define "quickwit.environment" -}}
- name: NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: QW_CONFIG
  value: {{ .Values.configLocation }}
{{- if not .Values.config.cluster_id }}
- name: QW_CLUSTER_ID
  value: {{ .Release.Namespace }}-{{ include "quickwit.fullname" . }}
{{- end }}
- name: QW_NODE_ID
  value: "$(POD_NAME)"
- name: QW_PEER_SEEDS
  value: {{ include "quickwit.fullname" . }}-headless
- name: QW_ADVERTISE_ADDRESS
  value: "$(POD_IP)"
- name: QW_CLUSTER_ENDPOINT
  value: http://{{ include "quickwit.fullname" $ }}-metastore.{{ $.Release.Namespace }}.svc.{{ .Values.clusterDomain }}:7280
{{- with (include "quickwit.extraEnv" .Values.environment) }}
{{ . }}
{{- end }}
{{- end }}

{{/*
Auto-generate a podAntiAffinity rule preventing two pods of the same
release+service from landing on the same node.
Called as: include "quickwit.nodeAntiAffinity" (list "indexer" .)
*/}}
{{- define "quickwit.nodeAntiAffinity" -}}
{{- $component := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- if $ctx.Values.podAntiAffinity.enabled -}}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          {{- include (printf "quickwit.%s.selectorLabels" $component) $ctx | nindent 10 }}
{{- end -}}
{{- end -}}

{{/*
Resolve the effective affinity for a component.
Merges global affinity and per-service affinity on top of any auto-generated
podAntiAffinity rule (same semantics as the existing merge pattern).
Called as: include "quickwit.componentAffinity" (list "indexer" .)
*/}}
{{- define "quickwit.componentAffinity" -}}
{{- $component := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- $explicit := merge (dict) (index $ctx.Values $component).affinity $ctx.Values.affinity -}}
{{- if $ctx.Values.podAntiAffinity.enabled -}}
{{- $base := include "quickwit.nodeAntiAffinity" (list $component $ctx) | fromYaml -}}
{{- toYaml (mergeOverwrite $base $explicit) -}}
{{- else if $explicit -}}
{{- toYaml $explicit -}}
{{- end -}}
{{- end -}}

{{/*
Auto-generate a topologySpreadConstraints entry to spread pods across zones.
Per-service Values.<component>.zoneSpreadConstraint takes precedence over
the global Values.zoneSpreadConstraint.
Called as: include "quickwit.zoneSpreadConstraint" (list "indexer" .)
*/}}
{{- define "quickwit.zoneSpreadConstraint" -}}
{{- $component := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- $zsc := (index $ctx.Values $component).zoneSpreadConstraint | default $ctx.Values.zoneSpreadConstraint -}}
{{- if $zsc.enabled -}}
maxSkew: {{ $zsc.maxSkew | default 1 }}
topologyKey: {{ $zsc.topologyKey | default "topology.kubernetes.io/zone" | quote }}
whenUnsatisfiable: {{ $zsc.whenUnsatisfiable | default "DoNotSchedule" | quote }}
labelSelector:
  matchLabels:
    {{- include (printf "quickwit.%s.selectorLabels" $component) $ctx | nindent 4 }}
{{- end -}}
{{- end -}}

{{/*
Render extra environment variables supporting both map and list formats.
Map format (legacy): { KEY: VALUE }
List format (recommended): [{ name: KEY, value: VALUE, valueFrom: ... }]
*/}}
{{- define "quickwit.extraEnv" -}}
{{- if kindIs "map" . -}}
{{- $envList := list -}}
{{- range $key, $value := . -}}
{{- $envList = append $envList (dict "name" $key "value" ($value | toString)) -}}
{{- end -}}
{{- if $envList -}}
{{- toYaml $envList -}}
{{- end -}}
{{- else -}}
{{- with . -}}
{{- toYaml . -}}
{{- end -}}
{{- end -}}
{{- end }}
