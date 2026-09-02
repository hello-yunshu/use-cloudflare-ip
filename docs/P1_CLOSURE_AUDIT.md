# P1 Closure Audit — Intelligent Loop Completion / Release Gate

审计对象：`cloudflare-ip-2.0-dev`。本文件区分本地代码证据、远端 Actions、Runtime/package qualification、真机证据和 Soak 证据；没有把其中任一层替代另一层。

## Gate summary

| Gate | 当前结论 | 证据 / 边界 |
|---|---|---|
| A. Runtime/package/qualification parity | ⚠️ OPEN | Cloudflare 合约当前绑定 Preview `da8389fec7f879b826d8d17cbc6bb98c03ef8462`、package `38f21f02c06a880abd3cd020004814887f3943a5`、qualification run `33511365899`；package PR #3 仍为 `BLOCKED`，package `main` 已是 `87514ee67a4a6b404f354c99eb66e656555d7f5f`，因此不能声称正式 release branch 已收敛。 |
| B. P1-1 resource pressure | ✅ CODE CLOSED | `rill.sh` 从 Runtime health 与 inspect 的真实 `resourceProfile/resourceUtilization` 计算 90% pressure，并传递为 `resourcePressure`、`healthHealthy=false` 和 `runtime_resource_pressure` fallback；`tests/resource-pressure-contract.sh` 通过。 |
| C. P1-2 Source Strategy Learner | ✅ SHADOW CODE CLOSED | 独立 `source-policy` decide/feedback、bounded semantic features、source-specific reward 和 qualification ledger 已接入；Native 配置仍是执行 authority，Rill 默认 Shadow。 |
| D. P1-3 reuse/current vs full optimize | ✅ CODE CLOSED | 配置 fingerprint、最近一次 full optimize、当前 IP 再验证、loss/TTFB/total 硬门槛、atomic state 和 Rill Shadow recommendation 已接入；Native gate 决定是否跳过 CFST/acquisition。 |
| E. P1-4 multi-IP diversity | ✅ CODE CLOSED | 仅在 Native Safe Envelope 内，按 IPv4 / IPv6 prefix、family、source class 做 deterministic selection；`tests/multi-ip-diversity-contract.sh` 通过。 |
| F. P1-5 delayed feedback | ✅ CODE CLOSED | queue 带 `expiresAt`、feature schema hash、model/state generation；重启后验证并处理，expiry/mismatch 计数并 drop；`tests/delayed-feedback-lifecycle-contract.sh` 通过。 |
| G. transaction/UI safety | ✅ CODE CLOSED | explicit sync mode 重算目标并控制 stop/apply/restart；LuCI save/apply 前调用同一 semantic validation RPC；disabled start 清理历史 cron。 |
| H. remote current-SHA CI | ✅ PASS | 当前提交 `0cd064fa3cc6722a0fa3ffd7d2ff09568b55d16d` 的 Actions run `33601273356` 已 terminal success，14 个 jobs 全部通过。 |
| I. Docker-backed install/runtime smoke | ✅ PASS (Docker) | OpenWrt 25.12.5 x86/64 容器已安装当前 SHA 生成的三个 APK，并通过包校验、PassWall/OpenClash semantic validation、非法配置拒绝、RPC dispatch、状态/诊断 JSON、Runtime help、禁用 cron 清理；不等同物理硬件证据。 |
| J. physical-device / soak | ⚪ SOAK SKIPPED (user-approved) | 72h/7d Soak 按用户批准直接跳过；物理 OpenWrt 设备、指定 proxy/protocol 场景仍未验证，不宣称硬件通过。 |

## Local implementation evidence

- Runtime 健康检查不再只依赖字符串 status；当 inspect 的 bounded counter 达到 90% profile 时，consumer 进入 resource pressure fail-closed path。
- Source Strategy 使用独立 policy action IDs 和语义特征向量；source reward 只来自对应来源的 availability/success/stale/failure/yield 统计。
- Reuse branch 先验证当前已发布 IP；失败、fingerprint 改变、full optimize 过期、上一次验证失败或 Runtime reset-required 时，Native 强制进入 full optimize。
- Assisted multi-IP 只接受 Native safe candidates，先保证多样性，再用 deterministic fallback 补足数量；不会让 Rill 引入未验证候选。
- Delayed feedback 的跨进程队列是 bounded、atomic、可过期、可拒绝的；generation/schema 不匹配不会静默更新模型。
- `validate-config` 已贯穿 `rpcd → cf-ip-auto-v2 --validate-config → load_config/validate_config`，并在 LuCI `safeApply()` 前执行。

## Required evidence fields

每次 release candidate 应保存：

1. Cloudflare commit SHA、Rill Runtime commit SHA、package commit SHA。
2. package qualification run ID、head SHA、结论和 artifact digest。
3. 同一 package commit 生成的 IPK/APK 文件名、SHA256、OpenWrt branch/arch。
4. 真机安装后的 package version、Runtime binary checksum、`cf-ip-auto --status`、`--rill-diagnostics` 和关键日志。
5. Soak 起止时间、设备、配置 fingerprint、reuse/full-optimize 次数、resource pressure、delayed accepted/expired/rejected、rollback/recovery 记录。

## Current release conclusion

代码层面的 P1 closure、当前 SHA CI 和 Docker-backed 安装运行 smoke 已完成；Soak 已按用户批准跳过。由于当前 package PR #3 未合并、package main 与合约 pinned commit 不一致，结论仍为：**⚠️ 尚未满足 RC Gate**。
