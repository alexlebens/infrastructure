#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
source "${SCRIPT_DIR}/helm-namespace.sh"

# Parse optional command-line flags
CHART="${CHART:-}"
CLUSTER="${CLUSTER:-cl01tl}"
API_VERSIONS="${API_VERSIONS:-}"
RAW_OUTPUT_DIR="${RAW_OUTPUT_DIR:-rendered-raw}"
SPLIT_OUTPUT_DIR=""
SKIP_RAW=false
SKIP_SPLIT=false

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
    --api-versions)
      API_VERSIONS="$2"
      shift 2
      ;;
    --raw-output-dir)
      RAW_OUTPUT_DIR="$2"
      shift 2
      ;;
    --split-output-dir)
      SPLIT_OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-raw)
      SKIP_RAW=true
      shift
      ;;
    --skip-split)
      SKIP_SPLIT=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>] [--api-versions <versions>] [--raw-output-dir <dir>] [--split-output-dir <dir>] [--skip-raw] [--skip-split]"
      echo "Renders Helm templates and splits them into manifest files for a single chart."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ]; then
  echo "Error: --chart or CHART environment variable is required." >&2
  exit 1
fi

CHART_PATH="clusters/${CLUSTER}/helm/${CHART}"

if [ ! -d "${CHART_PATH}" ] || [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
  echo "Error: Chart '${CHART}' not found at '${CHART_PATH}' or missing Chart.yaml." >&2
  exit 1
fi

# Determine namespace
NAMESPACE=$(resolve_namespace "${CHART}")

VALUES_ARGS=()
if [ -f "${CHART_PATH}/values.yaml" ]; then
  VALUES_ARGS+=("-f" "${CHART_PATH}/values.yaml")
fi

HELM_ARGS=("${CHART}" "${CHART_PATH}" "${VALUES_ARGS[@]}" --include-crds --namespace "${NAMESPACE}")
if [ -n "${API_VERSIONS}" ]; then
  HELM_ARGS+=(--api-versions "${API_VERSIONS}")
fi

echo ">> Rendering chart '${CHART}' into '${NAMESPACE}' namespace ..."

RAW_FILE="${RAW_OUTPUT_DIR}/${CHART}.yaml"

if [ "${SKIP_RAW}" = false ]; then
  mkdir -p "${RAW_OUTPUT_DIR}"
  helm template "${HELM_ARGS[@]}" > "${RAW_FILE}"
  echo ">> Raw template saved to ${RAW_FILE}"
else
  RAW_FILE=$(mktemp)
  helm template "${HELM_ARGS[@]}" > "${RAW_FILE}"
fi

# Split into individual manifest files
if [ "${SKIP_SPLIT}" = false ]; then
  SPLIT_DIR="${SPLIT_OUTPUT_DIR:-rendered-split/${CHART}/}"
  [[ "${SPLIT_DIR}" != */ ]] && SPLIT_DIR="${SPLIT_DIR}/"

  mkdir -p "${SPLIT_DIR}"
  echo ">> Splitting manifests into ${SPLIT_DIR} ..."

  cat "${RAW_FILE}" \
    | yq '... comments=""' \
    | yq 'select(. != null)' \
    | yq -s '"'"${SPLIT_DIR}"'" + .kind + "-" + .metadata.name + ".yaml"'

  for file in "${SPLIT_DIR}"*; do
    if [ -f "${file}" ]; then
      yq -i '... comments=""' "${file}"
    fi
  done

  echo ">> Split templates created successfully for ${CHART}"
fi

if [ "${SKIP_RAW}" = true ]; then
  rm -f "${RAW_FILE}"
fi

echo ""
echo "----"
