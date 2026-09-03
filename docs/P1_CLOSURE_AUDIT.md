# 2.0 Architecture Consolidation and Closure Audit

审计对象：`cloudflare-ip-2.0-dev`。本文件区分本地代码、远端 CI、Runtime/package qualification、真机和 Soak 证据；任何一层都不能替代另一层。

## Architecture decision

2.0 只保留一个 Runtime Learner：`Candidate Learner`，使用 22D candidate schema、candidate partition、reward/feedback/delayed feedback、rolling qualification、guarded assisted 和 resource-pressure fail-closed。Source Intelligence 是 Cloudflare consumer 内的确定性 registry/profile/order/cache/scheduler；Native Reuse 是独立的 current-IP validation hard gate，不进入 Runtime Learner。

经过消融审计，Source Learner / Reuse Learner 的当前 contextual modeling 无法提供与复杂度匹配的生产决策收益；保留 deterministic Source Intelligence 和 Native Adaptive Reuse 后，用户核心能力不损失。2.0 因此主动收敛为单 Candidate Learner 架构。

## Gate summary

| Gate | 结论 | 证据边界 |
|---|---|---|
| Candidate-only Runtime contract | CODE | Runtime state 仅允许 Cloudflare `candidate` partition；schema width 固定为 22；非候选 partition 的 feedback 被拒绝。 |
| Deterministic Source Intelligence | CODE | 保留 fixed registry、五种 profile、稳定排序、last-good cache、refresh deadline、source scheduler 和 diagnostics；无 Source Learner decide/feedback/qualification。 |
| Native Reuse hard gate | CODE | current-IP validation 通过才允许 `REUSE_CURRENT`；配置变更、过期、失败或缺少 baseline 时强制 full optimize；decision authority 为 Native。 |
| Mature optimizer behavior | CODE | CFST、IPv4/IPv6、PassWall/OpenClash transaction、target-domain probe、prefix/colo/multi-IP/reuse/rollback、LuCI staged validation 保留。 |
| Candidate feedback and qualification | CODE | 22D reward、attribution、delayed queue、lineage/generation、rolling qualification、guarded assisted、Health/Inspect 和 resource pressure 保留。 |
| Current-head remote regression | PASS | Cloudflare `dffeb8f22d92c88cab02b0138326585057c13d1e`、tree `d46e04f67e44d11fe8479093059cc372cab8f08` 的 CI run `33723365283` terminal success；host/legacy/RPC/LuCI/workflow/real CFST、四个 OpenWrt package matrix、same-release integration、qualification/evidence guards 全部通过。 |
| Package main convergence | OPEN | package qualification branch `38f21f02c06a880abd3cd020004814887f3943a5` 仍需进入 `rill-openwrt-packages/main`；当前 PR #3 为 `BLOCKED / REVIEW_REQUIRED`，package main 仍是 `87514ee67a4a6b404f354c99eb66e656555d7f5f`。 |
| Physical device / soak | NOT RUN | Docker、SDK、IPK/APK 和软件测试不能替代真实 OpenWrt 设备或 72h/7d soak。 |

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

The final status must remain `CODE COMPLETE` only when all code gates and the
current-head remote checks pass. It must not be promoted to full release
closure while package main convergence, physical-device evidence or soak is
still open.
