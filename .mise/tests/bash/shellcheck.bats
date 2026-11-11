#!/usr/bin/env bats
# Tests that all bash .mise tasks and libraries pass shellcheck cleanly.

setup() {
  load 'test_helper/common-setup'
  _common_setup

  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "shellcheck is not installed"
  fi
}

@test "shellcheck: all .mise/lib scripts pass shellcheck" {
  local scripts=()
  while IFS= read -r -d '' f; do
    scripts+=("$f")
  done < <(find "${MISE_LIB_DIR}" -type f -name "*.sh" -print0 2>/dev/null)

  [ ${#scripts[@]} -gt 0 ]
  run shellcheck "${scripts[@]}"
  assert_success
}

@test "shellcheck: all .mise/tasks bash scripts pass shellcheck" {
  local scripts=()
  while IFS= read -r -d '' f; do
    if head -n 1 "$f" | grep -qE '^#!/(usr/)?bin/(env )?bash'; then
      scripts+=("$f")
    fi
  done < <(find "${MISE_TASKS_DIR}" -type f -print0 2>/dev/null)

  [ ${#scripts[@]} -gt 0 ]
  run shellcheck "${scripts[@]}"
  assert_success
}
