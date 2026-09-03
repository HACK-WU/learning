#!/usr/bin/env bash
# 课 4 步骤 3：重启 VM 开启 Graphite/OpenTSDB 协议，并查清 CSV 落库 0 条的原因
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py

echo "########## 1. 重启 VM，开启 Graphite + OpenTSDB ##########"
echo "  先查原容器启动参数（保留 storageDataPath 等）:"
docker inspect vm-learn --format '{{range .Args}}{{.}} {{end}}' 2>/dev/null
echo
docker inspect vm-learn --format '  Mounts: {{range .Mounts}}{{.Source}} -> {{.Destination}} {{end}}' 2>/dev/null

echo
echo "  停止并重建容器（保留数据卷，新增协议端口）..."
docker rm -f vm-learn >/dev/null 2>&1
sleep 2
docker run -d --name vm-learn \
  -p 8428:8428 -p 2003:2003 -p 2003:2003/udp -p 4242:4242 -p 4243:4243 \
  -v /mnt/d/projects/learning/victoriametrics/playground/data:/victoria-metrics-data \
  victoriametrics/victoria-metrics:latest \
  -storageDataPath=/victoria-metrics-data \
  -retentionPeriod=1d \
  -graphiteListenAddr=:2003 \
  -opentsdbListenAddr=:4242 \
  -opentsdbHTTPListenAddr=:4243 \
  -selfScrapeInterval=10s

echo "  等待 VM 启动..."
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 3 http://localhost:8428/health)" = "200" ] \
    && { echo "  VM 就绪 (${i}s)"; break; }
  sleep 1
done

echo
echo "########## 2. 验证新开启的端口 ##########"
for p in 8428 2003 4242 4243; do
  if (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null; then echo "  $p: 已监听 ✅"
  else echo "  $p: 未监听 ❌"; fi
done

echo
echo "########## 3. 确认原有数据还在（数据卷保留）##########"
echo "  series/count: $(curl -s -m 10 http://localhost:8428/api/v1/series/count)"
curl -s -m 15 -G "$VM/api/v1/query" --data-urlencode 'query=l04_inf_b_load' \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'

echo
echo "########## 4. Graphite plaintext 协议实测 ##########"
NOW=$(date +%s)
echo "  格式: <metric.path> <value> <timestamp>"
echo "  写入: l04.graphite.test 42 $NOW"
echo "l04.graphite.test 42 $NOW" | timeout 5 nc -q0 127.0.0.1 2003 2>/dev/null \
  && echo "    已发送" || echo "    nc 发送失败（可能未安装 netcat）"

echo "  备用：用 bash /dev/tcp 发送"
exec 3<>/dev/tcp/127.0.0.1/2003
echo "l04.graphite.test 42 $NOW" >&3
exec 3<&-
sleep 2
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 1
echo "--- 查 graphite 指标 ---"
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04.graphite.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "########## 5. OpenTSDB HTTP 协议实测（/api/put）##########"
OTS='{"metric":"l04.opentsdb.test","timestamp":'"$NOW"',"value":18,"tags":{"host":"web01"}}'
echo "  $OTS"
curl -s -m 10 -o /dev/null -w "    http=%{http_code}\n" \
  -X POST "$VM/api/put" --data-binary "$OTS"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "--- 查 opentsdb 指标 ---"
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04.opentsdb.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "########## 6. CSV 落库 0 条排查：看服务端返回体 ##########"
CSV="l04_csv_c,hostA,3.14,${NOW}"
echo "  POST body 方式（format 用 -G 拼 URL）:"
curl -s -m 15 -G "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:l04_csv_c,2:label:host,3:metric:value,4:time:unix_s' \
  -w "\n    http=%{http_code}\n" \
  --data-urlencode "data=$CSV" -o /tmp/l04_csv_resp.txt
echo "    响应体: $(cat /tmp/l04_csv_resp.txt 2>/dev/null | head -3)"

echo
echo "  改用纯 POST + body（format 仍在 URL）:"
curl -s -m 15 -o /tmp/l04_csv_resp2.txt -w "    http=%{http_code}\n" \
  -X POST "$VM/api/v1/import/csv?format=1:metric:l04_csv_c,2:label:host,3:metric:value,4:time:unix_s" \
  --data-binary "$CSV"
echo "    响应体: $(cat /tmp/l04_csv_resp2.txt 2>/dev/null | head -3)"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_csv.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    CSV 落库 {} 条".format(len(d)))
for m in d: print("      ", m)
'
