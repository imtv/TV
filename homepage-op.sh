#!/bin/sh

# ==========================================
# OpenWrt Homepage 自动配置脚本
# 用于自动配置 rpcd 用户和 ACL 权限
# ==========================================

echo "----------------------------------------"
echo "开始配置 Homepage 面板所需的 OpenWrt 用户"
echo "----------------------------------------"

# 1. 交互式获取密码
echo -n "请输入你要设置的 homepage 用户密码: "
read PASSWORD

if [ -z "$PASSWORD" ]; then
    echo "❌ 错误: 密码不能为空！"
    exit 1
fi

echo "正在处理..."

# 2. 创建 ACL 权限文件
# 使用 cat EOF 写入，确保格式绝对正确
ACL_FILE="/usr/share/rpcd/acl.d/homepage.json"
echo " -> 正在创建 ACL 权限文件: $ACL_FILE"

cat > "$ACL_FILE" <<EOF
{
  "homepage": {
    "description": "Homepage widget",
    "read": {
      "ubus": {
        "network.interface.wan": ["status"],
        "network.interface.lan": ["status"],
        "network.device": ["status"],
        "system": ["info"]
      }
    }
  }
}
EOF

# 3. 使用 UCI 配置 RPCD 用户
echo " -> 正在配置系统用户 (UCI)..."

# 删除旧配置（如果存在）以防冲突
uci delete rpcd.homepage 2>/dev/null

# 创建新配置
uci set rpcd.homepage=login
uci set rpcd.homepage.username='homepage'

# 生成密码哈希 (利用 uhttpd -m)
PASSWORD_HASH=$(uhttpd -m "$PASSWORD")
uci set rpcd.homepage.password="$PASSWORD_HASH"

# 关联刚才创建的 ACL 组
uci add_list rpcd.homepage.read='homepage'

# 提交更改
uci commit rpcd

# 4. 重启服务
echo " -> 正在重启 rpcd 服务..."
/etc/init.d/rpcd restart

# 5. 自我验证
echo "----------------------------------------"
echo " -> 正在验证配置..."
sleep 2

# 尝试在本地登录
LOGIN_TEST=$(ubus call session login "{\"username\":\"homepage\",\"password\":\"$PASSWORD\"}" 2>/dev/null)

# 检查结果是否包含 session
if echo "$LOGIN_TEST" | grep -q "ubus_rpc_session"; then
    echo "✅ 配置成功！"
    echo "----------------------------------------"
    echo "请在 Homepage 的 services.yaml 中填写:"
    echo "username: homepage"
    echo "password: \"$PASSWORD\"  <-- 记得加双引号!"
    echo "----------------------------------------"
else
    echo "❌ 配置可能失败，请检查日志。"
    echo "测试返回: $LOGIN_TEST"
fi
