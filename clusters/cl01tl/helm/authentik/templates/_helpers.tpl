{{/*
Common labels
*/}}
{{- define "authentik.labels" -}}
{{ include "authentik.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "authentik.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}
