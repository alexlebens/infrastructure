{{/*
Common labels
*/}}
{{- define "backrest.labels" -}}
{{ include "backrest.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backrest.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
NFS names
*/}}
{{- define "backrest.storageNfsName" -}}
backrest-nfs-storage
{{- end -}}
{{- define "backrest.shareNfsName" -}}
backrest-nfs-share
{{- end -}}
