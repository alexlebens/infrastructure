#!/usr/bin/env bash
set -euo pipefail

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

if [ "${EVENT_NAME}" = "pull_request" ]; then
  echo ""
  echo ">> Checking for changes in a pull request ..."
  # If the PR was automerged before this step runs, origin/main might already
  # include our changes, causing the standard diff to be empty.
  if git diff --name-only "${BASE_BRANCH}" 2>/dev/null | grep -q . ; then
    DIFF_TARGET="${BASE_BRANCH}"
  else
    echo ">> Diff against ${BASE_BRANCH} is empty (likely already merged). Falling back to HEAD^1..HEAD"
    DIFF_TARGET="HEAD^1..HEAD"
  fi
else
  BEFORE="${EVENT_BEFORE}"
  if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
    DIFF_TARGET="HEAD^1..HEAD"
  else
    DIFF_TARGET="${BEFORE}..HEAD"
  fi

  echo ""
  echo ">> Checking for changes from a push (Diff target: ${DIFF_TARGET}) ..."
fi

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
  fi
else
  echo ""
  echo ">> Did not find any valid helm charts to test"

  echo ""
  echo "----"
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "matrix=[]" >> "${GITHUB_OUTPUT}"
  fi
fi
