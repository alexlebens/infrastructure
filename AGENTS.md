# Agent Guidelines (Infrastructure)

- **Git & Safety**: Read-only git (`status`, `diff`, `log`). No mutating `kubectl` (`apply`, `delete`, `patch`, `scale`)
  unless asked. Read-only diagnostics permitted.
- **GitOps & State**: Declarative edits only via `clusters/cl01tl/helm/` or `tofu/`. Never edit generated outputs
  directly. Use `tmp/` for scratch files.
- **Helm**: Scaffolding via `mise run new-chart <name> [ns]`; validate via `mise run check-chart <name>` (runs repos,
  build, lint, render, trivy, kubeconform). Use `bjw-s/app-template` v5 with chart alias matching `<app-name>`.
- **Images**: Pin tag and digest (`<tag>@sha256:<hash>`); prefer Docker Hub; never `latest`.
- **Storage**: S3 buckets are managed via OpenTofu in `tofu/buckets/` (`s3-bucket:` in `values.yaml`). Never create
  ad-hoc or embed MinIO subcharts.
- **Conventions**: Consult `helm-chart-authoring` skill for ordering and modular refs (`databases-*`, `secrets-openbao`,
  `storage-s3`, `auth-sso`).
