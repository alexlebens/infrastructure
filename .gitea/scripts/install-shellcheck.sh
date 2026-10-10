#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: $0 [version]"
      echo "Installs or verifies the specified ShellCheck version (defaults to \$SHELLCHECK_VERSION or v0.11.0)."
      exit 0
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

VERSION="${VERSION:-${SHELLCHECK_VERSION:-v0.11.0}}"
VERSION_NO_V="${VERSION#v}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

# Download only if shellcheck is missing or version does not match
if ! command -v shellcheck >/dev/null 2>&1 || [[ "$(shellcheck --version 2>/dev/null || true)" != *"${VERSION_NO_V}"* ]]; then
  echo ">> Downloading ShellCheck ${VERSION} ..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  wget -qO "${TEMP_DIR}/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/${VERSION}/shellcheck-${VERSION}.linux.x86_64.tar.xz"
  tar -xf "${TEMP_DIR}/shellcheck.tar.xz" -C "${TEMP_DIR}"
  mv "${TEMP_DIR}/shellcheck-${VERSION}/shellcheck" "${BIN_DIR}/shellcheck"
  chmod +x "${BIN_DIR}/shellcheck"
else
  echo ">> ShellCheck ${VERSION} is already installed"
fi

echo ">> Verified: $(shellcheck --version | head -n 2 | tail -n 1)"
echo ""
echo "----"
