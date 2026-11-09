"""Unit tests for .mise/lib/crd_schema_cache.py."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

PROJECT_ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = PROJECT_ROOT / ".mise" / "lib" / "crd_schema_cache.py"


def _load_crd_schema_cache() -> ModuleType:
    spec = importlib.util.spec_from_file_location("crd_schema_cache", MODULE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["crd_schema_cache"] = module
    spec.loader.exec_module(module)
    return module


crd_cache = _load_crd_schema_cache()


def test_parse_openapi_index(tmp_path: Path) -> None:
    index_file = tmp_path / "openapi.txt"
    index_file.write_text(
        "/openapi/v3/api/v1?hash=core1\n"
        "/openapi/v3/apis/monitoring.coreos.com/v1?hash=prom1\n"
        "/openapi/v3/apis/postgresql.cnpg.io/v1?hash=cnpg1\n",
        encoding="utf-8",
    )
    result = crd_cache.parse_openapi_index(index_file)
    assert result == {
        "monitoring.coreos.com/v1": "/openapi/v3/apis/monitoring.coreos.com/v1?hash=prom1",
        "postgresql.cnpg.io/v1": "/openapi/v3/apis/postgresql.cnpg.io/v1?hash=cnpg1",
    }


def test_build_fetch_plan_identifies_cached_and_changed_crds(tmp_path: Path) -> None:
    schema_dir = tmp_path / "schemas"
    schema_dir.mkdir()
    (schema_dir / "alpha_v1.json").write_text("{}", encoding="utf-8")
    (schema_dir / "beta_v1.json").write_text("{}", encoding="utf-8")

    index_file = tmp_path / "openapi.txt"
    index_file.write_text(
        "/openapi/v3/apis/alpha.io/v1?hash=h_alpha\n/openapi/v3/apis/beta.io/v1?hash=h_beta_new\n",
        encoding="utf-8",
    )
    gv_hashes = crd_cache.parse_openapi_index(index_file)
    alpha_gv_hash = crd_cache.compute_gv_hash("alpha.io", ["v1"], "10", gv_hashes)

    manifest_file = schema_dir / ".crd-manifest.json"
    manifest_file.write_text(
        json.dumps(
            {
                "alphas.alpha.io": {
                    "hash": "spec_hash_alpha",
                    "gv_hash": alpha_gv_hash,
                    "files": ["alpha_v1.json"],
                },
                "betas.beta.io": {
                    "hash": "spec_hash_beta",
                    "gv_hash": "old_beta_gv_hash",
                    "files": ["beta_v1.json"],
                },
                "deleted.old.io": {
                    "hash": "spec_hash_old",
                    "gv_hash": "old_gv_hash",
                    "files": ["deleted_v1.json"],
                },
            }
        ),
        encoding="utf-8",
    )

    meta_file = tmp_path / "meta.txt"
    meta_file.write_text(
        "alphas.alpha.io\talpha.io\tAlpha\tv1,\t10\nbetas.beta.io\tbeta.io\tBeta\tv1,\t20\n",
        encoding="utf-8",
    )

    plan_file = tmp_path / "plan.json"
    plan = crd_cache.build_fetch_plan(
        meta_file,
        index_file,
        schema_dir,
        manifest_file,
        plan_file,
    )

    assert plan is not None
    assert plan["total"] == 2
    assert [c["name"] for c in plan["unchanged"]] == ["alphas.alpha.io"]
    assert [c["name"] for c in plan["to_fetch"]] == ["betas.beta.io"]
    assert plan["removed"] == ["deleted.old.io"]


def test_diff_and_update_manifest_prunes_stale_files_and_writes_changed(tmp_path: Path) -> None:
    schema_dir = tmp_path / "schemas"
    schema_dir.mkdir()
    (schema_dir / "alpha_v1.json").write_text("{}", encoding="utf-8")
    (schema_dir / "gamma_v1.json").write_text("{}", encoding="utf-8")

    index_file = tmp_path / "openapi.txt"
    index_file.write_text("", encoding="utf-8")

    alpha_spec = {
        "group": "alpha.io",
        "names": {"kind": "Alpha"},
        "versions": [{"name": "v1"}],
    }
    alpha_hash = crd_cache.hashlib.sha256(
        json.dumps(alpha_spec, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    manifest_file = schema_dir / ".crd-manifest.json"
    manifest_file.write_text(
        json.dumps(
            {
                "alphas.alpha.io": {
                    "hash": alpha_hash,
                    "gv_hash": "rv:1",
                    "files": ["alpha_v1.json"],
                },
                "gammas.gamma.io": {
                    "hash": "old_gamma",
                    "gv_hash": "rv:2",
                    "files": ["gamma_v1.json"],
                },
            }
        ),
        encoding="utf-8",
    )

    crd_list_file = tmp_path / "crds.json"
    crd_list_file.write_text(
        json.dumps(
            {
                "apiVersion": "v1",
                "kind": "List",
                "items": [
                    {
                        "metadata": {"name": "alphas.alpha.io", "resourceVersion": "1"},
                        "spec": alpha_spec,
                    },
                    {
                        "metadata": {"name": "betas.beta.io", "resourceVersion": "3"},
                        "spec": {
                            "group": "beta.io",
                            "names": {"kind": "Beta"},
                            "versions": [{"name": "v1"}],
                        },
                    },
                ],
            }
        ),
        encoding="utf-8",
    )

    changed_file = tmp_path / "changed.json"
    new_manifest_file = tmp_path / "new_manifest.json"

    changed, unchanged, removed = crd_cache.diff_and_update_manifest(
        crd_list_file,
        index_file,
        schema_dir,
        manifest_file,
        changed_file,
        new_manifest_file,
        needs_full_list=True,
    )

    assert (changed, unchanged, removed) == (1, 1, 1)
    assert not (schema_dir / "gamma_v1.json").exists()
    changed_doc = json.loads(changed_file.read_text(encoding="utf-8"))
    assert len(changed_doc["items"]) == 1
    assert changed_doc["items"][0]["metadata"]["name"] == "betas.beta.io"


def test_normalize_crd_list_wraps_single_resource(tmp_path: Path) -> None:
    single_file = tmp_path / "single.json"
    out_file = tmp_path / "out.json"
    single_file.write_text(
        json.dumps({"apiVersion": "apiextensions.k8s.io/v1", "kind": "CustomResourceDefinition"}),
        encoding="utf-8",
    )
    crd_cache.normalize_crd_list(single_file, out_file)
    result = json.loads(out_file.read_text(encoding="utf-8"))
    assert result["kind"] == "List"
    assert len(result["items"]) == 1
