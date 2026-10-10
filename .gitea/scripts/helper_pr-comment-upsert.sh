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
    | jq -r --arg tag "${TAG}" 'if type == "array" then .[] | select((.body? // "") | contains($tag)) | .id else empty end' 2>/dev/null | head -n 1 || true)

  local HTTP_CODE RESP_BODY
  if [ -n "${EXISTING_COMMENT_ID}" ] && [ "${EXISTING_COMMENT_ID}" != "null" ]; then
    echo ">> Updating existing PR comment #${EXISTING_COMMENT_ID} ..."
    RESP_BODY=$(curl -s -w "\n%{http_code}" -X PATCH "${SERVER_URL}/api/v1/repos/${REPO}/issues/comments/${EXISTING_COMMENT_ID}" \
      -H "Authorization: token ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg body "${BODY}" '{body: $body}')")
    HTTP_CODE=$(tail -n1 <<< "${RESP_BODY}")
    if [ "${HTTP_CODE}" != "200" ] && [ "${HTTP_CODE}" != "201" ]; then
      echo ">> Warning: Failed to update PR comment (HTTP ${HTTP_CODE}):" >&2
      sed '$d' <<< "${RESP_BODY}" >&2
    fi
  else
    echo ">> Creating new PR comment ..."
    RESP_BODY=$(curl -s -w "\n%{http_code}" -X POST "${COMMENTS_URL}" \
      -H "Authorization: token ${GITEA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg body "${BODY}" '{body: $body}')")
    HTTP_CODE=$(tail -n1 <<< "${RESP_BODY}")
    if [ "${HTTP_CODE}" != "200" ] && [ "${HTTP_CODE}" != "201" ]; then
      echo ">> Warning: Failed to create PR comment (HTTP ${HTTP_CODE}):" >&2
      sed '$d' <<< "${RESP_BODY}" >&2
    fi
  fi
}
