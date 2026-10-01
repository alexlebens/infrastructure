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

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
else
  echo ">> Notice: Backblaze credentials not found in OpenBao or environment"
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

# Retrieve VolSync Restic Passwords per Storage Tier
echo ">> Fetching VolSync Restic passwords from OpenBao..."

# Tier A: Synology NAS (ps02sn)
VOLSYNC_RESTIC_A=""
for path in "ps02sn/garage/keys/volsync-backups" "garage/home-infra/volsync-backups"; do
  RESP=$(fetch_bao_path "$path")
  P=$(echo "$RESP" | jq -r '.data.data.RESTIC_PASSWORD // .data.data.RESTIC_PASSWORD_LOCAL // empty' 2>/dev/null || true)
  if [ -n "$P" ]; then
    VOLSYNC_RESTIC_A="$P"
    echo ">> Loaded Tier A VolSync Restic password from OpenBao: secret/${path}"
    break
  fi
done
if [ -n "${VOLSYNC_RESTIC_A}" ]; then
  mask_var "${VOLSYNC_RESTIC_A}"
  output_var "volsync_restic_password_a_ps02sn" "${VOLSYNC_RESTIC_A}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_volsync_restic_password_a_ps02sn=${VOLSYNC_RESTIC_A}" >> "${GITHUB_ENV}"
  fi
fi

# Tier B: Talos Cluster (cl01tl)
VOLSYNC_RESTIC_B=""
for path in "cl01tl/garage/keys/volsync-backups" "garage/home-infra/volsync-backups"; do
  RESP=$(fetch_bao_path "$path")
  P=$(echo "$RESP" | jq -r '.data.data.RESTIC_PASSWORD // .data.data.RESTIC_PASSWORD_LOCAL // empty' 2>/dev/null || true)
  if [ -n "$P" ]; then
    VOLSYNC_RESTIC_B="$P"
    echo ">> Loaded Tier B VolSync Restic password from OpenBao: secret/${path}"
    break
  fi
done
if [ -n "${VOLSYNC_RESTIC_B}" ]; then
  mask_var "${VOLSYNC_RESTIC_B}"
  output_var "volsync_restic_password_b_cl01tl" "${VOLSYNC_RESTIC_B}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_volsync_restic_password_b_cl01tl=${VOLSYNC_RESTIC_B}" >> "${GITHUB_ENV}"
  fi
fi

# Tier C: Raspberry Pi (ps10rp)
VOLSYNC_RESTIC_C=""
for path in "ps10rp/garage/keys/volsync-backups" "garage/home-infra/volsync-backups"; do
  RESP=$(fetch_bao_path "$path")
  P=$(echo "$RESP" | jq -r '.data.data.RESTIC_PASSWORD // .data.data.RESTIC_PASSWORD_REMOTE // empty' 2>/dev/null || true)
  if [ -n "$P" ]; then
    VOLSYNC_RESTIC_C="$P"
    echo ">> Loaded Tier C VolSync Restic password from OpenBao: secret/${path}"
    break
  fi
done
if [ -n "${VOLSYNC_RESTIC_C}" ]; then
  mask_var "${VOLSYNC_RESTIC_C}"
  output_var "volsync_restic_password_c_ps10rp" "${VOLSYNC_RESTIC_C}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_volsync_restic_password_c_ps10rp=${VOLSYNC_RESTIC_C}" >> "${GITHUB_ENV}"
  fi
fi

# Tier D: Backblaze B2 (cs01bb)
VOLSYNC_RESTIC_D=""
for path in "cs01bb/s3/keys/volsync-backups" "backblaze/home-infra/volsync-backups"; do
  RESP=$(fetch_bao_path "$path")
  P=$(echo "$RESP" | jq -r '.data.data.RESTIC_PASSWORD // empty' 2>/dev/null || true)
  if [ -n "$P" ]; then
    VOLSYNC_RESTIC_D="$P"
    echo ">> Loaded Tier D VolSync Restic password from OpenBao: secret/${path}"
    break
  fi
done
if [ -n "${VOLSYNC_RESTIC_D}" ]; then
  mask_var "${VOLSYNC_RESTIC_D}"
  output_var "volsync_restic_password_d_cs01bb" "${VOLSYNC_RESTIC_D}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TF_VAR_volsync_restic_password_d_cs01bb=${VOLSYNC_RESTIC_D}" >> "${GITHUB_ENV}"
  fi
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
