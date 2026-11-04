#!/usr/bin/env bash
# Fail the image build if any baked-in tool is missing or fails to execute.
set -euo pipefail

python3 - <<'PY'
import shutil
import subprocess
import sys

CMDS = {
    "actionlint": ["actionlint", "-version"],
    "argocd": ["argocd", "version", "--client", "--short"],
    "bats": ["bats", "--version"],
    "bun": ["bun", "--version"],
    "crane": ["crane", "version"],
    "ct": ["ct", "version"],
    "helm": ["helm", "version", "--short"],
    "jq": ["jq", "--version"],
    "kubeconform": ["kubeconform", "-v"],
    "kubectl": ["kubectl", "version", "--client"],
    "lychee": ["lychee", "--version"],
    "mise": ["mise", "--version"],
    "opentofu": ["tofu", "version"],
    "pytest": ["pytest", "--version"],
    "python": ["python3", "--version"],
    "ruff": ["ruff", "--version"],
    "shellcheck": ["shellcheck", "--version"],
    "trivy": ["trivy", "--version"],
    "uv": ["uv", "--version"],
    "yamale": ["yamale", "--version"],
    "yamllint": ["yamllint", "--version"],
    "yq": ["yq", "--version"],
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

if not shutil.which("openapi2jsonschema.py"):
    print("MISSING  openapi2jsonschema.py (/usr/local/bin/openapi2jsonschema.py)")
    failed = True
else:
    print("OK       openapi2jsonschema.py -> /usr/local/bin/openapi2jsonschema.py")

sys.exit(1 if failed else 0)
PY
