#!/usr/bin/env bash
set -euo pipefail

ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-1.7.12}"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${BIN_DIR}" >> "${GITHUB_PATH}"
fi
export PATH="${BIN_DIR}:${PATH}"

if ! command -v actionlint >/dev/null 2>&1; then
  echo ">> Installing actionlint ${ACTIONLINT_VERSION} ..."
  bash <(curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) "${ACTIONLINT_VERSION}" "${BIN_DIR}"
fi

echo ">> Running actionlint on workflows in .gitea/workflows/ ..."
shopt -s nullglob
workflows=(.gitea/workflows/*.yaml .gitea/workflows/*.yml)
shopt -u nullglob

if [ ${#workflows[@]} -eq 0 ]; then
  echo "No workflow files found in .gitea/workflows/."
  exit 0
fi

actionlint \
  -ignore 'specifying action "builtin:checkout" in invalid format' \
  -ignore 'undefined variable "gitea"' \
  "${workflows[@]}"

echo ">> All workflows passed actionlint!"
