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
{{- define "custom.storageNfsName" -}}
jellyfin-nfs-storage
{{- end -}}
{{- define "custom.storageYoutubeNfsName" -}}
jellyfin-youtube-nfs-storage
{{- end -}}
