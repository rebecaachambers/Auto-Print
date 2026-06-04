# Auto Printer Server

将老旧 USB 打印机变成支持 AirPrint 的网络打印机，照片打印自动页面居中。

## 支持的系统

| 系统 | 架构 | 状态 |
|------|------|------|
| Ubuntu 22.04 Jammy | arm64 (aarch64) | ✅ 已验证（N1 盒子） |
| Ubuntu 22.04 Jammy | amd64 (x86_64) | ✅ 已测试 |
| 其他 Linux（Debian 系） | arm64 / amd64 | ⚠️ 尝试在线安装 |

### 安装前注意

> 离线包（`packages/`）来自 **Ubuntu 22.04 Jammy**，仅适用于相同系统版本。
> 系统不匹配时脚本会自动回退到 `apt-get` 在线安装。

## 快速开始

```bash
chmod +x install.sh && ./install.sh
```

脚本会自动完成：
- 检测系统架构（arm64 / amd64）
- 从 `packages/` 离线安装依赖，无需网络
- 部署居中过滤器（`imagetoraster` 包装器）
- 部署打印机自动检测服务（udev 热插拔 + systemd 开机检测）
- 配置 CUPS 远程访问 + 打印机共享（AirPrint 就绪）
- 启动 avahi-daemon（mDNS 广播，`armbian.local` 可访问）

## 文件结构

```
auto-print/
├── install.sh                   # 一键安装
├── packages/
│   ├── arm64/                   # ARM64 离线包（91 个）
│   └── amd64/                   # AMD64 离线包（91 个）
└── scripts/
    ├── center-filter.py         # PDF 居中过滤器
    ├── imagetoraster-wrapper.py # AirPrint 照片居中包装器
    └── printer-auto-detect.sh   # 打印机自动检测
```

## 使用方法

### 连接打印机

插入 USB 打印机，系统会自动检测并配置。也可手动添加：

```bash
# 查看 USB 打印机 URI
lpinfo -v | grep usb

# 手动添加
lpadmin -p 打印机名 -E -v usb://厂商/型号 -m everywhere

# 开启共享
cupsctl --share-printers --remote-any
```

### AirPrint 打印

同一局域网下，iPhone / iPad / Mac 可直接在打印列表中看到打印机，选择即可打印。

管理界面：`http://armbian.local:631` 或 `http://IP地址:631`

## 工作原理

### 为什么需要拦截 imagetoraster？

iPhone 通过 AirPrint 打印照片时，发送的是 **JPEG 图片**（不是 PDF）。
CUPS 直接使用 `imagetoraster` 将 JPEG 转为光栅，跳过 `pdftopdf` 和 `gstoraster`，
导致无法在 PDF 层面做居中处理。

**解决方案**：用 Python 包装器替换 `imagetoraster`：

1. 拦截 JPEG 输入 → `imagetopdf` 转为 PDF
2. `center-filter.py` 检测是否照片（文本 < 30 字符）
3. 如果是照片 → 修改 PDF 内容流，居中并缩放到页面 92%
4. `gstoraster` 转为 CUPS 光栅输出

### 居中原理

直接修改 PDF 内容流（content stream），在每页内容前插入 PDF 标准变换矩阵：

```
q
scale 0 0 scale offset_x offset_y cm
[原始内容]
Q
```

任何 PDF 处理器（包括 `gstoraster`）都无法忽略这些操作符，确保打印和预览一致。

### 打印机自动检测

- **udev 规则**：插入 USB 打印机时自动触发检测脚本
- **systemd path 监控**：开机后自动扫描 USB 打印机
- **驱动匹配**：按型号 → 品牌+型号 → 品牌 → VID/PID → IPP Everywhere → Raw 依次降级尝试

## 注意事项

- 安装脚本会自动修复 Windows 导致的 BOM/CRLF 问题
- USB 线松动会导致打印机无响应，重新插拔即可
- 仅对照片生效（文本 < 30 字符），文档打印不受影响
- 如外网访问需自行配置穿透（Cloudflare Tunnel、frp 等）

## 恢复默认

```bash
systemctl stop cups avahi-daemon
mv /usr/lib/cups/filter/imagetoraster{.orig,} 2>/dev/null
mv /usr/lib/cups/filter/gstoraster{.orig,} 2>/dev/null
rm -f /etc/udev/rules.d/99-printer-auto-detect.rules
rm -f /etc/systemd/system/printer-auto-detect.*
apt-get remove --purge -y cups avahi-daemon 2>/dev/null
```
