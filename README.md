# Auto Printer Server

将老旧 USB 打印机变成支持 AirPrint 的网络打印机，照片打印自动页面居中。

支持 Docker 一键部署，也可在 Armbian / Ubuntu 上直接安装。

## 快速开始

### 方式一：Docker（推荐）

```bash
# 克隆项目
git clone https://github.com/rebecaachambers/Auto-Print.git
cd Auto-Print

# 构建镜像（自动匹配 arm64 / amd64）
docker compose build

# 启动
docker compose up -d
```

或者直接拉取预构建镜像（后续提供）：

```bash
docker run -d \
  --network host \
  --privileged \
  --name auto-print \
  rebecaachambers/auto-print:latest
```

### 方式二：直接在系统上安装

```bash
chmod +x install.sh && ./install.sh
```

脚本会自动完成：
- 检测系统架构（arm64 / amd64），从 `packages/` 离线安装依赖
- 部署居中过滤器
- 部署打印机自动检测服务
- 配置 CUPS 远程访问 + AirPrint
- 启动 avahi-daemon（mDNS 广播）

## 支持的系统

| 系统 | 架构 | 安装方式 |
|------|------|----------|
| 任何系统 | arm64 / amd64 | Docker |
| Ubuntu 22.04 Jammy | arm64 | install.sh（已验证 N1） |
| Ubuntu 22.04 Jammy | amd64 | install.sh（已验证） |
| 其他 Debian 系 | arm64 / amd64 | install.sh 在线安装 |

## 文件结构

```
auto-print/
├── Dockerfile                   # 多架构 Docker 镜像
├── docker-compose.yml           # Docker Compose 配置
├── entrypoint.sh                # Docker 容器启动脚本
├── install.sh                   # 物理机一键安装
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

插入 USB 打印机即可自动检测配置。也可手动：

```bash
# 查看 USB 打印机 URI
lpinfo -v | grep usb

# 手动添加
lpadmin -p 打印机名 -E -v usb://厂商/型号 -m everywhere
```

### AirPrint 打印

同一局域网下，iPhone / iPad / Mac 可直接在打印列表中看到打印机。

管理界面：`http://主机名:631`（Docker 模式）或 `http://armbian.local:631`（物理机模式）

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

任何 PDF 处理器都无法忽略这些操作符，确保打印和预览一致。

### 打印机自动检测

- **物理机**：udev 热插拔 + systemd 开机检测
- **Docker**：轮询 `/dev/usb/lp*` 监听打印机插拔

## 注意事项

- USB 线松动会导致打印机无响应，重新插拔即可
- 仅对照片生效（文本 < 30 字符），文档打印不受影响
- Docker 需要 `--network host` 和 `--privileged` 权限
- 外网访问需自行配置穿透（Cloudflare Tunnel、frp 等）
