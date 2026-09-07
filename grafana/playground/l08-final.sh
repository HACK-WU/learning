#!/usr/bin/env bash
# 课 8 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana

echo "=========================================================="
echo " 课 8 交付前全量复验"
echo "=========================================================="

echo ""
echo "--- [1] 结构校验 ---"
bash playground/l08-verify.sh 2>&1 | tail -3

echo ""
echo "--- [2] 全仓链接可达性 ---"
bash playground/l03-linkcheck-all.sh 2>&1 | tail -5

echo ""
echo "--- [3] 档案一致性：四处都该说 24/36 与课 8 已完成 ---"
echo "  00-学习档案.md:"
grep -o '24 / 36 知识点' 00-学习档案.md | head -1 | sed 's/^/    /'
for k in 7.1 7.2 7.3 8.1 8.2 8.3; do
  line=$(grep "^| $k " 00-学习档案.md | head -1)
  case "$line" in
    *"✅ 已完成"*) echo "    $k ✅" ;;
    *) echo "    $k ✗ 未完成: $line" ;;
  esac
done
echo "  02-课程目录.md:"
grep -o '24 / 36 知识点' 02-课程目录.md | head -1 | sed 's/^/    /'
grep -n '| 8 |' 02-课程目录.md | head -2 | sed 's/^/    /'
echo "  01-学习路径总览.md:"
grep -o '24 / 36' 01-学习路径总览.md | head -1 | sed 's/^/    /'
echo "  00-评审清单.md:"
grep -c '\- \[x\] 阶段 3·课 8' 00-评审清单.md | sed 's/^/    课8已勾选: /'
echo "  stages/3-叫得醒/overview.md:"
grep -c '\- \[x\] .*lesson-08' stages/3-叫得醒/overview.md | sed 's/^/    课8已勾选: /'

echo ""
echo "--- [4] 剩余待编写（应只剩课 9-12）---"
grep -n '待编写' 02-课程目录.md | head -6 | sed 's/^/    /'

echo ""
echo "--- [5] 环境健康 ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'grafana-lab|grafana-prom|grafana-node|l08-webhook' | sed 's/^/  /'

echo ""
echo "--- [6] 告警状态残留（应全 0）---"
curl -s -u admin:admin http://localhost:3001/metrics 2>/dev/null \
  | grep '^grafana_alerting_alerts{' | sed 's/^/  /'

echo ""
echo "--- [7] 告警资源残留（应 0）---"
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/alert-rules \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  规则数：%d'%len(d))
for r in d: print('    残留：%s'%r.get('uid'))
"
echo -n "  contact point 数："
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/contact-points | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  mute timing 数："
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/mute-timings | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
echo -n "  策略树："
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/policies | python3 -c "import sys,json; d=json.load(sys.stdin); print('receiver=%s'%d.get('receiver'))"

echo ""
echo "--- [8] Prometheus targets（应 4 个全 up）---"
curl -s http://localhost:9201/api/v1/targets | python3 -c "
import sys,json
d=json.load(sys.stdin)
ts=d.get('data',{}).get('activeTargets') or []
up=sum(1 for t in ts if t.get('health')=='up')
print('  %d/%d up'%(up,len(ts)))
"

echo ""
echo "--- [9] 文件夹（l07alerts + l08alerts 保留供后续复用）---"
curl -s -u admin:admin "http://localhost:3001/api/folders?limit=30" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  文件夹数：%d'%len(d))
for f in d: print('    uid=%-14s title=%s'%(f.get('uid'),f.get('title')))
"

echo ""
echo "=========================================================="
echo " 复验完成"
echo "=========================================================="
