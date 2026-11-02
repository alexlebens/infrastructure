#!/usr/bin/env bats
# Tests that all .mise tasks and libraries pass shellcheck cleanly.

setup() {
  load 'test_helper/common-setup'
  _common_setup

  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "shellcheck is not installed"
  fi
}

@test "shellcheck: all .mise/lib scripts pass shellcheck" {
  local scripts=()
  while IFS= read -r f; do
    [ -f "$f" ] && scripts+=("$f")
  done < <(find "${MISE_LIB_DIR}" -type f -name "*.sh")

  [ ${#scripts[@]} -gt 0 ]
  run shellcheck "${scripts[@]}"
  assert_success
}

@test "shellcheck: all .mise/tasks scripts pass shellcheck" {
  local scripts=()
  while IFS= read -r f; do
    [ -f "$f" ] && scripts+=("$f")
  done < <(find "${MISE_TASKS_DIR}" -type f)

  [ ${#scripts[@]} -gt 0 ]
  run shellcheck "${scripts[@]}"
  assert_success
}
