# sing-box 1.14：Debian VPS 双 443

- `server.json`：基于仓库 `config/singbox/1.14X/VPS/server.json` 裁剪的服务端，VLESS-Reality 监听 **TCP 443**，Hysteria2 监听 **UDP 443**（无 Salamander）。Nginx 的 HTTPS 伪装站独立监听 TCP 8443，不会自动成为 Reality 握手目标。
- `client/`：Windows、Linux、macOS、iPhone、Android 的完整 sing-box 客户端，以及完整 Mihomo YAML。细节见 [`client/README.md`](client/README.md)。
- `Update-SingboxDual443.ps1`：递归扫描本目录及子目录的 `.json`、`.yaml`，只覆写识别出的双 443 配置；脚本和生成后的配置都可能含明文密钥，**不要提交到公开仓库**。

原版服务端另有 AnyTLS、TUIC 等其他入站和 Cloudflare ACME；这里只保留 VLESS-Reality 与 Hy2。保留原版 Reality 的 Vision 和 `multiplex.padding`，客户端也开启对应的 padding。既然你已有证书，Hy2 TLS 直接使用 `certificate_path` 和 `key_path`；两个字段现在都是显式模板占位符。

## 字段与端口

先在 `.custom/singbox-dual443/Update-SingboxDual443.ps1` 文件头的 `$Values` 中填值，再运行脚本。以下是**不同含义**的字段：

| 脚本字段 | 用途 |
| --- | --- |
| `NodeAddress` | 客户端连接的 VPS 域名或 IP；对应 `REPLACE_WITH_NODE_ADDRESS`，**不是** Reality 的伪装域名 |
| `Hy2Sni` | Hy2 证书实际覆盖的域名；对应 `REPLACE_WITH_HY2_SNI`。多数情况下与 `NodeAddress` 相同；若节点用 IP 连接，这里仍用证书域名 |
| `RealitySni` | Reality 客户端握手使用的 SNI，需与服务端 `tls.server_name` 对应；当前模板示例为 `www.cloudflare.com` |
| `HandshakeHost` / `HandshakePort` | 服务端 Reality 转发握手的目标与端口；可用可达的外部站点，或经专门配置的本机 Nginx 8443。**不能只改端口就假定伪装生效** |
| `Uuid` / `RealityPrivateKey` / `RealityPublicKey` / `ShortId` | VLESS UUID、Reality 配对密钥和 short ID；私钥只写服务端，公钥只写客户端 |
| `Hy2Password` | Hy2 登录密码；服务端与两类客户端一致 |
| `CertificatePath` / `KeyPath` | Debian VPS 上真实证书链和私钥的绝对路径；对应 `REPLACE_WITH_CERTIFICATE_PATH` / `REPLACE_WITH_KEY_PATH`，必须让 sing-box 进程可读 |
| `SingboxApiSecret` / `MihomoApiSecret` | 两类客户端的本机控制 API 密钥，不是节点密码 |
| `HeadscaleServer` / `HeadscaleBaseDomain` | （可选）Headscale 控制面/DERP 域名及 MagicDNS 根域名；**若不使用可留空 `''`**，脚本会自动忽略且不报错 |

生成 UUID、Reality 密钥对和 Hy2 强随机密码（在私有终端执行，避免记录到公开日志）：

```sh
sing-box generate uuid
sing-box generate reality-keypair
openssl rand -hex 32
```

端口 **TCP 443 + UDP 443** 互不冲突，但要检查 VPS/云平台防火墙；Nginx 若仍占用相同 IP 的 TCP 443，则 Reality 会发生端口冲突。节点 DNS 记录应指向 VPS；若域名托管在 Cloudflare 等 CDN，节点记录通常应仅 DNS 解析、不经 CDN 代理。

## 脚本使用

```powershell
# 先填脚本头部；预检所有配置，不写文件，不输出凭据
pwsh -File .custom/singbox-dual443/Update-SingboxDual443.ps1 -Preview
# 递归识别双 443 配置，原地覆写（当前目录有 server.json 和 client/ 下六份配置）
pwsh -File .custom/singbox-dual443/Update-SingboxDual443.ps1
```

脚本递归检测本目录及子目录中的 JSON/YAML，按节点类型、标签和字段定位；不匹配的文件跳过。修改脚本值后可以再次运行；它不会修改 README、远程规则集地址或仓库原版配置。脚本不替你申请证书或验证服务器可达。**原地覆写会移除模板占位符**；请自己备份原始模板，勿把填有真实私钥/密码的脚本与配置提交到 Git。若在 Git 工作目录使用，可用 `git status --short` 检查待提交文件。

在相应目标系统上运行 `sing-box check -c server.json` 或 `sing-box check -c client/singbox-windows.json`（依平台选择）。服务端证书路径必须存在且可读；Linux 客户端 `auto_redirect` 必须在 Linux 上检查。Mihomo 请用实际内核/客户端核验；语法检查不能代替证书、DNS、规则集下载与连通性测试。

字段依据：[sing-box VLESS 入站](https://sing-box.sagernet.org/configuration/inbound/vless/)、[Hy2 入站](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)、[Reality 与证书 TLS](https://sing-box.sagernet.org/configuration/shared/tls/)。
