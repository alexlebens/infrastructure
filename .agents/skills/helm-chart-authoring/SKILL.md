---
name: helm-chart-authoring
description: Standards and workflows for creating, formatting, and validating homelab deployment Helm charts.
---

# Helm Chart Authoring Workflow

## 1. Initialization

Never scaffold a chart from scratch. Run the standard scaffolder from the `infrastructure` root:

```bash
mise run new-chart <app-name> [namespace]
```

This initializes a standardized chart in `clusters/cl01tl/helm/<app-name>` from `.helm-starters/app-template`.

## 2. Structural Standards

- **Ordering in values.yaml**: In general order the values by the order the upstream chart's values.yaml file. When
  defining spec of resources follow the official ordering in Kubernetes.
- **Security Context**: Prefer when compatible: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and
  `capabilities: drop: ["ALL"]`. Provide an `emptyDir` mount for writeable paths like `/tmp` when read-only root is
  enabled.
- **Template Separation**: Strictly 1 resource kind per file in kebab-case (e.g. `external-secret.yaml`,
  `config-map.yaml`, `service-monitor.yaml`, `grafana-dashboard.yaml`).
- **Spacing**: In (`values.yaml`) separate dependant chart values sections with an empty line.
- **forceRename**: When using app-template charts use forceRename for persistance and services for consistency.
- **Renovate Docker Tags**: In `Chart.yaml`, always use `# renovate: datasource=docker depName=<image-repository>`
  immediately above `appVersion` matching the primary container image repository deployed in `values.yaml` (e.g.
  `ghcr.io/org/app` or `library/image`). Only fallback to `datasource=github-releases` when no container image is
  directly managed in `values.yaml` (e.g. wrapped third-party upstream charts). See
  [references/renovate.md](references/renovate.md).

## 3. Conditional Patterns (Read Only When Applicable)

To preserve token efficiency, inspect only the specific reference file needed for the workload. Ensure the charts and
images are updated to the latest versions:

| Need / Architecture                            | Reference Document                                                   |
| :--------------------------------------------- | :------------------------------------------------------------------- |
| **HTTPRoute & Gateway API**                    | [references/networking-route.md](references/networking-route.md)     |
| **Homepage Dashboard Discovery**               | [references/homepage.md](references/homepage.md)                     |
| **Tailscale Ingress & Exposure**               | [references/tailscale.md](references/tailscale.md)                   |
| **PostgreSQL (CloudNativePG)**                 | [references/databases-cnpg.md](references/databases-cnpg.md)         |
| **MariaDB / MySQL**                            | [references/databases-mariadb.md](references/databases-mariadb.md)   |
| **MongoDB (Percona PSMDB)**                    | [references/databases-mongodb.md](references/databases-mongodb.md)   |
| **Valkey / Redis (Cache & Key-Value)**         | [references/databases-valkey.md](references/databases-valkey.md)     |
| **Secrets & OpenBao (ExternalSecrets)**        | [references/secrets-openbao.md](references/secrets-openbao.md)       |
| **Mail (Postfix) & Push Alerts (ntfy)**        | [references/notifications.md](references/notifications.md)           |
| **Pocket ID OIDC & SSO**                       | [references/auth-sso.md](references/auth-sso.md)                     |
| **Blackbox Probes & Prometheus Metrics**       | [references/observability.md](references/observability.md)           |
| **Grafana Dashboards (Grafana Operator)**      | [references/grafana-dashboards.md](references/grafana-dashboards.md) |
| **Ceph PVCs & VolSync Backups**                | [references/storage-backups.md](references/storage-backups.md)       |
| **S3 Object Storage & OpenTofu**               | [references/storage-s3.md](references/storage-s3.md)                 |
| **Application Configs (`config/`) & Reloader** | [references/configuration.md](references/configuration.md)           |
| **Image Tag Pinning & Renovate Annotations**   | [references/renovate.md](references/renovate.md)                     |

## 4. Validation Sequence

Every chart requires an updated `values.schema.json`. Run the standard validation suite before finishing:

```bash
mise run check-chart <app-name>
```

_(Executes the same stages as the CI `test-chart` workflow: adds repos, builds dependencies, lints, renders manifests,
scans security misconfigurations with Trivy, and validates against schemas with kubeconform. Individual stages can be
executed with `--step <repos|build|lint|render|trivy|kubeconform|all>`)._

## 5. Documentation Sync (Cross-Repo)

Whenever adding or altering an application chart, update the accompanying documentation in the sibling `docs`
repository:

- **Location**: `../docs/docs/Applications/cl01tl/<app-name>.md` (or `docs/docs/...` if opened from parent workspace
  root).
- **Rule**: Follow `docs-core.md` in the `docs` repository.
