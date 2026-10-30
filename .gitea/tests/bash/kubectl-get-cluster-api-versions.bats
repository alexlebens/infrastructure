#!/usr/bin/env bats
# Tests for .gitea/scripts/kubectl-get-cluster-api-versions.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"

  # Stub kubectl: simulates version, crd, and api-versions endpoints
  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "--raw" && "$3" == "/version" ]]; then
  printf "{\"gitVersion\": \"v1.31.0\"}\n"
elif [[ "$1" == "get" && "$2" == "crd" ]]; then
  if [[ "$*" == *"range .spec.versions"* ]]; then
    # Full API versions query
    printf "monitoring.coreos.com/v1/Prometheus\n"
    printf "monitoring.coreos.com/v1/ServiceMonitor\n"
  else
    # Fingerprint query
    printf "prometheuses.monitoring.coreos.com:1\n"
    printf "servicemonitors.monitoring.coreos.com:2\n"
  fi
elif [[ "$1" == "api-versions" ]]; then
  printf "v1\napps/v1\nbatch/v1\n"
fi
exit 0
'
}

@test "kubectl-get-cluster-api-versions: --help prints usage" {
  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kubectl-get-cluster-api-versions: rejects unknown arguments" {
  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "kubectl-get-cluster-api-versions: computes fingerprint with --fingerprint" {
  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh" --fingerprint
  assert_success
  assert_output --partial "Cluster Fingerprint:"
  run _output_value fingerprint
  assert_output --regexp '^[a-f0-9]{64}$'
}

@test "kubectl-get-cluster-api-versions: reads from cache file when present" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  echo "v1,apps/v1,cached/v1/MyKind" > "${cache}"

  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh" --cache-file "${cache}"
  assert_success
  assert_output --partial "Using cached API versions"
  assert_equal "$(_output_value api-versions)" "v1,apps/v1,cached/v1/MyKind"
  # Should NOT query kubectl when cache is valid
  assert [ ! -f "${KUBECTL_LOG}" ]
}

@test "kubectl-get-cluster-api-versions: fetches from cluster and populates empty cache file" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  : > "${cache}" # empty file should trigger fetch

  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh" --cache-file "${cache}"
  assert_success
  assert_output --partial "Saved API versions to cache file"
  assert_equal "$(_output_value api-versions)" "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
  run cat "${cache}"
  assert_output "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}

@test "kubectl-get-cluster-api-versions: fetches from cluster without cache file" {
  run "${SCRIPTS_DIR}/kubectl-get-cluster-api-versions.sh"
  assert_success
  assert_equal "$(_output_value api-versions)" "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}
