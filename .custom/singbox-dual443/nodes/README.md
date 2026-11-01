# Nodes：分享链接（server.json 的两种节点）

本目录是 `.custom/singbox-dual443/server.json` 里两个入站的 **分享链接（URI）** 形态，一文件一协议，便于直接导入客户端或发给别人：

| 文件 | 对应服务端入站 | 链接形式 |
| :--- | :--- | :--- |
| `vless.txt` | `VLESS-Vision-Reality-in`（**TCP** 443，`flow: xtls-rprx-vision`，Reality + `multiplex.padding`） | `vless://...` |
| `hysteria2.txt` | `hysteria-in`（**UDP** 443，无 Salamander） | `hysteria2://...` |

## 占位符来源

链接里的占位符与 `Update-SingboxDual443.sh` / `.ps1` 头部的变量一一对应，**不要手填，跑脚本即可**；脚本会用同一批值同时覆写 `server.json`、各客户端配置与本目录的链接，避免两边不一致。

| 链接中的占位符 | 脚本变量 | 取值来源 |
| :--- | :--- | :--- |
| `REPLACE_WITH_UUID` | `Uuid` | `server.json` → `VLESS-Vision-Reality-in.users[0].uuid` |
| `REPLACE_WITH_REALITY_PUBLIC_KEY` | `RealityPublicKey` | 与服务端 `reality.private_key` 配对的**公钥**（不是私钥） |
| `REPLACE_WITH_REALITY_SNI` | `RealitySni` | `server.json` → Reality `tls.server_name` / `handshake.server`（默认 `www.cloudflare.com`） |
| `01234567` | `ShortId` | `server.json` → `reality.short_id[0]` |
| `REPLACE_WITH_HY2_SNI` | `Hy2Sni` | `server.json` → Hy2 `tls.server_name`，即证书实际覆盖的域名 |
| `REPLACE_WITH_HYSTERIA2_PASSWORD` | `Hy2Password` | `server.json` → `hysteria-in.users[0].password` |
| `REPLACE_WITH_NODE_ADDRESS` | `NodeAddress` | 客户端实际连接用的 VPS 域名或 IP（两个节点共用） |

端口固定为 443：Reality 走 **TCP 443**、Hy2 走 **UDP 443**，两者互不冲突。`vless.txt` 里的 `fp=chrome` 与客户端的 `utls.fingerprint` 对应；`hysteria2.txt` 里的 `insecure=0` 与客户端 `tls.insecure: false` 对应，不要随意改成 `1`。

## 与客户端配置的关系

链接只是另一种表达方式，参数必须与 `client/`、`client_v4only/`、`router/` 保持一致，否则导入后连不上：

- Reality：`sid`、`pbk`、`sni`、`flow` 四项任一不一致即握手失败。
- Hy2：`password` 与 `sni` 必须匹配服务端证书；证书域名不等于节点地址时，`sni` 仍填证书域名。

需要 `multiplex`（服务端与客户端均开启 `padding`）的客户端，导入链接后请手动补上；分享链接格式本身不表达 sing-box 的 `multiplex` 字段。

> 占位符版本可以安全提交；一旦跑过脚本，这两份文件就是**含明文 UUID / 公钥 / Hy2 密码的可直接连接凭据**，与 `server.json` 同等敏感，请勿上传到公开仓库或无鉴权静态站点。
