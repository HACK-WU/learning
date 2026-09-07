#!/bin/bash
D=/mnt/d/projects/learning/grafana
echo "=== 全量相对链接可达性（含两个索引 + 各阶段 overview）==="
python3 - <<'PYEOF'
import re,os
root="/mnt/d/projects/learning/grafana"
files=[]
for dp,dn,fn in os.walk(root):
    if '.git' in dp: continue
    for f in fn:
        if f.endswith('.md'): files.append(os.path.join(dp,f))
tot=0; bad=0
for fp in sorted(files):
    txt=open(fp,encoding='utf-8').read()
    links=re.findall(r'\[([^\]]*)\]\((\.\.?[^):]+)\)',txt)
    for name,link in links:
        tot+=1
        p=os.path.normpath(os.path.join(os.path.dirname(fp),link))
        if not os.path.exists(p):
            bad+=1
            print(f"  ❌ {os.path.relpath(fp,root)}: [{name}] -> {link}")
print(f"  检查链接 {tot} 条，死链 {bad} 条")
PYEOF
echo

echo "=== 四处档案回写确认 ==="
grep -c "课 12\|lesson-12" "$D/02-课程目录.md" | xargs echo "  02-课程目录.md 命中数:"
grep -n "lesson-12" "$D/02-课程目录.md" | head -2
echo "  ---"
grep -n "✅ 已完成" "$D/00-学习档案.md" | tail -3
echo "  ---"
grep -n "lesson-12" "$D/stages/4-管得住/overview.md"
echo "  ---"
grep -n "课 12" "$D/00-评审清单.md" | head -3
echo "  ---"
grep -n "总进度\|阶段 4：管得住" "$D/01-学习路径总览.md" | head -4
echo

echo "=== 课 12 文件最终大小 ==="
wc -l -c "$D/stages/4-管得住/lessons/lesson-12-性能、高可用与升级运维.md"
