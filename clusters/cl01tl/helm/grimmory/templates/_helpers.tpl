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
{{- define "custom.booksNfsName" -}}
grimmory-books-nfs-storage
{{- end -}}
{{- define "custom.booksImportNfsName" -}}
grimmory-books-import-nfs-storage
{{- end -}}
