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
NFS names
*/}}
{{- define "custom.storageImportNfsName" -}}
shelfmark-import-nfs-storage
{{- end -}}
{{- define "custom.storageAudiobooksNfsName" -}}
shelfmark-audiobooks-nfs-storage
{{- end -}}
{{- define "custom.storageDownloadsNfsName" -}}
shelfmark-downloads-nfs-storage
{{- end -}}
