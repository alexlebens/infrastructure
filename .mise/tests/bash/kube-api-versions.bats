#!/usr/bin/env bats
# Tests for .mise/tasks/kube/api-versions

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"

  # Stub kubectl: simulates openapi/v3, version, crd, and api-versions endpoints
  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "--raw" && "$3" == "/openapi/v3" ]]; then
  printf "{\"paths\":{\"api/v1\":{\"serverRelativeURL\":\"/openapi/v3/api/v1?hash=abc\"}}}\n"
elif [[ "$1" == "version" ]]; then
  exit 0
elif [[ "$1" == "get" && "$2" == "crd" ]]; then
  printf "monitoring.coreos.com/v1/Prometheus\n"
  printf "monitoring.coreos.com/v1/ServiceMonitor\n"
elif [[ "$1" == "api-versions" ]]; then
  printf "v1\napps/v1\nbatch/v1\n"
fi
exit 0
'
}

@test "kube:api-versions: --help prints usage" {
  run "${MISE_TASKS_DIR}/kube/api-versions" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kube:api-versions: rejects unknown arguments" {
  run "${MISE_TASKS_DIR}/kube/api-versions" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "kube:api-versions: computes fingerprint with --fingerprint" {
  run "${MISE_TASKS_DIR}/kube/api-versions" --fingerprint
  assert_success
  assert_output --partial "Cluster Fingerprint:"
  run _output_value fingerprint
  assert_output --regexp '^[a-f0-9]{64}$'
}

@test "kube:api-versions: reads from cache file when present" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  echo "v1,apps/v1,cached/v1/MyKind" > "${cache}"

  run "${MISE_TASKS_DIR}/kube/api-versions" --cache-file "${cache}"
  assert_success
  assert_output --partial "Using cached API versions"
  assert_equal "$(_output_value api-versions)" "v1,apps/v1,cached/v1/MyKind"
  # Should NOT query kubectl when cache is valid
  assert [ ! -f "${KUBECTL_LOG}" ]
}

@test "kube:api-versions: fetches from cluster and populates empty cache file" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  : > "${cache}"

  run "${MISE_TASKS_DIR}/kube/api-versions" --cache-file "${cache}"
  assert_success
  assert_output --partial "Saved API versions to cache file"
  assert_equal "$(_output_value api-versions)" "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
  run cat "${cache}"
  assert_output "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}

@test "kube:api-versions: fetches from cluster without cache file" {
  run "${MISE_TASKS_DIR}/kube/api-versions"
  assert_success
  assert_equal "$(_output_value api-versions)" "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}
