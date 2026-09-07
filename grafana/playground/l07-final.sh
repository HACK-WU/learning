#!/usr/bin/env bash
# 课 7 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana

echo "=========================================================="
echo " 课 7 交付前全量复验"
echo "=========================================================="

echo ""
echo "--- [1] 结构校验 ---"
bash playground/l07-verify.sh 2>&1 | tail -4

echo ""
echo "--- [2] 全仓链接可达性 ---"
bash playground/l03-linkcheck-all.sh 2>&1 | tail -5

echo ""
echo "--- [3] 档案一致性：四处都该说 21/36 与课 7 已完成 ---"
echo "  00-学习档案.md:"
grep -o '21 / 36 知识点' 00-学习档案.md | head -1 | sed 's/^/    /'
for k in 7.1 7.2 7.3; do
  line=$(grep "^| $k " 00-学习档案.md | head -1)
  case "$line" in
    *"✅ 已完成"*) echo "    $k ✅" ;;
    *) echo "    $k ✗ 未完成: $line" ;;
  esac
done
echo "  02-课程目录.md:"
grep -o '21 / 36 知识点' 02-课程目录.md | head -1 | sed 's/^/    /'
grep -c '| 7 | \[告警架构' 02-课程目录.md | sed 's/^/    课7链接: /'
echo "  01-学习路径总览.md:"
grep -o '21 / 36' 01-学习路径总览.md | head -1 | sed 's/^/    /'
echo "  00-评审清单.md:"
grep -c '\- \[x\] 阶段 3·课 7' 00-评审清单.md | sed 's/^/    课7已勾选: /'
echo "  stages/3-叫得醒/overview.md:"
grep -c '\- \[x\] .*lesson-07' stages/3-叫得醒/overview.md | sed 's/^/    课7已勾选: /'

echo ""
echo "--- [4] 阶段 3 概览的 No Data 表述是否已修正 ---"
grep -n 'No Data 与 Error 是独立配置' stages/3-叫得醒/overview.md | sed 's/^/    /'

echo ""
echo "--- [5] 剩余待编写（应只剩课 8-12）---"
grep -n '待编写' 02-课程目录.md | head -6 | sed 's/^/    /'

echo ""
echo "--- [6] 环境健康 ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'grafana-lab|grafana-prom|grafana-node' | sed 's/^/  /'

echo ""
echo "--- [7] 告警状态残留（应全 0）---"
curl -s -u admin:admin http://localhost:3001/metrics 2>/dev/null \
  | grep '^grafana_alerting_alerts{' | sed 's/^/  /'

echo ""
echo "--- [8] 告警规则残留（应 0 条）---"
curl -s -u admin:admin http://localhost:3001/api/v1/provisioning/alert-rules \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  规则数：%d'%len(d))
for r in d: print('    残留：%s'%r.get('uid'))
"

echo ""
echo "--- [9] 文件夹（l07alerts 应保留供课 8）---"
curl -s -u admin:admin "http://localhost:3001/api/folders?limit=20" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  文件夹数：%d'%len(d))
for f in d: print('    uid=%-12s title=%s'%(f.get('uid'),f.get('title')))
"

echo ""
echo "--- [10] pushgateway 残留（应 0）---"
curl -s http://localhost:9091/metrics | grep -c 'l07' | sed 's/^/  l07 指标残留: /'

echo ""
echo "=========================================================="
echo " 复验完成"
echo "=========================================================="
