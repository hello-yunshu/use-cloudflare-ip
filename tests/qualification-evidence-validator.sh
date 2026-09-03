#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
commit=0123456789abcdef0123456789abcdef01234567
python3 - "$TMP/manifest.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
manifest = {
  "schemaVersion": 1, "commit": commit, "runId": "42", "jobs": {}, "artifacts": [],
  "assetFiles": [{"name": "a.ipk", "sha256": "a" * 64}],
  "qualificationState": "automated-qualification", "releaseEligible": True,
  "rill": {
    "schemaVersion": 1,
    "package": {"repository": "hello-yunshu/rill-openwrt-packages", "commit": "b" * 40, "qualificationRunId": 7, "qualificationManifestSha256": "c" * 64},
    "stablePackageQualification": "PASS", "previewRuntimeIntegration": "PASS",
    "stableCommit": "d" * 40, "previewCommit": "e" * 40,
    "runtime": {"version": "1.5.6", "tag": "preview-exact-commit", "commit": "e" * 40, "sourceArchiveSha256": "not-applicable-preview", "binarySha256": "f" * 64},
    "integration": {"status": "pass", "sameRelease": True}
  }
}
json.dump(manifest, open(path, "w"))
PY
python3 "$ROOT/scripts/validate-qualification-evidence.py" "$TMP/manifest.json" --commit "$commit" --require-assets 1
python3 - "$TMP/manifest.json" <<'PY'
import json, sys
path=sys.argv[1]; data=json.load(open(path)); data["rill"]["integration"]["sameRelease"]=False; json.dump(data, open(path,"w"))
PY
if python3 "$ROOT/scripts/validate-qualification-evidence.py" "$TMP/manifest.json" --commit "$commit"; then
  echo 'validator accepted sameRelease=false' >&2
  exit 1
fi
echo 'shared qualification evidence validator passed'
