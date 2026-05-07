#!/bin/sh
# SmartDNS 规则更新脚本（运行于容器内部）
# 由 entrypoint.sh 在启动时和 crond 定时触发
# ==========================================
set -e

RULES_DIR="/etc/smartdns/rules"
CONFIG_FILE="/etc/smartdns/smartdns.conf"

log() { echo "[update] $(date '+%H:%M:%S') $*"; }

download() {
    name="$1" url="$2" out="$RULES_DIR/$name"
    tmp="${out}.tmp"

    for src in "$url" \
        "https://gh-proxy.com/$url" \
        "https://mirror.ghproxy.com/$url" \
        "https://ghfast.top/$url"; do
        if curl -sSL --connect-timeout 10 --max-time 30 -o "$tmp" "$src" 2>/dev/null && [ -s "$tmp" ]; then
            if [ -f "$out" ] && cmp -s "$out" "$tmp"; then
                log "  = $name (unchanged)"
            else
                mv "$tmp" "$out"
                log "  ✔ $name (updated, $(wc -l < "$out") lines)"
                CHANGED=1
            fi
            rm -f "$tmp"
            return 0
        fi
        rm -f "$tmp"
    done

    if [ -f "$out" ] && [ -s "$out" ]; then
        log "  ⚠ $name (all sources failed, kept local)"
    else
        log "  ✖ $name (no local copy available)"
    fi
    return 0
}

CHANGED=0

log "=== 开始更新规则文件 ==="

# --- Loyalsoldier 核心规则 ---
download direct-list.txt   "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
download apple-cn.txt      "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/apple-cn.txt"
download proxy-list.txt    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
download geosite-gfw.txt   "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
download china_ip_list.txt "https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/cn.txt"

# --- AI 域名列表（sync-ai.sh 每 2 分钟也会同步，此处日更一次兜底）---
download ai-list.txt       "https://raw.githubusercontent.com/jeffok/mosdns/main/rules/ai-list.txt"
# custom-hosts.txt / custom-local.txt 为用户本地编辑文件，不会被覆盖

# --- 虚假 NXDOMAIN IP 过滤 ---
download bogus-nxdomain.china.conf \
    "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/bogus-nxdomain.china.conf"

# --- 国内域名增强（felixonmars 列表）---
download accelerated-domains.china.conf \
    "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"

download apple.china.conf \
    "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf"

# 合并 Loyalsoldier + felixonmars → cn_domains.txt（去重）
log "  ─ 合并国内域名列表..."
{
    cat "$RULES_DIR/direct-list.txt"
    awk -F '/' '/^server=/{print $2}' "$RULES_DIR/accelerated-domains.china.conf"
    awk -F '/' '/^server=/{print $2}' "$RULES_DIR/apple.china.conf"
} | grep -v '^#' | grep -v '^\s*$' | sort -u > "${RULES_DIR}/cn_domains.txt.tmp"

if [ -f "$RULES_DIR/cn_domains.txt" ] && cmp -s "$RULES_DIR/cn_domains.txt" "${RULES_DIR}/cn_domains.txt.tmp"; then
    log "  = cn_domains.txt (unchanged)"
    rm -f "${RULES_DIR}/cn_domains.txt.tmp"
else
    mv "${RULES_DIR}/cn_domains.txt.tmp" "$RULES_DIR/cn_domains.txt"
    log "  ✔ cn_domains.txt (merged, $(wc -l < "$RULES_DIR/cn_domains.txt") lines)"
    CHANGED=1
fi

log "=== 更新完成 ==="

# 有变化则优雅重载 SmartDNS（同容器内 SIGHUP，不丢请求）
if [ "$CHANGED" = "1" ]; then
    log "规则有变更，重载 smartdns..."
    if smartdns -signal reload 2>/dev/null || pkill -HUP smartdns 2>/dev/null; then
        log "smartdns 优雅重载完成"
    else
        log "✖ 重载失败，配置可能有误"
        exit 1
    fi
else
    log "规则无变更，跳过重载"
fi
