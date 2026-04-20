{{/*
Common labels
*/}}
{{- define "bazarr.labels" -}}
{{ include "bazarr.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "bazarr.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
NFS names
*/}}
{{- define "bazarr.storageNfsName" -}}
bazarr-nfs-storage
{{- end -}}
