{{/*
Common labels
*/}}
{{- define "audiobookshelf.labels" -}}
{{ include "audiobookshelf.selectorLabels" $ }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "audiobookshelf.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
NFS names
*/}}
{{- define "audiobookshelf.booksNfsName" -}}
audiobookshelf-books-nfs-storage
{{- end -}}
{{- define "audiobookshelf.audiobooksNfsName" -}}
audiobookshelf-audiobooks-nfs-storage
{{- end -}}
{{- define "audiobookshelf.podcastsNfsName" -}}
audiobookshelf-podcasts-nfs-storage
{{- end -}}
