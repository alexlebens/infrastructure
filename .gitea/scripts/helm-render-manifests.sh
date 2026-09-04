#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
MAIN_DIR="${MAIN_DIR:-infrastructure}"
MANIFEST_DIR="${MANIFEST_DIR:-infrastructure-manifests}"
CLUSTER="${CLUSTER:-cl01tl}"
RENDER_ALL="${RENDER_ALL:-false}"
RENDER_DIR="${RENDER_DIR:-}"
API_VERSIONS="${API_VERSIONS:-}"
PARALLEL_JOBS="${PARALLEL_JOBS:-5}"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --render-dir)
      RENDER_DIR="$2"
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
    -h|--help)
      echo "Usage: $0 [--main-dir <dir>] [--manifest-dir <dir>] [--cluster <cluster>] [--render-all <true|false>] [--render-dir <dirs>] [--api-versions <versions>] [--parallel-jobs <n>]"
      echo "Orchestrates cleaning, repository setup, and parallel rendering of Helm charts into the manifest repository."
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

if [ -z "${RENDER_DIR}" ]; then
  echo ">> No directories specified for rendering. Exiting."
  exit 0
fi

# Clean output manifest directories
echo ">> Cleaning target manifest directories in ${MANIFEST_DIR} ..."
if [[ "${RENDER_ALL}" == "true" ]]; then
  echo ">> Full render detected: clearing all manifests for cluster ${CLUSTER} ..."
  rm -rf "${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/"*
else
  echo ">> Incremental render: removing modified chart directories ..."
  for DIR in ${RENDER_DIR}; do
    CHART_OUTPUT="${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/${DIR}"
    if [ -d "${CHART_OUTPUT}" ]; then
      rm -rf "${CHART_OUTPUT}"/*
    fi
  done
fi

# Add required Helm repositories
echo ""
echo ">> Adding repositories for chart dependencies ..."
for DIR in ${RENDER_DIR}; do
  CHART_PATH="${MAIN_DIR}/clusters/${CLUSTER}/helm/${DIR}"
  if [ -f "${CHART_PATH}/Chart.yaml" ]; then
    helm dependency list --max-col-width 120 "${CHART_PATH}" 2> /dev/null \
      | tail -n +2 \
      | awk 'NF > 0 { print $1, $3 }' \
      | while read -r REPO_NAME REPO_URL; do
        if [[ "${REPO_URL}" == oci://* ]]; then
          continue
        elif [[ -n "${REPO_NAME}" && -n "${REPO_URL}" ]]; then
          helm repo add "${REPO_NAME}" "${REPO_URL}" --force-update >/dev/null 2>&1 || true
        fi
      done || true
  fi
done

if [ "$(helm repo list 2>/dev/null | wc -l)" -gt 1 ]; then
  echo ">> Updating Helm repository cache ..."
  helm repo update >/dev/null 2>&1 || true
fi

# Set up fail tracking directory
FAIL_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${FAIL_DIR:-}"
}
trap cleanup EXIT

render_chart() {
  local DIR="$1"
  local CHART_PATH="${MAIN_DIR}/clusters/${CLUSTER}/helm/${DIR}"
  local OUTPUT_FOLDER="${MANIFEST_DIR}/clusters/${CLUSTER}/manifests/${DIR}/"

  if [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
    echo ">> Chart.yaml not found for ${DIR}, skipping."
    return 0
  fi

  mkdir -p "${OUTPUT_FOLDER}"
  echo ">> Rendering chart: ${DIR} ..."

  pushd "${CHART_PATH}" > /dev/null
  helm dependency update --skip-refresh > /dev/null 2>&1 || helm dependency build --skip-refresh > /dev/null 2>&1 || true
  helm lint . --namespace "${DIR}" > /dev/null 2>&1 || true
  popd > /dev/null

  # Determine namespace
  local NAMESPACE="${DIR}"
  case "${DIR}" in
    "stack")
      NAMESPACE="argocd"
      ;;
    "cilium" | "coredns" | "metrics-server")
      NAMESPACE="kube-system"
      ;;
  esac

  local VALUES_ARGS=()
  if [ -f "${CHART_PATH}/values.yaml" ]; then
    VALUES_ARGS+=("-f" "${CHART_PATH}/values.yaml")
  fi

  local HELM_ARGS=("${DIR}" "${CHART_PATH}" "${VALUES_ARGS[@]}" --include-crds --namespace "${NAMESPACE}")
  if [ -n "${API_VERSIONS}" ]; then
    HELM_ARGS+=(--api-versions "${API_VERSIONS}")
  fi

  local RAW_FILE
  RAW_FILE="$(mktemp)"
  if ! helm template "${HELM_ARGS[@]}" > "${RAW_FILE}" 2>/dev/null; then
    echo ">> Failed helm template for ${DIR}" >&2
    touch "${FAIL_DIR}/failed_${DIR}"
    rm -f "${RAW_FILE}"
    return 1
  fi

  # Split manifests into output folder
  set -o pipefail
  if ! cat "${RAW_FILE}" \
    | yq '... comments=""' \
    | yq 'select(. != null)' \
    | yq -s '"'"${OUTPUT_FOLDER}"'" + .kind + "-" + .metadata.name + ".yaml"' >/dev/null 2>&1; then
    echo ">> Failed yq splitting for ${DIR}" >&2
    touch "${FAIL_DIR}/failed_${DIR}"
    rm -f "${RAW_FILE}"
    return 1
  fi
  rm -f "${RAW_FILE}"

  for file in "${OUTPUT_FOLDER}"/*; do
    if [ -f "${file}" ]; then
      yq -i '... comments=""' "${file}" >/dev/null 2>&1 || true
    fi
  done

  echo ">> Manifests for ${DIR} rendered successfully to ${OUTPUT_FOLDER}"
}

export -f render_chart
export MAIN_DIR MANIFEST_DIR CLUSTER API_VERSIONS FAIL_DIR

echo ""
echo ">> Rendering charts in parallel (concurrency: ${PARALLEL_JOBS}) ..."
for DIR in ${RENDER_DIR}; do
  echo "${DIR}"
done | xargs -P "${PARALLEL_JOBS}" -I {} bash -c 'OUT=$(render_chart "$@" 2>&1); printf "%s\n" "$OUT"' _ {}

FAILED_COUNT=$(find "${FAIL_DIR}" -name "failed_*" | wc -l | xargs)
if [ "${FAILED_COUNT}" -gt 0 ]; then
  echo ""
  echo ">> Rendering failed for ${FAILED_COUNT} chart(s)!" >&2
  exit 1
fi

echo ""
echo ">> All charts rendered successfully."
echo "----"
