FROM ubuntu:22.04

LABEL description="Auto Printer Server - AirPrint with photo centering"
LABEL maintainer="rebecaachambers"

# 避免 apt 交互
ENV DEBIAN_FRONTEND=noninteractive

# 复制对应架构的离线包（Buildx 自动设置 TARGETARCH）
COPY packages/${TARGETARCH}/ /tmp/packages/

# 安装依赖
RUN dpkg -i --no-debsig /tmp/packages/*.deb 2>/dev/null || true && \
    apt --fix-broken install --no-download -y 2>/dev/null || true && \
    rm -rf /tmp/packages && \
    # 清理 apt 缓存
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 复制脚本
COPY scripts/center-filter.py /usr/local/bin/center-filter.py
COPY scripts/imagetoraster-wrapper.py /usr/lib/cups/filter/imagetoraster
COPY scripts/printer-auto-detect.sh /usr/local/bin/printer-auto-detect.sh

# 设置权限
RUN chmod +x /usr/local/bin/center-filter.py && \
    chmod +x /usr/lib/cups/filter/imagetoraster && \
    chmod +x /usr/local/bin/printer-auto-detect.sh && \
    # 备份原始 filter
    [ -f /usr/lib/cups/filter/imagetoraster.orig ] || true && \
    [ -f /usr/lib/cups/filter/gstoraster.orig ] || true

# 配置 CUPS 远程访问
RUN cupsctl --remote-any --share-printers 2>/dev/null || true && \
    sed -i 's/^Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf 2>/dev/null || true

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 631 5353
ENTRYPOINT ["/entrypoint.sh"]
