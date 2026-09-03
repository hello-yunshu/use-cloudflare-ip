# Validation plan

## Local gates

Run `git diff --check`, Bash/ash syntax, ShellCheck where available, `node --check`, `jq empty`, PO validation, existing 1.8.3 tests, every `tests/legacy/*.sh`, and every `tests/v2-*.sh`. Contract tests must use fixtures and side effects, not file-existence greps.

## Remote gates

Independent jobs cover host contracts, legacy behavior, RPC/LuCI contracts, Candidate context/lineage/requalification, holdout no-feedback/global cadence, evidence count/byte bounds, continuous qualification/regression downgrade, confidence consistency, same-release generic Rill consumer integration, OpenWrt 24.10.5/24.10.8 IPK, OpenWrt 25.12.0/25.12.5 APK, workflow lint, and real CFST parsing/timeout smoke. The packaged Runtime lifecycle test uses the extracted `/usr/bin/rill-runtime`, including context recovery and new-lineage feedback. The external `rill-openwrt-packages` repository separately qualifies the generic Runtime package on its IPK/APK matrix. SDK Prepare, Build and Inspect use `/builder`. Each qualification record stores commit, run ID, job name, result, and artifact path.

## Device boundary

Real LuCI rendering, rpcd/ubus dispatch on OpenWrt, actual PassWall/OpenClash service recovery, and hardware/network soak are not claimed by host tests. They remain `BLOCKED` or `NOT_EVALUATED` until device evidence exists.
