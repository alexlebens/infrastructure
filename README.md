<div align="center">
  <img src="https://cdn.jsdelivr.net/gh/selfhst/icons/png/kubernetes.png" width="120" alt="Infrastructure Logo" />
  <h1>alexlebens.net Infrastructure</h1>
  <p><em>GitOps-defined infrastructure and cluster configurations for the alexlebens.net domain.</em></p>
</div>

---

This repository serves as the single source of truth for all GitOps deployments, cluster configurations, and
infrastructure-as-code for my personal homelab environments.

## Features

- **GitOps Architecture**: All infrastructure is declaratively defined and automatically reconciled using ArgoCD.
- **App-of-Apps Pattern**: Clusters are bootstrapped and managed using the App-of-Apps deployment pattern for maximum
  scalability and maintainability.
- **Automated Dependency Updates**: Monitored and automatically updated using Renovate to keep all Helm charts,
  manifests, and system configurations secure and current.

## Clusters

### `cl01tl`

This is the primary cluster environment.

![Stack-cl01tl Badge](https://argocd.alexlebens.net/api/badge?name=stack-cl01tl&revision=true&showAppName=true)

- **Deployment Mechanism**: Managed via the `stack-cl01tl` App-of-Apps Application.
- **Dashboard**: Configurations sync automatically via ArgoCD.

## Hosts

System-level and node-specific configurations for the following hosts:

- `pd05wd`
- `ps08rp`
- `ps09rp`
- `ps10rp`

## Repository Structure

- `clusters/`: Environment-specific configurations, workloads, and Helm charts for different Kubernetes clusters.
- `hosts/`: Individual node configurations and system-level definitions.

## License

This project is open-source and licensed under the terms of the Apache 2.0 License. See the [LICENSE](LICENSE) file for
more details.
