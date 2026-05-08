# SmartDNS 智能分流 DNS 服务

基于 [SmartDNS](https://github.com/pymumu/smartdns) 的国内/国际/AI 三路分流 DNS 服务。
容器自包含，内置 crond 定时更新规则，支持 **amd64 + arm64** 双架构，开箱即用。

- **镜像**: `docker.io/jeffok/smartdns:latest`
- **源码**: `github.com/jeffok/smartdns`
- **架构**: `linux/amd64` · `linux/arm64`

## 架构

```
                    ┌─ domain-set:custom_local ─→ group cn
                    ├─ domain-set:cn_domains ───→ group cn
                    ├─ domain-set:apple_domains ─→ group cn
  client :53 ─→ SmartDNS
                    ├─ domain-set:ai_domains ───→ group ai
                    ├─ domain-set:proxy_domains → group global
                    ├─ domain-set:gfw_domains ──→ group global
                    └─ 未匹配域名 ──────────────→ group global（默认兜底）
```

三条链路：

| 分组 | 默认上游 | 用途 |
|:---|:---|:---|
| **cn** | 119.29.29.29, 223.5.5.5, 114.114.114.114, 202.96.128.86（广东电信） | 国内域名加速 |
| **global** | 1.1.1.1, 8.8.8.8, 9.9.9.9（含 DoT/DoH 加密上游） | 国际域名（未匹配默认） |
| **ai** | 1.0.0.1, 8.8.4.4 | ChatGPT/Gemini/Claude 等 AI 域名 |

## 快速开始

### 方式一：使用预构建镜像（推荐）

```bash
# 1. 配置环境变量
cp .env.example .env
vi .env

# 2. 直接启动（无需本地构建）
docker compose up -d

# 3. 查看日志
docker compose logs -f smartdns

# 4. 验证
dig @127.0.0.1 baidu.com      # → cn 组
dig @127.0.0.1 google.com     # → global 组
dig @127.0.0.1 chatgpt.com    # → ai 组
```

### 方式二：本地构建

```bash
docker compose build
docker compose up -d
```

首次启动会自动完成：模板生成 → 规则下载 → 合并去重 → AI 同步 → 提供服务。

## 环境变量

所有配置通过 `.env` 控制，完整参数见 `.env.example`。

### DNS 上游

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `DNS_CN` | `119.29.29.29,223.5.5.5,114.114.114.114,202.96.128.86` | 国内域名上游，逗号分隔 |
| `DNS_GLOBAL` | `1.1.1.1,8.8.8.8,9.9.9.9` | 国际域名上游，也是未匹配域名的默认上游 |
| `DNS_AI` | `1.0.0.1,8.8.4.4` | AI 域名专用上游 |

### ECS（CDN 优化）

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `ECS_PRESET` | 空（不启用） | 向上游发送的伪 IP 段，让 CDN 返回目标地区节点 |

```bash
# 海外回国（让 CDN 返回国内节点）
ECS_PRESET=119.29.29.29

# 国内出国（让 CDN 返回海外节点）
ECS_PRESET=8.8.8.8
```

### 容器内部 DNS

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `CONTAINER_DNS` | `8.8.8.8` | 容器内 curl/nslookup 等工具使用的 DNS，确保 GitHub 可访问 |

### RouterOS AI 同步（可选）

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `ROS_HOST` | 空 | RouterOS LAN IP，留空则关闭同步 |
| `ROS_USER` | `admin` | REST API 用户名 |
| `ROS_PASS` | 空 | REST API 密码 |

`sync-ai.sh`（每 2 分钟）解析 AI 域名 IP 并写入 ROS `ai-sgp` address-list，策略路由据此选路。

### AI 列表

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `AI_LIST_URL` | GitHub smartdns 项目 `data/rules/ai-list.txt` | 远端地址，支持 `|` 多源 |
| `RELOAD_ON_AI_LIST_CHANGE` | `1` | 变更后是否自动 SIGHUP 重载 |

### 通用

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `TZ` | `Asia/Shanghai` | 容器时区 |

## 域名路由规则

SmartDNS 按以下优先级逐条匹配：

| 优先级 | 域名集 | 文件来源 | 路由组 |
|:---|:---|:---|:---|
| 1 | `custom_local` | `data/rules/custom-local.txt`（**用户编辑**） | **cn** |
| 2 | `cn_domains` | Loyalsoldier + felixonmars 合并（自动更新） | **cn** |
| 3 | `apple_domains` | Loyalsoldier `apple-cn.txt` | **cn** |
| 4 | `ai_domains` | `data/rules/ai-list.txt`（sync-ai 每 2 分钟同步） | **ai** |
| 5 | `proxy_domains` | Loyalsoldier `proxy-list.txt` | **global** |
| 6 | `gfw_domains` | Loyalsoldier `gfw.txt` | **global** |
| — | 未匹配 | — | **global（默认）** |

### 域名集文件说明

| 文件 | 来源 | 更新方式 | 说明 |
|:---|:---|:---|:---|
| `cn_domains.txt` | Loyalsoldier `direct-list.txt` + felixonmars `accelerated-domains.china.conf` + `apple.china.conf` 三源合并去重 | crond 每日 04:30 | 国内域名加速 |
| `apple-cn.txt` | Loyalsoldier `apple-cn.txt` | crond 每日 04:30 | Apple 中国域名 |
| `proxy-list.txt` | Loyalsoldier `proxy-list.txt` | crond 每日 04:30 | 需代理域名 |
| `geosite-gfw.txt` | Loyalsoldier `gfw.txt` | crond 每日 04:30 | GFW 列表 |
| `ai-list.txt` | 项目内置 + GitHub 远端同步 | sync-ai 每 2 分钟 | AI 域名 |
| `custom-local.txt` | **用户本地编辑** | 手动 | 额外国内域名（**不会被覆盖**） |
| `custom-hosts.txt` | **用户本地编辑** | 手动 | 静态 IP 映射（**不会被覆盖**） |

> `custom-local.txt` 和 `custom-hosts.txt` 为用户维护文件，`update.sh` 不会下载覆盖。

## 容器内部机制

### 构建

```
Dockerfile（多阶段构建，目标 ~25MB，amd64 + arm64）

Stage 1: 提取
  FROM pymumu/smartdns:latest
  复制 /usr/local/lib/smartdns/  →  二进制 + run-smartdns 启动脚本 + 自带 glibc/ssl 库
  手动创建符号链接 /usr/sbin/smartdns → run-smartdns
  （注：官方镜像中的 /usr/sbin/smartdns 是符号链接，
   Docker COPY 会跟随链接复制内容，导致 run-smartdns 脚本内路径解析错误，
   因此改为手动 ln -s）

Stage 2: 运行层
  FROM alpine:3.20
  apk add curl bash procps bind-tools（~23MB 工具层）
  COPY --from=stage1 整个 smartdns 安装树
```

GitHub Actions 自动构建触发条件：

| 触发方式 | 时机 | 用途 |
|:---|:---|:---|
| `push master` | 代码变更时 | 脚本/配置更新 |
| `schedule` | **每月 1 号 04:00 UTC** | 上游镜像发版、Alpine 安全更新 |
| `workflow_dispatch` | 手动触发 | 临时需要构建 |

每月定时构建确保即使没有代码变更，镜像也会重新拉取 `pymumu/smartdns:latest` 和 `alpine:3.20` 基础镜像，保持最新。

### 启动流程

```
entrypoint.sh
  ├─ 设置容器 DNS（CONTAINER_DNS → /etc/resolv.conf）
  ├─ awk 替换模板占位符 → 生成 /etc/smartdns/smartdns.conf
  │     __UPSTREAMS_CN__ → server ... -group cn -exclude-default-group
  │     __UPSTREAMS_GLOBAL__ → server ... -group global
  │     __UPSTREAMS_AI__ → server ... -group ai -exclude-default-group
  │     __ECS_LINE__ → 空（未配置） 或 edns-client-subnet IP
  ├─ find 清理超过 2 天的日志
  ├─ run update.sh（首次规则下载 + 合并去重）
  ├─ crond 启动（update@04:30 + 日志清理 + sync-ai@*/2）
  ├─ run sync-ai.sh（首次 AI 域名同步）
  └─ exec smartdns -f（前台运行，PID 1）
```

### 规则更新

- **首次启动**：entrypoint 自动执行 `update.sh`，下载所有规则并合并
- **定时更新**：crond 每天 04:30 触发 `update.sh`
- **增量更新**：`cmp` 比对新旧文件，仅变更时写入磁盘 + SIGHUP 重载
- **多源镜像**：每条规则从 4 个源依次尝试（GitHub RAW → gh-proxy → mirror.ghproxy → ghfast.top）

### AI 域名同步

- **频率**：crond 每 2 分钟触发 `sync-ai.sh`
- **本地**：刷新 `ai-list.txt`，变化则 SIGHUP 重载 SmartDNS
- **RouterOS**：仅当 `ROS_HOST` + `ROS_PASS` 已配置时写入 ROS `ai-sgp`
- **开关**：不设置 `ROS_HOST` 即完全关闭 RouterOS 同步

### 优雅重载

规则或 AI 列表变更后，通过 `pkill -HUP smartdns` 发送 SIGHUP 信号重载，**不丢正在处理的请求**。
（Alpine 下 `smartdns -signal reload` 依赖 glibc loader 不可用，使用 `pkill` 代替）

### 健康检查

Dockerfile 内置 `HEALTHCHECK` 指令，通过 `nslookup baidu.com 127.0.0.1` 每 30 秒检查一次。
所有 Docker 部署方式（compose / docker run / swarm / k8s）均生效：

```bash
docker inspect smartdns --format '{{.State.Health.Status}}'
# healthy / unhealthy
```

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

# 使用预构建镜像（跳过本地构建）
docker compose pull
docker compose up -d
```

## RouterOS AI 联动

### 原理

```
sync-ai.sh ─→ nslookup 解析 AI 域名 → RouterOS REST API
                                        └─ /ip/firewall/address-list
                                             └─ list=ai-sgp → 策略路由 → 走 SGP 出口
```

### RouterOS 侧

```bash
/ip service set www disabled=no port=80
/ip firewall address-list add list=ai-sgp
/ip route add dst-address=0.0.0.0/0 gateway=10.0.0.1 routing-mark=ai-sgp
/ip firewall mangle add chain=prerouting dst-address-list=ai-sgp action=mark-routing new-routing-mark=ai-sgp
```

### 容器侧

```bash
# .env
ROS_HOST=192.168.88.254
ROS_USER=admin
ROS_PASS=your_password
```

配置后无需重启，sync-ai.sh 在 2 分钟内自动写入。

## 常见问题

### 规则下载失败

**原因**：容器内部 DNS 无法解析 GitHub。

**解决**：在 `.env` 中设置可用的 `CONTAINER_DNS`。

### 查询返回 SERVFAIL

```bash
docker compose logs smartdns
docker compose exec smartdns nslookup google.com 8.8.8.8
docker compose exec smartdns ls -la /etc/smartdns/rules/
```

### AI 列表不更新

```bash
docker compose exec smartdns /opt/smartdns/sync-ai.sh
```

### 容器健康检查状态

```bash
docker inspect smartdns --format '{{.State.Health.Status}}'
# 返回 healthy 或 unhealthy
# unhealthy 时查看日志定位问题
```

## 文件结构

```
smartdns/
├── compose.yaml                # Docker Compose 部署
├── .env                        # 本地配置（不提交）
├── .env.example                # 环境变量完整说明
├── .gitignore
├── README.md
├── .github/workflows/
│   └── docker-build.yml        # GitHub Actions：自动构建多架构镜像
│                               # 触发: push master / 每月1号 / 手动
│
├── docker/                     # 容器构建上下文
│   ├── Dockerfile              # 多阶段构建（从官方镜像提取 + alpine 运行层）
│   └── scripts/
│       ├── entrypoint.sh       # 容器入口：模板生成 + 规则下载 + crond
│       ├── update.sh           # 规则下载合并（容器内执行）
│       ├── sync-ai.sh          # AI 域名同步 + RouterOS 联动
│       └── healthcheck.sh      # 健康检查（每30秒 nslookup baidu.com）
│
└── data/                       # 运行时数据（挂载卷，仅 2 个挂载点）
    ├── rules/                  # Smartfile + 域名规则（挂载到 /etc/smartdns/rules）
    │   ├── Smartfile           #   SmartDNS 配置模板（entrypoint 处理占位符）
    │   ├── ai-list.txt         #   用户自定义（已跟踪）
    │   ├── custom-hosts.txt    #   用户自定义，不被覆盖（已跟踪）
    │   └── custom-local.txt    #   用户自定义，不被覆盖（已跟踪）
    │   ├── cn_domains.txt      #   自动生成（已忽略）
    │   └── ...                 #   自动生成（已忽略）
    └── logs/                   # SmartDNS 日志（已忽略，保留 2 天）
```

## License

MIT
