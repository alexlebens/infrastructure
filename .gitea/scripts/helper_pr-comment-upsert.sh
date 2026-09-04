#!/usr/bin/env bash
# Sourceable helper — upserts a Gitea PR comment identified by a unique HTML tag.
#
# Expected variables (set before calling):
#   GITEA_TOKEN  — Gitea API token
#   PR_NUMBER    — Pull request number
#   SERVER_URL   — Gitea public URL (e.g. https://gitea.example.com)
#   REPO         — Repository in "owner/repo" format
#
# Usage:
#   source pr-comment-upsert.sh
#   upsert_pr_comment "<tag>" "<body>"

upsert_pr_comment() {
  local TAG="$1"
  local BODY="$2"
  local COMMENTS_URL="${SERVER_URL}/api/v1/repos/${REPO}/issues/${PR_NUMBER}/comments"

  local EXISTING_COMMENT_ID
  EXISTING_COMMENT_ID=$(curl -s -H "Authorization: token ${GITEA_TOKEN}" "${COMMENTS_URL}" \
    | jq -r ".[] | select(.body | contains(\"${TAG}\")) | .id" | head -n 1 || true)

  if [ -n "${EXISTING_COMMENT_ID}" ] && [ "${EXISTING_COMMENT_ID}" != "null" ]; then
    echo ">> Updating existing PR comment #${EXISTING_COMMENT_ID} ..."
    curl -s -X PATCH "${SERVER_URL}/api/v1/repos/${REPO}/issues/comments/${EXISTING_COMMENT_ID}" \
      -H "Authorization: token ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg body "${BODY}" '{body: $body}')" > /dev/null
  else
    echo ">> Creating new PR comment ..."
    curl -s -X POST "${COMMENTS_URL}" \
      -H "Authorization: token ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg body "${BODY}" '{body: $body}')" > /dev/null
  fi
}
