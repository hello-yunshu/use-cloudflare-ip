# Rill qualification

Cloudflare IP consumes the external, package-owned `/usr/bin/rill-runtime`
generic IPC v3 Preview surface. The Cloudflare package does not download,
install, remove or publish a private Runtime adapter. The optional
`luci-app-cloudflare-ip-rill` integration remains a consumer mapping layer.
The package repository builds a separately named `rill-runtime-preview` from
the contract's exact upstream commit; Stable and Preview are never silently
substituted for one another.

Qualification must cover all of the following boundaries:

- the exact Rill Stable version and immutable source archive qualified by
  `rill-openwrt-packages`;
- a same-release build of the real generic `rill-runtime-preview` binary,
  extracted from the OpenWrt package artifact and used by the Cloudflare
  integration, including handshake, decide, selected action, persisted state,
  feedback and delayed feedback;
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
The x86_64, aarch64, riscv64gc, armv7 and i686 musl binaries belong to the
upstream Rill Stable release qualification. Cloudflare IP neither rebuilds nor
publishes private Runtime binaries; its consumer gate uses the external
package-owned `/usr/bin/rill-runtime` and the exact Stable provenance. The
generic Runtime package repository owns its own exact-commit Stable and Preview
IPK/APK qualification and immutable `qualification.json` evidence.

## Consumer decision and learning boundaries

```text
source candidates -> CFST -> history-aware probe priority -> mandatory probe
  -> Native eligible safe envelope -> Rill preference
  -> Shadow observation or Guarded Assisted selection -> transaction
  -> immediate validation -> delayed candidate outcome -> feedback
  -> qualification state
```

The v2 consumer schema has 22 bounded features. Candidate history is bounded
and atomically replaced. Shadow feedback always observes the Rill-selected IP
separately when it differs from the Native authority. Host transaction errors
are censored and cannot train a candidate. Assisted is only effective when the
persisted qualification state is `shadow-qualified` or `guarded-assisted`; it
can select only inside the Native top-K envelope and falls back to Native on
any invalid Runtime result.

Measurement is also bounded: the fixed source-policy registry orders at most
the configured source set, candidate probes run in capped batches, and the
early-stop decision is deterministic from the safe envelope and remaining
CFST ranks. Reward v2 is bounded to `[-1,1]` and records total latency, TTFB,
worst-domain loss, throughput, and delayed stability. Delayed entries carry
the candidate/domain context, generation and queue time; due entries are
re-observed before feedback, while malformed queues are quarantined.

The rolling qualification window is capped at 50 observations. It requires
complete attribution, at least 80% delayed completion, Native/Rill disagreement
evidence, recent error and severe-regression limits, and no negative rolling
regret. A previously qualified consumer is downgraded to `shadow` as soon as
the rolling gate is lost. Runtime status must come from the real Health and
Inspect protocol; resource pressure is never a hardcoded healthy value.

Qualification is intentionally conservative: it requires complete attribution,
low recent Runtime error rate, and delayed feedback coverage before entering
`shadow-qualified`. A reset or incompatible state moves the consumer to
`reset-required`/Native fallback until new evidence is collected.

## PageHinkley decision

The old Cloudflare adapter's PageHinkley latency detector is formally retired
from the consumer (`drift-decision.json`). It was responsible for detecting a
sustained Cloudflare-specific latency distribution shift and requesting a
model reset. The generic Runtime's bounded learner and model-health signals
replace only the generic part of that responsibility; no Cloudflare-specific
drift claim is made. A reset is explicit and state-generation checked. Any
missing, invalid, stale, rejected, or unhealthy Runtime result keeps native
ranking authoritative and leaves host mutation unchanged.
