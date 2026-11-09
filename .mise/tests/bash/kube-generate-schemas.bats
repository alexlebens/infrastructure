#!/usr/bin/env bats
# Tests for .mise/tasks/kube/generate-schemas

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export OPENAPI_LOG="${BATS_TEST_TMPDIR}/openapi.log"
  export OPENAPI_INPUT="${BATS_TEST_TMPDIR}/openapi_input.json"

  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "crds" ]]; then
  if [ -n "${MOCK_CRD_JSON:-}" ]; then
    echo "${MOCK_CRD_JSON}"
  else
    cat <<EOF
{
  "apiVersion": "v1",
  "kind": "List",
  "items": [
    {
      "apiVersion": "apiextensions.k8s.io/v1",
      "kind": "CustomResourceDefinition",
      "metadata": {"name": "testcrds.example.com"},
      "spec": {
        "names": {"kind": "TestCRD"},
        "versions": [
          {
            "name": "v1",
            "schema": {"openAPIV3Schema": {"type": "object", "description": "v1"}}
          }
        ]
      }
    }
  ]
}
EOF
  fi
fi
exit 0
'

  _stub openapi2jsonschema.py '
echo "$*" >> "${OPENAPI_LOG}"
cp "$1" "${OPENAPI_INPUT}"
python3 - "$1" << "PY"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for item in data.get("items", []):
    spec = item.get("spec", {})
    kind = spec.get("names", {}).get("kind", "testcrd")
    versions = spec.get("versions", [{"name": "v1"}])
    for v in versions:
        vname = v.get("name", "v1")
        fn = f"{kind}_{vname}.json".lower()
        with open(fn, "w") as out:
            json.dump(v.get("schema", {}), out)
PY
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
  assert [ -f "${schema_dir}/.crd-manifest.json" ]
}

@test "kube:generate-schemas: skips unchanged CRDs on subsequent runs" {
  local schema_dir="${BATS_TEST_TMPDIR}/schemas"
  mkdir -p "${schema_dir}"

  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "1 changed/new, 0 cached, 0 removed"
  assert [ -f "${OPENAPI_LOG}" ]

  rm -f "${OPENAPI_LOG}"

  # Second run with identical CRD spec should skip openapi2jsonschema.py entirely
  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "0 changed/new, 1 cached, 0 removed"
  assert [ ! -f "${OPENAPI_LOG}" ]
}

@test "kube:generate-schemas: updates only changed CRDs and removes deleted CRDs" {
  local schema_dir="${BATS_TEST_TMPDIR}/schemas"
  mkdir -p "${schema_dir}"

  export MOCK_CRD_JSON='{
    "apiVersion": "v1",
    "kind": "List",
    "items": [
      {
        "metadata": {"name": "alphas.example.com"},
        "spec": {
          "names": {"kind": "Alpha"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "alpha-v1"}}}]
        }
      },
      {
        "metadata": {"name": "betas.example.com"},
        "spec": {
          "names": {"kind": "Beta"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "beta-v1"}}}]
        }
      },
      {
        "metadata": {"name": "gammas.example.com"},
        "spec": {
          "names": {"kind": "Gamma"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "gamma-v1"}}}]
        }
      }
    ]
  }'

  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "3 changed/new, 0 cached, 0 removed"
  assert [ -f "${schema_dir}/alpha_v1.json" ]
  assert [ -f "${schema_dir}/beta_v1.json" ]
  assert [ -f "${schema_dir}/gamma_v1.json" ]

  # Next run: Alpha is unchanged, Beta is modified, Gamma is removed
  export MOCK_CRD_JSON='{
    "apiVersion": "v1",
    "kind": "List",
    "items": [
      {
        "metadata": {"name": "alphas.example.com"},
        "spec": {
          "names": {"kind": "Alpha"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "alpha-v1"}}}]
        }
      },
      {
        "metadata": {"name": "betas.example.com"},
        "spec": {
          "names": {"kind": "Beta"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "beta-v2-modified"}}}]
        }
      }
    ]
  }'

  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "1 changed/new, 1 cached, 1 removed"
  assert_output --partial "Generated 2 JSON schemas"
  assert [ -f "${schema_dir}/alpha_v1.json" ]
  assert [ -f "${schema_dir}/beta_v1.json" ]
  assert [ ! -f "${schema_dir}/gamma_v1.json" ]

  # Verify openapi2jsonschema.py only received Beta (1 item)
  local converted_count
  converted_count=$(jq '.items | length' "${OPENAPI_INPUT}")
  assert_equal "${converted_count}" "1"
}
