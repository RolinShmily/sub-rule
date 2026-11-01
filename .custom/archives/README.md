# 归档目录 (archives)

本目录用于存放历史版本或备用配置，独立于主配置目录（如 `../singbox-dual443/`）。

> **说明**：更新脚本 `Update-SingboxDual443.sh` 与 `Update-SingboxDual443.ps1` 默认仅扫描并覆写 `singbox-dual443/` 目录树，**不会扫描本归档目录**，因此存放在这里的历史配置不会受到日常批量更新操作的影响。

---

## 归档记录

### `singbox-20261101_170941/`
* **归档时间**：2026-11-01 17:09:41
* **归档内容**：原 `singbox-dual443` 下的全套 sing-box 客户端与软路由配置文件（共 11 份 JSON）：
  * `client/singbox/`：通用双栈客户端（Windows、Linux、macOS、iPhone、Android 共 5 份 JSON）
  * `client_v4only/singbox/`：纯 IPv4 VPS 专属客户端（Windows、Linux、macOS、iPhone、Android 共 5 份 JSON）
  * `router-selfonly/`：Debian 软路由专用配置（`singbox-homerouter-deb.json` 共 1 份 JSON）
