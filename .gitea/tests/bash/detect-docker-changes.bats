#!/usr/bin/env bats
# Tests for .gitea/scripts/detect-docker-changes.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  _fixture_write "hosts/ps01/app-a/compose.yaml" "services: {}"
  _fixture_write "hosts/ps01/app-b/compose.yml" "services: {}"
  _fixture_write "hosts/ps02/app-c/docker-compose.yaml" "services: {}"
  _fixture_write "hosts/ps02/app-d/docker-compose.yml" "services: {}"
  _fixture_write "hosts/ps02/not-compose/config.txt" "x"
  _fixture_commit "baseline"
  BASE_SHA="$(git rev-parse HEAD)"
}

_run_detect() {
  run "${SCRIPTS_DIR}/detect-docker-changes.sh" --event-name push --event-before "${BASE_SHA}" "$@"
}

@test "detect-docker-changes: all compose file name variants are recognised" {
  for d in hosts/ps01/app-a hosts/ps01/app-b hosts/ps02/app-c hosts/ps02/app-d; do
    _fixture_write "${d}/.env.example" "X=1"
  done
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["hosts/ps01/app-a","hosts/ps01/app-b","hosts/ps02/app-c","hosts/ps02/app-d"]'
  assert_equal "$(_output_value dirs)" "hosts/ps01/app-a hosts/ps01/app-b hosts/ps02/app-c hosts/ps02/app-d"
}

@test "detect-docker-changes: nested file changes map to the compose directory" {
  _fixture_write "hosts/ps01/app-a/config/nested/file.conf" "x"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value matrix)" '["hosts/ps01/app-a"]'
}

@test "detect-docker-changes: directories without a compose file are ignored" {
  _fixture_write "hosts/ps02/not-compose/config.txt" "changed"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value matrix)" "[]"
  assert_equal "$(_output_value dirs)" ""
}

@test "detect-docker-changes: host-level files (hosts/<host>/file) are ignored" {
  _fixture_write "hosts/ps01/README.md" "x"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
}

@test "detect-docker-changes: deleted compose directory is ignored" {
  git rm -q -r hosts/ps01/app-a
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
}

@test "detect-docker-changes: unknown argument fails" {
  run "${SCRIPTS_DIR}/detect-docker-changes.sh" --nope
  assert_failure
  assert_output --partial "Unknown argument"
}
