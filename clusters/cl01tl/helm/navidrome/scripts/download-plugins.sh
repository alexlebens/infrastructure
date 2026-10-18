#!/bin/sh
set -eu

PLUGINS_DIR="/data/plugins"
umask 022
mkdir -p "$PLUGINS_DIR"

install_plugin() {
  PLUGIN_NAME="$1"
  VERSION="$2"
  REPO="$3"
  URL="${4:-https://github.com/${REPO}/releases/download/${VERSION}/${PLUGIN_NAME}}"
  MARKER="${PLUGINS_DIR}/.${PLUGIN_NAME}.${VERSION}"
  TARGET="${PLUGINS_DIR}/${PLUGIN_NAME}"
  TMP_TARGET="${TARGET}.tmp"

  if [ -f "$MARKER" ] && [ -s "$TARGET" ]; then
    echo ">> [OK] ${PLUGIN_NAME} (${VERSION}) is already installed, skipping."
    return 0
  fi

  echo ">> [DOWNLOADING] ${PLUGIN_NAME} (${VERSION}) from ${URL}..."
  rm -f "$TMP_TARGET"

  if ! wget -q --timeout=30 -O "$TMP_TARGET" "$URL"; then
    echo ">> [ERROR] Failed to download ${PLUGIN_NAME} from ${URL}" >&2
    rm -f "$TMP_TARGET"
    return 1
  fi

  if [ ! -s "$TMP_TARGET" ]; then
    echo ">> [ERROR] Downloaded ${PLUGIN_NAME} is empty!" >&2
    rm -f "$TMP_TARGET"
    return 1
  fi

  # Atomic replace
  mv -f "$TMP_TARGET" "$TARGET"
  chmod 755 "$TARGET"

  # Clean up old version markers and set current
  rm -f "${PLUGINS_DIR}/.${PLUGIN_NAME}."*
  touch "$MARKER"
  echo ">> [INSTALLED] ${PLUGIN_NAME} (${VERSION})"
}

# renovate: datasource=github-releases depName=NeptuneHub/AudioMuse-AI-NV-plugin
install_plugin "audiomuseai.ndp" "v9" "NeptuneHub/AudioMuse-AI-NV-plugin"

# renovate: datasource=github-releases depName=J0R6IT0/navidrome-lyrics-plugin
install_plugin "nd-lyrics.ndp" "v7.1.0" "J0R6IT0/navidrome-lyrics-plugin"

# renovate: datasource=github-releases depName=andykelk/navidrome-ntfy-plugin
install_plugin "navidrome-ntfy.ndp" "v1.1.0" "andykelk/navidrome-ntfy-plugin"

chown -R 1000:1000 "$PLUGINS_DIR" 2>/dev/null || true
