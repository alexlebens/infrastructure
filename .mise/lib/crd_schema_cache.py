#!/usr/bin/env python3
"""CRD schema cache planning and diffing helper for kube:generate-schemas."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any


def parse_openapi_index(index_path: str | Path) -> dict[str, str]:
    """Parse OpenAPI v3 index lines into a mapping of `<group>/<version>` -> full URL line."""
    gv_hashes: dict[str, str] = {}
    path = Path(index_path)
    if not path.is_file():
        return gv_hashes

    prefix = "/openapi/v3/apis/"
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith(prefix):
            rest = line[len(prefix) :]
            gv = rest.split("?", 1)[0]
            gv_hashes[gv] = line
    return gv_hashes


def load_manifest(manifest_path: str | Path) -> dict[str, dict[str, Any]]:
    """Load the cached `.crd-manifest.json` dictionary if valid."""
    path = Path(manifest_path)
    if not path.is_file():
        return {}
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            return loaded
    except Exception:
        pass
    return {}


def compute_gv_hash(group: str, versions: list[str], rv: str, gv_hashes: dict[str, str]) -> str:
    """Compute a deterministic hash token from OpenAPI v3 group-version hashes or resourceVersion."""
    gv_tokens = [gv_hashes.get(f"{group}/{v}", "") for v in versions]
    if any(gv_tokens):
        token_src = "|".join(gv_tokens)
        return hashlib.sha256(token_src.encode("utf-8")).hexdigest()
    if rv:
        return f"rv:{rv}"
    return ""


def parse_crd_metadata(
    meta_path: str | Path,
    gv_hashes: dict[str, str],
) -> list[dict[str, Any]]:
    """Parse tab-separated CRD metadata lines emitted by `kubectl get crd -o go-template`."""
    path = Path(meta_path)
    if not path.is_file():
        return []

    crds: list[dict[str, Any]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip("\r\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        name, group, kind, versions_csv = parts[0], parts[1], parts[2], parts[3]
        rv = parts[4] if len(parts) > 4 else ""
        versions = [v for v in versions_csv.split(",") if v]
        if not name or not kind or not versions:
            continue
        files = [f"{kind}_{v}.json".lower() for v in versions]
        gv_hash = compute_gv_hash(group, versions, rv, gv_hashes)
        crds.append(
            {
                "name": name,
                "group": group,
                "kind": kind,
                "versions": versions,
                "files": files,
                "gv_hash": gv_hash,
            }
        )
    return crds


def build_fetch_plan(
    meta_path: str | Path,
    index_path: str | Path,
    schema_dir: str | Path,
    manifest_path: str | Path,
    plan_path: str | Path,
) -> dict[str, Any] | None:
    """Determine which CRDs need fetching from the cluster based on OpenAPI v3 hashes and cache state."""
    gv_hashes = parse_openapi_index(index_path)
    crds = parse_crd_metadata(meta_path, gv_hashes)
    if not crds:
        return None

    old_manifest = load_manifest(manifest_path)
    schema_dir_path = Path(schema_dir)

    to_fetch: list[dict[str, Any]] = []
    unchanged: list[dict[str, Any]] = []
    current_names: set[str] = set()

    for crd in crds:
        name = crd["name"]
        current_names.add(name)
        old_entry = old_manifest.get(name)
        files = crd["files"]
        gv_hash = crd["gv_hash"]

        cache_valid = False
        if isinstance(old_entry, dict) and old_entry.get("files") == files and len(files) > 0:
            if gv_hash and old_entry.get("gv_hash") == gv_hash:
                if all((schema_dir_path / fn).is_file() for fn in files):
                    cache_valid = True

        if cache_valid:
            unchanged.append(crd)
        else:
            to_fetch.append(crd)

    removed = [old_name for old_name in old_manifest if old_name not in current_names]

    plan = {
        "total": len(crds),
        "to_fetch": to_fetch,
        "unchanged": unchanged,
        "removed": removed,
    }
    Path(plan_path).write_text(json.dumps(plan, indent=2), encoding="utf-8")
    return plan


def normalize_crd_list(input_path: str | Path, output_path: str | Path) -> None:
    """Ensure a single CustomResourceDefinition JSON document is wrapped in a Kubernetes List."""
    data = json.loads(Path(input_path).read_text(encoding="utf-8"))
    if data.get("kind") != "List":
        data = {"apiVersion": "v1", "kind": "List", "items": [data]}
    Path(output_path).write_text(json.dumps(data), encoding="utf-8")


def _remove_stale_files(schema_dir_path: Path, filenames: set[str] | list[str]) -> None:
    for stale_fn in filenames:
        stale_path = schema_dir_path / stale_fn
        if stale_path.is_file():
            try:
                os.remove(stale_path)
            except OSError:
                pass


def diff_and_update_manifest(
    crd_list_path: str | Path,
    index_path: str | Path,
    schema_dir: str | Path,
    manifest_path: str | Path,
    changed_crd_path: str | Path,
    new_manifest_path: str | Path,
    plan_path: str | Path | None = None,
    needs_full_list: bool = False,
) -> tuple[int, int, int]:
    """Compare fetched CRD specs against the cached manifest, prune stale files, and write changed CRDs."""
    gv_hashes = parse_openapi_index(index_path)
    schema_dir_path = Path(schema_dir)

    try:
        data = json.loads(Path(crd_list_path).read_text(encoding="utf-8"))
    except Exception:
        data = {}

    items = data.get("items") or []
    old_manifest = load_manifest(manifest_path)

    new_manifest: dict[str, dict[str, Any]] = {}
    changed_items: list[dict[str, Any]] = []
    unchanged_count = 0

    if not needs_full_list and plan_path and Path(plan_path).is_file():
        plan = json.loads(Path(plan_path).read_text(encoding="utf-8"))
        for crd in plan.get("unchanged", []):
            name = crd["name"]
            old_entry = old_manifest.get(name, {})
            new_manifest[name] = {
                "hash": old_entry.get("hash", ""),
                "gv_hash": crd.get("gv_hash", old_entry.get("gv_hash", "")),
                "files": crd["files"],
            }
            unchanged_count += 1

    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        meta = item.get("metadata") or {}
        spec = item.get("spec") or {}
        name = meta.get("name") or f"crd-{idx}"
        rv = meta.get("resourceVersion") or ""
        group = spec.get("group") or ""

        kind = (spec.get("names") or {}).get("kind") or ""
        versions = spec.get("versions") or []
        files: list[str] = []
        v_names: list[str] = []
        if kind and isinstance(versions, list):
            for v in versions:
                if isinstance(v, dict) and v.get("name"):
                    v_name = v["name"]
                    v_names.append(v_name)
                    files.append(f"{kind}_{v_name}.json".lower())

        gv_hash = compute_gv_hash(group, v_names, rv, gv_hashes)
        spec_bytes = json.dumps(spec, sort_keys=True, separators=(",", ":")).encode("utf-8")
        spec_hash = hashlib.sha256(spec_bytes).hexdigest()

        old_entry = old_manifest.get(name)
        cache_valid = False
        if (
            isinstance(old_entry, dict)
            and old_entry.get("hash") == spec_hash
            and old_entry.get("files") == files
            and len(files) > 0
        ):
            if all((schema_dir_path / fn).is_file() for fn in files):
                cache_valid = True

        if cache_valid:
            unchanged_count += 1
        else:
            changed_items.append(item)
            if isinstance(old_entry, dict):
                old_files = set(old_entry.get("files") or [])
                _remove_stale_files(schema_dir_path, old_files - set(files))

        new_manifest[name] = {"hash": spec_hash, "gv_hash": gv_hash, "files": files}

    removed_count = 0
    for old_name, old_entry in old_manifest.items():
        if old_name not in new_manifest:
            removed_count += 1
            if isinstance(old_entry, dict):
                _remove_stale_files(schema_dir_path, old_entry.get("files") or [])

    if changed_items:
        out_doc = {
            "apiVersion": data.get("apiVersion", "v1"),
            "kind": data.get("kind", "List"),
            "items": changed_items,
        }
        Path(changed_crd_path).write_text(json.dumps(out_doc), encoding="utf-8")

    Path(new_manifest_path).write_text(
        json.dumps(new_manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return len(changed_items), unchanged_count, removed_count


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="CRD schema cache helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="Compute CRD fetch plan from metadata")
    plan_parser.add_argument("--meta-file", required=True)
    plan_parser.add_argument("--index-file", required=True)
    plan_parser.add_argument("--schema-dir", required=True)
    plan_parser.add_argument("--manifest-file", required=True)
    plan_parser.add_argument("--plan-file", required=True)

    names_parser = subparsers.add_parser("fetch-names", help="Print CRD names to fetch from plan")
    names_parser.add_argument("--plan-file", required=True)

    norm_parser = subparsers.add_parser("normalize-list", help="Wrap single CRD JSON in List")
    norm_parser.add_argument("--input-file", required=True)
    norm_parser.add_argument("--output-file", required=True)

    diff_parser = subparsers.add_parser("diff", help="Diff fetched CRDs and write manifest")
    diff_parser.add_argument("--crd-list-file", required=True)
    diff_parser.add_argument("--index-file", required=True)
    diff_parser.add_argument("--schema-dir", required=True)
    diff_parser.add_argument("--manifest-file", required=True)
    diff_parser.add_argument("--changed-crd-file", required=True)
    diff_parser.add_argument("--new-manifest-file", required=True)
    diff_parser.add_argument("--plan-file", default="")
    diff_parser.add_argument("--needs-full-list", default="false")

    args = parser.parse_args(argv)

    if args.command == "plan":
        plan = build_fetch_plan(
            args.meta_file,
            args.index_file,
            args.schema_dir,
            args.manifest_file,
            args.plan_file,
        )
        if plan is None:
            print("FALLBACK")
        else:
            print(
                f"OK {plan['total']} {len(plan['to_fetch'])} "
                f"{len(plan['unchanged'])} {len(plan['removed'])}"
            )
    elif args.command == "fetch-names":
        plan_data = json.loads(Path(args.plan_file).read_text(encoding="utf-8"))
        for crd in plan_data.get("to_fetch", []):
            print(crd["name"])
    elif args.command == "normalize-list":
        normalize_crd_list(args.input_file, args.output_file)
    elif args.command == "diff":
        changed, unchanged, removed = diff_and_update_manifest(
            args.crd_list_file,
            args.index_file,
            args.schema_dir,
            args.manifest_file,
            args.changed_crd_file,
            args.new_manifest_file,
            plan_path=args.plan_file or None,
            needs_full_list=(args.needs_full_list.lower() == "true"),
        )
        print(f"{changed} {unchanged} {removed}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
