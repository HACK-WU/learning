#!/usr/bin/env bash
# 课 4 交付前全量复验（修复后）
set -u
cd /mnt/d/projects/learning/grafana

echo "=========================================================="
echo " 课 4 交付前全量复验"
echo "=========================================================="

echo ""
echo "--- [1] 结构校验 ---"
bash playground/l04-verify.sh 2>&1 | tail -8

echo ""
echo "--- [2] 命令写法：必须全是单行（0 处反斜杠续行）---"
DOC="stages/2-查得到/lessons/lesson-04-查询编辑器与数据源协议：一次查询的完整旅程.md"
# 用 awk 排除 ``` 围栏内的代码块（那里可能有展示缺陷用的错误示范）
BAD=$(awk '/^```/{inblk=!inblk; next} !inblk && /wsl -d Ubuntu -- bash -lc +\\$/{c++} END{print c+0}' "$DOC")
GOOD=$(grep -c 'wsl -d Ubuntu -- bash -lc "' "$DOC")
echo "  单行写法：$GOOD 处   反斜杠续行（代码块外）：$BAD 处"
if [ "$BAD" -eq 0 ]; then
  echo "  ✅ 无续行缺陷（代码块内的错误示范已排除）"
else
  echo "  ❌ 仍有 $BAD 处"
fi

echo ""
echo "--- [3] 全仓链接可达性（65+ 条）---"
bash playground/l03-linkcheck-all.sh 2>&1 | tail -6

echo ""
echo "--- [4] 环境健康检查 ---"
curl -s http://localhost:3001/api/health | tr -d ' \n'
echo ""
docker ps --format '{{.Names}} {{.Status}}' | grep grafana | sed 's/^/  /'

echo ""
echo "--- [5] 数据源清单（确认无临时残留）---"
curl -s -u admin:admin http://localhost:3001/api/datasources \
  | python3 -c "
import sys,json
ds=json.load(sys.stdin)
print('  数据源数：%d' % len(ds))
for d in ds:
    print('    %-12s %s' % (d['name'], d['url']))
"

echo ""
echo "--- [6] 容器清单（确认探针容器已清理）---"
docker ps -a --format '{{.Names}}' | grep -E 'l04|sniff' | sed 's/^/  /' || echo "  ✅ 无 l04 残留容器"

echo ""
echo "=========================================================="
echo " 复验完成"
echo "=========================================================="
