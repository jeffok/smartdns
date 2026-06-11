#!/bin/sh
# sync-ai.sh — 解析 AI 域名并通过 REST API 写入 RouterOS address-list
# 增量模式：只添加，不删除旧条目，依赖 TTL 自然过期
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

api_post() {
  curl -sS --header "Authorization: Basic $AUTH" \
    --header "content-type: application/json" \
    --data "$2" "$1" 2>/dev/null
}

# 增量同步：只添加，重复由 ROS 返回 400 自动忽略，旧条目靠 TTL 过期清理
DOMAIN_COUNT=0
IP_COUNT=0
ADD_OK=0
ADD_DUP=0
ADD_FAIL=0

while IFS= read -r line; do
  domain=$(echo "$line" | sed 's/#.*//' | xargs)
  [ -z "$domain" ] && continue
  DOMAIN_COUNT=$((DOMAIN_COUNT + 1))

  for ip in $(resolve_ipv4s "$domain"); do
    if is_valid_ipv4 "$ip"; then
      IP_COUNT=$((IP_COUNT + 1))
      resp=$(api_post "${API}/add" "{\"list\":\"${LIST}\",\"address\":\"${ip}\",\"timeout\":\"${TTL}\",\"comment\":\"${COMMENT}\"}")
      case "$resp" in
        *'"ret"'*) ADD_OK=$((ADD_OK + 1)) ;;
        *'already have'*) ADD_DUP=$((ADD_DUP + 1)) ;;
        *) ADD_FAIL=$((ADD_FAIL + 1)) ;;
      esac
    fi
  done
done < "$AI_LIST"

echo "[sync-ai] done domains=$DOMAIN_COUNT ips=$IP_COUNT added=$ADD_OK dup=$ADD_DUP failed=$ADD_FAIL"
