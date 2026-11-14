#!/usr/bin/env bats
# Tests for .mise/tasks/gitea/detect-helm

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  # Baseline: two charts on main
  _fixture_write "clusters/cl01tl/helm/alpha/Chart.yaml" "name: alpha"
  _fixture_write "clusters/cl01tl/helm/beta/Chart.yaml" "name: beta"
  _fixture_write "clusters/cl01tl/helm/beta/scripts/run.sh" "echo hi"
  _fixture_write "clusters/cl01tl/helm/gamma/Chart.yaml" "name: gamma"
  _fixture_write "clusters/cl01tl/helm/gamma/tests/unit.bats" "# test"
  _fixture_write "clusters/other/helm/alpha/Chart.yaml" "name: alpha"
  _fixture_commit "baseline"
  BASE_SHA="$(git rev-parse HEAD)"
}

_run_detect() {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name push --event-before "${BASE_SHA}" "$@"
}

@test "detect-helm-changes: single chart change produces matrix and no scripts" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["alpha"]'
  assert_equal "$(_output_value charts)" "alpha"
  assert_equal "$(_output_value scripts-detected)" "false"
  assert_equal "$(_output_value script-matrix)" "[]"
}

@test "detect-helm-changes: charts with scripts/ or tests/ are added to script-matrix" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_write "clusters/cl01tl/helm/gamma/values.yaml" "c: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value matrix)" '["alpha","beta","gamma"]'
  assert_equal "$(_output_value charts)" "alpha beta gamma"
  assert_equal "$(_output_value scripts-detected)" "true"
  assert_equal "$(_output_value script-matrix)" '["beta","gamma"]'
}

@test "detect-helm-changes: deleted chart (no Chart.yaml) is excluded" {
  git rm -q -r "clusters/cl01tl/helm/alpha"
  _fixture_commit "remove alpha"

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value matrix)" "[]"
  assert_equal "$(_output_value charts)" ""
}

@test "detect-helm-changes: changes in another cluster are ignored" {
  _fixture_write "clusters/other/helm/alpha/values.yaml" "x: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
}

@test "detect-helm-changes: --cluster selects the other cluster" {
  _fixture_write "clusters/other/helm/alpha/values.yaml" "x: 1"
  _fixture_commit

  _run_detect --cluster other
  assert_success
  assert_equal "$(_output_value matrix)" '["alpha"]'
}

@test "detect-helm-changes: non-helm changes produce empty outputs" {
  _fixture_write "README.md" "docs"
  _fixture_commit

  _run_detect
  assert_success
  assert_output --partial "Did not find any valid helm charts to test"
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value scripts-detected)" "false"
  assert_equal "$(_output_value script-matrix)" "[]"
}

@test "detect-helm-changes: pull_request mode diffs feature branch against base" {
  git checkout -q -b feature
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 2"
  _fixture_commit

  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main
  assert_success
  assert_equal "$(_output_value matrix)" '["beta"]'
  assert_equal "$(_output_value script-matrix)" '["beta"]'
}

@test "detect-helm-changes: works without GITHUB_OUTPUT" {
  unset GITHUB_OUTPUT
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_output --partial "Charts to test:"
}

@test "detect-helm-changes: unknown argument fails" {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "detect-helm-changes: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "detect-helm-changes: skips charts matching state-file tree sha and tooling hash" {
  git checkout -q -b "feat/state-cache"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit "commit 1"

  local alpha_tree beta_tree state_file
  alpha_tree="$(git rev-parse HEAD:clusters/cl01tl/helm/alpha)"
  beta_tree="$(git rev-parse HEAD:clusters/cl01tl/helm/beta)"
  state_file="${BATS_TEST_TMPDIR}/state.json"

  jq -n --arg a "${alpha_tree}:chash1" --arg b "${beta_tree}:shash1" \
    '{charts: {alpha: $a}, scripts: {beta: $b}}' > "${state_file}"

  run "${MISE_TASKS_DIR}/gitea/detect-helm" \
    --event-name pull_request \
    --base-branch main \
    --state-file "${state_file}" \
    --chart-tooling-hash "chash1" \
    --script-tooling-hash "shash1"

  assert_success
  assert_output --partial "Skipping charts unchanged since last cached pass:"
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["beta"]'
  assert_equal "$(_output_value scripts-detected)" "false"
  assert_equal "$(_output_value script-matrix)" "[]"
}

@test "detect-helm-changes: tooling hash change invalidates cached state" {
  git checkout -q -b "feat/tooling-hash"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit "commit 1"

  local alpha_tree state_file
  alpha_tree="$(git rev-parse HEAD:clusters/cl01tl/helm/alpha)"
  state_file="${BATS_TEST_TMPDIR}/state.json"

  jq -n --arg a "${alpha_tree}:chash1" '{charts: {alpha: $a}, scripts: {}}' > "${state_file}"

  run "${MISE_TASKS_DIR}/gitea/detect-helm" \
    --event-name pull_request \
    --base-branch main \
    --state-file "${state_file}" \
    --chart-tooling-hash "chash2"

  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["alpha"]'
}
