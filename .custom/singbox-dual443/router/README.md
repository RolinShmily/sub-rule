# Debian 软路由专用 sing-box 本机透明代理方案

本目录专为 **Debian 单系统软路由**（WAN: 无线网卡/临时手机 USB，LAN: 双物理网口网桥 `br-lan`，DHCP: dnsmasq，防火墙: nftables）打造。

### 核心设计目标
- **下游设备（Windows PC / 交换机 / 下级路由）**：100% 保持**纯软路由透传**。Debian 仅负责 DHCP、DNS 缓存和 NAT 转发，下游发出的流量绝不进入 sing-box 代理，排障链路极简，校园网认证无阻。
- **Debian 宿主机自身**：享受与 Windows 客户端完全一致的**全自动无感智能分流**。命令行 `curl`、`apt`、`git`、`docker` 等均自动透明代理；国内流量和校园网内网自动直连，国外流量自动走双 443 节点。
- **动态网络兼容**：自动适应无线网卡 `wlo1` 与随手插入的临时手机 USB 共享网络（`enx*`）。

---

## 包含文件

| 文件 | 说明 |
| :--- | :--- |
| `singbox-homerouter-deb.json` | 专为 Debian 软路由定制的 sing-box 配置文件（纯 IPv4 加固，已开启 TUN 智能分流，关闭 `auto_redirect`，排除局域网与校园网段；`mixed-in` 与控制 `api` 均监听 `0.0.0.0` 供局域网按需连接与面板管理） |
| `setup-router-guard.sh` | 一键持久化策略路由脚本，将 `iif br-lan` 物理钉死在主路由表，彻底隔离下游设备 |

---

## 快速使用

### 1. 批量填入节点凭据
在上一级目录的 `Update-SingboxDual443.sh`（或 `.ps1`）中填好凭据并运行：
```bash
# 覆写配置（会自动识别并处理 router/singbox-homerouter-deb.json）
./.custom/singbox-dual443/Update-SingboxDual443.sh
```

### 2. 在 Debian 上执行下游隔离守护脚本
将 `setup-router-guard.sh` 拷贝到 Debian 机器（或直接在该机器上执行）：
```bash
sudo ./setup-router-guard.sh
```
该脚本会自动：
- 立即添加策略路由：`ip rule add iif br-lan table main priority 100`。
- 配置 NetworkManager Dispatcher 钩子与 systemd 服务双保险，开机和网卡重启自动生效。

### 3. 在 Debian 上启动 sing-box
在 Debian 上运行测试：
```bash
sudo sing-box run -c singbox-homerouter-deb.json
```
若希望作为系统后台守护进程运行，可配置 systemd 服务（`/etc/systemd/system/sing-box.service`）：
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

---

## 网段与接口排除逻辑说明

在 `singbox-homerouter-deb.json` 中：

1. **纯 IPv4 加固（v4only）**：
   - TUN 设备仅分配 IPv4 地址（`172.19.0.1/30`），移除虚拟 IPv6。
   - 规则层内置公网 IPv6 本地拦截（`ip_version: 6 -> reject`），配合应用层 Happy Eyeballs 瞬时秒退回到 IPv4，杜绝死数据包发往海外 VPS。
2. **局域网监听扩展**：
   - `mixed-in`：监听 `0.0.0.0:2080`，局域网内其他设备如需显式代理可直接指向 `192.168.22.1:2080`。
   - `api`：监听 `0.0.0.0:9090`，局域网内的 Windows 电脑可通过 Web 控制面板（如 metacubexd / yacd）输入 `http://192.168.22.1:9090` 远程监控管理 Debian 上的 sing-box 状态。
3. **排除网段（`route_exclude_address`）**：
   - `192.168.0.0/16`：涵盖 `br-lan` 局域网（`192.168.22.0/24`）及常用私网。
   - `172.16.0.0/12`：标准 RFC 1918 私网网段。
   - `172.32.0.0/12`：高校校园网常用大二层网段，确保校园网内网与 Web Portal 认证页绝对直连。
   - `10.0.0.0/8`：标准私网及校园网认证常见网段。
   - `100.64.0.0/10`：Tailscale / CGNAT 网段。
2. **排除接口（`exclude_interface`）**：
   - `br-lan`、`enp1s0`、`enp3s0`、`tailscale0`。
3. **出站自适应（`route.auto_detect_interface: true`）**：
   - 不硬编码出网网卡，无线 WiFi（`wlo1`）与临时手机 USB（`enx*`）无缝热插拔切换。
