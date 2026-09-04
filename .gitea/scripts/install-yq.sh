#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified yq version (defaults to \$YQ_VERSION or v4.53.3)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${YQ_VERSION:-v4.53.3}}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if yq is missing or version does not match
if ! command -v yq >/dev/null 2>&1 || [[ "$(yq -V 2>/dev/null || true)" != *"${VERSION#v}"* ]]; then
  echo ">> Downloading yq ${VERSION} ..."
  wget -qO "${BIN_DIR}/yq" "https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_amd64"
  chmod +x "${BIN_DIR}/yq"
else
  echo ">> yq ${VERSION} is already installed"
fi

echo ">> Verified: $(yq -V)"
echo ""
echo "----"
