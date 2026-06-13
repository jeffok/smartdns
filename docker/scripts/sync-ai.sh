#!/bin/sh
# Author: Jeff
# Date: 2025-06-01
# Description: AI 域名同步脚本，解析 AI 域名 IP 并通过 REST API 写入 RouterOS address-list（增量+TTL 续期）
# Copyright © 2022 by Jeff, All Rights Reserved.
# ==========================================
RULES=/etc/smartdns/rules
AI_LIST="$RULES/ai-list.txt"
AI_LIST_URL="${AI_LIST_URL:-https://raw.githubusercontent.com/jeffok/smartdns/master/data/rules/ai-list.txt}"
LIST="ai-sgp"
COMMENT="smartdns-ai"
TTL="3600s"
DNS="${CONTAINER_DNS:-8.8.8.8}"
RELOAD_ON_AI_LIST_CHANGE="${RELOAD_ON_AI_LIST_CHANGE:-1}"
AI_LIST_CHANGED=0
CACHE_FILE="/tmp/ai-sgp-last.txt"

refresh_ai_list() {
  [ -z "$AI_LIST_URL" ] && return 0
  tmp="${AI_LIST}.tmp"

  downloaded=0
  old_ifs="$IFS"
  IFS='|'
  set -- $AI_LIST_URL
  IFS="$old_ifs"

  for url; do
    url=$(echo "$url" | xargs)
    [ -z "$url" ] && continue

    for src in "$url" \
        "https://gh-proxy.com/$url" \
        "https://mirror.ghproxy.com/$url" \
        "https://ghfast.top/$url"; do
      if curl -sSL --connect-timeout 10 --max-time 30 -o "$tmp" "$src" 2>/dev/null && [ -s "$tmp" ]; then
        if [ -f "$AI_LIST" ] && cmp -s "$AI_LIST" "$tmp"; then
          rm -f "$tmp"
        else
          mv "$tmp" "$AI_LIST"
          AI_LIST_CHANGED=1
          echo "[sync-ai] refreshed ai-list from $src (changed)"
        fi
        downloaded=1
        break 2
      fi
      rm -f "$tmp"
    done
  done

  if [ "$downloaded" = "0" ]; then
    if [ -s "$AI_LIST" ]; then
      echo "[sync-ai] WARN: refresh failed, using local ai-list"
      return 0
    fi
    echo "[sync-ai] WARN: ai-list missing and remote refresh failed"
    return 1
  fi
}

request_smartdns_reload() {
  [ "$RELOAD_ON_AI_LIST_CHANGE" = "0" ] && return 0
  [ "$RELOAD_ON_AI_LIST_CHANGE" = "false" ] && return 0

  if pkill -HUP smartdns 2>/dev/null || smartdns -signal reload 2>/dev/null; then
    echo "[sync-ai] ai-list changed, smartdns reloaded via SIGHUP"
    return 0
  fi
  echo "[sync-ai] WARN: ai-list changed but smartdns reload failed"
  return 1
}

resolve_ipv4s() {
  domain="$1"
  nslookup "$domain" "$DNS" 2>/dev/null | awk '
    $1 == "Name:" { seen_name = 1; next }
    seen_name && $1 == "Address:" { print $2; next }
    seen_name && $1 == "Address" && $2 ~ /^[0-9]+:$/ { print $3; next }
  ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
}

is_valid_ipv4() {
  case "$1" in ""|*[!0-9.]*) return 1 ;; esac
  o1=$(echo "$1" | cut -d. -f1); o2=$(echo "$1" | cut -d. -f2)
  o3=$(echo "$1" | cut -d. -f3); o4=$(echo "$1" | cut -d. -f4)
  [ -n "$o1" ] && [ -n "$o2" ] && [ -n "$o3" ] && [ -n "$o4" ] || return 1
  for o in "$o1" "$o2" "$o3" "$o4"; do [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1; done
  { [ "$o1" -eq 0 ] || [ "$o1" -eq 127 ]; } && return 1
  { [ "$o1" -eq 169 ] && [ "$o2" -eq 254 ]; } && return 1
  return 0
}

# ==========================================
# 主流程
# ==========================================
[ -d "$RULES" ] || mkdir -p "$RULES"
refresh_ai_list || exit 0
[ "$AI_LIST_CHANGED" -eq 1 ] && request_smartdns_reload

# ROS_HOST 为空则仅更新本地 ai-list，不同步 RouterOS
[ -z "$ROS_HOST" ] && exit 0
[ -z "$ROS_PASS" ] && exit 0
[ ! -f "$AI_LIST" ] && exit 0

ROS_USER="${ROS_USER:-admin}"
AUTH=$(printf '%s:%s' "$ROS_USER" "$ROS_PASS" | base64)
API="http://${ROS_HOST}/rest/ip/firewall/address-list"

api_get() {
  curl -sS --header "Authorization: Basic $AUTH" "$1" 2>/dev/null
}

api_post() {
  curl -sS --header "Authorization: Basic $AUTH" \
    --header "content-type: application/json" \
    --data "$2" "$1" 2>/dev/null
}

api_patch() {
  curl -sS --header "Authorization: Basic $AUTH" \
    --header "content-type: application/json" \
    -X PATCH --data "$2" "$1" 2>/dev/null
}

# 解析所有域名，收集当前 IP 列表
CURRENT_IPS="/tmp/ai-sgp-current.txt"
: > "$CURRENT_IPS"
DOMAIN_COUNT=0

while IFS= read -r line; do
  domain=$(echo "$line" | sed 's/#.*//' | xargs)
  [ -z "$domain" ] && continue
  DOMAIN_COUNT=$((DOMAIN_COUNT + 1))

  for ip in $(resolve_ipv4s "$domain"); do
    is_valid_ipv4 "$ip" && echo "$ip" >> "$CURRENT_IPS"
  done
done < "$AI_LIST"

# 去重排序
sort -u "$CURRENT_IPS" -o "$CURRENT_IPS"
IP_COUNT=$(wc -l < "$CURRENT_IPS" | tr -d ' ')

# 和上次对比
CHANGED=0
if [ -f "$CACHE_FILE" ]; then
  if ! cmp -s "$CACHE_FILE" "$CURRENT_IPS"; then
    CHANGED=1
    NEW_IPS=$(comm -13 "$CACHE_FILE" "$CURRENT_IPS" | wc -l | tr -d ' ')
    GONE_IPS=$(comm -23 "$CACHE_FILE" "$CURRENT_IPS" | wc -l | tr -d ' ')
    echo "[sync-ai] IP changed: +${NEW_IPS} -${GONE_IPS} (gone will expire via TTL)"
  fi
else
  CHANGED=1
fi

# 同步到 ROS：对每个 IP 执行 add 或 PATCH 续期
ADD_OK=0
RENEW_OK=0
FAIL=0

while IFS= read -r ip; do
  resp=$(api_post "${API}/add" "{\"list\":\"${LIST}\",\"address\":\"${ip}\",\"timeout\":\"${TTL}\",\"comment\":\"${COMMENT}\"}")
  case "$resp" in
    *'"ret"'*)
      ADD_OK=$((ADD_OK + 1))
      ;;
    *'already have'*)
      # 已存在，PATCH 刷新 TTL
      entry_id=$(api_get "${API}?list=${LIST}&address=${ip}" | grep -o '".id":"[^"]*"' | head -1 | cut -d'"' -f4)
      if [ -n "$entry_id" ]; then
        api_patch "${API}/${entry_id}" "{\"timeout\":\"${TTL}\"}" >/dev/null && RENEW_OK=$((RENEW_OK + 1))
      fi
      ;;
    *)
      FAIL=$((FAIL + 1))
      ;;
  esac
done < "$CURRENT_IPS"

# 保存本次结果作为下次对比基准
cp "$CURRENT_IPS" "$CACHE_FILE"
rm -f "$CURRENT_IPS"

# 仅在有变化或有新增/失败时输出详细日志
if [ "$CHANGED" -eq 1 ] || [ "$ADD_OK" -gt 0 ] || [ "$FAIL" -gt 0 ]; then
  echo "[sync-ai] done domains=$DOMAIN_COUNT ips=$IP_COUNT added=$ADD_OK renewed=$RENEW_OK failed=$FAIL"
fi
