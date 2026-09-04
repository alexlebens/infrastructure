#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified ArgoCD CLI version (defaults to \$ARGOCD_VERSION or v3.5.2)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${ARGOCD_VERSION:-v3.5.2}}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if argocd is missing or version does not match
if ! command -v argocd >/dev/null 2>&1 || [[ "$(argocd version --client 2>/dev/null || true)" != *"${VERSION#v}"* ]]; then
  echo ">> Downloading ArgoCD CLI, version: ${VERSION} ..."
  curl -sSL -o "${BIN_DIR}/argocd" "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"
  chmod +x "${BIN_DIR}/argocd"
else
  echo ">> ArgoCD CLI ${VERSION} is already installed"
fi

echo ">> Verified: $(argocd version --client 2>&1)"
echo ""
echo "----"
