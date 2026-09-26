#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
TOFU_DIR="${TOFU_DIR:-tofu/buckets}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
PR_NUMBER="${PR_NUMBER:-}"
PUBLIC_URL="${PUBLIC_URL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      TOFU_DIR="$2"
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
      echo "Usage: $0 [--dir <dir>] [--gitea-token <token>] [--pr-number <number>]"
      echo "Runs OpenTofu plan and publishes results to Action UI summary and PR comments."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "${TOFU_DIR}" ]; then
  echo "Error: Directory '${TOFU_DIR}' not found." >&2
  exit 1
fi

PLAN_OUT="$(mktemp)"
PLAN_ERR="$(mktemp)"

cleanup() {
  rm -f "${PLAN_OUT:-}" "${PLAN_ERR:-}"
}
trap cleanup EXIT

echo ">> Running OpenTofu plan in ${TOFU_DIR} ..."
pushd "${TOFU_DIR}" > /dev/null

set +e
tofu plan -no-color -detailed-exitcode > "${PLAN_OUT}" 2> "${PLAN_ERR}"
PLAN_EXIT=$?
set -e

popd > /dev/null

DIFF_FOUND=false

if [ ${PLAN_EXIT} -eq 0 ]; then
  echo ">> OpenTofu plan succeeded: No changes detected."
elif [ ${PLAN_EXIT} -eq 2 ]; then
  echo ">> OpenTofu plan succeeded: Changes detected."
  DIFF_FOUND=true
else
  echo ">> OpenTofu plan failed with exit code ${PLAN_EXIT}!" >&2
  cat "${PLAN_ERR}" >&2
  cat "${PLAN_OUT}" >&2

  # Publish error to PR comment if possible before exiting
  if [ -n "${GITEA_TOKEN}" ] && [ -n "${PR_NUMBER}" ]; then
    SERVER_URL="${PUBLIC_URL:-${GITHUB_SERVER_URL:-${GITEA_SERVER_URL:-}}}"
    REPO="${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}"
    TAG="<!-- tofu-plan-buckets -->"
    COMMENT_BODY="${TAG}
### OpenTofu Plan: S3 Buckets & Credentials
**Status**: **Plan Failed** (exit code ${PLAN_EXIT})

\`\`\`
$(cat "${PLAN_ERR}" "${PLAN_OUT}" | tail -n 40)
\`\`\`"
    source "${SCRIPT_DIR}/helper_pr-comment-upsert.sh"
    upsert_pr_comment "${TAG}" "${COMMENT_BODY}"
  fi
  exit ${PLAN_EXIT}
fi

# Extract summary line (e.g., "Plan: X to add, Y to change, Z to destroy." or "No changes...")
SUMMARY_LINE=$(grep -E "(Plan:|No changes\.)" "${PLAN_OUT}" | tail -n 1 || true)
if [ -z "${SUMMARY_LINE}" ]; then
  if [ "${DIFF_FOUND}" = "true" ]; then
    SUMMARY_LINE="Changes detected in bucket resources."
  else
    SUMMARY_LINE="No changes. Infrastructure matches configuration."
  fi
fi

# Build plan details (stripping refresh noise if possible)
if grep -q "OpenTofu will perform the following actions:" "${PLAN_OUT}"; then
  PLAN_DETAILS=$(sed -n '/OpenTofu will perform the following actions:/,$p' "${PLAN_OUT}")
elif grep -q "Terraform will perform the following actions:" "${PLAN_OUT}"; then
  PLAN_DETAILS=$(sed -n '/Terraform will perform the following actions:/,$p' "${PLAN_OUT}")
else
  PLAN_DETAILS=$(cat "${PLAN_OUT}")
fi

# Cap plan length to prevent excessive comment sizes
MAX_LINES=300
LINE_COUNT=$(wc -l <<< "${PLAN_DETAILS}")
if [ "${LINE_COUNT}" -gt "${MAX_LINES}" ]; then
  PLAN_DETAILS="$(head -n "${MAX_LINES}" <<< "${PLAN_DETAILS}")

... [Truncated remaining $(( LINE_COUNT - MAX_LINES )) lines. View full plan in Action run logs.]"
fi

# Build Markdown Comment
TAG="<!-- tofu-plan-buckets -->"
if [ "${DIFF_FOUND}" = "true" ]; then
  COMMENT_BODY="${TAG}
### OpenTofu Plan: S3 Buckets & Credentials
**Status**: Changes detected
> **${SUMMARY_LINE}**

<details>
<summary>Click to view plan details</summary>

\`\`\`terraform
${PLAN_DETAILS}
\`\`\`

</details>"
else
  COMMENT_BODY="${TAG}
### OpenTofu Plan: S3 Buckets & Credentials
**Status**: Up to date
> **${SUMMARY_LINE}**"
fi

# Publish to Action UI Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "${COMMENT_BODY}"
    echo ""
  } >> "${GITHUB_STEP_SUMMARY}"
fi

# Publish to Gitea PR Comment
SERVER_URL="${PUBLIC_URL:-${GITHUB_SERVER_URL:-${GITEA_SERVER_URL:-}}}"
REPO="${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}"

if [ -n "${GITEA_TOKEN}" ] && [ -n "${PR_NUMBER}" ] && [ -n "${SERVER_URL}" ] && [ -n "${REPO}" ]; then
  echo ">> Posting OpenTofu plan to PR #${PR_NUMBER} ..."
  source "${SCRIPT_DIR}/helper_pr-comment-upsert.sh"
  upsert_pr_comment "${TAG}" "${COMMENT_BODY}"
fi

# Set action outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changes-detected=${DIFF_FOUND}" >> "${GITHUB_OUTPUT}"
fi

echo "----"
