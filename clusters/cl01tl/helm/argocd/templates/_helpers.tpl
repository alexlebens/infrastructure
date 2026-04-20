{{/*
Common labels
*/}}
{{- define "argocd.labels" -}}
{{ include "argocd.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "argocd.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}
