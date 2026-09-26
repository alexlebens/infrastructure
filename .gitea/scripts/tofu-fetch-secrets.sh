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

echo ">> Authenticating to OpenBao using Kubernetes Auth (role: gitea-runner)..."

OPENBAO_ADDR="${OPENBAO_ADDR:-https://openbao.alexlebens.dev}"
OPENBAO_ROLE="${OPENBAO_ROLE:-gitea-runner}"

# Obtain Kubernetes ServiceAccount JWT token
K8S_JWT=""
if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
  K8S_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  echo ">> Loaded projected ServiceAccount token from /var/run/secrets/kubernetes.io/serviceaccount/token"
fi

if [ -z "${K8S_JWT}" ]; then
  for sa in "buildx-runner" "gitea-runner" "default"; do
    K8S_JWT=$(kubectl create token "$sa" -n gitea --audience=openbao 2>/dev/null || true)
    if [ -n "${K8S_JWT}" ]; then
      echo ">> Generated Kubernetes projected token for serviceaccount: gitea/${sa}"
      break
    fi
  done
fi

if [ -z "${K8S_JWT}" ]; then
  echo "Error: Failed to obtain Kubernetes ServiceAccount token for OpenBao authentication." >&2
  exit 1
fi

# Login to OpenBao via Kubernetes Auth
login_openbao_k8s() {
  local role="$1"
  local jwt="$2"
  local res
  res=$(curl -sk -X POST \
    -H "Content-Type: application/json" \
    -d "{\"role\": \"${role}\", \"jwt\": \"${jwt}\"}" \
    "${OPENBAO_ADDR}/v1/auth/kubernetes/login" 2>/dev/null || true)
  if [ -z "$res" ] || [ "$(echo "$res" | jq -r '.auth.client_token // empty' 2>/dev/null)" = "" ]; then
    res=$(curl -sk -X POST \
      -H "Content-Type: application/json" \
      -d "{\"role\": \"${role}\", \"jwt\": \"${jwt}\"}" \
      "http://openbao-internal.openbao:8200/v1/auth/kubernetes/login" 2>/dev/null || true)
  fi
  echo "$res"
}

LOGIN_RESP=$(login_openbao_k8s "${OPENBAO_ROLE}" "${K8S_JWT}")
OPENBAO_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.auth.client_token // empty' 2>/dev/null || true)

if [ -z "${OPENBAO_TOKEN}" ]; then
  echo "Error: OpenBao Kubernetes authentication failed for role '${OPENBAO_ROLE}'." >&2
  echo "Response: ${LOGIN_RESP}" >&2
  exit 1
fi

mask_var "${OPENBAO_TOKEN}"
output_var "openbao_token" "${OPENBAO_TOKEN}"
echo ">> Successfully authenticated to OpenBao using Kubernetes Auth role '${OPENBAO_ROLE}'"

# Helper to fetch a JSON payload from OpenBao KV v2 (mount: secret)
fetch_bao_path() {
  local path="$1"
  local res
  res=$(curl -sk -H "X-Vault-Token: ${OPENBAO_TOKEN}" "${OPENBAO_ADDR}/v1/secret/data/${path}" 2>/dev/null || true)
  if [ -z "$res" ] || [ "$(echo "$res" | jq -r '.data.data // empty' 2>/dev/null)" = "" ]; then
    res=$(curl -sk -H "X-Vault-Token: ${OPENBAO_TOKEN}" "http://openbao-internal.openbao:8200/v1/secret/data/${path}" 2>/dev/null || true)
  fi
  echo "$res"
}

# Retrieve Garage Admin Token
echo ">> Fetching Garage token from OpenBao..."
GARAGE_TOKEN=""
for path in "cl01tl/garage-operator/config" "garage/config" "garage/home-infra/admin"; do
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

# Retrieve Backblaze B2 Credentials
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

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
else
  echo ">> Notice: Backblaze credentials not found in OpenBao (falling back to workflow secret if defined)"
fi

# Retrieve Garage S3 Admin Keys (for CORS/Website management)
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
