#!/bin/bash
echo "=== vmagent 自身暴露的指标名（含 remotewrite）==="
curl -s http://localhost:8429/metrics 2>/dev/null | grep -E "^vmagent_remotewrite|^vmagent_persistentqueue" | awk '{print "  " $1}' | sort -u | head -40

echo
echo "=== 关键指标的当前值 ==="
curl -s http://localhost:8429/metrics 2>/dev/null | grep -E "vmagent_remotewrite_(samples|packets|retries|pending)|vmagent_persistentqueue" | grep -v "^#" | head -25

echo
echo "=== 队列目录结构 ==="
docker exec vmagent-learn sh -c "find /vmagent-remotewrite-data -type f 2>/dev/null | head -20; echo '--- 目录大小 ---'; du -sh /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null"

echo
echo "=== 数据是否真的写到了后端 ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    rs=d['data']['result']
    print('  查到 up 序列条数:', len(rs))
    for r in rs[:6]:
        m=r['metric']
        print('     job=%-16s instance=%-20s = %s' % (m.get('job'), m.get('instance'), r['value'][1]))
except Exception as e:
    print('  解析失败:', e)
"
