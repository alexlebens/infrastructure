#!/usr/bin/env bash
# Fail the image build if mise is missing or fails to execute.
set -euo pipefail

python3 - <<'PY'
import shutil
import subprocess
import sys

CMDS = {
    "mise": ["mise", "--version"],
}

failed = False
for name, cmd in sorted(CMDS.items()):
    path = shutil.which(cmd[0])
    if not path:
        print(f"MISSING  {name} ({cmd[0]} not on PATH)")
        failed = True
        continue
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        first_line = (out.stdout + out.stderr).strip().splitlines()[0]
        print(f"OK       {name:<12} -> {path} ({first_line})")
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"FAILED   {name:<12} -> {exc}")
        failed = True

sys.exit(1 if failed else 0)
PY
