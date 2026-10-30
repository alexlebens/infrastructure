"""Shared pytest fixtures for .gitea/scripts Python tests.

The scripts under test have hyphenated file names, so they are loaded by path
rather than imported as regular modules.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS_DIR = PROJECT_ROOT / ".gitea" / "scripts"


def load_script(filename: str) -> ModuleType:
    """Load a script from .gitea/scripts as a module."""
    path = SCRIPTS_DIR / filename
    module_name = path.stem.replace("-", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec and spec.loader, f"cannot load {path}"
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def project_root() -> Path:
    return PROJECT_ROOT


@pytest.fixture
def github_output(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Point GITHUB_OUTPUT at a fresh temp file."""
    out = tmp_path / "github_output"
    out.write_text("", encoding="utf-8")
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    return out


def parse_github_output(path: Path) -> dict[str, str]:
    """Parse a GITHUB_OUTPUT file supporting `key=value` and heredoc entries."""
    result: dict[str, str] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if "<<" in line and ("=" not in line or line.index("<<") < line.index("=")):
            key, delim = line.split("<<", 1)
            body = []
            i += 1
            while i < len(lines) and lines[i] != delim:
                body.append(lines[i])
                i += 1
            result[key] = "\n".join(body)
        elif "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
        i += 1
    return result


@pytest.fixture
def git_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Isolate git from the developer's global configuration."""
    gitconfig = tmp_path / "gitconfig"
    gitconfig.write_text(
        "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(gitconfig))
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")


def git(*args: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, text=True, capture_output=True
    ).stdout.strip()
