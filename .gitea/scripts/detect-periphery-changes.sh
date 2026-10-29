#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
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
      echo "Detects Komodo Periphery changes and outputs 'systemd' (true/false) and 'compose-hosts' (JSON array)."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

export BASE_BRANCH="${BASE_BRANCH:-origin/main}"
export EVENT_NAME="${EVENT_NAME:-${GITHUB_EVENT_NAME:-push}}"
export EVENT_BEFORE="${EVENT_BEFORE:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

# Resolve diff target using shared helper
source "${SCRIPT_DIR}/helper_resolve-diff-target.sh"
resolve_diff_target

CHANGED_FILES=$(git diff --name-only "${DIFF_TARGET}" || true)
echo ">> Changed files in ${DIFF_TARGET}:"
if [[ -n "${CHANGED_FILES}" ]]; then
  while IFS= read -r file; do
    [[ -n "${file}" ]] && echo "  - ${file}"
  done <<< "${CHANGED_FILES}"
else
  echo "  (none)"
fi

update_systemd="false"
if echo "${CHANGED_FILES}" | grep -qE "^(clusters/cl01tl/helm/komodo/|\.gitea/scripts/update-remote-periphery-systemd\.sh$|\.gitea/scripts/detect-periphery-changes\.sh$|\.gitea/workflows/update-komodo-periphery\.yaml$)"; then
  update_systemd="true"
fi

if echo "${CHANGED_FILES}" | grep -qE "^(\.gitea/scripts/deploy-remote-compose\.sh$|\.gitea/scripts/detect-periphery-changes\.sh$|\.gitea/workflows/update-komodo-periphery\.yaml$)"; then
  RAW_COMPOSE_HOSTS=$( (find hosts -mindepth 2 -maxdepth 2 -type d -name "komodo-periphery" 2>/dev/null || true) | cut -d/ -f2 | sort -u)
else
  RAW_COMPOSE_HOSTS=$( (echo "${CHANGED_FILES}" | grep -E "^hosts/[^/]+/komodo-periphery/" || true) | cut -d/ -f2 | sort -u)
fi

VALID_COMPOSE_HOSTS=""
for H in ${RAW_COMPOSE_HOSTS}; do
  if [[ -n "${H}" ]] && [[ -d "hosts/${H}/komodo-periphery" ]]; then
    VALID_COMPOSE_HOSTS="${VALID_COMPOSE_HOSTS} ${H}"
  fi
done
VALID_COMPOSE_HOSTS=$(echo "${VALID_COMPOSE_HOSTS}" | xargs)

if [[ -n "${VALID_COMPOSE_HOSTS}" ]]; then
  COMPOSE_HOSTS_JSON=$(echo "${VALID_COMPOSE_HOSTS}" | jq -R -c 'split(" ") | map(select(length > 0))')
else
  COMPOSE_HOSTS_JSON="[]"
fi

echo ""
echo ">> Periphery update detection:"
echo "  - systemd hosts: ${update_systemd}"
echo "  - compose hosts: ${COMPOSE_HOSTS_JSON}"
echo "----"

if [[ -n "${GITHUB_OUTPUT}" ]]; then
  echo "systemd=${update_systemd}" >> "${GITHUB_OUTPUT}"
  echo "compose-hosts=${COMPOSE_HOSTS_JSON}" >> "${GITHUB_OUTPUT}"
fi
