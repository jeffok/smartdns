FROM pymumu/smartdns:latest

# 安装运行时依赖:
#   curl       - 下载规则文件
#   bash       - 脚本运行
#   procps     - pgrep/pkill（SIGHUP 信号重载）
#   dnsutils   - nslookup（AI 域名解析）
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bash procps dnsutils \
    && rm -rf /var/lib/apt/lists/*

# 复制所有运行时脚本
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh

ENTRYPOINT ["/entrypoint.sh"]
