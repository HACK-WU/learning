#!/bin/bash
echo "=== A. vmagent 抓取目标状态 ==="
curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('  %-14s %-24s health=%-5s samples=%-7s err=%s' % (
        t['labels'].get('job'), t['labels'].get('instance'),
        t['health'], t.get('lastSamplesScraped'), t.get('lastError','')[:45]))
" 2>/dev/null

echo
echo "=== B. vmagent 队列与写入指标 ==="
curl -s http://localhost:8429/metrics 2>/dev/null | grep -E "^vmagent_remotewrite_(blocks_sent_total|bytes_sent_total|samples_total|pending_data_bytes|retries_count_total|samples_dropped_total|packets_dropped_total)" | grep -v "^#" | awk '{printf "  %-52s %s\n", $1, $2}' | sort -u | head -20

echo
echo "=== C. 队列目录 ==="
docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{printf \"  dir=%s  %s bytes\n\", \$2, \$1}'; ls /vmagent-remotewrite-data/ 2>/dev/null | sed 's/^/  item: /'"

echo
echo "=== D. vmalert 规则状态 ==="
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    print('  组 [%s] file=%s interval=%ss' % (g['name'], g.get('file','').split('/')[-1], g.get('interval')))
    for r in g['rules']:
        err=r.get('lastError','')
        print('     %-28s type=%-9s state=%-9s samples=%-6s err=%s' % (
            r.get('name'), r.get('type'), r.get('state','-'),
            r.get('lastEvaluationSamples','-'), err[:50] if err else ''))
" 2>/dev/null

echo
echo "=== E. vmalert 关键指标 ==="
curl -s http://localhost:8880/metrics 2>/dev/null | grep -E "^vmalert_(alerts_fired_total|alerts_sent_total|config_last_reload_successful|iteration_duration|rules_total|execution_errors_total)" | grep -v "^#" | head -12

echo
echo "=== F. 记录规则产物 ==="
for m in "job:up:sum" "job:scrape_samples:avg" "l11:mql:test"; do
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('  %-24s (无数据)' % '$m')
for r in rs: print('  %-24s job=%-14s = %s' % ('$m', r['metric'].get('job'), r['value'][1]))
" 2>/dev/null
done

echo
echo "=== G. 告警当前状态 ==="
echo "  vmalert alerts: $(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["alerts"]))' 2>/dev/null)"
echo "  Alertmanager  : $(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null)"

echo
echo "=== H. 记录规则开销对比（各 3 次）==="
echo "  --- 原始 sum by(job)(up) ---"
for i in 1 2 3; do curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=sum%20by(job)(up)" -w "     %{time_total}s\n" -o /dev/null 2>/dev/null; done
echo "  --- 记录规则 job:up:sum ---"
for i in 1 2 3; do curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:up:sum" -w "     %{time_total}s\n" -o /dev/null 2>/dev/null; done
