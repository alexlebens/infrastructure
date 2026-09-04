#!/usr/bin/env python3
"""Gitea Pull Request Manager.

Reusable, workflow-agnostic script to detect changes in a repository or directory,
commit and push them, and manage the Gitea Pull Request lifecycle (creating, updating,
or automerging).
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
import urllib.request


def run_cmd(
    cmd: list[str], cwd: str | None = None, check: bool = True
) -> subprocess.CompletedProcess:
  """Run a shell command and return CompletedProcess."""
  return subprocess.run(
      cmd, cwd=cwd, check=check, text=True, capture_output=True
  )


def write_github_output(outputs: dict[str, str]):
  """Append outputs to GITHUB_OUTPUT environment file."""
  output_file = os.getenv("GITHUB_OUTPUT")
  if not output_file:
    return
  with open(output_file, "a", encoding="utf-8") as f:
    for key, value in outputs.items():
      f.write(f"{key}={value}\n")


def gitea_api_request(
    url: str,
    token: str,
    method: str = "GET",
    data: dict | None = None,
) -> tuple[int, dict | list | str]:
  """Perform HTTP request against Gitea API."""
  headers = {
      "Authorization": f"token {token}",
      "Content-Type": "application/json",
      "User-Agent": "infrastructure-ci-pr-sync",
  }
  body_bytes = json.dumps(data).encode("utf-8") if data is not None else None
  req = urllib.request.Request(
      url, data=body_bytes, headers=headers, method=method
  )

  try:
    with urllib.request.urlopen(req) as resp:
      status = resp.status
      resp_text = resp.read().decode("utf-8")
      try:
        return status, json.loads(resp_text)
      except json.JSONDecodeError:
        return status, resp_text
  except HTTPError as e:
    resp_text = e.read().decode("utf-8")
    try:
      return e.code, json.loads(resp_text)
    except json.JSONDecodeError:
      return e.code, resp_text
  except URLError as e:
    print(f">> Network error contacting Gitea API: {e}", file=sys.stderr)
    return 0, str(e)


def main():
  parser = argparse.ArgumentParser(
      description="Manage Git commits, pushes, and Gitea Pull Requests."
  )
  parser.add_argument(
      "--work-dir",
      default=os.getenv("WORK_DIR", "."),
      help="Working directory of git repository (default: .)",
  )
  parser.add_argument(
      "--add-path",
      default=os.getenv("ADD_PATH", "."),
      help="Path(s) to git add before committing (default: .)",
  )
  parser.add_argument(
      "--base-branch",
      default=os.getenv("BASE_BRANCH", "main"),
      help="Base branch to target with PR (default: main).",
  )
  parser.add_argument(
      "--head-branch",
      default=os.getenv("HEAD_BRANCH", ""),
      help="Head branch containing new changes.",
  )
  parser.add_argument(
      "--force-push",
      action="store_true",
      default=os.getenv("FORCE_PUSH", "false").lower() == "true",
      help="Force push branch to remote (default: false).",
  )
  parser.add_argument(
      "--is-automerge",
      default=os.getenv("IS_AUTOMERGE", "false"),
      help="Whether to automatically merge the PR (default: false).",
  )
  parser.add_argument(
      "--assignee",
      default=os.getenv("ASSIGNEE", "alexlebens"),
      help="Gitea username to assign PR to (default: alexlebens).",
  )
  parser.add_argument(
      "--token",
      default=os.getenv("GITEA_TOKEN", ""),
      help="Gitea API token.",
  )
  parser.add_argument(
      "--url",
      default=os.getenv("GITEA_URL", ""),
      help="Gitea base URL.",
  )
  parser.add_argument(
      "--repo",
      default=os.getenv(
          "REPOSITORY",
          os.getenv("GITHUB_REPOSITORY", os.getenv("GITEA_REPOSITORY", "")),
      ),
      help="Target repository in format owner/repo.",
  )
  parser.add_argument(
      "--title",
      default=os.getenv("TITLE", os.getenv("PR_TITLE", "Automated Pull Request")),
      help="Pull request title.",
  )
  parser.add_argument(
      "--body",
      default=os.getenv("BODY", os.getenv("PR_BODY", "Automated changes pushed by CI workflow.")),
      help="Pull request body markdown.",
  )
  parser.add_argument(
      "--body-file",
      default=os.getenv("BODY_FILE", ""),
      help="Path to file containing pull request body markdown.",
  )
  parser.add_argument(
      "--commit-msg",
      default=os.getenv("COMMIT_MSG", "chore: automated update"),
      help="Git commit message.",
  )

  args = parser.parse_args()

  work_dir = os.path.abspath(args.work_dir)
  if not os.path.isdir(work_dir):
    print(
        f"Error: Working directory '{work_dir}' not found.",
        file=sys.stderr,
    )
    sys.exit(1)

  base_branch = args.base_branch
  head_branch = args.head_branch
  force_push = args.force_push
  is_automerge = args.is_automerge.lower() == "true"
  assignee = args.assignee
  token = args.token
  gitea_url = args.url.rstrip("/")
  repo = args.repo
  title = args.title
  commit_msg = args.commit_msg

  if not head_branch:
    print("Error: --head-branch or HEAD_BRANCH is required.", file=sys.stderr)
    sys.exit(1)
  if not token:
    print("Error: --token or GITEA_TOKEN is required.", file=sys.stderr)
    sys.exit(1)
  if not gitea_url or not repo:
    print(
        "Error: Gitea URL and Repository must be specified.", file=sys.stderr
    )
    sys.exit(1)

  # Check git status in working directory
  status_proc = run_cmd(["git", "status", "--porcelain"], cwd=work_dir)
  git_status = status_proc.stdout.strip()

  if not git_status:
    print(
        f">> No changes detected in {work_dir}, skipping commit and PR"
        " creation."
    )
    write_github_output({
        "changes-detected": "false",
        "changed-files-count": "0",
        "push": "false",
        "pushed": "false",
        "head-branch": head_branch,
        "pull-request-operation": "none",
        "pr-op": "none",
        "pull-request-number": "",
        "pr-number": "",
        "pull-request-url": "",
        "pr-url": "",
    })
    sys.exit(0)

  changed_files_count = len(git_status.splitlines())
  print(f">> Changes detected ({changed_files_count} files/entries):")
  print(git_status)
  print()

  # Ensure on head_branch in working directory
  curr_branch_proc = run_cmd(
      ["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=work_dir, check=False
  )
  curr_branch = curr_branch_proc.stdout.strip()
  if curr_branch and curr_branch != head_branch:
    print(f">> Switching to branch '{head_branch}' (from '{curr_branch}') ...")
    run_cmd(["git", "checkout", "-B", head_branch], cwd=work_dir)

  # Ensure git committer identity is configured
  user_name_check = run_cmd(
      ["git", "config", "user.name"], cwd=work_dir, check=False
  )
  if not user_name_check.stdout.strip():
    run_cmd(["git", "config", "user.name", "gitea-bot"], cwd=work_dir)
  user_email_check = run_cmd(
      ["git", "config", "user.email"], cwd=work_dir, check=False
  )
  if not user_email_check.stdout.strip():
    run_cmd(
        ["git", "config", "user.email", "gitea-bot@alexlebens.dev"], cwd=work_dir
    )

  print(f">> Committing changes to {head_branch} ...")
  run_cmd(["git", "add", args.add_path], cwd=work_dir)
  run_cmd(["git", "commit", "-m", commit_msg], cwd=work_dir)

  # Construct authenticated push URL
  parsed_url = urlparse(gitea_url)
  auth_netloc = f"oauth2:{token}@{parsed_url.netloc}"
  auth_repo_url = (
      f"{parsed_url.scheme}://{auth_netloc}/{repo.lstrip('/')}.git"
      if not repo.endswith(".git")
      else f"{parsed_url.scheme}://{auth_netloc}/{repo.lstrip('/')}"
  )

  push_cmd = ["git", "push", "-u"]
  if force_push:
    push_cmd.append("-f")
  push_cmd.extend([auth_repo_url, head_branch])

  print(
      f">> Pushing changes to {gitea_url}/{repo} on branch {head_branch} (force={force_push}) ..."
  )
  run_cmd(push_cmd, cwd=work_dir)
  print(">> Push completed successfully.")
  print()
  print("----")

  pr_operation = "none"
  pr_number = ""
  pr_url = ""

  # Resolve PR body content
  pr_body = ""
  if args.body_file and os.path.isfile(args.body_file):
    with open(args.body_file, "r", encoding="utf-8") as f:
      pr_body = f.read().strip()
  elif args.body:
    pr_body = args.body.strip()
  else:
    pr_body = "Automated changes pushed by CI workflow."

  # If not an automerge PR, check if an open PR from head_branch into base_branch already exists
  if not is_automerge:
    list_url = f"{gitea_url}/api/v1/repos/{repo}/pulls?state=open&page=1"
    print(
        f">> Checking for existing open PR from {head_branch} into"
        f" {base_branch} ..."
    )
    status_code, pulls_data = gitea_api_request(list_url, token, method="GET")

    existing_pr = None
    if status_code == 200 and isinstance(pulls_data, list):
      for p in pulls_data:
        head_ref = p.get("head", {}).get("ref", "")
        if head_ref == head_branch or head_ref == f"refs/heads/{head_branch}":
          existing_pr = p
          break

    if existing_pr:
      existing_pr_number = existing_pr["number"]
      pr_url = existing_pr.get(
          "html_url", f"{gitea_url}/{repo}/pulls/{existing_pr_number}"
      )
      print(f">> Found open PR #{existing_pr_number}. Updating PR ...")

      patch_url = f"{gitea_url}/api/v1/repos/{repo}/pulls/{existing_pr_number}"
      patch_payload = {}
      if pr_body:
        patch_payload["body"] = pr_body
      if title:
        patch_payload["title"] = title

      if patch_payload:
        patch_status, _ = gitea_api_request(
            patch_url, token, method="PATCH", data=patch_payload
        )
        if patch_status in (200, 201):
          print(f">> Pull Request #{existing_pr_number} updated successfully!")
          pr_operation = "updated"
          pr_number = str(existing_pr_number)
        else:
          print(
              f">> Warning: Failed to update PR #{existing_pr_number} (HTTP"
              f" {patch_status})."
          )
      else:
        pr_operation = "updated"
        pr_number = str(existing_pr_number)

  # If not updated, create a new PR
  if pr_operation == "none":
    print(f">> Creating new Pull Request for {head_branch} ...")
    create_url = f"{gitea_url}/api/v1/repos/{repo}/pulls"

    create_payload = {
        "head": head_branch,
        "base": base_branch,
        "assignee": assignee,
        "title": title,
        "body": pr_body,
    }

    create_status, create_data = gitea_api_request(
        create_url, token, method="POST", data=create_payload
    )

    if create_status == 201 and isinstance(create_data, dict):
      pr_number = str(create_data.get("number", ""))
      pr_url = create_data.get("html_url", f"{gitea_url}/{repo}/pulls/{pr_number}")
      pr_operation = "created"
      print(f">> Pull Request #{pr_number} created successfully!")
    elif create_status in (409, 422):
      print(f">> Pull Request already exists (HTTP {create_status}).")
    else:
      print(
          f">> Failed to create PR, HTTP {create_status}: {create_data}",
          file=sys.stderr,
      )
      sys.exit(1)

  # Handle Automerge if requested
  if is_automerge and pr_number:
    print(f">> Automerging PR #{pr_number} ...")
    merge_url = f"{gitea_url}/api/v1/repos/{repo}/pulls/{pr_number}/merge"
    merge_status, merge_data = gitea_api_request(
        merge_url, token, method="POST", data={"Do": "merge"}
    )

    if merge_status == 200:
      print(f">> Pull Request #{pr_number} merged successfully!")
      pr_operation = "merged"
    else:
      print(
          f">> Failed to automerge PR #{pr_number}, HTTP {merge_status}:"
          f" {merge_data}",
          file=sys.stderr,
      )
      # Clean up branch on automerge failure
      run_cmd(
          ["git", "push", "origin", "--delete", head_branch],
          cwd=work_dir,
          check=False,
      )
      sys.exit(1)

  if not pr_url and pr_number:
    pr_url = f"{gitea_url}/{repo}/pulls/{pr_number}"

  write_github_output({
      "changes-detected": "true",
      "changed-files-count": str(changed_files_count),
      "push": "true",
      "pushed": "true",
      "head-branch": head_branch,
      "pull-request-operation": pr_operation,
      "pr-op": pr_operation,
      "pull-request-number": pr_number,
      "pr-number": pr_number,
      "pull-request-url": pr_url,
      "pr-url": pr_url,
  })


if __name__ == "__main__":
  main()
