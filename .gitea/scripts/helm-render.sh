#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
source "${SCRIPT_DIR}/helper_helm-namespace.sh"
source "${SCRIPT_DIR}/helper_helm-render.sh"

# Parse optional command-line flags
MAIN_DIR="${MAIN_DIR:-.}"
MANIFEST_DIR="${MANIFEST_DIR:-.}"
CLUSTER="${CLUSTER:-cl01tl}"
CHART="${CHART:-}"
CHARTS="${CHARTS:-}"
RENDER_DIR="${RENDER_DIR:-}"
RENDER_ALL="${RENDER_ALL:-false}"
API_VERSIONS="${API_VERSIONS:-}"
PARALLEL_JOBS="${PARALLEL_JOBS:-5}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
SKIP_REPO_ADD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart)
      CHART="$2"
      shift 2
      ;;
    --charts)
      CHARTS="$2"
      shift 2
      ;;
    --render-dir)
      RENDER_DIR="$2"
      shift 2
      ;;
    --main-dir)
      MAIN_DIR="$2"
      shift 2
      ;;
    --manifest-dir)
      MANIFEST_DIR="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --render-all)
      RENDER_ALL="$2"
      shift 2
      ;;
    --api-versions)
      API_VERSIONS="$2"
      shift 2
      ;;
    --parallel-jobs)
      PARALLEL_JOBS="$2"
      shift 2
      ;;
    --github-output)
      GITHUB_OUTPUT="$2"
      shift 2
      ;;
    --skip-repo-add)
      SKIP_REPO_ADD=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--charts <charts>] [--render-dir <dirs>] [--main-dir <dir>] [--manifest-dir <dir>] [--cluster <cluster>] [--render-all <true|false>] [--api-versions <versions>] [--parallel-jobs <n>] [--github-output <file>] [--skip-repo-add]"
      echo "Renders Helm templates into individual manifest files in clusters/<cluster>/manifests/<chart>/."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -d "${MAIN_DIR}" ]; then
  MAIN_DIR="$(cd "${MAIN_DIR}" && pwd)"
fi
if [ -d "${MANIFEST_DIR}" ]; then
  MANIFEST_DIR="$(cd "${MANIFEST_DIR}" && pwd)"
fi

# Consolidate target charts
TARGET_CHARTS=""
if [ -n "${CHART}" ]; then
  TARGET_CHARTS="${CHART}"
elif [ -n "${CHARTS}" ]; then
  TARGET_CHARTS="${CHARTS//,/ }"
elif [ -n "${RENDER_DIR}" ]; then
  TARGET_CHARTS="${RENDER_DIR//,/ }"
elif [ "${RENDER_ALL}" = "true" ]; then
  HELM_ROOT="${MAIN_DIR}/clusters/${CLUSTER}/helm"
  if [ -d "${HELM_ROOT}" ]; then
    TARGET_CHARTS=$(find "${HELM_ROOT}" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/Chart.yaml' ';' -exec basename '{}' ';' | sort | xargs)
  fi
fi

if [ -z "${TARGET_CHARTS}" ]; then
  echo ">> No charts specified or found for rendering. Exiting."
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "changed-charts-csv=" >> "${GITHUB_OUTPUT}"
    echo "changed-charts=" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
fi

# Clean output manifest directories
echo ">> Cleaning target manifest directories in ${MANIFEST_DIR}/clusters/${CLUSTER}/manifests ..."
if [[ "${RENDER_ALL}" == "true" ]]; then
  echo ">> Full render detected: clearing all manifests for cluster ${CLUSTER} ..."
  rm -rf "${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/"*
else
  for C in ${TARGET_CHARTS}; do
    CHART_OUTPUT="${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/${C}"
    if [ -d "${CHART_OUTPUT}" ]; then
      rm -rf "${CHART_OUTPUT}"/*
    fi
  done
fi

# Add required Helm repositories if not skipped
if [ "${SKIP_REPO_ADD}" = false ] && [ -f "${SCRIPT_DIR}/helm-add-repos.sh" ]; then
  "${SCRIPT_DIR}/helm-add-repos.sh" --main-dir "${MAIN_DIR}" --cluster "${CLUSTER}" --charts "${TARGET_CHARTS}"
fi

# Set up fail tracking directory
FAIL_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${FAIL_DIR:-}"
}
trap cleanup EXIT

render_chart() {
  local C="$1"
  local CHART_PATH="${MAIN_DIR}/clusters/${CLUSTER}/helm/${C}"
  local OUTPUT_FOLDER="${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/${C}/"

  if [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
    echo ">> Chart.yaml not found for ${C} at ${CHART_PATH}, skipping."
    return 0
  fi

  mkdir -p "${OUTPUT_FOLDER}"

  local RENDER_ARGS=(--chart "${C}" --chart-path "${CHART_PATH}" --split-output-dir "${OUTPUT_FOLDER}" --build-deps --cleanup-raw)
  if [ -n "${API_VERSIONS}" ]; then
    RENDER_ARGS+=(--api-versions "${API_VERSIONS}")
  fi

  if ! render_helm_chart "${RENDER_ARGS[@]}"; then
    touch "${FAIL_DIR}/failed_${C}"
    return 1
  fi

  echo ">> Manifests for ${C} rendered successfully"
  for file in "${OUTPUT_FOLDER}"/*; do
    if [ -f "${file}" ]; then
      echo "  - $(basename "${file}")"
    fi
  done
  echo ""
}

export -f render_chart render_helm_chart resolve_namespace
export MAIN_DIR MANIFEST_DIR CLUSTER API_VERSIONS FAIL_DIR

CHART_COUNT=$(wc -w <<< "${TARGET_CHARTS}" | xargs)

if [ "${CHART_COUNT}" -eq 1 ]; then
  echo ">> Rendering single chart: ${TARGET_CHARTS} ..."
  render_chart "${TARGET_CHARTS}"
else
  echo ">> Rendering ${CHART_COUNT} charts in parallel (concurrency: ${PARALLEL_JOBS}) ..."
  for C in ${TARGET_CHARTS}; do
    echo "${C}"
  done | xargs -P "${PARALLEL_JOBS}" -I {} bash -c 'OUT=$(render_chart "$@" 2>&1); printf "%s\n" "$OUT"' _ {}
fi

FAILED_COUNT=$(find "${FAIL_DIR}" -name "failed_*" | wc -l | xargs)
if [ "${FAILED_COUNT}" -gt 0 ]; then
  echo ""
  echo ">> Rendering failed for ${FAILED_COUNT} chart(s)!" >&2
  exit 1
fi

echo ""
echo ">> All charts rendered successfully."
echo "----"

# Detect charts that actually have rendered changes in the manifest directory (if it is a git repo)
CHANGED_CHARTS=""
CHANGED_CHARTS_CSV=""
if [ -d "${MANIFEST_DIR}/.git" ]; then
  CHANGED_CHARTS=$(git -C "${MANIFEST_DIR}" -c core.quotepath=false status --porcelain -uall | (grep -oE "clusters/${CLUSTER}/manifests/[^/]+/" || true) | sed -E "s#clusters/${CLUSTER}/manifests/([^/]+)/#\1#" | sort -u)
  if [ -n "${CHANGED_CHARTS}" ]; then
    CHANGED_CHARTS_CSV=$(echo "${CHANGED_CHARTS}" | paste -sd, -)
  fi
fi

if [ -n "${CHANGED_CHARTS}" ]; then
  echo ">> Manifest Changes Detected in Charts:"
  for C in ${CHANGED_CHARTS}; do
    echo "  - ${C}"
  done
  echo ">> Changed Charts (CSV): ${CHANGED_CHARTS_CSV}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  if [ -n "${CHANGED_CHARTS}" ]; then
    echo "changes-detected=true" >> "${GITHUB_OUTPUT}"
    echo "changed-charts-csv=${CHANGED_CHARTS_CSV}" >> "${GITHUB_OUTPUT}"
    echo "changed-charts<<EOF" >> "${GITHUB_OUTPUT}"
    echo "${CHANGED_CHARTS}" >> "${GITHUB_OUTPUT}"
    echo "EOF" >> "${GITHUB_OUTPUT}"
  else
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "changed-charts-csv=" >> "${GITHUB_OUTPUT}"
    echo "changed-charts=" >> "${GITHUB_OUTPUT}"
  fi
fi
