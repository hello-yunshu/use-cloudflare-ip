# use-cloudflare-ip

使用 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 在 OpenWrt 上优选 Cloudflare IP，并自动写入 PassWall 或 OpenClash 配置。

脚本适合放在路由器上定时静默运行：成功时不输出内容，失败时只向 stderr 输出错误。它会把节点里的连接地址改成优选 IP，同时把原始域名保留在 SNI、Host 等字段中，避免 TLS 或 CDN 回源识别失败。

## 依赖

先在 OpenWrt 上安装基础依赖：

```sh
opkg update
opkg install bash curl wget tar jq ca-bundle ca-certificates
```

还需要满足：

- PassWall 模式需要已安装 PassWall，并且系统可用 `uci` 命令。
- OpenClash 模式需要已安装 OpenClash，并知道当前使用的 YAML 配置文件路径。
- 代理节点的域名已经正确接入 Cloudflare CDN。

脚本会自动下载当前设备架构对应的 `cfst`，也就是 CloudflareSpeedTest 的可执行文件。

脚本里的架构映射按 CloudflareSpeedTest 当前 Linux 发布包对齐：`386`、`amd64`、`arm64`、`armv5`、`armv6`、`armv7`、`mips`、`mips64`、`mipsle`、`mips64le`。

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

## 配置示例

```sh
# Config version / 配置文件版本:
#   The script checks this against the minimum required config version.
#   脚本会检查它是否满足最低配置版本要求；不要删除这一项。
CONFIG_VERSION="1.1.0"

# Mode / 运行模式:
#   passwall  = update PassWall nodes / 修改 PassWall 节点
#   openclash = update OpenClash YAML proxies / 修改 OpenClash YAML 里的代理节点
MODE="passwall"

# Work directory / 工作目录:
#   Empty means script directory / 留空表示使用脚本所在目录。
#   cfst binary, cf_result.txt, and ip-all.txt will be stored here.
#   cfst 二进制、测速结果、历史 IP 都会保存在这里。
WORK_DIR=""

# IP count / 优选 IP 数量:
#   Keep the fastest 4 IPs by default / 默认保留 4 个最快 IP。
#   If fewer IPs are found, the fastest one is reused / 不足时用最快 IP 补齐。
IP_COUNT="4"

# CloudflareSpeedTest options / 测速参数:
#   SPEEDTEST_DN  maps to cfst -dn / 下载测速数量
#   SPEEDTEST_TLL maps to cfst -tll / 平均延迟上限
SPEEDTEST_DN="10"
SPEEDTEST_TLL="40"

# PassWall target domain / PassWall 目标域名:
#   The script scans `uci show passwall` and updates only nodes whose
#   address equals this domain.
#   脚本会扫描 `uci show passwall`，只修改 address 等于该域名的节点。
PASSWALL_TARGET_DOMAIN="cdn.example.com"

# OpenClash target / OpenClash 目标:
#   OPENCLASH_CONFIG is the active YAML config path.
#   OPENCLASH_CONFIG 是 OpenClash 当前使用的 YAML 配置文件路径。
#   Only proxies whose server equals OPENCLASH_TARGET_DOMAIN are updated.
#   只修改 server 等于 OPENCLASH_TARGET_DOMAIN 的代理节点。
OPENCLASH_CONFIG="/etc/openclash/config/config.yaml"
OPENCLASH_TARGET_DOMAIN="cdn.example.com"

# Self update / 脚本自升级:
#   true  = check this script version on startup and auto-upgrade if newer
#           启动时检查脚本版本，有新版就自动升级
#   false = never update this script automatically
#           禁用脚本自动升级
#   The local cf-openwrt-auto.conf is never overwritten by self-update.
#   自升级只替换脚本，不会覆盖本地 cf-openwrt-auto.conf。
AUTO_UPDATE="true"
SELF_UPDATE_URL="https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/cf-openwrt-auto.sh"

# Verbose / 调试输出:
#   false = silent on success / 成功时静默
#   true  = print progress to stderr / 输出过程日志到 stderr
VERBOSE="false"
```

## PassWall 模式

设置：

```sh
MODE="passwall"
PASSWALL_TARGET_DOMAIN="cdn.example.com"
```

脚本会读取：

```sh
uci show passwall
```

然后筛选所有 `address` 等于 `PASSWALL_TARGET_DOMAIN` 的节点。比如有 4 个 PassWall 节点都填了：

```text
address = cdn.example.com
```

测速得到 4 个 IP 后，会依次执行类似操作：

```sh
uci set passwall.<matched-section-1>.address=<fast-ip-1>
uci set passwall.<matched-section-2>.address=<fast-ip-2>
uci set passwall.<matched-section-3>.address=<fast-ip-3>
uci set passwall.<matched-section-4>.address=<fast-ip-4>
uci commit passwall
/etc/init.d/passwall restart
```

如果只测速出 1 个可用 IP，会自动补齐，多个匹配节点都会写入同一个最快 IP。

PassWall 的配置保存在 UCI 中，运行中的进程需要重启 PassWall 后才会重新生成并加载节点配置。脚本只重启 `passwall` 服务；HAProxy 负载均衡由 PassWall 自己的启动流程处理。

## OpenClash 模式

设置：

```sh
MODE="openclash"
OPENCLASH_CONFIG="/etc/openclash/config/config.yaml"
OPENCLASH_TARGET_DOMAIN="cdn.example.com"
```

脚本会查找 `server` 等于 `OPENCLASH_TARGET_DOMAIN` 的代理节点，并把这些节点的 `server` 改成测速得到的 IP。`servername` 和 `Host` 会保留为原域名。

写入 YAML 后，脚本会执行：

```sh
/etc/init.d/openclash restart
```

OpenClash 需要重启后才会重新读取修改后的配置文件。如果只改 YAML 而不重启，正在运行的 OpenClash 通常不会自动使用新 IP。

示例节点：

```yaml
- name: xxxxx
  type: vless
  server: cdn.example.com
  port: 443
  uuid: xxxxx
  client-fingerprint: chrome
  tls: true
  network: ws
  ws-opts:
    path: /xxx
    headers:
      Host: cdn.example.com
  skip-cert-verify: false
  servername: cdn.example.com
```

更新后类似：

```yaml
- name: xxxxx
  type: vless
  server: 104.18.1.1
  port: 443
  uuid: xxxxx
  client-fingerprint: chrome
  tls: true
  network: ws
  ws-opts:
    path: /xxx
    headers:
      Host: cdn.example.com
  skip-cert-verify: false
  servername: cdn.example.com
```

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

脚本内置版本号 `SCRIPT_VERSION`。当配置里：

```sh
AUTO_UPDATE="true"
```

脚本启动后会从 `SELF_UPDATE_URL` 下载远端脚本，读取远端 `SCRIPT_VERSION`。如果远端版本高于本地版本，会先做 `bash -n` 语法检查，通过后替换当前脚本并重新执行。

配置文件也有版本号 `CONFIG_VERSION`。脚本会检查它是否满足当前脚本的最低配置版本要求；如果缺失、格式不正确，或低于最低要求，会直接输出错误并退出，提示你根据 `cf-openwrt-auto.conf.example` 更新配置文件。

自升级只会替换：

```text
cf-openwrt-auto.sh
```

不会修改：

```text
cf-openwrt-auto.conf
```

如果你用 Git 管理这个目录，`cf-openwrt-auto.conf` 也已经被 `.gitignore` 忽略。只要你没有手动把它 `git add -f` 进仓库，正常 `git pull` 不会覆盖本地配置。

## 静默与调试

默认：

```sh
VERBOSE="false"
```

成功运行不会输出内容，适合 cron 定时任务。失败会输出类似：

```text
[cloudflare-ip] ERROR: no PassWall nodes matched address: cdn.example.com
```

手动排查时可以临时改成：

```sh
VERBOSE="true"
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
