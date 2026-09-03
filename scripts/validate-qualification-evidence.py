#!/usr/bin/env python3
"""Single qualification predicate shared by CI evidence and release promotion."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HEX40 = re.compile(r"^[0-9a-fA-F]{40}$")
HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")


def fail(message: str) -> int:
    print(f"qualification evidence invalid: {message}", file=sys.stderr)
    return 1


def require(value: object, condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate(manifest: dict, expected_commit: str | None, require_assets: int | None) -> None:
    require(manifest, isinstance(manifest, dict), "manifest must be an object")
    require(manifest.get("schemaVersion"), manifest.get("schemaVersion") == 1, "schemaVersion must be 1")
    commit = manifest.get("commit")
    require(commit, isinstance(commit, str) and bool(HEX40.fullmatch(commit)), "commit must be a 40-digit SHA")
    if expected_commit is not None:
        require(commit, commit == expected_commit, "manifest commit does not match expected exact SHA")
    eligible = manifest.get("releaseEligible")
    require(eligible, isinstance(eligible, bool), "releaseEligible must be boolean")
    require(manifest.get("qualificationState"), isinstance(manifest.get("qualificationState"), str), "qualificationState missing")
    if not eligible:
        return
    require(manifest.get("qualificationState"), manifest["qualificationState"] == "automated-qualification", "qualificationState is not automated-qualification")
    rill = manifest.get("rill")
    require(rill, isinstance(rill, dict), "rill evidence missing")
    require(rill.get("schemaVersion"), rill.get("schemaVersion") == 1, "rill schemaVersion must be 1")
    package = rill.get("package")
    require(package, isinstance(package, dict), "package evidence missing")
    require(package.get("repository"), package.get("repository") == "hello-yunshu/rill-openwrt-packages", "wrong package repository")
    require(package.get("commit"), isinstance(package.get("commit"), str) and bool(HEX40.fullmatch(package["commit"])), "wrong package commit")
    require(package.get("qualificationRunId"), isinstance(package.get("qualificationRunId"), int), "qualification run id missing")
    require(package.get("qualificationManifestSha256"), isinstance(package.get("qualificationManifestSha256"), str) and bool(HEX64.fullmatch(package["qualificationManifestSha256"])), "wrong qualification manifest digest")
    require(rill.get("stablePackageQualification"), rill.get("stablePackageQualification") == "PASS", "Stable package qualification is not PASS")
    require(rill.get("previewRuntimeIntegration"), rill.get("previewRuntimeIntegration") == "PASS", "Preview Runtime integration is not PASS")
    for field in ("stableCommit", "previewCommit"):
        require(field, isinstance(rill.get(field), str) and bool(HEX40.fullmatch(rill[field])), f"wrong {field}")
    require("stableCommit", rill["stableCommit"] != rill["previewCommit"], "Stable and Preview commits must differ")
    runtime = rill.get("runtime")
    require(runtime, isinstance(runtime, dict), "runtime evidence missing")
    require(runtime.get("version"), isinstance(runtime.get("version"), str), "runtime version missing")
    require(runtime.get("tag"), isinstance(runtime.get("tag"), str), "runtime tag missing")
    require(runtime.get("commit"), isinstance(runtime.get("commit"), str) and bool(HEX40.fullmatch(runtime["commit"])), "wrong runtime commit")
    archive = runtime.get("sourceArchiveSha256")
    require(archive, archive == "not-applicable-preview" or (isinstance(archive, str) and bool(HEX64.fullmatch(archive))), "wrong source archive digest")
    require(runtime.get("binarySha256"), isinstance(runtime.get("binarySha256"), str) and bool(HEX64.fullmatch(runtime["binarySha256"])), "wrong Runtime binary digest")
    integration = rill.get("integration")
    require(integration, isinstance(integration, dict), "integration evidence missing")
    require(integration.get("status"), integration.get("status") == "pass", "integration status is not pass")
    require(integration.get("sameRelease"), integration.get("sameRelease") is True, "sameRelease must be true")
    assets = manifest.get("assetFiles")
    require(assets, isinstance(assets, list), "assetFiles must be an array")
    if require_assets is not None:
        require(assets, len(assets) == require_assets, f"expected {require_assets} release assets")
    for asset in assets:
        require(asset, isinstance(asset, dict) and isinstance(asset.get("sha256"), str) and bool(HEX64.fullmatch(asset["sha256"])), "missing asset digest")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--require-assets", type=int)
    args = parser.parse_args()
    try:
        data = json.loads(args.manifest.read_text(encoding="utf-8"))
        validate(data, args.commit, args.require_assets)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        return fail(str(exc))
    print(f"qualification evidence valid: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
