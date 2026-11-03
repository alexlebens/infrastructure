#!/usr/bin/env bash
# Emit docker build-args (one NAME_VERSION=x per line) for every [tools] entry in mise.toml.
# Usage: images/runner/build-args.sh [path/to/mise.toml]
set -euo pipefail

MISE_FILE="${1:-mise.toml}"

python3 - "$MISE_FILE" <<'PY'
import re
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    tools = tomllib.load(f).get("tools", {})

for name, spec in tools.items():
    version = spec if isinstance(spec, str) else spec["version"]
    arg = re.sub(r"[^A-Za-z0-9]", "_", name).upper()
    print(f"{arg}_VERSION={version}")
PY
