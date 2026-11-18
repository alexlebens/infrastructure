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

Dashboard provisioning is managed centrally through the `common-helpers` dependency (`>= 1.3.0`). Configure the default
folder (and optional per-dashboard overrides keyed by filename without `.json`) under `common-helpers.grafanaDashboard`:

```yaml
common-helpers:
  grafanaDashboard:
    enabled: true
    folder: applications
    # Optional per-dashboard override (keyed by filename without .json):
    # <dashboard-filename>:
    #   enabled: true
    #   folder: hardware
```

Multi-dashboard charts with dashboards in different folders (for example `kube-prometheus-stack` or `grafana-operator`)
key each dashboard explicitly under `common-helpers.grafanaDashboard.<name>`. Per-dashboard entries also support Grafana
Operator CRD options (`folderUID`, `folderRef`, `resyncPeriod`, `uid`, `datasources`, `plugins`, `variables`) and
remote/inline sources (`url`, `grafanaCom`, `oci`, `configMapRef`, `json`, `jsonnet`).

Folder resolution precedence is: `item.folderRef` → `item.folderUID` → `item.folder` → `defaults.folderRef` →
`defaults.folderUID` → `defaults.folder` → `"applications"`. Both `common-helpers`'s `values.schema.json` enum and
template rendering validate folders fail-fast against the 8 taxonomy categories above.

---

## Standard Manifest (`templates/grafana-dashboard.yaml`)

Every chart shipping local `dashboards/*.json` files must include this single-line template referencing
`common-helpers`:

```yaml
{{- include "custom.grafanaDashboards" . }}
```

_(Charts using only remote/inline sources such as `url` or `grafanaCom` under `common-helpers.grafanaDashboard.<name>`
do not need a local `templates/grafana-dashboard.yaml` at all.)_

---

## Dashboard Query & JSON Best Practices

- **Clean Metadata**: Standardize every dashboard's top-level schema to match the canonical template (`editable: false`,
  `fiscalYearStartMonth: 0`, `graphTooltip: 1`, `links: []`, `liveNow: false`, `schemaVersion: 42`, `timepicker: {}`,
  `timezone: "browser"`, `id: null`), preserve each dashboard's `time` period, `title`, `uid`, `tags`, `annotations`,
  `panels`, and `templating`, and omit `refresh`, `version`, `preload`, `weekStart`, `__requires`, and `description`.
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
