# P1 Closure Audit — Intelligent Loop Completion / Release Gate

审计对象：`cloudflare-ip-2.0-dev`。本文件区分本地代码证据、远端 Actions、Runtime/package qualification、真机证据和 Soak 证据；没有把其中任一层替代另一层。

## Gate summary

| Gate | 当前结论 | 证据 / 边界 |
|---|---|---|
| A. Runtime/package/qualification parity | ⚠️ OPEN | Cloudflare 合约当前绑定 Preview `da8389fec7f879b826d8d17cbc6bb98c03ef8462`、package `38f21f02c06a880abd3cd020004814887f3943a5`（`rill-runtime-preview` 1.5.6-r2）、qualification run `33511365899`（PASS）；package PR #3 仍为 `OPEN / BLOCKED / REVIEW_REQUIRED`，package `main` 仍为 `87514ee67a4a6b404f354c99eb66e656555d7f5f`，因此不能声称正式 release branch 已收敛。 |
| B. P1-1 resource pressure | ✅ CODE CLOSED | `rill.sh` 从 Runtime health 与 inspect 的真实 `resourceProfile/resourceUtilization` 计算 90% pressure，并传递为 `resourcePressure`、`healthHealthy=false` 和 `runtime_resource_pressure` fallback；`tests/resource-pressure-contract.sh` 通过。 |
| C. P1-2 Source Strategy Learner | ✅ SHADOW CODE CLOSED | 独立 `source-policy` decide/feedback、bounded semantic features、source-specific reward、strict decision attribution、bounded guarded exploration 和 rolling qualification ledger 已接入；Native 配置仍是执行 authority，Rill 默认 Shadow。 |
| D. P1-3 reuse/current vs full optimize | ✅ CODE CLOSED | 配置 fingerprint、fresh → full optimize → post-apply validation → reuse-current 生命周期、loss/TTFB/total 硬门槛、atomic state 和 Rill Shadow recommendation 已接入；Native gate 决定是否跳过 CFST/acquisition，且保存真实 `.probes` 数量。 |
| E. P1-4 multi-IP diversity | ✅ CODE CLOSED | 仅在 Native Safe Envelope 内，按 canonical IPv4 `/24` / IPv6 `/64` prefix、family、source class 做 deterministic selection；Prefix/Colo aggregate history 有 bounded retention、decay 和 diagnostics；相关合同通过。 |
| F. P1-5 delayed feedback | ✅ CODE CLOSED | queue 带 `expiresAt`、feature schema hash、model/state generation 和 state lineage；正常 restart 可处理，reset/incompatible lineage 会拒绝并计数；相关合同通过。 |
| G. transaction/UI safety | ✅ CODE CLOSED | explicit sync mode 重算目标并控制 stop/apply/restart；LuCI save/apply 前调用同一 semantic validation RPC；disabled start 清理历史 cron。 |
| H. remote current-SHA CI | ✅ PASS | 最终代码提交 `39e5a9246a7ffff2819c3e7b0e30e823bf031c38`（tree `3bf8851cef23464613cd7401ed125a5b4171adce`）的 Actions run `33625649824` 已 terminal success；host/legacy/RPC/workflow、四个 OpenWrt package matrix、same-release Runtime integration、package-release/qualification/evidence guards 全部通过。 |
| I. OpenWrt package/build evidence | ✅ PASS (CI) | run `33625649824` 的四个 OpenWrt SDK package jobs、package content contracts 和 same-release generic Runtime integration 已通过；历史 Docker 安装运行记录仍只属于旧 SHA，当前 Docker install smoke 未执行。 |
| J. physical-device / soak | ⚪ SOAK SKIPPED (user-approved) | 72h/7d Soak 按用户批准直接跳过；物理 OpenWrt 设备、指定 proxy/protocol 场景仍未验证，不宣称硬件通过。 |

## Local implementation evidence

- Runtime 健康检查不再只依赖字符串 status；当 inspect 的 bounded counter 达到 90% profile 时，consumer 进入 resource pressure fail-closed path。
- Source Strategy 使用独立 policy action IDs 和语义特征向量；source reward 只来自对应来源的 availability/success/stale/failure/yield 统计。
- Source learner 记录 requested/recommended/executed/decisionId、attribution coverage、native-vs-Rill delta、error rate 和 downgrade reason；探索只在显式 bounded cap 下发生。
- Reuse branch 先验证当前已发布 IP；fresh/full optimize 成功会同时建立可复用 validation baseline；失败、fingerprint 改变、full optimize 过期、上一次验证失败或 Runtime reset-required 时，Native 强制进入 full optimize。
- Assisted multi-IP 只接受 Native safe candidates，先保证多样性，再用 deterministic fallback 补足数量；Prefix Intelligence 以 canonical `/24`/`/64` 聚合，Colo 只使用真实观测值。
- Delayed feedback 的跨进程队列是 bounded、atomic、可过期、可拒绝的；generation/schema/lineage 不匹配不会静默更新模型。
- `validate-config` 已贯穿 `rpcd → cf-ip-auto-v2 --validate-config → load_config/validate_config`，并在 LuCI `safeApply()` 前执行。

## Required evidence fields

每次 release candidate 应保存：

1. Cloudflare commit SHA、Rill Runtime commit SHA、package commit SHA。
2. package qualification run ID、head SHA、结论和 artifact digest。
3. 同一 package commit 生成的 IPK/APK 文件名、SHA256、OpenWrt branch/arch。
4. 真机安装后的 package version、Runtime binary checksum、`cf-ip-auto --status`、`--rill-diagnostics` 和关键日志。
5. Soak 起止时间、设备、配置 fingerprint、reuse/full-optimize 次数、resource pressure、delayed accepted/expired/rejected、rollback/recovery 记录。

## Current release conclusion

代码层面的 P1 closure、本地回归和最终 SHA `39e5a9246a7ffff2819c3e7b0e30e823bf031c38`（tree `3bf8851cef23464613cd7401ed125a5b4171adce`）的远端 CI run `33625649824` 已 terminal success。该 run 同时证明了四个 OpenWrt 包构建、same-release generic Runtime integration、package-release-guard、qualification-guard 和 evidence-manifest。当前 Docker install smoke、物理设备和 Soak 仍分别为 NOT RUN / NOT RUN / 按用户批准跳过。

由于 package PR #3 当前仍为 `OPEN / BLOCKED / REVIEW_REQUIRED`，其 qualified commit `38f21f02c06a880abd3cd020004814887f3943a5` 尚未进入 package `main`，Runtime/package release convergence 仍未关闭。因此本轮结论必须为：**❌ Final Full Closure 未通过**；代码 Closure 已完成，可以在 package main 收敛后继续 RC / Physical Device Validation，但不能提前声称 release convergence 或 Full Closure。
