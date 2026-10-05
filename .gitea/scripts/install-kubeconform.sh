#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified kubeconform version (defaults to \$KUBECONFORM_VERSION or v0.8.0)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${KUBECONFORM_VERSION:-v0.8.0}}"
VERSION_NO_V="${VERSION#v}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if kubeconform is missing or version does not match
if ! command -v kubeconform >/dev/null 2>&1 || [[ "$(kubeconform -v 2>/dev/null || true)" != *"${VERSION_NO_V}"* ]]; then
  echo ">> Downloading kubeconform ${VERSION} ..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  wget -qO "${TEMP_DIR}/kubeconform.tar.gz" "https://github.com/yannh/kubeconform/releases/download/${VERSION}/kubeconform-linux-amd64.tar.gz"
  tar -xzf "${TEMP_DIR}/kubeconform.tar.gz" -C "${TEMP_DIR}" kubeconform
  mv "${TEMP_DIR}/kubeconform" "${BIN_DIR}/kubeconform"
  chmod +x "${BIN_DIR}/kubeconform"
else
  echo ">> kubeconform ${VERSION} is already installed"
fi

echo ">> Verified: $(kubeconform -v)"
echo ""
echo "----"
