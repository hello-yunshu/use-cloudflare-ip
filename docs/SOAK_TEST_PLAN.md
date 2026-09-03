# Soak Test Plan

## Duration and scope

RC minimum is 72 hours; preferred release evidence is 7 days. Run on at least one PassWall and one OpenClash device, with the exact package and Runtime commits intended for release.

本次执行状态：**⚪ SKIPPED（用户批准）**。本计划保留作为后续发布参考，但本次不启动 72h/7d 持续运行。

## Workload

- Scheduled runs at the production interval, plus bounded manual sync checks.
- Mix reuse-current, forced full optimize, source refresh, proxy restart and device/service restart.
- Include IPv4, IPv6 and dual-stack candidates where the device and proxy support them.
- Include one controlled Runtime resource-pressure event and one delayed-feedback schema/generation rejection fixture.

## Metrics and thresholds

| Metric | Required observation |
|---|---|
| crash / unhandled failure | 0 |
| stale or duplicate cron entries | 0 |
| unsafe candidate applied outside Native envelope | 0 |
| reuse validation before reuse apply | 100% |
| failed reuse followed by full optimize | 100% |
| delayed queue size | ≤64; expired/rejected are counted |
| state corruption | 0; any corrupt state must quarantine and fail safe |
| recovery after stop/apply failure | 100% verified restart or explicit blocker |
| resource pressure | fallback reason and diagnostics present for every event |

## Capture and exit criteria

At each interval capture timestamp, config fingerprint, selected IPs, effective mode, source policy, reuse decision, resource pressure, queue counters and transaction result. At the end, compare start/end state checksums and export logs plus a machine-readable summary.

Any unsafe apply, missing rollback, silent queue loss, unbounded source refresh, stale cron entry or unexplained Runtime/package drift fails the soak. Because this plan is explicitly skipped for this execution, it contributes no Soak PASS evidence and does not change the remaining release gates.

补充：已完成一次 OpenWrt 25.12.5 x86/64 Docker-backed 安装运行 smoke；它不计入 72h/7d Soak，也不替代 PassWall/OpenClash 物理设备持续运行证据。本次 Soak 已按用户批准跳过。
