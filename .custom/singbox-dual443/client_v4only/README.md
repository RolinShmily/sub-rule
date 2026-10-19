# 纯 IPv4 VPS 专属客户端配置 (v4only)

本目录下的客户端配置基于 `client/`，针对**没有公网 IPv6 的纯 IPv4 海外 VPS** 进行了专项加固：

1. **公网 IPv6 本地拦截**：
   在路由规则中，除放行 Tailscale 虚拟内网专属 IPv6 (`fd7a:115c:a1e0::/48`) 外，对其余所有试图经由代理发往公网的 IPv6 请求（如硬编码的 Cloudflare `2606:4700:4700::1111`）进行本地 `reject`；
2. **Happy Eyeballs 秒回退**：
   应用（如 Chrome / Edge）收到本地拒绝后，会在 0ms 瞬间回退走 IPv4 路由，绝不向纯 IPv4 的境外 VPS 发送死数据包，彻底消除 VPS 端的 `remote error: dial tcp network unreachable` 报错；
3. **完整保留 Tailscale / Headscale 直通**：
   包含 `直连-tailscale` 专属通道、`tailscale-dns` (100.100.100.100)、Windows 系统代理绕过名单及 Mihomo `direct-nameserver-follow-policy: true`。

配套的服务端位于 `../server_v4only.json`。
