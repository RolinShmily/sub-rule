#!/usr/bin/env bash
#
# 递归扫描脚本所在的 singbox-dual443/ 目录及子目录中的 .json/.yaml；仅覆写识别出的双 443 服务端与客户端配置。
# 请只在本机填写下方参数：脚本和覆写后的配置都将包含明文凭据，切勿提交或公开分享。
# 首次覆写后仍可修改参数再次运行；按配置字段定位，不依赖旧占位符。
# 示例：./Update-SingboxDual443.sh --preview
#       ./Update-SingboxDual443.sh
#       bash Update-SingboxDual443.sh
#

set -euo pipefail

# --- 只编辑这里；保持所有密钥为单引号字符串 ---
NodeAddress='REPLACE_WITH_NODE_ADDRESS'           # VPS 域名或 IP，客户端连接地址
Hy2Sni='REPLACE_WITH_HY2_SNI'                    # Hy2 证书覆盖的域名
RealitySni='REPLACE_WITH_REALITY_SNI'            # Reality 客户端 SNI / 服务端 server_name
HandshakeHost='REPLACE_WITH_REALITY_HANDSHAKE_HOST' # Reality 握手目标主机；可与 SNI 不同
HandshakePort=443                                # Reality 握手目标端口；Nginx 8443 时改为 8443
Uuid='REPLACE_WITH_UUID'
RealityPrivateKey='REPLACE_WITH_REALITY_PRIVATE_KEY'    # 只写服务端
RealityPublicKey='REPLACE_WITH_REALITY_PUBLIC_KEY'     # 只写客户端
ShortId='REPLACE_WITH_REALITY_SHORT_ID'           # 2-16 位偶数长度十六进制
Hy2Password='REPLACE_WITH_HYSTERIA2_PASSWORD'
CertificatePath='REPLACE_WITH_CERTIFICATE_PATH'   # Debian fullchain.pem 绝对路径
KeyPath='REPLACE_WITH_KEY_PATH'                   # Debian privkey.pem 绝对路径
SingboxApiSecret='REPLACE_WITH_SINGBOX_API_SECRET'     # 桌面端本机控制 API
MihomoApiSecret='REPLACE_WITH_MIHOMO_API_SECRET'       # Mihomo 本机控制 API

# --- 可选：Headscale / Tailscale 自建组网直连（若不使用自建 Headscale，保持 '' 或占位符即可） ---
HeadscaleServer='REPLACE_WITH_HEADSCALE_SERVER'      # 例如 'hs.example.com'，为空时自动剔除对应域名规则
HeadscaleBaseDomain='REPLACE_WITH_HEADSCALE_BASE_DOMAIN'  # 例如 'tail.net'，为空时自动剔除对应域名规则

# --- 以下内容请勿随意修改 ---

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ConfigRoot="${SCRIPT_DIR}"
Preview=0

show_help() {
    cat << 'EOF'
用法: Update-SingboxDual443.sh [选项]

递归扫描 singbox-dual443/ 目录及子目录中的 .json/.yaml，批量原地覆写双 443 服务端与客户端配置。

选项:
  -c, --config-root <DIR>  指定扫描的根目录路径（默认：脚本所在目录）
  -p, --preview, -Preview  仅预检扫描并输出识别出的配置文件路径，不修改文件，不泄露凭据
  -h, --help               显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config-root)
            if [[ -z "${2:-}" ]]; then
                echo "错误: $1 参数缺少目录路径；未修改任何配置。" >&2
                exit 1
            fi
            ConfigRoot="$2"
            shift 2
            ;;
        --config-root=*)
            ConfigRoot="${1#*=}"
            shift
            ;;
        -ConfigRoot)
            if [[ -z "${2:-}" ]]; then
                echo "错误: $1 参数缺少目录路径；未修改任何配置。" >&2
                exit 1
            fi
            ConfigRoot="$2"
            shift 2
            ;;
        -p|--preview|-Preview)
            Preview=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "错误: 未知参数 $1；未修改任何配置。" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "错误: 未找到 python3 命令。sing-box 双 443 配置覆写依赖 Python 3 标准库（无需安装任何第三方模块）。" >&2
    echo "请先在当前系统安装 Python 3：" >&2
    echo "  - Debian / Ubuntu: apt update && apt install -y python3" >&2
    echo "  - RHEL / CentOS / Rocky: dnf install -y python3" >&2
    echo "  - Alpine: apk add python3" >&2
    echo "  - macOS: brew install python 或使用 Xcode 命令行工具" >&2
    exit 1
fi

export DUAL443_CONFIG_ROOT="$ConfigRoot"
export DUAL443_PREVIEW="$Preview"
export DUAL443_NODE_ADDRESS="$NodeAddress"
export DUAL443_HY2_SNI="$Hy2Sni"
export DUAL443_REALITY_SNI="$RealitySni"
export DUAL443_HANDSHAKE_HOST="$HandshakeHost"
export DUAL443_HANDSHAKE_PORT="$HandshakePort"
export DUAL443_UUID="$Uuid"
export DUAL443_REALITY_PRIVATE_KEY="$RealityPrivateKey"
export DUAL443_REALITY_PUBLIC_KEY="$RealityPublicKey"
export DUAL443_SHORT_ID="$ShortId"
export DUAL443_HY2_PASSWORD="$Hy2Password"
export DUAL443_CERTIFICATE_PATH="$CertificatePath"
export DUAL443_KEY_PATH="$KeyPath"
export DUAL443_SINGBOX_API_SECRET="$SingboxApiSecret"
export DUAL443_MIHOMO_API_SECRET="$MihomoApiSecret"
export DUAL443_HEADSCALE_SERVER="$HeadscaleServer"
export DUAL443_HEADSCALE_BASE_DOMAIN="$HeadscaleBaseDomain"

python3 - << 'PY_EOF'
import sys
import os
import re
import json
import uuid

def main():
    values = {
        'NodeAddress': os.environ.get('DUAL443_NODE_ADDRESS', ''),
        'Hy2Sni': os.environ.get('DUAL443_HY2_SNI', ''),
        'RealitySni': os.environ.get('DUAL443_REALITY_SNI', ''),
        'HandshakeHost': os.environ.get('DUAL443_HANDSHAKE_HOST', ''),
        'HandshakePort': os.environ.get('DUAL443_HANDSHAKE_PORT', '443'),
        'Uuid': os.environ.get('DUAL443_UUID', ''),
        'RealityPrivateKey': os.environ.get('DUAL443_REALITY_PRIVATE_KEY', ''),
        'RealityPublicKey': os.environ.get('DUAL443_REALITY_PUBLIC_KEY', ''),
        'ShortId': os.environ.get('DUAL443_SHORT_ID', ''),
        'Hy2Password': os.environ.get('DUAL443_HY2_PASSWORD', ''),
        'CertificatePath': os.environ.get('DUAL443_CERTIFICATE_PATH', ''),
        'KeyPath': os.environ.get('DUAL443_KEY_PATH', ''),
        'SingboxApiSecret': os.environ.get('DUAL443_SINGBOX_API_SECRET', ''),
        'MihomoApiSecret': os.environ.get('DUAL443_MIHOMO_API_SECRET', ''),
        'HeadscaleServer': os.environ.get('DUAL443_HEADSCALE_SERVER', ''),
        'HeadscaleBaseDomain': os.environ.get('DUAL443_HEADSCALE_BASE_DOMAIN', ''),
    }
    config_root = os.environ.get('DUAL443_CONFIG_ROOT', '')
    is_preview = os.environ.get('DUAL443_PREVIEW', '0') == '1'

    def assert_values():
        optional_keys = {'HeadscaleServer', 'HeadscaleBaseDomain'}
        for key in values.keys():
            if key == 'HandshakePort' or key in optional_keys:
                continue
            val_str = str(values[key]).strip()
            if not val_str or val_str.startswith('REPLACE_WITH_'):
                raise ValueError(f"请先在脚本头部填写 {key}；未修改任何配置。")

        uuid_str = str(values['Uuid']).strip()
        try:
            uuid.UUID(uuid_str)
            if not re.fullmatch(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', uuid_str):
                raise ValueError()
        except Exception:
            raise ValueError("Uuid 必须是有效的 UUID；未修改任何配置。")

        short_id = str(values['ShortId'])
        if not re.fullmatch(r'^(?:[0-9a-fA-F]{2}){1,8}$', short_id):
            raise ValueError("ShortId 必须是 2-16 位偶数长度的十六进制字符串；未修改任何配置。")

        try:
            port = int(values['HandshakePort'])
            if port < 1 or port > 65535:
                raise ValueError()
        except Exception:
            raise ValueError("HandshakePort 必须在 1-65535 之间；未修改任何配置。")

        for key in ['RealityPrivateKey', 'RealityPublicKey']:
            val = str(values[key])
            if not re.fullmatch(r'^[A-Za-z0-9_-]{43}$', val):
                raise ValueError(f"{key} 的格式不是 43 位 Base64URL；未修改任何配置。")

        for key in ['CertificatePath', 'KeyPath']:
            val = str(values[key])
            if not val.startswith('/'):
                raise ValueError(f"{key} 必须是 Debian 上的绝对路径；未修改任何配置。")

        for key in ['NodeAddress', 'Hy2Sni', 'RealitySni', 'HandshakeHost']:
            val = str(values[key])
            if re.search(r'[\s/]', val):
                raise ValueError(f"{key} 只能填主机名或 IP，不要带协议或路径；未修改任何配置。")

        for key in optional_keys:
            val = str(values[key])
            if val.strip() and not val.strip().startswith('REPLACE_WITH_'):
                if re.search(r'[\s/:]', val):
                    raise ValueError(f"{key} 只能填主机名或域名（如 hs.example.com），不要带协议、路径或端口；未修改任何配置。")

        for key in ['Hy2Password', 'SingboxApiSecret', 'MihomoApiSecret']:
            val = str(values[key])
            if re.search(r'[\r\n]', val) or len(val) < 16:
                raise ValueError(f"{key} 至少 16 位且不能包含换行；未修改任何配置。")

    def get_one(items, description):
        if len(items) != 1:
            raise ValueError(f"无法唯一定位 {description}（找到 {len(items)} 个）；未修改任何配置。")
        return items[0]

    def assert_field(obj, field, description):
        if obj is None or not isinstance(obj, dict) or field not in obj or obj[field] is None:
            raise ValueError(f"缺少 {description}.{field}；未修改任何配置。")

    def convert_to_yaml_scalar(value):
        return "'" + str(value).replace("'", "''") + "'"

    def set_yaml_field(block, field, spaces, value):
        pattern = rf'(?m)^({" " * spaces}{re.escape(field)}:[ \t]*).*$'
        matches = list(re.finditer(pattern, block))
        if len(matches) != 1:
            raise ValueError(f"无法唯一定位 YAML 字段 {field}；未修改任何配置。")
        scalar = convert_to_yaml_scalar(value)
        return re.sub(pattern, lambda m: m.group(1) + scalar, block, count=1)

    def set_yaml_proxy(text, name, fields):
        pattern = rf'(?ms)^(  - name: {re.escape(name)}[^\r\n]*\r?\n)(.*?)(?=^  - name: |^[^\s#]|\z)'
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
        with open(path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)

        inbounds = cfg.get('inbounds', [])
        vless_list = [ib for ib in inbounds if ib.get('tag') == 'VLESS-Vision-Reality-in' and ib.get('type') == 'vless']
        hy2_list = [ib for ib in inbounds if ib.get('tag') == 'hysteria-in' and ib.get('type') == 'hysteria2']

        vless = get_one(vless_list, '服务端 Reality 入站')
        hy2 = get_one(hy2_list, '服务端 Hy2 入站')

        if vless.get('listen_port') != 443 or hy2.get('listen_port') != 443:
            raise ValueError("服务端不再是 TCP/UDP 双 443 模板；未修改任何配置。")

        for fld in ['users', 'tls']:
            assert_field(vless, fld, '服务端 Reality')
            assert_field(hy2, fld, '服务端 Hy2')

        user = get_one(vless.get('users', []), '服务端 Reality 用户')
        hy2_user = get_one(hy2.get('users', []), '服务端 Hy2 用户')

        assert_field(vless['tls'], 'reality', '服务端 Reality TLS')
        assert_field(vless['tls']['reality'], 'handshake', '服务端 Reality')
        for fld in ['certificate_path', 'key_path', 'server_name']:
            assert_field(hy2['tls'], fld, '服务端 Hy2 TLS')

        user['uuid'] = values['Uuid']
        vless['tls']['server_name'] = values['RealitySni']
        vless['tls']['reality']['handshake']['server'] = values['HandshakeHost']
        vless['tls']['reality']['handshake']['server_port'] = int(values['HandshakePort'])
        vless['tls']['reality']['private_key'] = values['RealityPrivateKey']
        vless['tls']['reality']['short_id'] = [values['ShortId']]

        hy2_user['password'] = values['Hy2Password']
        hy2['tls']['server_name'] = values['Hy2Sni']
        hy2['tls']['certificate_path'] = values['CertificatePath']
        hy2['tls']['key_path'] = values['KeyPath']

        return json.dumps(cfg, indent=2, ensure_ascii=False)

    def update_singbox_client(path):
        with open(path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)

        outbounds = cfg.get('outbounds', [])
        vless_list = [ob for ob in outbounds if ob.get('tag') == '自建-Reality' and ob.get('type') == 'vless']
        hy2_list = [ob for ob in outbounds if ob.get('tag') == '自建-Hy2' and ob.get('type') == 'hysteria2']

        vless = get_one(vless_list, f"{path} Reality 出站")
        hy2 = get_one(hy2_list, f"{path} Hy2 出站")

        for fld in ['tls', 'uuid', 'server']:
            assert_field(vless, fld, f"{path} Reality")
        for fld in ['tls', 'password', 'server']:
            assert_field(hy2, fld, f"{path} Hy2")
        assert_field(vless['tls'], 'reality', f"{path} Reality TLS")

        vless['server'] = values['NodeAddress']
        vless['uuid'] = values['Uuid']
        vless['tls']['server_name'] = values['RealitySni']
        vless['tls']['reality']['public_key'] = values['RealityPublicKey']
        vless['tls']['reality']['short_id'] = values['ShortId']

        hy2['server'] = values['NodeAddress']
        hy2['password'] = values['Hy2Password']
        hy2['tls']['server_name'] = values['Hy2Sni']

        for service in cfg.get('services', []):
            if service.get('type') == 'api':
                assert_field(service, 'secret', f"{path} API")
                service['secret'] = values['SingboxApiSecret']

        hs_server = values.get('HeadscaleServer', '')
        if hs_server.startswith('REPLACE_WITH_'):
            hs_server = ''
        else:
            hs_server = hs_server.strip()

        hs_domain = values.get('HeadscaleBaseDomain', '')
        if hs_domain.startswith('REPLACE_WITH_'):
            hs_domain = ''
        else:
            hs_domain = hs_domain.strip()

        # 1. 处理 inbounds.platform.http_proxy.bypass_domain (Windows / macOS)
        if 'inbounds' in cfg and cfg['inbounds']:
            for ib in cfg['inbounds']:
                if ('platform' in ib and ib['platform'] and
                    'http_proxy' in ib['platform'] and ib['platform']['http_proxy'] and
                    'bypass_domain' in ib['platform']['http_proxy'] and ib['platform']['http_proxy']['bypass_domain'] is not None):
                    new_bypass = []
                    for entry in ib['platform']['http_proxy']['bypass_domain']:
                        if entry == 'REPLACE_WITH_HEADSCALE_SERVER':
                            if hs_server:
                                new_bypass.append(hs_server)
                        elif entry == 'REPLACE_WITH_HEADSCALE_BASE_DOMAIN':
                            if hs_domain:
                                new_bypass.append(f"*.{hs_domain}")
                                new_bypass.append(hs_domain)
                        else:
                            new_bypass.append(entry)
                    ib['platform']['http_proxy']['bypass_domain'] = new_bypass

        # 2. 处理 dns.rules (MagicDNS 走 tailscale-dns，HeadscaleServer 走 ali)
        if 'dns' in cfg and cfg['dns'] and 'rules' in cfg['dns'] and cfg['dns']['rules']:
            new_dns_rules = []
            for r in cfg['dns']['rules']:
                is_magic_dns = False
                is_hs_server = False
                if 'domain_suffix' in r and r['domain_suffix'] is not None:
                    suffixes = r['domain_suffix']
                    if isinstance(suffixes, str):
                        suffixes = [suffixes]
                    for s in suffixes:
                        if s == 'REPLACE_WITH_HEADSCALE_BASE_DOMAIN' or (hs_domain and s == hs_domain):
                            is_magic_dns = True
                            break
                        if s == 'REPLACE_WITH_HEADSCALE_SERVER' or (hs_server and s == hs_server):
                            is_hs_server = True
                            break
                if is_magic_dns:
                    if hs_domain:
                        r['domain_suffix'] = [hs_domain]
                        r['server'] = 'tailscale-dns'
                        new_dns_rules.append(r)
                elif is_hs_server:
                    if hs_server:
                        r['domain_suffix'] = [hs_server]
                        r['server'] = 'ali'
                        new_dns_rules.append(r)
                else:
                    new_dns_rules.append(r)
            cfg['dns']['rules'] = new_dns_rules

        # 3. 处理 route.rules (精准分离内网与公网直连)
        if 'route' in cfg and cfg['route'] and 'rules' in cfg['route'] and cfg['route']['rules']:
            new_route_rules = []
            for r in cfg['route']['rules']:
                is_inner_domain = False
                is_server_domain = False
                if 'domain_suffix' in r and r['domain_suffix'] is not None:
                    suffixes = r['domain_suffix']
                    if isinstance(suffixes, str):
                        suffixes = [suffixes]
                    for s in suffixes:
                        if s == 'REPLACE_WITH_HEADSCALE_BASE_DOMAIN' or (hs_domain and s == hs_domain):
                            is_inner_domain = True
                            break
                        if s == 'REPLACE_WITH_HEADSCALE_SERVER' or (hs_server and s == hs_server):
                            is_server_domain = True
                            break
                if is_inner_domain:
                    if hs_domain:
                        r['domain_suffix'] = [hs_domain]
                        r['outbound'] = '直连-tailscale'
                        new_route_rules.append(r)
                elif is_server_domain:
                    if hs_server:
                        r['domain_suffix'] = [hs_server]
                        r['outbound'] = '直连'
                        new_route_rules.append(r)
                else:
                    new_route_rules.append(r)
            cfg['route']['rules'] = new_route_rules

        return json.dumps(cfg, indent=2, ensure_ascii=False)

    def update_mihomo(path):
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()

        text = set_yaml_proxy(text, '自建-Reality', {
            'server': (4, values['NodeAddress']),
            'uuid': (4, values['Uuid']),
            'servername': (4, values['RealitySni']),
            'public-key': (6, values['RealityPublicKey']),
            'short-id': (6, values['ShortId']),
        })
        text = set_yaml_proxy(text, '自建-Hy2', {
            'server': (4, values['NodeAddress']),
            'password': (4, values['Hy2Password']),
            'sni': (4, values['Hy2Sni']),
        })
        text = set_yaml_field(text, 'secret', 0, values['MihomoApiSecret'])

        hs_server = values.get('HeadscaleServer', '')
        if hs_server.startswith('REPLACE_WITH_'):
            hs_server = ''
        else:
            hs_server = hs_server.strip()

        hs_domain = values.get('HeadscaleBaseDomain', '')
        if hs_domain.startswith('REPLACE_WITH_'):
            hs_domain = ''
        else:
            hs_domain = hs_domain.strip()

        if hs_server:
            text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_SERVER,', f"  - DOMAIN-SUFFIX,{hs_server},", text)
        else:
            text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_SERVER,[^\r\n]*\r?\n?', '', text)

        if hs_domain:
            text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_BASE_DOMAIN,', f"  - DOMAIN-SUFFIX,{hs_domain},", text)
        else:
            text = re.sub(r'(?m)^\s*-\s*DOMAIN-SUFFIX,REPLACE_WITH_HEADSCALE_BASE_DOMAIN,[^\r\n]*\r?\n?', '', text)

        if hs_domain:
            text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN'", f"    - '+.{hs_domain}'", text)
            text = re.sub(r"(?m)^\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN':", f"    '+.{hs_domain}':", text)
        else:
            text = re.sub(r"(?m)^\s*-\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN'[^\r\n]*\r?\n?", '', text)
            text = re.sub(r"(?m)^\s*'\+\.REPLACE_WITH_HEADSCALE_BASE_DOMAIN':[^\r\n]*\r?\n\s*-\s*100\.100\.100\.100\r?\n?", '', text)

        return text

    # 主执行逻辑
    assert_values()
    root = os.path.abspath(config_root)
    if not os.path.isdir(root):
        raise ValueError(f"扫描目录不存在：{root}；未修改任何配置。")

    files = []
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in ['.json', '.yaml']:
                files.append(os.path.join(dirpath, filename))
    files.sort()

    updates = {}
    skipped = 0
    for file_path in files:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        ext = os.path.splitext(file_path)[1].lower()
        if ext == '.json':
            is_server = bool(re.search(r'"tag"\s*:\s*"(?:VLESS-Vision-Reality-in|hysteria-in)"', content))
            is_client = bool(re.search(r'"tag"\s*:\s*"(?:自建-Reality|自建-Hy2)"', content))
            if is_server and is_client:
                raise ValueError(f"文件同时包含服务端与客户端标签：{file_path}；未修改任何配置。")
            if is_server:
                updates[file_path] = update_server(file_path)
            elif is_client:
                updates[file_path] = update_singbox_client(file_path)
            else:
                skipped += 1
        elif ext == '.yaml':
            if (re.search(r'(?m)^proxies:[ \t]*\r?$', content) and
                re.search(r'(?m)^  - name:[ \t]*(?:自建-Reality|自建-Hy2)[ \t]*\r?$', content)):
                updates[file_path] = update_mihomo(file_path)
            else:
                skipped += 1
        else:
            skipped += 1

    paths = sorted(updates.keys())
    if len(paths) == 0:
        raise ValueError(f"扫描了 {len(files)} 个 JSON/YAML，但未识别到双 443 配置；未修改任何文件。")

    for p in paths:
        if 'REPLACE_WITH_' in updates[p]:
            raise ValueError(f"配置中仍有未处理的占位符：{p}；未修改任何配置。")

    if is_preview:
        print(f"扫描 {len(files)} 个 JSON/YAML，识别 {len(paths)} 个配置，跳过 {skipped} 个；预览模式未写入，也未输出任何凭据。")
        for p in paths:
            print(p)
        return

    for p in paths:
        temp = f"{p}.tmp-{uuid.uuid4().hex}"
        bak = f"{p}.bak-{uuid.uuid4().hex}"
        try:
            with open(temp, 'w', encoding='utf-8', newline='\n') as f:
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

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        sys.stderr.write(f"{str(e)}\n")
        sys.exit(1)
PY_EOF
