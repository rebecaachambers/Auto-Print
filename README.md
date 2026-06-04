# Auto Printer Server

将老旧 USB 打印机变成支持 AirPrint 的网络打印机，照片打印自动页面居中。

## 架构

```
iPhone ──AirPrint──> CUPS (Armbian N1) ──USB──> 打印机
                          │
               [imagetoraster wrapper]
                   JPEG → PDF → 居中 → 光栅
```

## 支持的操作系统

本项目专为 **Armbian (Ubuntu 22.04 Jammy, aarch64/arm64)** 系统构建。

| 系统 | 架构 | 状态 |
|------|------|------|
| Armbian (Ubuntu 22.04) | arm64 (aarch64) | ✅ 已验证 |
| Armbian (Debian 系) | arm64 | ⚠️ 可能兼容，需自行测试 |
| 其他 ARM64 Linux 发行版 | arm64 | ❌ 不保证兼容 |
| x86_64 系统 | amd64 | ❌ 不兼容 |

### ⚠️ 安装前必读

> **重要警告**：
> 1. `packages/` 目录下的 212 个离线 `.deb` 包是从 **Armbian (Ubuntu 22.04, aarch64)** 系统下载的，仅适用于相同系统版本
> 2. 在安装前，请确认你的系统与上述表格匹配
> 3. 如果系统不匹配，请不要使用离线安装，改用在线安装（脚本会自动检测 `packages/` 目录是否存在）
> 4. 在线安装不依赖 `packages/` 目录，脚本会通过 `apt-get` 自动适配当前系统版本

## 文件结构

```
auto-print/
├── install.sh                   # 一键安装（离线/在线双模式）
├── README.md
├── packages/                    # 离线 .deb 依赖包（Armbian Ubuntu 22.04 arm64）
└── scripts/
    ├── center-filter.py         # PDF 居中过滤器
    ├── imagetoraster-wrapper.py # AirPrint 照片居中包装器
    └── printer-auto-detect.sh   # 打印机自动检测
```

## 安装

在 N1（Armbian）上执行：

```bash
chmod +x install.sh && ./install.sh
```

安装脚本会自动检测：
- 如果 `packages/` 目录存在 → 使用本地离线包安装（**需系统版本匹配**）
- 如果 `packages/` 目录不存在 → 自动通过 `apt-get` 在线安装（推荐用于非标准系统）

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
