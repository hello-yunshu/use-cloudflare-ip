#!/usr/bin/env python3
"""Validate Cloudflare IP's immutable qualified Rill Runtime contract."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from urllib.request import Request, urlopen
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts/rill-runtime.json"
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SEMVER = re.compile(r"^1\.\d+\.\d+$")


def check(package_dir: Path | None) -> list[str]:
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    errors: list[str] = []
    if data.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if data.get("policy") != {"major": 1, "track": "latest-qualified-stable"}:
        errors.append("policy must be latest-qualified-stable major 1")
    resolved = data.get("resolved", {})
    package = data.get("openwrtPackage", {})
    qualification = data.get("qualification", {})
    version = resolved.get("version")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        errors.append("resolved.version must be Stable 1.x")
    if resolved.get("tag") != f"v{version}":
        errors.append("resolved.tag must match resolved.version")
    if not SHA1.fullmatch(str(resolved.get("upstreamCommit", ""))):
        errors.append("resolved.upstreamCommit must be SHA-1")
    if not SHA256.fullmatch(str(resolved.get("sourceArchiveSha256", ""))):
        errors.append("resolved.sourceArchiveSha256 must be SHA-256")
    if package.get("repository") != "hello-yunshu/rill-openwrt-packages":
        errors.append("openwrtPackage.repository is not canonical")
    if not SHA1.fullmatch(str(package.get("commit", ""))):
        errors.append("openwrtPackage.commit must be immutable")
    if package.get("package") != "rill-runtime" or package.get("packageVersion") != version:
        errors.append("Runtime package identity drifted")
    if package.get("binary") != "/usr/bin/rill-runtime":
        errors.append("canonical Runtime binary drifted")
    if qualification.get("required") is not True or qualification.get("verdict") != "PASS":
        errors.append("qualification is not required and PASS")
    if package_dir:
        makefile = package_dir / "package/rill-runtime/Makefile"
        metadata = package_dir / "metadata/rill-runtime.json"
        if not makefile.is_file() or not metadata.is_file():
            errors.append("package checkout is missing Runtime metadata")
        else:
            make = makefile.read_text(encoding="utf-8")
            meta = json.loads(metadata.read_text(encoding="utf-8"))
            upstream = meta.get("upstream", {})
            if f"PKG_VERSION:={version}" not in make or upstream.get("version") != version:
                errors.append("package version does not match contract")
            if upstream.get("commit") != resolved.get("upstreamCommit"):
                errors.append("package upstream commit does not match contract")
            if upstream.get("archiveSha256") != resolved.get("sourceArchiveSha256"):
                errors.append("package source hash does not match contract")
            try:
                head = subprocess.run(["git", "-C", str(package_dir), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
                if head != package.get("commit"):
                    errors.append("package checkout HEAD does not match contract")
            except (OSError, subprocess.CalledProcessError) as error:
                errors.append(f"cannot resolve package checkout HEAD: {error}")
    return errors


def api(path: str):
    request = Request(f"https://api.github.com/{path}", headers={"Accept": "application/vnd.github+json", "User-Agent": "cloudflare-ip-rill-sync"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def sync(package_dir: Path) -> int:
    releases = api("repos/hello-yunshu/rill-ml/releases?per_page=100")
    stable = [r for r in releases if not r.get("draft") and not r.get("prerelease") and SEMVER.fullmatch(str(r.get("tag_name", ""))[1:])]
    if not stable:
        raise RuntimeError("no published Stable Rill 1.x release")
    latest = max(stable, key=lambda r: tuple(int(x) for x in r["tag_name"][1:].split(".")))
    metadata = json.loads((package_dir / "metadata/rill-runtime.json").read_text(encoding="utf-8"))
    upstream = metadata.get("upstream", {})
    version = str(latest["tag_name"])[1:]
    if upstream.get("version") != version:
        print(f"WAIT: package qualification is not ready for latest Stable {version}; package has {upstream.get('version')}")
        return 0
    package_commit = subprocess.run(["git", "-C", str(package_dir), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    runs = api(f"repos/hello-yunshu/rill-openwrt-packages/actions/workflows/qualify.yml/runs?head_sha={package_commit}&status=completed&per_page=100").get("workflow_runs", [])
    passed = next((run for run in runs if run.get("conclusion") == "success"), None)
    if not passed:
        print(f"WAIT: no successful qualify.yml run for package commit {package_commit}")
        return 0
    contract = {"schemaVersion": 1, "policy": {"major": 1, "track": "latest-qualified-stable"}, "resolved": {"version": version, "tag": latest["tag_name"], "upstreamCommit": upstream["commit"], "sourceArchiveSha256": upstream["archiveSha256"]}, "openwrtPackage": {"repository": "hello-yunshu/rill-openwrt-packages", "commit": package_commit, "package": "rill-runtime", "packageVersion": version, "packageRelease": metadata["package"]["release"], "binary": "/usr/bin/rill-runtime"}, "qualification": {"required": True, "workflow": "qualify.yml", "runId": passed["id"], "verdict": "PASS"}}
    CONTRACT.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(contract, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-dir", type=Path)
    parser.add_argument("--sync", action="store_true", help="resolve latest qualified Stable 1.x and update the contract")
    args = parser.parse_args()
    if args.sync:
        if not args.package_dir:
            parser.error("--sync requires --package-dir")
        try:
            return sync(args.package_dir)
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1
    errors = check(args.package_dir)
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    print(f"PASS: qualified rill-runtime {data['resolved']['version']} from {data['openwrtPackage']['commit']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
