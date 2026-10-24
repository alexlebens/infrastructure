#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-}"
SSH_USER="${SSH_USER:-alex}"
SSH_PORT="${SSH_PORT:-22}"
SERVICE_PATH="${SERVICE_PATH:-}"
REPO_DIR="${REPO_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --service-path)
      SERVICE_PATH="$2"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="$2"
      shift 2
      ;;
    --user)
      SSH_USER="$2"
      shift 2
      ;;
    --port)
      SSH_PORT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --host <target_host> --service-path <path> [--repo-dir <dir>] [--user <user>] [--port <port>]"
      echo "Deploys/updates a Docker Compose stack on a remote host via SSH."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${TARGET_HOST}" ]]; then
  echo "Error: --host (or TARGET_HOST) is required." >&2
  exit 1
fi

if [[ -z "${SERVICE_PATH}" ]]; then
  echo "Error: --service-path (or SERVICE_PATH) is required." >&2
  exit 1
fi

echo ">> Connecting to ${SSH_USER}@${TARGET_HOST}:${SSH_PORT} to deploy ${SERVICE_PATH}..."

ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -p "${SSH_PORT}" "${SSH_USER}@${TARGET_HOST}" bash -s -- "${SERVICE_PATH}" "${REPO_DIR}" << 'EOF'
  set -euo pipefail
  SERVICE_PATH="$1"
  CUSTOM_REPO_DIR="$2"

  CANDIDATE_DIRS=("${CUSTOM_REPO_DIR}" "/mnt/data/infrastructure" "/opt/compose/infrastructure" "${HOME}/infrastructure")
  TARGET_DIR=""

  for dir in "${CANDIDATE_DIRS[@]}"; do
    if [[ -n "${dir}" && -d "${dir}" ]]; then
      TARGET_DIR="${dir}"
      break
    fi
  done

  if [[ -z "${TARGET_DIR}" ]]; then
    echo "::error::Target infrastructure repository directory not found on host!" >&2
    exit 1
  fi

  echo ">> Pulling latest changes in ${TARGET_DIR}..."
  cd "${TARGET_DIR}"
  git pull

  echo ">> Navigating to ${SERVICE_PATH} in ${TARGET_DIR}..."
  if [[ ! -d "${SERVICE_PATH}" ]]; then
    echo "::error::Directory ${SERVICE_PATH} does not exist under ${TARGET_DIR}!" >&2
    exit 1
  fi
  cd "${SERVICE_PATH}"

  echo ">> Pulling latest images..."
  docker compose pull || true

  echo ">> Recreating containers..."
  docker compose down
  docker compose up -d

  echo ">> Waiting for containers to initialize..."
  sleep 5

  echo ">> Verifying container status..."
  docker compose ps

  failed_containers=$(docker compose ps --filter "status=restarting" --filter "status=exited" --filter "status=dead" -q)
  if [[ -n "${failed_containers}" ]]; then
    echo "::error::One or more containers failed to start or crashed!" >&2
    docker compose logs --tail=25
    exit 1
  fi

  echo ">> Recent container logs:"
  docker compose logs --tail=8
EOF

echo ">> Successfully deployed ${SERVICE_PATH} on ${TARGET_HOST}!"
