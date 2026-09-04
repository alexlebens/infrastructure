#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
BASE_BRANCH="${BASE_BRANCH:-origin/main}"
EVENT_NAME="${EVENT_NAME:-${GITHUB_EVENT_NAME:-pull_request}}"
EVENT_BEFORE="${EVENT_BEFORE:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      echo "Usage: $0 [--base-branch <branch>] [--event-name <name>] [--event-before <sha>]"
      echo "Detects changed Docker Compose directories in hosts/ and sets action outputs."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo ">> Target branch for diff is: ${BASE_BRANCH}"

if [ "${EVENT_NAME}" = "pull_request" ]; then
  echo ""
  echo ">> Checking for changes in a pull request ..."
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

RAW_COMPOSE=$( (git diff --name-only "${DIFF_TARGET}" | grep -E "^hosts/[^/]+/[^/]+/" || true) | cut -d/ -f1,2,3 | sort -u)
VALID_COMPOSE=""

for D in $RAW_COMPOSE; do
  if [ -n "$D" ] && [ -d "$D" ]; then
    if [ -f "$D/compose.yaml" ] || [ -f "$D/compose.yml" ] || [ -f "$D/docker-compose.yaml" ] || [ -f "$D/docker-compose.yml" ]; then
      VALID_COMPOSE="${VALID_COMPOSE} ${D}"
    fi
  fi
done

VALID_COMPOSE=$(echo "${VALID_COMPOSE}" | xargs)

if [ -n "${VALID_COMPOSE}" ]; then
  COMPOSE_JSON=$(printf '%s\n' ${VALID_COMPOSE} | jq -R -s -c 'split("\n") | map(select(length > 0))')

  echo ""
  echo ">> Compose directories to lint:"
  for D in ${VALID_COMPOSE}; do
    echo "  - ${D}"
  done

  CHANGED_COMPOSE_CSV=$(echo "${VALID_COMPOSE}" | tr ' ' ',')

  echo ""
  echo "----"

  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=true" >> "${GITHUB_OUTPUT}"
    echo "matrix=${COMPOSE_JSON}" >> "${GITHUB_OUTPUT}"
    echo "dirs=${VALID_COMPOSE}" >> "${GITHUB_OUTPUT}"
    echo "compose-dir-csv=${CHANGED_COMPOSE_CSV}" >> "${GITHUB_OUTPUT}"
    echo "compose-dir<<EOF" >> "${GITHUB_OUTPUT}"
    for D in ${VALID_COMPOSE}; do
      echo "${D}" >> "${GITHUB_OUTPUT}"
    done
    echo "EOF" >> "${GITHUB_OUTPUT}"
  fi
else
  echo ""
  echo ">> Did not find any docker compose files to lint"

  echo ""
  echo "----"

  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "matrix=[]" >> "${GITHUB_OUTPUT}"
    echo "dirs=" >> "${GITHUB_OUTPUT}"
    echo "compose-dir-csv=" >> "${GITHUB_OUTPUT}"
    echo "compose-dir=" >> "${GITHUB_OUTPUT}"
  fi
fi
