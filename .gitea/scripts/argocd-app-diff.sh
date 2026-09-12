#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
CHART="${CHART:-}"
CLUSTER="${CLUSTER:-cl01tl}"
ARGOCD_SERVER_INTERNAL="${ARGOCD_SERVER_INTERNAL:-argocd-server.argocd.svc.cluster.local:80}"
ARGOCD_AUTH_TOKEN="${ARGOCD_AUTH_TOKEN:-}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
PR_NUMBER="${PR_NUMBER:-}"

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
    --server)
      ARGOCD_SERVER_INTERNAL="$2"
      shift 2
      ;;
    --token)
      ARGOCD_AUTH_TOKEN="$2"
      shift 2
      ;;
    --gitea-token)
      GITEA_TOKEN="$2"
      shift 2
      ;;
    --pr-number)
      PR_NUMBER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>] [--server <server>] [--token <auth-token>] [--gitea-token <token>] [--pr-number <number>]"
      echo "Runs ArgoCD app diff for a single chart and publishes results to the Action UI and PR comments."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ]; then
  echo "Error: --chart or CHART environment variable is required." >&2
  exit 1
fi

ARGOCD_APP_NAME="${CHART}"
case "${CHART}" in
  "stack")
    ARGOCD_APP_NAME="stack-cl01tl"
    ;;
esac

APP_PATH=""
DIFF_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
APP_CONFIG="$(mktemp)"
APP_CONFIG_ERR="$(mktemp)"
DIFF_FOUND=false
IS_NEW_APP=false

cleanup() {
  if [ -d .git.bak ]; then
    rm -rf .git
    mv .git.bak .git
  fi
  if [ -f .gitignore.bak ]; then
    rm -f .gitignore
    mv .gitignore.bak .gitignore
  fi
  rm -f "${DIFF_FILE:-}" "${ERR_FILE:-}" "${APP_CONFIG:-}" "${APP_CONFIG_ERR:-}"
}
trap cleanup EXIT

echo ">> Fetching live app configuration for ${ARGOCD_APP_NAME} ..."
set +e
argocd app get "${ARGOCD_APP_NAME}" \
  --server "${ARGOCD_SERVER_INTERNAL}" \
  --plaintext \
  --auth-token "${ARGOCD_AUTH_TOKEN}" \
  -o json > "${APP_CONFIG}" 2> "${APP_CONFIG_ERR}"
GET_EXIT=$?
set -e

if [ ${GET_EXIT} -ne 0 ]; then
  if grep -iqE "PermissionDenied|NotFound|not found" "${APP_CONFIG_ERR}"; then
    echo ">> Application '${ARGOCD_APP_NAME}' does not exist in ArgoCD (new application)."
    IS_NEW_APP=true
  else
    echo ">> ArgoCD encountered an error fetching ${ARGOCD_APP_NAME}!" >&2
    cat "${APP_CONFIG_ERR}" >&2
    exit ${GET_EXIT}
  fi
else
  APP_PATH=$(jq -r '.spec.source.path // empty' "${APP_CONFIG}" 2>/dev/null || true)
fi

if [ "${IS_NEW_APP}" = "false" ]; then
  MANIFEST_PATH="clusters/${CLUSTER}/manifests/${CHART}"

  if [ ! -d "${MANIFEST_PATH}" ]; then
    echo ">> Manifest directory '${MANIFEST_PATH}' not found for ${CHART}." >&2
    exit 1
  fi

  # Temporarily hide .git and .gitignore so argocd packages everything without exclusions
  mv .git .git.bak
  if [ -f .gitignore ]; then mv .gitignore .gitignore.bak; fi

  echo ">> Running argocd app diff for ${ARGOCD_APP_NAME} (chart: ${CHART}) ..."

  set +e
  argocd app diff "${ARGOCD_APP_NAME}" \
    --server "${ARGOCD_SERVER_INTERNAL}" \
    --plaintext \
    --auth-token "${ARGOCD_AUTH_TOKEN}" \
    --server-side-generate \
    --local "$PWD" > "${DIFF_FILE}" 2> "${ERR_FILE}"
  DIFF_EXIT=$?
  set -e

  # Restore git repository and gitignore immediately after diff completes
  if [ -d .git.bak ]; then
    rm -rf .git
    mv .git.bak .git
  fi
  if [ -f .gitignore.bak ]; then
    rm -f .gitignore
    mv .gitignore.bak .gitignore
  fi

  if [ ${DIFF_EXIT} -ne 0 ]; then
    if [ -s "${DIFF_FILE}" ]; then
      DIFF_FOUND=true
      rm -f "${ERR_FILE}"
      echo ">> Argo diff found for ${CHART}:"
      cat "${DIFF_FILE}"
      echo ""
    elif grep -iqE "PermissionDenied|NotFound|not found" "${ERR_FILE}"; then
      echo ">> Application '${ARGOCD_APP_NAME}' does not exist in ArgoCD (new application)."
      IS_NEW_APP=true
    else
      echo ">> ArgoCD encountered an error validating ${CHART}!" >&2
      cat "${ERR_FILE}" >&2
      exit 1
    fi
  else
    echo ">> No Argo diff or errors found for ${CHART}"
    rm -f "${DIFF_FILE}" "${ERR_FILE}"
  fi
else
  echo ">> Skipping diff because '${ARGOCD_APP_NAME}' is a new application."
fi

# Publish to Action UI Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### ArgoCD Diff: \`${CHART}\`"
    if [ "${IS_NEW_APP}" = "true" ]; then
      echo "New application detected (not yet deployed to ArgoCD)."
    elif [ "${DIFF_FOUND}" = "true" ]; then
      echo '```diff'
      cat "${DIFF_FILE}"
      echo '```'
    else
      echo "No diff detected (live cluster matches local changes)."
    fi
    echo ""
  } >> "${GITHUB_STEP_SUMMARY}"
fi

# Publish to Gitea PR Comment
SERVER_URL="${PUBLIC_URL:-${GITHUB_SERVER_URL:-${GITEA_SERVER_URL:-}}}"
REPO="${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}"

if [ -n "${GITEA_TOKEN}" ] && [ -n "${PR_NUMBER}" ] && [ -n "${SERVER_URL}" ] && [ -n "${REPO}" ]; then
  echo ">> Posting ArgoCD diff to PR #${PR_NUMBER} ..."

  TAG="<!-- argocd-diff-${CHART} -->"
  if [ "${IS_NEW_APP}" = "true" ]; then
    COMMENT_BODY="${TAG}
### ArgoCD Diff: \`${CHART}\`
New application detected (not yet deployed to ArgoCD)."
  elif [ "${DIFF_FOUND}" = "true" ]; then
    DIFF_CONTENT=$(cat "${DIFF_FILE}")
    COMMENT_BODY="${TAG}
### ArgoCD Diff: \`${CHART}\`
\`\`\`diff
${DIFF_CONTENT}
\`\`\`"
  else
    COMMENT_BODY="${TAG}
### ArgoCD Diff: \`${CHART}\`
No diff detected (live cluster matches local changes)."
  fi

  source "${SCRIPT_DIR}/helper_pr-comment-upsert.sh"
  upsert_pr_comment "${TAG}" "${COMMENT_BODY}"
fi

# Set action outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "diff-detected=${DIFF_FOUND}" >> "${GITHUB_OUTPUT}"
fi

rm -f "${DIFF_FILE}" "${ERR_FILE}" "${APP_CONFIG}" "${APP_CONFIG_ERR}"
echo "----"
