#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground

echo "=== 1. vmalert 的 -rule glob 是启动时展开还是每次 reload 重新扫描 ==="
echo "  容器内 /etc/vmalert 内容："
docker exec vmalert-learn sh -c "ls -la /etc/vmalert/" 2>/dev/null | sed 's/^/    /'

echo
echo "  当前 vmalert 加载的组："
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('    ', [g['name'] for g in d['data']['groups']])
" 2>/dev/null

echo
echo "  --- 再执行一次 reload 并等待 ---"
curl -s -X POST http://localhost:8880/-/reload >/dev/null 2>&1
sleep 12
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('    reload 后组:', [g['name'] for g in d['data']['groups']])
" 2>/dev/null

echo
echo "  --- 记录：reload 成功指标 ---"
curl -s http://localhost:8880/metrics 2>/dev/null | grep -E "^vmalert_config_last_reload_successful|^vmalert_config_last_reload_time" | grep -v "^#"

echo
echo "=== 2. 队列文件是否回收（pending=0 但文件 1.2MB）==="
echo "  当前 pending: $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{print $NF}')"
echo "  文件大小: $(docker exec vmagent-learn sh -c 'stat -c %s /vmagent-remotewrite-data/persistent-queue/1_C3AA545DE75AD94A/0000000000000000 2>/dev/null')"
echo "  metainfo.json 内容:"
docker exec vmagent-learn sh -c "cat /vmagent-remotewrite-data/persistent-queue/1_C3AA545DE75AD94A/metainfo.json 2>/dev/null" | sed 's/^/    /'
echo
echo "  --- 重启 vmagent 后文件是否还在（验证磁盘持久化的另一面）---"
docker restart vmagent-learn >/dev/null 2>&1
sleep 20
echo "    重启后 pending: $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{print $NF}')"
echo "    重启后文件大小: $(docker exec vmagent-learn sh -c 'stat -c %s /vmagent-remotewrite-data/persistent-queue/1_C3AA545DE75AD94A/0000000000000000 2>/dev/null')"
echo "    重启后 blocks_sent: $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_blocks_sent_total' | grep -v '^#' | awk '{print $NF}')"

echo
echo "=== 3. 验证 glob 展开：用通配符启动时新文件是否需要重启 ==="
echo "  结论验证：重启 vmalert 加载新规则文件"
docker restart vmalert-learn >/dev/null 2>&1
sleep 18
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('    重启后组:', [g['name'] for g in d['data']['groups']])
for g in d['data']['groups']:
    for r in g['rules']:
        err=r.get('lastError','')
        print('       %-24s err=%s' % (r.get('name'), err[:60] if err else '(无)'))
" 2>/dev/null
