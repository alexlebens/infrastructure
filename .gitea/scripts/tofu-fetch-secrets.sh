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
K8S_JWT=""
if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
  K8S_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  echo ">> Loaded projected ServiceAccount token from /var/run/secrets/kubernetes.io/serviceaccount/token"
fi

# Fallback: obtain token via kubectl if not mounted
if [ -z "${K8S_JWT}" ]; then
  if command -v kubectl >/dev/null 2>&1; then
    echo ">> Requesting projected token for buildx-runner via kubectl..."
    K8S_JWT=$(kubectl create token buildx-runner -n gitea --audience=openbao --request-timeout=3s 2>/dev/null || true)
    if [ -n "${K8S_JWT}" ]; then
      echo ">> Generated Kubernetes projected token for serviceaccount: gitea/buildx-runner"
    fi

    # Fallback to static ServiceAccount secret if projected token creation failed
    if [ -z "${K8S_JWT}" ]; then
      K8S_JWT=$(kubectl get secret -n gitea buildx-runner-token --request-timeout=3s -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
      if [ -n "${K8S_JWT}" ]; then
        echo ">> Loaded ServiceAccount token from secret: gitea/buildx-runner-token"
      fi
    fi
  else
    echo ">> Notice: kubectl is not available in environment"
  fi
fi

OPENBAO_TOKEN=""

if [ -n "${K8S_JWT}" ]; then
  LAST_LOGIN_RESP=""
  for role in "${OPENBAO_ROLE}" "buildx-runner" "external-secrets"; do
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
  if [ -z "${OPENBAO_TOKEN}" ] && [ -n "${LAST_LOGIN_RESP}" ]; then
    echo ">> Notice: Kubernetes auth login attempt failed. Response: ${LAST_LOGIN_RESP}"
  fi
fi

# Fallback: If Kubernetes Auth didn't succeed, retrieve token via kubectl from cluster secrets
if [ -z "${OPENBAO_TOKEN}" ] && command -v kubectl >/dev/null 2>&1; then
  echo ">> Falling back to in-cluster secret via kubectl..."
  OPENBAO_TOKEN=$(kubectl get secret -n external-secrets openbao-token --request-timeout=3s -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  if [ -z "${OPENBAO_TOKEN}" ]; then
    OPENBAO_TOKEN=$(kubectl get secret -n openbao openbao-unseal-keys --request-timeout=3s -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || true)
  fi
  if [ -n "${OPENBAO_TOKEN}" ]; then
    echo ">> Retrieved fallback token from in-cluster secret"
  fi
fi

if [ -z "${OPENBAO_TOKEN}" ]; then
  echo "Error: OpenBao authentication failed. Unable to authenticate via Kubernetes Auth or cluster fallback." >&2
  exit 1
fi

mask_var "${OPENBAO_TOKEN}"
output_var "openbao_token" "${OPENBAO_TOKEN}"

# Retrieve Garage Admin Token (primary: cl01tl/garage-operator/config)
echo ">> Fetching Garage token from OpenBao..."
GARAGE_TOKEN=""
for path in "cl01tl/garage-operator/config" "garage/home-infra/admin" "garage/config"; do
  RESP=$(fetch_bao_path "$path")
  TOKEN=$(echo "$RESP" | jq -r '.data.data["admin-token"] // .data.data.admin_token // .data.data.token // empty' 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    GARAGE_TOKEN="$TOKEN"
    echo ">> Loaded Garage admin token from OpenBao: secret/${path}"
    break
  fi
done

if [ -n "${GARAGE_TOKEN}" ]; then
  mask_var "${GARAGE_TOKEN}"
  output_var "garage_token" "${GARAGE_TOKEN}"
else
  echo ">> Warning: Garage admin token not found in OpenBao"
fi

# Retrieve Backblaze B2 Credentials (primary: backblaze/home-infra/s3-exporter)
echo ">> Fetching Backblaze credentials from OpenBao..."
BACKBLAZE_KEY=""
BACKBLAZE_SECRET=""

for path in "backblaze/home-infra/master" "backblaze/master" "backblaze/home-infra/s3-exporter" "backblaze/home-infra/talos-backups" "backblaze/home-infra/mariadb-backups" "backblaze/config"; do
  RESP=$(fetch_bao_path "$path")
  K=$(echo "$RESP" | jq -r '.data.data.ACCESS_KEY_ID // .data.data.AWS_ACCESS_KEY_ID // empty' 2>/dev/null || true)
  S=$(echo "$RESP" | jq -r '.data.data.ACCESS_SECRET_KEY // .data.data.AWS_SECRET_ACCESS_KEY // empty' 2>/dev/null || true)
  if [ -n "$K" ] && [ -n "$S" ]; then
    BACKBLAZE_KEY="$K"
    BACKBLAZE_SECRET="$S"
    echo ">> Loaded Backblaze credentials from OpenBao: secret/${path}"
    break
  fi
done

configure_opentofu_imports() {
  local key="$1"
  local secret="$2"

  mkdir -p tofu/buckets
  cat <<EOF > tofu/buckets/import.tf
# ==============================================================================
# Pre-Existing Buckets
# Generated dynamically by .gitea/scripts/tofu-fetch-secrets.sh
# ==============================================================================
EOF

  # Resolve Garage bucket IDs if garage token is present
  if [ -n "${GARAGE_TOKEN:-}" ]; then
    echo ">> Resolving pre-existing Garage bucket IDs..."
    local g_a_resp g_b_resp g_a_id g_b_id
    g_a_resp=$(curl -sk --connect-timeout 2 --max-time 4 -H "Authorization: Bearer ${GARAGE_TOKEN}" "http://synology.alexlebens.dev:3903/v1/bucket?alias=web-assets" 2>/dev/null || true)
    g_a_id=$(echo "$g_a_resp" | jq -r '.id // empty' 2>/dev/null || true)

    g_b_resp=$(curl -sk --connect-timeout 2 --max-time 4 -H "Authorization: Bearer ${GARAGE_TOKEN}" "http://garage-cluster-b.garage-operator:3903/v1/bucket?alias=reactive-resume-assets" 2>/dev/null || true)
    g_b_id=$(echo "$g_b_resp" | jq -r '.id // empty' 2>/dev/null || true)

    if [ -n "$g_a_id" ]; then
      cat <<EOF >> tofu/buckets/import.tf
import {
  to = garage_bucket.a_ps02sn["web-assets"]
  id = "${g_a_id}"
}
EOF
      echo ">> Resolved Garage bucket ID for web-assets: ${g_a_id}"
    fi

    if [ -n "$g_b_id" ]; then
      cat <<EOF >> tofu/buckets/import.tf
import {
  to = garage_bucket.b_cl01tl["reactive-resume"]
  id = "${g_b_id}"
}
EOF
      echo ">> Resolved Garage bucket ID for reactive-resume: ${g_b_id}"
    fi
  fi

  # Resolve Backblaze B2 bucket IDs
  if [ -n "$key" ] && [ -n "$secret" ]; then
    echo ">> Resolving Backblaze B2 bucket IDs for OpenTofu..."
    local auth_resp token api_url account_id
    auth_resp=$(curl -sk --connect-timeout 4 --max-time 8 -u "${key}:${secret}" "https://api.backblazeb2.com/b2api/v3/b2_authorize_account" 2>/dev/null || true)
    token=$(echo "$auth_resp" | jq -r '.authorizationToken // empty' 2>/dev/null || true)
    api_url=$(echo "$auth_resp" | jq -r '.apiUrl // empty' 2>/dev/null || true)
    account_id=$(echo "$auth_resp" | jq -r '.accountId // empty' 2>/dev/null || true)

    if [ -n "$token" ] && [ -n "$api_url" ] && [ -n "$account_id" ]; then
      local buckets_resp web_id resume_id
      buckets_resp=$(curl -sk --connect-timeout 4 --max-time 8 -H "Authorization: ${token}" \
        -H "Content-Type: application/json" \
        -d "{\"accountId\": \"${account_id}\"}" \
        "${api_url}/b2api/v3/b2_list_buckets" 2>/dev/null || true)

      web_id=$(echo "$buckets_resp" | jq -r '.buckets[] | select(.bucketName == "web-assets-770aef58c931fcf4") | .bucketId // empty' 2>/dev/null || true)
      resume_id=$(echo "$buckets_resp" | jq -r '.buckets[] | select(.bucketName == "reactive-resume-assets-61758b59b4c7c893") | .bucketId // empty' 2>/dev/null || true)

      if [ -n "$web_id" ]; then
        cat <<EOF >> tofu/buckets/import.tf
import {
  to = b2_bucket.d_cs01bb["web-assets"]
  id = "${web_id}"
}
EOF
        echo ">> Resolved Backblaze bucket ID for web-assets: ${web_id}"
      fi
      if [ -n "$resume_id" ]; then
        cat <<EOF >> tofu/buckets/import.tf
import {
  to = b2_bucket.d_cs01bb["reactive-resume"]
  id = "${resume_id}"
}
EOF
        echo ">> Resolved Backblaze bucket ID for reactive-resume: ${resume_id}"
      fi
    else
      echo ">> Notice: Unable to authorize with Backblaze B2 Native API to resolve bucket IDs."
    fi
  fi
}

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
  configure_opentofu_imports "${BACKBLAZE_KEY}" "${BACKBLAZE_SECRET}"
else
  echo ">> Notice: Backblaze credentials not found in OpenBao (falling back to workflow secret if defined)"
  configure_opentofu_imports "" ""
fi

# Retrieve Garage S3 Admin Keys (for CORS/Website management)
echo ">> Fetching Garage S3 admin keys from OpenBao..."
GARAGE_ADMIN_RESP=$(fetch_bao_path "garage/home-infra/admin")
GARAGE_S3_KEY=$(echo "$GARAGE_ADMIN_RESP" | jq -r '.data.data.ACCESS_KEY_ID // empty' 2>/dev/null || true)
GARAGE_S3_SECRET=$(echo "$GARAGE_ADMIN_RESP" | jq -r '.data.data.ACCESS_SECRET_KEY // empty' 2>/dev/null || true)
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
  if [ -n "${GARAGE_TOKEN}" ]; then
    echo "TF_VAR_garage_a_ps02sn_token=${GARAGE_TOKEN}" >> "${GITHUB_ENV}"
    echo "TF_VAR_garage_b_cl01tl_token=${GARAGE_TOKEN}" >> "${GITHUB_ENV}"
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
