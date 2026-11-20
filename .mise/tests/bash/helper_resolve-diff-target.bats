#!/usr/bin/env bats
# Tests for .mise/lib/resolve-diff-target.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  source "${MISE_LIB_DIR}/resolve-diff-target.sh"
}

@test "resolve_diff_target: pull_request with branch changes diffs against merge-base" {
  git checkout -q -b feature
  _fixture_write "file.txt"
  _fixture_commit

  EVENT_NAME="pull_request" BASE_BRANCH="main"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "main...HEAD"
}

@test "resolve_diff_target: pull_request already merged falls back to HEAD^1..HEAD" {
  _fixture_write "file.txt"
  _fixture_commit

  # HEAD == main, so main...HEAD is empty
  EVENT_NAME="pull_request" BASE_BRANCH="main"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "HEAD^1..HEAD"
}

@test "resolve_diff_target: pull_request with unknown base ref falls back to HEAD^1..HEAD" {
  _fixture_write "file.txt"
  _fixture_commit

  EVENT_NAME="pull_request" BASE_BRANCH="origin/does-not-exist"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "HEAD^1..HEAD"
}

@test "resolve_diff_target: push with before SHA diffs from that SHA" {
  EVENT_NAME="push" EVENT_BEFORE="abc1234"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "abc1234..HEAD"
}

@test "resolve_diff_target: push with all-zero before SHA (new branch) uses HEAD^1..HEAD" {
  EVENT_NAME="push" EVENT_BEFORE="0000000000000000000000000000000000000000"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "HEAD^1..HEAD"
}

@test "resolve_diff_target: push without before SHA uses HEAD^1..HEAD" {
  EVENT_NAME="push"
  unset EVENT_BEFORE
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "HEAD^1..HEAD"
}

@test "resolve_diff_target: non-PR events (workflow_dispatch) are treated like push" {
  EVENT_NAME="workflow_dispatch" EVENT_BEFORE=""
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "HEAD^1..HEAD"
}

@test "resolve_diff_target: pull_request with large multi-commit diff does not fall back to HEAD^1..HEAD under pipefail" {
  git checkout -q -b feature

  _fixture_write "clusters/cl01tl/helm/alpha/Chart.yaml" "name: alpha"
  mkdir -p "clusters/cl01tl/helm/alpha/files"
  local i
  for i in $(seq -w 1 1500); do
    : > "clusters/cl01tl/helm/alpha/files/padding-template-resource-file-${i}.yaml"
  done
  _fixture_commit "commit 1: alpha with large file list"

  _fixture_write "clusters/cl01tl/helm/beta/Chart.yaml" "name: beta"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit "commit 2: beta"

  _fixture_write "clusters/cl01tl/helm/gamma/Chart.yaml" "name: gamma"
  _fixture_write "clusters/cl01tl/helm/gamma/values.yaml" "c: 1"
  _fixture_commit "commit 3: gamma"

  set -o pipefail
  EVENT_NAME="pull_request" BASE_BRANCH="main"
  resolve_diff_target
  assert_equal "${DIFF_TARGET}" "main...HEAD"

  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main
  assert_success
  assert_equal "$(_output_value charts)" "alpha beta gamma"
}
