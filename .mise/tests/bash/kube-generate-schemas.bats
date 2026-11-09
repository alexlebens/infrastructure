#!/usr/bin/env bats
# Tests for .mise/tasks/kube/generate-schemas

setup() {
  load 'test_helper/common-setup'
  _common_setup

  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  export OPENAPI_LOG="${BATS_TEST_TMPDIR}/openapi.log"
  export OPENAPI_INPUT="${BATS_TEST_TMPDIR}/openapi_input.json"
  export K8S_OPENAPI_INDEX_FILE="${BATS_TEST_TMPDIR}/openapi_index.txt"

  _stub kubectl '
echo "$*" >> "${KUBECTL_LOG}"
if [[ "$1" == "get" && "$2" == "--raw" && "$3" == "/openapi/v3" ]]; then
  if [ -n "${MOCK_OPENAPI_V3_JSON:-}" ]; then
    echo "${MOCK_OPENAPI_V3_JSON}"
  else
    printf "{\"paths\":{\"apis/example.com/v1\":{\"serverRelativeURL\":\"/openapi/v3/apis/example.com/v1?hash=h1\"}}}\n"
  fi
elif [[ "$1" == "get" && "$2" == "crd" && "$3" == "-o" ]]; then
  if [ -n "${MOCK_CRD_META:-}" ]; then
    printf "%b" "${MOCK_CRD_META}"
  fi
elif [[ "$1" == "get" && "$2" == "crds" ]]; then
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
      "metadata": {"name": "testcrds.example.com", "resourceVersion": "100"},
      "spec": {
        "group": "example.com",
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

@test "kube:generate-schemas: uses OpenAPI v3 index and metadata to fetch only changed CRDs" {
  local schema_dir="${BATS_TEST_TMPDIR}/schemas"
  mkdir -p "${schema_dir}"

  # Pre-populate OpenAPI v3 index file as `kube:api-versions --fingerprint` would
  cat > "${K8S_OPENAPI_INDEX_FILE}" <<EOF
/openapi/v3/apis/alpha.io/v1?hash=alpha_h1
/openapi/v3/apis/beta.io/v1?hash=beta_h1
EOF

  export MOCK_CRD_META="alphas.alpha.io\talpha.io\tAlpha\tv1,\t10\nbetas.beta.io\tbeta.io\tBeta\tv1,\t20\n"
  export MOCK_CRD_JSON='{
    "apiVersion": "v1",
    "kind": "List",
    "items": [
      {
        "metadata": {"name": "alphas.alpha.io", "resourceVersion": "10"},
        "spec": {
          "group": "alpha.io",
          "names": {"kind": "Alpha"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object"}}}]
        }
      },
      {
        "metadata": {"name": "betas.beta.io", "resourceVersion": "20"},
        "spec": {
          "group": "beta.io",
          "names": {"kind": "Beta"},
          "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object"}}}]
        }
      }
    ]
  }'

  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "2 changed/new, 0 cached, 0 removed"

  # Now simulate Beta's OpenAPI hash changing while Alpha stays the same
  cat > "${K8S_OPENAPI_INDEX_FILE}" <<EOF
/openapi/v3/apis/alpha.io/v1?hash=alpha_h1
/openapi/v3/apis/beta.io/v1?hash=beta_h2_changed
EOF
  export MOCK_CRD_META="alphas.alpha.io\talpha.io\tAlpha\tv1,\t10\nbetas.beta.io\tbeta.io\tBeta\tv1,\t21\n"
  export MOCK_CRD_JSON='{
    "apiVersion": "apiextensions.k8s.io/v1",
    "kind": "CustomResourceDefinition",
    "metadata": {"name": "betas.beta.io", "resourceVersion": "21"},
    "spec": {
      "group": "beta.io",
      "names": {"kind": "Beta"},
      "versions": [{"name": "v1", "schema": {"openAPIV3Schema": {"type": "object", "description": "updated"}}}]
    }
  }'

  : > "${KUBECTL_LOG}"
  run "${MISE_TASKS_DIR}/kube/generate-schemas" --schema-dir "${schema_dir}"
  assert_success
  assert_output --partial "Discovered 2 CRDs via cluster metadata (1 need fetching)"
  assert_output --partial "1 changed/new, 1 cached, 0 removed"

  # Verify kubectl only fetched betas.beta.io and NOT all crds
  run cat "${KUBECTL_LOG}"
  assert_output --partial "get crds betas.beta.io -o json"
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
