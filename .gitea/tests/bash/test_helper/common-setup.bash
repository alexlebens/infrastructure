#!/usr/bin/env bash
# Common setup for all BATS test files.
# Source this in every test's setup() function:
#   load 'test_helper/common-setup'
#   _common_setup

_common_setup() {
  # Resolve project root (3 levels up from .gitea/tests/bash/)
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPTS_DIR="${PROJECT_ROOT}/.gitea/scripts"
  export PROJECT_ROOT SCRIPTS_DIR

  # Load bats helper libraries. Prefer the vendored copies installed by CI
  # (bats-action) and fall back to BATS_LIB_PATH (e.g. Homebrew installs).
  if [ -f "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash" ]; then
    load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
    load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"
  else
    bats_load_library bats-support
    bats_load_library bats-assert
  fi

  # Isolate git from the developer's global/system configuration so fixture
  # repositories behave identically locally and in CI.
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global init.defaultBranch main
  git config --global user.name "bats"
  git config --global user.email "bats@example.invalid"
  git config --global commit.gpgsign false
  git config --global advice.detachedHead false

  # Every test gets a fresh GITHUB_OUTPUT file.
  GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
  : > "${GITHUB_OUTPUT}"
  export GITHUB_OUTPUT
  unset GITHUB_EVENT_NAME GITHUB_STEP_SUMMARY

  # Directory for command stubs, prepended to PATH.
  MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
}

# Create a throwaway git repository with an initial empty commit and cd into it.
# Sets FIXTURE_REPO.
_init_fixture_repo() {
  FIXTURE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FIXTURE_REPO}"
  git -C "${FIXTURE_REPO}" init -q
  git -C "${FIXTURE_REPO}" commit -q --allow-empty -m "init"
  cd "${FIXTURE_REPO}" || return 1
  export FIXTURE_REPO
}

# Write a file (creating parent directories) inside the current directory.
#   _fixture_write <path> [content]
_fixture_write() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${2:-placeholder}" > "$1"
}

# Stage everything and commit.
#   _fixture_commit [message]
_fixture_commit() {
  git add -A
  git commit -q -m "${1:-change}"
}

# Print the value of a single-line key from GITHUB_OUTPUT (last occurrence wins).
#   _output_value <key>
_output_value() {
  local key="$1"
  grep -E "^${key}=" "${GITHUB_OUTPUT}" | tail -n 1 | cut -d= -f2-
}

# Print the body of a multi-line (heredoc style) key from GITHUB_OUTPUT.
#   _output_multiline <key> [delimiter]
_output_multiline() {
  local key="$1" delim="${2:-EOF}"
  awk -v start="${key}<<${delim}" -v end="${delim}" '
    $0 == start { capture = 1; next }
    capture && $0 == end { exit }
    capture { print }
  ' "${GITHUB_OUTPUT}"
}

# Create an executable stub in MOCK_BIN.
#   _stub <command> <script body>
_stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${MOCK_BIN}/$1"
  chmod +x "${MOCK_BIN}/$1"
}
