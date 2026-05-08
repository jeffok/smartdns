# Stage 1: 从官方镜像提取 SmartDNS（含 Web UI 插件）
FROM pymumu/smartdns:latest AS smartdns

# Stage 2: Alpine 运行环境
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

# 复制 SmartDNS 完整安装树
COPY --from=smartdns /usr/local/lib/smartdns/ /usr/local/lib/smartdns/
RUN ln -s /usr/local/lib/smartdns/run-smartdns /usr/sbin/smartdns

COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh
COPY scripts/healthcheck.sh /opt/smartdns/healthcheck.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh /opt/smartdns/healthcheck.sh

HEALTHCHECK --start-period=30s --interval=30s --timeout=5s --retries=3 \
    CMD ["/opt/smartdns/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
