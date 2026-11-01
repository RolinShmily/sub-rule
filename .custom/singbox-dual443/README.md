# 双 443：Debian VPS 服务端、Mihomo 客户端与软路由方案

本方案专为自建双 443 协议节点打造：VLESS-Reality 监听 **TCP 443**，Hysteria2 监听 **UDP 443**。端口完全复用互不冲突，Nginx 伪装站独立监听 TCP 8443。

---

## 目录结构

| 路径 | 说明 |
| :--- | :--- |
| `server/` | 服务端配置目录 |
| ├─ `server.json` | 通用双栈 VPS 服务端（Reality TCP 443 + Hy2 UDP 443） |
| └─ `server_v4only.json` | 纯 IPv4 VPS 服务端（安全拒绝公网 IPv6 请求） |
| `client/` | 客户端配置目录（Windows / macOS / Linux 通用） |
| ├─ `mihomo-clash.yaml` | 通用双栈客户端配置 |
| └─ `mihomo-clash-v4only.yaml` | 纯 IPv4 VPS 专属客户端配置（本地 0ms 截断公网 IPv6，触发 Happy Eyeballs 秒退走 IPv4） |
| `router-selfonly/` | Debian 软路由专用本机透明代理与下游物理隔离方案 |
| ├─ `mihomo-homerouter-deb.yaml` | 软路由专用配置（纯 IPv4 加固、TUN `auto-redirect: false`、排除校园网与局域网、支持 `proxy-providers` 外部订阅） |
| └─ `setup-router-guard.sh` | 一键策略路由脚本，将 `iif br-lan` 钉死在主路由表，下游发出的流量 100% 纯软路由透传 |
| `nodes/` | 节点分享链接（`vless.txt` 与 `hysteria2.txt`，由脚本自动同步生成，与服务端同源） |
| `Update-SingboxDual443.py` | 全平台统一批量原地凭据覆写脚本（Python 3 原生，无第三方依赖，支持 Linux/macOS/Windows） |
| `../archives/` | **历史版本归档**：历史 sing-box 客户端与软路由全套配置已移入该目录保存 |

---

## 脚本参数说明

直接编辑 `Update-SingboxDual443.py` 顶部的 `CONFIG` 字典，填入参数后再运行脚本：

| CONFIG 字段 | 用途说明 |
| :--- | :--- |
| `NodeAddress` | 客户端连接的 VPS 域名或 IP（对应 `REPLACE_WITH_NODE_ADDRESS`） |
| `Hy2Sni` | Hy2 证书实际覆盖的域名（对应 `REPLACE_WITH_HY2_SNI`） |
| `RealitySni` | Reality 握手 SNI，需与服务端 `server_name` 对应（默认 `www.cloudflare.com`） |
| `HandshakeHost` / `HandshakePort` | 服务端 Reality 回落握手目标与端口（默认 `www.cloudflare.com:443`） |
| `Uuid` / `ShortId` | VLESS UUID 与 short ID（2-16 位偶数长度十六进制） |
| `RealityPrivateKey` / `RealityPublicKey` | Reality 密钥对；私钥只写服务端，公钥只写客户端 |
| `Hy2Password` | Hy2 连接密码（服务端与客户端一致） |
| `CertificatePath` / `KeyPath` | Debian VPS 上证书链与私钥的绝对路径（对应 `REPLACE_WITH_CERTIFICATE_PATH` / `KEY_PATH`） |
| `SingboxApiSecret` / `MihomoApiSecret` | 本机控制 API 密钥（对应 `REPLACE_WITH_API_SECRET`，访问 Web 面板凭据） |
| `HeadscaleServer` / `HeadscaleBaseDomain` | （可选）Headscale 控制面域名与 MagicDNS 域名；留空 `''` 时脚本自动剔除规则 |
| `RuleSetProxy` | （可选）规则集与 Dashboard 下载镜像前缀，默认预设为 `https://gh-proxy.com/`，必须以 `/` 结尾。留空 `''` 则直连上游下载 |
| `ExternalSubscribes` | （可选）第三方外部机场订阅链接列表（原生列表 `["https://..."]`；留空 `[]` 时保持纯净不启用） |
| `ApplySubscribesToClients` | （开关）外部订阅是否同时作用于客户端配置（`True`: 客户端也注入订阅；`False`（默认）: 仅软路由注入，客户端保持纯净自建） |

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
