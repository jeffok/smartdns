#!/bin/sh
# 健康检查：查询 baidu.com 验证 SmartDNS 是否正常响应
nslookup baidu.com 127.0.0.1 >/dev/null 2>&1 || exit 1
