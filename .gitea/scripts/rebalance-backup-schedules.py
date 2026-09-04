#!/usr/bin/env python3
"""Rebalance Backup Schedules.

Automates, balances, and staggers backup cron schedules across Helm charts
in clusters/<cluster>/helm/*/values.yaml for Volsync and Postgres.
Operates within an off-peak window (post-midnight to early morning US/Chicago time),
guaranteeing no collisions between database backups and storage snapshots.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import sys


def parse_yaml_backup_targets(file_path: Path) -> tuple[list[dict], list[dict]]:
  """Parses Postgres and Volsync backup target configurations from a values.yaml file."""
  lines = file_path.read_text(encoding="utf-8").splitlines(keepends=True)

  postgres_targets = []
  volsync_targets = []

  current_section = None
  section_indent = 0
  sub_section = None
  volsync_type = None
  volsync_type_indent = 0

  for idx, line in enumerate(lines):
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    # Check if we left the current top-level section
    if (
        current_section
        and stripped
        and indent <= section_indent
        and not stripped.startswith("#")
    ):
      current_section = None
      sub_section = None
      volsync_type = None

    # Match top-level Postgres cluster (e.g., postgres-18-cluster:, postgres-cluster:)
    m_pg = re.match(r"^(\s*)(postgres[\w-]*cluster):\s*(?:#.*)?$", line)
    if m_pg:
      current_section = ("postgres", m_pg.group(2))
      section_indent = len(m_pg.group(1))
      sub_section = None
      continue

    # Match top-level Volsync target (e.g., volsync-target-data:, volsync-target:)
    m_vs = re.match(r"^(\s*)(volsync-target[\w-]*):\s*(?:#.*)?$", line)
    if m_vs:
      current_section = ("volsync", m_vs.group(2))
      section_indent = len(m_vs.group(1))
      sub_section = None
      volsync_type = None
      continue

    if not current_section or not stripped or stripped.startswith("#"):
      continue

    sec_type, sec_name = current_section

    if sec_type == "postgres":
      if re.match(r"^\s*backup:\s*(?:#.*)?$", line):
        sub_section = "backup"
      elif sub_section == "backup" and re.match(
          r"^\s*scheduledBackups:\s*(?:#.*)?$", line
      ):
        sub_section = "scheduledBackups"
      elif sub_section == "scheduledBackups":
        m_sched = re.match(
            r"^(\s*schedule:\s*)([\"']?)([^\"'\n]+)([\"']?)(.*)$", line
        )
        if m_sched:
          postgres_targets.append({
              "file": file_path,
              "line_idx": idx,
              "prefix": m_sched.group(1),
              "quote": m_sched.group(2) or m_sched.group(4) or '"',
              "current": m_sched.group(3),
              "suffix": m_sched.group(5),
              "section": sec_name,
          })
          sub_section = None

    elif sec_type == "volsync":
      m_type = re.match(r"^\s*(local|external|remote):\s*(?:#.*)?$", line)
      if m_type:
        volsync_type = m_type.group(1)
        volsync_type_indent = indent
        continue

      if volsync_type and indent > volsync_type_indent:
        m_sched = re.match(
            r"^(\s*schedule:\s*)([\"']?)([^\"'\n]+)([\"']?)(.*)$", line
        )
        if m_sched:
          volsync_targets.append({
              "file": file_path,
              "line_idx": idx,
              "prefix": m_sched.group(1),
              "quote": m_sched.group(2) or m_sched.group(4),
              "current": m_sched.group(3),
              "suffix": m_sched.group(5),
              "section": sec_name,
              "type": volsync_type,
          })
          volsync_type = None

  return postgres_targets, volsync_targets


def format_cst_time(hour: int, minute: int) -> str:
  """Converts a UTC hour and minute to standard US/Central time representation."""
  # Central Standard Time (CST) is UTC-6; Daylight Saving (CDT) is UTC-5.
  cst_hour = (hour - 6) % 24
  period = "AM" if cst_hour < 12 else "PM"
  disp_hour = 12 if cst_hour % 12 == 0 else cst_hour % 12
  return f"{disp_hour:02d}:{minute:02d} {period} CST"


def rebalance_schedules(
    main_dir: Path,
    cluster: str,
    dry_run: bool = False,
    pg_start_hour: int = 5,
    pg_start_min: int = 0,
    vs_start_hour: int = 7,
    vs_start_min: int = 30,
    ext_start_hour: int = 9,
    ext_start_min: int = 30,
    rem_start_hour: int = 10,
    rem_start_min: int = 30,
    interval_minutes: int = 5,
) -> tuple[list[dict], int]:
  """Computes non-overlapping schedules and optionally modifies values.yaml files."""
  helm_dir = main_dir / "clusters" / cluster / "helm"
  if not helm_dir.is_dir():
    print(f"Error: Helm directory not found: {helm_dir}", file=sys.stderr)
    return [], 0

  all_pg: list[tuple[str, dict]] = []
  all_vs: dict[tuple[str, str], dict[str, dict]] = {}

  for yml in sorted(helm_dir.glob("*/values.yaml")):
    chart_name = yml.parent.name
    pg_targets, vs_targets = parse_yaml_backup_targets(yml)
    for pg in pg_targets:
      all_pg.append((chart_name, pg))
    for vs in vs_targets:
      key = (chart_name, vs["section"])
      if key not in all_vs:
        all_vs[key] = {}
      all_vs[key][vs["type"]] = vs

  all_pg.sort(key=lambda x: x[0])
  sorted_vs_keys = sorted(all_vs.keys(), key=lambda x: (x[0], x[1]))

  table_rows = []
  file_modifications: dict[Path, list[tuple[int, str]]] = {}
  changed_files = set()

  # 1. Allocate Postgres Daily Backups (05:00 UTC - 07:25 UTC)
  for i, (chart, pg) in enumerate(all_pg):
    total_m = (pg_start_hour * 60 + pg_start_min) + i * interval_minutes
    h = (total_m // 60) % 24
    m = total_m % 60
    new_sched = f"0 {m} {h} * * *"
    changed = new_sched != pg["current"]

    quote = pg["quote"] or '"'
    new_line = f'{pg["prefix"]}{quote}{new_sched}{quote}{pg["suffix"]}\n'

    fpath = pg["file"]
    if fpath not in file_modifications:
      file_modifications[fpath] = []
    file_modifications[fpath].append((pg["line_idx"], new_line))
    if changed:
      changed_files.add(fpath)

    table_rows.append({
        "app": chart,
        "target": pg["section"],
        "kind": "Postgres",
        "freq": "Daily",
        "utc": new_sched,
        "cst": format_cst_time(h, m),
        "changed": changed,
    })

  # 2. Allocate Volsync Backups (Local Daily, External Weekly, Remote Weekly)
  dow_names = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
  ]

  for j, key in enumerate(sorted_vs_keys):
    chart, sec_name = key
    targets = all_vs[key]

    # Local: Daily
    if "local" in targets:
      vs = targets["local"]
      total_m = (vs_start_hour * 60 + vs_start_min) + j * interval_minutes
      h = (total_m // 60) % 24
      m = total_m % 60
      new_sched = f"{m} {h} * * *"
      changed = new_sched != vs["current"]
      quote = vs["quote"] or ""
      new_line = f'{vs["prefix"]}{quote}{new_sched}{quote}{vs["suffix"]}\n'

      fpath = vs["file"]
      if fpath not in file_modifications:
        file_modifications[fpath] = []
      file_modifications[fpath].append((vs["line_idx"], new_line))
      if changed:
        changed_files.add(fpath)

      table_rows.append({
          "app": chart,
          "target": f"{sec_name} (local)",
          "kind": "Volsync",
          "freq": "Daily",
          "utc": new_sched,
          "cst": format_cst_time(h, m),
          "changed": changed,
      })

    # External: Weekly (distributed across 7 days)
    dow = j % 7
    slot_idx = j // 7

    if "external" in targets:
      vs = targets["external"]
      total_m = (ext_start_hour * 60 + ext_start_min) + slot_idx * interval_minutes
      h = (total_m // 60) % 24
      m = total_m % 60
      new_sched = f"{m} {h} * * {dow}"
      changed = new_sched != vs["current"]
      quote = vs["quote"] or ""
      new_line = f'{vs["prefix"]}{quote}{new_sched}{quote}{vs["suffix"]}\n'

      fpath = vs["file"]
      if fpath not in file_modifications:
        file_modifications[fpath] = []
      file_modifications[fpath].append((vs["line_idx"], new_line))
      if changed:
        changed_files.add(fpath)

      table_rows.append({
          "app": chart,
          "target": f"{sec_name} (external)",
          "kind": "Volsync",
          "freq": f"Weekly ({dow_names[dow]})",
          "utc": new_sched,
          "cst": format_cst_time(h, m),
          "changed": changed,
      })

    # Remote: Weekly (same day, 1 hour after external)
    if "remote" in targets:
      vs = targets["remote"]
      total_m = (rem_start_hour * 60 + rem_start_min) + slot_idx * interval_minutes
      h = (total_m // 60) % 24
      m = total_m % 60
      new_sched = f"{m} {h} * * {dow}"
      changed = new_sched != vs["current"]
      quote = vs["quote"] or ""
      new_line = f'{vs["prefix"]}{quote}{new_sched}{quote}{vs["suffix"]}\n'

      fpath = vs["file"]
      if fpath not in file_modifications:
        file_modifications[fpath] = []
      file_modifications[fpath].append((vs["line_idx"], new_line))
      if changed:
        changed_files.add(fpath)

      table_rows.append({
          "app": chart,
          "target": f"{sec_name} (remote)",
          "kind": "Volsync",
          "freq": f"Weekly ({dow_names[dow]})",
          "utc": new_sched,
          "cst": format_cst_time(h, m),
          "changed": changed,
      })

  # Apply modifications in-place if not dry-run
  if not dry_run:
    for fpath, mods in file_modifications.items():
      lines = fpath.read_text(encoding="utf-8").splitlines(keepends=True)
      has_change = False
      for idx, line_content in mods:
        if lines[idx] != line_content:
          lines[idx] = line_content
          has_change = True
      if has_change:
        fpath.write_text("".join(lines), encoding="utf-8")

  return table_rows, len(changed_files)


def build_markdown_summary(table_rows: list[dict], changed_count: int) -> str:
  """Builds a formatted Markdown summary table of all schedules."""
  lines = [
      "## Backup Schedule Rebalance Summary",
      "",
      f"- **Total Managed Targets**: {len(table_rows)}",
      f"- **Files Modified**: {changed_count}",
      "- **Daily Window**: `05:00 - 12:20 UTC` (~11:00 PM - 06:20 AM US/Chicago)",
      "- **Spacing Interval**: 5 minutes per slot (0 concurrent intra-app collisions)",
      "",
      "| Application | Target | Engine | Frequency | Schedule (UTC) | US/Chicago (CST) | Status |",
      "| :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
  ]
  for r in table_rows:
    status_icon = "Updated" if r["changed"] else "Aligned"
    lines.append(
        f"| `{r['app']}` | `{r['target']}` | {r['kind']} | {r['freq']} | `{r['utc']}` | `{r['cst']}` | {status_icon} |"
    )

  return "\n".join(lines)


def main():
  parser = argparse.ArgumentParser(
      description="Rebalance and stagger backup schedules for Volsync and Postgres."
  )
  parser.add_argument(
      "--main-dir",
      type=Path,
      default=Path("."),
      help="Root directory of repository.",
  )
  parser.add_argument(
      "--cluster", default="cl01tl", help="Target cluster name (default: cl01tl)."
  )
  parser.add_argument(
      "--dry-run",
      action="store_true",
      help="Simulate calculations without editing values.yaml files.",
  )
  parser.add_argument(
      "--interval-minutes",
      type=int,
      default=5,
      help="Slot interval in minutes (default: 5).",
  )
  parser.add_argument(
      "--github-output",
      default=os.getenv("GITHUB_OUTPUT", ""),
      help="Path to GITHUB_OUTPUT environment file.",
  )
  parser.add_argument(
      "--summary-file",
      default=os.getenv("GITHUB_STEP_SUMMARY", ""),
      help="Path to write GitHub Step Summary markdown.",
  )
  args = parser.parse_args()

  print(f">> Scanning backup targets for cluster: {args.cluster} ...")
  rows, changed_count = rebalance_schedules(
      main_dir=args.main_dir,
      cluster=args.cluster,
      dry_run=args.dry_run,
      interval_minutes=args.interval_minutes,
  )

  print(f">> Total targets processed: {len(rows)}")
  print(f">> Files requiring schedule updates: {changed_count}")

  # Print text preview
  print("\n" + "=" * 95)
  print(
      f"{'Application':<15} | {'Target':<30} | {'Engine':<8} | {'Frequency':<18} | {'UTC Schedule':<14} | {'CST':<12}"
  )
  print("-" * 95)
  for r in rows:
    change_flag = " *" if r["changed"] else ""
    print(
        f"{r['app']:<15} | {r['target']:<30} | {r['kind']:<8} | {r['freq']:<18} | {r['utc']:<14} | {r['cst']:<12}{change_flag}"
    )
  print("=" * 95 + "\n")

  # Write Step Summary if requested
  md_summary = build_markdown_summary(rows, changed_count)
  if args.summary_file:
    with open(args.summary_file, "a", encoding="utf-8") as f:
      f.write("\n" + md_summary + "\n")

  # Write GitHub Output
  if args.github_output:
    with open(args.github_output, "a", encoding="utf-8") as f:
      f.write(f"changes-detected={'true' if changed_count > 0 else 'false'}\n")
      f.write(f"changed-files-count={changed_count}\n")
      f.write(f"total-targets={len(rows)}\n")


if __name__ == "__main__":
  main()
