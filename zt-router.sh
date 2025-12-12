#!/bin/bash
# ZeroTier ↔ 内网 路由一键配置/检查脚本（需 root 运行）

set -e

echo "=== ZeroTier 内网路由脚本 ==="
echo "1) 只检查当前配置（ip_forward 与 iptables）"
echo "2) 执行完整配置（交互式设置并保存）"
read -rp "请选择模式 [1/2]: " MODE

if [ "$MODE" = "1" ]; then
    echo
    echo "== 检查 net.ipv4.ip_forward 状态 =="
    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        IPFWD=$(cat /proc/sys/net/ipv4/ip_forward)
        echo "当前 net.ipv4.ip_forward = $IPFWD"
    else
        echo "未找到 /proc/sys/net/ipv4/ip_forward 文件，可能是容器环境或内核不支持。"
    fi

    echo
    echo "== 检查 iptables NAT 规则（POSTROUTING）=="
    iptables -t nat -L POSTROUTING -n -v || echo "获取 nat 表失败。"

    echo
    echo "== 检查 iptables FORWARD 规则 =="
    iptables -L FORWARD -n -v || echo "获取 FORWARD 链失败。"

    echo
    echo "检查完成，仅查看未修改任何配置。"
    exit 0
fi

if [ "$MODE" != "2" ]; then
    echo "无效选择，退出。"
    exit 1
fi

echo
echo "=== 进入配置模式 ==="

# 1. 询问物理内网网卡名称（连接你内网网段的那块，比如 ens33）
read -rp "请输入连接内网（你的局域网网段）的物理网卡名（例如 ens33）: " PHY_IFACE

# 简单检查
if ! ip link show "$PHY_IFACE" >/dev/null 2>&1; then
    echo "错误：找不到物理网卡 $PHY_IFACE ，请确认后重试。"
    exit 1
fi

# 2. 显示当前 ZeroTier 相关网卡，方便你确认名字
echo
echo "当前系统网卡列表（含 ZeroTier 网卡）："
ip -o link show | awk -F': ' '{print $2}' | grep -E 'zt|en|eth'

echo
read -rp "系统中有几个 ZeroTier 网卡需要做路由？请输入数量（例如 1 或 2）: " ZT_COUNT

if ! [[ "$ZT_COUNT" =~ ^[0-9]+$ ]] || [ "$ZT_COUNT" -lt 1 ]; then
    echo "错误：数量必须是 >=1 的整数。"
    exit 1
fi

ZT_IFACES=()
for ((i=1; i<=ZT_COUNT; i++)); do
    read -rp "请输入第 ${i} 个 ZeroTier 网卡名（例如 ztxatpvndj）: " ztname
    if ! ip link show "$ztname" >/dev/null 2>&1; then
        echo "错误：找不到 ZeroTier 网卡 $ztname ，请确认后重试。"
        exit 1
    fi
    ZT_IFACES+=("$ztname")
done

echo
echo "物理网卡: $PHY_IFACE"
echo "ZeroTier 网卡: ${ZT_IFACES[*]}"
read -rp "确认使用以上网卡配置？(y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "已取消。"
    exit 0
fi

echo
echo "== 1. 开启并持久化 IPv4 转发 =="

cat >/etc/sysctl.d/99-ipforward.conf << 'EOF'
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null
IPFWD=$(cat /proc/sys/net/ipv4/ip_forward)
echo "当前 net.ipv4.ip_forward = $IPFWD"
if [ "$IPFWD" != "1" ]; then
    echo "警告：ip_forward 未成功置为 1，请手动检查 /etc/sysctl.d/99-ipforward.conf。"
fi

echo
echo "== 2. 配置 iptables NAT 和 FORWARD 规则 =="

# 清空相关链，避免旧规则干扰
iptables -F FORWARD
iptables -t nat -F POSTROUTING

# NAT：从物理网卡出口做 MASQUERADE
iptables -t nat -A POSTROUTING -o "$PHY_IFACE" -j MASQUERADE

# FORWARD：为每个 ZeroTier 网卡添加转发规则
for zt in "${ZT_IFACES[@]}"; do
    # 内网 -> ZeroTier 的回包
    iptables -A FORWARD -i "$PHY_IFACE" -o "$zt" -m state --state RELATED,ESTABLISHED -j ACCEPT
    # ZeroTier -> 内网
    iptables -A FORWARD -i "$zt" -o "$PHY_IFACE" -j ACCEPT
done

echo
echo "== 3. 保存规则（netfilter-persistent）=="

if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "未检测到 netfilter-persistent，正在安装 iptables-persistent 和 netfilter-persistent ..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent netfilter-persistent
fi

netfilter-persistent save

echo
echo "== 4. 当前规则检查 =="

echo "--- nat 表 POSTROUTING ---"
iptables -t nat -L POSTROUTING -n -v

echo
echo "--- FORWARD 链 ---"
iptables -L FORWARD -n -v

echo
echo "配置完成："
echo "- 已开启并持久化 IPv4 转发"
echo "- 已为物理网卡 $PHY_IFACE 和 ZeroTier 网卡: ${ZT_IFACES[*]} 配置 NAT + 转发"
echo "- 规则已通过 netfilter-persistent 持久化"
echo
echo "请根据你实际的内网网段，在 ZeroTier 控制台中添加 Managed Route，例如："
echo "  Destination: <你的内网网段，例如 192.168.1.0/24 或 10.10.0.0/21>"
echo "  Via: 这台 Debian 的 ZeroTier IP"
echo
echo "然后在其他 ZeroTier 客户端上测试："
echo "  ping <Debian 的 ZeroTier IP>"
echo "  ping <内网主机的 IP（属于你上面填的网段）>"
