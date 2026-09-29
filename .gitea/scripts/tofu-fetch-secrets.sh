#!/usr/bin/env bash
set -euo pipefail

output_var() {
  local key="$1"
  local val="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${key}=${val}" >> "${GITHUB_OUTPUT}"
  fi
}

mask_var() {
  local val="$1"
  if [ -n "${val}" ]; then
    echo "::add-mask::${val}"
  fi
}

# Login to OpenBao via Kubernetes Auth
login_openbao_k8s() {
  local role="$1"
  local jwt="$2"
  curl -sk --connect-timeout 2 --max-time 4 -X POST \
    -H "Content-Type: application/json" \
    -d "{\"role\": \"${role}\", \"jwt\": \"${jwt}\"}" \
    "${OPENBAO_ADDR}/v1/auth/kubernetes/login" 2>/dev/null || true
}

# Helper to fetch a JSON payload from OpenBao KV v2 (mount: secret)
fetch_bao_path() {
  local path="$1"
  curl -sk --connect-timeout 2 --max-time 4 \
    -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
    "${OPENBAO_ADDR}/v1/secret/data/${path}" 2>/dev/null || true
}

echo ">> Initializing OpenBao secret extraction..."

OPENBAO_ADDR="${OPENBAO_ADDR:-http://openbao-internal.openbao:8200}"
echo ">> Using OpenBao endpoint: ${OPENBAO_ADDR}"

OPENBAO_ROLE="${OPENBAO_ROLE:-gitea-runner}"

# Obtain Kubernetes ServiceAccount JWT token
TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
if [ ! -f "${TOKEN_FILE}" ]; then
  echo "Error: Projected ServiceAccount token not found at ${TOKEN_FILE}." >&2
  echo "Ensure the runner pod mounts the projected serviceaccount token with audience 'openbao'." >&2
  exit 1
fi

K8S_JWT=$(cat "${TOKEN_FILE}")
echo ">> Loaded ServiceAccount token from ${TOKEN_FILE}"

OPENBAO_TOKEN=""
LAST_LOGIN_RESP=""

for role in "${OPENBAO_ROLE}" "gitea-runner"; do
  LOGIN_RESP=$(login_openbao_k8s "${role}" "${K8S_JWT}")
  TOKEN=$(echo "$LOGIN_RESP" | jq -r '.auth.client_token // empty' 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    OPENBAO_TOKEN="$TOKEN"
    echo ">> Successfully authenticated to OpenBao using Kubernetes Auth role '${role}'"
    break
  else
    LAST_LOGIN_RESP="${LOGIN_RESP}"
  fi
done

if [ -z "${OPENBAO_TOKEN}" ]; then
  echo "Error: OpenBao authentication failed for role '${OPENBAO_ROLE}'." >&2
  echo "Response from OpenBao: ${LAST_LOGIN_RESP}" >&2
  exit 1
fi

mask_var "${OPENBAO_TOKEN}"
output_var "openbao_token" "${OPENBAO_TOKEN}"

# Retrieve Garage Admin Tokens per Storage Tier
echo ">> Fetching Garage admin tokens from OpenBao..."

# Tier A: Synology NAS (ps02sn)
GARAGE_A_TOKEN=""
for path in "ps02sn/garage/token"; do
  RESP=$(fetch_bao_path "$path")
  T=$(echo "$RESP" | jq -r '.data.data.admin // empty' 2>/dev/null || true)
  if [ -n "$T" ]; then
    GARAGE_A_TOKEN="$T"
    echo ">> Loaded Tier A (ps02sn) admin token from OpenBao: secret/${path}"
    break
  fi
done

if [ -n "${GARAGE_A_TOKEN}" ]; then
  mask_var "${GARAGE_A_TOKEN}"
  output_var "garage_a_token" "${GARAGE_A_TOKEN}"
fi

# Tier B: Kubernetes (cl01tl)
GARAGE_B_TOKEN=""
for path in "cl01tl/garage/token"; do
  RESP=$(fetch_bao_path "$path")
  T=$(echo "$RESP" | jq -r '.data.data.admin // empty' 2>/dev/null || true)
  if [ -n "$T" ]; then
    GARAGE_B_TOKEN="$T"
    echo ">> Loaded Tier B (cl01tl) admin token from OpenBao: secret/${path}"
    break
  fi
done

if [ -n "${GARAGE_B_TOKEN}" ]; then
  mask_var "${GARAGE_B_TOKEN}"
  output_var "garage_b_token" "${GARAGE_B_TOKEN}"
fi

# Tier C: Raspberry Pi (ps10rp)
GARAGE_C_TOKEN=""
for path in "ps10rp/garage/token"; do
  RESP=$(fetch_bao_path "$path")
  T=$(echo "$RESP" | jq -r '.data.data.admin // empty' 2>/dev/null || true)
  if [ -n "$T" ]; then
    GARAGE_C_TOKEN="$T"
    echo ">> Loaded Tier C (ps10rp) admin token from OpenBao: secret/${path}"
    break
  fi
done

if [ -n "${GARAGE_C_TOKEN}" ]; then
  mask_var "${GARAGE_C_TOKEN}"
  output_var "garage_c_token" "${GARAGE_C_TOKEN}"
fi

# Retrieve Backblaze B2 Credentials
echo ">> Fetching Backblaze credentials from OpenBao..."
BACKBLAZE_KEY=""
BACKBLAZE_SECRET=""

for path in "cs01bb/s3/keys/admin"; do
  RESP=$(fetch_bao_path "$path")
  K=$(echo "$RESP" | jq -r '.data.data.AWS_ACCESS_KEY_ID // empty' 2>/dev/null || true)
  S=$(echo "$RESP" | jq -r '.data.data.AWS_SECRET_ACCESS_KEY // empty' 2>/dev/null || true)
  if [ -n "$K" ] && [ -n "$S" ]; then
    BACKBLAZE_KEY="$K"
    BACKBLAZE_SECRET="$S"
    echo ">> Loaded Backblaze credentials from OpenBao: secret/${path}"
    break
  fi
done

# Retrieve S3 / Garage Endpoints from OpenBao if available
echo ">> Checking for storage endpoints in OpenBao..."

# Tier A (ps02sn)
GARAGE_A_CFG=$(fetch_bao_path "ps02sn/garage/config")
GARAGE_A_EP=$(echo "$GARAGE_A_CFG" | jq -r '.data.data.ENDPOINT // empty' 2>/dev/null || true)

if [ -n "${GARAGE_A_EP}" ]; then
  echo ">> Loaded Tier A S3 endpoint from OpenBao: ${GARAGE_A_EP}"
  output_var "garage_a_s3_endpoint" "${GARAGE_A_EP}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_garage_a_ps02sn_s3_endpoint=${GARAGE_A_EP}" >> "${GITHUB_ENV}"
  fi
fi

# Tier B (cl01tl)
GARAGE_B_CFG=$(fetch_bao_path "cl01tl/garage/config")
GARAGE_B_EP=$(echo "$GARAGE_B_CFG" | jq -r '.data.data.ENDPOINT // empty' 2>/dev/null || true)

if [ -n "${GARAGE_B_EP}" ]; then
  echo ">> Loaded Tier B S3 endpoint from OpenBao: ${GARAGE_B_EP}"
  output_var "garage_b_s3_endpoint" "${GARAGE_B_EP}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_garage_b_cl01tl_s3_endpoint=${GARAGE_B_EP}" >> "${GITHUB_ENV}"
  fi
fi

# Tier C (ps10rp - Remote Garage)
GARAGE_C_CFG=$(fetch_bao_path "ps10rp/garage/config")
GARAGE_C_EP=$(echo "$GARAGE_C_CFG" | jq -r '.data.data.ENDPOINT // empty' 2>/dev/null || true)

if [ -n "${GARAGE_C_EP}" ]; then
  echo ">> Loaded Tier C (ps10rp) S3 endpoint from OpenBao: ${GARAGE_C_EP}"
  output_var "garage_c_s3_endpoint" "${GARAGE_C_EP}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_garage_c_ps10rp_s3_endpoint=${GARAGE_C_EP}" >> "${GITHUB_ENV}"
  fi
fi

# Tier D (cs01bb - Backblaze B2)
BACKBLAZE_CFG=$(fetch_bao_path "cs01bb/s3/config")
BACKBLAZE_EP=$(echo "$BACKBLAZE_CFG" | jq -r '.data.data.ENDPOINT // empty' 2>/dev/null || true)

if [ -n "${BACKBLAZE_EP}" ]; then
  echo ">> Loaded Tier D endpoint from OpenBao: ${BACKBLAZE_EP}"
  output_var "backblaze_endpoint" "${BACKBLAZE_EP}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_backblaze_d_cs01bb_endpoint=${BACKBLAZE_EP}" >> "${GITHUB_ENV}"
  fi
fi

# Configure imports from existing resources
configure_opentofu_imports() {
  local key="$1"
  local secret="$2"

  mkdir -p tofu/buckets
  cat <<EOF > tofu/buckets/import.tf
# ==============================================================================
# Pre-Existing Buckets
# Generated dynamically by .gitea/scripts/tofu-fetch-secrets.sh
# Note: garage_bucket does not implement the Terraform Import API.
# Existing Garage buckets are synchronized directly into state via tofu-sync-state.sh.
# ==============================================================================
EOF

  local a_token="${GARAGE_A_TOKEN:-${GARAGE_TOKEN:-}}"
  local b_token="${GARAGE_B_TOKEN:-${GARAGE_TOKEN:-}}"
  local c_token="${GARAGE_C_TOKEN:-${GARAGE_TOKEN:-}}"

  # Resolve Garage bucket IDs if any garage token is present
  if [ -n "${a_token}" ] || [ -n "${b_token}" ] || [ -n "${c_token}" ]; then
    echo ">> Resolving pre-existing Garage bucket IDs..."
    local g_a_id=""
    local g_b_id=""
    local g_c_id=""

    # Tier A: Synology NAS (ps02sn)
    local g_a_web_id=""
    local g_a_affine_id=""
    if [ -n "${a_token}" ]; then
      for ep in "http://synology.alexlebens.dev:3903/v2/GetBucketInfo?globalAlias=web-assets" \
                "http://synology.alexlebens.dev:3903/v2/GetBucketInfo?search=web-assets" \
                "http://synology.alexlebens.dev:3903/v1/bucket?alias=web-assets" \
                "http://synology.alexlebens.dev:3903/v2/ListBuckets" \
                "http://synology.alexlebens.dev:3903/v1/bucket"; do
        echo ">> Checking Synology A for bucket web-assets at ${ep}..."
        resp=$(curl -sk --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${a_token}" "${ep}" || true)
        if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
          id=$(echo "$resp" | jq -r '.[] | select((.globalAliases[]? // empty) == "web-assets" or .name == "web-assets") | .id // empty' 2>/dev/null | head -n 1 || true)
        else
          id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || true)
        fi
        if [ -n "$id" ]; then
          g_a_web_id="$id"
          echo ">> Successfully resolved Garage bucket ID for Tier A web-assets: ${g_a_web_id}"
          break
        fi
      done

      for ep in "http://synology.alexlebens.dev:3903/v2/GetBucketInfo?globalAlias=affine-assets" \
                "http://synology.alexlebens.dev:3903/v2/GetBucketInfo?search=affine-assets" \
                "http://synology.alexlebens.dev:3903/v1/bucket?alias=affine-assets" \
                "http://synology.alexlebens.dev:3903/v2/ListBuckets" \
                "http://synology.alexlebens.dev:3903/v1/bucket"; do
        echo ">> Checking Synology A for bucket affine-assets at ${ep}..."
        resp=$(curl -sk --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${a_token}" "${ep}" || true)
        if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
          id=$(echo "$resp" | jq -r '.[] | select((.globalAliases[]? // empty) == "affine-assets" or .name == "affine-assets") | .id // empty' 2>/dev/null | head -n 1 || true)
        else
          id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || true)
        fi
        if [ -n "$id" ]; then
          g_a_affine_id="$id"
          echo ">> Successfully resolved Garage bucket ID for Tier A affine-assets: ${g_a_affine_id}"
          break
        fi
      done
    fi

    # Tier B: Kubernetes Cluster (cl01tl)
    if [ -n "${b_token}" ]; then
      for ep in "http://garage-cluster-b.garage-operator.svc.cluster.local:3903/v2/GetBucketInfo?globalAlias=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator.svc.cluster.local:3903/v2/GetBucketInfo?search=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator:3903/v2/GetBucketInfo?globalAlias=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator:3903/v2/GetBucketInfo?search=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator.svc.cluster.local:3903/v1/bucket?alias=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator:3903/v1/bucket?alias=reactive-resume-assets" \
                "http://garage-cluster-b.garage-operator.svc.cluster.local:3903/v2/ListBuckets" \
                "http://garage-cluster-b.garage-operator:3903/v2/ListBuckets"; do
        echo ">> Checking Cluster B for bucket reactive-resume-assets at ${ep}..."
        resp=$(curl -sk --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${b_token}" "${ep}" || true)
        if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
          id=$(echo "$resp" | jq -r '.[] | select((.globalAliases[]? // empty) == "reactive-resume-assets" or .name == "reactive-resume-assets") | .id // empty' 2>/dev/null | head -n 1 || true)
        else
          id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || true)
        fi
        if [ -n "$id" ]; then
          g_b_id="$id"
          echo ">> Successfully resolved Garage bucket ID for Tier B reactive-resume: ${g_b_id}"
          break
        fi
      done
    fi

    # Tier C: Raspberry Pi (ps10rp)
    local g_c_web_id=""
    local g_c_affine_id=""
    if [ -n "${c_token}" ]; then
      for ep in "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/GetBucketInfo?globalAlias=web-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/GetBucketInfo?search=web-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v1/bucket?alias=web-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/ListBuckets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v1/bucket"; do
        echo ">> Checking Raspberry Pi C for bucket web-assets at ${ep}..."
        resp=$(curl -sk --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${c_token}" "${ep}" || true)
        if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
          id=$(echo "$resp" | jq -r '.[] | select((.globalAliases[]? // empty) == "web-assets" or .name == "web-assets") | .id // empty' 2>/dev/null | head -n 1 || true)
        else
          id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || true)
        fi
        if [ -n "$id" ]; then
          g_c_web_id="$id"
          echo ">> Successfully resolved Garage bucket ID for Tier C web-assets: ${g_c_web_id}"
          break
        fi
      done

      for ep in "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/GetBucketInfo?globalAlias=affine-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/GetBucketInfo?search=affine-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v1/bucket?alias=affine-assets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v2/ListBuckets" \
                "https://garage-ps10rp.boreal-beaufort.ts.net:3903/v1/bucket"; do
        echo ">> Checking Raspberry Pi C for bucket affine-assets at ${ep}..."
        resp=$(curl -sk --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${c_token}" "${ep}" || true)
        if echo "$resp" | jq -e 'type == "array"' >/dev/null 2>&1; then
          id=$(echo "$resp" | jq -r '.[] | select((.globalAliases[]? // empty) == "affine-assets" or .name == "affine-assets") | .id // empty' 2>/dev/null | head -n 1 || true)
        else
          id=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null || true)
        fi
        if [ -n "$id" ]; then
          g_c_affine_id="$id"
          echo ">> Successfully resolved Garage bucket ID for Tier C affine-assets: ${g_c_affine_id}"
          break
        fi
      done
    fi

    # Fallback to known live cluster bucket IDs if discovery timed out
    g_a_web_id="${g_a_web_id:-6a509026035a0797211b6fc07cbcf51404953ae9278fb9a414a55aceb0abf670}"
    g_b_id="${g_b_id:-23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46}"

    # Legacy variables for web-assets
    g_a_id="${g_a_web_id}"
    g_c_id="${g_c_web_id}"

    output_var "garage_a_bucket_id" "${g_a_id}"
    output_var "garage_a_web_assets_bucket_id" "${g_a_web_id}"
    output_var "garage_a_affine_assets_bucket_id" "${g_a_affine_id}"
    output_var "garage_b_bucket_id" "${g_b_id}"
    output_var "garage_c_bucket_id" "${g_c_id}"
    output_var "garage_c_web_assets_bucket_id" "${g_c_web_id}"
    output_var "garage_c_affine_assets_bucket_id" "${g_c_affine_id}"

    echo ">> Exported garage_a_bucket_id: ${g_a_id}"
    echo ">> Exported garage_a_web_assets_bucket_id: ${g_a_web_id}"
    echo ">> Exported garage_a_affine_assets_bucket_id: ${g_a_affine_id}"
    echo ">> Exported garage_b_bucket_id: ${g_b_id}"
    echo ">> Exported garage_c_bucket_id: ${g_c_id}"
    echo ">> Exported garage_c_web_assets_bucket_id: ${g_c_web_id}"
    echo ">> Exported garage_c_affine_assets_bucket_id: ${g_c_affine_id}"

    if [ -n "${GITHUB_ENV:-}" ]; then
      echo "GARAGE_A_BUCKET_ID=${g_a_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_A_WEB_ASSETS_BUCKET_ID=${g_a_web_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_A_AFFINE_ASSETS_BUCKET_ID=${g_a_affine_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_B_BUCKET_ID=${g_b_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_C_BUCKET_ID=${g_c_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_C_WEB_ASSETS_BUCKET_ID=${g_c_web_id}" >> "${GITHUB_ENV}"
      echo "GARAGE_C_AFFINE_ASSETS_BUCKET_ID=${g_c_affine_id}" >> "${GITHUB_ENV}"
    fi
  fi

  echo ">> Generated tofu/buckets/import.tf:"
  cat tofu/buckets/import.tf
}

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
  configure_opentofu_imports "${BACKBLAZE_KEY}" "${BACKBLAZE_SECRET}"
else
  echo ">> Notice: Backblaze credentials not found in OpenBao or environment"
  configure_opentofu_imports "" ""
fi

# Retrieve Garage S3 Admin Keys (for CORS/Website management)
echo ">> Fetching Garage S3 admin keys from OpenBao..."
GARAGE_ADMIN_RESP=$(fetch_bao_path "cl01tl/garage/keys/admin")
GARAGE_S3_KEY=$(echo "$GARAGE_ADMIN_RESP" | jq -r '.data.data.AWS_ACCESS_KEY_ID // empty' 2>/dev/null || true)
GARAGE_S3_SECRET=$(echo "$GARAGE_ADMIN_RESP" | jq -r '.data.data.AWS_SECRET_ACCESS_KEY // empty' 2>/dev/null || true)
if [ -n "$GARAGE_S3_KEY" ] && [ -n "$GARAGE_S3_SECRET" ]; then
  mask_var "${GARAGE_S3_KEY}"
  mask_var "${GARAGE_S3_SECRET}"
  output_var "garage_admin_access_key" "${GARAGE_S3_KEY}"
  output_var "garage_admin_secret_key" "${GARAGE_S3_SECRET}"
  echo ">> Loaded Garage S3 admin keys from OpenBao: secret/garage/home-infra/admin"
fi

# Export TF_VARs directly to GITHUB_ENV if running in GitHub/Gitea Actions
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "TF_VAR_openbao_token=${OPENBAO_TOKEN}" >> "${GITHUB_ENV}"
  if [ -n "${GARAGE_A_TOKEN}" ]; then
    echo "TF_VAR_garage_a_ps02sn_token=${GARAGE_A_TOKEN}" >> "${GITHUB_ENV}"
  elif [ -n "${GARAGE_TOKEN}" ]; then
    echo "TF_VAR_garage_a_ps02sn_token=${GARAGE_TOKEN}" >> "${GITHUB_ENV}"
  fi
  if [ -n "${GARAGE_B_TOKEN}" ]; then
    echo "TF_VAR_garage_b_cl01tl_token=${GARAGE_B_TOKEN}" >> "${GITHUB_ENV}"
  elif [ -n "${GARAGE_TOKEN}" ]; then
    echo "TF_VAR_garage_b_cl01tl_token=${GARAGE_TOKEN}" >> "${GITHUB_ENV}"
  fi
  if [ -n "${GARAGE_C_TOKEN}" ]; then
    echo "TF_VAR_garage_c_ps10rp_token=${GARAGE_C_TOKEN}" >> "${GITHUB_ENV}"
  elif [ -n "${GARAGE_TOKEN}" ]; then
    echo "TF_VAR_garage_c_ps10rp_token=${GARAGE_TOKEN}" >> "${GITHUB_ENV}"
  fi
  if [ -n "${BACKBLAZE_KEY}" ]; then
    echo "TF_VAR_backblaze_d_cs01bb_access_key_id=${BACKBLAZE_KEY}" >> "${GITHUB_ENV}"
    echo "TF_VAR_backblaze_d_cs01bb_secret_access_key=${BACKBLAZE_SECRET}" >> "${GITHUB_ENV}"
    echo "B2_APPLICATION_KEY_ID=${BACKBLAZE_KEY}" >> "${GITHUB_ENV}"
    echo "B2_APPLICATION_KEY=${BACKBLAZE_SECRET}" >> "${GITHUB_ENV}"
  fi
  if [ -n "${GARAGE_S3_KEY}" ]; then
    echo "TF_VAR_garage_a_ps02sn_admin_access_key=${GARAGE_S3_KEY}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_a_ps02sn_admin_secret_key=${GARAGE_S3_SECRET}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_b_cl01tl_admin_access_key=${GARAGE_S3_KEY}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_b_cl01tl_admin_secret_key=${GARAGE_S3_SECRET}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_c_ps10rp_admin_access_key=${GARAGE_S3_KEY}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_c_ps10rp_admin_secret_key=${GARAGE_S3_SECRET}" >> "${GITHUB_ENV}"
  fi
fi

echo ">> OpenBao secret extraction complete."
