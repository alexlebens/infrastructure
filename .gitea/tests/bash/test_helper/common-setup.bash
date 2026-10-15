#!/usr/bin/env bash
# Common setup for all BATS test files.
# Source this in every test's setup() function:
#   load 'test_helper/common-setup'

_common_setup() {
  # Resolve project root (3 levels up from .gitea/tests/bash/)
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export PROJECT_ROOT

  # Load bats helper libraries
  load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"
}
