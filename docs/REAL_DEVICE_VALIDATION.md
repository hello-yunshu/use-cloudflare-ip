# Real Device Validation Matrix

本文件是 RC 前的执行清单，不把 host contract 或 OpenWrt SDK build 当作真机证据。

## Matrix

| OpenWrt | Arch | Proxy / protocol | Required scenarios | Evidence |
|---|---|---|---|---|
| 24.10.5 | x86_64 | PassWall / TCP | full optimize、reuse success、current IP regression、rollback | install log、status、diagnostics、managed config diff |
| 24.10.5 | x86_64 | OpenClash / TCP+HTTP | transport filter、multi-IP apply、restart recovery | package/version、OpenClash readback、probe outcome |
| 24.10.8 | x86_64 | PassWall / TCP | delayed feedback across service restart、expiry、generation mismatch | before/after queue、qualification counters、logs |
| 25.12.0 | x86_64 | OpenClash / TCP+HTTP | resource pressure fallback、disabled cron cleanup | Runtime inspect、effective mode、crontab、rollback evidence |
| 25.12.5 | x86_64 | PassWall + OpenClash | end-to-end release candidate smoke | exact binary checksums、installed package metadata |

## Per-device procedure

1. Record device model, firmware image digest, architecture, package commit and Runtime/package qualification IDs.
2. Install the exact same-release base package, optional Rill package and Preview Runtime package; record package manager output and binary checksums.
3. Exercise both `reuse_enabled=1` and forced full optimize. Verify that reuse performs current-IP validation and that a failed validation enters full optimize without stale selection.
4. Change target domain, IP type, protocol, source policy and proxy mode one at a time. Verify fingerprint invalidation, explicit sync mode, LuCI validation rejection, stop/apply/restart ordering and rollback.
5. Restart the service between queue and delayed-feedback processing. Capture accepted, expired and schema/generation-rejected entries.
6. Preserve `/etc/cf_ip/status.json`, `/etc/cf_ip/rill-*.json`, `/etc/cf_ip/reuse-policy.json`, relevant logs, proxy readback and crontab as artifacts.

物理设备状态：未执行。没有物理设备安装、proxy readback 或真实 network probe 证据前，不写“真机通过”。

## Docker-backed validation record

作为设备不可用时的可重复安装运行 smoke，已在本机 OpenWrt 25.12.5 x86/64 rootfs 容器中执行。该记录证明安装后的 OpenWrt 用户空间链路，不替代物理设备和真实代理网络证据。

| 项目 | 结果 |
|---|---|
| Container image | `owrt-25.12.5:latest`, local image ID `sha256:228f656806c36a66fd1dc242a101c3c8484fdf94e0dec8a16b646046a3125e6a` |
| Cloudflare commit / Actions | `0cd064fa3cc6722a0fa3ffd7d2ff09568b55d16d` / run `33601273356` |
| Installed packages | `luci-app-cloudflare-ip-2.0.0.1-r1.apk`, `luci-app-cloudflare-ip-rill-2.0.0.1-r1.apk`, `rill-runtime-preview-1.5.6-r2.apk` |
| Package SHA256 | `85e183f710674b577f0a41f132a4e5fd1aca847237dd7926b9271bfb32808480`; `15eb6836639fc27ee680716710b82d2da2a30f578815a7b077f5d12a1eff6d5b`; `36ced00796b0d4aacd62eb3b48f10eebb8a1686b89d36925b1d3e292d4f00114` |
| Runtime checks | install PASS; PassWall/OpenClash validation PASS; invalid config rejection PASS; RPC list/call PASS; status/diagnostics JSON PASS; Runtime help PASS; disabled cron cleanup PASS |
| Boundary | No physical device, proxy readback, or real network probe was performed; post-install ubus registration was not exercised because the container was not booted with procd as PID 1. |

Docker 状态：**PASS（安装运行 smoke）**；物理真机状态：**NOT RUN**。
