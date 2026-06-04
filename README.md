# Auto Printer Server

将老旧 USB 打印机变成支持 AirPrint 的网络打印机，照片打印自动页面居中。

## 支持的操作系统与架构

本项目专为 **Ubuntu 22.04 Jammy** 系统构建，支持以下架构：

| 架构 | 离线包目录 | 状态 |
|------|-----------|------|
| ARM64 (aarch64) | `packages/arm64/` | ✅ 已验证（N1 盒子） |
| AMD64 (x86_64) | `packages/amd64/` | ✅ 已验证 |

### ⚠️ 安装前必读

> **重要警告**：
> 1. 离线包目录下共 **91 个 `.deb` 包**，从 **Ubuntu 22.04 Jammy** 系统下载，仅适用于相同系统版本
> 2. `install.sh` 会自动检测系统架构，选择对应的 `packages/arm64/` 或 `packages/amd64/` 目录安装
> 3. 如果系统不匹配或在线安装模式，脚本会回退到 `apt-get` 在线安装（无需离线包）

## 文件结构

```
auto-print/
├── install.sh                   # 一键安装（自动检测架构）
├── README.md
├── packages/
│   ├── arm64/                   # ARM64 离线 .deb 包
│   └── amd64/                   # AMD64 离线 .deb 包
└── scripts/
    ├── center-filter.py         # PDF 居中过滤器
    ├── imagetoraster-wrapper.py # AirPrint 照片居中包装器
    └── printer-auto-detect.sh   # 打印机自动检测
```

## 安装

在目标机器上执行：

```bash
chmod +x install.sh && ./install.sh
```

安装脚本会自动：
1. 检测系统架构（arm64 / amd64）
2. 选择对应的离线包目录安装，无需网络
3. 如果离线包不匹配，自动回退到 `apt-get` 在线安装

### 添加打印机

连接 USB 打印机后，脚本会自动检测并添加。也可手动：

```bash
lpadmin -p Brother_MFC7360 -E -v usb://Brother/MFC-7360 -m everywhere
cupsctl --share-printers --remote-any
systemctl restart cups
```

## 工作原理

### 为什么需要拦截 imagetoraster？

iPhone 通过 AirPrint 打印照片时，发送的是 **JPEG 图片**（不是 PDF）。
CUPS 直接使用 `imagetoraster` 将 JPEG 转为光栅，跳过 `pdftopdf` 和 `gstoraster`，
导致我们无法在 PDF 层面做居中处理。

**解决方案**：用 Python 包装器替换 `imagetoraster`：
1. 拦截 JPEG 输入
2. `imagetopdf` → 转为 PDF
3. `center-filter.py` → 检测是否照片（文本 < 30 字符）
4. 如果是照片 → 居中并缩放到页面 92%
5. `gstoraster` → 转为 CUPS 光栅输出

### 居中原理

直接修改 PDF 内容流（content stream），在每页内容前插入 PDF 标准变换矩阵：

```
q
scale 0 0 scale offset_x offset_y cm
[原始内容]
Q
```

任何 PDF 处理器（包括 `gstoraster`）都无法忽略这些操作符，确保打印和预览一致。

### 注意事项

- 安装脚本会自动修复 Windows 导致的 BOM/CRLF 问题
- USB 线松动会导致打印机无响应，重新插拔即可
- 仅对照片生效（文本 < 30 字符），文档打印不受影响
- 首次使用前建议先打印测试页确认打印机正常工作
