# Auto Printer Server

将老旧 USB 打印机变成支持 AirPrint 的网络打印机，照片打印自动页面居中。

## Docker 部署（推荐）

### 前提条件

- 安装 Docker：https://docs.docker.com/engine/install/
- 安装 Docker Compose：https://docs.docker.com/compose/install/
- Linux 系统（arm64 或 amd64 均可）

### 一键启动

```bash
# 克隆项目
git clone https://github.com/rebecaachambers/Auto-Print.git
cd Auto-Print

# 构建并启动（自动匹配 arm64 / amd64）
docker compose build
docker compose up -d
```

### 直接启动（不用 compose）

```bash
docker run -d \
  --network host \
  --privileged \
  --name auto-print \
  -v /dev/usb:/dev/usb \
  -v /dev/bus/usb:/dev/bus/usb \
  -e TZ=Asia/Shanghai \
  -e CUPS_ADMIN_PASS=admin \
  --restart unless-stopped \
  auto-print-auto-print
```

> **注意**：`--network host` 和 `--privileged` 是必需的，mDNS（AirPrint 发现）需要 host 网络模式，USB 访问需要特权模式。

### 查看日志

```bash
docker compose logs -f
```

### 停止

```bash
docker compose down
```

## 物理机安装（Armbian / Ubuntu）

```bash
chmod +x install.sh && ./install.sh
```

脚本自动完成：
- 检测架构（arm64 / amd64），离线安装依赖
- 部署照片居中过滤器
- 部署打印机自动检测（udev 热插拔）
- 配置 CUPS 远程访问 + AirPrint
- 启动 avahi-daemon（mDNS 广播）

## 支持的系统

| 系统 | 架构 | 安装方式 |
|------|------|----------|
| 任何 Linux（有 Docker） | arm64 / amd64 | Docker |
| Ubuntu 22.04 Jammy | arm64 | install.sh |
| Ubuntu 22.04 Jammy | amd64 | install.sh |
| 其他 Debian 系 | arm64 / amd64 | install.sh（在线模式） |

## 项目结构

```
auto-print/
├── Dockerfile                   # 多架构 Docker 镜像
├── docker-compose.yml           # Docker Compose 配置
├── entrypoint.sh                # 容器启动脚本
├── install.sh                   # 物理机一键安装
├── packages/
│   ├── arm64/                   # ARM64 离线依赖（91 包）
│   └── amd64/                   # AMD64 离线依赖（91 包）
└── scripts/
    ├── center-filter.py         # PDF 照片居中
    ├── imagetoraster-wrapper.py # AirPrint JPEG 居中包装器
    └── printer-auto-detect.sh   # 打印机自动检测
```

## 使用方法

### 连接打印机

插入 USB 打印机，自动检测配置。手动添加：

```bash
# 查看 USB 打印机 URI
lpinfo -v | grep usb

# 添加打印机
lpadmin -p 打印机名 -E -v usb://厂商/型号 -m everywhere

# 设为默认
lpadmin -d 打印机名
```

### AirPrint 打印

同一局域网下 iPhone / iPad / Mac 自动发现打印机。

管理界面：
- Docker：`http://宿主机IP:631`
- 物理机：`http://armbian.local:631`

## 工作原理

### 为什么拦截 imagetoraster？

iPhone 通过 AirPrint 打印照片时发送的是 **JPEG**（不是 PDF）。CUPS 直接用 `imagetoraster` 转光栅，跳过 PDF 层，导致无法居中。

**解决方案**：用 Python 包装器替换 `imagetoraster`：

1. JPEG → `imagetopdf` → PDF
2. `center-filter.py` 检测是否照片（文本 < 30 字符）
3. 是 → PDF 内容流居中（缩放 92%）
4. `gstoraster` → CUPS 光栅输出

### 居中原理

直接修改 PDF 内容流矩阵：

```
q
scale 0 0 scale offset_x offset_y cm
[原始内容]
Q
```

### 打印机自动检测

- **物理机**：udev 热插拔 + systemd 开机检测
- **Docker**：轮询 `/dev/usb/lp*` 监听

## 注意事项

- USB 线松动会导致打印机无响应，重新插拔即可
- 仅对照片居中（文本 < 30 字符），文档不受影响
- Docker 需 `--network host` 和 `--privileged`
- 外网访问需自行配置穿透（Cloudflare Tunnel 等）
