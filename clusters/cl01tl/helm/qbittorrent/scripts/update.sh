#!/bin/sh
set -eu

PORT="${1:-}"
API_ENDPOINT="${API_ENDPOINT:-http://localhost:8080/api/v2}"

# 1. Validate port argument
if [ -z "$PORT" ] || ! [ "$PORT" -ge 1 ] 2>/dev/null || ! [ "$PORT" -le 65535 ] 2>/dev/null; then
    echo ">> ERROR: A valid port number (1-65535) must be passed as the first argument" >&2
    exit 1
fi

echo ">> Running Update Port Script for port: $PORT"

# 2. Only install dependencies if missing
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo ">> Installing required dependencies (curl, jq)..."
    apk update >/dev/null 2>&1 || true
    apk add --no-cache -q curl jq
fi

# 3. Create secure isolated temp dir for cookies/scratch data (safe with read-only root)
TMP_DIR=$(mktemp -d /tmp/qbt-update.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
COOKIE_JAR="$TMP_DIR/cookie"

# 4. Wait for qBittorrent API to become ready (up to 30s)
echo ">> Checking qBittorrent connection..."
READY=false
for _ in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$API_ENDPOINT/app/version" 2>/dev/null || true)
    if [ "$STATUS" = "200" ]; then
        READY=true
        break
    fi
    sleep 1
done

if [ "$READY" != "true" ]; then
    echo ">> ERROR: qBittorrent WebUI at $API_ENDPOINT was not reachable after 30s" >&2
    exit 1
fi

# 5. Check current port - exit early if no change is needed
CURRENT_PORT=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$API_ENDPOINT/app/preferences" | jq -r '.listen_port // empty' 2>/dev/null || true)
if [ "$CURRENT_PORT" = "$PORT" ]; then
    echo ">> Port is already set to $PORT. No change needed."
    exit 0
fi

echo ">> Current port: ${CURRENT_PORT:-unknown}, updating to: $PORT"

# 6. Toggle random port to force socket rebind
PAYLOAD='{"random_port": true}'
curl -s -X POST -c "$COOKIE_JAR" -b "$COOKIE_JAR" --data "json=$PAYLOAD" "$API_ENDPOINT/app/setPreferences" >/dev/null
sleep 2

# 7. Update to the desired listening port
PAYLOAD="{\"listen_port\": $PORT}"
curl -s -X POST -c "$COOKIE_JAR" -b "$COOKIE_JAR" --data "json=$PAYLOAD" "$API_ENDPOINT/app/setPreferences" >/dev/null
sleep 2

# 8. Verify the new port
VERIFIED_PORT=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$API_ENDPOINT/app/preferences" | jq -r '.listen_port // empty' 2>/dev/null || true)

if [ "$VERIFIED_PORT" = "$PORT" ]; then
    echo ">> Port updated successfully to $PORT!"
else
    echo ">> ERROR: Failed to update port. Current port is: $VERIFIED_PORT" >&2
    exit 1
fi
