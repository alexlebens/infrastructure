#!/usr/bin/env bats
# Tests for k8s_get_fingerprint and k8s_get_api_versions in .mise/lib/k8s.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"

  # Stub kubectl: simulates version, crd, and api-versions endpoints
  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "--raw" && "$3" == "/version" ]]; then
  printf "{\"gitVersion\": \"v1.31.0\"}\n"
elif [[ "$1" == "version" ]]; then
  exit 0
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

  source "${MISE_LIB_DIR}/k8s.sh"
}

@test "k8s_get_fingerprint: computes fingerprint hash" {
  run k8s_get_fingerprint
  assert_success
  assert_output --regexp '^[a-f0-9]{64}$'
}

@test "k8s_get_api_versions: reads from cache file when present" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  echo "v1,apps/v1,cached/v1/MyKind" > "${cache}"

  run k8s_get_api_versions "${cache}"
  assert_success
  assert_output "v1,apps/v1,cached/v1/MyKind"
  # Should NOT query kubectl when cache is valid
  assert [ ! -f "${KUBECTL_LOG}" ]
}

@test "k8s_get_api_versions: fetches from cluster and populates cache file" {
  local cache="${BATS_TEST_TMPDIR}/cache.txt"
  : > "${cache}"

  run k8s_get_api_versions "${cache}"
  assert_success
  assert_output "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
  run cat "${cache}"
  assert_output "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}

@test "k8s_get_api_versions: fetches from cluster without cache file" {
  run k8s_get_api_versions
  assert_success
  assert_output "apps/v1,batch/v1,monitoring.coreos.com/v1/Prometheus,monitoring.coreos.com/v1/ServiceMonitor,v1"
}
