#!/usr/bin/env bash
# 课 6 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana

echo "=========================================================="
echo " 课 6 交付前全量复验"
echo "=========================================================="

echo ""
echo "--- [1] 结构校验 ---"
bash playground/l06-verify.sh 2>&1 | tail -6

echo ""
echo "--- [2] 全仓链接可达性 ---"
bash playground/l03-linkcheck-all.sh 2>&1 | tail -6

echo ""
echo "--- [3] 档案一致性：四处都该说 18/36 与课 6 已完成 ---"
echo "  00-学习档案.md:"
grep -o '18 / 36 知识点' 00-学习档案.md | head -1 | sed 's/^/    /'
for k in 6.1 6.2 6.3; do
  line=$(grep "^| $k " 00-学习档案.md | head -1)
  case "$line" in
    *"✅ 已完成"*) echo "    $k ✅" ;;
    *) echo "    $k ✗ 未完成: $line" ;;
  esac
done
echo "  02-课程目录.md:"
grep -o '18 / 36 知识点' 02-课程目录.md | head -1 | sed 's/^/    /'
grep -c '| 6 | \[变量进阶与动态仪表盘\]' 02-课程目录.md | sed 's/^/    课6链接: /'
echo "  01-学习路径总览.md:"
grep -o '18 / 36' 01-学习路径总览.md | head -1 | sed 's/^/    /'
echo "  00-评审清单.md:"
grep -c '\- \[x\] 阶段 2·课 6' 00-评审清单.md | sed 's/^/    课6已勾选: /'
echo "  stages/2-查得到/overview.md:"
grep -c '\- \[x\] .*lesson-06' stages/2-查得到/overview.md | sed 's/^/    课6已勾选: /'

echo ""
echo "--- [4] 是否有残留的「待编写」（课 6 应无，课 7+ 可有）---"
grep -n '待编写' 02-课程目录.md | head -6 | sed 's/^/    /'

echo ""
echo "--- [5] 阶段 2 是否全部完成（应 9/9）---"
n=$(grep -c '| 课 6 | ✅ 已完成' 00-学习档案.md)
echo "  课 6 已完成行数：$n（应为 3）"

echo ""
echo "--- [6] 环境健康 ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'grafana-lab|grafana-prom|grafana-node' | sed 's/^/  /'

echo ""
echo "--- [7] 数据源（应为 1 个，无临时残留）---"
curl -s -u admin:admin http://localhost:3001/api/datasources \
  | python3 -c "
import sys,json
ds=json.load(sys.stdin)
print('  数据源数：%d'%len(ds))
for d in ds: print('    %-12s %s'%(d['name'],d['url']))
"

echo ""
echo "--- [8] 临时 dashboard 残留检查 ---"
for uid in l06-var-probe l06-repeat-probe l05-tf-probe l05-tf2-probe; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin "http://localhost:3001/api/dashboards/uid/$uid")
  echo "  $uid → HTTP $code"
done

echo ""
echo "--- [9] 临时容器残留（本课相关）---"
docker ps -a --format '{{.Names}}' | grep -E 'l06|sniff' | sed 's/^/  /' || true
echo "  （l11-e3-probe 属其他课程，忽略）"

echo ""
echo "=========================================================="
echo " 复验完成"
echo "=========================================================="
