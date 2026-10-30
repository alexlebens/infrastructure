"""Tests for .gitea/scripts/pr-gitea.py.

A real temporary git repository is used for the commit flow. `git push` is
redirected to a local bare repository and the Gitea REST API is replaced by an
in-memory fake, so no network access is required.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest
from conftest import git, load_script, parse_github_output

pr = load_script("pr-gitea.py")

GITEA_URL = "https://gitea.example.invalid"
REPO = "owner/manifests"
TOKEN = "s3cr3t-t0ken"


# ── fakes ────────────────────────────────────────────────────────────


class FakeGitea:
    """Minimal in-memory stand-in for gitea_api_request.

    Responses are registered per (method, path-suffix) and consumed in order;
    the last registered response is sticky once the queue is exhausted.
    """

    def __init__(self):
        self.routes: dict[tuple[str, str], list[tuple[int, object]]] = {}
        self.calls: list[tuple[str, str, dict | None]] = []

    def on(self, method: str, path: str, *responses: tuple[int, object]):
        self.routes.setdefault((method, path), []).extend(responses)
        return self

    def __call__(self, url, token, method="GET", data=None):
        assert token == TOKEN
        assert url.startswith(f"{GITEA_URL}/api/v1/repos/{REPO}/")
        path = url[len(f"{GITEA_URL}/api/v1/repos/{REPO}") :]
        self.calls.append((method, path, data))
        for (m, p), queue in self.routes.items():
            if m == method and path.split("?")[0] == p:
                return queue.pop(0) if len(queue) > 1 else queue[0]
        return 404, {"message": "not found"}

    def called(self, method: str, path: str) -> list[dict | None]:
        return [d for m, p, d in self.calls if m == method and p.split("?")[0] == path]


@pytest.fixture
def repo(tmp_path: Path, git_env) -> Path:
    """Working repository with one pending change and a bare 'remote'."""
    remote = tmp_path / "remote.git"
    work = tmp_path / "work"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    work.mkdir()
    git("init", "-q", cwd=work)
    git("config", "user.name", "tester", cwd=work)
    git("config", "user.email", "tester@example.invalid", cwd=work)
    (work / "README.md").write_text("base\n")
    git("add", "-A", cwd=work)
    git("commit", "-q", "-m", "base", cwd=work)
    (work / "new.yaml").write_text("kind: ConfigMap\n")
    return work


@pytest.fixture
def push_log(monkeypatch, tmp_path: Path) -> list[list[str]]:
    """Redirect authenticated pushes to the local bare repo and record them."""
    calls: list[list[str]] = []
    real_run_cmd = pr.run_cmd
    remote = str(tmp_path / "remote.git")

    def fake_run_cmd(cmd, cwd=None, check=True):
        if cmd[:2] == ["git", "push"]:
            calls.append(list(cmd))
            cmd = [remote if c.startswith("https://") else c for c in cmd]
        return real_run_cmd(cmd, cwd=cwd, check=check)

    monkeypatch.setattr(pr, "run_cmd", fake_run_cmd)
    return calls


@pytest.fixture
def api(monkeypatch) -> FakeGitea:
    fake = FakeGitea()
    monkeypatch.setattr(pr, "gitea_api_request", fake)
    monkeypatch.setattr(pr.time, "sleep", lambda *_: None)
    return fake


@pytest.fixture
def clean_env(monkeypatch):
    for var in (
        "WORK_DIR",
        "ADD_PATH",
        "BASE_BRANCH",
        "HEAD_BRANCH",
        "FORCE_PUSH",
        "IS_AUTOMERGE",
        "GITEA_TOKEN",
        "GITEA_URL",
        "REPOSITORY",
        "GITHUB_REPOSITORY",
        "GITEA_REPOSITORY",
        "TITLE",
        "PR_TITLE",
        "BODY",
        "PR_BODY",
        "BODY_FILE",
        "COMMIT_MSG",
        "UPDATE_COMMENT",
        "UPDATE_BODY",
    ):
        monkeypatch.delenv(var, raising=False)


def run_main(monkeypatch, work: Path, *extra: str) -> int:
    argv = [
        "pr-gitea.py",
        "--work-dir",
        str(work),
        "--head-branch",
        "auto/update",
        "--base-branch",
        "manifests",
        "--token",
        TOKEN,
        "--url",
        GITEA_URL + "/",
        "--repo",
        REPO,
        "--title",
        "Automated Update",
        "--commit-msg",
        "chore: update",
        *extra,
    ]
    monkeypatch.setattr(sys, "argv", argv)
    try:
        pr.main()
    except SystemExit as e:
        return int(e.code or 0)
    return 0


# ── pure helpers ─────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("repo_name", "expected"),
    [
        ("owner/repo", "https://oauth2:tok@gitea.example.invalid/owner/repo.git"),
        ("/owner/repo", "https://oauth2:tok@gitea.example.invalid/owner/repo.git"),
        ("owner/repo.git", "https://oauth2:tok@gitea.example.invalid/owner/repo.git"),
        ("owner/repo/", "https://oauth2:tok@gitea.example.invalid/owner/repo.git"),
    ],
)
def test_build_auth_repo_url(repo_name: str, expected: str):
    assert pr.build_auth_repo_url(GITEA_URL, repo_name, "tok") == expected


def test_redact():
    assert (
        pr.redact("https://oauth2:abc@host abc", "abc") == "https://oauth2:***@host ***"
    )
    assert pr.redact("unchanged", "") == "unchanged"


def test_write_github_output_single_and_multiline(github_output: Path):
    pr.write_github_output({"a": "1", "b": "line1\nline2", "c": ""})
    assert parse_github_output(github_output) == {
        "a": "1",
        "b": "line1\nline2",
        "c": "",
    }


def test_write_github_output_delimiter_collision(github_output: Path):
    pr.write_github_output({"b": "x\nEOF\ny"})
    assert parse_github_output(github_output) == {"b": "x\nEOF\ny"}


def test_write_github_output_noop_without_env(monkeypatch, tmp_path: Path):
    monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
    pr.write_github_output({"a": "1"})  # must not raise


def test_find_open_pr_matches_plain_and_full_refs(api: FakeGitea):
    api.on(
        "GET",
        "/pulls",
        (
            200,
            [
                {"number": 1, "head": {"ref": "other"}},
                {"number": 2, "head": None},
                {"number": 3, "head": {"ref": "refs/heads/auto/update"}},
            ],
        ),
    )
    found = pr.find_open_pr(GITEA_URL, REPO, TOKEN, "auto/update")
    assert found and found["number"] == 3


def test_find_open_pr_handles_api_errors(api: FakeGitea):
    api.on("GET", "/pulls", (500, "boom"))
    assert pr.find_open_pr(GITEA_URL, REPO, TOKEN, "x") is None


def test_gitea_api_request_network_error(monkeypatch):
    def boom(*_a, **_k):
        raise pr.URLError("unreachable")

    monkeypatch.setattr(pr.urllib.request, "urlopen", boom)
    status, body = pr.gitea_api_request(f"{GITEA_URL}/api/v1/x", TOKEN)
    assert status == 0
    assert "unreachable" in body


# ── argument validation ─────────────────────────────────────────────


def test_missing_head_branch_fails(monkeypatch, repo: Path, clean_env, capsys):
    monkeypatch.setattr(
        sys, "argv", ["pr-gitea.py", "--work-dir", str(repo), "--token", TOKEN]
    )
    with pytest.raises(SystemExit) as exc:
        pr.main()
    assert exc.value.code == 1
    assert "--head-branch" in capsys.readouterr().out


def test_missing_token_fails(monkeypatch, repo: Path, clean_env):
    monkeypatch.setattr(
        sys, "argv", ["pr-gitea.py", "--work-dir", str(repo), "--head-branch", "x"]
    )
    with pytest.raises(SystemExit) as exc:
        pr.main()
    assert exc.value.code == 1


def test_missing_work_dir_fails(monkeypatch, tmp_path: Path, clean_env):
    monkeypatch.setattr(
        sys, "argv", ["pr-gitea.py", "--work-dir", str(tmp_path / "nope")]
    )
    with pytest.raises(SystemExit) as exc:
        pr.main()
    assert exc.value.code == 1


# ── main flow ───────────────────────────────────────────────────────


def test_no_changes_skips_everything(
    monkeypatch, repo: Path, api, push_log, github_output, clean_env
):
    (repo / "new.yaml").unlink()
    assert run_main(monkeypatch, repo) == 0
    assert push_log == []
    assert api.calls == []
    out = parse_github_output(github_output)
    assert out["changes-detected"] == "false"
    assert out["pr-op"] == "none"
    assert out["head-branch"] == "auto/update"


def test_creates_new_pr(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("GET", "/pulls", (200, []))
    api.on(
        "POST",
        "/pulls",
        (201, {"number": 11, "html_url": f"{GITEA_URL}/{REPO}/pulls/11"}),
    )

    assert run_main(monkeypatch, repo, "--body", "  hello body  ") == 0

    # commit landed on the head branch with the requested message
    assert git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo) == "auto/update"
    assert git("log", "-1", "--format=%s", cwd=repo) == "chore: update"
    # push used the authenticated URL (trailing slash in --url stripped)
    assert push_log == [
        [
            "git",
            "push",
            "-u",
            f"https://oauth2:{TOKEN}@gitea.example.invalid/{REPO}.git",
            "auto/update",
        ]
    ]
    assert api.called("POST", "/pulls") == [
        {
            "head": "auto/update",
            "base": "manifests",
            "assignee": "alexlebens",
            "title": "Automated Update",
            "body": "hello body",
        }
    ]
    out = parse_github_output(github_output)
    assert out["changes-detected"] == "true"
    assert out["changed-files-count"] == "1"
    assert out["pr-op"] == out["pull-request-operation"] == "created"
    assert out["pr-number"] == "11"
    assert out["pr-url"] == f"{GITEA_URL}/{REPO}/pulls/11"


def test_force_push_flag(monkeypatch, repo: Path, api, push_log, clean_env):
    api.on("GET", "/pulls", (200, []))
    api.on("POST", "/pulls", (201, {"number": 1}))
    assert run_main(monkeypatch, repo, "--force-push") == 0
    assert push_log[0][:4] == ["git", "push", "-u", "-f"]


def test_body_file_takes_precedence(
    monkeypatch, repo: Path, api: FakeGitea, push_log, tmp_path: Path, clean_env
):
    body_file = tmp_path / "body.md"
    body_file.write_text("\nfrom file\n")
    api.on("GET", "/pulls", (200, []))
    api.on("POST", "/pulls", (201, {"number": 1}))
    assert (
        run_main(monkeypatch, repo, "--body", "ignored", "--body-file", str(body_file))
        == 0
    )
    assert api.called("POST", "/pulls")[0]["body"] == "from file"


def test_updates_existing_pr_title_only_and_posts_comment(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("GET", "/pulls", (200, [{"number": 5, "head": {"ref": "auto/update"}}]))
    api.on("PATCH", "/pulls/5", (200, {}))
    api.on("POST", "/issues/5/comments", (201, {}))

    assert run_main(monkeypatch, repo, "--update-comment", "new render") == 0

    assert api.called("PATCH", "/pulls/5") == [{"title": "Automated Update"}]
    assert api.called("POST", "/issues/5/comments") == [{"body": "new render"}]
    assert api.called("POST", "/pulls") == []
    out = parse_github_output(github_output)
    assert out["pr-op"] == "updated"
    assert out["pr-number"] == "5"
    assert out["pr-url"] == f"{GITEA_URL}/{REPO}/pulls/5"


def test_update_body_flag_patches_body(
    monkeypatch, repo: Path, api: FakeGitea, push_log, clean_env
):
    api.on("GET", "/pulls", (200, [{"number": 5, "head": {"ref": "auto/update"}}]))
    api.on("PATCH", "/pulls/5", (200, {}))
    assert run_main(monkeypatch, repo, "--update-body", "--body", "fresh") == 0
    assert api.called("PATCH", "/pulls/5") == [
        {"body": "fresh", "title": "Automated Update"}
    ]


def test_create_conflict_resolves_existing_pr(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    # First listing (pre-create) misses it, second (post-409) finds it.
    api.on(
        "GET",
        "/pulls",
        (200, []),
        (200, [{"number": 8, "head": {"ref": "auto/update"}, "html_url": "u8"}]),
    )
    api.on("POST", "/pulls", (409, {"message": "exists"}))
    assert run_main(monkeypatch, repo) == 0
    out = parse_github_output(github_output)
    assert out["pr-number"] == "8"
    assert out["pr-url"] == "u8"


def test_create_failure_exits_non_zero(
    monkeypatch, repo: Path, api: FakeGitea, push_log, clean_env
):
    api.on("GET", "/pulls", (200, []))
    api.on("POST", "/pulls", (500, {"message": "boom"}))
    assert run_main(monkeypatch, repo) == 1


def test_push_failure_does_not_leak_token(
    monkeypatch, repo: Path, api, clean_env, capsys
):
    real_run_cmd = pr.run_cmd

    def failing_push(cmd, cwd=None, check=True):
        if cmd[:2] == ["git", "push"]:
            return subprocess.CompletedProcess(
                cmd, 128, "", f"fatal: unable to access '{cmd[-2]}': denied"
            )
        return real_run_cmd(cmd, cwd=cwd, check=check)

    monkeypatch.setattr(pr, "run_cmd", failing_push)
    assert run_main(monkeypatch, repo) == 1
    out = capsys.readouterr()
    assert TOKEN not in out.out + out.err
    assert "git push failed" in out.out
    assert api.calls == []


# ── automerge ───────────────────────────────────────────────────────


def test_automerge_success(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    api.on("GET", "/pulls/21/merge", (404, {}))
    api.on("POST", "/pulls/21/merge", (200, {}))

    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 0
    # automerge never looks up/updates an existing shared PR
    assert api.called("GET", "/pulls") == []
    assert api.called("POST", "/pulls/21/merge") == [{"Do": "merge"}]
    assert parse_github_output(github_output)["pr-op"] == "merged"


def test_automerge_already_merged(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    api.on("GET", "/pulls/21/merge", (204, ""))
    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 0
    assert api.called("POST", "/pulls/21/merge") == []
    assert parse_github_output(github_output)["pr-op"] == "merged"


def test_automerge_verified_after_server_error(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    # pre-check: not merged; post-500 verification: merged
    api.on("GET", "/pulls/21/merge", (404, {}), (204, ""))
    api.on("POST", "/pulls/21/merge", (500, "race"))
    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 0
    assert parse_github_output(github_output)["pr-op"] == "merged"


def test_automerge_retries_transient_errors_and_updates_branch(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    api.on("GET", "/pulls/21/merge", (404, {}))
    api.on("POST", "/pulls/21/merge", (409, "locked"), (422, "not ready"), (200, {}))
    api.on("POST", "/pulls/21/update", (200, {}))

    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 0
    assert len(api.called("POST", "/pulls/21/merge")) == 3
    # branch update is requested from the 2nd attempt onwards on 409/422
    assert len(api.called("POST", "/pulls/21/update")) == 1
    assert parse_github_output(github_output)["pr-op"] == "merged"


def test_automerge_permanent_failure_deletes_branch(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    api.on("GET", "/pulls/21/merge", (404, {}))
    api.on("POST", "/pulls/21/merge", (403, "forbidden"))

    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 1
    assert len(api.called("POST", "/pulls/21/merge")) == 1
    assert push_log[-1][2:] == [
        f"https://oauth2:{TOKEN}@gitea.example.invalid/{REPO}.git",
        "--delete",
        "auto/update",
    ]
    # outputs are not written on failure
    assert github_output.read_text() == ""


def test_automerge_gives_up_after_max_retries(
    monkeypatch, repo: Path, api: FakeGitea, push_log, clean_env
):
    api.on("POST", "/pulls", (201, {"number": 21}))
    api.on("GET", "/pulls/21/merge", (404, {}))
    api.on("POST", "/pulls/21/merge", (405, "checking"))
    assert run_main(monkeypatch, repo, "--is-automerge", "true") == 1
    assert len(api.called("POST", "/pulls/21/merge")) == 15


def test_env_var_configuration(
    monkeypatch, repo: Path, api: FakeGitea, push_log, github_output, clean_env
):
    monkeypatch.setenv("WORK_DIR", str(repo))
    monkeypatch.setenv("HEAD_BRANCH", "env/branch")
    monkeypatch.setenv("GITEA_TOKEN", TOKEN)
    monkeypatch.setenv("GITEA_URL", GITEA_URL)
    monkeypatch.setenv("GITHUB_REPOSITORY", REPO)
    monkeypatch.setenv("PR_TITLE", "Env Title")
    api.on("GET", "/pulls", (200, []))
    api.on("POST", "/pulls", (201, {"number": 3}))
    monkeypatch.setattr(sys, "argv", ["pr-gitea.py"])
    pr.main()
    payload = api.called("POST", "/pulls")[0]
    assert payload["head"] == "env/branch"
    assert payload["base"] == "main"
    assert payload["title"] == "Env Title"
