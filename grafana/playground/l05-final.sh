#!/usr/bin/env bash
# 课 5 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana

echo "=========================================================="
echo " 课 5 交付前全量复验"
echo "=========================================================="

echo ""
echo "--- [1] 结构校验 ---"
bash playground/l05-verify.sh 2>&1 | tail -6

echo ""
echo "--- [2] 全仓链接可达性 ---"
bash playground/l03-linkcheck-all.sh 2>&1 | tail -6

echo ""
echo "--- [3] 档案一致性：四处都该说 15/36 与课 5 已完成 ---"
echo "  00-学习档案.md:"
grep -o '15 / 36 知识点' 00-学习档案.md | head -1 | sed 's/^/    /'
grep -c '| 5\.1 |.*✅ 已完成' 00-学习档案.md | sed 's/^/    进度表 5.1 已完成: /'
echo "  02-课程目录.md:"
grep -o '15 / 36 知识点' 02-课程目录.md | head -1 | sed 's/^/    /'
grep -c '| 5 | \[Transformations' 02-课程目录.md | sed 's/^/    课5链接数: /'
echo "  01-学习路径总览.md:"
grep -o '15 / 36' 01-学习路径总览.md | head -1 | sed 's/^/    /'
echo "  00-评审清单.md:"
grep -c '\- \[x\] 阶段 2·课 5' 00-评审清单.md | sed 's/^/    课5已勾选: /'
echo "  stages/2-查得到/overview.md:"
grep -c '\- \[x\] .*lesson-05' stages/2-查得到/overview.md | sed 's/^/    课5已勾选: /'

echo ""
echo "--- [4] 是否有残留的「待编写」课 5 ---"
n=$(grep -c '课 5.*待编写\|lesson-05.*待编写' 02-课程目录.md 2>/dev/null)
echo "  残留条数：$n"
[ "$n" -eq 0 ] && echo "  ✓ 无残留" || echo "  ✗ 有残留"

echo ""
echo "--- [5] 环境健康 ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""
docker ps --format '{{.Names}} {{.Status}}' | grep grafana | sed 's/^/  /'

echo ""
echo "--- [6] 数据源（应为 1 个，无临时残留）---"
curl -s -u admin:admin http://localhost:3001/api/datasources \
  | python3 -c "
import sys,json
ds=json.load(sys.stdin)
print('  数据源数：%d'%len(ds))
for d in ds: print('    %-12s %s'%(d['name'],d['url']))
"

echo ""
echo "--- [7] 临时容器残留检查 ---"
docker ps -a --format '{{.Names}}' | grep -E 'l05|sniff|probe' | sed 's/^/  /' || echo "  ✓ 无残留"

echo ""
echo "=========================================================="
echo " 复验完成"
echo "=========================================================="
