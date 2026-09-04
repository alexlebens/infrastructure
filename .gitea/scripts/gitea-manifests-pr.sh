#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
MANIFEST_DIR="${MANIFEST_DIR:-infrastructure-manifests}"
CLUSTER="${CLUSTER:-cl01tl}"
BASE_BRANCH="${BASE_BRANCH:-manifests}"
HEAD_BRANCH="${HEAD_BRANCH:-}"
IS_AUTOMERGE="${IS_AUTOMERGE:-false}"
ASSIGNEE="${ASSIGNEE:-alexlebens}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
GITEA_URL="${GITEA_URL:-}"
REPOSITORY="${REPOSITORY:-${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}}"
EVENT_NAME="${EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
ACTOR="${ACTOR:-${GITHUB_ACTOR:-}}"
SHA="${SHA:-${GITHUB_SHA:-}}"
REF_NAME="${REF_NAME:-${GITHUB_REF_NAME:-}}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest-dir)
      MANIFEST_DIR="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --base-branch)
      BASE_BRANCH="$2"
      shift 2
      ;;
    --head-branch)
      HEAD_BRANCH="$2"
      shift 2
      ;;
    --is-automerge)
      IS_AUTOMERGE="$2"
      shift 2
      ;;
    --assignee)
      ASSIGNEE="$2"
      shift 2
      ;;
    --token)
      GITEA_TOKEN="$2"
      shift 2
      ;;
    --url)
      GITEA_URL="$2"
      shift 2
      ;;
    --repo)
      REPOSITORY="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--manifest-dir <dir>] [--cluster <cluster>] [--base-branch <base>] [--head-branch <head>] [--is-automerge <bool>]"
      echo "Checks git status in manifests repo, commits, pushes, and handles Gitea PR creation, updates, and automerges."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -d "${MANIFEST_DIR}" ]; then
  MANIFEST_DIR="$(cd "${MANIFEST_DIR}" && pwd)"
fi

if [ ! -d "${MANIFEST_DIR}" ]; then
  echo "Error: Manifest directory '${MANIFEST_DIR}' not found." >&2
  exit 1
fi

pushd "${MANIFEST_DIR}" > /dev/null

GIT_CHANGES=$(git status --porcelain)

if [ -z "${GIT_CHANGES}" ]; then
  echo ">> No changes detected in ${MANIFEST_DIR}, skipping commit and PR creation."
  echo ""
  echo "----"

  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "changed-charts-csv=" >> "${GITHUB_OUTPUT}"
    echo "push=false" >> "${GITHUB_OUTPUT}"
    echo "pull-request-operation=none" >> "${GITHUB_OUTPUT}"
    echo "pull-request-number=" >> "${GITHUB_OUTPUT}"
  fi
  popd > /dev/null
  exit 0
fi

echo ">> Changes detected:"
git status --porcelain
echo ""

CHANGED_CHARTS=$(echo "${GIT_CHANGES}" | grep -oE "clusters/${CLUSTER}/manifests/[^/]+" | awk -F '/' '{print $4}' | sort -u | paste -sd ',' - || true)
echo ">> Changed Charts: ${CHANGED_CHARTS}"

# Commit and Push
MSG="chore: Update manifests after change"
if [[ "${IS_AUTOMERGE}" == "true" ]]; then
  MSG="chore: Update manifests after automerge"
fi

echo ">> Committing changes to ${HEAD_BRANCH} ..."
git add .
git commit -m "${MSG}"

REPO_URL="${GITEA_URL}/${REPOSITORY}"
echo ">> Pushing changes to ${REPO_URL} on branch ${HEAD_BRANCH} ..."
git push -u "http://oauth2:${GITEA_TOKEN}@${REPO_URL#*://}" "${HEAD_BRANCH}"
echo ">> Push completed successfully."
echo ""
echo "----"

PR_OP="none"
PR_NUM=""

TEMP_RESP="$(mktemp)"
cleanup() {
  rm -f "${TEMP_RESP:-}"
}
trap cleanup EXIT

# Check for existing open PR
if [[ "${IS_AUTOMERGE}" == "false" ]]; then
  API_ENDPOINT="${GITEA_URL}/api/v1/repos/${REPOSITORY}/pulls?base_branch=${BASE_BRANCH}&state=open&page=1"
  echo ">> Checking for existing open PR from branch ${HEAD_BRANCH} into ${BASE_BRANCH} ..."
  HTTP_STATUS=$(curl -X GET -s -w '%{http_code}' -o "${TEMP_RESP}" \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_ENDPOINT}")

  EXISTING_PR_ID=""
  if [ "${HTTP_STATUS}" == "200" ]; then
    EXISTING_PR_ID=$(jq -r '.[] | select(.head.ref == "'"${HEAD_BRANCH}"'") | .number' "${TEMP_RESP}" 2>/dev/null | head -n 1 || true)
    if [ -z "${EXISTING_PR_ID}" ] && [ "$(jq -r '.[0].state // empty' "${TEMP_RESP}" 2>/dev/null)" == "open" ]; then
      EXISTING_PR_ID=$(jq -r '.[0].number' "${TEMP_RESP}")
    fi
  fi

  if [ -n "${EXISTING_PR_ID}" ] && [ "${EXISTING_PR_ID}" != "null" ]; then
    echo ">> Found open PR #${EXISTING_PR_ID}. Updating PR description ..."
    API_UPDATE="${GITEA_URL}/api/v1/repos/${REPOSITORY}/pulls/${EXISTING_PR_ID}"
    EXISTING_BODY=$(jq -r '.[] | select(.number == '"${EXISTING_PR_ID}"') | .body' "${TEMP_RESP}" 2>/dev/null || jq -r '.[0].body' "${TEMP_RESP}")

    NEW_DETAILS=$(printf "### Update Details (%s)\n- **Trigger**: \`%s\` by \`@%s\`\n- **Commit**: \`%s\` (on \`%s\`)\n- **Charts Updated**: \`%s\`" \
      "$(date -u +'%Y-%m-%d %H:%M UTC')" "${EVENT_NAME}" "${ACTOR}" "${SHA:0:7}" "${REF_NAME}" "${CHANGED_CHARTS}")
    UPDATED_BODY=$(printf "%s\n\n%s" "${EXISTING_BODY}" "${NEW_DETAILS}")

    PAYLOAD=$(jq -n --arg body "${UPDATED_BODY}" '{body: $body}')
    UPDATE_STATUS=$(curl -X PATCH -s -w '%{http_code}' -o /dev/null --data "${PAYLOAD}" \
      -H "Authorization: token ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      "${API_UPDATE}")

    if [ "${UPDATE_STATUS}" == "200" ] || [ "${UPDATE_STATUS}" == "201" ]; then
      echo ">> Pull Request #${EXISTING_PR_ID} updated successfully!"
      PR_OP="updated"
      PR_NUM="${EXISTING_PR_ID}"
    else
      echo ">> Warning: Failed to update PR, HTTP status code: ${UPDATE_STATUS}"
    fi
  fi
fi

# Create new PR if not updating
if [ "${PR_OP}" == "none" ]; then
  echo ">> Creating new Pull Request for ${HEAD_BRANCH} ..."
  API_CREATE="${GITEA_URL}/api/v1/repos/${REPOSITORY}/pulls"

  BODY=$(printf "This PR contains newly rendered Kubernetes manifests automatically generated by the CI workflow.\n\n### Details\n- **Trigger**: \`%s\` by \`@%s\`\n- **Commit**: \`%s\` (on \`%s\`)\n- **Charts Updated**: \`%s\`" \
    "${EVENT_NAME}" "${ACTOR}" "${SHA:0:7}" "${REF_NAME}" "${CHANGED_CHARTS}")

  if [[ "${IS_AUTOMERGE}" == "true" ]]; then
    TITLE="Automated Manifest Update - Automerge"
    BODY=$(printf "%s\n\n_This PR is expected to be automerged._" "${BODY}")
  else
    TITLE="Automated Manifest Update"
  fi

  PAYLOAD=$(jq -n \
    --arg head "${HEAD_BRANCH}" \
    --arg base "${BASE_BRANCH}" \
    --arg assignee "${ASSIGNEE}" \
    --arg title "${TITLE}" \
    --arg body "${BODY}" \
    '{head: $head, base: $base, assignee: $assignee, title: $title, body: $body}')

  CREATE_STATUS=$(curl -X POST -s -w '%{http_code}' -o "${TEMP_RESP}" --data "${PAYLOAD}" \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_CREATE}")

  if [ "${CREATE_STATUS}" == "201" ]; then
    PR_NUM=$(jq -r '.number' "${TEMP_RESP}")
    PR_OP="created"
    echo ">> Pull Request #${PR_NUM} created successfully!"
  elif [[ "${CREATE_STATUS}" == "422" || "${CREATE_STATUS}" == "409" ]]; then
    echo ">> Pull Request already exists (HTTP ${CREATE_STATUS})."
  else
    echo ">> Failed to create PR, HTTP status code: ${CREATE_STATUS}" >&2
    exit 1
  fi
fi

# Handle Automerge
if [[ "${IS_AUTOMERGE}" == "true" ]] && [ -n "${PR_NUM}" ]; then
  echo ">> Automerging PR #${PR_NUM} ..."
  API_MERGE="${GITEA_URL}/api/v1/repos/${REPOSITORY}/pulls/${PR_NUM}/merge"
  MERGE_PAYLOAD=$(jq -n --arg Do "merge" '{Do: $Do}')

  MERGE_STATUS=$(curl -X POST -s -w '%{http_code}' -o "${TEMP_RESP}" --data "${MERGE_PAYLOAD}" \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_MERGE}")

  if [ "${MERGE_STATUS}" == "200" ]; then
    echo ">> Pull Request #${PR_NUM} merged successfully!"
    PR_OP="merged"
  else
    echo ">> Failed to automerge PR #${PR_NUM}, HTTP status: ${MERGE_STATUS}" >&2
    # Clean up branch on automerge failure
    git push origin --delete "${HEAD_BRANCH}" || true
    exit 1
  fi
fi

popd > /dev/null

if [ -n "${GITHUB_OUTPUT}" ]; then
  echo "changes-detected=true" >> "${GITHUB_OUTPUT}"
  echo "changed-charts-csv=${CHANGED_CHARTS}" >> "${GITHUB_OUTPUT}"
  echo "push=true" >> "${GITHUB_OUTPUT}"
  echo "head-branch=${HEAD_BRANCH}" >> "${GITHUB_OUTPUT}"
  echo "pull-request-operation=${PR_OP}" >> "${GITHUB_OUTPUT}"
  echo "pull-request-number=${PR_NUM}" >> "${GITHUB_OUTPUT}"
fi
