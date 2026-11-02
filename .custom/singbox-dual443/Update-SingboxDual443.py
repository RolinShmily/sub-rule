#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Update-SingboxDual443.py
递归扫描 singbox-dual443/ 目录树并原地批量覆写双 443 服务端与客户端配置。
依赖：仅使用 Python 3 标准库（无需 pip 安装任何第三方依赖）。

用法示例：
    ./Update-SingboxDual443.py --preview   # 仅预检扫描识别出的文件，不修改任何文件
    ./Update-SingboxDual443.py             # 原地批量覆写配置并同步生成节点分享链接
    python Update-SingboxDual443.py       # Windows / 通用命令行执行
"""

import os
import sys
import re
import json
import uuid
import argparse
import urllib.parse

# ==============================================================================
# 用户参数配置（请只在本机填写；切勿将含真实密钥的文件提交到公开仓库）
# ==============================================================================
CONFIG = {
    # --------------------------------------------------------------------------
    # 【协议一：VLESS-Vision-REALITY (TCP 443 直连)】
    # --------------------------------------------------------------------------
    # --- 核心连接与凭据 ---
    "NodeAddress": "REPLACE_WITH_NODE_ADDRESS",                  # VPS 直连 IP 或未开启 CDN 代理的直连域名
    "RealityPort": 443,                                          # REALITY 监听与连接端口（默认 443）
    "Uuid": "REPLACE_WITH_UUID",                                 # VLESS 协议用户 UUID
    "RealitySni": "REPLACE_WITH_REALITY_SNI",                    # 偷取的 SNI 域名（如 www.apple.com）
    "RealityPublicKey": "REPLACE_WITH_REALITY_PUBLIC_KEY",       # REALITY 客户端公钥 (43位 Base64URL)
    "RealityPrivateKey": "REPLACE_WITH_REALITY_PRIVATE_KEY",     # REALITY 服务端私钥 (43位 Base64URL)
    "ShortId": "REPLACE_WITH_REALITY_SHORT_ID",                  # 2-16 位偶数长度十六进制 ShortId
    # --- 协议杂项 ---
    "HandshakeHost": "REPLACE_WITH_REALITY_HANDSHAKE_HOST",      # 握手回落目标主机（如 www.apple.com）
    "HandshakePort": 443,                                        # 握手回落目标端口（默认 443）

    # --------------------------------------------------------------------------
    # 【协议二：Hysteria 2 (UDP 443 直连)】
    # --------------------------------------------------------------------------
    # --- 核心连接与凭据 ---
    "Hy2Port": 443,                                              # Hysteria 2 监听与连接端口（默认 UDP 443）
    "Hy2Sni": "REPLACE_WITH_HY2_SNI",                            # Hy2 域名（如 hy2.example.com，必须与证书一致且为灰云）
    "Hy2Password": "REPLACE_WITH_HYSTERIA2_PASSWORD",            # Hy2 连接密码（建议 16 位以上强密码）
    # --- 协议杂项 ---
    "CertificatePath": "REPLACE_WITH_CERTIFICATE_PATH",          # 服务端证书 fullchain.pem 绝对路径
    "KeyPath": "REPLACE_WITH_KEY_PATH",                          # 服务端私钥 privkey.pem 绝对路径

    # --------------------------------------------------------------------------
    # 【协议三：VLESS-WS-TLS (TCP 8443 套 Cloudflare CDN)】
    # --------------------------------------------------------------------------
    # --- 核心连接与凭据 ---
    "WsOptimizedDomain": "REPLACE_WITH_CF_OPTIMIZED_DOMAIN",     # 客户端连接地址：社区优选域名或 Anycast 优选 IP
    "WsPort": 8443,                                              # 监听与转发端口（推荐 8443，需为 CF 支持的 HTTPS 端口）
    "WsSni": "REPLACE_WITH_WS_SNI",                              # CDN 代理域名（如 cdn.example.com，在 CF 开启橙云）
    "WsUuid": "REPLACE_WITH_WS_UUID",                            # VLESS WS 用户 UUID（可与 Uuid 相同或独立）
    # --- 协议杂项 ---
    "WsPath": "REPLACE_WITH_WS_PATH",                            # WebSocket 传输路径（如 /api/v3/tunnel-stream）
    "WsCertificatePath": "REPLACE_WITH_WS_CERTIFICATE_PATH",     # 服务端证书路径（若与 Hy2 同为泛域名可填相同路径）
    "WsKeyPath": "REPLACE_WITH_WS_KEY_PATH",                     # 服务端私钥路径
    "WsMaxEarlyData": 2048,                                      # 0-RTT 握手首包最大长度（字节，默认 2048）
    "WsEarlyDataHeader": "Sec-WebSocket-Protocol",               # Early Data 传递标头名称

    # --------------------------------------------------------------------------
    # 【公共与系统杂项 (Miscellaneous / System)】
    # --------------------------------------------------------------------------
    # --- 客户端面板与 API 控制杂项 ---
    "MihomoApiSecret": "REPLACE_WITH_MIHOMO_API_SECRET",         # Mihomo 控制 API 密钥（Web 面板访问密码）

    # --- 虚拟组网直连杂项（Headscale / Tailscale，可选）---
    "HeadscaleServer": "REPLACE_WITH_HEADSCALE_SERVER",          # 控制面域名，例如 'hs.example.com'
    "HeadscaleBaseDomain": "REPLACE_WITH_HEADSCALE_BASE_DOMAIN", # MagicDNS 根域名，例如 'tail.net'

    # --- 规则集与资源下载杂项 ---
    "RuleSetProxy": "https://gh-proxy.com/",                     # 规则集与 Dashboard 下载代理前缀（必须以 / 结尾）

    # --- 软路由第三方外部订阅杂项 ---
    "ExternalSubscribes": [
        # "https://airport1.com/api/v1/client/subscribe?token=xxxxxx",
        # "https://airport2.com/api/v1/client/subscribe?token=yyyyyy",
    ],
    "ApplySubscribesToClients": False,                           # 外部订阅是否同时作用于客户端配置（True/False）
}

# ==============================================================================
# 核心业务逻辑
# ==============================================================================

RULESET_PROXY_PLACEHOLDER = "REPLACE_WITH_RULESET_PROXY_PREFIX"

def assert_values(values):
    """校验参数有效性，确保不带未填写的占位符且格式符合各协议规范。"""
    optional_keys = {
        "HeadscaleServer", "HeadscaleBaseDomain", "RuleSetProxy",
        "ExternalSubscribes", "ApplySubscribesToClients",
        "RealityPort", "Hy2Port", "WsPort",
        "WsMaxEarlyData", "WsEarlyDataHeader"
    }
    for key, val in values.items():
        if key == "HandshakePort" or key in optional_keys:
            continue
        val_str = str(val).strip()
        if not val_str or val_str.startswith("REPLACE_WITH_"):
            raise ValueError(f"请先在 CONFIG 中填写 {key}；未修改任何配置。")

    for key in ["Uuid", "WsUuid"]:
        uuid_str = str(values[key]).strip()
        try:
            uuid.UUID(uuid_str)
            if not re.fullmatch(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", uuid_str):
                raise ValueError()
        except Exception:
            raise ValueError(f"{key} 必须是有效的 UUID 格式；未修改任何配置。")

    short_id = str(values["ShortId"]).strip()
    if not re.fullmatch(r"^(?:[0-9a-fA-F]{2}){1,8}$", short_id):
        raise ValueError("ShortId 必须是 2-16 位偶数长度的十六进制字符串；未修改任何配置。")

    for key in ["HandshakePort", "RealityPort", "Hy2Port", "WsPort"]:
        try:
            port = int(values.get(key, 0))
            if port < 1 or port > 65535:
                raise ValueError()
        except Exception:
            raise ValueError(f"{key} 必须在 1-65535 之间；未修改任何配置。")

    for key in ["RealityPrivateKey", "RealityPublicKey"]:
        val = str(values[key]).strip()
        if not re.fullmatch(r"^[A-Za-z0-9_-]{43}$", val):
            raise ValueError(f"{key} 的格式不是 43 位 Base64URL；未修改任何配置。")

    for key in ["CertificatePath", "KeyPath", "WsCertificatePath", "WsKeyPath"]:
        val = str(values[key]).strip()
        if not val.startswith("/"):
            raise ValueError(f"{key} 必须是 Debian 上的绝对路径；未修改任何配置。")

    for key in ["NodeAddress", "Hy2Sni", "RealitySni", "HandshakeHost", "WsOptimizedDomain", "WsSni"]:
        val = str(values[key]).strip()
        if re.search(r"[\s/]", val):
            raise ValueError(f"{key} 只能填主机名或 IP，不要带协议或路径；未修改任何配置。")

    ws_path = str(values["WsPath"]).strip()
    if not ws_path.startswith("/") or re.search(r"\s", ws_path):
        raise ValueError("WsPath 必须以 / 开头且不能包含空格；未修改任何配置。")

    for key in ["HeadscaleServer", "HeadscaleBaseDomain"]:
        val = str(values[key]).strip()
        if val and not val.startswith("REPLACE_WITH_"):
            if re.search(r"[\s/:]", val):
                raise ValueError(f"{key} 只能填主机名或域名（如 hs.example.com），不要带协议、路径或端口；未修改任何配置。")

    prefix = str(values["RuleSetProxy"]).strip()
    if prefix and not prefix.startswith("REPLACE_WITH_"):
        if not re.fullmatch(r"https?://[^\s]+/", prefix):
            raise ValueError("RuleSetProxy 必须以 http:// 或 https:// 开头并以 / 结尾（如 https://gh-proxy.com/）；留空 '' 表示直连下载。")

    for key in ["Hy2Password", "MihomoApiSecret"]:
        val = str(values[key])
        if re.search(r"[\r\n]", val) or len(val) < 16:
            raise ValueError(f"{key} 至少 16 位且不能包含换行；未修改任何配置。")


def get_one(items, description):
    if len(items) != 1:
        raise ValueError(f"无法唯一定位 {description}（找到 {len(items)} 个）；未修改任何配置。")
    return items[0]


def assert_field(obj, field, description):
    if obj is None or not isinstance(obj, dict) or field not in obj or obj[field] is None:
        raise ValueError(f"缺少 {description}.{field}；未修改任何配置。")


def resolve_ruleset_prefix():
    raw = str(CONFIG.get("RuleSetProxy", "")).strip()
    if not raw or raw.startswith("REPLACE_WITH_"):
        return ""
    return raw


def normalize_ruleset_url(url):
    """去除已有的镜像前缀与占位符，保留规范的原生 URL（实现幂等替换）。"""
    text = str(url)
    if text.startswith(RULESET_PROXY_PLACEHOLDER):
        return text[len(RULESET_PROXY_PLACEHOLDER):]
    cut = max(text.rfind("https://"), text.rfind("http://"))
    if cut > 0:
        return text[cut:]
    return text


def apply_ruleset_proxy_to_json(cfg):
    prefix = resolve_ruleset_prefix()
    touched = 0
    route = cfg.get("route")
    if isinstance(route, dict):
        for rule_set in route.get("rule_set") or []:
            if isinstance(rule_set, dict) and isinstance(rule_set.get("url"), str):
                rule_set["url"] = prefix + normalize_ruleset_url(rule_set["url"])
                touched += 1
    for service in cfg.get("services") or []:
        if isinstance(service, dict) and service.get("type") == "api":
            dashboard = service.get("dashboard")
            if isinstance(dashboard, dict) and isinstance(dashboard.get("download_url"), str):
                dashboard["download_url"] = prefix + normalize_ruleset_url(dashboard["download_url"])
                touched += 1
    return touched


def apply_ruleset_proxy_to_yaml(text):
    prefix = resolve_ruleset_prefix()

    # 1. 替换 external-ui-url（若存在）
    pattern_ui = re.compile(r'(?m)^(\s*external-ui-url:\s*["\']?)([^"\'\r\n]+)(["\']?)')
    def repl_ui(m):
        lead = m.group(1)
        val = m.group(2).strip()
        quote = m.group(3)
        return f"{lead}{prefix}{normalize_ruleset_url(val)}{quote}"
    text = pattern_ui.sub(repl_ui, text)

    # 2. 替换 rule-providers 下所有 url
    start = re.search(r'(?m)^rule-providers:[ \t]*\r?$', text)
    if not start:
        return text
    tail = text[start.end():]
    stop = re.search(r'(?m)^[^\s#]', tail)
    section_end = start.end() + (stop.start() if stop else len(tail))
    section = text[start.end():section_end]
    pattern = re.compile(r'(?m)^(\s+url: )([^\r\n]+)')
    def repl(m):
        value = m.group(2).strip()
        return m.group(1) + prefix + normalize_ruleset_url(value)
    new_section = pattern.sub(repl, section)
    return text[:start.end()] + new_section + text[section_end:]


def apply_proxy_providers_to_yaml(text, subs, is_router=True, apply_to_client=False):
    """处理 proxy-providers 与 proxy-groups 的动态注入与回退清理（支持软路由与客户端解耦）。"""
    effective_subs = subs if (is_router or apply_to_client) else []
    valid_subs = [s.strip() for s in effective_subs if s and not str(s).startswith("REPLACE_WITH_")]
    sec0_pattern = r'(?ms)^# =+\r?\n# 0\. 外部订阅提供者.*?(?=# =+\r?\n# 1\. 代理节点配置)'
    sec1_pattern = r'(?m)^(# =+\r?\n# 1\. 代理节点配置)'

    if valid_subs:
        lines = [
            "# ==============================================================================",
            "# 0. 外部订阅提供者 (Proxy Providers / 机场订阅)",
            "# ==============================================================================",
            "proxy-providers:",
        ]
        for i, url in enumerate(valid_subs):
            escaped_url = str(url).replace("'", "''")
            lines.extend([
                f"  Subscribe_{i}:",
                f"    type: http",
                f"    url: '{escaped_url}'",
                f"    path: ./proxy_providers/subscribe_{i}.yaml",
                f"    interval: 86400",
                f"    health-check:",
                f"      enable: true",
                f"      url: https://www.gstatic.com/generate_204",
                f"      interval: 300",
            ])
        lines.append("")
        sec0_content = "\n".join(lines) + "\n"
        if re.search(sec0_pattern, text):
            text = re.sub(sec0_pattern, sec0_content, text, count=1)
        else:
            text = re.sub(sec1_pattern, sec0_content + r'\1', text, count=1)
    else:
        if is_router:
            template = """# ==============================================================================
# 0. 外部订阅提供者 (Proxy Providers / 机场订阅)
# ==============================================================================
# 可选：支持 Clash YAML 格式、Base64 通用订阅或原始 URI 节点列表。
# 若在 Update-SingboxDual443.py 中配置了 ExternalSubscribes，脚本会自动在此生成订阅并联动至下方策略组。
# 模板示例（如需手动启用，取消下方注释并填入订阅链接）：
# proxy-providers:
#   Subscribe_0:
#     type: http
#     url: "你的订阅链接"
#     path: ./proxy_providers/subscribe_0.yaml
#     interval: 86400
#     health-check:
#       enable: true
#       url: https://www.gstatic.com/generate_204
#       interval: 300

"""
            if re.search(sec0_pattern, text):
                text = re.sub(sec0_pattern, template, text, count=1)
            else:
                text = re.sub(sec1_pattern, template + r'\1', text, count=1)
        else:
            # 客户端若无订阅或关闭开关，彻底清理 Section 0（保持绝对纯净）
            text = re.sub(sec0_pattern, "", text, count=1)

    group_pattern = r'(?ms)(^proxy-groups:\r?\n  - name: Proxy\r?\n    type: select\r?\n    proxies:\r?\n(?:      - [^\r\n]+\r?\n)+)(?:    use:\r?\n(?:      - [^\r\n]+\r?\n)+)?'
    def repl_group(m):
        base = m.group(1)
        if valid_subs:
            use_lines = "    use:\n" + "".join([f"      - Subscribe_{i}\n" for i in range(len(valid_subs))])
            return base + use_lines
        return base
    text = re.sub(group_pattern, repl_group, text, count=1)
    return text


def convert_to_yaml_scalar(value):
    if isinstance(value, int):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def set_yaml_field(block, field, spaces, value):
    pattern = rf'(?m)^({" " * spaces}{re.escape(field)}:[ \t]*).*$'
    matches = list(re.finditer(pattern, block))
    if len(matches) != 1:
        raise ValueError(f"无法唯一定位 YAML 字段 {field}；未修改任何配置。")
    scalar = convert_to_yaml_scalar(value)
    return re.sub(pattern, lambda m: m.group(1) + scalar, block, count=1)


def set_yaml_proxy(text, name, fields):
    pattern = rf'(?ms)^(  - name: {re.escape(name)}[^\r\n]*\r?\n)(.*?)(?=^  - name: |^[^\s#]|\Z)'
    matches = list(re.finditer(pattern, text))
    if len(matches) != 1:
        raise ValueError(f"无法唯一定位 Mihomo 节点 {name}；未修改任何配置。")
    def repl(m):
        header = m.group(1)
        block = m.group(2)
        for field, parts in fields.items():
            block = set_yaml_field(block, field, parts[0], parts[1])
        return header + block
    return re.sub(pattern, repl, text, count=1)


def update_server(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    inbounds = cfg.get("inbounds", [])
    vless_list = [ib for ib in inbounds if ib.get("tag") == "VLESS-Vision-Reality-in" and ib.get("type") == "vless"]
    hy2_list = [ib for ib in inbounds if ib.get("tag") == "hysteria-in" and ib.get("type") == "hysteria2"]
    ws_list = [ib for ib in inbounds if ib.get("tag") == "vless-ws-in" and ib.get("type") == "vless"]

    vless = get_one(vless_list, "服务端 Reality 入站")
    hy2 = get_one(hy2_list, "服务端 Hy2 入站")
    ws = get_one(ws_list, "服务端 VLESS-WS 入站")

    for fld in ["users", "tls"]:
        assert_field(vless, fld, "服务端 Reality")
        assert_field(hy2, fld, "服务端 Hy2")
        assert_field(ws, fld, "服务端 VLESS-WS")

    user = get_one(vless.get("users", []), "服务端 Reality 用户")
    hy2_user = get_one(hy2.get("users", []), "服务端 Hy2 用户")
    ws_user = get_one(ws.get("users", []), "服务端 VLESS-WS 用户")

    assert_field(vless["tls"], "reality", "服务端 Reality TLS")
    assert_field(vless["tls"]["reality"], "handshake", "服务端 Reality")
    for fld in ["certificate_path", "key_path", "server_name"]:
        assert_field(hy2["tls"], fld, "服务端 Hy2 TLS")
        assert_field(ws["tls"], fld, "服务端 VLESS-WS TLS")
    assert_field(ws, "transport", "服务端 VLESS-WS Transport")

    # 协议一：Reality
    vless["listen_port"] = int(CONFIG.get("RealityPort", 443))
    user["uuid"] = CONFIG["Uuid"]
    vless["tls"]["server_name"] = CONFIG["RealitySni"]
    vless["tls"]["reality"]["handshake"]["server"] = CONFIG["HandshakeHost"]
    vless["tls"]["reality"]["handshake"]["server_port"] = int(CONFIG["HandshakePort"])
    vless["tls"]["reality"]["private_key"] = CONFIG["RealityPrivateKey"]
    vless["tls"]["reality"]["short_id"] = [CONFIG["ShortId"]]

    # 协议二：Hysteria 2
    hy2["listen_port"] = int(CONFIG.get("Hy2Port", 443))
    hy2_user["password"] = CONFIG["Hy2Password"]
    hy2["tls"]["server_name"] = CONFIG["Hy2Sni"]
    hy2["tls"]["certificate_path"] = CONFIG["CertificatePath"]
    hy2["tls"]["key_path"] = CONFIG["KeyPath"]

    # 协议三：VLESS-WS-TLS (套 Cloudflare CDN)
    ws["listen_port"] = int(CONFIG.get("WsPort", 8443))
    ws_user["uuid"] = CONFIG["WsUuid"]
    ws["tls"]["server_name"] = CONFIG["WsSni"]
    ws["tls"]["certificate_path"] = CONFIG["WsCertificatePath"]
    ws["tls"]["key_path"] = CONFIG["WsKeyPath"]
    ws["transport"]["path"] = CONFIG["WsPath"]
    if "headers" not in ws["transport"] or not isinstance(ws["transport"]["headers"], dict):
        ws["transport"]["headers"] = {}
    ws["transport"]["headers"]["Host"] = CONFIG["WsSni"]
    ws["transport"]["max_early_data"] = int(CONFIG.get("WsMaxEarlyData", 2048))
    ws["transport"]["early_data_header_name"] = str(CONFIG.get("WsEarlyDataHeader", "Sec-WebSocket-Protocol"))

    return json.dumps(cfg, indent=2, ensure_ascii=False)


def update_singbox_client(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    outbounds = cfg.get("outbounds", [])
    vless_list = [ob for ob in outbounds if ob.get("tag") == "Reality" and ob.get("type") == "vless"]
    hy2_list = [ob for ob in outbounds if ob.get("tag") == "Hysteria2" and ob.get("type") == "hysteria2"]

    vless = get_one(vless_list, f"{path} Reality 出站")
    hy2 = get_one(hy2_list, f"{path} Hy2 出站")

    for fld in ["tls", "uuid", "server"]:
        assert_field(vless, fld, f"{path} Reality")
    for fld in ["tls", "password", "server"]:
        assert_field(hy2, fld, f"{path} Hy2")
    assert_field(vless["tls"], "reality", f"{path} Reality TLS")

    vless["server"] = CONFIG["NodeAddress"]
    vless["uuid"] = CONFIG["Uuid"]
    vless["tls"]["server_name"] = CONFIG["RealitySni"]
    vless["tls"]["reality"]["public_key"] = CONFIG["RealityPublicKey"]
    vless["tls"]["reality"]["short_id"] = CONFIG["ShortId"]

    hy2["server"] = CONFIG["NodeAddress"]
    hy2["password"] = CONFIG["Hy2Password"]
    hy2["tls"]["server_name"] = CONFIG["Hy2Sni"]

    for service in cfg.get("services", []):
        if service.get("type") == "api":
            assert_field(service, "secret", f"{path} API")
            service["secret"] = CONFIG.get("SingboxApiSecret", CONFIG.get("MihomoApiSecret", ""))

    hs_server = CONFIG.get("HeadscaleServer", "")
    if hs_server.startswith("REPLACE_WITH_"):
        hs_server = ""
    else:
        hs_server = hs_server.strip()

    hs_domain = CONFIG.get("HeadscaleBaseDomain", "")
    if hs_domain.startswith("REPLACE_WITH_"):
        hs_domain = ""
    else:
        hs_domain = hs_domain.strip()

    # 1. 处理 inbounds.platform.http_proxy.bypass_domain
    if "inbounds" in cfg and cfg["inbounds"]:
        for ib in cfg["inbounds"]:
            if ("platform" in ib and ib["platform"] and
                "http_proxy" in ib["platform"] and ib["platform"]["http_proxy"] and
                "bypass_domain" in ib["platform"]["http_proxy"] and ib["platform"]["http_proxy"]["bypass_domain"] is not None):
                new_bypass = []
                for entry in ib["platform"]["http_proxy"]["bypass_domain"]:
                    if entry == "REPLACE_WITH_HEADSCALE_SERVER":
                        if hs_server:
                            new_bypass.append(hs_server)
                    elif entry == "REPLACE_WITH_HEADSCALE_BASE_DOMAIN":
                        if hs_domain:
                            new_bypass.append(f"*.{hs_domain}")
                            new_bypass.append(hs_domain)
                    else:
                        new_bypass.append(entry)
                ib["platform"]["http_proxy"]["bypass_domain"] = new_bypass

    # 2. 处理 dns.rules
    if "dns" in cfg and cfg["dns"] and "rules" in cfg["dns"] and cfg["dns"]["rules"]:
        new_dns_rules = []
        for r in cfg["dns"]["rules"]:
            is_magic_dns = False
            is_hs_server = False
            if "domain_suffix" in r and r["domain_suffix"] is not None:
                suffixes = r["domain_suffix"]
                if isinstance(suffixes, str):
                    suffixes = [suffixes]
                for s in suffixes:
                    if s == "REPLACE_WITH_HEADSCALE_BASE_DOMAIN" or (hs_domain and s == hs_domain):
                        is_magic_dns = True
                        break
                    if s == "REPLACE_WITH_HEADSCALE_SERVER" or (hs_server and s == hs_server):
                        is_hs_server = True
                        break
            if is_magic_dns:
                if hs_domain:
                    r["domain_suffix"] = [hs_domain]
                    r["server"] = "tailscale-dns"
                    new_dns_rules.append(r)
            elif is_hs_server:
                if hs_server:
                    r["domain_suffix"] = [hs_server]
                    r["server"] = "ali"
                    new_dns_rules.append(r)
            else:
                new_dns_rules.append(r)
        cfg["dns"]["rules"] = new_dns_rules

    # 3. 处理 route.rules
    if "route" in cfg and cfg["route"] and "rules" in cfg["route"] and cfg["route"]["rules"]:
        new_route_rules = []
        for r in cfg["route"]["rules"]:
            is_inner_domain = False
            is_server_domain = False
            if "domain_suffix" in r and r["domain_suffix"] is not None:
                suffixes = r["domain_suffix"]
                if isinstance(suffixes, str):
                    suffixes = [suffixes]
                for s in suffixes:
                    if s == "REPLACE_WITH_HEADSCALE_BASE_DOMAIN" or (hs_domain and s == hs_domain):
                        is_inner_domain = True
                        break
                    if s == "REPLACE_WITH_HEADSCALE_SERVER" or (hs_server and s == hs_server):
                        is_server_domain = True
                        break
            if is_inner_domain:
                if hs_domain:
                    r["domain_suffix"] = [hs_domain]
                    r["outbound"] = "Direct-Tailscale"
                    new_route_rules.append(r)
            elif is_server_domain:
                if hs_server:
                    r["domain_suffix"] = [hs_server]
                    r["outbound"] = "Direct"
                    new_route_rules.append(r)
            else:
                new_route_rules.append(r)
        cfg["route"]["rules"] = new_route_rules

    apply_ruleset_proxy_to_json(cfg)
    return json.dumps(cfg, indent=2, ensure_ascii=False)


def update_mihomo(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    text = set_yaml_proxy(text, "Reality", {
        "server": (4, CONFIG["NodeAddress"]),
        "port": (4, int(CONFIG.get("RealityPort", 443))),
        "uuid": (4, CONFIG["Uuid"]),
        "servername": (4, CONFIG["RealitySni"]),
        "public-key": (6, CONFIG["RealityPublicKey"]),
        "short-id": (6, CONFIG["ShortId"]),
    })
    text = set_yaml_proxy(text, "Hysteria2", {
        "server": (4, CONFIG["NodeAddress"]),
        "port": (4, int(CONFIG.get("Hy2Port", 443))),
        "password": (4, CONFIG["Hy2Password"]),
        "sni": (4, CONFIG["Hy2Sni"]),
    })
    text = set_yaml_proxy(text, "VLESS-WS-CF", {
        "server": (4, CONFIG["WsOptimizedDomain"]),
        "port": (4, int(CONFIG.get("WsPort", 8443))),
        "uuid": (4, CONFIG["WsUuid"]),
        "servername": (4, CONFIG["WsSni"]),
        "path": (6, CONFIG["WsPath"]),
        "Host": (8, CONFIG["WsSni"]),
        "max-early-data": (6, int(CONFIG.get("WsMaxEarlyData", 2048))),
        "early-data-header-name": (6, CONFIG.get("WsEarlyDataHeader", "Sec-WebSocket-Protocol")),
    })
    text = set_yaml_field(text, "secret", 0, CONFIG["MihomoApiSecret"])

    hs_server = CONFIG.get("HeadscaleServer", "")
    if hs_server.startswith("REPLACE_WITH_"):
        hs_server = ""
    else:
        hs_server = hs_server.strip()

    hs_domain = CONFIG.get("HeadscaleBaseDomain", "")
    if hs_domain.startswith("REPLACE_WITH_"):
        hs_domain = ""
    else:
        hs_domain = hs_domain.strip()

    if hs_server:
        text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_SERVER,', f"  - DOMAIN-SUFFIX,{hs_server},", text)
        text = re.sub(r"(?m)^\s*-\s*'REPLACE_WITH_HEADSCALE_SERVER'", f"    - '{hs_server}'", text)
        text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_SERVER'", f"    - '+.{hs_server}'", text)
        text = re.sub(r"(?m)^\s*'REPLACE_WITH_HEADSCALE_SERVER':", f"    '{hs_server},+.{hs_server}':", text)
    else:
        text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_SERVER,[^\r\n]*\r?\n?', "", text)
        text = re.sub(r"(?m)^\s*-\s*'REPLACE_WITH_HEADSCALE_SERVER'[^\r\n]*\r?\n?", "", text)
        text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_SERVER'[^\r\n]*\r?\n?", "", text)
        text = re.sub(r"(?m)^\s*'REPLACE_WITH_HEADSCALE_SERVER':[^\r\n]*\r?\n(?:\s+-[^\r\n]+\r?\n)+", "", text)

    if hs_domain:
        text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_BASE_DOMAIN,', f"  - DOMAIN-SUFFIX,{hs_domain},", text)
    else:
        text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_BASE_DOMAIN,[^\r\n]*\r?\n?', "", text)

    if hs_domain:
        text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN'", f"    - '+.{hs_domain}'", text)
        text = re.sub(r"(?m)^\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN':", f"    '+.{hs_domain}':", text)
    else:
        text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN'[^\r\n]*\r?\n?", "", text)
        text = re.sub(r"(?m)^\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN':[^\r\n]*\r?\n\s*-\s*100\.100\.100\.100\r?\n?", "", text)

    # 处理 proxy-providers 外部多订阅自动注入与回退
    is_router = ("router-selfonly" in path) or ("router" in path)
    apply_to_client = bool(CONFIG.get("ApplySubscribesToClients", False))
    text = apply_proxy_providers_to_yaml(
        text,
        CONFIG.get("ExternalSubscribes", []),
        is_router=is_router,
        apply_to_client=apply_to_client
    )

    return apply_ruleset_proxy_to_yaml(text)


def render_node_links(root, is_preview=False):
    """用与 server.json 同一批取值生成 nodes/*.txt 分享链接，避免两端不一致。"""
    node = str(CONFIG["NodeAddress"]).strip()
    node_encoded = urllib.parse.quote(node, safe="")
    reality_port = int(CONFIG.get("RealityPort", 443))
    hy2_port = int(CONFIG.get("Hy2Port", 443))
    sni = urllib.parse.quote(str(CONFIG["RealitySni"]).strip(), safe=".-_")
    hy2_sni = urllib.parse.quote(str(CONFIG["Hy2Sni"]).strip(), safe=".-_")
    hy2_password = urllib.parse.quote(str(CONFIG["Hy2Password"]), safe="")

    vless_url = (
        f"vless://{CONFIG['Uuid']}@{node_encoded}:{reality_port}"
        f"?encryption=none&flow=xtls-rprx-vision&security=reality"
        f"&sni={sni}&fp=chrome&pbk={CONFIG['RealityPublicKey']}"
        f"&sid={CONFIG['ShortId']}&type=tcp&headerType=none#Reality"
    )
    hy2_url = (
        f"hysteria2://{hy2_password}@{node_encoded}:{hy2_port}/"
        f"?sni={hy2_sni}&insecure=0#Hysteria2"
    )

    ws_opt = urllib.parse.quote(str(CONFIG["WsOptimizedDomain"]).strip(), safe="")
    ws_sni = urllib.parse.quote(str(CONFIG["WsSni"]).strip(), safe=".-_")
    ws_path = urllib.parse.quote(str(CONFIG["WsPath"]).strip(), safe="/?=&")
    ws_port = int(CONFIG.get("WsPort", 8443))
    vless_ws_url = (
        f"vless://{CONFIG['WsUuid']}@{ws_opt}:{ws_port}"
        f"?encryption=none&security=tls&sni={ws_sni}&type=ws&host={ws_sni}"
        f"&path={ws_path}&fp=chrome#VLESS-WS-CF"
    )

    out_dir = os.path.join(root, "nodes")
    targets = [
        (os.path.join(out_dir, "vless.txt"), vless_url + "\n"),
        (os.path.join(out_dir, "hysteria2.txt"), hy2_url + "\n"),
        (os.path.join(out_dir, "vless_ws.txt"), vless_ws_url + "\n"),
    ]
    if is_preview:
        return [p for p, _ in targets]

    os.makedirs(out_dir, exist_ok=True)
    written = []
    for path, content in targets:
        temp = f"{path}.tmp-{uuid.uuid4().hex}"
        with open(temp, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        os.replace(temp, path)
        written.append(path)
    return written


def parse_args():
    parser = argparse.ArgumentParser(
        description="递归扫描 singbox-dual443/ 目录及子目录中的 .json/.yaml，批量原地覆写双 443 服务端与客户端配置。"
    )
    parser.add_argument(
        "-c", "--config-root",
        dest="config_root",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="指定扫描的根目录路径（默认：脚本所在目录）"
    )
    parser.add_argument(
        "-p", "--preview",
        dest="is_preview",
        action="store_true",
        help="仅预检扫描并输出识别出的配置文件路径，不修改文件，不泄露凭据"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    assert_values(CONFIG)

    root = os.path.abspath(args.config_root)
    if not os.path.isdir(root):
        raise ValueError(f"扫描目录不存在：{root}；未修改任何配置。")

    files = []
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in [".json", ".yaml"]:
                files.append(os.path.join(dirpath, filename))
    files.sort()

    updates = {}
    skipped = 0
    for file_path in files:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
        ext = os.path.splitext(file_path)[1].lower()
        if ext == ".json":
            is_server = bool(re.search(r'"tag"\s*:\s*"(?:VLESS-Vision-Reality-in|hysteria-in)"', content))
            is_client = bool(re.search(r'"tag"\s*:\s*"(?:Reality|Hysteria2)"', content))
            if is_server and is_client:
                raise ValueError(f"文件同时包含服务端与客户端标签：{file_path}；未修改任何配置。")
            if is_server:
                updates[file_path] = update_server(file_path)
            elif is_client:
                updates[file_path] = update_singbox_client(file_path)
            else:
                skipped += 1
        elif ext == ".yaml":
            if (re.search(r'(?m)^proxies:[ \t]*\r?$', content) and
                re.search(r'(?m)^  - name:[ \t]*(?:Reality|Hysteria2)[ \t]*\r?$', content)):
                updates[file_path] = update_mihomo(file_path)
            else:
                skipped += 1
        else:
            skipped += 1

    paths = sorted(updates.keys())
    if len(paths) == 0:
        raise ValueError(f"扫描了 {len(files)} 个 JSON/YAML，但未识别到双 443 配置；未修改任何文件。")

    for p in paths:
        if "REPLACE_WITH_" in updates[p]:
            raise ValueError(f"配置中仍有未处理的占位符：{p}；未修改任何配置。")

    proxy_desc = resolve_ruleset_prefix() or "（未设置，规则集与 Dashboard 走直连下载）"

    if args.is_preview:
        print(f"扫描 {len(files)} 个 JSON/YAML，识别 {len(paths)} 个配置，跳过 {skipped} 个；预览模式未写入，也未输出任何凭据。")
        print(f"规则集下载前缀：{proxy_desc}")
        for p in paths:
            print(p)
        print("将同步生成分享链接：")
        for p in render_node_links(root, is_preview=True):
            print(p)
        return

    for p in paths:
        temp = f"{p}.tmp-{uuid.uuid4().hex}"
        bak = f"{p}.bak-{uuid.uuid4().hex}"
        try:
            with open(temp, "w", encoding="utf-8", newline="\n") as f:
                f.write(updates[p] + "\n")
            try:
                st = os.stat(p)
                os.chmod(temp, st.st_mode)
            except OSError:
                pass
            os.replace(temp, p)
        finally:
            if os.path.exists(temp):
                try: os.remove(temp)
                except OSError: pass
            if os.path.exists(bak):
                try: os.remove(bak)
                except OSError: pass

    print(f"已原地覆写 {len(paths)} 个配置文件；请在目标系统检查并测试，不要将脚本或含真实凭据的文件提交 Git。")
    print(f"规则集下载前缀：{proxy_desc}")
    for p in render_node_links(root, is_preview=False):
        print(f"已同步分享链接：{p}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(f"{str(e)}\n")
        sys.exit(1)
