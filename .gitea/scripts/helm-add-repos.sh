#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
MAIN_DIR="${MAIN_DIR:-.}"
CLUSTER="${CLUSTER:-cl01tl}"
CHARTS="${CHARTS:-${CHART:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-dir)
      MAIN_DIR="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --chart)
      CHARTS="${CHARTS} $2"
      shift 2
      ;;
    --charts)
      CHARTS="${CHARTS} $2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--main-dir <dir>] [--cluster <cluster>] [--chart <chart>] [--charts <charts...>]"
      echo "Adds Helm repositories required by chart dependencies, deduplicating shared repositories."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

CHARTS=$(echo "${CHARTS}" | xargs)

if [ -z "${CHARTS}" ]; then
  echo ">> No charts specified. Skipping repository addition."
  exit 0
fi

if [ -d "${MAIN_DIR}" ]; then
  MAIN_DIR="$(cd "${MAIN_DIR}" && pwd)"
fi

echo ">> Checking dependencies for chart(s): ${CHARTS} ..."

# Extract and deduplicate non-OCI repository dependencies across all charts
REPO_LIST=$(
  for C in ${CHARTS}; do
    CHART_PATH="${MAIN_DIR}/clusters/${CLUSTER}/helm/${C}"
    if [ -f "${CHART_PATH}/Chart.yaml" ]; then
      helm dependency list --max-col-width 120 "${CHART_PATH}" 2>/dev/null || true
    fi
  done | awk '$1 != "NAME" && $3 !~ /^oci:\/\// && NF >= 3 { print $1, $3 }' | sort -u
)

if [ -n "${REPO_LIST}" ]; then
  echo ">> Adding Helm repositories ..."
  while read -r REPO_NAME REPO_URL; do
    if [ -n "${REPO_NAME}" ] && [ -n "${REPO_URL}" ]; then
      echo ">> Adding repo: ${REPO_NAME} (${REPO_URL})"
      helm repo add "${REPO_NAME}" "${REPO_URL}" --force-update >/dev/null 2>&1 || true
    fi
  done <<< "${REPO_LIST}"

  if [ "$(helm repo list 2>/dev/null | wc -l)" -gt 1 ]; then
    echo ">> Updating repository cache ..."
    helm repo update >/dev/null 2>&1 || true
  fi
else
  echo ">> No external Helm repositories required."
fi

echo ""
echo "----"
