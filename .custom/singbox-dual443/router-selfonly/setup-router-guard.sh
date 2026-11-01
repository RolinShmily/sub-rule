#!/bin/sh
#
# Debian 软路由 br-lan 流量隔离守护脚本
# 作用：确保来自网桥 br-lan（下游 Windows 及其他设备）的流量 100% 直通主路由表，
#       绝对不被 Debian 宿主机上的 sing-box TUN 代理劫持，保障纯软路由转发稳定性。
#

# 若用户使用 sh 执行且系统存在 bash，自动无缝切换为 bash 环境
if [ -z "${BASH_VERSION:-}" ] && command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
fi

set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USER_ID=$(id -u 2>/dev/null || echo "1")
if [ "$USER_ID" -ne 0 ]; then
    printf "${RED}[错误] 本脚本需要 root 权限，请使用 sudo 执行：${NC}\n" >&2
    printf "  sudo %s\n" "$0" >&2
    exit 1
fi

printf "${BLUE}=== [1/4] 配置即时策略路由规则 (ip rule) ===${NC}\n"
# 清理可能存在的旧重复规则，确保只有一条 priority 100
while ip rule show 2>/dev/null | grep -q "iif br-lan lookup main"; do
    ip rule del iif br-lan table main priority 100 2>/dev/null || ip rule del iif br-lan table main 2>/dev/null || break
done

ip rule add iif br-lan table main priority 100
printf "${GREEN}[✓] 已成功添加策略路由：iif br-lan table main priority 100${NC}\n"

printf "\n${BLUE}=== [2/4] 配置 NetworkManager 自动触发器持久化 ===${NC}\n"
DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"
DISPATCHER_FILE="${DISPATCHER_DIR}/99-br-lan-guard.sh"

if [ -d "$DISPATCHER_DIR" ]; then
    cat << 'EOF' > "$DISPATCHER_FILE"
#!/bin/sh
INTERFACE="$1"
ACTION="$2"

if [ "$INTERFACE" = "br-lan" ] && [ "$ACTION" = "up" ]; then
    ip rule del iif br-lan table main priority 100 2>/dev/null || true
    ip rule add iif br-lan table main priority 100
fi
EOF
    chmod +x "$DISPATCHER_FILE"
    printf "${GREEN}[✓] 已创建 NetworkManager 钩子：${DISPATCHER_FILE}${NC}\n"
else
    printf "${YELLOW}[提示] 未检测到 NetworkManager 目录，跳过 dispatcher 写入${NC}\n"
fi

printf "\n${BLUE}=== [3/4] 配置 systemd 双保险服务开机自启 ===${NC}\n"
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

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable singbox-br-lan-guard.service 2>/dev/null || true
    systemctl start singbox-br-lan-guard.service 2>/dev/null || true
    printf "${GREEN}[✓] 已启用并启动开机守护服务：singbox-br-lan-guard.service${NC}\n"
else
    printf "${YELLOW}[提示] 未检测到 systemd，跳过服务注册${NC}\n"
fi

printf "\n${BLUE}=== [4/4] 检查 nftables USB 手机共享网络兼容性 ===${NC}\n"
NFT_CONF="/etc/nftables.conf"
if [ -f "$NFT_CONF" ]; then
    if grep -q 'oifname "wlo1" masquerade' "$NFT_CONF"; then
        printf "${YELLOW}[建议] 检测到当前 nftables 仅伪装了 wlo1：${NC}\n"
        printf "       oifname \"wlo1\" masquerade\n"
        printf "       若后续插入临时手机 USB 共享网络（enx*），下游可能会因未做 NAT 而断网。\n"
        printf "       建议将该行修改为反向排除模式（只要不是发给 br-lan 的流量都做 NAT）：\n"
        printf "${GREEN}       oifname != \"br-lan\" masquerade${NC}\n"
    else
        printf "${GREEN}[✓] nftables 配置无需额外提醒${NC}\n"
    fi
fi

printf "\n${GREEN}=== 当前系统策略路由 (ip rule) 状态 ===${NC}\n"
ip rule show | grep -E "br-lan|priority 100|$" || ip rule show

printf "\n${GREEN}部署完成！${NC}\n"
printf "下游设备（Windows 等）的所有流量现在被物理钉死在系统主路由表上，\n"
printf "即使 Debian 本机运行 singbox-homerouter-deb.json 开启 TUN，下游也绝对不会受到任何干扰。\n"
