#!/bin/bash
# 排查：vmauth 写入路径 400
set -u
echo "=============================================="
echo " W1 看写入 400 的具体内容"
echo "=============================================="
curl -s -i -X POST --max-time 20 -u backend:backend-pass-123 \
  --data-binary 'l10_dbg,idx=1 value=1' \
  'http://localhost:8427/api/v1/write' 2>&1 | tail -3
echo
echo "  ⚠️ 注意：我这次【没带时间戳】，Influx 行协议可以省略时间戳"
echo "     但先确认报错是什么"

echo
echo "=============================================="
echo " W2 推断拼接结果"
echo "=============================================="
echo "  我的配置:"
echo "    src_paths:  ['/api/v1/write']"
echo "    url_prefix: ['http://vminsert-learn:8480/insert/100/influx']"
echo
echo "  拼接 = /insert/100/influx + /api/v1/write"
echo "       = /insert/100/influx/api/v1/write"
echo
echo "  但真实写入路径是 /insert/100/influx/write"
echo "  又错了！/api/v1/write 是【Prometheus 风格】，"
echo "  而 /insert/<tenant>/influx/write 是【Influx 风格】"

echo
echo "=============================================="
echo " W3 验证：直连后端试各种写入路径"
echo "=============================================="
for P in "/insert/100/influx/write" "/insert/100/influx/api/v1/write" \
         "/insert/100/prometheus/api/v1/write" "/insert/100/prometheus/write"; do
  printf "    %-42s " "$P"
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 20 \
    --data-binary 'l10_dbg,idx=1 value=1' \
    "http://localhost:8480$P"
done

echo
echo "=============================================="
echo " W4 关键认知：src_paths 和 url_prefix 的路径是【拼接】关系"
echo "=============================================="
echo "  正确做法：让 src_paths 的后半段 = 后端路径的后半段"
echo
echo "  方案：src_paths 用 /api/v1/write，url_prefix 用"
echo "        http://vminsert:8480/insert/100/influx"
echo "        → 拼出 /insert/100/influx/api/v1/write  ✗"
echo
echo "  改法 A（推荐）：src_paths 直接用 /write"
echo "        src_paths:  ['/write']"
echo "        url_prefix: ['http://vminsert:8480/insert/100/influx']"
echo "        → 拼出 /insert/100/influx/write  ✓"
echo "        客户端访问: http://vmauth:8427/write   ← 不再是标准 Prometheus 路径"
echo
echo "  改法 B：用 vmauth 的 path rewriting"
echo "        vmauth 支持在 url_prefix 里用 \$1 引用 src_paths 的捕获组"
echo
echo "  改法 C（最实用）：用 Prometheus remote write 协议"
echo "        src_paths:  ['/api/v1/write']"
echo "        url_prefix: ['http://vminsert:8480/insert/100/prometheus']"
echo "        → 拼出 /insert/100/prometheus/api/v1/write  ✓"
echo "        客户端用 Prometheus remote_write，走标准路径"

echo
echo "=============================================="
echo " W5 验证改法 C"
echo "=============================================="
printf "    直连 /insert/100/prometheus/api/v1/write: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 20 \
  --data-binary 'l10_dbg,idx=1 value=1' \
  'http://localhost:8480/insert/100/prometheus/api/v1/write'
echo "    （remote write 需要 Snappy 压缩的 protobuf，"
echo "      纯文本可能不是 204，但至少不该是 400 unsupported path）"

echo
echo "=============================================="
echo " W6 检查 vmauth 是否支持路径重写"
echo "=============================================="
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -iE 'rewrite|drop_src_path|url_prefix' | head -10
echo
echo "  -- 看官方配置文件支持哪些字段 --"
docker run --rm victoriametrics/vmauth:v1.151.0 --help 2>&1 \
  | grep -B2 -A6 'src_paths' | head -25
