#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-}"
SSH_USER="${SSH_USER:-alex}"
SSH_PORT="${SSH_PORT:-22}"
CORE_ADDRESS="${CORE_ADDRESS:-https://komodo.alexlebens.dev}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      TARGET_HOST="$2"
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
    --core-address)
      CORE_ADDRESS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --host <target_host> [--user <ssh_user>] [--port <ssh_port>] [--core-address <url>]"
      echo "Updates Komodo Periphery on systemd-managed hosts via SSH."
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

echo ">> Connecting to ${SSH_USER}@${TARGET_HOST}:${SSH_PORT} for Systemd Periphery update..."

ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -p "${SSH_PORT}" "${SSH_USER}@${TARGET_HOST}" bash -s -- "${CORE_ADDRESS}" << 'EOF'
  set -euo pipefail
  CORE_ADDRESS="$1"

  echo ">> Waiting for any in-flight Komodo docker compose operations to finish..."
  sleep 10
  idle_checks=0
  elapsed=0
  max_wait=300
  while [[ "${idle_checks}" -lt 2 ]]; do
    if pgrep -f "docker[ -]compose" >/dev/null 2>&1; then
      idle_checks=0
      if [[ "${elapsed}" -ge "${max_wait}" ]]; then
        echo "::warning::Timed out after ${max_wait}s waiting for docker compose operations; proceeding with update..."
        break
      fi
      echo "   Active docker compose process detected; waiting 5s (${elapsed}s/${max_wait}s)..."
      sleep 5
      elapsed=$((elapsed + 5))
    else
      idle_checks=$((idle_checks + 1))
      if [[ "${idle_checks}" -lt 2 ]]; then
        sleep 5
        elapsed=$((elapsed + 5))
      fi
    fi
  done

  echo ">> Running Komodo Periphery setup/update script with sudo..."
  curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py \
    | sudo -n python3 - --core-address="${CORE_ADDRESS}"

  echo ">> Waiting for Periphery agent to initialize..."
  sleep 3

  echo ">> Verifying systemd service status..."
  sudo -n systemctl is-active periphery.service

  echo ">> Installed binary version:"
  /usr/local/bin/periphery --version || periphery --version || true

  echo ">> Recent service journal logs:"
  sudo -n journalctl -u periphery -n 6 --no-pager
EOF

echo ">> Successfully updated Komodo Periphery on ${TARGET_HOST}!"
