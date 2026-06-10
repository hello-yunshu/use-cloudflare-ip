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
- **定时任务**：通过 procd 守护进程自动运行，可配置间隔时间
- **IP 类型**：IPv4 / IPv6 / 双栈
- **测速协议**：TCP（默认）/ HTTP（支持按数据中心筛选）
- **连通性验证**：测速后逐个验证 IP 可达性，不可用自动跳过
- **多域名支持**：目标域名支持逗号分隔多个
- **IP 历史记录**：查看历史优选 IP 列表
- **自更新**：脚本支持从 GitHub 自动更新

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
| 自更新 | 启用脚本自更新 | 开 |
| GitHub 镜像 | 加速 GitHub 下载的镜像地址 | — |
| 下载重试次数 | GitHub 下载失败重试次数 | 3 |
| 重试间隔 | 重试间隔秒数 | 5 |
| 详细日志 | 输出详细运行日志 | 关 |

### 日志与记录

- 查看运行日志
- 查看 IP 历史记录
- 手动触发测速
- 手动更新脚本
- 启动 / 停止 / 重启服务

## 项目结构

```
root/
├── etc/
│   ├── config/cf_ip                          # UCI 配置文件
│   └── init.d/cf_ip                          # procd 服务脚本
└── usr/
    ├── bin/cf-ip-auto                        # 核心业务脚本
 │   ├── libexec/rpcd/cf_ip                    # RPC 后端（15 个 API 方法）
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
│  (6 个 JS 视图)│ ←──────────────  │  (15 个 API 方法)  │ ←──────────  │  cf_ip        │
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
3. 测速结果写入状态文件 `/tmp/cf_ip/status.json`
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
| `speedtest_dn` | integer | 10 | 下载测速线程数 |
| `speedtest_tll` | integer | 40 | 平均延迟下限（ms），过滤假墙 IP |
| `speedtest_tl` | integer | — | 平均延迟上限（ms），留空不限制 |
| `stop_service` | boolean | 1 | 测速前停止代理服务 |
| `startup_delay` | string | — | 启动延迟，`random` = 0~300s |
| `auto_update` | boolean | 1 | 启用脚本自更新 |
| `self_update_url` | string | — | 自更新下载地址 |
| `download_retries` | integer | 3 | GitHub 下载重试次数 |
| `download_retry_delay` | integer | 5 | 重试间隔秒数 |
| `github_mirror` | string | — | GitHub 镜像加速地址 |
| `verbose` | boolean | 0 | 详细日志 |
| `work_dir` | string | — | 工作目录 |
| `cron_interval` | string | 6h | 自动运行计划，支持 `6h`、`30m` 或 5 字段 cron 表达式 |

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
