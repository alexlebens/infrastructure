#!/usr/bin/env bats
# Tests for .mise/tasks/check/kubeconform

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECONFORM_LOG="${BATS_TEST_TMPDIR}/kubeconform.log"

  _stub kubeconform '
echo "$*" >> "${KUBECONFORM_LOG}"
exit 0
'
}

@test "check:kubeconform: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/kubeconform" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "check:kubeconform: requires --chart or --manifest" {
  run "${MISE_TASKS_DIR}/check/kubeconform"
  assert_failure
  assert_output --partial "Error: --chart (or CHART env var) or --manifest is required."
}

@test "check:kubeconform: fails if manifest path does not exist" {
  run "${MISE_TASKS_DIR}/check/kubeconform" --chart non-existent-chart
  assert_failure
  assert_output --partial "Error: Manifest path"
  assert_output --partial "not found"
}

@test "check:kubeconform: empty manifest directory skips validation cleanly" {
  local dir="${BATS_TEST_TMPDIR}/empty-manifests"
  mkdir -p "${dir}"

  run "${MISE_TASKS_DIR}/check/kubeconform" --manifest "${dir}"
  assert_success
  assert_output --partial "No manifest files found in"
  assert [ ! -f "${KUBECONFORM_LOG}" ]
}

@test "check:kubeconform: validates all yaml files in a directory" {
  local dir="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${dir}"
  echo "kind: Deployment" > "${dir}/deployment.yaml"
  echo "kind: Service" > "${dir}/service.yaml"

  run "${MISE_TASKS_DIR}/check/kubeconform" --manifest "${dir}"
  assert_success
  assert_output --partial "kubeconform validation completed successfully."

  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "-summary -output text"
  assert_output --partial "-ignore-missing-schemas"
  assert_output --partial "${dir}/deployment.yaml"
  assert_output --partial "${dir}/service.yaml"
}

@test "check:kubeconform: passes stripped kubernetes-version and strict flags" {
  local dir="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${dir}"
  echo "kind: ConfigMap" > "${dir}/cm.yaml"

  run "${MISE_TASKS_DIR}/check/kubeconform" --manifest "${dir}" --kubernetes-version "v1.31.0" --strict
  assert_success

  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "-kubernetes-version 1.31.0"
  assert_output --partial "-strict"
}

@test "check:kubeconform: validates a single manifest file" {
  local file="${BATS_TEST_TMPDIR}/single.yaml"
  echo "kind: Ingress" > "${file}"

  run "${MISE_TASKS_DIR}/check/kubeconform" --manifest "${file}"
  assert_success
  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "${file}"
}
