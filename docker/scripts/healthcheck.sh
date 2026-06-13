#!/bin/sh
# Author: Jeff
# Date: 2025-06-01
# Description: SmartDNS 健康检查，通过 nslookup 验证 DNS 服务是否正常响应
# Copyright © 2022 by Jeff, All Rights Reserved.
# ==========================================
nslookup baidu.com 127.0.0.1 >/dev/null 2>&1 || exit 1
