# 双 443 + CDN：Debian VPS 服务端、Mihomo 客户端与软路由方案

本方案专为自建高性能代理打造，整合三种协议形态：
1. **VLESS-Vision-REALITY**：监听 **TCP 443**，借用大厂证书直连伪装；
2. **Hysteria 2**：监听 **UDP 443**，双 443 复用互不冲突，极速抗丢包；
3. **VLESS-WS-TLS**：监听 **TCP 8443**，专门配合 Cloudflare CDN（橙云代理）与客户端社区优选域名/优选 IP。

---

## 目录结构

| 路径 | 说明 |
| :--- | :--- |
| `server/` | 服务端配置目录 |
| ├─ `server.json` | 通用双栈 VPS 服务端（Reality TCP 443 + Hy2 UDP 443 + VLESS-WS TCP 8443） |
| └─ `server_v4only.json` | 纯 IPv4 VPS 服务端（安全拒绝公网 IPv6 请求） |
| `client/` | 客户端配置目录（Windows / macOS / Linux 通用） |
| ├─ `mihomo-clash.yaml` | 通用双栈客户端配置（内置 Reality / Hysteria2 / CF-CDN 三节点） |
| ├─ `mihomo-clash-v4only.yaml` | 纯 IPv4 VPS 专属客户端配置（本地 0ms 截断公网 IPv6，触发 Happy Eyeballs 秒退走 IPv4） |
| └─ `nodes.txt` | 节点分享链接汇总（包含 Reality / Hysteria2 / CF-CDN 三节点，每行一个，支持客户端一键全量导入） |
| `router-selfonly/` | Debian 软路由专用本机透明代理与下游物理隔离方案 |
| ├─ `mihomo-homerouter-deb.yaml` | 软路由专用配置（纯 IPv4 加固、TUN `auto-redirect: false`、排除校园网与局域网、支持 `proxy-providers` 外部订阅） |
| └─ `setup-router-guard.sh` | 一键策略路由脚本，将 `iif br-lan` 钉死在主路由表，下游发出的流量 100% 纯软路由透传 |
| `Update-SingboxDual443.py` | 全平台统一批量原地凭据覆写脚本（Python 3 原生，无第三方依赖，支持 Linux/macOS/Windows） |
| `../archives/` | **历史版本归档**：历史 sing-box 客户端与软路由全套配置已移入该目录保存 |

---

## 脚本参数说明

直接编辑 `Update-SingboxDual443.py` 顶部的 `CONFIG` 字典，配置区按协议与杂项清晰分隔：

| 协议分类 | CONFIG 字段 | 用途说明 |
| :--- | :--- | :--- |
| **协议一：REALITY** | `NodeAddress` | VPS 直连 IP 或未开启 CDN 代理的直连域名 |
| | `RealityPort` | REALITY 监听与连接端口（默认 443） |
| | `Uuid` | VLESS 协议用户 UUID |
| | `RealitySni` | Reality 握手 SNI，需与服务端 `server_name` 对应（默认 `www.cloudflare.com`） |
| | `RealityPublicKey` / `RealityPrivateKey` | Reality 密钥对；私钥只写服务端，公钥只写客户端 |
| | `ShortId` | 2-16 位偶数长度十六进制 ShortId |
| | `HandshakeHost` / `HandshakePort` | 服务端 Reality 回落握手目标与端口（默认 `www.cloudflare.com:443`） |
| **协议二：Hysteria 2** | `Hy2Port` | Hysteria 2 监听与连接端口（默认 UDP 443） |
| | `Hy2Sni` | Hy2 证书实际覆盖的域名（在 Cloudflare 保持灰云直连） |
| | `Hy2Password` | Hy2 连接认证密码 |
| | `CertificatePath` / `KeyPath` | Debian VPS 上证书链与私钥绝对路径 |
| **协议三：VLESS-WS (CDN)** | `WsOptimizedDomain` | 客户端连接目标：社区分享的优选域名或 Anycast 优选 IP |
| | `WsPort` | 监听与 Cloudflare 转发端口（推荐 8443） |
| | `WsSni` | CDN 代理域名（在 Cloudflare 开启橙云，如 `cdn.example.com`） |
| | `WsUuid` | VLESS WS 用户 UUID（可与 Uuid 相同或独立） |
| | `WsPath` | WebSocket 传输路径（如 `/api/v3/tunnel-stream`） |
| | `WsCertificatePath` / `WsKeyPath` | 服务端证书与私钥绝对路径（泛域名证书可与 Hy2 相同） |
| | `WsMaxEarlyData` / `WsEarlyDataHeader` | 0-RTT 握手首包长度（默认 2048）与报头名称 |
| **公共与系统杂项** | `MihomoApiSecret` | 本机控制 API 密钥（对应 `REPLACE_WITH_API_SECRET`，访问 Web 面板凭据） |
| | `HeadscaleServer` / `HeadscaleBaseDomain` | （可选）Headscale 控制面域名与 MagicDNS 域名；留空 `''` 时脚本自动剔除规则 |
| | `RuleSetProxy` | （可选）规则集与 Dashboard 下载镜像前缀（默认 `https://gh-proxy.com/`） |
| | `ExternalSubscribes` | （可选）第三方外部机场订阅链接列表（原生列表 `["https://..."]`；留空 `[]` 时保持纯净不启用） |
| | `ApplySubscribesToClients` | （开关）外部订阅是否同时作用于客户端配置（`True`/`False`） |

> 生成密钥对命令：
> ```bash
> sing-box generate uuid
> sing-box generate reality-keypair
> openssl rand -hex 32
> ```

---

## 脚本执行方式

### Linux / macOS / Debian 软路由
```bash
# 预检扫描（不写文件，不暴露凭据）
./Update-SingboxDual443.py --preview

# 执行批量覆写
./Update-SingboxDual443.py
```

### Windows (PowerShell / CMD)
```powershell
# 预检扫描
python .\Update-SingboxDual443.py --preview

# 执行批量覆写
python .\Update-SingboxDual443.py
```

---

## Debian 软路由专用方案说明 (`router-selfonly/`)

专为 **Debian 单系统软路由**（WAN: 无线网卡/临时手机 USB，LAN: 双物理网口网桥 `br-lan`，DHCP: dnsmasq，防火墙: nftables）打造：

1. **下游隔离**：
   - 运行 `sudo ./router-selfonly/setup-router-guard.sh` 添加内核策略路由 `ip rule add iif br-lan table main priority 100`。
   - 软路由配置显式设置 `auto-redirect: false`，绝对不劫持 `br-lan` 下游转发流量，保障下游 Windows 电脑与校园网 Web 认证纯透传。
2. **排除网段**：
   - 显式排除 `192.168.0.0/16`（`br-lan`）、`172.16.0.0/12`、`172.32.0.0/12`（校园网大二层/认证直连）、`10.0.0.0/8` 与 `100.64.0.0/10`（Tailscale）。
3. **多订阅扩展 (`proxy-providers`)**：
   - 配置顶部预设 `0. 外部订阅提供者`。填入外部机场/第三方订阅链接后，`Proxy` 策略组会自动汇聚所有节点。
   - 支持多订阅叠加：复制 `Subscribe_0` 并重命名为 `Subscribe_1`、`Subscribe_2`，在策略组 `use` 中添加对应名字即可。
4. **后台守护进程 (systemd)**：
   创建 `/etc/systemd/system/mihomo.service`：
   ```ini
   [Unit]
   Description=Mihomo Daemon for Debian Router
   After=network.target network-online.target

   [Service]
   Type=simple
   User=root
   ExecStart=/usr/bin/mihomo -d /etc/mihomo -f /etc/mihomo/mihomo-homerouter-deb.yaml
   Restart=on-failure
   RestartSec=5s
   LimitNOFILE=1048576

   [Install]
   WantedBy=multi-user.target
   ```
   启用并启动：
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now mihomo.service
   ```

---

## Web 控制面板与应急直连

1. **访问面板**：
   - 软路由端：局域网设备直接在浏览器访问 `http://192.168.22.1:9090/ui`（密码填写 `MihomoApiSecret`）。
   - 桌面客户端：本地浏览器访问 `http://127.0.0.1:9090/ui`。
2. **应急直连**：
   - `Proxy` 策略组内置 `Reality`、`Hysteria2`、`Direct` 三个出口。自建节点不可用时，在面板中直接切换为 `Direct` 即可恢复直连上网，无需修改配置文件。
