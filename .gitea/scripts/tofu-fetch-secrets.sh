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

echo ">> Extracting OpenTofu secrets from cluster..."

# 1. Garage Admin Token
GARAGE_TOKEN=$(kubectl get secret -n garage-operator garage-operator-token -o jsonpath='{.data.admin-token}' 2>/dev/null | base64 -d || true)
if [ -z "${GARAGE_TOKEN}" ]; then
  GARAGE_TOKEN=$(kubectl get secret -n garage-operator garage-operator -o jsonpath='{.data.adminToken}' 2>/dev/null | base64 -d || true)
fi
if [ -n "${GARAGE_TOKEN}" ]; then
  mask_var "${GARAGE_TOKEN}"
  output_var "garage_token" "${GARAGE_TOKEN}"
  echo ">> Found Garage admin token"
else
  echo ">> Warning: Garage admin token not found in garage-operator secret"
fi

# 2. OpenBao Root / Service Token
OPENBAO_TOKEN=$(kubectl get secret -n external-secrets openbao-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
if [ -z "${OPENBAO_TOKEN}" ]; then
  OPENBAO_TOKEN=$(kubectl get secret -n openbao openbao-unseal-keys -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || true)
fi
if [ -n "${OPENBAO_TOKEN}" ]; then
  mask_var "${OPENBAO_TOKEN}"
  output_var "openbao_token" "${OPENBAO_TOKEN}"
  echo ">> Found OpenBao token"
else
  echo ">> Warning: OpenBao token not found"
fi

# 3. Backblaze B2 Credentials
BACKBLAZE_KEY=""
BACKBLAZE_SECRET=""

# Search active in-cluster backup secrets across namespaces
for candidate in \
  "talos talos-etcd-backup-external-config" \
  "pigallery2 pigallery2-mariadb-cluster-backup-secret-external" \
  "grimmory grimmory-mariadb-cluster-backup-secret-external" \
  "s3-exporter backblaze"; do
  read -r NS NAME <<< "$candidate"
  K=$(kubectl get secret -n "$NS" "$NAME" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d || true)
  [ -z "$K" ] && K=$(kubectl get secret -n "$NS" "$NAME" -o jsonpath='{.data.access}' 2>/dev/null | base64 -d || true)
  S=$(kubectl get secret -n "$NS" "$NAME" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d || true)
  [ -z "$S" ] && S=$(kubectl get secret -n "$NS" "$NAME" -o jsonpath='{.data.secret}' 2>/dev/null | base64 -d || true)
  if [ -n "$K" ] && [ -n "$S" ]; then
    BACKBLAZE_KEY="$K"
    BACKBLAZE_SECRET="$S"
    echo ">> Loaded Backblaze credentials from cluster secret: ${NS}/${NAME}"
    break
  fi
done

# Fallback to querying OpenBao directly if token is available
if [ -z "$BACKBLAZE_KEY" ] && [ -n "$OPENBAO_TOKEN" ]; then
  for path in "backblaze/home-infra/talos-backups" "backblaze/home-infra/s3-exporter" "backblaze/home-infra/mariadb-backups"; do
    RESP=$(curl -sk -H "X-Vault-Token: $OPENBAO_TOKEN" "https://openbao.alexlebens.dev/v1/secret/data/$path" 2>/dev/null || true)
    K=$(echo "$RESP" | jq -r '.data.data.AWS_ACCESS_KEY_ID // .data.data.ACCESS_KEY_ID // empty' 2>/dev/null || true)
    S=$(echo "$RESP" | jq -r '.data.data.AWS_SECRET_ACCESS_KEY // .data.data.ACCESS_SECRET_KEY // empty' 2>/dev/null || true)
    if [ -n "$K" ] && [ -n "$S" ]; then
      BACKBLAZE_KEY="$K"
      BACKBLAZE_SECRET="$S"
      echo ">> Loaded Backblaze credentials from OpenBao: ${path}"
      break
    fi
  done
fi

if [ -n "$BACKBLAZE_KEY" ]; then
  mask_var "${BACKBLAZE_KEY}"
  mask_var "${BACKBLAZE_SECRET}"
  output_var "backblaze_access_key_id" "${BACKBLAZE_KEY}"
  output_var "backblaze_secret_access_key" "${BACKBLAZE_SECRET}"
  echo ">> Found Backblaze B2 credentials"
else
  echo ">> Notice: Backblaze credentials not found in cluster or OpenBao (falling back to workflow secret if defined)"
fi
