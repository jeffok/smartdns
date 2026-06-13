# Author: Jeff
# Date: 2025-06-01
# Description: SmartDNS 多阶段构建，从官方镜像提取二进制 + Alpine 运行环境，支持 amd64/arm64
# Copyright © 2022 by Jeff, All Rights Reserved.
# ==========================================

# Stage 1: 从官方镜像提取 SmartDNS（含 Web UI 插件）
FROM pymumu/smartdns:latest AS smartdns

# Stage 2: Alpine 运行环境
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

# 复制 SmartDNS 完整安装树
COPY --from=smartdns /usr/local/lib/smartdns/ /usr/local/lib/smartdns/
RUN ln -s /usr/local/lib/smartdns/run-smartdns /usr/sbin/smartdns

COPY docker/scripts/entrypoint.sh /entrypoint.sh
COPY docker/scripts/update.sh /opt/smartdns/update.sh
COPY docker/scripts/sync-ai.sh /opt/smartdns/sync-ai.sh
COPY docker/scripts/healthcheck.sh /opt/smartdns/healthcheck.sh

# 内置默认配置（挂载卷为空时自动复制）
COPY data/rules/Smartfile /opt/smartdns/default/Smartfile
COPY data/rules/custom-hosts.txt /opt/smartdns/default/custom-hosts.txt
COPY data/rules/custom-local.txt /opt/smartdns/default/custom-local.txt
COPY data/rules/ai-list.txt /opt/smartdns/default/ai-list.txt

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh /opt/smartdns/healthcheck.sh

HEALTHCHECK --start-period=30s --interval=30s --timeout=5s --retries=3 \
    CMD ["/opt/smartdns/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
