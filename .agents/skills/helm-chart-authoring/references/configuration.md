# Configuration Files & ConfigMaps Reference

Guidelines for application configuration files, scripts, and rolling reloaders.

---

## Dedicated `config/` Directory

- Application configuration files (`.yaml`, `.json`, `.toml`, `.ini`, `.conf`) must be placed in a dedicated `config/`
  directory within the chart.
- **Rule:** Never embed multi-line raw configuration text blocks directly into `values.yaml`.

---

## ConfigMap Manifest (`templates/config-map.yaml`)

Import configuration files dynamically using Helm's `.Files.Glob`. Replace 'app name' with an appropriate name:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: <app name>-config
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: <app name>-config
    {{- include "custom.labels" . | nindent 4 }}
data:
  {{- (.Files.Glob "config/*").AsConfig | nindent 2 }}

```

Alternatively, for specific single-file injection:

```yaml
data:
  config.toml: |-
    {{- .Files.Get "config/config.toml" | nindent 4 }}
```

---

## Mounting & Reloader (app-template)

In `app-template`, configuration ConfigMaps and Stakater Reloader annotations are configured declaratively in
`values.yaml`:

### 1. Mounting ConfigMap via `persistence`

Mount the generated ConfigMap under `persistence` in `values.yaml`:

```yaml
persistence:
  config:
    type: configMap
    name: <app-name>-config
    globalMounts:
      - path: /etc/app/config
        readOnly: true
```

For mounting a specific single configuration file using `subPath`:

```yaml
persistence:
  config:
    type: configMap
    name: <app-name>-config
    advancedMounts:
      main:
        main:
          - path: /app/config.json
            subPath: config.json
            readOnly: true
```

### 2. Auto-Reloading via Reloader

Add the Stakater Reloader annotation to the controller `annotations` block in `values.yaml` so any change to
configuration files triggers a rolling pod restart automatically:

```yaml
controllers:
  main:
    type: deployment
    annotations:
      reloader.stakater.com/auto: 'true'
```

---

## Scripts (`scripts/`)

If a workload requires custom entrypoints, initialization scripts, or database migration scripts:

1. Store executable scripts in a `scripts/` directory within the chart.
2. Import them into a ConfigMap (`templates/scripts-config-map.yaml`) using `.Files.Glob "scripts/*"` or `.Files.Get`.
3. Mount the scripts ConfigMap via `persistence` in `values.yaml` with executable permissions (`defaultMode: 0755`):

```yaml
persistence:
  scripts:
    type: configMap
    name: <app-name>-scripts
    defaultMode: 0755
    globalMounts:
      - path: /scripts
        readOnly: true
```
