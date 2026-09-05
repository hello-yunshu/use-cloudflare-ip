# luci-app-cloudflare-ip

[English](README.en.md) | **中文**

<p align="center">
  <strong>OpenWrt 上的 Cloudflare IP 优选工具</strong>
</p>

<p align="center">
  自动测速优选 Cloudflare IP 并更新 PassWall / OpenClash 代理节点，通过 LuCI Web 界面管理，无需命令行操作。
</p>

---

## 功能特性

- **LuCI Web 界面**：概览仪表盘、设置表单、日志维护，全部可视化操作
- **PassWall / OpenClash 双模式**：自动检测已安装的代理服务，按需显示对应配置页
- **CFST 自动管理**：首次使用时一键下载 CloudflareSpeedTest，支持在线更新
- **定时任务**：通过 cron 托管计划自动运行，可配置间隔时间
- **IP 类型**：IPv4 / IPv6 / 双栈
- **测速协议**：TCP（默认）/ HTTP（支持按数据中心筛选）
- **连通性验证**：测速后逐个验证 IP 可达性，不可用自动跳过
- **多域名支持**：目标域名支持逗号分隔多个
- **IP 历史记录**：查看历史优选 IP 列表
- **升级策略**：2.1 使用软件包升级；旧脚本自更新入口仅保留迁移兼容性

## 当前版本

当前 2.x 仍是 `2.0 prerelease development line`，当前 package milestone 为
`2.6.0-r2`，GitHub Release 必须保持 prerelease，不代表稳定版。2.6.0 在 2.0 的确定性 Native 安全边界上增加
Candidate Intelligence：上下文指纹与隔离、非阻塞 holdout、受预算约束的 evidence store、
持续 qualification、置信度原因和 LuCI diagnostics。Runtime 仍只有一个 Candidate Learner；
Source Intelligence 与 Reuse 仍分别由确定性 consumer 逻辑和 Native current-IP hard gate 负责。

正式包只从 `main` 的 successful exact-head CI 自动晋级到新的 `v2.6.0-2` prerelease。IPK/APK、
`sha256sums.txt` 和 `qualification.json` 是同一资格化证据链的一部分；真实 OpenWrt 设备、
硬件矩阵和 Soak 不由主机或 SDK 测试替代。

Adaptive Measurement 已实现，是独立的 Native 预探测调度层，默认 Shadow；
它只使用 CFST、来源、历史、前缀/Colo 和上一健康赢家等 pre-probe 字段，绝不创建
第二个 Rill learner 或 partition。Guarded 只有在完整、兼容、未过期的真实审计证据
达到 recall、安全性和节省阈值后才可启用；资格失效、状态损坏或探测错误下一次全量
回退。详见 docs/2.2_ADAPTIVE_MEASUREMENT.md。

Guarded 模式只有在 `probe_top_count` 大于 `adaptive_min_probe_count` 时才会产生明显的 probe savings；默认值保持保守，不为追求表面 savings 放大完整测量规模。

## 安装

### 前置条件

- OpenWrt 24.10.x 或 25.12+
- PassWall 或 OpenClash 已安装
- 代理节点的域名已正确接入 Cloudflare CDN

### 下载安装

从 [Releases](../../releases) 页面下载对应格式的包：

| 包格式 | 适用版本 | 安装命令 |
|--------|---------|---------|
| `.ipk` | OpenWrt 24.10.x | `opkg install luci-app-cloudflare-ip_*.ipk` |
| `.apk` | OpenWrt 25.12+ | `apk add luci-app-cloudflare-ip*.apk` |

安装后刷新浏览器缓存即可在 **服务 → Cloudflare IP 优选** 中看到菜单。

### 包信息

| 项目 | 值 |
|------|-----|
| 包名 | `luci-app-cloudflare-ip` |
| 服务名 | `cf_ip` |
| UCI 配置 | `/etc/config/cf_ip` |
| 核心脚本 | `/usr/bin/cf-ip-auto` |
| RPC 后端 | `cf_ip`（`ubus call cf_ip <method>`） |

> **注意**：本包名为 `luci-app-cloudflare-ip`，与 PassWall（`luci-app-passwall`）和 OpenClash（`luci-app-openclash`）是独立的包，互不依赖。本包仅读取和修改代理配置，不会替换或覆盖 PassWall / OpenClash 本体。

### 校验

```sh
sha256sum -c sha256sums.txt
```

### 依赖

```
bash curl tar jq ca-bundle ca-certificates luci-base rpcd
```

## 使用指南

### 概览页

打开 **服务 → Cloudflare IP 优选**，概览页显示：

- **运行状态**：当前是否运行中、上次结果、运行模式
- **环境检测**：CFST 安装状态（含下载/更新按钮）、PassWall/OpenClash 安装状态
- **优选 IP**：最近一次测速的最佳 IP 列表

CFST 未安装时，点击「下载 CFST」按钮即可自动下载；已安装时显示「更新 CFST」。

### 基本设置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 启用 | 开启定时自动优选 | 关 |
| 模式 | PassWall / OpenClash（自动检测已安装的服务） | PassWall |
| IP 数量 | 保留的优选 IP 个数 | 4 |
| IP 类型 | ipv4 / ipv6 / both | ipv4 |
| 测速协议 | tcp / http | tcp |
| 运行调度 | 自动运行间隔，支持 `6h`/`30m`/cron 表达式，可选 Custom 自定义 | 6h |

### PassWall 设置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 目标域名 | 需要优选的节点域名，逗号分隔多个 | — |
| 名称后缀 | 节点名称后缀，支持 `{n}` 序号和 `{ip}` 占位符 | ` [CF-{n}]` |

筛选 `address` 匹配目标域名的节点，替换为优选 IP。

### Rill Shadow / Assisted

Rill 默认关闭；Runtime 只运行 Candidate Learner（22D、`candidate` partition）。`shadow` 只做候选影子观测，不改变 Native 选出的代理配置；`assisted` 只有在资格化且健康时才可在 Native safe envelope 内偏好候选。Reward v2、跨重启 delayed feedback、rolling qualification、Health/Inspect、resource-pressure fail-closed 和 Native fallback 均保留。来源策略是确定性的 registry/profile/order/cache/scheduler，不是 Runtime Learner；Reuse 是 Native current-IP validation hard gate，失败或配置变更会强制 full optimize。

### OpenClash 设置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 配置文件 | OpenClash YAML 配置文件路径 | `/etc/openclash/config/config.yaml` |
| 目标域名 | 需要优选的节点域名，逗号分隔多个 | — |
| 名称后缀 | 节点名称后缀，支持 `{n}` 序号和 `{ip}` 占位符 | ` [CF-{n}]` |
| 传输协议过滤 | 按传输协议筛选节点（如 `ws,grpc`） | — |
| 备份数量 | 保留的配置备份数 | 3 |
| 配置备份管理 | 在 OpenClash 设置页可直接管理 YAML 备份（列出、恢复、删除） | — |

查找 `server` 匹配目标域名的节点，按 IP 数量生成 `[CF-1]`、`[CF-2]` 等节点。`servername` 和 `Host` 保留原域名。支持 vless / vmess / trojan，需满足 `tls: true` 或 `network` 为 ws / xhttp / grpc / h2 / http。

### 高级设置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 测速前停止代理 | 避免代理干扰测速结果 | 开 |
| 启动延迟 | 随机延迟秒数，`random` = 0~300s | — |
| 自更新 | 已弃用；2.0 由软件包管理 | 关 |
| GitHub 镜像 | 加速 GitHub 下载的镜像地址 | — |
| 下载重试次数 | GitHub 下载失败重试次数 | 3 |
| 重试间隔 | 重试间隔秒数 | 5 |
| 详细日志 | 输出详细运行日志 | 关 |

### 日志与记录

- 查看运行日志
- 查看 IP 历史记录
- 手动触发测速
- 自更新入口仅返回“已弃用”；请通过 IPK/APK 包升级
- 启动 / 停止 / 重启服务

## 项目结构

```
root/
├── etc/
│   ├── config/cf_ip                          # UCI 配置文件
│   └── init.d/cf_ip                          # 生命周期与 cron 调度脚本
└── usr/
    ├── bin/cf-ip-auto                        # 核心业务脚本
    │   ├── libexec/rpcd/cf_ip                    # RPC 后端（兼容 API + 2.0 扩展）
    └── share/
        ├── luci/menu.d/                      # LuCI 菜单注册
        └── rpcd/acl.d/                       # RPC 权限控制

htdocs/luci-static/resources/
├── cloudflare-ip/
│   ├── cloudflare-ip.css                     # 全局样式
│   └── utils.js                              # 共享工具函数
└── view/cloudflare-ip/
    ├── overview.js                           # 概览仪表盘
    ├── settings.js                           # 基本设置
    ├── passwall.js                           # PassWall 配置
    ├── openclash.js                          # OpenClash 配置
    ├── advanced.js                           # 高级设置
    └── diagnostics.js                        # 日志与记录
```

## 架构设计

```
┌──────────────┐     ubus/rpcd     ┌──────────────────┐     UCI      ┌──────────────┐
│  LuCI 前端    │ ──────────────→  │  rpcd 后端        │ ──────────→ │  UCI 配置     │
│  (8 个 JS 视图)│ ←──────────────  │  (兼容 API + 扩展) │ ←──────────  │  cf_ip        │
└──────────────┘     JSON 响应      └──────────────────┘              └──────┬───────┘
                                                                            │
                                                              cf-ip-auto
                                                                            │
                                                                   ┌────────▼────────┐
                                                                   │  CloudflareSpeedTest │
                                                                   │  (自动下载/更新)      │
                                                                   └────────┬────────┘
                                                                            │
                                                              测速 → 验证 → 更新节点
```

**数据流**：

1. 前端通过 `ubus call cf_ip <method>` 调用 rpcd 后端
2. 后端调用 `cf-ip-auto` 执行具体操作
3. 测速结果写入持久状态文件 `/etc/cf_ip/status.json`
4. 根据 UCI 配置的 mode 更新 PassWall 或 OpenClash 节点
5. 日志写入 `/tmp/cf_ip/cf-ip-auto.log`

## UCI 配置参考

### service section

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | 0 | 启用定时自动优选 |
| `mode` | enum | passwall | 代理模式：`passwall` / `openclash` |
| `ip_count` | integer | 4 | 保留的优选 IP 个数 |
| `ip_type` | enum | ipv4 | IP 类型：`ipv4` / `ipv6` / `both` |
| `speedtest_protocol` | enum | tcp | 测速协议：`tcp` / `http` |
| `speedtest_cfcolo` | string | — | 按数据中心筛选（HTTP 协议时有效） |
| `speedtest_dn` | integer | 8 | 下载测速线程数 |
| `speedtest_tll` | integer | 40 | 平均延迟下限（ms），过滤假墙 IP |
| `speedtest_tl` | integer | — | 平均延迟上限（ms），留空不限制 |
| `stop_service` | boolean | 1 | 测速前停止代理服务 |
| `startup_delay` | string | — | 启动延迟，`random` = 0~300s |
| `auto_update` | boolean | 0 | 已弃用的脚本自更新兼容键；2.0 不使用 |
| `self_update_url` | string | — | 自更新下载地址 |
| `download_retries` | integer | 3 | GitHub 下载重试次数 |
| `download_retry_delay` | integer | 5 | 重试间隔秒数 |
| `github_mirror` | string | — | GitHub 镜像加速地址 |
| `verbose` | boolean | 0 | 详细日志 |
| `work_dir` | string | — | 工作目录 |
| `cron_interval` | string | 6h | 自动运行计划，支持 `6h`、`30m` 或 5 字段 cron 表达式 |
| `measurement_timeout` | integer | 60 | 测量与正常应用 deadline（20-300 秒） |
| `recovery_timeout` | integer | 30 | 回滚、恢复服务与恢复确认 deadline（10-120 秒） |
| `probe_batch_size` | integer | 4 | 候选主动探测批次大小（1-16） |
| `max_probe_count` | integer | 8 | 单次最多探测候选数，不超过 `probe_top_count` |
| `early_stop_enabled` | boolean | 1 | 达到安全候选且排序余量足够时确定性提前停止 |
| `source_policy` | enum | balanced | 来源策略：`balanced`、`official-heavy`、`history-heavy`、`diversity-heavy`、`community-heavy` |
| `cfst_persist` | boolean | 1 | sysupgrade 时保留 `${work_dir}/cfst/cfst` |

### passwall section

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `target_domain` | string | — | 目标域名，逗号分隔多个 |
| `name_suffix` | string | ` [CF-{n}]` | 节点名称后缀 |

### openclash section

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `config` | string | `/etc/openclash/config/config.yaml` | YAML 配置文件路径 |
| `target_domain` | string | — | 目标域名，逗号分隔多个 |
| `name_suffix` | string | ` [CF-{n}]` | 节点名称后缀 |
| `transport_filter` | string | — | 传输协议过滤（如 `ws,grpc`） |
| `backup_count` | integer | 3 | 配置备份数量 |

## 构建

本项目使用 GitHub Actions 自动构建：

- 推送到 main 分支触发版本检测和构建
- 也可在 Actions 页面手动触发

## 致谢

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
## 2.6 Intelligence 引擎

包版本 `2.6.0` 在完整的 1.8.3 行为基线和 2.0 closure 上演进。Overview、Settings、Diagnostics、PassWall、OpenClash、定时任务、CFST、名称后缀、多 IP、备份和升级行为均保留；确定性候选来源、限额调度、目标域名主动探测、Native Rank、事务化应用/回滚、单一 Candidate Learner、Native Reuse hard gate、可选通用 Rill Runtime v3 Preview shadow 和可选 LAN Publisher 为新增能力。Adaptive Measurement 只消费 pre-probe 字段，默认 Shadow，完整审计才允许 Guarded；Operational Health 只允许保守降级。Product Intelligence 页面展示当前 Endpoint、System Health、Adaptive、Candidate、下一次审计/优化和有限历史，不引入第二个 learner 或大型 dashboard。Candidate 的 training feedback 与 evaluation evidence 分离；Material context change 会轮换 lineage、隔离旧 evidence，并允许新 context 在重新资格化后恢复 Assisted。Generic Rill runtime contract 由 `hello-yunshu/rill-ml` 负责；OpenWrt package/distribution 由 `hello-yunshu/rill-openwrt-packages` 负责，并以独立的 `rill-runtime-preview` 包锁定资格化 Preview commit。Cloudflare 只保留消费者映射；启用 Rill 时需额外安装同版本 `luci-app-cloudflare-ip-rill`，Runtime 由 package manager 提供。

候选测速数量默认 128，允许 100-512 个唯一候选。历史优质 IP、社区种子和 Cloudflare 官方网段探索约占 1/8、5/8、1/4；官方 CIDR 会先由调度器采样为具体 IP，每个任务只启动一次 CFST。社区源中的 `IP:port` 只贡献 IP，域名候选会被拒绝且不会 DNS 解析。

应用 PassWall 或 OpenClash 前，每个选中 IP 都必须使用正确 SNI/Host 通过目标域名探测。Host transaction 在关闭代理前保存配置和服务状态，测量 deadline 只约束测速、探测、应用和正常重启；失败后进入独立 recovery deadline，执行纯变换、block 级意图映射回读、回滚、恢复服务和健康检查。超时、资格探测失败或重启失败都会回滚并恢复原服务状态；Rill 出错时回退到 Native Rank。Shadow 对 Rill 选择但未应用的候选执行独立探测；只有 candidate-specific、未被 host failure censor 的 outcome 才会进入延迟反馈队列。

2.0 的自更新已弃用，因为引擎是多文件、由软件包管理。默认 `auto_update=0`，请通过经过验证的 IPK/APK 升级。UCI、CFST、来源 last-good 缓存、managed ownership 和有限历史会保留；运行、探测和 publisher 文件可重建。LAN Publisher 默认关闭，只允许 LAN 绑定，拒绝 `0.0.0.0`，提供 `/ip.txt`、`/best-ipv4.txt`、`/best-ipv6.txt` 和 `/result.json`。

发布门禁：稳定发布必须通过完整 legacy 矩阵、Host/RPC/LuCI、同版本通用 Rill consumer integration、当前 OpenWrt 24.10.8 IPK、25.12.5 APK 以及兼容性 24.10.5/25.12.0 gate、回滚和真实 CFST smoke；Docker/软件包检查不等同于真实 OpenWrt 设备或硬件 soak。2.3 Docker 回放只产生标记为 `replayed` 的证据，不授权自动调参；物理 OpenWrt 和 soak 在本轮保持 `SKIPPED (user-approved)`。正式 release 只由 `main` workflow_run 触发。

候选不足时报告 degraded candidate count，绝不复制最快 IP 伪造数量；多个来源会增加可用 seed 池，但所有候选仍在本地统一重测，来源数量不等于单次测速数量无限增加。LAN Publisher 仅为默认关闭的 LAN 可选兼容输出，不替代 PassWall/OpenClash 直接修改。
