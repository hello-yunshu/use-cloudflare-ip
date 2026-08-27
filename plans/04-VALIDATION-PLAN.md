# Validation plan

## Local gates

Run `git diff --check`, Bash/ash syntax, ShellCheck where available, `node --check`, `jq empty`, PO validation, existing 1.8.3 tests, every `tests/legacy/*.sh`, and every `tests/v2-*.sh`. Contract tests must use fixtures and side effects, not file-existence greps.

## Remote gates

Independent jobs cover host contracts, legacy behavior, RPC/LuCI contracts, native/Rill, each of five musl targets, OpenWrt IPK/APK, workflow lint, and real CFST parsing/timeout smoke. SDK Prepare, Build and Inspect use `/builder`. Each qualification record stores commit, run ID, job name, result, and artifact path.

## Device boundary

Real LuCI rendering, rpcd/ubus dispatch on OpenWrt, actual PassWall/OpenClash service recovery, and hardware/network soak are not claimed by host tests. They remain `BLOCKED` or `NOT_EVALUATED` until device evidence exists.
