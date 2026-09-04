#!/usr/bin/env bash
# Sourceable helper — resolves the Kubernetes namespace for a given Helm chart name.
#
# Charts with non-standard namespace mappings are defined here in a single location
# to keep helm-render-manifests.sh and helm-render-templates.sh in sync.
#
# Usage:
#   source helm-namespace.sh
#   NAMESPACE=$(resolve_namespace "my-chart")

resolve_namespace() {
  local CHART="$1"
  case "${CHART}" in
    "stack")
      echo "argocd"
      ;;
    "cilium" | "coredns" | "metrics-server")
      echo "kube-system"
      ;;
    *)
      echo "${CHART}"
      ;;
  esac
}
