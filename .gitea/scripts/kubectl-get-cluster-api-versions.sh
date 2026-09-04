#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0"
      echo "Fetches Kubernetes cluster API versions and CRD kinds, outputting them formatted for Helm."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

CLUSTER_API_VERSIONS=$(kubectl api-versions | tr '\n' ',')
CLUSTER_CRD_KINDS=$(kubectl get crd -o json | jq -r '.items[] | .spec.group as $group | .spec.names.kind as $kind | .spec.versions[] | select(.served == true) | "\($group)/\(.name)/\($kind)"' | paste -sd, -)

# Merge versions and kinds
API_VERSIONS="${CLUSTER_API_VERSIONS},${CLUSTER_CRD_KINDS}"

# Format and deduplicate for helm
API_VERSIONS=$(echo "${API_VERSIONS}" | awk -F, '{for(i=1;i<=NF;i++) if($i!="") print $i}' | sort -u | paste -sd, -)

echo ">> API Versions:"
echo "${API_VERSIONS}"

echo ""
echo "----"

if [ -n "${GITHUB_OUTPUT}" ]; then
  echo "api-versions=${API_VERSIONS}" >> "${GITHUB_OUTPUT}"
fi
