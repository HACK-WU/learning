#!/usr/bin/env bash
# 课 4 步骤 5：重启 VM 加载 relabel + 流式聚合，实测写入前治理效果
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
PG=/mnt/d/projects/learning/victoriametrics/playground

echo "########## 1. 重启 VM，加载 relabel + 流式聚合配置 ##########"
docker rm -f vm-learn >/dev/null 2>&1
sleep 2
docker run -d --name vm-learn \
  -p 8428:8428 -p 2003:2003 -p 2003:2003/udp -p 4242:4242 -p 4243:4243 \
  -v "$PG/data:/victoria-metrics-data" \
  -v "$PG/relabel.yaml:/etc/victoriametrics/relabel.yaml:ro" \
  -v "$PG/stream-aggr.yaml:/etc/victoriametrics/stream-aggr.yaml:ro" \
  victoriametrics/victoria-metrics:latest \
  -storageDataPath=/victoria-metrics-data \
  -retentionPeriod=1d \
  -graphiteListenAddr=:2003 \
  -opentsdbListenAddr=:4242 \
  -opentsdbHTTPListenAddr=:4243 \
  -selfScrapeInterval=10s \
  -relabelConfig=/etc/victoriametrics/relabel.yaml \
  -streamAggr.config=/etc/victoriametrics/stream-aggr.yaml

echo "  等待启动..."
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 3 "$VM/health")" = "200" ] \
    && { echo "  就绪 (${i}s)"; break; }
  sleep 1
done
sleep 3

echo
echo "########## 2. 检查配置是否被加载 ##########"
echo "  --- 启动日志中的 relabel / streamAggr 相关信息 ---"
docker logs vm-learn 2>&1 | grep -iE 'relabel|streamAggr|stream aggregation' | head -10
echo
echo "  --- vm_streamaggr 指标（流式聚合是否在工作）---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_streamaggr.*"}' --data-urlencode "nocache=1" \
| python3 "$FMT"

echo
echo "########## 3. 实测 A：relabel 丢弃 user_id 标签 ##########"
NOW=$(date +%s)
echo "  写入带 user_id 的新数据（应被 labeldrop 去掉 user_id）"
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
  "l04_relabel_test{user_id=\"u999\",endpoint=\"/api/x\"} 42 ${NOW}"
# 也重新写一批 highcard
python3 - "$NOW" <<'PY' > /tmp/l04_rl.txt
import sys
now=int(sys.argv[1])
for i in range(20):
    print(f'l04_rl_card{{user_id="z{i}",endpoint="/api/y"}} {i} {now}')
PY
curl -s -m 30 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l04_rl.txt
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
sleep 3

echo "  --- 查询：user_id 标签应该消失了 ---"
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]=l04_relabel_test' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条：".format(len(d)))
for m in d: print("      ", m)
'
echo "  --- 关键：20 个不同 user_id 被 drop 后应合并为 1 条 ---"
curl -s -m 15 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]=l04_rl_card' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条（若 labeldrop 生效，20 个 user_id 合并为 1 条）：".format(len(d)))
for m in d: print("      ", m)
'

echo
echo "########## 4. 实测 B：流式聚合输出 ##########"
echo "  配置: l04_highcard → without user_id → sum_samples (1m)"
echo "  预期输出指标名: l04_highcard:1m_without_user_id_sum_samples"
echo
echo "  --- 先写入一批 highcard 数据触发聚合 ---"
python3 - "$NOW" <<'PY' > /tmp/l04_sa.txt
import sys
now=int(sys.argv[1])
for i in range(100):
    print(f'l04_highcard{{user_id="sa{i}",endpoint="/api/order"}} {i} {now}')
PY
curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l04_sa.txt
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
echo "  等待 1 分钟聚合窗口 flush..."
sleep 65
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
sleep 2

echo "  --- 查询聚合输出 ---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l04_highcard:.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    聚合输出 {} 条：".format(len(d)))
for m in d[:6]: print("      ", m)
'
echo "  --- 聚合输出的值 ---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"l04_highcard:.*"}' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "########## 5. 对比：聚合前 vs 聚合后 ##########"
echo "  --- l04_highcard 原始序列数（按 endpoint）---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count(l04_highcard) by (endpoint)' \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,4p'
echo "  --- 流式聚合后的序列数 ---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"l04_highcard:.*"})' \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,4p'
