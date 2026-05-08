# Stage 1: 从官方镜像提取 SmartDNS 二进制（多架构支持 amd64 + arm64）
FROM pymumu/smartdns:latest AS smartdns

# Stage 2: Alpine 运行环境
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

# 复制 SmartDNS 完整安装（二进制 + run-smartdns 脚本 + 自带 glibc/ssl 库）
COPY --from=smartdns /usr/local/lib/smartdns/ /usr/local/lib/smartdns/
COPY --from=smartdns /usr/sbin/smartdns /usr/sbin/smartdns

# 复制运行时脚本
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh
COPY scripts/healthcheck.sh /opt/smartdns/healthcheck.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh /opt/smartdns/healthcheck.sh

# 通用健康检查：所有 Docker 部署方式均生效（compose / docker run / swarm / k8s）
# 覆盖 compose.yaml 中的 healthcheck 即可自定义
HEALTHCHECK --start-period=30s --interval=30s --timeout=5s --retries=3 \
    CMD ["/opt/smartdns/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
