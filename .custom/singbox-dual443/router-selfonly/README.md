# Debian 软路由专用本机透明代理方案 (sing-box / Mihomo)

本目录专为 **Debian 单系统软路由**（WAN: 无线网卡/临时手机 USB，LAN: 双物理网口网桥 `br-lan`，DHCP: dnsmasq，防火墙: nftables）打造，同时提供 **sing-box** 与 **Mihomo** 两套开箱即用的透明代理方案，用户可按喜好任选其一。

### 核心设计目标
- **下游设备（Windows PC / 交换机 / 下级路由）**：100% 保持**纯软路由透传**。Debian 仅负责 DHCP、DNS 缓存和 NAT 转发，下游发出的流量绝不进入代理核心（sing-box 或 Mihomo），排障链路极简，校园网认证无阻。
- **Debian 宿主机自身**：享受与桌面客户端完全一致的**全自动无感智能分流**。命令行 `curl`、`apt`、`git`、`docker` 等均自动透明代理；国内流量和校园网内网自动直连，国外流量自动走双 443 节点。
- **动态网络兼容**：自动适应无线网卡 `wlo1` 与随手插入的临时手机 USB 共享网络（`enx*`）。

---

## 包含文件

| 文件 | 说明 |
| :--- | :--- |
| `singbox-homerouter-deb.json` | 专为 Debian 软路由定制的 sing-box 配置文件（纯 IPv4 加固，已开启 TUN 智能分流，关闭 `auto_redirect`，排除局域网与校园网段；`mixed-in` 与控制 `api` 均监听 `0.0.0.0` 供局域网按需连接与面板管理） |
| `mihomo-homerouter-deb.yaml` | 专为 Debian 软路由定制的 Mihomo 配置文件（纯 IPv4 加固，TUN `auto-redirect: false`，排除局域网与校园网大二层，预置 MetaCubeXD 面板，`mixed-port: 7890` 与控制 API 监听 `0.0.0.0` 供局域网管理） |
| `setup-router-guard.sh` | 一键持久化策略路由脚本，将 `iif br-lan` 物理钉死在主路由表，彻底隔离下游设备（对 sing-box 与 Mihomo 均完全通用且有效） |

---

## 快速使用

### 1. 批量填入节点凭据
在上一级目录的 `Update-SingboxDual443.sh`（或 `.ps1`）中填好凭据并运行：
```bash
# 覆写配置（会自动递归识别并处理 router-selfonly/ 下的 sing-box 与 Mihomo 配置）
./.custom/singbox-dual443/Update-SingboxDual443.sh
```

### 2. 在 Debian 上执行下游隔离守护脚本
将 `setup-router-guard.sh` 拷贝到 Debian 机器（或直接在该机器上执行）：
```bash
sudo ./setup-router-guard.sh
```
该脚本会自动：
- 立即添加内核策略路由：`ip rule add iif br-lan table main priority 100`。
- 配置 NetworkManager Dispatcher 钩子与 systemd 服务双保险，开机和网卡重启自动生效。

### 3. 在 Debian 上启动代理核心（二选一）

#### 选项 A：使用 sing-box
在 Debian 上前台测试：
```bash
sudo sing-box run -c singbox-homerouter-deb.json
```
作为系统后台守护进程运行（创建 `/etc/systemd/system/sing-box.service`）：
```ini
[Unit]
Description=sing-box service for Debian Router
After=network.target network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/singbox-homerouter-deb.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
```
启用并启动：
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sing-box.service
```

#### 选项 B：使用 Mihomo
在 Debian 上前台测试：
```bash
sudo mihomo -d /etc/mihomo -f mihomo-homerouter-deb.yaml
```
作为系统后台守护进程运行（创建 `/etc/systemd/system/mihomo.service`）：
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

## 网段与接口排除逻辑说明

在 `singbox-homerouter-deb.json` 与 `mihomo-homerouter-deb.yaml` 中，两者遵循完全对齐的路由原则：

1. **纯 IPv4 加固（v4only）**：
   - TUN 设备仅接管 IPv4 流量，移除虚拟 IPv6。
   - 规则层内置公网 IPv6 本地拦截（`ip_version: 6 -> reject` 或 `IP-CIDR6,::/0,REJECT,no-resolve`），配合应用层 Happy Eyeballs 瞬时秒退回到 IPv4，杜绝死数据包发往海外 VPS。
2. **局域网监听扩展与 Web 面板**：
   - **混合端口**：sing-box 监听 `0.0.0.0:2080`，Mihomo 监听 `0.0.0.0:7890`，局域网内其他设备如需显式代理可直接指向软路由 IP。
   - **控制 API**：均监听 `0.0.0.0:9090`。局域网内的 Windows 电脑可通过浏览器直接访问 `http://192.168.22.1:9090/ui`（sing-box 预设官方 Dashboard，Mihomo 预设 MetaCubeXD 面板），远程监控管理软路由上的节点状态与切换出口。两者的下载 URL 均默认预设 `https://gh-proxy.com/` 国内镜像加速。
3. **关键隔离：`auto-redirect: false` 与策略路由协同**：
   - 软路由上的 TUN 核心严禁开启 `auto-redirect`（防止自动向系统注入 iptables/nftables PREROUTING 劫持转发流量）。
   - 配合 `setup-router-guard.sh` 的 `priority 100` 策略路由，下游发来的数据包在物理层面绕过 TUN 路由表，绝不产生误拦截或回环。
4. **排除网段（`route_exclude_address` / `route-exclude-address`）**：
   - `192.168.0.0/16`：涵盖 `br-lan` 局域网（`192.168.22.0/24`）及常用私网。
   - `172.16.0.0/12`：标准 RFC 1918 私网网段。
   - `172.32.0.0/12`：高校校园网常用大二层网段与 Web Portal 认证页，确保内网和认证绝对直连。
   - `10.0.0.0/8`：标准私网及校园网认证常见网段。
   - `100.64.0.0/10`：Tailscale / CGNAT 网段。
5. **出站自适应（`auto_detect_interface: true` / `auto-detect-interface: true`）**：
   - 不硬编码出网网卡，无线 WiFi（`wlo1`）与临时手机 USB（`enx*`）无缝热插拔切换。

---

## 节点全部失效时的应急直连

两套配置的 `Proxy` 策略组均内置三个出口：`Reality`、`Hysteria2`、`Direct`。两个自建节点同时不可用时，无需修改任何配置文件：

1. 从内网或 Tailscale 打开 `http://192.168.22.1:9090/ui`；
2. 把 `Proxy` 组切到 `Direct`（或在控制面板中把模式切换为 `Direct`）；
3. 节点恢复后切回 `Reality` / `Hysteria2`。
