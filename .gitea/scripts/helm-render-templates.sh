#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
source "${SCRIPT_DIR}/helper_helm-namespace.sh"
source "${SCRIPT_DIR}/helper_helm-render.sh"

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

# Build render arguments
RENDER_ARGS=(--chart "${CHART}" --chart-path "${CHART_PATH}")

if [ "${SKIP_RAW}" = false ]; then
  RENDER_ARGS+=(--raw-output-file "${RAW_OUTPUT_DIR}/${CHART}.yaml")
fi

if [ "${SKIP_SPLIT}" = false ]; then
  RENDER_ARGS+=(--split-output-dir "${SPLIT_OUTPUT_DIR:-rendered-split/${CHART}/}")
fi

if [ -n "${API_VERSIONS}" ]; then
  RENDER_ARGS+=(--api-versions "${API_VERSIONS}")
fi

render_helm_chart "${RENDER_ARGS[@]}"

echo ""
echo "----"
