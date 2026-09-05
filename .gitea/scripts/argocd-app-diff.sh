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

TEMP_COPIED="false"
APP_PATH=""
DIFF_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
DIFF_FOUND=false

cleanup() {
  if [ -d .git.bak ]; then
    rm -rf .git
    mv .git.bak .git
  fi
  if [ -f .gitignore.bak ]; then
    rm -f .gitignore
    mv .gitignore.bak .gitignore
  fi
  if [ "${TEMP_COPIED}" = "true" ] && [ -n "${APP_PATH}" ]; then
    rm -rf "${APP_PATH}"
  fi
  rm -f "${DIFF_FILE:-}" "${ERR_FILE:-}"
}
trap cleanup EXIT

# Temporarily hide .git and .gitignore so argocd packages everything without exclusions
mv .git .git.bak
if [ -f .gitignore ]; then mv .gitignore .gitignore.bak; fi

echo ">> Fetching live app configuration for ${ARGOCD_APP_NAME} ..."
APP_PATH=$(argocd app get "${ARGOCD_APP_NAME}" \
  --server "${ARGOCD_SERVER_INTERNAL}" \
  --plaintext \
  --auth-token "${ARGOCD_AUTH_TOKEN}" \
  -o json 2>/dev/null | jq -r '.spec.source.path // empty' 2>/dev/null || true)

LOCAL_CHART_PATH="clusters/${CLUSTER}/helm/${CHART}"

if [ -n "${APP_PATH}" ] && [ "${APP_PATH}" != "${LOCAL_CHART_PATH}" ] && [ "${APP_PATH}" != "null" ]; then
  echo ">> Live ArgoCD App expects path '${APP_PATH}', but local path is '${LOCAL_CHART_PATH}'."
  echo ">> Temporarily mirroring directory so local diff succeeds ..."
  mkdir -p "$(dirname "${APP_PATH}")"
  cp -r "${LOCAL_CHART_PATH}" "${APP_PATH}"
  TEMP_COPIED="true"
fi

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

# Restore git repository and mirror directory immediately after diff completes
if [ -d .git.bak ]; then
  rm -rf .git
  mv .git.bak .git
fi
if [ -f .gitignore.bak ]; then
  rm -f .gitignore
  mv .gitignore.bak .gitignore
fi
if [ "${TEMP_COPIED}" = "true" ] && [ -n "${APP_PATH}" ]; then
  rm -rf "${APP_PATH}"
  TEMP_COPIED="false"
fi

if [ ${DIFF_EXIT} -ne 0 ]; then
  if [ -s "${DIFF_FILE}" ]; then
    DIFF_FOUND=true
    rm -f "${ERR_FILE}"
    echo ">> Argo diff found for ${CHART}:"
    cat "${DIFF_FILE}"
    echo ""
  else
    echo ">> ArgoCD encountered an error validating ${CHART}!" >&2
    cat "${ERR_FILE}" >&2
    exit 1
  fi
else
  echo ">> No Argo diff or errors found for ${CHART}"
  rm -f "${DIFF_FILE}" "${ERR_FILE}"
fi

# Publish to Action UI Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### ArgoCD Diff: \`${CHART}\`"
    if [ "${DIFF_FOUND}" = "true" ]; then
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
  if [ "${DIFF_FOUND}" = "true" ]; then
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

rm -f "${DIFF_FILE}" "${ERR_FILE}"
echo "----"
