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

Grafana folders must use single-word functional categories (`GrafanaFolder` resources provisioned by
`grafana-operator`):

- `overview`: Unified cluster and homelab home dashboard (`cluster-home`).
- `hardware`: Bare-metal hardware, nodes, UPS, power, temperatures.
- `kubernetes`: Core Kubernetes components (pods, etcd, coredns, descheduler).
- `networking`: Ingress, service mesh, DNS, TLS, proxies (traefik, cilium, external-dns, cert-manager).
- `storage`: S3 object storage, block/Ceph, backups (ceph, garage, volsync, backrest).
- `platform`: Shared cluster services, operators, databases, CI/CD, auth (cloudnative-pg, mongodb, valkey, openbao,
  pocket-id, gitea, argocd, loki, blackbox).
- `applications`: End-user self-hosted services and media stack (immich, jellyfin, audiobookshelf, actual, radarr,
  bazarr).
- `iot`: Smart home devices and sensors (airgradient, shelly) — displayed with title `IoT`.

---

## Values Configuration (`values.yaml`)

Specify the default Grafana folder for the chart in `values.yaml`, and optionally override per dashboard filename
(without `.json`) when a single chart ships dashboards targeting different folders:

```yaml
grafanaDashboard:
  folder: applications
  # Optional per-dashboard folder override:
  # folders:
  #   <dashboard-filename>: hardware
```

Folder resolution precedence is: `grafanaDashboard.folders.<name>` → `grafanaDashboard.folder` → first valid folder
category found in `$dashboard.tags` → `"applications"`. Rendering fails fast if the resolved folder is not one of the
valid categories above.

---

## Standard Manifest (`templates/grafana-dashboard.yaml`)

Every chart shipping a dashboard must include this identical standard manifest to deploy `GrafanaDashboard` custom
resources:

```yaml
{{- range $path, $bytes := .Files.Glob "dashboards/*.json" }}
{{- $name := base $path | replace ".json" "" }}
{{- $json := $.Files.Get $path }}
{{- $dashboard := $json | fromJson }}
{{- $cfg := $.Values.grafanaDashboard | default dict }}
{{- $folders := $cfg.folders | default dict }}
{{- $validFolders := list "overview" "hardware" "kubernetes" "networking" "storage" "platform" "applications" "iot" }}
{{- $folder := index $folders $name | default $cfg.folder }}
{{- if not $folder }}
  {{- range ($dashboard.tags | default list) }}
    {{- if and (not $folder) (has . $validFolders) }}
      {{- $folder = . }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $folder = $folder | default "applications" }}
{{- if not (has $folder $validFolders) }}
  {{- fail (printf "Invalid Grafana folder %q for dashboard %q; must be one of: %s" $folder $name (join ", " $validFolders)) }}
{{- end }}
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: {{ $name }}
  namespace: grafana-operator
  labels:
    app.kubernetes.io/name: {{ $name }}
    {{- include "custom.labels" $ | nindent 4 }}
spec:
  instanceSelector:
    matchLabels:
      app: grafana-main
  folderUID: grafana-folder-{{ $folder }}
  resyncPeriod: 6h
  json: |-
{{ $json | indent 4 }}
{{- end }}
```

---

## Dashboard Query & JSON Best Practices

- **Clean Metadata**: Set `"id": null`, `"editable": true`, `"graphTooltip": 1` (shared crosshair), and an explicit
  `"refresh"` matched to the exporter scrape interval (`"1m"` default, `"5m"` for 5m exporters, `"1h"` for 6h
  exporters).
- **Standardized Datasource Variable**: Define a hidden `DS_PROMETHEUS` (`"hide": 2`, `"type": "datasource"`,
  `"query": "prometheus"`, default `"kube-prometheus-stack"`) and reference
  `{"type": "prometheus", "uid": "${DS_PROMETHEUS}"}` across queries (plus hidden `DS_LOKI` /
  `{"type": "loki", "uid": "${DS_LOKI}"}` when querying Loki). Never leave hardcoded datasource UUIDs or legacy string
  datasources.
- **Variable Templating**: Add `$instance` / `$pod` / `$namespace` template variables with `"refresh": 1` or `2` (never
  `0`) for interactive filtering.
- **Rate Intervals & Legends**: Always use `[$__rate_interval]` rather than hardcoded `[1m]` in
  `rate()`/`irate()`/`increase()` (unless the scrape interval exceeds the dashboard's normal range, e.g., use
  `last_over_time(...[12h])` for 6h scrapes). Set explicit `legendFormat` (e.g., `"{{pod}}"`, `"{{job}}"`) to avoid
  merged/ambiguous series.
- **Panel Types**: Never use deprecated `graph` or `singlestat` panels; use `timeseries`, `stat`, `gauge`, `bargauge`,
  `table`, `piechart`, `state-timeline`, `heatmap`, or `logs`.
