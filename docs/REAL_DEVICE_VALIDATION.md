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

状态：未执行。没有设备安装、Runtime checksum、proxy readback 或真实 network probe 证据前，不写“真机通过”。
