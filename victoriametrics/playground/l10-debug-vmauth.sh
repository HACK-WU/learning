#!/bin/bash
# 排查：vmauth 认证通过但返回 400
set -u
echo "=============================================="
echo " D1 看 400 的具体内容"
echo "=============================================="
echo "  -- 带 -i 看响应头与 body --"
curl -s -i --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=up' \
  'http://localhost:8427/api/v1/query' 2>&1 | head -20

echo
echo "=============================================="
echo " D2 对照：直接打后端同样的路径"
echo "=============================================="
echo "  -- 后端完整路径应该是 --"
echo "     http://vmselect-learn:8481/select/100/prometheus/api/v1/query"
echo
echo -n "   直连 vmselect /select/100/prometheus/api/v1/query: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=up' \
  'http://localhost:8481/select/100/prometheus/api/v1/query' 2>/dev/null

echo
echo "  ⚠️ 关键：vmauth 的 url_prefix 拼接规则是"
echo "     url_prefix + 【原始请求路径】"
echo "     即 http://vmselect:8481/select/100/ + api/v1/query"
echo "     = http://vmselect:8481/select/100/api/v1/query"
echo
echo "     但真实路径需要 /select/100/prometheus/api/v1/query"
echo "     中间少了 【prometheus】 这一段！"

echo
echo "=============================================="
echo " D3 验证这个猜想"
echo "=============================================="
echo -n "   /select/100/api/v1/query (无 prometheus): "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=up' \
  'http://localhost:8481/select/100/api/v1/query' 2>/dev/null
echo -n "   /select/100/prometheus/api/v1/query:      "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 \
  --data-urlencode 'query=up' \
  'http://localhost:8481/select/100/prometheus/api/v1/query' 2>/dev/null

echo
echo "=============================================="
echo " D4 正确的两种修复方式"
echo "=============================================="
echo "  方式 A：src_paths 用完整路径，url_prefix 补上 prometheus"
echo "    src_paths:   ['/api/v1/query']"
echo "    url_prefix:  ['http://vmselect:8481/select/100/prometheus']"
echo "    → 拼接: /select/100/prometheus + /api/v1/query ✓"
echo
echo "  方式 B：src_paths 声明为 /prometheus/api/v1/query"
echo "    （客户端也用这个路径访问）"
echo
echo "  ⚠️ 但 vmauth 有更优雅的机制：url_prefix 支持【多路径】"
echo "     且 vmauth 会按顺序尝试，第一个返回成功的生效"

echo
echo "=============================================="
echo " D5 检查 vmauth 的 -help，确认拼接规则"
echo "=============================================="
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -A8 'url_prefix' | head -20

echo
echo "  -- 相关文档片段 --"
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -iE 'src_paths|url_map|backend' | head -10
