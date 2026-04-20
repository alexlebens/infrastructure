{{/*
Common labels
*/}}
{{- define "dawarich.labels" -}}
{{ include "dawarich.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dawarich.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}
