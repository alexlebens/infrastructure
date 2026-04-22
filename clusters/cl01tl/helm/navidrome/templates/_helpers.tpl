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
{{- define "custom.storageMusicNfsName" -}}
navidrome-music-nfs-storage
{{- end -}}
{{- define "custom.storageMusicYoutubeNfsName" -}}
navidrome-music-youtube-nfs-storage
{{- end -}}
{{- define "custom.storageMusicGrabberNfsName" -}}
navidrome-music-grabber-nfs-storage
{{- end -}}
{{- define "custom.storageMusicSingleNfsName" -}}
navidrome-music-single-nfs-storage
{{- end -}}
