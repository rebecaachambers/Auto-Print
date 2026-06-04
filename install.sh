#!/bin/bash
# ============================================================
# Auto Printer Server - Install Script
# 将老旧 USB 打印机变成支持 AirPrint 的网络打印机
# 支持 arm64 / amd64 离线安装，自动回退在线安装
# ============================================================

set -e

# ---------- 颜色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m' # No Color
ok()  { echo -e "  ${GREEN}✓${NC} $1"; }
info(){ echo -e "  ${CYAN}→${NC} $1"; }
warn(){ echo -e "  ${YELLOW}⚠${NC} $1"; }
fail(){ echo -e "  ${RED}✗${NC} $1"; }

# ---------- Root 检查 ----------
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\n${RED}错误：需要 root 权限${NC}"
    echo "请使用 sudo 或以 root 用户运行：sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}   Auto Printer Server 安装程序${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}\n"

# ---------- 系统检测 ----------
info "检测系统信息..."
OS=""
[ -f /etc/os-release ] && . /etc/os-release && OS="$PRETTY_NAME"
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
echo "    系统: ${OS:-未知}"
echo "    架构: $ARCH"

# 架构 → 包目录映射
case "$ARCH" in
    aarch64|arm64)    PKG_ARCH="arm64" ;;
    x86_64|amd64)     PKG_ARCH="amd64" ;;
    *)                PKG_ARCH="" ;;
esac

# ---------- 磁盘空间检查 ----------
MIN_SPACE_MB=200
AVAIL_MB=$(df / --output=avail 2>/dev/null | tail -1)
if [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -lt "$MIN_SPACE_MB" ]; then
    warn "磁盘剩余空间不足 ${MIN_SPACE_MB}MB（当前: ${AVAIL_MB}MB），安装后可能需要扩展"
fi

# ---------- 安装依赖 ----------
INSTALL_MODE=""
PKG_DIR="$SCRIPT_DIR/packages/$PKG_ARCH"

if [ -n "$PKG_ARCH" ] && [ -d "$PKG_DIR" ]; then
    PKG_COUNT=$(ls "$PKG_DIR"/*.deb 2>/dev/null | wc -l)
fi

if [ -n "$PKG_COUNT" ] && [ "$PKG_COUNT" -gt 0 ]; then
    INSTALL_MODE="offline"
    echo ""
    info "找到 ${PKG_COUNT} 个离线包（架构: $PKG_ARCH）"
    echo -e "${YELLOW}  即将安装依赖包，请稍候...${NC}"

    DPKG_FAIL=0
    dpkg -i --no-debsig "$PKG_DIR"/*.deb 2>&1 | tail -3 || DPKG_FAIL=1

    if [ "$DPKG_FAIL" -ne 0 ]; then
        warn "部分包安装有依赖问题，尝试自动修复..."
        apt --fix-broken install --no-download -y 2>&1 | tail -3 || true
    fi

    # 验证安装结果
    INSTALLED=$(dpkg -l 2>/dev/null | grep "^ii" | wc -l)
    ok "依赖安装完成（系统中已安装 ${INSTALLED} 个软件包）"
else
    INSTALL_MODE="online"
    echo ""
    if [ -n "$PKG_ARCH" ]; then
        warn "架构 ${PKG_ARCH} 的离线包目录未找到或为空"
    else
        warn "不支持的架构: ${ARCH}"
    fi
    info "切换到在线安装模式..."
    apt-get update -qq && apt-get install -y cups cups-filters avahi-daemon \
        poppler-utils ghostscript printer-driver-brlaser python3 || {
        fail "在线安装失败，请检查网络连接"
        exit 1
    }
    ok "在线安装完成"
fi

# ---------- 部署脚本 ----------
echo ""
info "部署居中过滤器..."

# center-filter.py
cp "$SCRIPT_DIR/scripts/center-filter.py" /usr/local/bin/center-filter.py
chmod +x /usr/local/bin/center-filter.py
ok "center-filter.py → /usr/local/bin/"

# imagetoraster wrapper
if [ -f /usr/lib/cups/filter/imagetoraster ]; then
    if [ ! -f /usr/lib/cups/filter/imagetoraster.orig ]; then
        cp /usr/lib/cups/filter/imagetoraster /usr/lib/cups/filter/imagetoraster.orig
        ok "已备份原始 imagetoraster"
    else
        info "原始 imagetoraster 已备份，跳过"
    fi
fi
cp "$SCRIPT_DIR/scripts/imagetoraster-wrapper.py" /usr/lib/cups/filter/imagetoraster
chmod +x /usr/lib/cups/filter/imagetoraster
ok "imagetoraster wrapper 部署完成"

# gstoraster backup
if [ -f /usr/lib/cups/filter/gstoraster ] && [ ! -f /usr/lib/cups/filter/gstoraster.orig ]; then
    cp /usr/lib/cups/filter/gstoraster /usr/lib/cups/filter/gstoraster.orig
    ok "已备份原始 gstoraster"
fi

# ---------- 修复 BOM/CRLF ----------
echo ""
info "修复 Windows 换行符..."
for f in /usr/local/bin/center-filter.py /usr/lib/cups/filter/imagetoraster; do
    sed -i '1s/^\xef\xbb\xbf//' "$f" 2>/dev/null || true
    sed -i 's/\r$//' "$f" 2>/dev/null || true
done

# ---------- 校验关键文件 ----------
echo ""
info "校验关键文件..."
ALL_OK=true
for f in /usr/local/bin/center-filter.py /usr/lib/cups/filter/imagetoraster; do
    if [ -f "$f" ] && [ -x "$f" ]; then
        ok "$f"
    else
        fail "$f 不存在或不可执行"
        ALL_OK=false
    fi
done

# ---------- 启动服务 ----------
echo ""
info "配置并启动服务..."
if command -v systemctl &>/dev/null; then
    systemctl enable avahi-daemon cups 2>/dev/null && ok "avahi-daemon, cups 已设置开机自启"
    systemctl restart avahi-daemon cups 2>/dev/null && ok "avahi-daemon, cups 已重启"
    sleep 2

    # 验证服务状态
    for svc in avahi-daemon cups; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc 运行中"
        else
            warn "$svc 未运行（可稍后手动启动: systemctl start $svc）"
        fi
    done
else
    warn "未检测到 systemd，请手动启动 avahi-daemon 和 cups 服务"
fi

# ---------- 完成 ----------
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}   安装完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  安装模式: ${INSTALL_MODE}"
echo "  系统架构: ${ARCH}"
echo ""
echo "  下一步操作："
echo "    1. 连接 USB 打印机"
echo "    2. 打印机自动检测，或手动添加："
echo "       lpadmin -p 打印机名 -E -v usb://... -m everywhere"
echo "    3. 开启共享：cupsctl --share-printers --remote-any"
echo "    4. 管理界面：http://armbian.local:631"
echo "    5. 用 iPhone 打印照片测试居中效果"
echo ""
echo "  恢复原始状态："
echo "    systemctl stop cups avahi-daemon"
echo "    mv /usr/lib/cups/filter/imagetoraster.orig /usr/lib/cups/filter/imagetoraster 2>/dev/null"
echo "    mv /usr/lib/cups/filter/gstoraster.orig /usr/lib/cups/filter/gstoraster 2>/dev/null"
echo "    apt-get remove --purge -y cups avahi-daemon 2>/dev/null"
echo ""
