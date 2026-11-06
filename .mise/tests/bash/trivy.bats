#!/usr/bin/env bats
# Tests for .mise/tasks/check/trivy

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export TRIVY_LOG="${BATS_TEST_TMPDIR}/trivy.log"

  _stub jq '
cat <<EOF
0	0	0	0
EOF
'
  _stub trivy '
echo "$*" >> "${TRIVY_LOG}"
echo "{\"Results\": []}"
exit 0
'
}

@test "check:trivy: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/trivy" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "check:trivy: requires --chart or --manifest" {
  run "${MISE_TASKS_DIR}/check/trivy"
  assert_failure
  assert_output --partial "Error: --chart (or CHART env var) or --manifest is required."
}

@test "check:trivy: fails if manifest path does not exist" {
  run "${MISE_TASKS_DIR}/check/trivy" --chart non-existent-chart
  assert_failure
  assert_output --partial "Error: Manifest path"
  assert_output --partial "not found"
}

@test "check:trivy: scans manifest directory successfully" {
  local dir="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${dir}"
  echo "kind: Deployment" > "${dir}/deployment.yaml"

  run "${MISE_TASKS_DIR}/check/trivy" --manifest "${dir}"
  assert_success
  assert_output --partial "Trivy scan passed gate"

  run cat "${TRIVY_LOG}"
  assert_output --partial "config"
  assert_output --partial "--format json"
}

@test "check:trivy: fails when findings exist under default FAIL_ON=ANY" {
  local dir="${BATS_TEST_TMPDIR}/manifests-findings"
  mkdir -p "${dir}"
  echo "kind: Deployment" > "${dir}/deployment.yaml"

  _stub jq '
cat <<EOF
0	0	1	0
EOF
'

  run "${MISE_TASKS_DIR}/check/trivy" --manifest "${dir}"
  assert_failure
  assert_output --partial "Security check failed: 1 misconfiguration(s) detected"
}
