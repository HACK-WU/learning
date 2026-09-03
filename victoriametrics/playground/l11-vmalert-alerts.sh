#!/bin/bash
echo "=== 1. 规则实际状态（用 vmalert 的 /api/v1/rules 原始输出）==="
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    for r in g['rules']:
        name = r.get('name','')
        typ  = r.get('type','')
        print('  [%s] %-30s type=%-8s state=%-10s lastExec=%s' % (
            g['name'], name, typ, r.get('state','-'), str(r.get('lastEvaluation',''))[:19]))
" 2>/dev/null

echo
echo "=== 2. 记录规则是否写入了后端 ==="
echo "  --- job:up:sum（记录规则产物）---"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:up:sum" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     (尚无数据)')
for r in rs: print('     job=%-14s = %s' % (r['metric'].get('job'), r['value'][1]))
" 2>/dev/null

echo "  --- job:scrape_samples:avg ---"
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:scrape_samples:avg" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     (尚无数据)')
for r in rs: print('     job=%-14s = %s' % (r['metric'].get('job'), r['value'][1]))
" 2>/dev/null

echo
echo "=== 3. 记录规则的开销对比：原始查询 vs 预计算 ==="
echo "  --- 直接查 sum by(job)(up) ---"
for i in 1 2 3; do
  curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=sum%20by(job)(up)" \
    -w "     耗时=%{time_total}s\n" -o /dev/null 2>/dev/null
done
echo "  --- 查记录规则产物 job:up:sum ---"
for i in 1 2 3; do
  curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:up:sum" \
    -w "     耗时=%{time_total}s\n" -o /dev/null 2>/dev/null
done

echo
echo "=== 4. 触发告警：停掉一个被抓取的目标 ==="
echo "  当前 up 状态："
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d['data']['result']:
    print('     job=%-14s instance=%-22s up=%s' % (r['metric'].get('job'), r['metric'].get('instance'), r['value'][1]))
" 2>/dev/null

echo "  停止 vmselect-learn（它是 vmagent 的抓取目标之一）..."
docker stop vmselect-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STOPPED，等待告警触发（for:10s + 求值 5s）"
sleep 30

echo
echo "=== 5. 告警是否 FIRING ==="
curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
alerts=d['data']['alerts']
print('  活跃告警数:', len(alerts))
for a in alerts:
    print('     %-24s state=%-8s severity=%s' % (a.get('name'), a.get('state'), a['labels'].get('severity')))
    print('        value=%s  activeAt=%s' % (a.get('value'), str(a.get('activeAt',''))[:19]))
    print('        summary=%s' % a.get('annotations',{}).get('summary'))
" 2>/dev/null

echo
echo "=== 6. Alertmanager 是否收到 ==="
curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  Alertmanager 收到的告警数:', len(d))
for a in d[:5]:
    lbl=a.get('labels',{})
    print('     %-24s severity=%-9s job=%s' % (lbl.get('alertname'), lbl.get('severity'), lbl.get('job')))
" 2>/dev/null

echo
echo "=== 7. 恢复目标，观察告警 RESOLVED ==="
docker start vmselect-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STARTED"
sleep 25
curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  恢复后活跃告警数:', len(d['data']['alerts']))
" 2>/dev/null
