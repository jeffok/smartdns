# Stage 1: 从源码编译 SmartDNS（golang:alpine 原生支持多架构交叉编译）
FROM --platform=$BUILDPLATFORM golang:alpine AS builder
ARG TARGETPLATFORM

RUN apk add --no-cache git

RUN git clone --depth 1 https://github.com/pymumu/smartdns.git /smartdns-src
WORKDIR /smartdns-src

# TARGETPLATFORM 格式: linux/amd64, linux/arm64, linux/arm/v7
# 转为 Go 交叉编译变量
RUN GOOS=linux \
    GOARCH=$(echo "$TARGETPLATFORM" | cut -d/ -f2) \
    GOARM=$(echo "$TARGETPLATFORM" | grep -oE 'v[0-9]+' | tr -d 'v') \
    CGO_ENABLED=0 \
    go build -ldflags="-w -s" -o /smartdns .

# Stage 2: 运行环境
FROM alpine:3.20

RUN apk add --no-cache curl bash procps bind-tools

COPY --from=builder /smartdns /usr/sbin/smartdns

COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/update.sh /opt/smartdns/update.sh
COPY scripts/sync-ai.sh /opt/smartdns/sync-ai.sh

RUN chmod +x /entrypoint.sh /opt/smartdns/update.sh /opt/smartdns/sync-ai.sh

ENTRYPOINT ["/entrypoint.sh"]
