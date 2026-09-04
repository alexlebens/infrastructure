#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
CHART=""
CLUSTER="${CLUSTER:-cl01tl}"
API_VERSIONS="${API_VERSIONS:-}"
RAW_OUTPUT_DIR=""
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
      echo "Renders Helm templates and splits them into manifest files."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

CHARTS="${CHART:-${CHANGED_CHARTS:-}}"

if [ -z "${CHARTS}" ]; then
  echo "Error: --chart or CHART/CHANGED_CHARTS environment variable is required." >&2
  exit 1
fi

for C in ${CHARTS}; do
  CHART_PATH="clusters/${CLUSTER}/helm/${C}"

  if [ ! -d "${CHART_PATH}" ] || [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
    echo "Error: Chart '${C}' not found at '${CHART_PATH}' or missing Chart.yaml." >&2
    exit 1
  fi

  # Determine namespace
  NAMESPACE="${C}"
  case "${C}" in
    "stack")
      NAMESPACE="argocd"
      ;;
    "cilium" | "coredns" | "metrics-server")
      NAMESPACE="kube-system"
      ;;
  esac

  VALUES_ARGS=()
  if [ -f "${CHART_PATH}/values.yaml" ]; then
    VALUES_ARGS+=("-f" "${CHART_PATH}/values.yaml")
  fi

  HELM_ARGS=("${C}" "${CHART_PATH}" "${VALUES_ARGS[@]}" --include-crds --namespace "${NAMESPACE}")
  if [ -n "${API_VERSIONS}" ]; then
    HELM_ARGS+=(--api-versions "${API_VERSIONS}")
  fi

  echo ">> Rendering chart '${C}' into '${NAMESPACE}' namespace ..."

  # Determine raw output file
  C_RAW_DIR="${RAW_OUTPUT_DIR:-rendered-raw}"
  RAW_FILE="${C_RAW_DIR}/${C}.yaml"

  if [ "${SKIP_RAW}" = false ]; then
    mkdir -p "${C_RAW_DIR}"
    helm template "${HELM_ARGS[@]}" > "${RAW_FILE}"
    echo ">> Raw template saved to ${RAW_FILE}"
  else
    RAW_FILE=$(mktemp)
    helm template "${HELM_ARGS[@]}" > "${RAW_FILE}"
  fi

  # Determine split output folder
  if [ "${SKIP_SPLIT}" = false ]; then
    if [ -n "${SPLIT_OUTPUT_DIR}" ]; then
      C_SPLIT_DIR="${SPLIT_OUTPUT_DIR}"
    else
      C_SPLIT_DIR="rendered-split/${C}/"
    fi
    [[ "${C_SPLIT_DIR}" != */ ]] && C_SPLIT_DIR="${C_SPLIT_DIR}/"

    mkdir -p "${C_SPLIT_DIR}"
    echo ">> Splitting manifests into ${C_SPLIT_DIR} ..."

    cat "${RAW_FILE}" \
      | yq '... comments=""' \
      | yq 'select(. != null)' \
      | yq -s '"'"${C_SPLIT_DIR}"'" + .kind + "-" + .metadata.name + ".yaml"'

    for file in "${C_SPLIT_DIR}"*; do
      if [ -f "${file}" ]; then
        yq -i '... comments=""' "${file}"
      fi
    done

    echo ">> Split templates created successfully for ${C}"
  fi

  if [ "${SKIP_RAW}" = true ]; then
    rm -f "${RAW_FILE}"
  fi

  echo ""
  echo "----"
done
