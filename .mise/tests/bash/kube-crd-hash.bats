#!/usr/bin/env bats
# Tests for .mise/tasks/kube/crd-hash

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"

  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "crds" ]]; then
  printf "certificates.cert-manager.io:1\n"
  printf "issuers.cert-manager.io:1\n"
fi
exit 0
'
}

@test "kube:crd-hash: --help prints usage" {
  run "${MISE_TASKS_DIR}/kube/crd-hash" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kube:crd-hash: rejects unknown arguments" {
  run "${MISE_TASKS_DIR}/kube/crd-hash" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "kube:crd-hash: computes and sets hash output" {
  run "${MISE_TASKS_DIR}/kube/crd-hash"
  assert_success
  assert_output --partial "Cluster CRD Hash:"
  run _output_value hash
  assert_output --regexp '^[a-f0-9]{64}$'
}
