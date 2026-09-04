#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
EVENT_NAME="${EVENT_NAME:-${GITHUB_EVENT_NAME:-pull_request}}"
PR_TITLE="${PR_TITLE:-}"
PR_NUMBER="${PR_NUMBER:-}"
IS_AUTOMERGE_INPUT="${IS_AUTOMERGE:-}"
MANIFEST_DIR="${MANIFEST_DIR:-infrastructure-manifests}"
BASE_BRANCH="${BASE_BRANCH:-manifests}"
BRANCH_NAME_BASE="${BRANCH_NAME_BASE:-auto/update-manifests}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event-name)
      EVENT_NAME="$2"
      shift 2
      ;;
    --pr-title)
      PR_TITLE="$2"
      shift 2
      ;;
    --pr-number)
      PR_NUMBER="$2"
      shift 2
      ;;
    --is-automerge)
      IS_AUTOMERGE_INPUT="$2"
      shift 2
      ;;
    --manifest-dir)
      MANIFEST_DIR="$2"
      shift 2
      ;;
    --base-branch)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --branch-name-base)
      BRANCH_NAME_BASE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--event-name <name>] [--pr-title <title>] [--pr-number <num>] [--is-automerge <true|false>] [--manifest-dir <dir>]"
      echo "Determines workflow rendering mode and prepares the destination manifest git branch."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

IS_AUTOMERGE="false"
RENDER_ALL="false"
DIFF_TARGET=""
TRIGGER_INFO=""
NTFY_TITLE="Manifests Updated"

if [[ "${EVENT_NAME}" == "schedule" || "${EVENT_NAME}" == "workflow_dispatch" ]]; then
  echo ">> Mode: Dispatch/Schedule (Render All)"
  RENDER_ALL="true"
  TRIGGER_INFO="Triggered by: ${EVENT_NAME}"
  NTFY_TITLE="Manifests Rendered (${EVENT_NAME})"

elif [[ "${EVENT_NAME}" == "pull_request" ]]; then
  TRIGGER_INFO="Source PR: ${PR_TITLE}"
  NTFY_TITLE="${PR_TITLE}"

  if [[ "${IS_AUTOMERGE_INPUT}" == "true" ]]; then
    echo ">> Mode: PR Merged (Automerge)"
    IS_AUTOMERGE="true"
  else
    echo ">> Mode: PR Merged (Standard)"
  fi

  DIFF_TARGET="HEAD^..HEAD"
fi

echo ">> Preparing manifest branch in '${MANIFEST_DIR}' ..."
if [ -d "${MANIFEST_DIR}" ]; then
  pushd "${MANIFEST_DIR}" > /dev/null

  echo ">> Configure git to use gitea-bot as committer ..."
  git config user.name "gitea-bot"
  git config user.email "gitea-bot@alexlebens.dev"

  if [[ "${IS_AUTOMERGE}" == "true" ]]; then
    BRANCH_NAME="${BRANCH_NAME_BASE}-automerge-${PR_NUMBER}"
    echo ">> Creating branch ${BRANCH_NAME} ..."
    git checkout -B "${BRANCH_NAME}"
  else
    echo ">> Checking if PR branch exists ..."
    BRANCH_NAME="${BRANCH_NAME_BASE}"

    if git ls-remote --exit-code --heads origin "${BRANCH_NAME}" > /dev/null 2>&1; then
      echo ">> Branch '${BRANCH_NAME}' exists, pulling changes ..."
      git fetch origin "${BRANCH_NAME}"
      git checkout "${BRANCH_NAME}"
      git pull --rebase
    else
      echo ">> Branch '${BRANCH_NAME}' does not exist, creating ..."
      git checkout -b "${BRANCH_NAME}"
    fi
  fi

  popd > /dev/null
else
  echo "Warning: Manifest directory '${MANIFEST_DIR}' not found. Skipping git branch checkout."
  if [[ "${IS_AUTOMERGE}" == "true" ]]; then
    BRANCH_NAME="${BRANCH_NAME_BASE}-automerge-${PR_NUMBER}"
  else
    BRANCH_NAME="${BRANCH_NAME_BASE}"
  fi
fi

echo ""
echo ">> Summary:"
echo "  - is-automerge: ${IS_AUTOMERGE}"
echo "  - render-all: ${RENDER_ALL}"
echo "  - diff-target: ${DIFF_TARGET}"
echo "  - branch-name: ${BRANCH_NAME}"
echo "  - ntfy-title: ${NTFY_TITLE}"
echo ""
echo "----"

if [ -n "${GITHUB_OUTPUT}" ]; then
  echo "is-automerge=${IS_AUTOMERGE}" >> "${GITHUB_OUTPUT}"
  echo "render-all=${RENDER_ALL}" >> "${GITHUB_OUTPUT}"
  echo "diff-target=${DIFF_TARGET}" >> "${GITHUB_OUTPUT}"
  echo "trigger-info=${TRIGGER_INFO}" >> "${GITHUB_OUTPUT}"
  echo "ntfy-title=${NTFY_TITLE}" >> "${GITHUB_OUTPUT}"
  echo "pr-title=${PR_TITLE}" >> "${GITHUB_OUTPUT}"
  echo "branch-name=${BRANCH_NAME}" >> "${GITHUB_OUTPUT}"
fi
