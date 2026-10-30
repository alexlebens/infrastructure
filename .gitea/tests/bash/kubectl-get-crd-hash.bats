#!/usr/bin/env bats
# Tests for .gitea/scripts/kubectl-get-crd-hash.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  # Stub kubectl to return sample CRDs
  _stub kubectl '
if [[ "$1" == "get" && "$2" == "crds" ]]; then
  printf "certificates.cert-manager.io:1\nissuers.cert-manager.io:2\n"
fi
exit 0
'
}

@test "kubectl-get-crd-hash: --help prints usage" {
  run "${SCRIPTS_DIR}/kubectl-get-crd-hash.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kubectl-get-crd-hash: rejects unknown arguments" {
  run "${SCRIPTS_DIR}/kubectl-get-crd-hash.sh" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "kubectl-get-crd-hash: computes and sets hash output" {
  run "${SCRIPTS_DIR}/kubectl-get-crd-hash.sh"
  assert_success
  assert_output --partial "Cluster CRD Hash:"
  run _output_value hash
  assert_output --regexp '^[a-f0-9]{64}$'
}
