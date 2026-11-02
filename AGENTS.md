# Agent Guidelines (Infrastructure)

## 1. Safety & GitOps Constraints

- **Git**: Strictly read-only (`git status`, `git diff`, `git log`). Never commit, push, or rewrite history.
- **Cluster Diagnostics**: Read-only `kubectl` commands (`get`, `describe`, `logs`, `exec`) are permitted. Never execute
  mutating commands (`apply`, `delete`, `patch`, `scale`) unless explicitly requested by the user.
- **GitOps Declarative State**: Never edit generated output files directly. All changes must be made declaratively in
  source charts (`clusters/cl01tl/helm/`) or OpenTofu (`tofu/`).
- **Temporary Files**: Write temporary test files or scratch output to `tmp/` only.

## 2. Helm & Chart Standards

- **Scaffolding**: Never create Helm charts from scratch; always run `mise run new-chart <name> [namespace]`.
- **Validation**: Verify charts using `mise run check-chart clusters/cl01tl/helm/<name>`.
- **App-Template**: Application charts must use `bjw-s/app-template` v5 with the chart alias matching `<app-name>`.
- **Pinning**: Pin container images with tag and digest (`<tag>@sha256:<hash>`), preferring Docker Hub. Never use
  `latest`.
- **Skills**: Consult `helm-chart-authoring` for conventions, values ordering, and modular references (`databases-*`,
  `secrets-openbao`, `storage-s3`, `auth-sso`).

## 3. OpenTofu & Object Storage

- S3 buckets are managed declaratively via OpenTofu in `tofu/buckets/`.
- Never create S3 buckets via ad-hoc CLI commands or embed MinIO subcharts. Configure `s3-bucket:` in `values.yaml` and
  run OpenTofu.

## 4. Token Efficiency & Diagnostics

- **Targeted Output**: Always scope `kubectl` and `helm` diagnostics using `json
