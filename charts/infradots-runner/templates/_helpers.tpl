{{- define "runner.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "runner.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "runner.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: infradots
{{- end }}

{{/* Selector labels of one component: "agent" or "executor". */}}
{{- define "runner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "runner.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "runner.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "runner.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* The Secret and key holding a component's registration token; fails when neither is configured. */}}
{{- define "runner.tokenSecretName" -}}
{{- $registration := index .root.Values .component "registration" }}
{{- if $registration.existingSecret }}
{{- $registration.existingSecret }}
{{- else if $registration.token }}
{{- printf "%s-%s" (include "runner.fullname" .root) .component }}
{{- else }}
{{- fail (printf "%s.registration: set existingSecret (recommended) or token -- the %s pool's registration token" .component .component) }}
{{- end }}
{{- end }}

{{- define "runner.tokenSecretKey" -}}
{{- $registration := index .root.Values .component "registration" }}
{{- if $registration.existingSecret }}{{ $registration.existingSecretKey }}{{ else }}REGISTRATION_TOKEN{{ end }}
{{- end }}

{{- define "runner.proxyEnv" -}}
{{- with .Values.proxy.httpsProxy }}
- name: HTTPS_PROXY
  value: {{ . | quote }}
- name: https_proxy
  value: {{ . | quote }}
{{- end }}
{{- with .Values.proxy.httpProxy }}
- name: HTTP_PROXY
  value: {{ . | quote }}
- name: http_proxy
  value: {{ . | quote }}
{{- end }}
{{- with .Values.proxy.noProxy }}
- name: NO_PROXY
  value: {{ . | quote }}
- name: no_proxy
  value: {{ . | quote }}
{{- end }}
{{- end }}

{{- define "runner.idpUrl" -}}
{{- .Values.idpUrl | trimSuffix "/" }}
{{- end }}

{{/* The executor's per-job websocket: wss:// for an https platform URL, ws:// for http. */}}
{{- define "runner.websocketUrl" -}}
{{- include "runner.idpUrl" . | replace "https://" "wss://" | replace "http://" "ws://" }}/ws/worker/
{{- end }}
