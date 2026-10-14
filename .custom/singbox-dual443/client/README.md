# 双 443：完整客户端配置（sing-box 1.14 / Mihomo）

本目录只包含客户端，服务端以 `../server.json` 为唯一参数来源：Reality **TCP 443**（当前握手目标示例 `www.cloudflare.com:443`）、Hy2 **UDP 443**（无 Salamander）、Nginx 伪装站独立使用 **TCP 8443**。服务端 Reality 开启 `multiplex.padding: true`，这里两种客户端的 Reality 节点均与之匹配。不要将 Nginx 8443 误填成节点端口。

| 文件 | 来源及用途 |
| --- | --- |
| `windows.json` | 基于 `config/singbox/1.14X/windows.json` 的完整 DNS/TUN/规则/服务策略配置 |
| `linux.json` | 基于 `config/singbox/1.14X/linux.json`，保留 Linux `auto_redirect` |
| `iphone.json` | 基于 `config/singbox/1.14X/iphone.json`，供官方 Apple 客户端导入 |
| `macos.json` | 基于同一 Apple 平台模板，增加仅监听本机的桌面控制 API；供官方 sing-box for macOS (SFM) 导入 |
| `android.json` | 从仓库 iPhone 移动端模板改造；官方 sing-box for Android 提供 VPN/TUN 实现，移除本机 mixed/API |
| `mihomo.yaml` | 基于 `config/mihomo/config/mihomo.yaml` 的完整节点/DNS/TUN/嗅探/分流/规则集；TUN 为跨平台基础配置；按 [Mihomo 官方文档](https://wiki.metacubex.one/en/config/) 复核 |

原仓库里的机场订阅入口、空的国家地区节点组被移除；所有业务策略组保留并改为在 Reality、Hy2、自动选择和直连间切换。Mihomo 模板原有的「拒绝非 CN 的 UDP/443」规则被移除，以免应用使用 Hy2 时被误拦。仓库自有的 `fakeipfilter-cn` / `fakeipfilter-!cn` 规则链接已经指向 `RolinShmily/sub-rule` 的 `main/rules/`（sing-box 沿用模板的 `gh-proxy.com` 前缀）；SagerNet 的 `.srs` 和 MetaCubeX 的 `.mrs` 在本 fork 中并不存在，仍引用上游，不能只替换仓库名，否则会 404。其他 DNS、地理规则及第三方 URL 沿用仓库模板，并非重新设计的防泄漏审计；首次使用需能下载远程规则集。

## 必须替换（每份客户端均需一致）

- `REPLACE_WITH_NODE_ADDRESS` → VPS 节点域名或 IP，两个客户端节点的 `server` 均使用此值。`REPLACE_WITH_HY2_SNI` → Hy2 证书实际覆盖的域名；即便 `server` 使用 IP，SNI 仍要按证书填写。
- `REPLACE_WITH_UUID` → `../server.json` 中 VLESS `users[0].uuid`。
- `REPLACE_WITH_REALITY_PUBLIC_KEY` → 与服务端 Reality **私钥配对**的公钥，不是私钥本身。
- `REPLACE_WITH_HYSTERIA2_PASSWORD` → 服务端 Hy2 `users[0].password`。
- `01234567` → 服务端 Reality `short_id`；请在所有配置中改成一致的十六进制值。
- `www.cloudflare.com` → 仅当你改动服务端 Reality 握手目标时，才对应修改两类客户端的 Reality `server_name` / `servername`；不要改成 Hy2 证书域名，除非服务端也相应修改。
- `REPLACE_WITH_API_SECRET` → Windows/Linux/macOS sing-box 的本机 API 和 Mihomo 本机控制端口各自的强随机密钥；这不是节点密码。移动端 sing-box 无此字段。

建议在 `.custom/singbox-dual443/Update-SingboxDual443.ps1` 的 `$Values` 中一次填写全部字段，再用 `-Preview` 预检后原地批量覆写；证书路径、Reality 私钥等字段的说明见 [`../README.md`](../README.md)。使用 `sing-box generate reality-keypair` 产生新密钥对；不要复制原仓库的演示密钥。脚本及客户端文件包含可连接节点的密码，**完整 Mihomo YAML 作为订阅地址发布时必须限制访问**，不可上传到公开 Git 或无鉴权静态站点。

## 运行边界和验证

- 五份 sing-box 配置保留仓库的远程规则集、DNS、按应用服务分流。Windows/Linux 裸核运行 TUN 需管理员/root 或相应权限；macOS/iPhone/Android 的官方图形客户端由系统授予 VPN 权限。Linux `auto_redirect` 需要 Linux/nftables，在 Windows 上运行 `sing-box check` 会因平台限制失败，必须在 Linux 上检查。
- Mihomo YAML 包含通用 `tun.enable: true`、`auto-route` 和 `dns-hijack`，便于具备 TUN 权限的 Linux 裸核接管本机流量。Clash Verge Rev 运行时会按 GUI 的 TUN 开关覆写 `tun.enable`；其他客户端是否覆写取决于具体应用，直接运行裸核则会尝试启用 TUN（需权限）。Linux 网关/路由器若要代理其他设备的转发流量，通常还需 Linux 专属 `auto-redirect`、转发/防火墙等设置；这些不放进通用配置。客户端若自行接管系统 DNS，应核对其运行时配置确实启用了 DNS 劫持；不能只凭 `dns.enable: true` 断言不会泄漏。
- Windows/Linux/macOS/iPhone sing-box 的本地 mixed HTTP/SOCKS 端口为 `127.0.0.1:2080`（Windows/macOS/iPhone 的系统 HTTP 代理端口已同步）；Android 版本未启用 mixed。Mihomo 的本地 mixed 端口仍为 `127.0.0.1:7890`。Windows/Linux/macOS sing-box 和 Mihomo 的控制 API 均监听本机 `9090`，同时启动前还须调整其中一个 API 端口；即使端口都错开，两个 TUN 同时接管系统流量仍可能造成路由冲突。
- Mihomo DNS 沿用仓库的 fake-ip 与国内/国外分流：国内域名交给阿里/腾讯 DoH，国外域名经“默认代理”访问 Google DoH；节点域名通过 `proxy-server-nameserver` 直连解析以避免代理启动循环。规则集命中后按服务分组或国内直连。国内 DNS 查询和国内流量会直接连接，故这不是“所有流量都经 VPS”的配置。若你需要强制全局代理或特定 DNS 隐私策略，应进一步定制。
- 替换字段后运行 `sing-box check -c windows.json` / `sing-box check -c linux.json`（对应系统下）；Mihomo 用实际目标设备的内核配置检查命令验证。`check` 通过也不能代替 VPS、证书、UDP 防火墙和下载规则集的实际连通性测试。

官方资料：[sing-box Apple 客户端](https://sing-box.sagernet.org/clients/apple/)、[sing-box Android 客户端](https://sing-box.sagernet.org/clients/android/)、[sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/)、[Mihomo TUN](https://wiki.metacubex.one/en/config/inbound/tun/)、[Mihomo VLESS](https://wiki.metacubex.one/en/config/proxies/vless/)、[Mihomo Hy2](https://wiki.metacubex.one/en/config/proxies/hysteria2/)。
