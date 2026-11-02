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
