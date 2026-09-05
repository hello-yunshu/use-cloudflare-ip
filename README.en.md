# luci-app-cloudflare-ip

**English** | [中文](README.md)

<p align="center">
  <strong>Cloudflare IP Optimizer for OpenWrt</strong>
</p>

<p align="center">
  Automatically benchmark and optimize Cloudflare IPs for PassWall / OpenClash proxy nodes, managed through the LuCI web interface — no CLI required.
</p>

---

## Features

- **LuCI Web Interface**: Dashboard overview, settings forms, log maintenance — all visual
- **PassWall / OpenClash Dual Mode**: Auto-detects installed proxy services, shows relevant config pages only
- **CFST Auto-Management**: One-click download CloudflareSpeedTest on first use, with online updates
- **Scheduled Tasks**: Automatic runs via cron-managed schedules with configurable intervals
- **IP Type**: IPv4 / IPv6 / Dual-stack
- **Benchmark Protocol**: TCP (default) / HTTP (with data center filtering)
- **Connectivity Verification**: Validates each IP after benchmarking, skips unreachable ones
- **Multi-Domain Support**: Comma-separated target domains
- **IP History**: View historical optimized IP list
- **Upgrade Policy**: 2.1 is package-managed; the legacy script self-update key is retained only for migration compatibility

## Current version

The 2.x line remains the `2.0 prerelease development line`; the current package
milestone is `2.6.0-r2`, and GitHub Releases remain prereleases rather than stable
releases. It builds on the deterministic Native
safety envelope from 2.0 and adds Candidate Intelligence: context fingerprints and
isolation, non-blocking holdout evaluation, budgeted evidence storage, continuous
qualification, confidence reasons, and LuCI diagnostics. Runtime still has one
Candidate Learner; Source Intelligence and Reuse remain deterministic consumer
logic and a Native current-IP hard gate respectively.

The formal package is promoted only from successful exact-head CI on `main` to
the new `v2.6.0-2` prerelease. IPK/APK packages, `sha256sums.txt`, and `qualification.json` belong to
one qualification chain. Live OpenWrt devices, hardware coverage, and soak are
separate evidence boundaries.

Adaptive Measurement is implemented as an independent Native pre-probe
scheduler, defaulting to Shadow. It accepts only CFST/source/history/prefix/Colo
and previous-winner fields, never creates a second Rill learner or partition, and
enables Guarded only after complete, compatible, fresh audit evidence meets the
recall, safety, and savings thresholds. Invalid state or probe failure returns
the next run to the full Native baseline. Guarded mode produces meaningful probe savings only when `probe_top_count` is greater than `adaptive_min_probe_count`; the conservative defaults do not inflate the full measurement scale. See docs/2.2_ADAPTIVE_MEASUREMENT.md.

## Installation

### Prerequisites

- OpenWrt 24.10.x or 25.12+
- PassWall or OpenClash installed
- Proxy node domains properly routed through Cloudflare CDN

### Download & Install

Grab the package from the [Releases](../../releases) page:

| Format | Target | Install Command |
|--------|--------|-----------------|
| `.ipk` | OpenWrt 24.10.x | `opkg install luci-app-cloudflare-ip_*.ipk` |
| `.apk` | OpenWrt 25.12+ | `apk add luci-app-cloudflare-ip*.apk` |

After installation, clear your browser cache and look for **Services → Cloudflare IP 优选** in the LuCI menu.

### Package Info

| Item | Value |
|------|-------|
| Package name | `luci-app-cloudflare-ip` |
| Service name | `cf_ip` |
| UCI config | `/etc/config/cf_ip` |
| Core script | `/usr/bin/cf-ip-auto` |
| RPC backend | `cf_ip` (`ubus call cf_ip <method>`) |

> **Note**: This package is `luci-app-cloudflare-ip`, which is independent from PassWall (`luci-app-passwall`) and OpenClash (`luci-app-openclash`). It only reads and modifies proxy configurations — it does not replace or overwrite PassWall / OpenClash itself.

### Verify

```sh
sha256sum -c sha256sums.txt
```

### Dependencies

```
bash curl tar jq ca-bundle ca-certificates luci-base rpcd
```

## Usage Guide

### Overview Page

Navigate to **Services → Cloudflare IP 优选**. The overview page shows:

- **Run Status**: Whether currently running, last result, run mode
- **Environment Check**: CFST installation status (with download/update button), PassWall/OpenClash status
- **Optimized IPs**: Best IP list from the latest benchmark

When CFST is not installed, click "Download CFST" to auto-download; when installed, "Update CFST" is shown instead.

### Basic Settings

| Option | Description | Default |
|--------|-------------|---------|
| Enabled | Enable scheduled auto-optimization | Off |
| Mode | PassWall / OpenClash (auto-detects installed services) | PassWall |
| IP Count | Number of optimized IPs to keep | 4 |
| IP Type | ipv4 / ipv6 / both | ipv4 |
| Benchmark Protocol | tcp / http | tcp |
| Run Schedule | Auto-run interval: `6h`/`30m`/cron expression, or Custom for full cron | 6h |

### PassWall Settings

| Option | Description | Default |
|--------|-------------|---------|
| Target Domain | Node domains to optimize, comma-separated | — |
| Name Suffix | Node name suffix, supports `{n}` index and `{ip}` placeholder | ` [CF-{n}]` |

Filters nodes where `address` matches the target domain, replaces with optimized IPs.

### OpenClash Settings

| Option | Description | Default |
|--------|-------------|---------|
| Config File | OpenClash YAML config file path | `/etc/openclash/config/config.yaml` |
| Target Domain | Node domains to optimize, comma-separated | — |
| Name Suffix | Node name suffix, supports `{n}` index and `{ip}` placeholder | ` [CF-{n}]` |
| Transport Filter | Filter nodes by transport protocol (e.g. `ws,grpc`) | — |
| Backup Count | Number of config backups to keep | 3 |
| Backup Management | Manage YAML backups from the OpenClash page (list, restore, delete) | — |

Finds nodes where `server` matches the target domain, generates `[CF-1]`, `[CF-2]`, etc. based on IP count. `servername` and `Host` preserve the original domain. Supports vless / vmess / trojan, requiring `tls: true` or `network` being ws / xhttp / grpc / h2 / http.

### Advanced Settings

| Option | Description | Default |
|--------|-------------|---------|
| Stop Proxy Before Benchmark | Avoid proxy interference with benchmark results | On |
| Startup Delay | Random delay in seconds, `random` = 0~300s | — |
| Self-Update | Deprecated; 2.1 is package-managed | Off |
| GitHub Mirror | Mirror URL to accelerate GitHub downloads | — |
| Download Retries | GitHub download retry count | 3 |
| Retry Delay | Retry interval in seconds | 5 |
| Verbose Logging | Output detailed runtime logs | Off |

### Logs & Maintenance

- View runtime logs
- View IP history
- Manually trigger benchmark
- Self-update only reports “deprecated”; upgrade through the IPK/APK package
- Start / Stop / Restart service

## Project Structure

```
root/
├── etc/
│   ├── config/cf_ip                          # UCI configuration
│   └── init.d/cf_ip                          # lifecycle and cron scheduler script
└── usr/
    ├── bin/cf-ip-auto                        # Core business script
    │   ├── libexec/rpcd/cf_ip                    # RPC backend (compatibility API + 2.0 extensions)
    └── share/
        ├── luci/menu.d/                      # LuCI menu registration
        └── rpcd/acl.d/                       # RPC access control

htdocs/luci-static/resources/
├── cloudflare-ip/
│   ├── cloudflare-ip.css                     # Global styles
│   └── utils.js                              # Shared utility functions
└── view/cloudflare-ip/
    ├── overview.js                           # Dashboard overview
    ├── settings.js                           # Basic settings
    ├── passwall.js                           # PassWall configuration
    ├── openclash.js                          # OpenClash configuration
    ├── advanced.js                           # Advanced settings
    └── diagnostics.js                        # Logs & Records
```

## Architecture

```
┌──────────────┐     ubus/rpcd     ┌──────────────────┐     UCI      ┌──────────────┐
│  LuCI Frontend│ ──────────────→  │  rpcd Backend     │ ──────────→ │  UCI Config   │
│  (8 JS views) │ ←──────────────  │  (compatibility + extensions) │ ←────── │  cf_ip │
└──────────────┘     JSON response └──────────────────┘              └──────┬───────┘
                                                                            │
                                                              cf-ip-auto
                                                                            │
                                                                   ┌────────▼────────┐
                                                                   │  CloudflareSpeedTest │
                                                                   │  (auto download/update)│
                                                                   └────────┬────────┘
                                                                            │
                                                              Benchmark → Verify → Update Nodes
```

**Data Flow**:

1. Frontend calls rpcd backend via `ubus call cf_ip <method>`
2. Backend invokes `cf-ip-auto` to execute operations
3. Benchmark results are written to persistent `/etc/cf_ip/status.json`
4. PassWall or OpenClash nodes are updated based on UCI mode config
5. Logs are written to `/tmp/cf_ip/cf-ip-auto.log`

## UCI Configuration Reference

### service section

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | 0 | Enable scheduled auto-optimization |
| `mode` | enum | passwall | Proxy mode: `passwall` / `openclash` |
| `ip_count` | integer | 4 | Number of optimized IPs to keep |
| `ip_type` | enum | ipv4 | IP type: `ipv4` / `ipv6` / `both` |
| `speedtest_protocol` | enum | tcp | Benchmark protocol: `tcp` / `http` |
| `speedtest_cfcolo` | string | — | Filter by data center (HTTP protocol only) |
| `speedtest_dn` | integer | 8 | Download benchmark threads |
| `speedtest_tll` | integer | 40 | Average latency floor (ms), filter fake IPs |
| `speedtest_tl` | integer | — | Average latency ceiling (ms), leave empty for no limit |
| `stop_service` | boolean | 1 | Stop proxy service before benchmarking |
| `startup_delay` | string | — | Startup delay, `random` = 0~300s |
| `auto_update` | boolean | 0 | Deprecated script self-update compatibility key; unused by 2.0 |
| `self_update_url` | string | — | Self-update download URL |
| `download_retries` | integer | 3 | GitHub download retry count |
| `download_retry_delay` | integer | 5 | Retry interval in seconds |
| `github_mirror` | string | — | GitHub mirror URL for acceleration |
| `verbose` | boolean | 0 | Verbose logging |
| `work_dir` | string | — | Working directory |
| `cron_interval` | string | 6h | Auto-run schedule, supports `6h`, `30m`, or a 5-field cron expression |
| `measurement_timeout` | integer | 60 | Measurement and normal-apply deadline (20-300 seconds) |
| `recovery_timeout` | integer | 30 | Rollback, service restore and recovery-health deadline (10-120 seconds) |
| `cfst_persist` | boolean | 1 | Preserve `${work_dir}/cfst/cfst` across sysupgrade |

### passwall section

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `target_domain` | string | — | Target domains, comma-separated |
| `name_suffix` | string | ` [CF-{n}]` | Node name suffix |

### openclash section

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `config` | string | `/etc/openclash/config/config.yaml` | YAML config file path |
| `target_domain` | string | — | Target domains, comma-separated |
| `name_suffix` | string | ` [CF-{n}]` | Node name suffix |
| `transport_filter` | string | — | Transport protocol filter (e.g. `ws,grpc`) |
| `backup_count` | integer | 3 | Config backup count |

## Building

This project uses GitHub Actions for automated builds:

- Pushing to main branch triggers version detection and build
- Manual dispatch is also available from the Actions tab

## Acknowledgments

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
## 2.6 Intelligence engine

Package version `2.6.0` builds on the complete 1.8.3 behavior baseline and the 2.0 closure. Overview, Settings, Diagnostics, PassWall, OpenClash, scheduling, CFST, suffixes, multi-IP variants, backups, and upgrade behavior remain available. Candidate IP Sources, bounded scheduling, target-domain Active Probe, Native Rank, transactional apply/rollback, optional generic Rill Runtime v3 Preview shadow intelligence, and an optional LAN Publisher are additive. Adaptive Measurement consumes pre-probe fields only and defaults to Shadow; complete audits are required before Guarded, and Operational Health only permits conservative downgrades. The Intelligence page shows endpoint, system health, Adaptive/Candidate state, next audit/optimize, and bounded history without adding another learner or a large dashboard. Training feedback and evaluation evidence are separate; material context changes rotate lineage and isolate incompatible evidence before a fresh context can requalify. The upstream OpenWrt package repository owns distribution and publishes a separately qualified `rill-runtime-preview` package pinned to the exact Preview commit; this repository only provides the optional consumer mapping package.

Candidate Budget defaults to 128 and accepts 100-512 unique candidates. Fresh history, community seeds, and official CIDR exploration receive about 1/8, 5/8, and 1/4; deficits flow between pools. Official CIDRs are sampled into concrete IPs and one CFST process measures the merged input. A community `IP:port` contributes only its IP; domain candidates are rejected without DNS resolution.

The measurement policy is explicit and bounded: `balanced`, `official-heavy`, `history-heavy`, `diversity-heavy`, or `community-heavy`. Source Intelligence is deterministic registry/profile/order/cache/scheduler logic, not a Runtime Learner. Runtime has one Candidate Learner with a 22D schema and `candidate` partition. Active probes run in bounded batches with a deterministic early-stop rule; Reward v2, delayed feedback, rolling qualification, Health/Inspect and resource-pressure fail-closed behavior remain enabled. Assisted can prefer only inside the Native safe envelope and falls back to Native on every invalid or unhealthy Runtime result. Reuse is a Native current-IP validation hard gate: stale, changed or failed validation forces full optimize.

Before PassWall or OpenClash is changed, every selected IP must pass the configured target-domain probe with the intended SNI/Host. One host transaction captures state before stopping the proxy; the measurement deadline covers measurement, probes, apply and normal restart, while failures enter an independent recovery deadline for rollback, service restore and health confirmation. The transaction invokes a pure transformer, performs block-level intended-mapping readback, restarts, and verifies health. Timeout, failed eligibility, or restart failure rolls back configuration and managed state. Rill errors always fall back to Native Rank. Shadow separately probes a Rill-only candidate, and only candidate-specific non-censored outcomes enter delayed feedback.

Script self-update is deprecated because 2.1 is multi-file and package-managed. `auto_update=0` is the default; upgrade via a validated IPK/APK package. UCI, CFST, source last-good caches, ownership and bounded history persist across upgrades, while run/probe/publisher files are temporary. LAN Publisher is disabled by default, LAN-only, refuses `0.0.0.0`, and serves `/ip.txt`, `/best-ipv4.txt`, `/best-ipv6.txt`, and `/result.json`.

Release gates require every legacy item, host/RPC/LuCI, same-release generic Rill consumer integration, OpenWrt 24.10.8 IPK, 25.12.5 APK, compatibility 24.10.5/25.12.0 builds, rollback gates, and real CFST smoke. The 2.3 Docker replay emits evidence explicitly marked `replayed` and cannot authorize automatic tuning; physical OpenWrt and soak remain `SKIPPED (user-approved)` in this run. Formal promotion is triggered only by a successful `main` `workflow_run`. Package or Docker checks do not prove live OpenWrt or hardware soak.

When fewer candidates qualify, the result reports a degraded candidate count and never duplicates the fastest IP. More sources enlarge the seed pool, but all candidates are retested locally; source count does not mean an unbounded number of IPs in one speed test. LAN Publisher is optional, LAN-only, disabled by default, and never replaces direct PassWall/OpenClash updates.
