# Qualification evidence

The exact qualification source of truth is the CI artifact `qualification.json`, generated for each run from `GITHUB_SHA`, `GITHUB_RUN_ID`, required job results, and uploaded artifact metadata. This document is intentionally not a hand-maintained copy of a historical SHA or run.

## Automated qualification

- State: generated per exact SHA; only `releaseEligible: true` with `qualificationState: automated-qualification` may trigger promotion.
- Required gates: host, legacy, RPC/LuCI, workflow lint, same-release generic Rill consumer integration, OpenWrt 24.10.5 IPK, OpenWrt 25.12.0 APK, behavior rollback tests, package content contract, real CFST smoke, and release asset contract. Generic Runtime package qualification is authoritative from the exact successful run and `qualification.json` in `rill-openwrt-packages`; the Preview artifact is extracted from that package matrix and is the binary used by consumer integration.
- Release workflow: `workflow_run` from successful CI on `main`; it verifies the manifest commit equals the release SHA before collecting assets.
- 2.1 RC evidence: final candidate CI run `33745358580` passed on exact RC head `f459f8b3d095a6967066aa7b524d028a4a1f8e8d`. Package main provenance is `64ee22f978ed8f8ed19bb675700678f57eec19e3`, qualified by package run `33735123909`.

## Explicit device boundary

| Evidence | State |
|---|---|
| Real OpenWrt device runtime | `NOT_EVALUATED` unless separately recorded |
| Real PassWall versions | `NOT_EVALUATED` unless separately recorded |
| Real OpenClash versions | `NOT_EVALUATED` unless separately recorded |
| Hardware coverage | `NOT_EVALUATED` unless separately recorded |
| 24-hour soak | `NOT_EVALUATED` |

Docker, SDK, QEMU, package inspection, and real CFST tool execution do not substitute for those device-level gates.
