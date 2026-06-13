#!/bin/sh
# Author: Jeff
# Date: 2025-06-01
# Description: SmartDNS 规则更新脚本，从 ASN-China 项目和上游源下载域名列表并合并去重，由 entrypoint 和 crond 触发
# Copyright © 2022 by Jeff, All Rights Reserved.
# ==========================================
set -e

RULES_DIR="/etc/smartdns/rules"
CONFIG_FILE="/etc/smartdns/smartdns.conf"

# ASN-China release-files 分支基础 URL（主备镜像）
ASN_CHINA_PRIMARY="https://raw.githubusercontent.com/jeffok/ASN-China/release-files"
ASN_CHINA_MIRRORS="https://gh-proxy.com/${ASN_CHINA_PRIMARY}|https://mirror.ghproxy.com/${ASN_CHINA_PRIMARY}|https://ghfast.top/${ASN_CHINA_PRIMARY}"

log() { echo "[update] $(date '+%H:%M:%S') $*"; }

download() {
    name="$1" url="$2" out="$RULES_DIR/$name"
    tmp="${out}.tmp"

    # 构建主备 URL 列表
    primary_url="$url"
    # 如果 URL 以 ASN_CHINA_PRIMARY 开头，自动添加镜像
    case "$url" in
        ${ASN_CHINA_PRIMARY}*)
            suffix="${url#${ASN_CHINA_PRIMARY}}"
            urls="$primary_url"
            OLD_IFS="$IFS"; IFS='|'
            for mirror_base in $ASN_CHINA_MIRRORS; do
                urls="$urls ${mirror_base}${suffix}"
            done
            IFS="$OLD_IFS"
            ;;
        https://raw.githubusercontent.com/*)
            # 其他 GitHub 文件也走镜像
            urls="$primary_url https://gh-proxy.com/$url https://mirror.ghproxy.com/$url https://ghfast.top/$url"
            ;;
        *)
            urls="$primary_url"
            ;;
    esac

    for src in $urls; do
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

# --- 从 ASN-China release-files 分支拉取（主数据源）---
# 国内域名（已合并 Loyalsoldier + felixonmars，去重排序）
download cn_domains.txt    "${ASN_CHINA_PRIMARY}/cn-domains.txt"
# Apple 中国域名
download apple-cn.txt      "${ASN_CHINA_PRIMARY}/apple-cn.txt"
# 代理域名
download proxy-list.txt    "${ASN_CHINA_PRIMARY}/proxy-domains.txt"
# GFW 域名
download geosite-gfw.txt   "${ASN_CHINA_PRIMARY}/gfw-domains.txt"
# AI 域名
download ai-list.txt       "${ASN_CHINA_PRIMARY}/ai-domains.txt"
# 中国 IPv4 段（供 SmartDNS ip-set 使用）
download china_ip_list.txt "${ASN_CHINA_PRIMARY}/IPv4.China.list"

# --- 虚假 NXDOMAIN IP 过滤（felixonmars，ASN-China 未收录此文件）---
download bogus-nxdomain.china.conf \
    "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/bogus-nxdomain.china.conf"

# custom-hosts.txt / custom-local.txt 为用户本地编辑文件，不会被覆盖

log "=== 更新完成 ==="

# 有变化则优雅重载 SmartDNS（SIGHUP，不丢请求）
# 首次启动时 smartdns 尚未运行，跳过重载避免假报错
if [ "$CHANGED" = "1" ]; then
    if pgrep smartdns >/dev/null 2>&1; then
        log "规则有变更，重载 smartdns..."
        if pkill -HUP smartdns 2>/dev/null || smartdns -signal reload 2>/dev/null; then
            log "smartdns 优雅重载完成"
        else
            log "✖ 重载失败（不影响当前运行，下次重启生效）"
        fi
    else
        log "规则有变更，smartdns 尚未运行，跳过重载"
    fi
else
    log "规则无变更，跳过重载"
fi
