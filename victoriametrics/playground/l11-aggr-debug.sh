#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 流式聚合为什么没产物 ==="
echo "  --- 配置 reload 成功，检查是否 match 到数据 ---"
curl -s http://localhost:8437/metrics 2>/dev/null | grep -E "^vmagent_streamaggr" | grep -v "^#" | sed 's/^/    /'

echo
echo "  --- 关键：vmagent 抓取的 up 是否真的进了流聚合管道 ---"
echo "  vmagent-aggr 的 targets:"
curl -s http://localhost:8437/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('     %-14s health=%-5s samples=%s' % (t['labels'].get('job'), t['health'], t.get('lastSamplesScraped')))
" 2>/dev/null

echo
echo "  --- 写入指标：确认数据确实在写 ---"
curl -s http://localhost:8437/metrics 2>/dev/null | grep -E "^vmagent_remotewrite_(blocks_sent_total|samples_total)" | grep -v "^#" | awk '{print "     " $1 " " $2}' | head -4

echo
echo "  --- 检查产物名：keep_metric_names=false 时的命名 ---"
echo "  官方文档：keep_metric_names=false -> 产物名为 <output>_<metric_name>"
echo "  实测查询多种命名："
for m in "up:sum_samples" "up:sum_samples_sum" "sum_samples:up" "sum_samples" "up_sum_samples" ":sum_samples"; do
  r=$(curl -s "http://localhost:8487/select/99/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print('有 %d 条' % len(rs)) if rs else print('无数据')
" 2>/dev/null)
  printf "     %-24s %s\n" "$m" "$r"
done

echo
echo "  --- 直接看 tenant 99 里有哪些指标 ---"
curl -s "http://localhost:8487/select/99/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=d['data']
print('     tenant 99 指标数 =', len(names))
for n in names[:20]: print('       ', n)
" 2>/dev/null

echo
echo "=== 2. 改用 keep_metric_names=true 重试 ==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__="up"}'
  interval: 30s
  outputs: [sum_samples, count_samples]
  keep_metric_names: true
EOF
docker restart vmagent-aggr >/dev/null 2>&1
sleep 45
echo "  --- 重启后 tenant 99 指标 ---"
curl -s "http://localhost:8487/select/99/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=d['data']
print('     指标数 =', len(names))
for n in names[:20]: print('       ', n)
" 2>/dev/null
echo "  --- 聚合产物值 ---"
for m in "up:sum_samples" "up:count_samples"; do
curl -s "http://localhost:8487/select/99/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
if not rs: print('     $m : 无数据')
for r in rs: print('     $m : %-40s = %s' % (str(r['metric'])[:38], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 3. vmagent 的 /api/v1/query 为何 400 ==="
echo "  vmagent /api/v1/query body: $(curl -s http://localhost:8429/api/v1/query?query=up 2>/dev/null | head -c 80)"
echo "  (vmagent 是采集器，不实现查询 API —— 这是与 Prometheus 的本质差异)"

echo
echo "=== 4. 清理 ==="
docker rm -f vmagent-aggr >/dev/null 2>&1
echo "  已清理临时容器"
