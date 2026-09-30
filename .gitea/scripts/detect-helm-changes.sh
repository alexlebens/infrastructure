#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --base-branch)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --event-name)
      EVENT_NAME="$2"
      shift 2
      ;;
    --event-before)
      EVENT_BEFORE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--cluster <cluster>] [--base-branch <branch>] [--event-name <name>] [--event-before <sha>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve configuration from arguments or environment variables
CLUSTER="${CLUSTER:-cl01tl}"
BASE_BRANCH="${BASE_BRANCH:-origin/main}"
EVENT_NAME="${EVENT_NAME:-${GITHUB_EVENT_NAME:-pull_request}}"
EVENT_BEFORE="${EVENT_BEFORE:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

echo ">> Target branch for diff is: ${BASE_BRANCH}"

# Resolve diff target using shared helper
source "${SCRIPT_DIR}/helper_resolve-diff-target.sh"
resolve_diff_target

# Find changed charts
RAW_CHARTS=$( (git diff --name-only "${DIFF_TARGET}" | grep -E "^clusters/${CLUSTER}/helm/" || true) | awk -F '/' '{print $4}' | sort -u)
VALID_CHARTS=""

for C in $RAW_CHARTS; do
  if [ -n "$C" ] && [ -f "clusters/${CLUSTER}/helm/${C}/Chart.yaml" ]; then
    VALID_CHARTS="${VALID_CHARTS} ${C}"
  fi
done

VALID_CHARTS=$(echo "${VALID_CHARTS}" | xargs)

if [ -n "${VALID_CHARTS}" ]; then
  CHARTS_JSON=$(printf '%s\n' ${VALID_CHARTS} | jq -R -s -c 'split("\n") | map(select(length > 0))')

  echo ""
  echo ">> Charts to test:"
  echo "${VALID_CHARTS}"

  echo ""
  echo "----"
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=true" >> "${GITHUB_OUTPUT}"
    echo "matrix=${CHARTS_JSON}" >> "${GITHUB_OUTPUT}"
    echo "charts=${VALID_CHARTS}" >> "${GITHUB_OUTPUT}"
  fi
else
  echo ""
  echo ">> Did not find any valid helm charts to test"

  echo ""
  echo "----"
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "matrix=[]" >> "${GITHUB_OUTPUT}"
    echo "charts=" >> "${GITHUB_OUTPUT}"
  fi
fi
