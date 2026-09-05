<div align="center">
  <img src="https://web-assets.alexlebens.dev/logo/logo.png" width="120" alt="Infrastructure Logo" />
  <h1>alexlebens.dev Infrastructure</h1>
  <p><em>GitOps-defined infrastructure and cluster configurations for my homelab and personal systems.</em></p>
</div>

---

## Features

- **GitOps Architecture**: All Kubernetes infrastructure and workloads are declaratively defined and automatically
  reconciled using ArgoCD.
- **App-of-Apps Pattern**: Clusters are bootstrapped and managed using the App-of-Apps deployment pattern for clean
  modularity, scalability, and maintainability.
- **Rendered Manifests Pipeline**: Helm charts are rendered into pure Kubernetes manifests via CI workflows
  (`render-manifests.yaml`), keeping the rendered state versioned on the `manifests` branch for automated, transparent
  GitOps reconciliation.
- **Automated PR Tracking & Diffing**: CI runs live ArgoCD diffs and Trivy security/misconfiguration scans on PRs,
  posting detailed feedback and maintaining update logs across runs.
- **Automated Dependency Updates**: Continuous dependency maintenance via Renovate to keep Docker images, Helm charts,
  GitHub Actions, and system components up to date.
- **Automated Backup Schedule Rebalancing**: Workflows routinely stagger VolSync and CloudNativePG backup schedules
  across off-peak hours to eliminate storage and snapshot collisions.

## Clusters

### `cl01tl`

Primary Kubernetes cluster running containerized workloads, core platforms, and persistent services.

[![Stack-cl01tl Badge](https://argocd.alexlebens.dev/api/badge?name=stack-cl01tl&revision=true&showAppName=true)](https://argocd.alexlebens.dev/applications/stack-cl01tl)

- **Deployment Mechanism**: Bootstrapped and orchestrated via the `stack-cl01tl` root App-of-Apps Application.
- **Synchronization**: Automatically reconciled against target branches via ArgoCD.

## Hosts

Host-level and node-specific Docker Compose services and configurations:

- `pd05wd`
- `ps08rp`
- `ps09rp`
- `ps10rp`

## Repository Structure

```text
infrastructure/
├── .gitea/
│   ├── scripts/     # Modular CI/CD helper scripts (rendering, PR automation, diffs, scanning)
│   └── workflows/   # Gitea Actions CI/CD workflows
├── clusters/
│   └── cl01tl/
│       └── helm/    # Helm charts and values files for Kubernetes workloads
├── hosts/           # Host-level services and compose configurations per node
└── renovate.json    # Renovate bot configuration and schedule rules
```

## CI / CD Workflows

- **`test-helm.yaml`**: Validates modified Helm charts using `helm lint`, `kubeconform`, server-side `kubectl` schema
  validation, ArgoCD live diffing, and Trivy security auditing.
- **`test-docker.yaml`**: Validates Docker Compose files across hosts using Compose linter and formatting checks.
- **`render-manifests.yaml`**: Renders changed Helm charts into raw Kubernetes manifests on the `manifests` branch and
  manages automated sync Pull Requests.
- **`rebalance-backup-schedules.yaml`**: Automatically staggers VolSync PVC backup snapshots and CloudNativePG backup
  jobs.
- **`prettier.yaml`**: Enforces consistent code style and formatting across YAML, JSON, and Markdown.

## License

This project is open-source and licensed under the terms of the Apache 2.0 License. See the [LICENSE](LICENSE) file for
more details.
