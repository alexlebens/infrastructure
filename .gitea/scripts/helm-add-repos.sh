#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
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
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

CLUSTER="${CLUSTER:-cl01tl}"
CHART="${CHART:-}"

if [ -z "${CHART}" ]; then
  echo "Error: --chart or CHART environment variable is required." >&2
  exit 1
fi

CHART_PATH="clusters/${CLUSTER}/helm/${CHART}"

if [ ! -d "${CHART_PATH}" ]; then
  echo "Error: Chart directory '${CHART_PATH}' not found." >&2
  exit 1
fi

echo ">> Checking dependencies for chart '${CHART}' at ${CHART_PATH} ..."

helm dependency list --max-col-width 120 "${CHART_PATH}" 2> /dev/null \
  | tail -n +2 \
  | awk 'NF > 0 { print $1, $3 }' \
  | while read -r REPO_NAME REPO_URL; do
    if [[ "${REPO_URL}" == oci://* ]]; then
      echo ">> Ignoring OCI repo: ${REPO_URL}"
    elif [[ -n "${REPO_NAME}" && -n "${REPO_URL}" ]]; then
      echo ">> Adding Helm repo: ${REPO_NAME} (${REPO_URL})"
      helm repo add "${REPO_NAME}" "${REPO_URL}"
    fi
  done || true

echo ""

if [ "$(helm repo list 2>/dev/null | wc -l)" -gt 1 ]; then
  echo ">> Updating repository cache ..."
  helm repo update
  echo ""
fi

echo "----"
