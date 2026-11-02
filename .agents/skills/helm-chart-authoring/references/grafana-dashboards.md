# Grafana Dashboards Reference

Dashboards are managed declaratively using the Grafana Operator and exported JSON definitions stored within the
application chart.

---

## File Placement

Place exported dashboard JSON files directly into the `dashboards/` directory of the Helm chart:

```text
clusters/cl01tl/helm/<app-name>/
├── Chart.yaml
├── dashboards/
│   └── <app-name>.json
├── templates/
│   └── grafana-dashboard.yaml
└── values.yaml
```

---

## Folder Categories (Taxonomy)

Grafana folders must use single-word functional categories:

- `hardware`: Bare-metal hardware, nodes, UPS, power, temperatures.
- `kubernetes`: Core Kubernetes components (pods, etcd, coredns, descheduler).
- `networking`: Ingress, service mesh, DNS, TLS, proxies (traefik, cilium, external-dns, cert-manager).
- `storage`: S3 object storage, block/CeSI, backups (ceph, garage, volsync, backrest).
- `platform`: Shared cluster services, operators, databases, CI/CD, auth (cloudnative-pg, mongodb, valkey, openbao,
  pocket-id, gitea, argocd, loki, blackbox).
- `applications`: End-user self-hosted services and media stack (immich, jellyfin, audiobookshelf, actual, radarr,
  bazarr).
- `iot`: Smart home devices and sensors (airgradient, shelly).

---

## Values Configuration (`values.yaml`)

Specify the target Grafana folder in `values.yaml`:

```yaml
grafanaDashboard:
  folder: applications
```

---

## Standard Manifest (`templates/grafana-dashboard.yaml`)

Every chart shipping a dashboard must include this standard manifest to deploy `GrafanaDashboard` custom resources:

```yaml
{{- range $path, $bytes := .Files.Glob "dashboards/*.json" }}
{{- $name := base $path | replace ".json" "" }}
{{- $json := $.Files.Get $path }}
{{- $dashboard := $json | fromJson }}
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: {{ $name }}
  namespace: grafana-operator
  labels:
    app.kubernetes.io/name: {{ $name }}
    {{- include "common-helpers.labels" $ | default (include "homelab-app.labels" $) | nindent 4 }}
spec:
  instanceSelector:
    matchLabels:
      app: grafana-main
{{- $folder := $.Values.grafanaDashboard.folder | default (index ($dashboard.tags | default (list "applications")) 0) }}
  folderUID: grafana-folder-{{ $folder }}
  resyncPeriod: 6h
  json: |-
{{ $json | indent 4 }}
{{- end }}
```

---

## Dashboard Query & JSON Best Practices

- **Variable Templating**: Always add `$instance` / `$pod` template variables to panel queries to allow
  per-pod/per-instance filtering.
- **Legend Formats**: Explicitly set `legendFormat: "{{job}}"` or `{{pod}}` to avoid merged/ambiguous series in
  VictoriaMetrics / Prometheus.
- **Export Cleanup**: Ensure exported JSON does not contain hardcoded datasource UUIDs (use default or variable
  datasource where possible) or ephemeral cluster credentials.
