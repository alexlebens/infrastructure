#!/usr/bin/env python3
"""Gitea Manifest PR Sync

Detects changes in rendered Kubernetes manifests, commits and pushes them to Gitea,
and manages the Pull Request lifecycle (creating, updating, or automerging).
Uses only the Python standard library (no third-party dependencies required).
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import re
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
      "User-Agent": "infrastructure-ci-manifest-sync",
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
      description="Manage manifest commits and Gitea Pull Requests."
  )
  parser.add_argument(
      "--manifest-dir",
      default=os.getenv("MANIFEST_DIR", "infrastructure-manifests"),
  )
  parser.add_argument("--cluster", default=os.getenv("CLUSTER", "cl01tl"))
  parser.add_argument(
      "--base-branch", default=os.getenv("BASE_BRANCH", "manifests")
  )
  parser.add_argument("--head-branch", default=os.getenv("HEAD_BRANCH", ""))
  parser.add_argument(
      "--is-automerge", default=os.getenv("IS_AUTOMERGE", "false")
  )
  parser.add_argument("--assignee", default=os.getenv("ASSIGNEE", "alexlebens"))
  parser.add_argument("--token", default=os.getenv("GITEA_TOKEN", ""))
  parser.add_argument("--url", default=os.getenv("GITEA_URL", ""))
  parser.add_argument(
      "--repo",
      default=os.getenv(
          "REPOSITORY",
          os.getenv("GITHUB_REPOSITORY", os.getenv("GITEA_REPOSITORY", "")),
      ),
  )
  parser.add_argument(
      "--event-name",
      default=os.getenv(
          "EVENT_NAME", os.getenv("GITHUB_EVENT_NAME", "pull_request")
      ),
  )
  parser.add_argument(
      "--actor",
      default=os.getenv("ACTOR", os.getenv("GITHUB_ACTOR", "gitea-bot")),
  )
  parser.add_argument(
      "--sha", default=os.getenv("SHA", os.getenv("GITHUB_SHA", "HEAD"))
  )
  parser.add_argument(
      "--ref-name",
      default=os.getenv("REF_NAME", os.getenv("GITHUB_REF_NAME", "main")),
  )

  args = parser.parse_args()

  manifest_dir = os.path.abspath(args.manifest_dir)
  if not os.path.isdir(manifest_dir):
    print(
        f"Error: Manifest directory '{manifest_dir}' not found.",
        file=sys.stderr,
    )
    sys.exit(1)

  cluster = args.cluster
  base_branch = args.base_branch
  head_branch = args.head_branch
  is_automerge = args.is_automerge.lower() == "true"
  assignee = args.assignee
  token = args.token
  gitea_url = args.url.rstrip("/")
  repo = args.repo
  event_name = args.event_name
  actor = args.actor
  sha = args.sha[:7] if len(args.sha) >= 7 else args.sha
  ref_name = args.ref_name

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

  # Check git status in manifest repository
  status_proc = run_cmd(["git", "status", "--porcelain"], cwd=manifest_dir)
  git_status = status_proc.stdout.strip()

  if not git_status:
    print(
        f">> No changes detected in {manifest_dir}, skipping commit and PR"
        " creation."
    )
    write_github_output({
        "changes-detected": "false",
        "changed-charts-csv": "",
        "push": "false",
        "head-branch": head_branch,
        "pull-request-operation": "none",
        "pull-request-number": "",
    })
    sys.exit(0)

  print(">> Changes detected:")
  print(git_status)
  print()

  # Extract changed chart names
  pattern = re.compile(rf"clusters/{re.escape(cluster)}/manifests/([^/\s]+)/?")
  changed_charts_set = set()
  for line in git_status.splitlines():
    match = pattern.search(line)
    if match:
      changed_charts_set.add(match.group(1))

  changed_charts_list = sorted(changed_charts_set)
  changed_charts_csv = ",".join(changed_charts_list)
  print(f">> Changed Charts ({len(changed_charts_list)}): {changed_charts_csv}")

  # Commit changes
  commit_msg = (
      "chore: Update manifests after automerge"
      if is_automerge
      else "chore: Update manifests after change"
  )
  print(f">> Committing changes to {head_branch} ...")
  run_cmd(["git", "add", "."], cwd=manifest_dir)
  run_cmd(["git", "commit", "-m", commit_msg], cwd=manifest_dir)

  # Construct authenticated push URL
  parsed_url = urlparse(gitea_url)
  auth_netloc = f"oauth2:{token}@{parsed_url.netloc}"
  auth_repo_url = (
      f"{parsed_url.scheme}://{auth_netloc}/{repo.lstrip('/')}.git"
      if not repo.endswith(".git")
      else f"{parsed_url.scheme}://{auth_netloc}/{repo.lstrip('/')}"
  )

  print(
      f">> Pushing changes to {gitea_url}/{repo} on branch {head_branch} ..."
  )
  push_proc = run_cmd(
      ["git", "push", "-u", auth_repo_url, head_branch], cwd=manifest_dir
  )
  print(">> Push completed successfully.")
  print()
  print("----")

  pr_operation = "none"
  pr_number = ""

  # If not an automerge PR, check if an open PR from head_branch into base_branch already exists
  if not is_automerge:
    list_url = f"{gitea_url}/api/v1/repos/{repo}/pulls?base_branch={base_branch}&state=open&page=1"
    print(
        f">> Checking for existing open PR from {head_branch} into"
        f" {base_branch} ..."
    )
    status_code, pulls_data = gitea_api_request(list_url, token, method="GET")

    existing_pr = None
    if status_code == 200 and isinstance(pulls_data, list):
      for p in pulls_data:
        head_ref = p.get("head", {}).get("ref", "")
        if head_ref == head_branch:
          existing_pr = p
          break
      if not existing_pr and pulls_data and pulls_data[0].get("state") == "open":
        existing_pr = pulls_data[0]

    if existing_pr:
      existing_pr_number = existing_pr["number"]
      print(f">> Found open PR #{existing_pr_number}. Updating PR body ...")
      existing_body = existing_pr.get("body", "")

      now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
      new_details = (
          f"### Update Details ({now_utc})\n"
          f"- **Trigger**: `{event_name}` by `@{actor}`\n"
          f"- **Commit**: `{sha}` (on `{ref_name}`)\n"
          f"- **Charts Updated**: `{changed_charts_csv}`"
      )
      updated_body = f"{existing_body}\n\n{new_details}".strip()

      patch_url = (
          f"{gitea_url}/api/v1/repos/{repo}/pulls/{existing_pr_number}"
      )
      patch_status, _ = gitea_api_request(
          patch_url, token, method="PATCH", data={"body": updated_body}
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

  # If not updated, create a new PR
  if pr_operation == "none":
    print(f">> Creating new Pull Request for {head_branch} ...")
    create_url = f"{gitea_url}/api/v1/repos/{repo}/pulls"

    title = (
        "Automated Manifest Update - Automerge"
        if is_automerge
        else "Automated Manifest Update"
    )
    body = (
        "This PR contains newly rendered Kubernetes manifests automatically"
        " generated by the CI workflow.\n\n"
        "### Details\n"
        f"- **Trigger**: `{event_name}` by `@{actor}`\n"
        f"- **Commit**: `{sha}` (on `{ref_name}`)\n"
        f"- **Charts Updated**: `{changed_charts_csv}`"
    )
    if is_automerge:
      body += "\n\n_This PR is expected to be automerged._"

    create_payload = {
        "head": head_branch,
        "base": base_branch,
        "assignee": assignee,
        "title": title,
        "body": body,
    }

    create_status, create_data = gitea_api_request(
        create_url, token, method="POST", data=create_payload
    )

    if create_status == 201 and isinstance(create_data, dict):
      pr_number = str(create_data.get("number", ""))
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
          cwd=manifest_dir,
          check=False,
      )
      sys.exit(1)

  write_github_output({
      "changes-detected": "true",
      "changed-charts-csv": changed_charts_csv,
      "push": "true",
      "head-branch": head_branch,
      "pull-request-operation": pr_operation,
      "pull-request-number": pr_number,
  })


if __name__ == "__main__":
  main()
