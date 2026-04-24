{{/*
Common labels
*/}}
{{- define "custom.labels" -}}
{{ include "custom.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "custom.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
ClusterRole names
*/}}
{{- define "custom.certificatesName" -}}
"certificates-{{ .Release.Name }}"
{{- end -}}
{{- define "custom.eventsName" -}}
"events-{{ .Release.Name }}"
{{- end -}}
