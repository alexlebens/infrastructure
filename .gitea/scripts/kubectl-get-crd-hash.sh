#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0"
      echo "Calculates a SHA256 hash of cluster CRD names and generations for cache busting."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

CRD_HASH=$(kubectl get crds -o jsonpath='{range .items[*]}{.metadata.name}:{.metadata.generation}{"\n"}{end}' | sha256sum | awk '{print $1}')

echo ">> Cluster CRD Hash:"
echo "${CRD_HASH}"

echo ""
echo "----"

if [ -n "${GITHUB_OUTPUT}" ]; then
  echo "hash=${CRD_HASH}" >> "${GITHUB_OUTPUT}"
fi
