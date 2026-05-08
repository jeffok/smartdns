# ==========================================
# Stage 1: 从源码编译 SmartDNS（含 Web UI）
# ==========================================
FROM ubuntu:latest AS builder

ARG SMARTDNS_VER=Release47

# 构建基础依赖
RUN apt-get update && apt-get install -y \
    curl make gcc clang wget unzip ca-certificates binutils perl \
    pkg-config libssl-dev cmake golang-go \
    && rm -rf /var/lib/apt/lists/*

# Node.js（Web UI 前端）
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# 下载 SmartDNS 源码
WORKDIR /build
RUN curl -sSL "https://github.com/pymumu/smartdns/archive/refs/tags/${SMARTDNS_VER}.tar.gz" \
    | tar -zxv --strip-components=1

# 编译（静态链接 + Web UI，GCC 有 memcmp bug 需用 clang）
ENV PATH="/root/.cargo/bin:${PATH}" \
    CC=clang CXX=clang++
RUN sh package/build-pkg.sh \
    --platform linux \
    --arch $(dpkg --print-architecture) \
    --with-ui --static

# 提取编译产物到 /release
RUN mkdir -p /release/var/log /release/run /release/var/lib/smartdns && \
    cd package && \
    tar -xvf *.tar.gz && \
    cp -a smartdns/etc /release/ && \
    cp -a smartdns/usr /release/ && \
    rm -f /release/usr/local/smartdns/lib/libssl* 2>/dev/null || true && \
    rm -f /release/usr/local/smartdns/lib/libcrypto* 2>/dev/null || true

# ==========================================
# Stage 2: Alpine 运行环境
# ==========================================
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

# 复制 SmartDNS（含 Web UI）
COPY --from=builder /release/ /

# 复制脚本
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh
COPY scripts/healthcheck.sh /opt/smartdns/healthcheck.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh /opt/smartdns/healthcheck.sh

HEALTHCHECK --start-period=30s --interval=30s --timeout=5s --retries=3 \
    CMD ["/opt/smartdns/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
