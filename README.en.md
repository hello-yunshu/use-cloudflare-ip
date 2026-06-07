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
- **Scheduled Tasks**: Automatic runs via procd daemon with configurable intervals
- **IP Type**: IPv4 / IPv6 / Dual-stack
- **Benchmark Protocol**: TCP (default) / HTTP (with data center filtering)
- **Connectivity Verification**: Validates each IP after benchmarking, skips unreachable ones
- **Multi-Domain Support**: Comma-separated target domains
- **IP History**: View historical optimized IP list
- **Self-Update**: Script auto-updates from GitHub

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
| Run Interval | Auto-run interval in minutes | 360 |

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

Finds nodes where `server` matches the target domain, generates `[CF-1]`, `[CF-2]`, etc. based on IP count. `servername` and `Host` preserve the original domain. Supports vless / vmess / trojan, requiring `tls: true` or `network` being ws / xhttp / grpc / h2 / http.

### Advanced Settings

| Option | Description | Default |
|--------|-------------|---------|
| Stop Proxy Before Benchmark | Avoid proxy interference with benchmark results | On |
| Startup Delay | Random delay in seconds, `random` = 0~300s | — |
| Self-Update | Enable script self-update | On |
| GitHub Mirror | Mirror URL to accelerate GitHub downloads | — |
| Download Retries | GitHub download retry count | 3 |
| Retry Delay | Retry interval in seconds | 5 |
| Verbose Logging | Output detailed runtime logs | Off |

### Logs & Maintenance

- View runtime logs
- View IP history
- Manually trigger benchmark
- Manually update script
- Start / Stop / Restart service

## Project Structure

```
root/
├── etc/
│   ├── config/cf_ip                          # UCI configuration
│   └── init.d/cf_ip                          # procd service script
└── usr/
    ├── bin/cf-ip-auto                        # Core business script
    ├── libexec/rpcd/cf_ip                    # RPC backend (13 API methods)
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
    └── diagnostics.js                        # Logs & maintenance
```

## Architecture

```
┌──────────────┐     ubus/rpcd     ┌──────────────────┐     UCI      ┌──────────────┐
│  LuCI Frontend│ ──────────────→  │  rpcd Backend     │ ──────────→ │  UCI Config   │
│  (6 JS views) │ ←──────────────  │  (13 API methods) │ ←──────────  │  cf_ip        │
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
3. Benchmark results are written to `/tmp/cf_ip/status.json`
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
| `speedtest_dn` | integer | 10 | Download benchmark threads |
| `speedtest_tll` | integer | 40 | Average latency floor (ms), filter fake IPs |
| `speedtest_tl` | integer | — | Average latency ceiling (ms), leave empty for no limit |
| `stop_service` | boolean | 1 | Stop proxy service before benchmarking |
| `startup_delay` | string | — | Startup delay, `random` = 0~300s |
| `auto_update` | boolean | 1 | Enable script self-update |
| `self_update_url` | string | — | Self-update download URL |
| `download_retries` | integer | 3 | GitHub download retry count |
| `download_retry_delay` | integer | 5 | Retry interval in seconds |
| `github_mirror` | string | — | GitHub mirror URL for acceleration |
| `verbose` | boolean | 0 | Verbose logging |
| `work_dir` | string | — | Working directory |
| `cron_interval` | string | 6h | Auto-run schedule, supports `6h`, `30m`, or a 5-field cron expression |

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
