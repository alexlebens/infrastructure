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

for path in "backblaze/home-infra/s3-exporter" "backblaze/home-infra/talos-backups" "backblaze/home-infra/mariadb-backups" "backblaze/config"; do
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

ensure_backblaze_cors() {
  local key="$1"
  local secret="$2"
  if [ -z "$key" ] || [ -z "$secret" ]; then
    return 0
  fi

  echo ">> Checking Backblaze B2 bucket CORS configurations..."
  local auth_resp
  auth_resp=$(curl -sk --connect-timeout 4 --max-time 8 -u "${key}:${secret}" "https://api.backblazeb2.com/b2api/v3/b2_authorize_account" 2>/dev/null || true)
  local token api_url account_id
  token=$(echo "$auth_resp" | jq -r '.authorizationToken // empty' 2>/dev/null || true)
  api_url=$(echo "$auth_resp" | jq -r '.apiUrl // empty' 2>/dev/null || true)
  account_id=$(echo "$auth_resp" | jq -r '.accountId // empty' 2>/dev/null || true)

  if [ -z "$token" ] || [ -z "$api_url" ] || [ -z "$account_id" ]; then
    echo ">> Notice: Unable to authorize with Backblaze B2 Native API to verify CORS."
    return 0
  fi

  local buckets_resp
  buckets_resp=$(curl -sk --connect-timeout 4 --max-time 8 -H "Authorization: ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"accountId\": \"${account_id}\"}" \
    "${api_url}/b2api/v3/b2_list_buckets" 2>/dev/null || true)

  for target_bucket in "web-assets-770aef58c931fcf4" "reactive-resume-assets-61758b59b4c7c893"; do
    local b_info
    b_info=$(echo "$buckets_resp" | jq -r --arg name "$target_bucket" '.buckets[] | select(.bucketName == $name) // empty' 2>/dev/null || true)
    if [ -n "$b_info" ]; then
      local b_id cors_count
      b_id=$(echo "$b_info" | jq -r '.bucketId' 2>/dev/null || true)
      cors_count=$(echo "$b_info" | jq -r '.corsRules | length' 2>/dev/null || 0)
      if [ "$cors_count" -eq 0 ]; then
        echo ">> Initializing default CORS rule on Backblaze B2 bucket: ${target_bucket}..."
        local update_payload
        update_payload=$(jq -n \
          --arg acct "$account_id" \
          --arg bid "$b_id" \
          '{accountId: $acct, bucketId: $bid, corsRules: [{corsRuleName: "s3-cors-default", allowedOrigins: ["*"], allowedOperations: ["s3_get", "s3_head"], maxAgeSeconds: 3600}]}')
        local update_resp
        update_resp=$(curl -sk --connect-timeout 4 --max-time 8 -H "Authorization: ${token}" \
          -H "Content-Type: application/json" \
          -d "$update_payload" \
          "${api_url}/b2api/v3/b2_update_bucket" 2>/dev/null || true)
        if [ "$(echo "$update_resp" | jq -r '.bucketId // empty' 2>/dev/null)" = "$b_id" ]; then
          echo ">> Successfully initialized CORS rule on Backblaze B2 bucket: ${target_bucket}"
        else
          echo ">> Notice: Failed to update CORS on ${target_bucket}: ${update_resp}"
        fi
      else
        echo ">> Backblaze B2 bucket ${target_bucket} already has CORS rules configured."
      fi
    fi
  done
}

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
  ensure_backblaze_cors "${BACKBLAZE_KEY}" "${BACKBLAZE_SECRET}"
else
  echo ">> Notice: Backblaze credentials not found in OpenBao (falling back to workflow secret if defined)"
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
