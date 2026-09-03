# 2.1 Architecture Consolidation and Closure Audit

审计对象：2.0 closure、`cloudflare-ip-2.1-dev` 和 `release/2.1.0`。本文件区分本地代码、远端 CI、Runtime/package qualification、真机和 Soak 证据；任何一层都不能替代另一层。

## Architecture decision

2.1 只保留一个 Runtime Learner：`Candidate Learner`，使用 22D candidate schema、candidate partition、reward/feedback/delayed feedback、rolling qualification、guarded assisted 和 resource-pressure fail-closed。新增 Context、non-blocking Holdout、budgeted Evidence Store、Continuous Qualification、Confidence Reasons 和 LuCI diagnostics，均服务于 Candidate Learner 的可观测收益。Source Intelligence 是 Cloudflare consumer 内的确定性 registry/profile/order/cache/scheduler；Native Reuse 是独立的 current-IP validation hard gate，不进入 Runtime Learner。

经过消融审计，Source Learner / Reuse Learner 的当前 contextual modeling 无法提供与复杂度匹配的生产决策收益；保留 deterministic Source Intelligence 和 Native Adaptive Reuse 后，用户核心能力不损失。2.0 因此主动收敛为单 Candidate Learner 架构。

## Gate summary

| Gate | 结论 | 证据边界 |
|---|---|---|
| Candidate-only Runtime contract | CODE | Runtime state 仅允许 Cloudflare `candidate` partition；schema width 固定为 22；非候选 partition 的 feedback 被拒绝。 |
| Deterministic Source Intelligence | CODE | 保留 fixed registry、五种 profile、稳定排序、last-good cache、refresh deadline、source scheduler 和 diagnostics；无 Source Learner decide/feedback/qualification。 |
| Native Reuse hard gate | CODE | current-IP validation 通过才允许 `REUSE_CURRENT`；配置变更、过期、失败或缺少 baseline 时强制 full optimize；decision authority 为 Native。 |
| Mature optimizer behavior | CODE | CFST、IPv4/IPv6、PassWall/OpenClash transaction、target-domain probe、prefix/colo/multi-IP/reuse/rollback、LuCI staged validation 保留。 |
| Candidate feedback and qualification | CODE | 22D reward、attribution、delayed queue、lineage/generation、rolling qualification、guarded assisted、Health/Inspect 和 resource pressure 保留。 |
| 2.0 Final Closure A1-A6 | PASS | Cloudflare closure exact branch `a01d3167a119a1ee15681b48f2d912625cf987f7`；A6 package-main convergence and exact package qualification completed at package main `64ee22f978ed8f8ed19bb675700678f57eec19e3`, qualification run `33735123909`. |
| 2.1 development exact-head regression | PASS | `cloudflare-ip-2.1-dev` exact head `cbffb586f0a7bb04238da4c45b78d631a95d3830`, CI run `33738665315`; all host/legacy/RPC/LuCI, real CFST, four SDK targets, packaged Runtime, release asset, qualification and evidence gates passed. |
| Release candidate exact-head regression | PASS | `release/2.1.0` final RC head `f459f8b3d095a6967066aa7b524d028a4a1f8e8d`, PR CI run `33745358580`; all required jobs passed. |
| Package main convergence | PASS | `rill-openwrt-packages/main` is `64ee22f978ed8f8ed19bb675700678f57eec19e3`; PR #3 was merged after the explicitly authorized production ruleset change, and qualification run `33735123909` passed. |
| Physical device / soak | USER-APPROVED SKIP | Docker, SDK, IPK/APK and software tests do not substitute for the separately approved physical OpenWrt matrix or 24-hour soak. |

## Consumer boundaries

```text
deterministic source registry/profile/order/cache/scheduler
  -> CFST -> Native rank and mandatory target-domain probe
  -> Native safe envelope -> Candidate Learner shadow/guarded-assisted preference
  -> transaction -> immediate validation -> delayed candidate feedback
```

Native remains authoritative whenever Runtime is absent, unhealthy, stale,
invalid, resource-pressured, unqualified, timed out or reset-required. Runtime
cannot access UCI, mutate PassWall/OpenClash, restart services or commit a host
transaction. Source selection and reuse/full-optimize decisions remain owned by
the consumer.

## Required release evidence

Each release candidate must record the Cloudflare commit/tree, Rill Runtime
commit, package commit, package qualification run and artifact digests. A
physical validation record must additionally include installed package versions,
Runtime checksum, `cf-ip-auto --status`, `--rill-diagnostics`, proxy readback,
rollback/recovery, delayed accepted/expired/rejected counters and soak timing.

The final status may be promoted only after the merged `main` exact-head CI and
the release workflow validate the same SHA and generated qualification manifest.
Physical-device matrix and soak remain the two explicitly approved evidence
boundaries; they are not represented as automated PASS.
