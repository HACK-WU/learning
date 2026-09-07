#!/usr/bin/env bash
# 诊断：/api/health 的原始字节到底是什么样？为什么 grep 没命中
set -u
PORT="${1:-3011}"

echo "=== 1. 原始字节（前 120 字节，cat -A 显示不可见字符）==="
curl -s "http://localhost:${PORT}/api/health" | head -c 120 | cat -A

echo
echo
echo "=== 2. 去掉所有空白后 ==="
curl -s "http://localhost:${PORT}/api/health" | tr -d ' \n' | head -c 200
echo

echo
echo "=== 3. 两种 grep 写法对比 ==="
body=$(curl -s "http://localhost:${PORT}/api/health")
echo -n "  紧凑写法 '\"database\":\"ok\"'  : "
echo "$body" | grep -q '"database":"ok"' && echo "命中" || echo "未命中"
echo -n "  带空格写法 '\"database\": \"ok\"': "
echo "$body" | grep -q '"database": "ok"' && echo "命中" || echo "未命中"
echo -n "  jq 写法                        : "
echo "$body" | jq -r '.database' 2>/dev/null || echo "（无 jq）"
