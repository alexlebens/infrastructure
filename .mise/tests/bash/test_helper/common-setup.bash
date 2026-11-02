#!/usr/bin/env bash
# Common setup for .mise BATS test files.
# Source this in every test's setup() function:
#   load 'test_helper/common-setup'
#   _common_setup

_common_setup() {
  # Resolve project root (4 levels up from .mise/tests/bash/)
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  MISE_LIB_DIR="${PROJECT_ROOT}/.mise/lib"
  MISE_TASKS_DIR="${PROJECT_ROOT}/.mise/tasks"
  export PROJECT_ROOT MISE_LIB_DIR MISE_TASKS_DIR

  # Load bats helper libraries. Prefer vendored copies in .gitea/tests/bash/test_helper
  # or relative to BATS_TEST_DIRNAME, falling back to BATS_LIB_PATH.
  if [ -f "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash" ]; then
    load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
    load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"
  elif [ -f "${PROJECT_ROOT}/.gitea/tests/bash/test_helper/bats-support/load.bash" ]; then
    load "${PROJECT_ROOT}/.gitea/tests/bash/test_helper/bats-support/load"
    load "${PROJECT_ROOT}/.gitea/tests/bash/test_helper/bats-assert/load"
  else
    bats_load_library bats-support
    bats_load_library bats-assert
  fi

  # Isolate git from the developer's global/system configuration
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global init.defaultBranch main
  git config --global user.name "bats"
  git config --global user.email "bats@example.invalid"
  git config --global commit.gpgsign false

  # Directory for command stubs, prepended to PATH.
  MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
}

# Create an executable stub in MOCK_BIN.
#   _stub <command> <script body>
_stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "${MOCK_BIN}/$1"
  chmod +x "${MOCK_BIN}/$1"
}
