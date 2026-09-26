#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified OpenTofu version (defaults to \$TOFU_VERSION or v1.8.8)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${TOFU_VERSION:-1.8.8}}"
# Strip leading 'v' if present for tarball name
VERSION_NO_V="${VERSION#v}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if tofu is missing or version does not match
if ! command -v tofu >/dev/null 2>&1 || [[ "$(tofu version 2>/dev/null || true)" != *"${VERSION_NO_V}"* ]]; then
  echo ">> Downloading OpenTofu ${VERSION} ..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  wget -qO "${TEMP_DIR}/tofu.tar.gz" "https://github.com/opentofu/opentofu/releases/download/v${VERSION_NO_V}/tofu_${VERSION_NO_V}_linux_amd64.tar.gz"
  tar -xzf "${TEMP_DIR}/tofu.tar.gz" -C "${TEMP_DIR}" tofu
  mv "${TEMP_DIR}/tofu" "${BIN_DIR}/tofu"
  chmod +x "${BIN_DIR}/tofu"
else
  echo ">> OpenTofu ${VERSION} is already installed"
fi

echo ">> Verified: $(tofu version | head -n 1)"
echo ""
echo "----"
