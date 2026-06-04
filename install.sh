#!/bin/bash
# ============================================================
# Auto Printer Server - Install Script
# 将老旧 USB 打印机变成支持 AirPrint 的网络打印机
# 支持 arm64 / amd64 离线安装，自动回退在线安装
# ============================================================

# 关闭 set -e，改用手动错误处理
set -u

# ---------- 颜色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
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

# ============================================================
# 第一步：安装依赖包
# ============================================================
INSTALL_MODE=""
PKG_DIR="$SCRIPT_DIR/packages/$PKG_ARCH"
PKG_COUNT=0

[ -n "$PKG_ARCH" ] && [ -d "$PKG_DIR" ] && PKG_COUNT=$(ls "$PKG_DIR"/*.deb 2>/dev/null | wc -l)

if [ "$PKG_COUNT" -gt 0 ]; then
    INSTALL_MODE="离线安装"
    echo ""
    info "找到 ${PKG_COUNT} 个离线包（架构: $PKG_ARCH）"
    dpkg -i --no-debsig "$PKG_DIR"/*.deb || true
    apt --fix-broken install --no-download -y 2>&1 | tail -2 || true
    ok "依赖安装完成"
else
    INSTALL_MODE="在线安装"
    echo ""
    [ -n "$PKG_ARCH" ] && warn "架构 ${PKG_ARCH} 的离线包目录未找到或为空" || warn "不支持的架构: ${ARCH}"
    info "通过 apt-get 在线安装..."
    apt-get update -qq || true
    apt-get install -y cups cups-filters avahi-daemon poppler-utils ghostscript printer-driver-brlaser python3 || {
        fail "在线安装失败，请检查网络连接和软件源"
        exit 1
    }
    ok "在线安装完成"
fi

# ============================================================
# 第二步：部署 filter 脚本（居中处理）
# ============================================================
echo ""
info "部署居中过滤器..."

# center-filter.py
cp "$SCRIPT_DIR/scripts/center-filter.py" /usr/local/bin/center-filter.py
chmod +x /usr/local/bin/center-filter.py
ok "center-filter.py"

# imagetoraster wrapper
if [ -f /usr/lib/cups/filter/imagetoraster ] && [ ! -f /usr/lib/cups/filter/imagetoraster.orig ]; then
    cp /usr/lib/cups/filter/imagetoraster /usr/lib/cups/filter/imagetoraster.orig
    ok "已备份原始 imagetoraster"
fi
cp "$SCRIPT_DIR/scripts/imagetoraster-wrapper.py" /usr/lib/cups/filter/imagetoraster
chmod +x /usr/lib/cups/filter/imagetoraster
ok "imagetoraster wrapper"

# gstoraster backup
if [ -f /usr/lib/cups/filter/gstoraster ] && [ ! -f /usr/lib/cups/filter/gstoraster.orig ]; then
    cp /usr/lib/cups/filter/gstoraster /usr/lib/cups/filter/gstoraster.orig
    ok "已备份原始 gstoraster"
fi

# ============================================================
# 第三步：部署打印机自动检测服务
# ============================================================
echo ""
info "部署打印机自动检测服务..."

# 复制脚本
cp "$SCRIPT_DIR/scripts/printer-auto-detect.sh" /usr/local/bin/printer-auto-detect.sh
chmod +x /usr/local/bin/printer-auto-detect.sh
ok "printer-auto-detect.sh"

# 创建 udev 规则：插入 USB 打印机时自动触发
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-printer-auto-detect.rules << 'UDEVRULES'
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS_FROM_DATABASE}=="printer", RUN+="/usr/local/bin/printer-auto-detect.sh"
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_CLASS_FROM_DATABASE}=="Printer", RUN+="/usr/local/bin/printer-auto-detect.sh"
UDEVRULES
udevadm control --reload-rules 2>/dev/null || true
ok "udev 规则（USB 热插拔自动检测）"

# systemd path unit：开机后自动检测
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/printer-auto-detect.path << 'SYSTEMDPATH'
[Unit]
Description=Monitor printer device files
[Path]
PathExists=/dev/usb/lp0
PathExists=/dev/lp0
[Install]
WantedBy=multi-user.target
SYSTEMDPATH

cat > /etc/systemd/system/printer-auto-detect.service << 'SYSTEMDSVC'
[Unit]
Description=Auto detect and configure USB printer
After=cups.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/printer-auto-detect.sh
[Install]
WantedBy=multi-user.target
SYSTEMDSVC
systemctl daemon-reload 2>/dev/null || true
systemctl enable printer-auto-detect.path 2>/dev/null || true
ok "systemd 路径检测（开机自动检测）"

# ============================================================
# 第四步：配置 CUPS（远程访问 + 共享 + AirPrint）
# ============================================================
echo ""
info "配置 CUPS..."

# 开启远程访问和打印机共享
cupsctl --remote-any --share-printers 2>/dev/null && ok "CUPS 已配置远程访问和共享" || warn "cupsctl 执行失败"

# 确保 cupsd.conf 允许远程访问（兜底）
CUPSD_CONF="/etc/cups/cupsd.conf"
if [ -f "$CUPSD_CONF" ]; then
    # 确保 Listen 包含 0.0.0.0:631
    if grep -q "^Listen localhost:631" "$CUPSD_CONF" 2>/dev/null; then
        sed -i 's/^Listen localhost:631/Listen 0.0.0.0:631/' "$CUPSD_CONF"
        ok "cupsd.conf: 监听所有网卡"
    fi
    # 确保 Allow 包含 @LOCAL
    if grep -q "Allow @LOCAL" "$CUPSD_CONF" 2>/dev/null; then
        : # 已存在
    else
        # 在适当位置插入 Allow @LOCAL
        sed -i '/<Location \/>/,/<\/Location>/s/Allow \/Allow \@LOCAL\n  Allow \//' "$CUPSD_CONF" 2>/dev/null || true
    fi
fi

# ============================================================
# 第五步：修复 BOM/CRLF
# ============================================================
echo ""
info "修复 Windows 换行符..."
for f in /usr/local/bin/center-filter.py /usr/lib/cups/filter/imagetoraster /usr/local/bin/printer-auto-detect.sh; do
    sed -i '1s/^\xef\xbb\xbf//' "$f" 2>/dev/null || true
    sed -i 's/\r$//' "$f" 2>/dev/null || true
done

# ============================================================
# 第六步：校验关键文件
# ============================================================
echo ""
info "校验关键文件..."
ANY_MISSING=false
for f in /usr/local/bin/center-filter.py /usr/lib/cups/filter/imagetoraster /usr/local/bin/printer-auto-detect.sh; do
    if [ -f "$f" ] && [ -x "$f" ]; then
        ok "$f"
    else
        fail "$f 不存在或不可执行"
        ANY_MISSING=true
    fi
done

# ============================================================
# 第七步：启动服务
# ============================================================
echo ""
info "启动服务..."
if command -v systemctl &>/dev/null; then
    systemctl daemon-reload 2>/dev/null
    systemctl enable avahi-daemon cups 2>/dev/null
    systemctl restart avahi-daemon cups 2>/dev/null
    sleep 2

    for svc in avahi-daemon cups; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc 运行中"
        else
            warn "$svc 未运行（可手动启动: systemctl start $svc）"
        fi
    done
else
    warn "未检测到 systemd，请手动启动服务"
fi

# 触发一次打印机自动检测
/usr/local/bin/printer-auto-detect.sh 2>/dev/null || true

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}   安装完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  安装模式: ${INSTALL_MODE}"
echo "  系统架构: ${ARCH}"
echo ""
echo "  后续操作："
echo "    1. 插入 USB 打印机 → 自动检测配置"
echo "    2. 同一局域网下 iPhone/Mac 可直接 AirPrint 打印"
echo "    3. 管理界面：http://armbian.local:631"
echo "    4. 手动添加：lpadmin -p 打印机名 -E -v usb://... -m everywhere"
echo ""
echo "  恢复默认："
echo "    systemctl stop cups avahi-daemon"
echo "    mv /usr/lib/cups/filter/imagetoraster{.orig,} 2>/dev/null"
echo "    mv /usr/lib/cups/filter/gstoraster{.orig,} 2>/dev/null"
echo "    rm -f /etc/udev/rules.d/99-printer-auto-detect.rules"
echo "    rm -f /etc/systemd/system/printer-auto-detect.*"
echo "    apt-get remove --purge -y cups avahi-daemon 2>/dev/null"
echo ""
