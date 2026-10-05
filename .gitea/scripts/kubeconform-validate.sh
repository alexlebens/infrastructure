#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
CHART="${CHART:-}"
CLUSTER="${CLUSTER:-cl01tl}"
MANIFEST_PATH="${MANIFEST_PATH:-}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-}"
IGNORE_MISSING_SCHEMAS="${IGNORE_MISSING_SCHEMAS:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart)
      CHART="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --manifest|--manifest-path|--manifest-dir)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --kubernetes-version)
      KUBERNETES_VERSION="$2"
      shift 2
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>] [--manifest <file|dir>] [--kubernetes-version <version>] [--strict]"
      echo "Validates rendered Kubernetes manifests using kubeconform."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ] && [ -z "${MANIFEST_PATH}" ]; then
  echo "Error: --chart (or CHART env var) or --manifest is required." >&2
  exit 1
fi

if [ -z "${MANIFEST_PATH}" ]; then
  MANIFEST_PATH="clusters/${CLUSTER}/manifests/${CHART}"
fi

if [ ! -e "${MANIFEST_PATH}" ]; then
  echo "Error: Manifest path '${MANIFEST_PATH}' not found." >&2
  exit 1
fi

echo ">> Running kubeconform validation for: ${CHART:-$(basename "${MANIFEST_PATH}")}"

# Build kubeconform arguments
SCHEMA_DIR="${HOME}/.schemas"

KUBECONFORM_ARGS=(
  -summary
  -output text
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
  -schema-location "${SCHEMA_DIR}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
)

if [ -n "${KUBERNETES_VERSION}" ]; then
  # Strip leading 'v' if present for kubeconform
  KUBECONFORM_ARGS+=(-kubernetes-version "${KUBERNETES_VERSION#v}")
fi

if [ "${IGNORE_MISSING_SCHEMAS}" = "true" ]; then
  KUBECONFORM_ARGS+=(-ignore-missing-schemas)
fi

if [ "${STRICT:-false}" = "true" ]; then
  KUBECONFORM_ARGS+=(-strict)
fi

# Run kubeconform against the rendered manifests
if [ -d "${MANIFEST_PATH}" ]; then
  shopt -s nullglob
  MANIFEST_FILES=("${MANIFEST_PATH}"/*.yaml)
  shopt -u nullglob

  if [ ${#MANIFEST_FILES[@]} -eq 0 ]; then
    echo ">> No manifest files found in ${MANIFEST_PATH}. Skipping validation."
    exit 0
  fi

  kubeconform "${KUBECONFORM_ARGS[@]}" "${MANIFEST_FILES[@]}"
else
  kubeconform "${KUBECONFORM_ARGS[@]}" "${MANIFEST_PATH}"
fi

echo ""
echo ">> kubeconform validation completed successfully."
echo "----"
