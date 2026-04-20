{{/*
Common labels
*/}}
{{- define "cilium.labels" -}}
{{ include "cilium.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cilium.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}
