#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
CHART="${CHART:-}"
MANIFEST_FILE=""
IGNORE_ERRORS="${IGNORE_ERRORS:-garage-bucket,GarageBucket}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart)
      CHART="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --ignore-errors)
      IGNORE_ERRORS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--manifest <file>] [--ignore-errors <comma-separated-patterns>]"
      echo "Performs server-side API dry-run validation using kubectl."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ] && [ -z "${MANIFEST_FILE}" ]; then
  echo "Error: --chart (or CHART env var) or --manifest is required." >&2
  exit 1
fi

MANIFEST_FILE="${MANIFEST_FILE:-rendered-raw/${CHART}.yaml}"

if [ ! -f "${MANIFEST_FILE}" ]; then
  echo "Error: Manifest file '${MANIFEST_FILE}' not found." >&2
  exit 1
fi

echo ">> Running server-side dry-run for: ${CHART:-$(basename "${MANIFEST_FILE}")}"

check_ignored() {
  local output="$1"
  local ignore_list="$2"
  [ -z "${ignore_list}" ] && return 1

  local error_lines
  error_lines=$(grep -iE "error|failed|invalid" <<< "${output}" || true)
  [ -z "${error_lines}" ] && error_lines="${output}"

  local pattern
  pattern=$(echo "${ignore_list}" | sed "s/,/|/g")

  while IFS= read -r line; do
    [ -z "${line}" ] && continue
    if ! grep -iqE "${pattern}" <<< "${line}"; then
      echo ">> Unignored error detected: ${line}" >&2
      return 1
    fi
  done <<< "${error_lines}"

  return 0
}

set +e
APPLY_OUTPUT=$(kubectl apply --server-side --force-conflicts --dry-run=server -f <(yq 'select(.metadata.annotations."helm.sh/hook" == null)' "${MANIFEST_FILE}") 2>&1)
EXIT_CODE=$?
set -e

echo "${APPLY_OUTPUT}"

if [ ${EXIT_CODE} -ne 0 ]; then
  if [ -n "${IGNORE_ERRORS}" ] && check_ignored "${APPLY_OUTPUT}" "${IGNORE_ERRORS}"; then
    echo ""
    echo ">> Warning: Errors occurred during server-side dry-run, but matched ignore list (${IGNORE_ERRORS})."
    echo ">> Ignoring error and continuing."
    EXIT_CODE=0
  else
    echo ""
    echo ">> Server-side dry-run failed with unignored errors." >&2
    exit ${EXIT_CODE}
  fi
fi

echo ""
echo ">> Server-side dry-run completed successfully."
echo "----"
