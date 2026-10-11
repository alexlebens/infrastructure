#!/usr/bin/env bash
set -euo pipefail

if ! command -v shellcheck >/dev/null 2>&1; then
  echo ">> Installing shellcheck ..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck
  else
    echo "Error: shellcheck is not installed and cannot be installed automatically." >&2
    exit 1
  fi
fi

echo ">> Running shellcheck on bash scripts in .gitea/scripts/ ..."
shopt -s nullglob
scripts=(.gitea/scripts/*.sh)
shopt -u nullglob

if [ ${#scripts[@]} -eq 0 ]; then
  echo "No bash scripts found in .gitea/scripts/."
  exit 0
fi

shellcheck "${scripts[@]}"
echo ">> All bash scripts passed shellcheck!"
