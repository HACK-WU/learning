#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground

echo "=== 1. 队列真实状态（完整行）==="
curl -s http://localhost:8429/metrics 2>/dev/null | grep "pending_data_bytes" | grep -v "^#"
echo "  --- 队列目录明细 ---"
docker exec vmagent-learn sh -c "ls -la /vmagent-remotewrite-data/persistent-queue/1_C3AA545DE75AD94A/ 2>/dev/null | head -15"
echo "  --- 目录数 ---"
docker exec vmagent-learn sh -c "ls /vmagent-remotewrite-data/persistent-queue/1_C3AA545DE75AD94A/ 2>/dev/null | wc -l"

echo
echo "=== 2. 重新验证 MetricsQL 在记录规则中可用 ==="
cat > $P/rules/mql-test.yml <<'EOF'
groups:
  - name: l11-mql
    interval: 10s
    rules:
      - record: l11:mql:topk
        expr: topk_avg(1, sum by (job) (up), job)
      - record: l11:mql:lagtest
        expr: lag(up[job="vmsingle"])
EOF
echo "  规则文件已写入 rules/mql-test.yml（宿主机挂载，无需 cp）"
curl -s -X POST http://localhost:8880/-/reload >/dev/null 2>&1
echo "  reload 执行，等待 30 秒..."
sleep 30

curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    print('  组 [%s]' % g['name'])
    for r in g['rules']:
        err=r.get('lastError','')
        print('     %-24s type=%-9s err=%s' % (r.get('name'), r.get('type'), err[:70] if err else '(无)'))
" 2>/dev/null

echo
echo "  --- MetricsQL 规则产物 ---"
for m in "l11:mql:topk" "l11:mql:lagtest"; do
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     $m : (无数据)')
for r in rs: print('     $m : %s = %s' % (r['metric'], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 3. 对照：PromQL 不支持的写法在 Prometheus 里是什么表现 ==="
echo "  (用 prom-learn 验证 topk_avg 是否为 PromQL 非法函数)"
echo "  prom-learn 容器: $(docker ps --filter name=prom-learn --format '{{.Status}}' 2>/dev/null)"
docker exec prom-learn sh -c "which promtool && echo 'query=topk_avg(1, sum by (job) (up), job)' | promtool check query /dev/stdin 2>&1 | head -5" 2>/dev/null | sed 's/^/  /'

echo
echo "=== 4. 记录规则开销：构造高基数聚合做公平对比 ==="
echo "  --- 复杂查询：多序列聚合 + 函数嵌套（各 5 次取中位数）---"
for m in "sum by(job)(rate(scrape_samples_scraped[5m]))" "job:scrape_samples:avg"; do
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$m")
  times=""
  for i in 1 2 3 4 5; do
    t=$(curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$enc" -w "%{time_total}" -o /dev/null 2>/dev/null)
    times="$times $t"
  done
  echo "     $m"
  echo "        5 次耗时:$times"
done

echo
echo "  --- 用 range query 放大差异（查 6 小时窗口）---"
END=$(date +%s); START=$((END-21600))
for m in "sum by(job)(up)" "job:up:sum"; do
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$m")
  times=""
  for i in 1 2 3; do
    t=$(curl -s "http://localhost:8481/select/0/prometheus/api/v1/query_range?query=$enc&start=$START&end=$END&step=60" -w "%{time_total}" -o /dev/null 2>/dev/null)
    times="$times $t"
  done
  echo "     $m"
  echo "        range 6h 耗时:$times"
done
