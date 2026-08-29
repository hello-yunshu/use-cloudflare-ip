# Qualification evidence

The exact qualification source of truth is the CI artifact `qualification.json`, generated for each run from `GITHUB_SHA`, `GITHUB_RUN_ID`, required job results, and uploaded artifact metadata. This document is intentionally not a hand-maintained copy of a historical SHA or run.

## Automated qualification

- State: generated per exact SHA; only `releaseEligible: true` with `qualificationState: automated-qualification` may trigger promotion.
- Required gates: host, legacy, RPC/LuCI, workflow lint, same-release generic Rill consumer integration, OpenWrt 24.10.5 IPK, OpenWrt 25.12.0 APK, behavior rollback tests, package content contract, real CFST smoke, and release asset contract. Generic Runtime package qualification is authoritative from the exact successful run and `qualification.json` in `rill-openwrt-packages`.
- Release workflow: `workflow_run` from successful CI on `main`; it verifies the manifest commit equals the release SHA before collecting assets.

## Explicit device boundary

| Evidence | State |
|---|---|
| Real OpenWrt device runtime | `NOT_EVALUATED` unless separately recorded |
| Real PassWall versions | `NOT_EVALUATED` unless separately recorded |
| Real OpenClash versions | `NOT_EVALUATED` unless separately recorded |
| Hardware coverage | `NOT_EVALUATED` unless separately recorded |
| 24-hour soak | `NOT_EVALUATED` |

Docker, SDK, QEMU, package inspection, and real CFST tool execution do not substitute for those device-level gates.
