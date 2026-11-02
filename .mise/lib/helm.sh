#!/usr/bin/env bash
# Sourceable helper library for Helm mise tasks.
#
# Provides common initialization, environment resolution, and chart discovery.
#
# Usage:
#   source "${REPO_ROOT}/.mise/lib/helm.sh"
#   helm_init "$@"
#
# Populates:
#   REPO_ROOT   - Absolute path to git root
#   CLUSTER     - Active cluster name (default: cl01tl)
#   HELM_DIR    - Path to clusters/${CLUSTER}/helm
#   CHARTS      - Array of target chart names
#   UNPARSED_ARGS - Array of any script-specific flags left over

# Prevent double-sourcing
if [[ -n "${_MISE_LIB_HELM_LOADED:-}" ]]; then
  return 0
fi
_MISE_LIB_HELM_LOADED=1

# Ensure log.sh is sourced
_HELM_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
# shellcheck source=./log.sh
source "${_HELM_LIB_DIR}/log.sh"

helm_init() {
  local SCRIPT_SOURCE="${BASH_SOURCE[1]}"
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_SOURCE}")" &>/dev/null && pwd -P)"

  REPO_ROOT="${REPO_ROOT:-${MISE_PROJECT_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd -- "$SCRIPT_DIR/../../.." &>/dev/null && pwd -P))}}"
  CLUSTER="${CLUSTER:-cl01tl}"
  CHARTS=()
  UNPARSED_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --main-dir)
        REPO_ROOT="$2"
        shift 2
        ;;
      --cluster)
        CLUSTER="$2"
        shift 2
        ;;
      --chart)
        CHARTS+=("$2")
        shift 2
        ;;
      --charts)
        local SPLIT_CHARTS=()
        read -ra SPLIT_CHARTS <<< "$2"
        CHARTS+=("${SPLIT_CHARTS[@]}")
        shift 2
        ;;
      *)
        # Positional arguments not starting with "-" are considered chart names if no specific flag
        if [[ "$1" != -* ]]; then
          CHARTS+=("$1")
          shift
        else
          UNPARSED_ARGS+=("$1")
          shift
        fi
        ;;
    esac
  done

  HELM_DIR="${REPO_ROOT}/clusters/${CLUSTER}/helm"

  if [ ! -d "${HELM_DIR}" ]; then
    log_fatal "Directory not found: ${HELM_DIR}"
  fi

  # Discover all valid charts if none specified
  if [ ${#CHARTS[@]} -eq 0 ]; then
    for path in "${HELM_DIR}"/*; do
      if [ -d "${path}" ] && [ -f "${path}/Chart.yaml" ]; then
        CHARTS+=("$(basename "${path}")")
      fi
    done
  else
    # Normalize chart names if full/relative paths were passed (e.g. clusters/cl01tl/helm/foo -> foo)
    local NORMALIZED_CHARTS=()
    for c in "${CHARTS[@]}"; do
      NORMALIZED_CHARTS+=("$(basename "${c}")")
    done
    CHARTS=("${NORMALIZED_CHARTS[@]}")
  fi
}

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
    pushd "${CHART_PATH}" > /dev/null || exit 1
    helm dependency build --skip-refresh > /dev/null 2>&1 || helm dependency update --skip-refresh > /dev/null 2>&1 || true
    popd > /dev/null || exit 1
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
    if ! yq '... comments=""' "${RAW_FILE}" \
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
        # Inject metadata.namespace if omitted
        case "$(basename "${file}")" in
          CustomResourceDefinition-*|ClusterRole-*|ClusterRoleBinding-*|ClusterSecretStore-*|ClusterIssuer-*|Namespace-*|StorageClass-*|PersistentVolume-*)
            ;;
          *)
            NAMESPACE="${NAMESPACE}" yq -i '.metadata.namespace = (.metadata.namespace // env(NAMESPACE))' "${file}" > /dev/null 2>&1 || true
            ;;
        esac
      fi
    done

    echo ">> Split manifests created successfully for ${CHART}"
  fi

  # Cleanup raw file if requested or temp
  if [ "${RAW_IS_TEMP}" = true ] || [ "${CLEANUP_RAW}" = true ]; then
    rm -f "${RAW_FILE}"
  fi
}
