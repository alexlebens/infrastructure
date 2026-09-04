#!/usr/bin/env bash
# Sourceable helper — renders a single Helm chart to raw and/or split output.
#
# Requires: resolve_namespace (from helper_helm-namespace.sh) to be available.
#
# Usage:
#   source helper_helm-namespace.sh
#   source helper_helm-render.sh
#   render_helm_chart --chart <name> --chart-path <path> [options]
#
# Options:
#   --chart <name>            Chart name (required)
#   --chart-path <path>       Path to chart directory (required)
#   --raw-output-file <file>  Persist raw template to this file (optional, uses temp if omitted)
#   --split-output-dir <dir>  Split manifests into this directory (optional, skips split if omitted)
#   --api-versions <versions> API versions string for helm template (optional)
#   --build-deps              Build helm dependencies before rendering (optional)
#   --cleanup-raw             Delete raw file after split even if not temp (optional)

render_helm_chart() {
  local CHART="" CHART_PATH="" RAW_OUTPUT_FILE="" SPLIT_OUTPUT_DIR=""
  local API_VERSIONS="" BUILD_DEPS=false CLEANUP_RAW=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chart) CHART="$2"; shift 2 ;;
      --chart-path) CHART_PATH="$2"; shift 2 ;;
      --raw-output-file) RAW_OUTPUT_FILE="$2"; shift 2 ;;
      --split-output-dir) SPLIT_OUTPUT_DIR="$2"; shift 2 ;;
      --api-versions) API_VERSIONS="$2"; shift 2 ;;
      --build-deps) BUILD_DEPS=true; shift ;;
      --cleanup-raw) CLEANUP_RAW=true; shift ;;
      *) echo "Unknown argument to render_helm_chart: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "${CHART}" ] || [ -z "${CHART_PATH}" ]; then
    echo "Error: --chart and --chart-path are required." >&2
    return 1
  fi

  # Resolve namespace via shared helper
  local NAMESPACE
  NAMESPACE=$(resolve_namespace "${CHART}")

  # Build values args
  local VALUES_ARGS=()
  if [ -f "${CHART_PATH}/values.yaml" ]; then
    VALUES_ARGS+=("-f" "${CHART_PATH}/values.yaml")
  fi

  # Build helm template args
  local HELM_ARGS=("${CHART}" "${CHART_PATH}" "${VALUES_ARGS[@]}" --include-crds --namespace "${NAMESPACE}")
  if [ -n "${API_VERSIONS}" ]; then
    HELM_ARGS+=(--api-versions "${API_VERSIONS}")
  fi

  # Build dependencies if requested
  if [ "${BUILD_DEPS}" = true ]; then
    pushd "${CHART_PATH}" > /dev/null
    helm dependency build --skip-refresh > /dev/null 2>&1 || helm dependency update --skip-refresh > /dev/null 2>&1 || true
    popd > /dev/null
  fi

  echo ">> Rendering chart '${CHART}' into '${NAMESPACE}' namespace ..."

  # Render to raw file
  local RAW_FILE
  local RAW_IS_TEMP=false
  if [ -n "${RAW_OUTPUT_FILE}" ]; then
    RAW_FILE="${RAW_OUTPUT_FILE}"
    mkdir -p "$(dirname "${RAW_FILE}")"
  else
    RAW_FILE="$(mktemp)"
    RAW_IS_TEMP=true
  fi

  if ! helm template "${HELM_ARGS[@]}" > "${RAW_FILE}" 2>/dev/null; then
    echo ">> Failed helm template for ${CHART}" >&2
    rm -f "${RAW_FILE}"
    return 1
  fi

  if [ "${RAW_IS_TEMP}" = false ]; then
    echo ">> Raw template saved to ${RAW_FILE}"
  fi

  # Split into individual manifest files
  if [ -n "${SPLIT_OUTPUT_DIR}" ]; then
    local SPLIT_DIR="${SPLIT_OUTPUT_DIR}"
    [[ "${SPLIT_DIR}" != */ ]] && SPLIT_DIR="${SPLIT_DIR}/"

    mkdir -p "${SPLIT_DIR}"
    echo ">> Splitting manifests into ${SPLIT_DIR} ..."

    set -o pipefail
    if ! cat "${RAW_FILE}" \
      | yq '... comments=""' \
      | yq 'select(. != null)' \
      | yq -s '"'"${SPLIT_DIR}"'" + .kind + "-" + .metadata.name + ".yaml"' > /dev/null 2>&1; then
      echo ">> Failed yq splitting for ${CHART}" >&2
      if [ "${RAW_IS_TEMP}" = true ] || [ "${CLEANUP_RAW}" = true ]; then
        rm -f "${RAW_FILE}"
      fi
      return 1
    fi

    for file in "${SPLIT_DIR}"*; do
      if [ -f "${file}" ]; then
        yq -i '... comments=""' "${file}" > /dev/null 2>&1 || true
      fi
    done

    echo ">> Split manifests created successfully for ${CHART}"
  fi

  # Cleanup raw file if requested or temp
  if [ "${RAW_IS_TEMP}" = true ] || [ "${CLEANUP_RAW}" = true ]; then
    rm -f "${RAW_FILE}"
  fi
}
