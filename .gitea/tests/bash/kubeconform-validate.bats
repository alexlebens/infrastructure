#!/usr/bin/env bats
# Tests for .gitea/scripts/kubeconform-validate.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECONFORM_LOG="${BATS_TEST_TMPDIR}/kubeconform.log"

  _stub kubeconform '
echo "$*" >> "${KUBECONFORM_LOG}"
exit 0
'
}

@test "kubeconform-validate: --help prints usage" {
  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kubeconform-validate: requires --chart or --manifest" {
  run "${SCRIPTS_DIR}/kubeconform-validate.sh"
  assert_failure
  assert_output --partial "Error: --chart (or CHART env var) or --manifest is required."
}

@test "kubeconform-validate: fails if manifest path does not exist" {
  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --chart non-existent-chart
  assert_failure
  assert_output --partial "Error: Manifest path"
  assert_output --partial "not found"
}

@test "kubeconform-validate: empty manifest directory skips validation cleanly" {
  local dir="${BATS_TEST_TMPDIR}/empty-manifests"
  mkdir -p "${dir}"

  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --manifest "${dir}"
  assert_success
  assert_output --partial "No manifest files found in"
  assert [ ! -f "${KUBECONFORM_LOG}" ]
}

@test "kubeconform-validate: validates all yaml files in a directory" {
  local dir="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${dir}"
  echo "kind: Deployment" > "${dir}/deployment.yaml"
  echo "kind: Service" > "${dir}/service.yaml"

  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --manifest "${dir}"
  assert_success
  assert_output --partial "kubeconform validation completed successfully."

  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "-summary -output text"
  assert_output --partial "-ignore-missing-schemas"
  assert_output --partial "${dir}/deployment.yaml"
  assert_output --partial "${dir}/service.yaml"
}

@test "kubeconform-validate: passes stripped kubernetes-version and strict flags" {
  local dir="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${dir}"
  echo "kind: ConfigMap" > "${dir}/cm.yaml"

  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --manifest "${dir}" --kubernetes-version "v1.31.0" --strict
  assert_success

  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "-kubernetes-version 1.31.0"
  assert_output --partial "-strict"
}

@test "kubeconform-validate: validates a single manifest file" {
  local file="${BATS_TEST_TMPDIR}/single.yaml"
  echo "kind: Ingress" > "${file}"

  run "${SCRIPTS_DIR}/kubeconform-validate.sh" --manifest "${file}"
  assert_success
  run cat "${KUBECONFORM_LOG}"
  assert_output --partial "${file}"
}
