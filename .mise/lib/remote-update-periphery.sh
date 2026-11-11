#!/usr/bin/env bash
# Remote Komodo Periphery systemd update script streamed over SSH by host:update-periphery.
set -euo pipefail

CORE_ADDRESS="${1:?CORE_ADDRESS argument is required}"

INITIAL_SLEEP="${INITIAL_SLEEP:-10}"
POLL_SLEEP="${POLL_SLEEP:-5}"
MAX_WAIT="${MAX_WAIT:-300}"
POST_INSTALL_SLEEP="${POST_INSTALL_SLEEP:-3}"

echo ">> Waiting for any in-flight Komodo docker compose operations to finish..."
sleep "${INITIAL_SLEEP}"
idle_checks=0
elapsed=0
while [[ "${idle_checks}" -lt 2 ]]; do
  if pgrep -f "docker[ -]compose" >/dev/null 2>&1; then
    idle_checks=0
    if [[ "${elapsed}" -ge "${MAX_WAIT}" ]]; then
      echo "::warning::Timed out after ${MAX_WAIT}s waiting for docker compose operations; proceeding with update..."
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

echo ">> Configuring systemd drop-in override (KillMode=process)..."
sudo -n mkdir -p /etc/systemd/system/periphery.service.d
printf "[Service]\nKillMode=process\n" | sudo -n tee /etc/systemd/system/periphery.service.d/override.conf >/dev/null
sudo -n systemctl daemon-reload

echo ">> Running Komodo Periphery setup/update script with sudo..."
curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/setup-periphery.py \
  | sudo -n python3 - --core-address="${CORE_ADDRESS}"

echo ">> Waiting for Periphery agent to initialize..."
sleep "${POST_INSTALL_SLEEP}"

echo ">> Verifying systemd service status..."
sudo -n systemctl is-active periphery.service

echo ">> Installed binary version:"
/usr/local/bin/periphery --version || periphery --version || true

echo ">> Recent service journal logs:"
sudo -n journalctl -u periphery -n 6 --no-pager
