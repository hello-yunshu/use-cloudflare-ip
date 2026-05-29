# use-cloudflare-ip

使用 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 在 OpenWrt 上优选 Cloudflare IP，并自动写入 PassWall 或 OpenClash 配置。

脚本适合放在路由器上定时静默运行：成功时不输出内容，失败时只向 stderr 输出错误。它会把节点里的连接地址改成优选 IP，同时把原始域名保留在 SNI、Host 等字段中，避免 TLS 或 CDN 回源识别失败。

## 依赖

先在 OpenWrt 上安装基础依赖。

OpenWrt 25.12+ 使用 apk：

```sh
apk update
apk add bash curl tar jq ca-bundle ca-certificates
```

OpenWrt 24.10 及更早版本使用 opkg：

```sh
opkg update
opkg install bash curl tar jq ca-bundle ca-certificates
```

还需要满足：

- PassWall 模式需要已安装 PassWall，并且系统可用 `uci` 命令。
- OpenClash 模式需要已安装 OpenClash，并知道当前使用的 YAML 配置文件路径。
- 代理节点的域名已经正确接入 Cloudflare CDN。

脚本会自动下载当前设备架构对应的 `cfst`，也就是 CloudflareSpeedTest 的可执行文件。

脚本里的架构映射按 CloudflareSpeedTest 当前 Linux 发布包对齐：`386`、`amd64`、`arm64`、`armv5`、`armv6`、`armv7`、`mips`、`mips64`、`mipsle`、`mips64le`。

如果路由器访问 GitHub 不稳定，也可以手动下载对应架构的压缩包，例如：

```text
cfst_linux_amd64.tar.gz
```

把它放到 `WORK_DIR` 目录里即可；`WORK_DIR` 默认就是脚本所在目录。脚本下载失败时会自动使用这个本地包。如果目录里已经有可执行的 `cfst`，GitHub 临时不可用时也会继续使用现有 `cfst` 运行。

## 文件

- `cf-openwrt-auto.sh`：执行脚本。
- `cf-openwrt-auto.conf.example`：配置模板，带中英结合说明。
- `cf-openwrt-auto.conf`：实际配置文件，需要从模板复制生成，并和脚本放在同一目录。

`cf-openwrt-auto.conf` 已加入 `.gitignore`，不会被 Git 跟踪。正常 `git pull` 不会覆盖你的本地配置；脚本自升级也只替换 `cf-openwrt-auto.sh`，不会覆盖 `cf-openwrt-auto.conf`。

## 初始化

```sh
cp cf-openwrt-auto.conf.example cf-openwrt-auto.conf
chmod +x cf-openwrt-auto.sh
```

然后编辑 `cf-openwrt-auto.conf`。运行时不需要传参数：

```sh
./cf-openwrt-auto.sh
```

## 功能

### 优选 IP 数量

`IP_COUNT` 控制保留多少个最快 IP，默认 4 个。如果测速结果不足，会用最快的第 1 个 IP 自动补齐。

### IP 类型

`IP_TYPE` 支持三种模式：

- `ipv4`：只测 IPv4 地址（使用 ip.txt）
- `ipv6`：只测 IPv6 地址（使用 ipv6.txt）
- `both`：同时测 IPv4 和 IPv6（先 ip.txt 再 ipv6.txt，合并结果）

### 测速协议

`SPEEDTEST_PROTOCOL` 支持两种测速方式：

- `tcp`：TCPing 模式（默认），测 TCP 连接延迟，速度快
- `http`：HTTPing 模式，测 HTTP 响应延迟，更贴近实际使用场景

HTTPing 模式下可通过 `SPEEDTEST_CFCOLO` 按 Cloudflare 数据中心筛选，多个用逗号分隔（如 `HKG,NRT,LAX`），留空不筛选。

`SPEEDTEST_DN` 和 `SPEEDTEST_TLL` 分别对应 cfst 的下载测速数量和平均延迟上限。

### IP 连通性验证

如果配置了目标域名（`PASSWALL_TARGET_DOMAIN` 或 `OPENCLASH_TARGET_DOMAIN`），脚本会在测速后逐个验证优选 IP 是否能通过该域名正常访问。不可达的 IP 会被跳过，确保写入配置的 IP 都是可用的。

如果配置了多个域名，IP 必须对所有域名都可达才会被选用。

如果所有 IP 都验证失败，会回退使用测速结果中最快的 IP，并输出警告。

### 多域名支持

`PASSWALL_TARGET_DOMAIN` 和 `OPENCLASH_TARGET_DOMAIN` 支持多个域名，用逗号分隔：

```sh
PASSWALL_TARGET_DOMAIN="cdn1.example.com,cdn2.example.com"
OPENCLASH_TARGET_DOMAIN="cdn1.example.com,cdn2.example.com"
```

每个域名的处理方式相同。单域名配置无需任何修改，完全向后兼容。

### IP 历史记录

每次运行后，优选 IP 会追加到 `ip-all.txt`。文件超过 1000 行时自动截断，只保留最近的记录。

### 节点名称后缀

PassWall 和 OpenClash 模式都支持节点名称后缀（`PASSWALL_NAME_SUFFIX` / `OPENCLASH_NAME_SUFFIX`），修改节点后会在原始名称后面追加后缀。支持占位符：

- `{n}`：序号，从 1 开始
- `{ip}`：优选 IP 地址

留空则不修改节点名称。

### OpenClash 传输协议过滤

`OPENCLASH_TRANSPORT_FILTER` 可以只修改指定传输协议的代理节点，留空则修改所有支持的节点。可选值：`ws`、`grpc`、`xhttp`、`h2`、`http`，多个用逗号分隔。

## PassWall 模式

脚本会读取：

```sh
uci show passwall
```

然后筛选所有 `address` 等于 `PASSWALL_TARGET_DOMAIN` 中任一域名的节点。测速得到 IP 后，会依次把匹配节点的 `address` 改成优选 IP，然后 `uci commit passwall` 并重启 PassWall 服务。

如果只测速出 1 个可用 IP，会自动补齐，多个匹配节点都会写入同一个最快 IP。

PassWall 的配置保存在 UCI 中，运行中的进程需要重启 PassWall 后才会重新生成并加载节点配置。脚本只重启 `passwall` 服务；HAProxy 负载均衡由 PassWall 自己的启动流程处理。

## OpenClash 模式

脚本首次运行会查找 `server` 等于 `OPENCLASH_TARGET_DOMAIN` 中任一域名的代理节点作为模板，并按配置里的 `IP_COUNT` 生成带 `[CF-1]`、`[CF-2]` 这类后缀的代理节点。后续运行会优先按这些标记刷新对应节点；如果只剩 `[CF-1]`，也会按 `IP_COUNT` 自动补齐缺少的节点。`server` 会改成测速得到的 IP，`servername` 和 `Host` 会保留为该节点匹配到的原域名。

写入 YAML 后，脚本会重启 OpenClash 服务。OpenClash 需要重启后才会重新读取修改后的配置文件。如果只改 YAML 而不重启，正在运行的 OpenClash 通常不会自动使用新 IP。

## OpenClash 协议判断

脚本只自动更新常见 Cloudflare CDN 代理场景：

- `type: vless`
- `type: vmess`
- `type: trojan`

并且节点需要满足以下任一条件：

- `tls: true`
- `network: ws`
- `network: xhttp`
- `network: grpc`
- `network: h2`
- `network: http`

对于 `network: ws`，脚本会确保 `ws-opts.headers.Host` 是目标域名。对于 `network: xhttp`，脚本会确保 `xhttp-opts.headers.Host` 是目标域名。对于 `tls: true`，脚本会确保 `servername` 是目标域名。

不符合条件的节点会被跳过，避免把不支持 SNI 或 Host 保留域名的协议错误改成 IP。

## 版本与自升级

脚本内置版本号 `SCRIPT_VERSION`。当配置里 `AUTO_UPDATE="true"` 时，脚本启动后会从 `SELF_UPDATE_URL` 下载远端脚本，读取远端 `SCRIPT_VERSION`。如果远端版本高于本地版本，会先做 `bash -n` 语法检查，通过后替换当前脚本并重新执行。

配置文件也有版本号 `CONFIG_VERSION`。脚本会检查它是否满足当前脚本的最低配置版本要求；如果缺失、格式不正确，或低于最低要求，会直接输出错误并退出，提示你根据 `cf-openwrt-auto.conf.example` 更新配置文件。

自升级只会替换 `cf-openwrt-auto.sh`，不会修改 `cf-openwrt-auto.conf`。如果你用 Git 管理这个目录，`cf-openwrt-auto.conf` 也已经被 `.gitignore` 忽略。只要你没有手动把它 `git add -f` 进仓库，正常 `git pull` 不会覆盖本地配置。

## 静默与调试

默认 `VERBOSE="false"`，成功运行不会输出内容，适合 cron 定时任务。失败会输出类似：

```text
[cloudflare-ip] ERROR: no PassWall nodes matched address: cdn.example.com
```

手动排查时可以临时改成 `VERBOSE="true"`。

也可以不改配置，直接在终端这样运行：

```sh
./cf-openwrt-auto.sh --verbose
```

开启后会输出自升级检查、CloudflareSpeedTest 版本检查、下载、测速、连通性验证、配置更新和服务重启等步骤。

GitHub 下载相关步骤默认会重试 3 次，每次间隔 5 秒；可以在配置里调整：

```sh
DOWNLOAD_RETRIES="3"
DOWNLOAD_RETRY_DELAY="5"
```

## 定时运行

配置文件和脚本在同一目录，定时任务只需要执行脚本本身：

```cron
0 */6 * * * /path/to/cf-openwrt-auto.sh
```

推荐默认每 6 小时运行一次。Cloudflare 优选 IP 的质量会随运营商、时间段和线路状态变化，但一般没必要高频测速；6 小时能兼顾可用性和资源占用。

可以按实际网络情况调整：

- 网络稳定：每天 1 次
- 常规使用：每 6 小时 1 次
- 波动明显：每 3 小时 1 次

不建议低于每小时 1 次，测速会占用路由器 CPU 和网络资源，也可能造成没有必要的连接波动。

如果不想让 cron 邮件接收错误输出，可以自行重定向：

```cron
0 */6 * * * /path/to/cf-openwrt-auto.sh >/dev/null 2>&1
```

## 致谢

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
