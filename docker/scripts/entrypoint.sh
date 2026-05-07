#!/bin/sh
# SmartDNS 入口脚本
# 功能: 模板生成 + 初始规则下载 + AI 同步 + crond 定时维护 + 前台运行
# ==========================================
set -e

WORKDIR="/opt/smartdns"
SMARTFILE_TPL="/etc/smartdns/Smartfile"
SMARTFILE_OUT="/etc/smartdns/smartdns.conf"

log() { echo "[entrypoint] $*"; }

# ---- 1. 容器内部 DNS ----
CONTAINER_DNS="${CONTAINER_DNS:-8.8.8.8}"
echo "nameserver $CONTAINER_DNS" > /etc/resolv.conf
log "container DNS set to $CONTAINER_DNS"

# ---- 2. 从环境变量生成 smartdns.conf ----
# DNS 上游（逗号分隔 IP:PORT）
DNS_CN="${DNS_CN:-119.29.29.29,223.5.5.5,114.114.114.114,202.96.128.86}"
DNS_GLOBAL="${DNS_GLOBAL:-1.1.1.1,8.8.8.8,9.9.9.9}"
DNS_AI="${DNS_AI:-1.0.0.1,8.8.4.4}"

# CSV → server 行（带 group 和排除属性）
dns_to_servers() {
  group="$1" exclude_default="$2" csv="$3"
  echo "$csv" | tr ',' '\n' | while read -r addr; do
    addr=$(echo "$addr" | xargs)
    [ -n "$addr" ] && echo "server $addr -group $group${exclude_default:+ -exclude-default-group}"
  done
}

CN_YAML=$(dns_to_servers cn true "$DNS_CN")
GL_YAML=$(dns_to_servers global false "$DNS_GLOBAL")
AI_YAML=$(dns_to_servers ai true "$DNS_AI")

# ECS: 留空则不启用
ECS_LINE=""
ECS_PRESET="${ECS_PRESET:-}"
if [ -n "$ECS_PRESET" ]; then
  ECS_LINE="edns-client-subnet $ECS_PRESET"
fi

if [ -f "$SMARTFILE_TPL" ]; then
  awk -v cn="$CN_YAML" -v gl="$GL_YAML" -v ai="$AI_YAML" -v ecs="$ECS_LINE" \
    '/__UPSTREAMS_CN__/{print cn;next}
     /__UPSTREAMS_GLOBAL__/{print gl;next}
     /__UPSTREAMS_AI__/{print ai;next}
     /__ECS_LINE__/{print ecs;next}
     {print}' "$SMARTFILE_TPL" > "$SMARTFILE_OUT"
  if [ -n "$ECS_PRESET" ]; then
    log "config generated: CN=$DNS_CN GLOBAL=$DNS_GLOBAL AI=$DNS_AI ECS=$ECS_PRESET"
  else
    log "config generated: CN=$DNS_CN GLOBAL=$DNS_GLOBAL AI=$DNS_AI ECS=disabled"
  fi
else
  log "ERROR: Smartfile template not found at $SMARTFILE_TPL"
  exit 1
fi

# ---- 3. 初始规则下载 ----
log "running initial rule update..."
$WORKDIR/update.sh
log "initial rule update done"

# ---- 4. crond 定时任务 ----
{
  echo "30 4 * * * $WORKDIR/update.sh >/dev/null 2>&1"
  echo "*/2 * * * * $WORKDIR/sync-ai.sh >/dev/null 2>&1"
} | crontab -
crond -b -l 2
log "crond started (update@04:30, sync-ai@*/2)"

# ---- 5. 启动时执行一次 AI 同步 ----
log "running initial AI sync..."
$WORKDIR/sync-ai.sh
log "initial AI sync done"

# ---- 6. 前台启动 SmartDNS ----
log "starting smartdns..."
exec smartdns -f -c "$SMARTFILE_OUT"
