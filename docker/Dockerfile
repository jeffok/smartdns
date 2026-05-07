# Stage 1: 提取 SmartDNS 静态二进制
FROM pymumu/smartdns:latest AS smartdns

# Stage 2: Alpine 运行环境
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

# 复制 SmartDNS 静态二进制（静态编译，musl 兼容）
COPY --from=smartdns /usr/sbin/smartdns /usr/sbin/smartdns

# 复制运行时脚本
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh

ENTRYPOINT ["/entrypoint.sh"]
