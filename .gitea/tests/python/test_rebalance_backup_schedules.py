"""Tests for .gitea/scripts/rebalance-backup-schedules.py."""

from __future__ import annotations

import collections
import textwrap
from pathlib import Path

import pytest
from conftest import load_script, parse_github_output

rbs = load_script("rebalance-backup-schedules.py")


# ── helpers ──────────────────────────────────────────────────────────


def write_values(root: Path, chart: str, content: str, cluster: str = "c1") -> Path:
    path = root / "clusters" / cluster / "helm" / chart / "values.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")
    return path


PG_VALUES = """
postgres-18-cluster:
  mode: standalone
  backup:
    objectStore:
      index: 1
    scheduledBackups:
      suspend: false
      schedule: "0 25 15 * * *"  # keep me
other:
  schedule: "1 1 1 1 1"
"""

VS_VALUES = """
volsync-target-data:
  pvcTarget: app-data
  a:
    enabled: true
    schedule: 1 1 * * *
  c:
    enabled: true
    schedule: '2 2 * * 0'
  d:
    enabled: true
    schedule: 3 3 * * 0
volsync-target-config:
  a:
    schedule: 4 4 * * *
"""

S3_VALUES = """
s3-bucket:
  enabled: true
  bucketName: assets
  backups:
    a:
      enabled: true
      cronJob:
        schedule: "9 9 * * *"
      destination:
        bucketName: assets
    c:
      cronJob:
        schedule: "9 9 * * 0"
    d:
      cronJob:
        schedule: "9 9 * * 0"
    extra_tier:
      cronJob:
        schedule: "9 9 * * *"
  unrelated:
    schedule: "nope"
"""


def slot_occupancy(rows: list[dict]) -> dict[tuple[int, int], list[dict]]:
    """Map (day-of-week, minute-of-day) -> rows scheduled in that slot."""
    occ: dict[tuple[int, int], list[dict]] = collections.defaultdict(list)
    for r in rows:
        fields = r["utc"].split()
        if r["kind"] == "Postgres":  # CNPG cron has a leading seconds field
            fields = fields[1:]
        minute, hour, _, _, dow = fields
        days = range(7) if dow == "*" else [int(dow)]
        for d in days:
            occ[(d, int(hour) * 60 + int(minute))].append(r)
    return occ


def pg_vs_storage_collisions(rows: list[dict]) -> list:
    return [
        sorted(f"{r['app']}:{r['target']}" for r in v)
        for v in slot_occupancy(rows).values()
        if {"Postgres"} < {r["kind"] for r in v}
    ]


def intra_app_collisions(rows: list[dict]) -> list:
    found = []
    for slot, v in slot_occupancy(rows).items():
        counts = collections.Counter(r["app"] for r in v)
        for app, n in counts.items():
            if n > 1:
                found.append((slot, sorted(r["target"] for r in v if r["app"] == app)))
    return found


# ── parse_yaml_backup_targets ───────────────────────────────────────


def test_parse_postgres_target(tmp_path: Path):
    f = write_values(tmp_path, "app", PG_VALUES)
    pg, vs, s3 = rbs.parse_yaml_backup_targets(f)
    assert vs == [] and s3 == []
    assert len(pg) == 1
    t = pg[0]
    assert t["section"] == "postgres-18-cluster"
    assert t["current"] == "0 25 15 * * *"
    assert t["quote"] == '"'
    assert t["suffix"] == "  # keep me"
    assert f.read_text().splitlines()[t["line_idx"]].strip().startswith("schedule:")


def test_parse_postgres_requires_scheduled_backups_block(tmp_path: Path):
    f = write_values(
        tmp_path,
        "app",
        """
        postgres-cluster:
          schedule: "0 0 0 * * *"
          backup:
            schedule: "0 0 0 * * *"
        """,
    )
    pg, _, _ = rbs.parse_yaml_backup_targets(f)
    assert pg == []


def test_parse_volsync_targets_tiers_and_quotes(tmp_path: Path):
    f = write_values(tmp_path, "app", VS_VALUES)
    _, vs, _ = rbs.parse_yaml_backup_targets(f)
    got = {(t["section"], t["type"]): (t["current"], t["quote"]) for t in vs}
    assert got == {
        ("volsync-target-data", "a"): ("1 1 * * *", ""),
        ("volsync-target-data", "c"): ("2 2 * * 0", "'"),
        ("volsync-target-data", "d"): ("3 3 * * 0", ""),
        ("volsync-target-config", "a"): ("4 4 * * *", ""),
    }


def test_parse_s3_targets_ignores_schedules_outside_backups(tmp_path: Path):
    f = write_values(tmp_path, "app", S3_VALUES)
    _, _, s3 = rbs.parse_yaml_backup_targets(f)
    assert [t["target"] for t in s3] == ["a", "c", "d", "extra_tier"]
    assert all(t["current"].startswith("9 9") for t in s3)


def test_parse_skips_unmanaged_marker(tmp_path: Path):
    f = write_values(tmp_path, "app", "# backup-rebalancer: unmanaged\n" + PG_VALUES)
    assert rbs.parse_yaml_backup_targets(f) == ([], [], [])


def test_parse_skips_gitea_chart(tmp_path: Path):
    f = write_values(tmp_path, "gitea", PG_VALUES)
    assert rbs.parse_yaml_backup_targets(f) == ([], [], [])


def test_parse_section_ends_at_next_top_level_key(tmp_path: Path):
    f = write_values(
        tmp_path,
        "app",
        """
        volsync-target-data:
          a:
            enabled: true
        unrelated:
          a:
            schedule: 1 1 * * *
        """,
    )
    _, vs, _ = rbs.parse_yaml_backup_targets(f)
    assert vs == []


def test_parse_comment_lines_do_not_close_section(tmp_path: Path):
    f = write_values(
        tmp_path,
        "app",
        """
        volsync-target-data:
        # a comment at column 0
          a:
            schedule: 1 1 * * *
        """,
    )
    _, vs, _ = rbs.parse_yaml_backup_targets(f)
    assert len(vs) == 1


# ── format_cst_time ─────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("hour", "minute", "expected"),
    [
        (6, 0, "12:00 AM CST"),
        (5, 0, "11:00 PM CST"),
        (18, 0, "12:00 PM CST"),
        (12, 20, "06:20 AM CST"),
        (0, 5, "06:05 PM CST"),
    ],
)
def test_format_cst_time(hour: int, minute: int, expected: str):
    assert rbs.format_cst_time(hour, minute) == expected


# ── rebalance_schedules ─────────────────────────────────────────────


def test_rebalance_missing_helm_dir_returns_empty(tmp_path: Path, capsys):
    rows, changed = rbs.rebalance_schedules(tmp_path, "nope")
    assert (rows, changed) == ([], 0)
    assert "Helm directory not found" in capsys.readouterr().err


def test_rebalance_postgres_slots_are_sequential_and_sorted(tmp_path: Path):
    for chart in ("zeta", "alpha", "mid"):
        write_values(tmp_path, chart, PG_VALUES)
    rows, changed = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    assert [(r["app"], r["utc"]) for r in rows] == [
        ("alpha", "0 0 5 * * *"),
        ("mid", "0 5 5 * * *"),
        ("zeta", "0 10 5 * * *"),
    ]
    assert changed == 3


def test_rebalance_volsync_tiers(tmp_path: Path):
    write_values(tmp_path, "app", VS_VALUES)
    rows, _ = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    got = {r["target"]: (r["utc"], r["freq"]) for r in rows}
    # Sections sorted by name: volsync-target-config (j=0), volsync-target-data (j=1)
    assert got == {
        "volsync-target-config (a)": ("30 7 * * *", "Daily"),
        "volsync-target-data (a)": ("35 7 * * *", "Daily"),
        "volsync-target-data (d)": ("30 9 * * 1", "Weekly (Monday)"),
        "volsync-target-data (c)": ("30 10 * * 1", "Weekly (Monday)"),
    }


def test_rebalance_volsync_weekly_wraps_days_then_slots(tmp_path: Path):
    for i in range(8):
        write_values(
            tmp_path,
            f"app{i}",
            """
            volsync-target:
              d:
                schedule: 0 0 * * 0
            """,
        )
    rows, _ = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    scheds = [r["utc"] for r in rows]
    assert scheds[:7] == [f"30 9 * * {d}" for d in range(7)]
    assert scheds[7] == "35 9 * * 0"


def test_rebalance_s3_tiers(tmp_path: Path):
    write_values(tmp_path, "app", S3_VALUES)
    rows, _ = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    got = {r["target"]: r["utc"] for r in rows}
    assert got == {
        "s3-bucket (d)": "0 2 * * 0",
        "s3-bucket (c)": "30 2 * * 0",
        "s3-bucket (a)": "0 3 * * *",
        "s3-bucket (extra_tier)": "5 3 * * *",
    }


def test_rebalance_dry_run_does_not_write(tmp_path: Path):
    f = write_values(tmp_path, "app", PG_VALUES)
    before = f.read_text()
    _, changed = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    assert changed == 1
    assert f.read_text() == before


def test_rebalance_writes_preserving_quotes_comments_and_other_lines(tmp_path: Path):
    f_pg = write_values(tmp_path, "app", PG_VALUES)
    f_vs = write_values(tmp_path, "vs", VS_VALUES)
    rbs.rebalance_schedules(tmp_path, "c1")

    pg_text = f_pg.read_text()
    assert '      schedule: "0 0 5 * * *"  # keep me\n' in pg_text
    assert 'schedule: "1 1 1 1 1"' in pg_text  # untouched non-backup key

    vs_lines = f_vs.read_text().splitlines()
    assert "    schedule: 30 7 * * *" in vs_lines  # unquoted stays unquoted
    assert "    schedule: '30 10 * * 1'" in vs_lines  # single quotes preserved
    assert len(vs_lines) == len(textwrap.dedent(VS_VALUES).strip().splitlines())


def test_rebalance_is_idempotent(tmp_path: Path):
    write_values(tmp_path, "app", PG_VALUES)
    write_values(tmp_path, "vs", VS_VALUES)
    write_values(tmp_path, "s3", S3_VALUES)
    _, first = rbs.rebalance_schedules(tmp_path, "c1")
    rows, second = rbs.rebalance_schedules(tmp_path, "c1")
    assert first == 3
    assert second == 0
    assert not any(r["changed"] for r in rows)


def test_rebalance_custom_interval(tmp_path: Path):
    write_values(tmp_path, "a", PG_VALUES)
    write_values(tmp_path, "b", PG_VALUES)
    rows, _ = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True, interval_minutes=15)
    assert [r["utc"] for r in rows] == ["0 0 5 * * *", "0 15 5 * * *"]


def test_rebalance_small_fleet_has_no_collisions(tmp_path: Path):
    for i in range(10):
        write_values(tmp_path, f"app{i:02d}", PG_VALUES + VS_VALUES + S3_VALUES)
    rows, _ = rbs.rebalance_schedules(tmp_path, "c1", dry_run=True)
    assert pg_vs_storage_collisions(rows) == []
    assert intra_app_collisions(rows) == []


# ── build_markdown_summary ──────────────────────────────────────────


def test_build_markdown_summary():
    rows = [
        {
            "app": "a",
            "target": "t",
            "kind": "Postgres",
            "freq": "Daily",
            "utc": "0 0 5 * * *",
            "cst": "11:00 PM CST",
            "changed": True,
        },
        {
            "app": "b",
            "target": "u",
            "kind": "Volsync",
            "freq": "Daily",
            "utc": "30 7 * * *",
            "cst": "01:30 AM CST",
            "changed": False,
        },
    ]
    md = rbs.build_markdown_summary(rows, 1)
    assert "- **Total Managed Targets**: 2" in md
    assert "- **Files Modified**: 1" in md
    assert (
        "| `a` | `t` | Postgres | Daily | `0 0 5 * * *` | `11:00 PM CST` | Updated |"
        in md
    )
    assert md.splitlines()[-1].endswith("| Aligned |")


# ── main (CLI) ──────────────────────────────────────────────────────


def test_main_writes_outputs_and_summary(tmp_path: Path, monkeypatch, github_output):
    write_values(tmp_path, "app", PG_VALUES)
    summary = tmp_path / "summary.md"
    monkeypatch.setattr(
        "sys.argv",
        [
            "rebalance",
            "--main-dir",
            str(tmp_path),
            "--cluster",
            "c1",
            "--summary-file",
            str(summary),
        ],
    )
    rbs.main()
    out = parse_github_output(github_output)
    assert out == {
        "changes-detected": "true",
        "changed-files-count": "1",
        "total-targets": "1",
    }
    assert "Backup Schedule Rebalance Summary" in summary.read_text()


def test_main_no_changes(tmp_path: Path, monkeypatch, github_output):
    write_values(tmp_path, "app", PG_VALUES)
    rbs.rebalance_schedules(tmp_path, "c1")
    monkeypatch.setattr(
        "sys.argv", ["rebalance", "--main-dir", str(tmp_path), "--cluster", "c1"]
    )
    rbs.main()
    assert parse_github_output(github_output)["changes-detected"] == "false"


def test_main_missing_helm_dir_exits_non_zero(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(
        "sys.argv", ["rebalance", "--main-dir", str(tmp_path), "--cluster", "nope"]
    )
    with pytest.raises(SystemExit) as exc:
        rbs.main()
    assert exc.value.code == 1


def test_main_rejects_non_positive_interval(tmp_path: Path, monkeypatch):
    write_values(tmp_path, "app", PG_VALUES)
    monkeypatch.setattr(
        "sys.argv",
        [
            "rebalance",
            "--main-dir",
            str(tmp_path),
            "--cluster",
            "c1",
            "--interval-minutes",
            "0",
        ],
    )
    with pytest.raises(SystemExit) as exc:
        rbs.main()
    assert exc.value.code == 1


# ── invariants against the real repository ─────────────────────────


@pytest.fixture(scope="module")
def real_rows(project_root: Path) -> list[dict]:
    if not (project_root / "clusters" / "cl01tl" / "helm").is_dir():
        pytest.skip("cl01tl helm directory not present")
    rows, _ = rbs.rebalance_schedules(project_root, "cl01tl", dry_run=True)
    return rows


def test_real_repo_has_backup_targets(real_rows: list[dict]):
    assert real_rows, "expected the rebalancer to discover backup targets"


def test_real_repo_schedules_are_valid_cron(real_rows: list[dict]):
    for r in real_rows:
        fields = r["utc"].split()
        assert len(fields) == (6 if r["kind"] == "Postgres" else 5), r


@pytest.mark.xfail(
    strict=True,
    reason=(
        "Known bug: Postgres slots start at 05:00 and VolSync daily at 07:30 with a "
        "fixed 5 min interval, so >30 Postgres clusters overflow into the VolSync "
        "window. Remove this marker once the windows are derived dynamically."
    ),
)
def test_real_repo_no_postgres_vs_storage_collisions(real_rows: list[dict]):
    assert pg_vs_storage_collisions(real_rows) == []


@pytest.mark.xfail(
    strict=True,
    reason=(
        "Known bug: with enough VolSync targets the daily (a) window reaches the "
        "weekly (c)/(d) windows, so the same PVC can get two movers in one slot."
    ),
)
def test_real_repo_no_intra_app_collisions(real_rows: list[dict]):
    assert intra_app_collisions(real_rows) == []
