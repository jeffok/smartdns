# ==========================================
# Stage 1: 从源码编译 SmartDNS（含 Web UI）
# 使用 Ubuntu 22.04（GCC 11，无 memcmp bug）
# ==========================================
FROM ubuntu:22.04 AS builder

ARG SMARTDNS_VER=Release47

# 构建基础依赖（含 Node.js / Rust / OpenSSL）
RUN apt-get update && apt-get install -y \
    curl make gcc clang wget unzip ca-certificates binutils perl \
    pkg-config libssl-dev cmake golang-go \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20.x（Web UI 前端）
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# 下载 SmartDNS 源码
WORKDIR /build
RUN curl -sSL "https://github.com/pymumu/smartdns/archive/refs/tags/${SMARTDNS_VER}.tar.gz" \
    | tar -zxv --strip-components=1

# 编译（静态链接 + Web UI，使用 clang 回避 GCC aws-lc-sys bug）
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
    cp -a smartdns/usr /release/

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
