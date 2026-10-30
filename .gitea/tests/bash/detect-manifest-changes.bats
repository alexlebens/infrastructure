#!/usr/bin/env bats
# Tests for .gitea/scripts/detect-manifest-changes.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  _fixture_write "clusters/cl01tl/helm/alpha/Chart.yaml" "name: alpha"
  _fixture_write "clusters/cl01tl/helm/beta/Chart.yaml" "name: beta"
  _fixture_write "clusters/cl01tl/helm/gamma/Chart.yaml" "name: gamma"
  _fixture_commit "baseline"
  BASE_SHA="$(git rev-parse HEAD)"
}

@test "detect-manifest-changes: diff target lists changed charts in csv and multiline outputs" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/gamma/values.yaml" "c: 1"
  _fixture_commit

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir . --diff-target "${BASE_SHA}..HEAD"
  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value render-dir-csv)" "alpha,gamma"
  run _output_multiline render-dir
  assert_output "alpha
gamma"
}

@test "detect-manifest-changes: deleted charts are still reported so manifests get pruned" {
  git rm -q -r clusters/cl01tl/helm/beta
  _fixture_commit

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir . --diff-target "${BASE_SHA}..HEAD"
  assert_success
  assert_equal "$(_output_value render-dir-csv)" "beta"
}

@test "detect-manifest-changes: without diff target falls back to HEAD^..HEAD" {
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir .
  assert_success
  assert_output --partial "falling back to HEAD^..HEAD"
  assert_equal "$(_output_value render-dir-csv)" "beta"
}

@test "detect-manifest-changes: render-all discovers every chart directory" {
  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir . --render-all true
  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value render-dir-csv)" "alpha,beta,gamma"
}

@test "detect-manifest-changes: no helm changes yields empty outputs" {
  _fixture_write "README.md" "x"
  _fixture_commit

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir . --diff-target "${BASE_SHA}..HEAD"
  assert_success
  assert_output --partial "No chart changes detected"
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value render-dir-csv)" ""
}

@test "detect-manifest-changes: missing main dir falls back to cwd when it is the infra repo" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir does-not-exist --diff-target "${BASE_SHA}..HEAD"
  assert_success
  assert_equal "$(_output_value render-dir-csv)" "alpha"
}

@test "detect-manifest-changes: missing main dir outside the infra repo fails" {
  cd "${BATS_TEST_TMPDIR}"
  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir does-not-exist
  assert_failure
  assert_output --partial "Directory 'does-not-exist' not found"
}

@test "detect-manifest-changes: runs from parent directory via --main-dir" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit
  cd "${BATS_TEST_TMPDIR}"

  run "${SCRIPTS_DIR}/detect-manifest-changes.sh" --main-dir repo --diff-target "${BASE_SHA}..HEAD"
  assert_success
  assert_equal "$(_output_value render-dir-csv)" "alpha"
}
