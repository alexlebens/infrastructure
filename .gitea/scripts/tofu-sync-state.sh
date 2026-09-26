#!/usr/bin/env bash
set -euo pipefail

TOFU_DIR="${1:-tofu/buckets}"

echo ">> Synchronizing OpenTofu state for pre-existing Garage buckets in ${TOFU_DIR}..."

pushd "${TOFU_DIR}" > /dev/null

STATE_FILE="$(mktemp)"
NEW_STATE="$(mktemp)"
trap 'rm -f "${STATE_FILE:-}" "${NEW_STATE:-}"' EXIT

set +e
tofu state pull > "${STATE_FILE}" 2>/dev/null
PULL_EXIT=$?
set -e

if [ ${PULL_EXIT} -ne 0 ] || [ ! -s "${STATE_FILE}" ] || [ "$(cat "${STATE_FILE}")" = "" ]; then
  echo ">> State is empty or uninitialized. Initializing base state structure..."
  cat <<'EOF' > "${STATE_FILE}"
{
  "version": 4,
  "terraform_version": "1.8.8",
  "serial": 1,
  "lineage": "s3-buckets-lineage",
  "resources": [],
  "check_results": null
}
EOF
fi

STATE_UPDATED=false

# 1. Garage Tier A: web-assets on a_ps02sn
# Discovered ID: 6a509026035a0797211b6fc07cbcf51404953ae9278fb9a414a55aceb0abf670
GARAGE_A_ID="${GARAGE_A_BUCKET_ID:-6a509026035a0797211b6fc07cbcf51404953ae9278fb9a414a55aceb0abf670}"
HAS_A_BUCKET=$(jq -r '.resources[]? | select(.type == "garage_bucket" and .name == "a_ps02sn") | .instances[]? | select(.index_key == "web-assets") | .attributes.id // empty' "${STATE_FILE}" 2>/dev/null || true)

if [ -z "${HAS_A_BUCKET}" ] && [ -n "${GARAGE_A_ID}" ]; then
  echo ">> Injecting garage_bucket.a_ps02sn[\"web-assets\"] (id: ${GARAGE_A_ID}) into state..."
  jq --arg id "${GARAGE_A_ID}" '
    .serial += 1 |
    .resources += [{
      "mode": "managed",
      "type": "garage_bucket",
      "name": "a_ps02sn",
      "provider": "provider[\"registry.terraform.io/arsolitt/garagehq\"].a_ps02sn",
      "instances": [{
        "index_key": "web-assets",
        "schema_version": 0,
        "attributes": {
          "bytes": 0,
          "global_alias": "web-assets",
          "id": $id,
          "objects": 0
        },
        "sensitive_attributes": []
      }]
    }]
  ' "${STATE_FILE}" > "${NEW_STATE}"
  cp "${NEW_STATE}" "${STATE_FILE}"
  STATE_UPDATED=true
fi

# 2. Garage Tier B: reactive-resume on b_cl01tl
# Discovered ID: 23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46
GARAGE_B_ID="${GARAGE_B_BUCKET_ID:-23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46}"
HAS_B_BUCKET=$(jq -r '.resources[]? | select(.type == "garage_bucket" and .name == "b_cl01tl") | .instances[]? | select(.index_key == "reactive-resume") | .attributes.id // empty' "${STATE_FILE}" 2>/dev/null || true)

if [ -z "${HAS_B_BUCKET}" ] && [ -n "${GARAGE_B_ID}" ]; then
  echo ">> Injecting garage_bucket.b_cl01tl[\"reactive-resume\"] (id: ${GARAGE_B_ID}) into state..."
  jq --arg id "${GARAGE_B_ID}" '
    .serial += 1 |
    .resources += [{
      "mode": "managed",
      "type": "garage_bucket",
      "name": "b_cl01tl",
      "provider": "provider[\"registry.terraform.io/arsolitt/garagehq\"].b_cl01tl",
      "instances": [{
        "index_key": "reactive-resume",
        "schema_version": 0,
        "attributes": {
          "bytes": 0,
          "global_alias": "reactive-resume-assets",
          "id": $id,
          "objects": 0
        },
        "sensitive_attributes": []
      }]
    }]
  ' "${STATE_FILE}" > "${NEW_STATE}"
  cp "${NEW_STATE}" "${STATE_FILE}"
  STATE_UPDATED=true
fi

if [ "${STATE_UPDATED}" = "true" ]; then
  echo ">> Pushing synchronized state to Gitea backend..."
  tofu state push "${STATE_FILE}"
  echo ">> State successfully synchronized."
else
  echo ">> Garage buckets already present in state."
fi

popd > /dev/null
