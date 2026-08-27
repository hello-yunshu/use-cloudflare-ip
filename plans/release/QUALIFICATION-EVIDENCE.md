# Qualification evidence

This file records exact evidence for the clean rebuild branch. It does not authorize a stable release by itself.

## Remote branch and baseline

- Branch: `codex/cloudflare-ip-2-0-clean-rebuild-20260827`
- Qualification target commit: `abca78846cafad7beec4604483675a5adfbcc6b1`
- `origin/main`: `77a65a86a84b5fdf4cd0a854edc83a9c5c7d7fb1`
- Ahead of `origin/main` at qualification: `10` commits; merged to `main`: `NOT_RUN`
- Prior remote branches `codex/cloudflare-ip-2-0-dev-20260827` and `cloudflare-ip-2-0-rebuild-20260827`: deleted and absent from `origin`

## GitHub Actions qualification

Run: [33079322937](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/33079322937) at the qualification target commit above. Run conclusion: `success`.

| Gate | Job conclusion |
|---|---|
| Host contracts | `PASS` |
| Legacy contracts | `PASS` |
| RPC/LuCI contracts | `PASS` |
| Workflow lint | `PASS` |
| Rill native | `PASS` |
| Rill musl x86_64 | `PASS` |
| Rill musl aarch64/QEMU | `PASS` |
| Rill musl armv7/QEMU | `PASS` |
| Rill musl i686/QEMU | `PASS` |
| Rill musl riscv64/QEMU | `PASS` |
| OpenWrt 24.10.5 x86_64 IPK | `PASS` |
| OpenWrt 25.12.0 x86_64 APK | `PASS` |
| Package/release guard | `PASS` |
| Qualification guard | `PASS` |

## Local qualification

The local shell, security, source-engine, candidate-budget, exact-CFST-input, legacy, package, actionlint, ShellCheck, and Rill adapter checks passed before push. The Rill adapter also passed `cargo fmt --check`, Clippy with `-D warnings`, tests, release build, and its smoke test.

## Release boundary

- Stable release/tag/public package publication: `NO-GO` — this branch is not merged to `main`, and real-device, real OpenWrt runtime, hardware coverage, and 24-hour soak evidence remain `NOT_EVALUATED`.
- Hardware and real OpenWrt runtime: `NOT_EVALUATED`
- 24-hour soak: `NOT_EVALUATED`
