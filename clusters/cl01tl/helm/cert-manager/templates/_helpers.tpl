{{/*
Common labels
*/}}
{{- define "cert-manager.labels" -}}
{{ include "cert-manager.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cert-manager.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
NFS names
*/}}
{{- define "cert-manager.cloudflareSecretName" -}}
cert-manager-cloudflare-api-token
{{- end -}}
{{- define "cert-manager.cloudflareSecretKey" -}}
api-token
{{- end -}}
