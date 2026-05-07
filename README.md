# SmartDNS 智能分流 DNS 服务

基于 [SmartDNS](https://github.com/pymumu/smartdns) 的国内/国际/AI 三路分流 DNS 服务。
容器自包含，无需宿主机 crontab、无需外部依赖，启动即用。

## 架构

```
                    ┌─ domain-set:cn_domines ──→ group cn（国内上游）
                    ├─ domain-set:apple_domains ─→ group cn
  client :53 ─→ SmartDNS
                    ├─ domain-set:ai_domains ──→ group ai（AI 专用）
                    ├─ domain-set:proxy/gfw ──→ group global
                    └─ 未匹配域名 ─────────────→ group global（默认兜底）
```

三条链路：

| 分组 | 上游 DNS | 默认值 | 用途 |
|:---|:---|:---|:---|
| **cn** | `$DNS_CN` | 119.29.29.29, 223.5.5.5, 114.114.114.114 | 国内域名加速 |
| **global** | `$DNS_GLOBAL` | 1.1.1.1, 8.8.8.8, 9.9.9.9 | 国际域名（默认兜底） |
| **ai** | `$DNS_AI` | 同 `$DNS_GLOBAL` | ChatGPT/Gemini/Claude 等 AI 域名 |

## 快速开始

```bash
# 1. 配置环境变量
cp .env.example .env
vi .env

# 2. 构建并启动
docker compose build
docker compose up -d

# 3. 查看启动日志
docker compose logs -f smartdns

# 4. 验证
dig @127.0.0.1 baidu.com      # → cn 组
dig @127.0.0.1 google.com     # → global 组
dig @127.0.0.1 chatgpt.com    # → ai 组
```

首次启动会自动完成：模板生成 → 规则下载 → 合并去重 → AI 同步 → 提供服务。

## 环境变量

所有配置通过 `.env` 控制，完整参数见 `.env.example`。

### DNS 上游

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `DNS_CN` | `119.29.29.29,223.5.5.5,114.114.114.114` | 国内域名上游，逗号分隔 |
| `DNS_GLOBAL` | `1.1.1.1,8.8.8.8,9.9.9.9` | 国际域名上游，也是未匹配域名的默认上游 |
| `DNS_AI` | 同 `$DNS_GLOBAL` | AI 域名专用上游，如有独立专线/通道在此填写 |

### ECS（CDN 优化）

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `ECS_PRESET` | `127.0.0.0/24` | 向上游发送的伪 IP 段，让 CDN 返回目标地区节点 |

```bash
# 海外回国（让 CDN 返回国内节点）
ECS_PRESET=119.29.29.29

# 国内出国（让 CDN 返回海外节点）
ECS_PRESET=8.8.8.8
```

### 容器内部 DNS

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `CONTAINER_DNS` | `8.8.8.8` | 容器内 curl/nslookup 等工具使用的 DNS。默认 8.8.8.8 确保 GitHub 可访问 |

### RouterOS AI 同步（可选）

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `ROS_HOST` | 空 | RouterOS LAN IP，留空则关闭 RouterOS 同步 |
| `ROS_USER` | `admin` | RouterOS REST API 用户名 |
| `ROS_PASS` | 空 | RouterOS 密码 |

RouterOS 同步逻辑：`sync-ai.sh`（每 2 分钟）→ 解析 AI 域名 IP → 写入 ROS `ai-sgp` address-list → 策略路由据此强制走指定出口。

### AI 列表

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `AI_LIST_URL` | 项目 `data/rules/ai-list.txt`（GitHub） | AI 域名列表远端地址，支持 `|` 分隔多源镜像 |
| `RELOAD_ON_AI_LIST_CHANGE` | `1` | AI 列表变更后是否自动 SIGHUP 重载 SmartDNS |

### 通用

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `TZ` | `Asia/Shanghai` | 容器时区 |

## 域名路由规则

SmartDNS 按以下优先级逐条匹配：

| 优先级 | 域名集 | 文件来源 | 路由组 |
|:---|:---|:---|:---|
| 1 | `custom_local` | `data/rules/custom-local.txt` | **cn** |
| 2 | `cn_domains` | Loyalsoldier + felixonmars 合并 | **cn** |
| 3 | `apple_domains` | Loyalsoldier `apple-cn.txt` | **cn** |
| 4 | `ai_domains` | `data/rules/ai-list.txt` | **ai** |
| 5 | `proxy_domains` | Loyalsoldier `proxy-list.txt` | **global** |
| 6 | `gfw_domains` | Loyalsoldier `gfw.txt` | **global** |
| — | 未匹配 | — | **global（默认）** |

### 域名集文件说明

| 文件 | 位置 | 来源 | 更新 | 说明 |
|:---|:---|:---|:---|:---|
| `cn_domains.txt` | `data/rules/` | 三源合并 | 每日 04:30 | 国内域名，自动去重 |
| `apple-cn.txt` | `data/rules/` | Loyalsoldier | 每日 04:30 | Apple 中国 |
| `proxy-list.txt` | `data/rules/` | Loyalsoldier | 每日 04:30 | 需代理 |
| `geosite-gfw.txt` | `data/rules/` | Loyalsoldier | 每日 04:30 | GFW |
| `ai-list.txt` | `data/rules/` | 项目内置 | 每 2 分钟 | AI 域名 |
| `custom-local.txt` | `data/rules/` | **用户编辑** | 手动 | 额外国内域名 |
| `custom-hosts.txt` | `data/rules/` | **用户编辑** | 手动 | 静态 IP 映射 |

## 容器内部机制

### 启动流程

```
容器启动
  └─ entrypoint.sh
       ├─ 设置容器 DNS（CONTAINER_DNS）
       ├─ 从 .env 生成 smartdns.conf（awk 替换模板占位符）
       ├─ 运行 update.sh（首次规则下载 + 合并）
       ├─ 启动 crond（每日 04:30 更新 + 每 2 分钟 AI 同步）
       ├─ 运行 sync-ai.sh（首次 AI 域名同步）
       └─ exec smartdns -f（前台运行，PID 1）
```

### 规则更新

- **首次启动**：entrypoint 自动执行 `update.sh`，下载所有规则并合并
- **定时更新**：crond 每天 04:30 触发 `update.sh`
- **增量更新**：脚本内部 `cmp` 比对新旧文件，只有内容变化才写入磁盘 + SIGHUP 重载
- **多源镜像**：每条规则从 4 个源依次尝试（GitHub RAW → gh-proxy → mirror.ghproxy → ghfast.top）

### AI 域名同步

- **频率**：每 2 分钟（crond）
- **本地**：刷新 `ai-list.txt`，如有变化则 SIGHUP 重载 SmartDNS
- **RouterOS**：仅当 `ROS_HOST` + `ROS_PASS` 已配置时，将 AI 域名解析的 IP 写入 ROS `ai-sgp` 地址列表
- **开关**：不设置 `ROS_HOST` 即完全关闭 RouterOS 同步

### 优雅重载

规则或 AI 列表有变更时，通过 `smartdns -signal reload`（SIGHUP）重载配置，**不丢正在处理的请求**。

## 手动操作

```bash
# 手动触发规则更新
docker compose exec smartdns /opt/smartdns/update.sh

# 手动触发 AI 同步
docker compose exec smartdns /opt/smartdns/sync-ai.sh

# 查看实时日志
docker compose logs -f smartdns

# 重启容器
docker compose restart smartdns

# 重建镜像（拉取最新规则后）
docker compose build --no-cache
```

## RouterOS AI 联动完整配置

### 原理

```
sync-ai.sh ─→ nslookup 解析 AI 域名 ─→ RouterOS REST API
                                         └─ /ip/firewall/address-list
                                              └─ list=ai-sgp
                                                   └─ 策略路由匹配
                                                        └─ 走 SGP 出口
```

### RouterOS 侧配置

```bash
# 1. 启用 REST API
/ip service set www disabled=no port=80

# 2. 创建地址列表（sync-ai.sh 会自动写入）
/ip firewall address-list add list=ai-sgp

# 3. 策略路由（示例：ai-sgp 走新加坡网关）
/ip route add dst-address=0.0.0.0/0 gateway=10.0.0.1 routing-mark=ai-sgp
/ip firewall mangle add chain=prerouting dst-address-list=ai-sgp action=mark-routing new-routing-mark=ai-sgp
```

### 容器侧配置

```bash
# .env
ROS_HOST=192.168.88.254
ROS_USER=admin
ROS_PASS=your_password
```

配置后无需重启，sync-ai.sh 会在 2 分钟内自动写入 ROS。

## 常见问题

### 规则下载失败

**现象**：日志显示 `all sources failed`。

**原因**：容器内部 DNS 无法解析 GitHub。

**解决**：在 `.env` 中设置可用的 `CONTAINER_DNS`。

### 查询返回 SERVFAIL

**现象**：`dig @127.0.0.1 example.com` 返回 `SERVFAIL`。

**排查**：

```bash
docker compose logs smartdns
docker compose exec smartdns nslookup google.com 8.8.8.8
docker compose exec smartdns ls -la /etc/smartdns/rules/
```

### AI 列表不更新

```bash
docker compose exec smartdns /opt/smartdns/sync-ai.sh
```

## 文件结构

```
smartdns/
├── compose.yaml                # Docker Compose 部署
├── .env                        # 本地配置（不提交）
├── .env.example                # 环境变量模板
├── .gitignore
├── README.md
│
├── docker/                     # 容器构建上下文
│   ├── Dockerfile
│   └── scripts/
│       ├── entrypoint.sh       # 容器入口
│       ├── update.sh           # 规则下载合并
│       └── sync-ai.sh          # AI 域名 + RouterOS 同步
│
├── config/                     # 静态配置模板
│   └── Smartfile               # SmartDNS 配置模板
│
└── data/                       # 运行时数据（挂载卷）
    ├── rules/                  # 域名规则文件
    │   ├── ai-list.txt         #   用户自定义（已跟踪）
    │   ├── custom-hosts.txt    #   用户自定义（已跟踪）
    │   └── custom-local.txt    #   用户自定义（已跟踪）
    │   ├── cn_domains.txt      #   自动生成（已忽略）
    │   └── ...                 #   自动生成（已忽略）
    └── logs/                   # SmartDNS 日志（已忽略）
```

## License

MIT
