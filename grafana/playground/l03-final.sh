#!/usr/bin/env bash
# 课 3 交付前全量复验
set -u
cd /mnt/d/projects/learning/grafana
FAIL=0

echo "=== 1. 课 3 结构与链接校验 ==="
if bash playground/l03-verify.sh >/tmp/l03v.log 2>&1; then
  echo "  ✅ 通过（$(grep -c '✅' /tmp/l03v.log) 项）"
else
  echo "  ❌ 未通过"; tail -20 /tmp/l03v.log; FAIL=$((FAIL+1))
fi

echo
echo "=== 2. 全仓链接可达性 ==="
if bash playground/l03-linkcheck-all.sh >/tmp/l03lc.log 2>&1; then
  echo "  ✅ $(head -1 /tmp/l03lc.log)"
else
  echo "  ❌ 存在死链"; cat /tmp/l03lc.log; FAIL=$((FAIL+1))
fi

echo
echo "=== 3. 四处档案回写核验 ==="
python3 - <<'PYEOF'
import io,sys
B='/mnt/d/projects/learning/grafana/'
fails=[]
def has(f,s,label):
    t=io.open(B+f,encoding='utf-8').read()
    print(('  ✅ ' if s in t else '  ❌ ')+label)
    if s not in t: fails.append(label)

has('00-学习档案.md','| 3.3 | Row 与折叠、面板复用与 JSON Model 初见 | 课 3 | ✅ 已完成 |','档案①进度表 3.1-3.3 已勾选')
has('00-学习档案.md','**进度统计**：9 / 36 知识点','档案①进度统计 9/36')
has('00-学习档案.md','课 3《变量与 Dashboard 组织》','档案②评审记录已追加')
has('00-学习档案.md','阶段 1 课 3 已交付（9/36 知识点','档案③断点信息已更新')
has('00-学习档案.md','`grafana-node2`(9102,hostname=node-alpha)','档案④环境资产已更新')
has('00-评审清单.md','- [x] 阶段 1·课 3《变量与 Dashboard 组织','评审清单已勾选')
has('00-评审清单.md','| 2026-09-04 | 课 3《变量与 Dashboard 组织》','评审清单记录已追加')
has('01-学习路径总览.md','**总进度**：9 / 36 知识点','路径总览进度已更新')
has('02-课程目录.md','9 / 36 知识点（阶段 1：9/9 已完成）','课程目录进度已更新')
has('02-课程目录.md','[变量与 Dashboard 组织：一张图服务 N 台机器](stages/1-看得见/lessons/','课程目录课 3 已加链接')
has('stages/1-看得见/overview.md','- [x] `lessons/lesson-03-变量与Dashboard组织','阶段概览产出已勾选')
has('stages/1-看得见/overview.md','resource` 表','阶段概览存储层变化已记')
sys.exit(1 if fails else 0)
PYEOF
[ $? -ne 0 ] && FAIL=$((FAIL+1))

echo
echo "=== 4. .gitignore 规则准确性 ==="
cd /mnt/d/projects/learning
if bash grafana/playground/l03-ignore-verify.sh >/tmp/l03ig.log 2>&1; then
  echo "  ✅ $(grep '🎉' /tmp/l03ig.log | head -1)"
else
  echo "  ❌ 规则有误伤"; tail -15 /tmp/l03ig.log; FAIL=$((FAIL+1))
fi

echo
echo "=== 5. 环境最终状态 ==="
docker ps --filter name=grafana --format '  {{.Names}} | {{.Status}}' 2>/dev/null | head -8
curl -s http://localhost:3001/api/health | tr -d ' \n' | head -c 60; echo

echo
echo "=========== 汇总 ==========="
if [ "$FAIL" -eq 0 ]; then echo "  🎉 课 3 交付复验全部通过"; else echo "  ⚠️ $FAIL 组未通过"; fi
exit $FAIL
