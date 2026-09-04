#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified Trivy version (defaults to \$TRIVY_VERSION or v0.74.0)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${TRIVY_VERSION:-v0.74.0}}"
VERSION_NO_V="${VERSION#v}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if trivy is missing or version does not match
if ! command -v trivy >/dev/null 2>&1 || [[ "$(trivy --version 2>/dev/null || true)" != *"${VERSION_NO_V}"* ]]; then
  echo ">> Downloading Trivy ${VERSION} ..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  wget -qO "${TEMP_DIR}/trivy.tar.gz" "https://github.com/aquasecurity/trivy/releases/download/${VERSION}/trivy_${VERSION_NO_V}_Linux-64bit.tar.gz"
  tar -xzf "${TEMP_DIR}/trivy.tar.gz" -C "${TEMP_DIR}" trivy
  mv "${TEMP_DIR}/trivy" "${BIN_DIR}/trivy"
  chmod +x "${BIN_DIR}/trivy"
else
  echo ">> Trivy ${VERSION} is already installed"
fi

echo ">> Verified: $(trivy --version | head -n 1)"
echo ""
echo "----"
