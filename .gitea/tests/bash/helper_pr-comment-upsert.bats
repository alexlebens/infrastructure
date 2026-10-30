#!/usr/bin/env bats
# Tests for .gitea/scripts/helper_pr-comment-upsert.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export GITEA_TOKEN="secret-token"
  export PR_NUMBER="42"
  export SERVER_URL="https://gitea.example.invalid"
  export REPO="owner/repo"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export COMMENTS_JSON='[]'
  export WRITE_CODE="201"

  # curl stub: GET returns $COMMENTS_JSON, POST/PATCH return $WRITE_CODE.
  # Every invocation's argv is appended to $CURL_LOG (one arg per line, then "--").
  _stub curl '
printf "%s\n" "$@" >> "${CURL_LOG}"
echo "--" >> "${CURL_LOG}"
method=GET
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -d) echo "DATA=$(jq -c . <<< "$2")" >> "${CURL_LOG}"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "${method}" = "GET" ]; then
  printf "%s" "${COMMENTS_JSON}"
else
  printf "{\"id\": 1}\n%s" "${WRITE_CODE}"
fi
'

  source "${SCRIPTS_DIR}/helper_pr-comment-upsert.sh"
}

@test "upsert_pr_comment: creates a new comment when no tagged comment exists" {
  COMMENTS_JSON='[{"id": 5, "body": "unrelated"}]'

  run upsert_pr_comment "<!-- tag:a -->" "hello"
  assert_success
  assert_output --partial "Creating new PR comment"

  run cat "${CURL_LOG}"
  assert_line "POST"
  assert_line "${SERVER_URL}/api/v1/repos/owner/repo/issues/42/comments"
  assert_line 'DATA={"body":"hello"}'
  assert_line "Authorization: token secret-token"
  refute_line "PATCH"
}

@test "upsert_pr_comment: updates the first comment containing the tag" {
  COMMENTS_JSON='[{"id": 5, "body": "unrelated"}, {"id": 7, "body": "x <!-- tag:a --> y"}, {"id": 9, "body": "<!-- tag:a -->"}]'
  WRITE_CODE=200

  run upsert_pr_comment "<!-- tag:a -->" "new body"
  assert_success
  assert_output --partial "Updating existing PR comment #7"

  run cat "${CURL_LOG}"
  assert_line "PATCH"
  assert_line "${SERVER_URL}/api/v1/repos/owner/repo/issues/comments/7"
  refute_line "POST"
}

@test "upsert_pr_comment: body with quotes and newlines is JSON-encoded safely" {
  run upsert_pr_comment "<!-- t -->" $'line "one"\nline two'
  assert_success
  run cat "${CURL_LOG}"
  assert_line 'DATA={"body":"line \"one\"\nline two"}'
}

@test "upsert_pr_comment: comments with null body are ignored" {
  COMMENTS_JSON='[{"id": 3, "body": null}]'
  run upsert_pr_comment "<!-- t -->" "b"
  assert_success
  assert_output --partial "Creating new PR comment"
}

@test "upsert_pr_comment: API error object (non-array) falls back to create" {
  COMMENTS_JSON='{"message": "not found"}'
  run upsert_pr_comment "<!-- t -->" "b"
  assert_success
  assert_output --partial "Creating new PR comment"
}

@test "upsert_pr_comment: non-JSON listing response falls back to create" {
  COMMENTS_JSON='<html>502 Bad Gateway</html>'
  run upsert_pr_comment "<!-- t -->" "b"
  assert_success
  assert_output --partial "Creating new PR comment"
}

@test "upsert_pr_comment: failed create logs a warning but does not fail the caller" {
  WRITE_CODE=500
  run upsert_pr_comment "<!-- t -->" "b"
  assert_success
  assert_output --partial "Warning: Failed to create PR comment (HTTP 500)"
}

@test "upsert_pr_comment: failed update logs a warning" {
  COMMENTS_JSON='[{"id": 7, "body": "<!-- t -->"}]'
  WRITE_CODE=403
  run upsert_pr_comment "<!-- t -->" "b"
  assert_success
  assert_output --partial "Warning: Failed to update PR comment (HTTP 403)"
}
