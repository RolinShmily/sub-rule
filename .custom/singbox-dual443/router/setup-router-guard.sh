#!/usr/bin/env bash
#
# Debian 软路由 br-lan 流量隔离守护脚本
# 作用：确保来自网桥 br-lan（下游 Windows 及其他设备）的流量 100% 直通主路由表，
#       绝对不被 Debian 宿主机上的 sing-box TUN 代理劫持，保障纯软路由转发稳定性。
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[错误] 本脚本需要 root 权限，请使用 sudo 执行：${NC}" >&2
    echo "  sudo $0" >&2
    exit 1
fi

echo -e "${BLUE}=== [1/4] 配置即时策略路由规则 (ip rule) ===${NC}"
# 清理可能存在的旧重复规则，确保只有一条 priority 100
while ip rule show | grep -q "iif br-lan lookup main"; do
    ip rule del iif br-lan table main priority 100 2>/dev/null || ip rule del iif br-lan table main 2>/dev/null || break
done

ip rule add iif br-lan table main priority 100
echo -e "${GREEN}[✓] 已成功添加策略路由：iif br-lan table main priority 100${NC}"

echo -e "\n${BLUE}=== [2/4] 配置 NetworkManager 自动触发器持久化 ===${NC}"
DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"
DISPATCHER_FILE="${DISPATCHER_DIR}/99-br-lan-guard.sh"

if [[ -d "$DISPATCHER_DIR" ]]; then
    cat << 'EOF' > "$DISPATCHER_FILE"
#!/bin/bash
INTERFACE="$1"
ACTION="$2"

if [ "$INTERFACE" = "br-lan" ] && [ "$ACTION" = "up" ]; then
    ip rule del iif br-lan table main priority 100 2>/dev/null || true
    ip rule add iif br-lan table main priority 100
fi
EOF
    chmod +x "$DISPATCHER_FILE"
    echo -e "${GREEN}[✓] 已创建 NetworkManager 钩子：${DISPATCHER_FILE}${NC}"
else
    echo -e "${YELLOW}[提示] 未检测到 NetworkManager 目录，跳过 dispatcher 写入${NC}"
fi

echo -e "\n${BLUE}=== [3/4] 配置 systemd 双保险服务开机自启 ===${NC}"
SERVICE_FILE="/etc/systemd/system/singbox-br-lan-guard.service"
cat << 'EOF' > "$SERVICE_FILE"
[Unit]
Description=Guard rule for br-lan to bypass sing-box TUN
After=network.target network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ip rule del iif br-lan table main priority 100 2>/dev/null || true; ip rule add iif br-lan table main priority 100'
ExecStop=/bin/sh -c 'ip rule del iif br-lan table main priority 100 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable singbox-br-lan-guard.service
systemctl start singbox-br-lan-guard.service
echo -e "${GREEN}[✓] 已启用并启动开机守护服务：singbox-br-lan-guard.service${NC}"

echo -e "\n${BLUE}=== [4/4] 检查 nftables USB 手机共享网络兼容性 ===${NC}"
NFT_CONF="/etc/nftables.conf"
if [[ -f "$NFT_CONF" ]]; then
    if grep -q 'oifname "wlo1" masquerade' "$NFT_CONF"; then
        echo -e "${YELLOW}[建议] 检测到当前 nftables 仅伪装了 wlo1：${NC}"
        echo "       oifname \"wlo1\" masquerade"
        echo -e "       若后续插入临时手机 USB 共享网络（enx*），下游可能会因未做 NAT 而断网。"
        echo -e "       建议将该行修改为反向排除模式（只要不是发给 br-lan 的流量都做 NAT）："
        echo -e "${GREEN}       oifname != \"br-lan\" masquerade${NC}"
    else
        echo -e "${GREEN}[✓] nftables 配置无需额外提醒${NC}"
    fi
fi

echo -e "\n${GREEN}=== 当前系统策略路由 (ip rule) 状态 ===${NC}"
ip rule show | grep -E --color=always "br-lan|priority 100|$"

echo -e "\n${GREEN}部署完成！${NC}"
echo "下游设备（Windows 等）的所有流量现在被物理钉死在系统主路由表上，"
echo "即使 Debian 本机运行 singbox-homerouter-deb.json 开启 TUN，下游也绝对不会受到任何干扰。"
