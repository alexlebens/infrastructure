#!/usr/bin/env bash
# Fail the image build if any [tools] entry in mise.toml is missing or at a different version.
# Usage: verify-tools.sh <mise.toml>
set -euo pipefail

MISE_FILE="${1:?usage: verify-tools.sh <mise.toml>}"

python3 - "$MISE_FILE" <<'PY'
import subprocess
import sys
import tomllib

# tool -> version command (tools not listed use "<tool> --version")
CMDS = {
    "opentofu": ["tofu", "version"],
    "kubectl": ["kubectl", "version", "--client"],
    "kubeconform": ["kubeconform", "-v"],
    "helm": ["helm", "version", "--short"],
    "argocd": ["argocd", "version", "--client", "--short"],
    "crane": ["crane", "version"],
    "jq": ["jq", "--version"],
    "yq": ["yq", "--version"],
    "shellcheck": ["shellcheck", "--version"],
    "bats": ["bats", "--version"],
}

# Tools whose binary does not report a semver (crane's official image prints a git commit).
# For these we only check the binary runs; the version is pinned by the source image tag.
PRESENCE_ONLY = {"crane"}

with open(sys.argv[1], "rb") as f:
    tools = tomllib.load(f).get("tools", {})

failed = False
for name, spec in tools.items():
    version = spec if isinstance(spec, str) else spec["version"]
    cmd = CMDS.get(name, [name, "--version"])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        text = out.stdout + out.stderr
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"MISSING  {name}@{version}: {exc}")
        failed = True
        continue
    if name in PRESENCE_ONLY:
        print(f"OK       {name}@{version} (presence only)")
    elif version in text:
        print(f"OK       {name}@{version}")
    else:
        print(f"MISMATCH {name}@{version}: {text.strip().splitlines()[0] if text.strip() else ''}")
        failed = True

sys.exit(1 if failed else 0)
PY
