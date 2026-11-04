#!/usr/bin/env bats
# Tests for .mise/tasks/kube/generate-schemas

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export OPENAPI_LOG="${BATS_TEST_TMPDIR}/openapi.log"

  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "crds" ]]; then
  echo "testcrds.test.io"
elif [[ "$1" == "get" && "$2" == "crd" ]]; then
  echo "apiVersion: apiextensions.k8s.io/v1"
  echo "kind: CustomResourceDefinition"
fi
exit 0
'

  _stub openapi2jsonschema.py '
echo "$*" >> "${OPENAPI_LOG}"
echo "{}" > "testcrd_v1.json"
exit 0
'
}

@test "kube:generate-schemas: --help prints usage" {
  run "${MISE_TASKS_DIR}/kube/generate-schemas" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "kube:generate-schemas: rejects unknown arguments" {
  run "${MISE_TASKS_DIR}/kube/generate-schemas" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "kube:generate-schemas: extracts CRDs and converts to JSON" {
  local schema_dir="${BATS_TEST_TMPDIR}/schemas"
  mkdir -p "${schema_dir}"

  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "Generated 1 JSON schemas"
  assert [ -f "${schema_dir}/testcrd_v1.json" ]
}
