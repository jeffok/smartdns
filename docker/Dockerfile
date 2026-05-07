# Stage 1: 构建工具层（Debian 含 curl/bash/procps/dnsutils）
FROM debian:stable-slim AS tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates bash procps dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: SmartDNS 运行层（distroless + 工具 + 脚本）
FROM pymumu/smartdns:latest

# 复制工具及依赖库（glibc 兼容，无冲突）
COPY --from=tools / /

# 复制运行时脚本
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh

ENTRYPOINT ["/entrypoint.sh"]
