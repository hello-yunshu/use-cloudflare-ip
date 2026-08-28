# Rill qualification

Cloudflare IP consumes the external, package-owned `/usr/bin/rill-runtime`
generic IPC v3 Preview surface. The Cloudflare package does not download,
install, remove or publish a private Runtime adapter. The optional
`luci-app-cloudflare-ip-rill` integration remains a consumer mapping layer.

Qualification must cover all of the following boundaries:

- the exact Rill Stable version and immutable source archive qualified by
  `rill-openwrt-packages`;
- a same-release build of the real generic `rill-runtime` binary, including
  handshake, decide, selected action, persisted state, feedback and delayed
  feedback;
- the canonical feature schema and its real SHA256, normalized feature order,
  bounded values and conservative missing-value policy;
- native candidate-set invariants, native fallback on invalid/missing/late
  Runtime responses, and no host mutation by Runtime; and
- OpenWrt IPK/APK package qualification for the required x86_64 SDKs.

Native rank remains authoritative and complete when Runtime is absent,
unsupported, corrupt, timed out or invalid. The host remains responsible for
measurement, candidate construction, native policy, authorization, apply,
verification, rollback and outcome definition. Runtime supplies only generic
intelligence/state and cannot write UCI, change PassWall/OpenClash, restart a
service or commit a router transaction.

Native Rust gates are fmt, clippy `-D warnings`, test, release build and smoke.
Release qualification additionally executes x86_64, aarch64, riscv64gc, armv7
and i686 musl binaries with the matching QEMU names.
