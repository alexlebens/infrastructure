#!/usr/bin/env bash
# Remote Docker Compose deployment script streamed over SSH by host:deploy-compose.
set -euo pipefail

if [[ -z "${KEEP_PATH:-}" ]]; then
  export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:${PATH:-}"
fi

SERVICE_PATH="${1:?SERVICE_PATH argument is required}"
TARGET_DIR="${2:?TARGET_DIR argument is required}"

INITIAL_SLEEP="${INITIAL_SLEEP:-10}"
POLL_SLEEP="${POLL_SLEEP:-5}"
MAX_WAIT="${MAX_WAIT:-300}"
POST_UP_SLEEP="${POST_UP_SLEEP:-5}"

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "::error::Target repository directory '${TARGET_DIR}' not found on host!" >&2
  exit 1
fi

echo ">> Waiting for any in-flight Komodo docker compose operations to finish..."
sleep "${INITIAL_SLEEP}"
idle_checks=0
elapsed=0
while [[ "${idle_checks}" -lt 2 ]]; do
  if pgrep -f "docker[ -]compose" >/dev/null 2>&1; then
    idle_checks=0
    if [[ "${elapsed}" -ge "${MAX_WAIT}" ]]; then
      echo "::warning::Timed out after ${MAX_WAIT}s waiting for docker compose operations; proceeding with deploy..."
      break
    fi
    echo "   Active docker compose process detected; waiting ${POLL_SLEEP}s (${elapsed}s/${MAX_WAIT}s)..."
    sleep "${POLL_SLEEP}"
    elapsed=$((elapsed + POLL_SLEEP))
  else
    idle_checks=$((idle_checks + 1))
    if [[ "${idle_checks}" -lt 2 ]]; then
      sleep "${POLL_SLEEP}"
      elapsed=$((elapsed + POLL_SLEEP))
    fi
  fi
done

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
sleep "${POST_UP_SLEEP}"

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
