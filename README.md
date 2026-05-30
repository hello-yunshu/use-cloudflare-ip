# use-cloudflare-ip

使用 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 在 OpenWrt 上优选 Cloudflare IP，自动写入 PassWall 或 OpenClash 配置。

> 📖 **图文教程**：[Cloudflare 优选 IP + OpenWrt 自动配置](https://hey.run/posts/cloudflare-ip-auto-openwrt/)

## 快速开始

**1. 安装依赖**

OpenWrt 25.12+：

```sh
apk update
apk add bash curl tar jq ca-bundle ca-certificates
```

OpenWrt 24.10 及更早：

```sh
opkg update
opkg install bash curl tar jq ca-bundle ca-certificates
```

**2. 初始化**

```sh
cp cf-openwrt-auto.conf.example cf-openwrt-auto.conf
chmod +x cf-openwrt-auto.sh
```

编辑 `cf-openwrt-auto.conf`，填入目标域名等配置。

**3. 运行**

```sh
./cf-openwrt-auto.sh
```

## 前置条件

- PassWall 模式：已安装 PassWall，系统可用 `uci` 命令
- OpenClash 模式：已安装 OpenClash，知道当前使用的 YAML 配置文件路径
- 代理节点的域名已正确接入 Cloudflare CDN

## 文件说明

| 文件 | 说明 |
|------|------|
| `cf-openwrt-auto.sh` | 执行脚本 |
| `cf-openwrt-auto.conf.example` | 配置模板（中英双语注释） |
| `cf-openwrt-auto.conf` | 实际配置，需从模板复制，已加入 `.gitignore` |

脚本自升级只替换 `.sh`，不会覆盖 `.conf`。

## 功能概览

- **IP 类型**：`ipv4` / `ipv6` / `both`
- **测速协议**：`tcp`（默认）/ `http`（支持按数据中心筛选）
- **IP 数量**：`IP_COUNT` 控制保留个数，不足时自动补齐
- **连通性验证**：测速后逐个验证 IP 可达性，不可用自动跳过
- **多域名支持**：目标域名支持逗号分隔多个
- **节点名称后缀**：支持 `{n}` 序号、`{ip}` 地址占位符
- **OpenClash 协议过滤**：`OPENCLASH_TRANSPORT_FILTER` 可按传输协议筛选
- **IP 历史记录**：追加到 `ip-all.txt`，超 1000 行自动截断

## PassWall 模式

筛选 `address` 匹配目标域名的节点，替换为优选 IP，`uci commit` 后重启 PassWall。

## OpenClash 模式

查找 `server` 匹配目标域名的节点，按 `IP_COUNT` 生成 `[CF-1]`、`[CF-2]` 等节点。`servername` 和 `Host` 保留原域名。支持 vless / vmess / trojan，需满足 `tls: true` 或 `network` 为 ws / xhttp / grpc / h2 / http。

## 定时运行

```cron
0 */6 * * * /path/to/cf-openwrt-auto.sh
```

推荐每 6 小时一次，不建议低于每小时一次。

## 其他配置

| 配置项 | 说明 |
|--------|------|
| `VERBOSE` | `true` 输出详细日志，也可 `./cf-openwrt-auto.sh --verbose` |
| `AUTO_UPDATE` | `true` 启用脚本自升级 |
| `STARTUP_DELAY` | 启动随机延迟，`random` = 0~300s，`0` = 不等待 |
| `DOWNLOAD_RETRIES` | GitHub 下载重试次数，默认 3 |
| `DOWNLOAD_RETRY_DELAY` | 重试间隔秒数，默认 5 |

## 致谢

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
