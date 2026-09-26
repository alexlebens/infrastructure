#!/usr/bin/env bash
set -euo pipefail

TOFU_DIR="${1:-tofu/buckets}"

echo ">> Synchronizing OpenTofu state for pre-existing Garage buckets in ${TOFU_DIR}..."

pushd "${TOFU_DIR}" > /dev/null

STATE_FILE="$(mktemp)"
NEW_STATE="$(mktemp)"
PULL_ERR="$(mktemp)"
trap 'rm -f "${STATE_FILE:-}" "${NEW_STATE:-}" "${PULL_ERR:-}"' EXIT

GITEA_PASS="${TF_HTTP_PASSWORD:-${GITEA_TOKEN:-}}"
if [ -n "${GITEA_PASS}" ]; then
  # Auto-detect token owner from Gitea API to ensure basic auth username matches the token owner
  GITEA_USER=$(curl -sk --connect-timeout 4 --max-time 8 -H "Authorization: token ${GITEA_PASS}" "https://gitea.alexlebens.dev/api/v1/user" | jq -r '.username // empty' 2>/dev/null || true)
  if [ -n "${GITEA_USER}" ]; then
    echo ">> Authenticated to Gitea as: ${GITEA_USER}"
    export TF_HTTP_USERNAME="${GITEA_USER}"
  fi
fi

set +e
tofu state pull > "${STATE_FILE}" 2> "${PULL_ERR}"
PULL_EXIT=$?
set -e

if [ -s "${PULL_ERR}" ]; then
  echo ">> Notice from tofu state pull:"
  cat "${PULL_ERR}"
fi

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
  PUSH_OUT="$(mktemp)"
  set +e
  tofu state push -force -lock=false "${STATE_FILE}" > "${PUSH_OUT}" 2>&1
  PUSH_EXIT=$?
  set -e

  if [ ${PUSH_EXIT} -ne 0 ]; then
    echo ">> Notice: tofu state push failed:"
    cat "${PUSH_OUT}"
    echo ">> Attempting direct upload via Gitea Package API..."
    GITEA_URL="https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets"
    HTTP_CODE=$(curl -sk -w "%{http_code}" -o "${PUSH_OUT}" -X POST \
      -H "Authorization: token ${GITEA_PASS}" \
      -H "Content-Type: application/json" \
      --data-binary "@${STATE_FILE}" \
      "${GITEA_URL}" || true)

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ] || [ "${HTTP_CODE}" = "204" ]; then
      echo ">> State successfully pushed via Gitea Package API (HTTP ${HTTP_CODE})."
    else
      echo ">> Token upload returned HTTP ${HTTP_CODE}: $(cat "${PUSH_OUT}" | head -c 200)"
      if [ -n "${TF_HTTP_USERNAME:-}" ]; then
        echo ">> Attempting direct upload with Basic Auth (${TF_HTTP_USERNAME})..."
        HTTP_CODE=$(curl -sk -w "%{http_code}" -o "${PUSH_OUT}" -X POST \
          -u "${TF_HTTP_USERNAME}:${GITEA_PASS}" \
          -H "Content-Type: application/json" \
          --data-binary "@${STATE_FILE}" \
          "${GITEA_URL}" || true)
        if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ] || [ "${HTTP_CODE}" = "204" ]; then
          echo ">> State successfully pushed via Gitea Package API with Basic Auth (HTTP ${HTTP_CODE})."
        else
          echo ">> Error: Basic Auth upload also returned HTTP ${HTTP_CODE}: $(cat "${PUSH_OUT}" | head -c 200)"
          rm -f "${PUSH_OUT}"
          exit 1
        fi
      else
        rm -f "${PUSH_OUT}"
        exit 1
      fi
    fi
  else
    cat "${PUSH_OUT}"
    echo ">> State successfully synchronized via tofu state push."
  fi
  rm -f "${PUSH_OUT}"
else
  echo ">> Garage buckets already present in state."
fi

popd > /dev/null
