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

if [ "$#" -gt 0 ]; then
  scripts=("$@")
  echo ">> Running shellcheck on specified scripts: ${scripts[*]} ..."
else
  echo ">> Running shellcheck on bash scripts in .gitea/scripts/ ..."
  shopt -s nullglob
  scripts=(.gitea/scripts/*.sh)
  shopt -u nullglob
fi

if [ ${#scripts[@]} -eq 0 ]; then
  echo "No bash scripts found to check."
  exit 0
fi

shellcheck "${scripts[@]}"
echo ">> All bash scripts passed shellcheck!"
